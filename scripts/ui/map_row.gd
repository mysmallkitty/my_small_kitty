class_name MapRow
extends Control

signal pressed(item: MapRow)

@export var normal_offset_x := 36.0
@export var hover_offset_x := 32.0
@export var selected_offset_x := 0.0
@export var move_step := 10.0

var data: Dictionary = {}
var base_pos := Vector2.ZERO
var target_pos := Vector2.ZERO
var _selected := false
var _hovered := false
var _data_ready := false

@onready var title_label: Label = $Panel/HBox/MapTitle
@onready var creator_label: Label = $Panel/Creator
@onready var difficulty_icon: TextureRect = $Panel/DifficultyIcon
@onready var ranked_icon: TextureRect = $Panel/HBox/IsRanked
@onready var liked_icon: TextureRect = $Panel/HBox/IsLiked
@onready var wip_icon: TextureRect = $Panel/HBox/IsWIP

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_data_ready = true
	_apply_data()
	_update_target()
	set_process(true)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func _process(_delta: float) -> void:
	position = _step_towards(position, target_pos, move_step)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pressed.emit(self)

func set_data(entry: Dictionary) -> void:
	data = entry
	if _data_ready:
		_apply_data()

func _apply_data() -> void:
	var meta = data.get("metadata", null)
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	if title_label != null:
		var title := str(data.get("title", meta.get("title", "")))
		title_label.text = title if title.strip_edges() != "" else "untitled"
	if creator_label != null:
		creator_label.text = str(data.get("creator", meta.get("creator", "")))
	if difficulty_icon != null:
		difficulty_icon.texture = null
	if ranked_icon != null:
		ranked_icon.visible = bool(data.get("is_ranked", false))
	_update_difficulty_icon(int(data.get("rating", meta.get("rating", 1))))

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_target()

func set_base_position(pos: Vector2) -> void:
	base_pos = pos
	_update_target()

func _on_mouse_entered() -> void:
	_hovered = true
	_update_target()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_target()

func _update_target() -> void:
	var offset_x := normal_offset_x
	if _selected:
		offset_x = selected_offset_x
	elif _hovered:
		offset_x = hover_offset_x
	target_pos = base_pos + Vector2(offset_x, 0.0)

func _update_difficulty_icon(difficulty: int) -> void:
	if difficulty_icon == null:
		return
	var diff := clampi(difficulty, 1, 8)
	var path := "res://graphics/ui/16px/difficulty/%s.png" % str(diff)
	if ResourceLoader.exists(path):
		difficulty_icon.texture = load(path)

func _step_towards(from: Vector2, to: Vector2, step: float) -> Vector2:
	var out := from
	var dx := to.x - from.x
	if abs(dx) <= step:
		out.x = to.x
	else:
		out.x += step * sign(dx)
	var dy := to.y - from.y
	if abs(dy) <= step:
		out.y = to.y
	else:
		out.y += step * sign(dy)
	return out
