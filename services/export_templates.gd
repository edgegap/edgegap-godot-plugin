extends RefCounted
class_name EdgegapExportTemplates

const EdgegapLogger = preload("logger.gd")

const LINUX_DEBUG := "linux_debug.x86_64"
const LINUX_RELEASE := "linux_release.x86_64"

func _version_base() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d.%s" % [v.major, v.minor, v.patch, v.status]

func _is_dotnet_editor() -> bool:
	return OS.has_feature("mono") or OS.has_feature("dotnet")

func templates_root() -> String:
	return EditorInterface.get_editor_paths().get_data_dir().path_join("export_templates")

## Ordered candidates. Prefer an existing folder that already has Linux templates.
func version_candidates() -> PackedStringArray:
	var base := _version_base()
	var out: PackedStringArray = []
	if _is_dotnet_editor():
		out.append(base + ".mono")
	out.append(base)
	# Always consider the mono folder too — editor feature tags can be unreliable.
	var mono := base + ".mono"
	if out.find(mono) < 0:
		out.append(mono)
	return out

func resolved_version() -> String:
	var root := templates_root()
	var fallback := version_candidates()[0]
	for version in version_candidates():
		var dir := root.path_join(version)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		fallback = version
		if FileAccess.file_exists(dir.path_join(LINUX_DEBUG)) \
			and FileAccess.file_exists(dir.path_join(LINUX_RELEASE)):
			return version
	return fallback

func templates_dir() -> String:
	return templates_root().path_join(resolved_version())

func has_linux_debug() -> bool:
	return FileAccess.file_exists(templates_dir().path_join(LINUX_DEBUG))

func has_linux_release() -> bool:
	return FileAccess.file_exists(templates_dir().path_join(LINUX_RELEASE))

func is_installed() -> bool:
	return has_linux_debug() and has_linux_release()

func status_message() -> String:
	var version := resolved_version()
	var dir := templates_dir()
	if is_installed():
		return "Linux debug & release templates found (%s)." % version
	var missing: PackedStringArray = []
	if not has_linux_debug():
		missing.append("debug")
	if not has_linux_release():
		missing.append("release")
	return "Missing Linux %s templates for %s\nLooking in: %s" % [
		" & ".join(missing), version, dir
	]

func download_url() -> String:
	var v := Engine.get_version_info()
	var tag := "%d.%d.%d-%s" % [v.major, v.minor, v.patch, v.status]
	var file_version := "%d.%d.%d-%s" % [v.major, v.minor, v.patch, v.status]
	# Match the folder we will install into (mono vs standard).
	var use_mono := resolved_version().ends_with(".mono") or _is_dotnet_editor()
	if use_mono:
		return "https://github.com/godotengine/godot-builds/releases/download/%s/Godot_v%s_mono_export_templates.tpz" % [tag, file_version]
	return "https://github.com/godotengine/godot-builds/releases/download/%s/Godot_v%s_export_templates.tpz" % [tag, file_version]

func cache_tpz_path() -> String:
	var cache_dir := OS.get_cache_dir().path_join("edgegap-godot")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	return cache_dir.path_join("export_templates.tpz")

## Downloads to disk (not memory). Call with a dedicated HTTPRequest.
func begin_download(http: HTTPRequest) -> Error:
	var url := download_url()
	var path := cache_tpz_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	http.download_file = path
	# Large archive; don't abort mid-download.
	http.timeout = 0
	http.use_threads = true

	EdgegapLogger.info("Downloading export templates from %s" % url)
	EdgegapLogger.info("Saving to %s" % path)
	var err := http.request(url)
	if err != OK:
		EdgegapLogger.error("Template download request failed: %s" % error_string(err))
		http.download_file = ""
	return err

func install_from_cache() -> Error:
	var tpz_path := cache_tpz_path()
	if not FileAccess.file_exists(tpz_path):
		EdgegapLogger.error("Template archive missing at %s" % tpz_path)
		return ERR_FILE_NOT_FOUND

	var target := templates_root().path_join(resolved_version())
	# If nothing exists yet, install into the preferred candidate.
	if not DirAccess.dir_exists_absolute(target):
		var preferred := version_candidates()[0]
		target = templates_root().path_join(preferred)
	DirAccess.make_dir_recursive_absolute(target)

	var zip := ZIPReader.new()
	var zerr := zip.open(tpz_path)
	if zerr != OK:
		EdgegapLogger.error("Failed to open template archive: %s" % error_string(zerr))
		return zerr

	var written := 0
	for path in zip.get_files():
		var relative := path
		if relative.begins_with("templates/"):
			relative = relative.substr("templates/".length())
		if relative.is_empty() or relative.ends_with("/"):
			continue
		var out_path := target.path_join(relative.get_file())
		var data := zip.read_file(path)
		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			EdgegapLogger.error("Cannot write %s" % out_path)
			zip.close()
			return ERR_CANT_CREATE
		out.store_buffer(data)
		out.close()
		written += 1
	zip.close()

	EdgegapLogger.info("Extracted %d template files to %s" % [written, target])

	if not (
		FileAccess.file_exists(target.path_join(LINUX_DEBUG))
		and FileAccess.file_exists(target.path_join(LINUX_RELEASE))
	):
		EdgegapLogger.error("Linux debug/release binaries still missing in %s" % target)
		return ERR_FILE_NOT_FOUND

	EdgegapLogger.info("Export templates installed to %s" % target)
	return OK
