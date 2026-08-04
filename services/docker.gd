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
var _build_log_path := ""

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
	var binary_path := project_root.path_join("%s.x86_64" % server_build_path)
	var pck_path := project_root.path_join("%s.pck" % server_build_path)
	if not FileAccess.file_exists(binary_path):
		EdgegapLogger.error("Server binary missing before Docker build: %s" % binary_path)
		return ERR_FILE_NOT_FOUND
	if not FileAccess.file_exists(pck_path):
		EdgegapLogger.error(
			"Server .pck missing before Docker build: %s. In the Edgegap export preset, disable binary_format/embed_pck, then re-export." % pck_path
		)
		return ERR_FILE_NOT_FOUND

	var args := PackedStringArray(["build"])
	# Docker Desktop on Apple Silicon: plain `docker build --platform` cross-builds and
	# loads locally. Avoid `buildx --load`, which often fails with the default docker driver.
	if is_arm_cpu() and not _has_platform_flag(build_params):
		args.append_array(PackedStringArray(["--platform", "linux/amd64"]))

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
	_build_log_path = _docker_log_path("docker-build.log")

	var command_and_args := _docker_command(args)
	var command: String = command_and_args[0]
	var cmd_args: PackedStringArray = command_and_args[1]
	EdgegapLogger.info("Docker build starting: %s %s" % [command, " ".join(cmd_args)])
	EdgegapLogger.info("Docker build log: %s" % _build_log_path)

	_build_pid = _create_process_with_log(command, cmd_args, _build_log_path)
	if _build_pid < 0:
		EdgegapLogger.error("Failed to start Docker build process.")
		_build_pid = -1
		return ERR_CANT_CREATE

	EdgegapLogger.info("Docker build pid=%d" % _build_pid)
	return OK

static func _has_platform_flag(build_params: String) -> bool:
	return build_params.find("--platform") >= 0

## Returns -1 while still running, otherwise the process exit code (and clears pid).
func take_build_exit_code() -> int:
	if _build_pid < 0:
		return FAILED
	if OS.is_process_running(_build_pid):
		return -1
	var code := _normalize_exit_code(OS.get_process_exit_code(_build_pid))
	_build_pid = -1
	if code != 0:
		EdgegapLogger.error("Docker build failed with exit code %d" % code)
		_dump_log_tail(_build_log_path)
	else:
		EdgegapLogger.info("Docker image built: %s:%s" % [_build_image_name, _build_image_tag])
	return code

## Godot on macOS/Linux may return a wait-status (exit << 8) instead of a plain exit code.
static func _normalize_exit_code(code: int) -> int:
	if code < 0:
		return code
	if code > 255:
		return (code >> 8) & 0xff
	return code

func _docker_log_path(filename: String) -> String:
	var cache_dir := OS.get_cache_dir().path_join("edgegap-godot")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	return cache_dir.path_join(filename)

func _create_process_with_log(command: String, args: PackedStringArray, log_path: String) -> int:
	var parts: PackedStringArray = [_shell_quote(command)]
	for arg in args:
		parts.append(_shell_quote(str(arg)))
	var redirected := "%s > %s 2>&1" % [" ".join(parts), _shell_quote(log_path)]
	if OS.get_name() == "Windows":
		return OS.create_process("cmd.exe", PackedStringArray(["/C", redirected]), false)
	return OS.create_process("/bin/bash", PackedStringArray(["-c", redirected]), false)

func _dump_log_tail(log_path: String, max_lines: int = 50) -> void:
	if log_path.is_empty() or not FileAccess.file_exists(log_path):
		EdgegapLogger.error("Docker log file missing; cannot show build output.")
		return
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		EdgegapLogger.error("Could not read Docker log: %s" % log_path)
		return
	var text := file.get_as_text()
	file.close()
	var lines := text.replace("\r", "").split("\n", false)
	var start := maxi(0, lines.size() - max_lines)
	EdgegapLogger.error("—— Docker output (last %d lines) ——" % mini(max_lines, lines.size()))
	for i in range(start, lines.size()):
		EdgegapLogger.error(lines[i])
	EdgegapLogger.error("—— end Docker output ——")

func _shell_quote(value: String) -> String:
	if OS.get_name() == "Windows":
		return "\"%s\"" % value.replace("\"", "\\\"")
	return "'%s'" % value.replace("'", "'\"'\"'")

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
	var code := _normalize_exit_code(OS.get_process_exit_code(_push_pid))
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

var _docker_bin := ""

## Resolve the Docker CLI once. Godot (and other GUI apps) on macOS often lack the
## user shell PATH, so plain `docker` looks "not installed" even when Docker Desktop runs.
func _resolve_docker_bin() -> String:
	if not _docker_bin.is_empty():
		return _docker_bin

	if OS.get_name() == "Windows":
		_docker_bin = "docker"
		return _docker_bin

	var home := OS.get_environment("HOME")
	var candidates := PackedStringArray([
		"/usr/local/bin/docker",
		"/opt/homebrew/bin/docker",
		home.path_join(".docker/bin/docker"),
		"/Applications/Docker.app/Contents/Resources/bin/docker",
	])
	for path in candidates:
		if not path.is_empty() and FileAccess.file_exists(path):
			_docker_bin = path
			EdgegapLogger.info("Using Docker CLI at %s" % _docker_bin)
			return _docker_bin

	# Login shell picks up ~/.zprofile / ~/.bash_profile PATH customizations.
	var which_out: Array = []
	var which_code := OS.execute(
		"/bin/bash",
		PackedStringArray(["-lc", "command -v docker"]),
		which_out,
		true,
		false
	)
	if which_code == 0 and not which_out.is_empty():
		var found := str(which_out[0]).strip_edges()
		if not found.is_empty() and FileAccess.file_exists(found):
			_docker_bin = found
			EdgegapLogger.info("Using Docker CLI at %s" % _docker_bin)
			return _docker_bin

	_docker_bin = "docker"
	return _docker_bin

## Prefer an absolute Docker binary on macOS/Linux so PATH does not matter.
## Windows keeps `docker` on PATH (Docker Desktop).
func _docker_command(docker_args: PackedStringArray) -> Array:
	return [_resolve_docker_bin(), docker_args]
