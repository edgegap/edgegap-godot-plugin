@tool
extends ScrollContainer

const ConstantsScript = preload("../constants.gd")
const SettingsScript = preload("../services/settings.gd")
const LoggerScript = preload("../services/logger.gd")
const AuthScript = preload("../services/auth.gd")
const TemplatesScript = preload("../services/export_templates.gd")
const PresetScript = preload("../services/export_preset.gd")
const ExportScript = preload("../services/headless_export.gd")
const DockerScript = preload("../services/docker.gd")
const PathsScript = preload("../services/paths.gd")
const RevertibleFieldScript = preload("revertible_field.gd")
const ActionStatusScript = preload("action_status.gd")

var _root := VBoxContainer.new()
var _signed_out_box := VBoxContainer.new()
var _auth_box := VBoxContainer.new()
var _workflow_box := VBoxContainer.new()

var _token_edit := LineEdit.new()
var _auth_status
var _templates_status_label := Label.new()
var _templates_status
var _export_status
var _docker_status
var _containerize_status
var _local_status

var _install_templates_btn := Button.new()
var _export_btn := Button.new()
var _validate_token_btn := Button.new()
var _containerize_btn := Button.new()
var _deploy_local_btn := Button.new()

var _image_name_field
var _image_tag_field
var _dockerfile_field
var _run_params_field
var _local_tag_option := OptionButton.new()

var _http := HTTPRequest.new()
var _templates_http := HTTPRequest.new()
var _auth
var _templates
var _presets
var _exporter
var _docker

var _awaiting_token_entry := false
var _templates_downloading := false
var _exporting := false
var _export_progress := 0.0

func _ready() -> void:
	_auth = AuthScript.new()
	_templates = TemplatesScript.new()
	_presets = PresetScript.new()
	_exporter = ExportScript.new()
	_docker = DockerScript.new()

	SettingsScript.ensure_defaults()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)

	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_auth.bind_http(_http)
	_auth.verified.connect(_on_auth_verified)

	add_child(_templates_http)
	_templates_http.request_completed.connect(_on_templates_http_completed)

	_build_header()
	_build_discord_row()
	_build_signed_out()
	_build_auth()
	_build_workflow()
	_refresh_auth_visibility()

func _new_action_status():
	return ActionStatusScript.new()

