class_name InfoSign
extends Node2D

@export var fade_in_time := 0.15
@export var fade_out_time := 0.25
@export var default_text := ""
@export var icon : Texture

@onready var label: Label = $Label
@onready var area: Area2D = $Area2D

var _tween: Tween

func _ready() -> void:
	if label != null:
		label.visible = false
		label.modulate.a = 0.0
		if default_text != "":
			label.text = default_text
	if area != null:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

func apply_map_entry(entry: Dictionary) -> void:
	if label == null:
		return
	var data := {}
	if entry.has("data") and typeof(entry["data"]) == TYPE_DICTIONARY:
		data = entry["data"]
	var text := str(data.get("text", ""))
	if text == "":
		text = default_text
	label.text = text

func set_text(value: String) -> void:
	if label != null:
		label.text = value

func _on_body_entered(_body: Node) -> void:
	if _body is Player:
		label.visible = true
		_fade_to(1.0, fade_in_time)

func _on_body_exited(_body: Node) -> void:
	if _body is Player:
		_fade_to(0.0, fade_out_time)

func _fade_to(target: float, duration: float) -> void:
	if label == null:
		return
	if _tween != null:
		_tween.kill()
	label.visible = true
	_tween = create_tween()
	_tween.tween_property(label, "modulate:a", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func():
		if target <= 0.0:
			label.visible = false
	)
