extends RefCounted
class_name EdgegapDocker

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")
const EdgegapSettings = preload("settings.gd")

enum Status {
	OK,
	NOT_RUNNING,
	NOT_INSTALLED,
}

func is_available() -> bool:
	return check_status() == Status.OK

static func is_arm_cpu() -> bool:
	return EdgegapSettings.is_arm_cpu()

## docker --version only needs the CLI; a tiny `docker info` format probe needs the daemon.
## Runs quietly — full `docker info` output is huge and was drowning useful logs.
func check_status() -> Status:
	var output: Array = []
	var version_code: int = _execute_docker(PackedStringArray(["--version"]), output, true)
	if version_code != 0:
		return Status.NOT_INSTALLED

	output.clear()
	var info_code: int = _execute_docker(
		PackedStringArray(["info", "--format", "{{.ServerVersion}}"]),
		output,
		true
	)
	if info_code != 0:
		return Status.NOT_RUNNING
	return Status.OK

func status_message(status: Status = Status.OK) -> String:
	match status:
		Status.OK:
			return "Docker is installed and running."
		Status.NOT_RUNNING:
			return "Docker is installed but not running. Start Docker Desktop and try again."
		Status.NOT_INSTALLED:
			return "Docker is not installed."
	return "Docker is not available."

func open_install_page() -> void:
	OS.shell_open(EdgegapConstants.DOCKER_INSTALL_URL)

var _build_pid: int = -1
var _build_image_name := ""
var _build_image_tag := ""

func is_build_running() -> bool:
	return _build_pid >= 0 and OS.is_process_running(_build_pid)

func build_image_name() -> String:
	return _build_image_name

func build_image_tag() -> String:
	return _build_image_tag

## Starts a non-blocking docker build. Poll with is_build_running() / take_build_exit_code().
func start_build_image(
	dockerfile_path: String,
	server_build_path: String,
	image_name: String,
	image_tag: String,
	build_params: String = ""
) -> Error:
	if is_build_running():
		return ERR_BUSY

	var project_root := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray()

	# Match Edgegap Unity: ARM hosts cross-compile with buildx for amd64 Edgegap infra.
	if is_arm_cpu():
		args.append_array(PackedStringArray(["buildx", "build", "--platform", "linux/amd64"]))
	else:
		args.append("build")

	for part in build_params.split(" ", false):
		if not part.is_empty():
			args.append(part)

	args.append_array(PackedStringArray([
		"-f", dockerfile_path,
		"--build-arg", "SERVER_BUILD_PATH=%s" % server_build_path,
		"-t", "%s:%s" % [image_name, image_tag],
		project_root,
	]))

	_build_image_name = image_name
	_build_image_tag = image_tag

	var command_and_args := _docker_command(args)
	var command: String = command_and_args[0]
	var cmd_args: PackedStringArray = command_and_args[1]
	EdgegapLogger.info("Docker build starting: %s %s" % [command, " ".join(cmd_args)])
	_build_pid = OS.create_process(command, cmd_args, false)
	if _build_pid < 0:
		EdgegapLogger.error("Failed to start Docker build process.")
		_build_pid = -1
		return ERR_CANT_CREATE

	EdgegapLogger.info("Docker build pid=%d" % _build_pid)
	return OK

## Returns -1 while still running, otherwise the process exit code (and clears pid).
func take_build_exit_code() -> int:
	if _build_pid < 0:
		return FAILED
	if OS.is_process_running(_build_pid):
		return -1
	var code := OS.get_process_exit_code(_build_pid)
	_build_pid = -1
	if code != 0:
		EdgegapLogger.error("Docker build failed with exit code %d" % code)
	else:
		EdgegapLogger.info("Docker image built: %s:%s" % [_build_image_name, _build_image_tag])
	return code

func run_container(image_name: String, image_tag: String, run_params: String) -> String:
	if is_plugin_container_running():
		EdgegapLogger.error(
			"A local container started by the plugin is already running. Terminate it first."
		)
		return ""

	var args := PackedStringArray(["run", "-d", "--rm"])
	if is_arm_cpu():
		args.append_array(PackedStringArray(["--platform", "linux/amd64"]))
	for part in run_params.split(" ", false):
		if not part.is_empty():
			args.append(part)
	args.append("%s:%s" % [image_name, image_tag])

	var output: Array = []
	var code := _execute_docker(args, output)
	for line in output:
		EdgegapLogger.info(str(line))
	if code != 0 or output.is_empty():
		EdgegapLogger.error("Docker run failed with exit code %d" % code)
		return ""
	var container_id := str(output[0]).strip_edges()
	EdgegapSettings.set_local_container_id(container_id)
	EdgegapLogger.info("Started container %s" % container_id)
	return container_id

func is_plugin_container_running() -> bool:
	var id: String = EdgegapSettings.get_local_container_id()
	if id.is_empty():
		return false
	var output: Array = []
	var code := _execute_docker(
		PackedStringArray(["inspect", "-f", "{{.State.Running}}", id]),
		output,
		true
	)
	if code != 0:
		EdgegapSettings.clear_local_container_id()
		return false
	var running := " ".join(PackedStringArray(output)).strip_edges().to_lower() == "true"
	if not running:
		EdgegapSettings.clear_local_container_id()
	return running

