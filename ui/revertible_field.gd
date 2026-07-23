@tool
extends HBoxContainer

signal value_changed(value: String)

var _default_value := ""
var _line := LineEdit.new()
var _revert := Button.new()

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.text_changed.connect(_on_text_changed)
	add_child(_line)

	_revert.text = "X"
	_revert.tooltip_text = "Revert to default"
	_revert.custom_minimum_size = Vector2(28, 0)
	_revert.pressed.connect(revert_to_default)
	_revert.visible = false
	add_child(_revert)

func configure(default_value: String, current_value: String = "", placeholder: String = "") -> void:
	_default_value = default_value
	_line.placeholder_text = placeholder
	_line.text = current_value if not current_value.is_empty() else default_value
	_update_revert_visibility()

func get_value() -> String:
	return _line.text

func set_value(value: String) -> void:
	_line.text = value
	_update_revert_visibility()

func set_default(default_value: String) -> void:
	_default_value = default_value
	_update_revert_visibility()

func revert_to_default() -> void:
	_line.text = _default_value
	_update_revert_visibility()
	value_changed.emit(_line.text)

func _on_text_changed(value: String) -> void:
	_update_revert_visibility()
	value_changed.emit(value)

func _update_revert_visibility() -> void:
	_revert.visible = _line.text != _default_value
