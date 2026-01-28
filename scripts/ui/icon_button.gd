@tool
class_name IconButton
extends TextureButton

@export var icon_texture: Texture2D:
	set(value):
		icon_texture = value
		_apply_icon()

@export var click_sound: AudioStreamWAV = load("res://audio/click.wav")
@export var icon_modulate_normal := Color(1, 1, 1, 1)
@export var icon_modulate_hover := Color(1.08, 1.08, 1.08, 1)
@export var icon_modulate_pressed := Color(0.8, 0.8, 0.8, 1)
@export var icon_modulate_disabled := Color(0.7, 0.7, 0.7, 1)
@export var pressed_offset := Vector2(0, 1)

var _base_position := Vector2.ZERO
var _last_state := ""
var audio_stream := AudioStreamPlayer.new()

@onready var _icon: TextureRect = get_node_or_null("Icon")

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	audio_stream.stream = click_sound
	_base_position = position
	set_process(true)
	_apply_icon()
	_apply_state(_get_state())
	pressed.connect(_pressed)
	

func _pressed() -> void:
	audio_stream.play()
	
func _process(_delta: float) -> void:
	var state := _get_state()
	if state != _last_state:
		_apply_state(state)
	if Engine.is_editor_hint():
		_apply_icon()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _last_state == "normal":
		_base_position = position

func _get_state() -> String:
	if disabled:
		return "disabled"
	if is_pressed():
		return "pressed"
	if is_hovered():
		return "hover"
	return "normal"

func _apply_state(state: String) -> void:
	_last_state = state
	var icon_color := icon_modulate_normal
	var offset := Vector2.ZERO
	match state:
		"disabled":
			icon_color = icon_modulate_disabled
			offset = pressed_offset
		"pressed":
			icon_color = icon_modulate_pressed
			offset = pressed_offset
		"hover":
			icon_color = icon_modulate_hover
	position = _base_position + offset
	if _icon != null:
		_icon.modulate = icon_color

func _apply_icon() -> void:
	if _icon == null:
		return
	_icon.texture = icon_texture
	if icon_texture != null:
		_icon.custom_minimum_size = icon_texture.get_size()
		_icon.size = _icon.custom_minimum_size
		_icon.position = (size - _icon.custom_minimum_size) * 0.5
