class_name SlidePopup
extends Control

@export var dim_path: NodePath
@export var slide_dir := Vector2(0, -1)
@export var slide_margin := 8.0
@export var anim_time := 0.3

var _base_pos := Vector2.ZERO
var _dim: CanvasItem
var _dim_is_color := false
var _tween: Tween

func _ready() -> void:
	_base_pos = position
	if dim_path != NodePath():
		_dim = get_node_or_null(dim_path) as CanvasItem
	_dim_is_color = _dim is ColorRect
	if _dim != null:
		_dim.visible = false

func show_popup() -> void:
	_visible_on()
	_position_offscreen()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", _base_pos, anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _dim != null:
		_dim.visible = true
		if _dim is Control:
			(_dim as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		_set_dim_alpha(0.0)
		var prop := "color:a" if _dim_is_color else "modulate:a"
		_tween.parallel().tween_property(_dim, prop, 0.55, anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_popup() -> void:
	if _tween != null:
		_tween.kill()
	var target := _offscreen_position()
	_tween = create_tween()
	_tween.tween_property(self, "position", target, anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _dim != null:
		var prop := "color:a" if _dim_is_color else "modulate:a"
		_tween.parallel().tween_property(_dim, prop, 0.0, anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_on_hide_finished)

func _position_offscreen() -> void:
	position = _offscreen_position()

func _slide_offset() -> Vector2:
	var dir := slide_dir
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)
	var size_vec := size
	if size_vec == Vector2.ZERO and custom_minimum_size != Vector2.ZERO:
		size_vec = custom_minimum_size
	var sx := 0.0
	var sy := 0.0
	if dir.x > 0.0:
		sx = 1.0
	elif dir.x < 0.0:
		sx = -1.0
	if dir.y > 0.0:
		sy = 1.0
	elif dir.y < 0.0:
		sy = -1.0
	var offset := Vector2(sx * (size_vec.x + slide_margin), sy * (size_vec.y + slide_margin))
	if dir.x == 0:
		offset.x = 0.0
	if dir.y == 0:
		offset.y = 0.0
	return offset

func _offscreen_position() -> Vector2:
	var dir := slide_dir
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)
	var size_vec := size
	if size_vec == Vector2.ZERO and custom_minimum_size != Vector2.ZERO:
		size_vec = custom_minimum_size
	var viewport_size := get_viewport_rect().size
	var target := _base_pos
	if dir.x < 0.0:
		target.x = -size_vec.x - slide_margin
	elif dir.x > 0.0:
		target.x = viewport_size.x + slide_margin
	if dir.y < 0.0:
		target.y = -size_vec.y - slide_margin
	elif dir.y > 0.0:
		target.y = viewport_size.y + slide_margin
	return target

func _visible_on() -> void:
	visible = true

func _set_dim_alpha(alpha: float) -> void:
	if _dim == null:
		return
	if _dim_is_color:
		var rect := _dim as ColorRect
		var color := rect.color
		if color.a <= 0.0:
			color = Color(color.r, color.g, color.b, 1.0)
		color.a = alpha
		rect.color = color
	else:
		_dim.modulate.a = alpha

func _on_hide_finished() -> void:
	visible = false
	if _dim != null:
		_dim.visible = false
