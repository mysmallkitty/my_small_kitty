class_name GhostPlayer
extends CharacterBody2D

@onready var name_label: Label = $playername
@onready var death_particles: CPUParticles2D = $DeathParticles
@onready var sprite: Sprite2D = $Kitty

var _alive := true

func set_nickname(nick: String) -> void:
	if name_label != null:
		name_label.text = nick if nick.strip_edges() != "" else "(guest)"

func apply_state(pos: Vector2, dir: float = 0.0, alive: bool = true) -> void:
	global_position = pos
	if dir != 0 and sprite != null:
		sprite.scale.x = 1 if dir >= 0 else -1
	if alive and not _alive:
		_set_alive(true)
	elif not alive and _alive:
		_play_death_fx()
	_set_alive(alive)

func play_death() -> void:
	_play_death_fx()
	_set_alive(false)

func _set_alive(alive: bool) -> void:
	_alive = alive
	if sprite != null:
		var color := sprite.modulate
		color.a = 0.6 if alive else 0.25
		sprite.modulate = color

func set_sprite_texture(tex: Texture2D) -> void:
	if sprite == null or tex == null:
		return
	sprite.texture = tex

func _play_death_fx() -> void:
	if death_particles == null:
		return
	death_particles.global_position = global_position
	death_particles.emitting = false
	death_particles.restart()
	death_particles.emitting = true
