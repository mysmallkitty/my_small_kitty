class_name MapSelectCreatePanel
extends "res://scripts/ui/popup_panel.gd"

signal create_requested(title: String)
signal close_pressed

@onready var _title_edit: LineEdit = $LineEdit
@onready var _confirm_button: BaseButton = $Confirm
@onready var _close_button: BaseButton = $CloseButton

func _ready() -> void:
	super()
	z_as_relative = false
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _confirm_button != null and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)
	if _title_edit != null and not _title_edit.text_submitted.is_connected(_on_title_submitted):
		_title_edit.text_submitted.connect(_on_title_submitted)

func reset_focus() -> void:
	if _title_edit != null:
		_title_edit.text = ""
		_title_edit.grab_focus()

func _on_confirm_pressed() -> void:
	if _title_edit == null:
		return
	create_requested.emit(_title_edit.text.strip_edges())

func _on_title_submitted(new_text: String) -> void:
	create_requested.emit(new_text.strip_edges())

func _on_close_pressed() -> void:
	close_pressed.emit()

func show_popup() -> void:
	super()
	var dim := get_node_or_null(dim_path) as CanvasItem
	if dim != null:
		dim.z_index = z_index - 1
