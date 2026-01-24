extends CanvasLayer

@export var alert_scene: PackedScene = preload("res://graphics/ui/panels/alert/alert.tscn")
@export var info_texture: Texture2D = preload("res://graphics/ui/panels/alert/info.png")
@export var warning_texture: Texture2D = preload("res://graphics/ui/panels/alert/warning.png")
@export var margin := Vector2(8, 8)
@export var spacing := 2.0
@export var enter_time := 0.3
@export var exit_time := 0.3
@export var hold_time := 2.0
@export var slide_in_offset := 12.0

var _root: Control
var _items: Array[Control] = []

func _ready() -> void:
	layer = 900
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_root.position = Vector2(-margin.x, margin.y)
	add_child(_root)

func push(message: String, is_warning: bool = false) -> void:
	if alert_scene == null:
		return
	var alert := alert_scene.instantiate() as Control
	if alert == null:
		return
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_alert_style(alert, message, is_warning)
	_root.add_child(alert)
	_items.append(alert)
	var index := _items.size() - 1
	var target := _calc_target_position(index, alert)
	_start_enter(alert, target)
	_reflow(true, alert)
	_schedule_exit(alert)

func _apply_alert_style(alert: Control, message: String, is_warning: bool) -> void:
	var panel := alert.get_node_or_null("panel") as TextureRect
	if panel != null:
		panel.texture = warning_texture if is_warning else info_texture
	var label := alert.get_node_or_null("message") as Label
	if label != null:
		label.text = message

func _start_enter(alert: Control, target: Vector2) -> void:
	var start_x := target.x + alert.size.x + slide_in_offset
	alert.position = Vector2(start_x, target.y)
	alert.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(alert, "position", target, enter_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(alert, "modulate:a", 1.0, enter_time)

func _schedule_exit(alert: Control) -> void:
	var timer := get_tree().create_timer(hold_time)
	timer.timeout.connect(func():
		_start_exit(alert)
	)

func _start_exit(alert: Control) -> void:
	if not _items.has(alert):
		return
	var target := alert.position + Vector2(0, -alert.size.y - spacing)
	var tween := create_tween()
	tween.tween_property(alert, "position", target, exit_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(alert, "modulate:a", 0.0, exit_time)
	tween.finished.connect(func():
		_remove_alert(alert)
	)

func _remove_alert(alert: Control) -> void:
	if _items.has(alert):
		_items.erase(alert)
	if is_instance_valid(alert):
		alert.queue_free()
	_reflow(true)

func _reflow(animate: bool, skip: Control = null) -> void:
	var y := 0.0
	for item in _items:
		if item == null:
			continue
		if item == skip:
			y += item.size.y + spacing
			continue
		var target := Vector2(-item.size.x, y)
		if animate:
			_move_item(item, target)
		else:
			item.position = target
		y += item.size.y + spacing

func _move_item(item: Control, target: Vector2) -> void:
	if item.has_meta("move_tween"):
		var tween: Tween = item.get_meta("move_tween") as Tween
		if tween != null:
			tween.kill()
	var new_tween := create_tween()
	new_tween.tween_property(item, "position", target, enter_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	item.set_meta("move_tween", new_tween)

func _calc_target_position(index: int, alert: Control) -> Vector2:
	var h := alert.size.y + spacing
	return Vector2(-alert.size.x, index * h)
