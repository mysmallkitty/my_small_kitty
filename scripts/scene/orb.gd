extends Area2D
class_name Orb

@export var anim: AnimatedSprite2D
@export var passive_particles: CPUParticles2D
@export var break_particles: CPUParticles2D
@export var icon: Texture2D
@export var sfx: AudioStream  = preload("res://audio/orb_hit.wav")

var sfx_player : AudioStreamPlayer
var player: Player = null
var enable = true

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	if sfx:
		sfx_player.stream = sfx
		sfx_player.bus = "sfx"
	anim.animation_finished.connect(_on_animation_finished)
	add_child(sfx_player)
	anim.stop()

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player) or not enable:
		return
	player = body
	
	if not player.is_connected("signal_grounded", _regen):
		player.connect("signal_grounded", _regen, CONNECT_ONE_SHOT)
	if not player.is_connected("signal_damaged", _regen):
		player.connect("signal_damaged", _regen, CONNECT_ONE_SHOT)
	
	
	_orb_func(player)
	if sfx:
		sfx_player.play()
	break_particles.emitting = true
	enable = false
	anim.play("break")

func _on_animation_finished() -> void:
	if anim.animation == "regen":
		player = null

func _regen() -> void:
	if anim.animation == "regen":
		return
	enable = true
	anim.play("regen")

@warning_ignore("unused_parameter")
func _orb_func(body:Player):
	pass
