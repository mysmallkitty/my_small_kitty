extends Area2D
class_name TileObg

@export var sprite: AnimatedSprite2D
@export var icon: Texture2D
@export var sfx: AudioStream
@export var regen_on_grounded = true
@export var regenable = true

var sfx_player : AudioStreamPlayer
var player: Player = null
var enable = true

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	body_entered.connect(_on_body_entered)
	if sfx:
		sfx_player.stream = sfx
		sfx_player.bus = "sfx"
	sprite.animation_finished.connect(_on_animation_finished)
	add_child(sfx_player)
	sprite.stop()

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player) or not enable:
		return
	player = body

	if not player.is_connected("signal_grounded", _regen):
		player.connect("signal_grounded", _regen, CONNECT_ONE_SHOT)
	if not player.is_connected("signal_damaged", _regen):
		player.connect("signal_damaged", _regen, CONNECT_ONE_SHOT)
	_func(player)
	if sfx:
		sfx_player.play()
	enable = false
	sprite.play("active")

func _on_animation_finished() -> void:
	if sprite.animation == "regen":
		player = null

func _regen() -> void:
	if sprite.animation == "regen":
		return
	enable = true
	sprite.play("regen")

@warning_ignore("unused_parameter")
func _func(body:Player):
	pass
