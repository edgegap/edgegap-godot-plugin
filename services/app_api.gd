extends RefCounted
class_name EdgegapAppApi

## Applications list for the upload UI dropdown (Unity GetApps).
## App creation is left to the Edgegap dashboard version-create flow.

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")

signal get_apps_completed(ok: bool, response_code: int, app_names: PackedStringArray, body: String)

var _http: HTTPRequest
var _authorization := ""
var _pending := false

func bind_http(http: HTTPRequest) -> void:
	if _http and _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.disconnect(_on_request_completed)
	_http = http
	if not _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.connect(_on_request_completed)

func set_authorization(token: String) -> void:
	_authorization = token

func get_apps() -> Error:
	if _http == null:
		EdgegapLogger.error("App API: HTTPRequest not bound.")
		return ERR_UNCONFIGURED
	# Avoid "HTTPRequest is processing a request" when refresh overlaps dropdown.
	if _pending or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
		_pending = false
	_pending = true
	EdgegapLogger.info("App API: GET v1/apps")
	return _request(HTTPClient.METHOD_GET, "%s/v1/apps" % EdgegapConstants.API_BASE)

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: %s" % _authorization,
		"Accept: application/json",
	])

func _request(method: int, url: String) -> Error:
	if _http == null:
		EdgegapLogger.error("App API: HTTPRequest not bound.")
		return ERR_UNCONFIGURED
	if _authorization.is_empty():
		EdgegapLogger.error("App API: authorization token is empty.")
		return ERR_INVALID_PARAMETER
	var err := _http.request(url, _auth_headers(), method, "")
	if err != OK:
		EdgegapLogger.error("App API request failed to start: %s" % error_string(err))
		_pending = false
	return err

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _pending:
		return
	_pending = false
	var text := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		EdgegapLogger.error("App API HTTP transport error: result=%d" % result)
		get_apps_completed.emit(false, response_code, PackedStringArray(), text)
		return

	var ok := response_code >= 200 and response_code < 300
	var names: PackedStringArray = []
	if ok:
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			var apps: Variant = parsed.get("applications", [])
			if typeof(apps) == TYPE_ARRAY:
				for app in apps:
					if typeof(app) == TYPE_DICTIONARY:
						var name := str(app.get("name", "")).strip_edges()
						if not name.is_empty():
							names.append(name)
		else:
			ok = false
	if ok:
		EdgegapLogger.info("Loaded %d Edgegap application(s)." % names.size())
	else:
		EdgegapLogger.error("Get apps failed: HTTP %d %s" % [response_code, text])
	get_apps_completed.emit(ok, response_code, names, text)
