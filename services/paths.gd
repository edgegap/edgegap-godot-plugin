extends RefCounted
class_name EdgegapPaths

## Resolves the addon root no matter where the plugin is installed under res://.
static func addon_root() -> String:
	var script := preload("paths.gd") as Script
	# .../addons/edgegap/services/paths.gd -> .../addons/edgegap
	return script.resource_path.get_base_dir().get_base_dir()

static func dockerfile_res_path() -> String:
	return addon_root().path_join("defaults/Dockerfile")
