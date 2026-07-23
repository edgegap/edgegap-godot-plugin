extends RefCounted
class_name EdgegapDocker

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")
const EdgegapSettings = preload("settings.gd")
const EdgegapProcess = preload("process_runner.gd")

const DOCKER_CMD := "docker"

func is_available() -> bool:
	var runner = EdgegapProcess.new()
	var code: int = runner.run(DOCKER_CMD, PackedStringArray(["info"]))
	return code == 0

func open_install_page() -> void:
	OS.shell_open(EdgegapConstants.DOCKER_INSTALL_URL)

func build_image(dockerfile_path: String, server_build_path: String, image_name: String, image_tag: String) -> Error:
	var project_root := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"build",
		"-f", dockerfile_path,
		"--build-arg", "SERVER_BUILD_PATH=%s" % server_build_path,
		"-t", "%s:%s" % [image_name, image_tag],
		project_root,
	])
	var runner = EdgegapProcess.new()
	var code: int = runner.run(DOCKER_CMD, args)
	if code != 0:
		EdgegapLogger.error("docker build failed with exit code %d" % code)
		return FAILED
	EdgegapLogger.info("Docker image built: %s:%s" % [image_name, image_tag])
	return OK

func run_container(image_name: String, image_tag: String, run_params: String) -> String:
	var args := PackedStringArray(["run", "-d", "--rm"])
	for part in run_params.split(" ", false):
		if not part.is_empty():
			args.append(part)
	args.append("%s:%s" % [image_name, image_tag])

	var output: Array = []
	var code := OS.execute(DOCKER_CMD, args, output, true, false)
	for line in output:
		EdgegapLogger.info(str(line))
	if code != 0 or output.is_empty():
		EdgegapLogger.error("docker run failed with exit code %d" % code)
		return ""
	var container_id := str(output[0]).strip_edges()
	EdgegapSettings.add_local_container(container_id)
	EdgegapLogger.info("Started container %s" % container_id)
	return container_id

func terminate_plugin_containers() -> int:
	var ids: PackedStringArray = EdgegapSettings.get_local_containers()
	var stopped := 0
	for id in ids:
		var rm_out: Array = []
		OS.execute(DOCKER_CMD, PackedStringArray(["rm", "-f", id]), rm_out, true, false)
		for line in rm_out:
			EdgegapLogger.info(str(line))
		stopped += 1
	EdgegapSettings.set_local_containers(PackedStringArray())
	EdgegapLogger.info("Terminated %d container(s) started by the plugin." % stopped)
	return stopped
