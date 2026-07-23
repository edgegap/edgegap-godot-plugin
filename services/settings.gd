extends RefCounted
class_name EdgegapSettings

const EdgegapConstants = preload("../constants.gd")
const EdgegapPaths = preload("paths.gd")

static func _editor_settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()

static func ensure_defaults() -> void:
	var es := _editor_settings()
	_ensure_setting(es, EdgegapConstants.SETTINGS_TOKEN, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_TOKEN_VERIFIED, false)
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_URL, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_PROJECT, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_USERNAME, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_TOKEN, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_LOCAL_CONTAINERS, PackedStringArray())

static func _ensure_setting(es: EditorSettings, key: String, default_value: Variant) -> void:
	if not es.has_setting(key):
		es.set_setting(key, default_value)
	es.set_initial_value(key, default_value, false)

static func get_token() -> String:
	return str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_TOKEN))

static func set_token(token: String) -> void:
	var es := _editor_settings()
	es.set_setting(EdgegapConstants.SETTINGS_TOKEN, token)
	es.set_setting(EdgegapConstants.SETTINGS_TOKEN_VERIFIED, not token.is_empty())
	es.save()

static func clear_token() -> void:
	set_token("")
	clear_registry_credentials()

static func is_token_verified() -> bool:
	return bool(_editor_settings().get_setting(EdgegapConstants.SETTINGS_TOKEN_VERIFIED)) \
		and not get_token().is_empty()

static func set_registry_credentials(credentials: Dictionary) -> void:
	var es := _editor_settings()
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_URL, str(credentials.get("registry_url", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_PROJECT, str(credentials.get("project", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_USERNAME, str(credentials.get("username", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_TOKEN, str(credentials.get("token", "")))
	es.save()

static func clear_registry_credentials() -> void:
	set_registry_credentials({})

static func get_registry_credentials() -> Dictionary:
	return {
		"registry_url": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_URL)),
		"project": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_PROJECT)),
		"username": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_USERNAME)),
		"token": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_TOKEN)),
	}

static func has_registry_credentials() -> bool:
	var creds := get_registry_credentials()
	return not str(creds.registry_url).is_empty() and not str(creds.username).is_empty()

static func get_local_containers() -> PackedStringArray:
	var value = _editor_settings().get_setting(EdgegapConstants.SETTINGS_LOCAL_CONTAINERS)
	if value is PackedStringArray:
		return value
	return PackedStringArray()

static func set_local_containers(ids: PackedStringArray) -> void:
	var es := _editor_settings()
	es.set_setting(EdgegapConstants.SETTINGS_LOCAL_CONTAINERS, ids)
	es.save()

static func add_local_container(container_id: String) -> void:
	var ids := get_local_containers()
	if container_id.is_empty() or container_id in ids:
		return
	ids.append(container_id)
	set_local_containers(ids)

static func default_image_name() -> String:
	var name := String(ProjectSettings.get_setting("application/config/name", "godot-server"))
	name = name.strip_edges().to_lower().replace(" ", "-")
	if name.is_empty():
		return "godot-server"
	return name

static func default_dockerfile_path() -> String:
	return ProjectSettings.globalize_path(EdgegapPaths.dockerfile_res_path())

static func default_docker_run_params() -> String:
	return "-p %d:%d/udp" % [EdgegapConstants.DEFAULT_SERVER_PORT, EdgegapConstants.DEFAULT_SERVER_PORT]

static func unity_style_timestamp_tag() -> String:
	var utc := Time.get_datetime_dict_from_system(true)
	return "%02d.%02d.%02d-%02d.%02d.%02d-UTC" % [
		utc.year % 100, utc.month, utc.day, utc.hour, utc.minute, utc.second
	]
