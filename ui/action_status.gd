@tool
extends VBoxContainer

## Per-action progress + result, shown under the related button.

var progress: ProgressBar
var result: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.visible = false
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.custom_minimum_size = Vector2(0, 16)
	add_child(progress)

	result = Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.visible = false
	add_child(result)

func clear() -> void:
	progress.visible = false
	progress.value = 0
	result.visible = false
	result.text = ""

func set_busy(message: String, pct: float = 10.0) -> void:
	result.visible = true
	result.text = message
	progress.visible = true
	progress.value = clampf(pct, 0.0, 100.0)

func set_progress(pct: float, message: String = "") -> void:
	progress.visible = true
	progress.value = clampf(pct, 0.0, 100.0)
	if not message.is_empty():
		result.visible = true
		result.text = message

func set_success(message: String) -> void:
	progress.visible = false
	progress.value = 100
	result.visible = true
	result.text = message

func set_error(message: String) -> void:
	progress.visible = false
	result.visible = true
	result.text = message
