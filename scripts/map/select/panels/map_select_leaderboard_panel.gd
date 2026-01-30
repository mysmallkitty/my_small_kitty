class_name MapSelectLeaderboardPanel
extends SlidePopup

signal close_pressed
signal user_selected(user_id: int)

@export var row_scene: PackedScene = preload("res://ui/panels/record_row.tscn")

@onready var _rows: Control = $Panel/RecordContainer
@onready var _close_button: BaseButton = $Panel/CloseButton
@onready var _empty_label: Label = $Panel/no_records_yet

func _ready() -> void:
	super()
	if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)

func set_rows(rows: Array) -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	if rows.is_empty():
		if _empty_label != null:
			_empty_label.visible = true
		return
	if _empty_label != null:
		_empty_label.visible = false
	var y := 0.0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry_dict: Dictionary = row as Dictionary
		var row_node := row_scene.instantiate() as Control
		if row_node == null:
			continue
		row_node.position = Vector2(0, y)
		var name_label := row_node.get_node_or_null("Panel/username") as Label
		if name_label != null:
			name_label.text = str(entry_dict.get("username",""))
		var time_label := row_node.get_node_or_null("Panel/HBoxContainer/ClearTime") as Label
		if time_label != null:
			time_label.text = Game._format_ticks(int(entry_dict.get("clear_time",0)))
		var death_label := row_node.get_node_or_null("Panel/HBoxContainer/DeathCount") as Label
		if death_label != null:
			death_label.text = str(int(entry_dict.get("deaths", entry_dict.get("death", 0))))
		var pp_label := row_node.get_node_or_null("Panel/HBoxContainer/PP") as Label
		if pp_label != null:
			pp_label.text = str(int(entry_dict.get("pp", 0))) + "pp"
		var user_id := int(entry_dict.get("user_id", 0))
		row_node.set_meta("user_id", user_id)
		row_node.mouse_filter = Control.MOUSE_FILTER_STOP
		if not row_node.gui_input.is_connected(_on_row_input):
			row_node.gui_input.connect(_on_row_input.bind(row_node))
		_rows.add_child(row_node)
		y += row_node.size.y

func _on_row_input(event: InputEvent, row_node: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var user_id := int(row_node.get_meta("user_id", 0))
			if user_id > 0:
				user_selected.emit(user_id)

func _on_close_pressed() -> void:
	close_pressed.emit()