func terminate_plugin_container() -> bool:
	var id: String = EdgegapSettings.get_local_container_id()
	if id.is_empty():
		EdgegapLogger.info("No plugin container to terminate.")
		return false
	var rm_out: Array = []
	_execute_docker(PackedStringArray(["rm", "-f", id]), rm_out)
	for line in rm_out:
		EdgegapLogger.info(str(line))
	EdgegapSettings.clear_local_container_id()
	EdgegapLogger.info("Terminated plugin container %s." % id)
	return true

## Returns local image refs as "repository:tag" (skips dangling <none> entries).
func list_local_image_refs() -> PackedStringArray:
	var output: Array = []
	var code := _execute_docker(
		PackedStringArray(["images", "--format", "{{.Repository}}:{{.Tag}}"]),
		output,
		true
	)
	var refs: PackedStringArray = []
	if code != 0:
		EdgegapLogger.warn("Failed to list local Docker images (exit %d)." % code)
		return refs

	# OS.execute often returns one blob with embedded newlines (especially on Windows).
	var chunks: PackedStringArray = []
	for entry in output:
		for line in str(entry).replace("\r\n", "\n").replace("\r", "\n").split("\n", false):
			chunks.append(line)

	for line in chunks:
		var text := line.strip_edges()
		if text.is_empty():
			continue
		if text.begins_with("<none>") or text.ends_with(":<none>"):
			continue
		if refs.find(text) < 0:
			refs.append(text)
	return refs

## Match Unity LoginContainerRegistry: docker login -u … --password … registry
func login_registry(registry_url: String, username: String, password: String) -> bool:
	var code := _run_docker(PackedStringArray([
		"login",
		"-u", username,
		"--password", password,
		registry_url,
	]))
	if code != 0:
		EdgegapLogger.error("Docker registry login failed (exit %d)." % code)
		return false
	EdgegapLogger.info("Docker registry login succeeded: %s" % registry_url)
	return true

## Tag a local image for Edgegap registry push: registry/project/image:tag
func tag_for_registry(
	local_ref: String,
	registry_url: String,
	project: String,
	image_name: String,
	image_tag: String
) -> String:
	var remote_ref := "%s/%s/%s:%s" % [registry_url, project, image_name, image_tag]
	if local_ref == remote_ref:
		return remote_ref
	var code := _run_docker(PackedStringArray(["tag", local_ref, remote_ref]))
	if code != 0:
		EdgegapLogger.error("Docker tag failed: %s → %s (exit %d)" % [local_ref, remote_ref, code])
		return ""
	EdgegapLogger.info("Tagged %s → %s" % [local_ref, remote_ref])
	return remote_ref

var _push_pid: int = -1
var _push_remote_ref := ""

func is_push_running() -> bool:
	return _push_pid >= 0 and OS.is_process_running(_push_pid)

## Starts non-blocking docker push. Poll with is_push_running() / take_push_exit_code().
func start_push_image(remote_ref: String) -> Error:
	if is_push_running() or is_build_running():
		return ERR_BUSY
	_push_remote_ref = remote_ref
	var command_and_args := _docker_command(PackedStringArray(["push", remote_ref]))
	var command: String = command_and_args[0]
	var cmd_args: PackedStringArray = command_and_args[1]
	EdgegapLogger.info("Docker push starting: %s %s" % [command, " ".join(cmd_args)])
	_push_pid = OS.create_process(command, cmd_args, false)
	if _push_pid < 0:
		EdgegapLogger.error("Failed to start Docker push process.")
		_push_pid = -1
		return ERR_CANT_CREATE
	EdgegapLogger.info("Docker push pid=%d" % _push_pid)
	return OK

func take_push_exit_code() -> int:
	if _push_pid < 0:
		return FAILED
	if OS.is_process_running(_push_pid):
		return -1
	var code := OS.get_process_exit_code(_push_pid)
	_push_pid = -1
	if code != 0:
		EdgegapLogger.error("Docker push failed with exit code %d (%s)" % [code, _push_remote_ref])
	else:
		EdgegapLogger.info("Docker image pushed: %s" % _push_remote_ref)
	return code

func _run_docker(args: PackedStringArray, quiet: bool = true) -> int:
	var output: Array = []
	return _execute_docker(args, output, quiet)

func _execute_docker(args: PackedStringArray, output: Array, quiet: bool = false) -> int:
	var command_and_args := _docker_command(args)
	if not quiet:
		EdgegapLogger.info("Running: %s %s" % [command_and_args[0], " ".join(command_and_args[1])])
	return OS.execute(command_and_args[0], command_and_args[1], output, true, false)

## Windows: `docker …` directly.
## macOS/Linux: `/bin/bash -c "docker …"` so login-shell PATH/aliases resolve (same as Unity plugin).
func _docker_command(docker_args: PackedStringArray) -> Array:
	if OS.get_name() == "Windows":
		return ["docker", docker_args]
	var shell := "docker"
	for arg in docker_args:
		shell += " " + _shell_quote(str(arg))
	return ["/bin/bash", PackedStringArray(["-c", shell])]

func _shell_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "'\"'\"'")