func _action_block(button_row: Control, status: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	box.add_child(button_row)
	box.add_child(status)
	return box

func _build_header() -> void:
	var tex := load(PathsScript.addon_root().path_join("assets/banner.png")) as Texture2D

	var clip := Control.new()
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	if tex:
		clip.custom_minimum_size = Vector2(0, tex.get_height())

	var banner := TextureRect.new()
	banner.texture = tex
	banner.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	banner.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	banner.tooltip_text = ConstantsScript.SITE_URL
	banner.gui_input.connect(_on_banner_gui_input)
	if tex:
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		banner.anchor_left = 1.0
		banner.anchor_top = 0.0
		banner.anchor_right = 1.0
		banner.anchor_bottom = 0.0
		banner.offset_left = -w
		banner.offset_top = 0.0
		banner.offset_right = 0.0
		banner.offset_bottom = h

	clip.add_child(banner)
	_root.add_child(clip)

func _on_banner_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(ConstantsScript.SITE_URL)

func _build_discord_row() -> void:
	var discord := Button.new()
	discord.text = "Join our Discord"
	discord.pressed.connect(func(): OS.shell_open(ConstantsScript.DISCORD_URL))
	_root.add_child(discord)

func _build_signed_out() -> void:
	_signed_out_box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "1. Connect your Edgegap Account"
	title.add_theme_font_size_override("font_size", 16)
	_signed_out_box.add_child(title)

	var sign_in := Button.new()
	sign_in.text = "Sign in"
	sign_in.pressed.connect(_on_sign_in_pressed)
	_signed_out_box.add_child(sign_in)
	_root.add_child(_signed_out_box)

func _build_auth() -> void:
	_auth_box.add_theme_constant_override("separation", 8)
	_auth_box.add_child(_section_label("1. Connect your Edgegap Account"))

	_token_edit.secret = true
	_token_edit.placeholder_text = "token xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
	_token_edit.focus_entered.connect(func(): _token_edit.secret = false)
	_token_edit.focus_exited.connect(func(): _token_edit.secret = true)
	_auth_box.add_child(_token_edit)

	var auth_row := HBoxContainer.new()
	var get_token := Button.new()
	get_token.text = "Get token"
	get_token.pressed.connect(func(): OS.shell_open(ConstantsScript.SIGN_IN_URL))
	_validate_token_btn.text = "Validate token"
	_validate_token_btn.pressed.connect(_on_validate_token)
	var sign_out := Button.new()
	sign_out.text = "Sign out"
	sign_out.pressed.connect(_on_sign_out)
	auth_row.add_child(get_token)
	auth_row.add_child(_validate_token_btn)
	auth_row.add_child(sign_out)

	_auth_status = _new_action_status()
	_auth_box.add_child(_action_block(auth_row, _auth_status))
	_root.add_child(_auth_box)

func _build_workflow() -> void:
	_workflow_box.add_theme_constant_override("separation", 12)
	_workflow_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_workflow_box.add_child(_section_label("2. Build Your Game Server"))
	_templates_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workflow_box.add_child(_templates_status_label)

	var template_row := HBoxContainer.new()
	var validate_templates := Button.new()
	validate_templates.text = "Validate export templates"
	validate_templates.pressed.connect(_on_validate_templates)
	_install_templates_btn.text = "Install templates"
	_install_templates_btn.pressed.connect(_on_install_templates)
	_install_templates_btn.visible = false
	template_row.add_child(validate_templates)
	template_row.add_child(_install_templates_btn)
	_templates_status = _new_action_status()
	_workflow_box.add_child(_action_block(template_row, _templates_status))

	var open_presets := Button.new()
	open_presets.text = "Open export presets"
	open_presets.pressed.connect(func(): _presets.open_export_dialog())
	_workflow_box.add_child(open_presets)

	_export_btn.text = "Export server"
	_export_btn.pressed.connect(_on_export_server)
	_export_status = _new_action_status()
	_workflow_box.add_child(_action_block(_export_btn, _export_status))

	_workflow_box.add_child(_section_label("3. Containerize Your Server"))
	var validate_docker := Button.new()
	validate_docker.text = "Validate Docker"
	validate_docker.pressed.connect(_on_validate_docker)
	_docker_status = _new_action_status()
	_workflow_box.add_child(_action_block(validate_docker, _docker_status))

	_image_name_field = RevertibleFieldScript.new()
	_image_tag_field = RevertibleFieldScript.new()
	_dockerfile_field = RevertibleFieldScript.new()
	_workflow_box.add_child(_labeled("Image name", _image_name_field))
	_workflow_box.add_child(_labeled("Image tag", _image_tag_field))
	_workflow_box.add_child(_labeled("Dockerfile path", _dockerfile_field))

	_containerize_btn.text = "Containerize with Docker"
	_containerize_btn.pressed.connect(_on_containerize)
	_containerize_status = _new_action_status()
	_workflow_box.add_child(_action_block(_containerize_btn, _containerize_status))

	_workflow_box.add_child(_section_label("4. Test Your Server Locally"))
	_local_tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workflow_box.add_child(_labeled("Server image tag", _local_tag_option))
	_run_params_field = RevertibleFieldScript.new()
	_workflow_box.add_child(_labeled("Docker run parameters", _run_params_field))

	var local_row := HBoxContainer.new()
	_deploy_local_btn.text = "Deploy local container"
	_deploy_local_btn.pressed.connect(_on_deploy_local)
	var terminate := Button.new()
	terminate.text = "Terminate"
	terminate.pressed.connect(_on_terminate_local)
	local_row.add_child(_deploy_local_btn)
	local_row.add_child(terminate)
	_local_status = _new_action_status()
	_workflow_box.add_child(_action_block(local_row, _local_status))

	_root.add_child(_workflow_box)
	_reload_field_defaults()

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	return label

func _labeled(title: String, field: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(field)
	return box

func _reload_field_defaults() -> void:
	if _image_name_field == null:
		return
	var image_default: String = SettingsScript.default_image_name()
	_image_name_field.configure(image_default, image_default)
	_image_tag_field.configure("", "", "yy.MM.dd-HH.mm.ss-UTC (auto on build)")
	_image_tag_field.set_value("")
	var docker_default: String = SettingsScript.default_dockerfile_path()
	_dockerfile_field.configure(docker_default, docker_default)
	var run_default: String = SettingsScript.default_docker_run_params()
	_run_params_field.configure(run_default, run_default)
	_token_edit.text = SettingsScript.get_token()
	_refresh_local_tags()
	_on_validate_templates()

func _refresh_auth_visibility() -> void:
	var has_token: bool = SettingsScript.is_token_verified()
	if has_token:
		_awaiting_token_entry = false
		_signed_out_box.visible = false
		_auth_box.visible = true
		_workflow_box.visible = true
		_token_edit.text = SettingsScript.get_token()
		_reload_field_defaults()
		return

	_auth_box.visible = _awaiting_token_entry
	_workflow_box.visible = false
	_signed_out_box.visible = not _awaiting_token_entry

func _on_sign_in_pressed() -> void:
	OS.shell_open(ConstantsScript.SIGN_IN_URL)
	_awaiting_token_entry = true
	_refresh_auth_visibility()
	_token_edit.grab_focus()
	if _auth_status:
		_auth_status.set_success("Paste your API token, then click Validate token.")

func _on_sign_out() -> void:
	SettingsScript.clear_token()
	_token_edit.text = ""
	_awaiting_token_entry = false
	_refresh_auth_visibility()
	if _auth_status:
		_auth_status.set_success("Signed out.")

func _on_validate_token() -> void:
	_validate_token_btn.disabled = true
	_auth_status.set_busy("Validating token via Edgegap wizard…", 20)
	_auth.validate_token(_token_edit.text)

func _on_auth_verified(ok: bool, message: String) -> void:
	_validate_token_btn.disabled = false
	if ok:
		_auth_status.set_success(message)
		_refresh_auth_visibility()
		if SettingsScript.has_registry_credentials():
			var creds := SettingsScript.get_registry_credentials()
			LoggerScript.info(
				"Registry ready: %s / project=%s / user=%s" % [
					creds.registry_url, creds.project, creds.username
				]
			)
	else:
		_auth_status.set_error(message)

func _process(delta: float) -> void:
	if _templates_downloading and _templates_status:
		var total := _templates_http.get_body_size()
		var got := _templates_http.get_downloaded_bytes()
		if total > 0:
			var pct := clampf(10.0 + 60.0 * (float(got) / float(total)), 10.0, 70.0)
			_templates_status.set_progress(pct, "Downloading… %d / %d MB" % [
				got / (1024 * 1024), total / (1024 * 1024)
			])
		else:
			_templates_status.set_progress(20, "Downloading… %d MB" % [got / (1024 * 1024)])

	if _exporting and _export_status:
		if _exporter.is_running():
			_export_progress = minf(_export_progress + delta * 12.0, 90.0)
			_export_status.set_progress(_export_progress, "Exporting dedicated server (debug)…")
		else:
			_finish_export()

func _on_validate_templates() -> void:
	var ok: bool = _templates.is_installed()
	_templates_status_label.text = _templates.status_message()
	_install_templates_btn.visible = not ok
	LoggerScript.info(
		"Templates check: version=%s dir=%s installed=%s" % [
			_templates.resolved_version(), _templates.templates_dir(), ok
		]
	)
	if _templates_status == null:
		return
	if ok:
		_templates_status.set_success("Templates OK.")
		LoggerScript.info(_templates.status_message())
	else:
		_templates_status.set_error("Templates missing — install required.")
		LoggerScript.warn(_templates.status_message())

func _on_install_templates() -> void:
	if _templates_downloading:
		return
	_templates_downloading = true
	_install_templates_btn.disabled = true
	_templates_status.set_busy("Downloading export templates…", 10)
	var err: Error = _templates.begin_download(_templates_http)
	if err != OK:
		_templates_downloading = false
		_install_templates_btn.disabled = false
		_templates_status.set_error("Failed to start template download. See Output.")

func _on_templates_http_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_templates_downloading = false
	_install_templates_btn.disabled = false
	_templates_http.download_file = ""

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_templates_status.set_error("Download failed (HTTP %d)." % response_code)
		LoggerScript.error("Template download failed: result=%d http=%d" % [result, response_code])
		return

	_templates_status.set_busy("Installing export templates…", 80)
	var err: Error = _templates.install_from_cache()
	_on_validate_templates()
	if err != OK:
		_templates_status.set_error("Install failed. See Output.")
	else:
		_templates_status.set_success("Export templates installed.")

func _on_export_server() -> void:
	if _exporting:
		return

	_export_status.set_busy("Preparing export…", 5)
	var preset_err: Error = _presets.ensure_preset()
	if preset_err != OK:
		_export_status.set_error("Failed to ensure export preset. See Output.")
		return

	if not _templates.is_installed():
		_on_validate_templates()
		_export_status.set_error("Export templates missing. Install them first.")
		return

	_export_progress = 10.0
	_exporting = true
	_export_btn.disabled = true
	_export_status.set_busy("Exporting dedicated server (debug)…", _export_progress)

	var err: Error = _exporter.start_export_debug(
		ConstantsScript.PRESET_NAME,
		_presets.get_export_path()
	)
	if err != OK:
		_exporting = false
		_export_btn.disabled = false
		_export_status.set_error("Failed to start export. See Output.")

func _finish_export() -> void:
	var code: int = _exporter.take_exit_code()
	_exporting = false
	_export_btn.disabled = false

	if code != 0:
		_export_status.set_error("Export failed (exit %d). See Output." % code)
		LoggerScript.error("Export failed with exit code %d" % code)
		return

	var out_path: String = _exporter.export_output_path()
	if not FileAccess.file_exists(out_path):
		_export_status.set_error("Export finished but binary missing. See Output.")
		LoggerScript.error("Export finished but binary missing at %s" % out_path)
		return

	_export_status.set_success("Export finished: %s" % _presets.get_export_path())
	LoggerScript.info("Export succeeded: %s" % out_path)

func _on_validate_docker() -> void:
	_docker_status.set_busy("Checking Docker…", 30)
	if _docker.is_available():
		_docker_status.set_success("Docker is installed and running.")
		LoggerScript.info("Docker validation succeeded.")
	else:
		_docker_status.set_error("Docker is not available. Opening install page.")
		LoggerScript.error("Docker validation failed. Opening install page.")
		_docker.open_install_page()

func _on_containerize() -> void:
	if not _docker.is_available():
		_containerize_status.set_error("Docker is not available.")
		_docker.open_install_page()
		return

	if not _presets.has_preset():
		_containerize_status.set_error("Export preset missing. Run Export server first.")
		return

	var image_name: String = _image_name_field.get_value().strip_edges()
	var image_tag: String = _image_tag_field.get_value().strip_edges()
	if image_tag.is_empty():
		image_tag = SettingsScript.unity_style_timestamp_tag()
		_image_tag_field.set_value(image_tag)

	var dockerfile: String = _dockerfile_field.get_value().strip_edges()
	if not FileAccess.file_exists(dockerfile):
		_containerize_status.set_error("Dockerfile not found.")
		LoggerScript.error("Dockerfile missing at %s" % dockerfile)
		return

	_containerize_btn.disabled = true
	_containerize_status.set_busy("Building Docker image…", 30)
	# OS.execute blocks; yield a frame so the busy state paints first.
	await get_tree().process_frame
	var err: Error = _docker.build_image(dockerfile, _presets.get_server_build_arg(), image_name, image_tag)
	_containerize_btn.disabled = false
	if err != OK:
		_containerize_status.set_error("Containerize failed. See Output.")
		return
	_refresh_local_tags()
	_local_tag_option.select(_find_tag_index(image_tag))
	_containerize_status.set_success("Image ready: %s:%s" % [image_name, image_tag])

func _on_deploy_local() -> void:
	var image_name: String = _image_name_field.get_value().strip_edges()
	var image_tag: String = ""
	if _local_tag_option.item_count > 0:
		image_tag = _local_tag_option.get_item_text(_local_tag_option.selected)
	elif not _image_tag_field.get_value().is_empty():
		image_tag = _image_tag_field.get_value()
	if image_tag.is_empty():
		_local_status.set_error("No image tag selected.")
		return
	_local_status.set_busy("Starting local container…", 50)
	var id: String = _docker.run_container(image_name, image_tag, _run_params_field.get_value())
	if id.is_empty():
		_local_status.set_error("Failed to start container. See Output.")
		return
	_local_status.set_success("Container running: %s" % id)

func _on_terminate_local() -> void:
	var count: int = _docker.terminate_plugin_containers()
	_local_status.set_success("Terminated %d container(s)." % count)

func _refresh_local_tags() -> void:
	_local_tag_option.clear()
	var current: String = _image_tag_field.get_value()
	if not current.is_empty():
		_local_tag_option.add_item(current)

func _find_tag_index(tag: String) -> int:
	for i in _local_tag_option.item_count:
		if _local_tag_option.get_item_text(i) == tag:
			return i
	_local_tag_option.add_item(tag)
	return _local_tag_option.item_count - 1

func _on_http_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Wizard/auth owns auth HTTP responses via EdgegapWizardApi.
	pass
