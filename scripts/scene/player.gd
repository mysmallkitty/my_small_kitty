class_name Player
extends CharacterBody2D

@export var move_speed := 50.0
@export var jump_speed := 130.0
@export var gravity := 340.0
@export var coyote_time := 0.12
@export var jump_buffer := 10.0

@export var dash_speed := 120.0
@export var dash_time := 0.25
@export var dash_gravity_scale := 0
@export var dash_lift_accel := 0
@export var wall_climb_speed := 50.0
@export var wall_slide_gravity_mult := 0.5

@export var ground_accel := 2000.0
@export var air_accel := 900.0

@export var dash_post_jump_window_frames_at_60: int = 5
@export var dash_jump_boost_mult :=  1.7
@export var dash_jump_boost_add := 0.0

@export var editor_mode: bool = false
@export var jump_sfx: AudioStream = preload("res://audio/jump.wav")
@export var hyper_sfx: AudioStream = preload("res://audio/hyper.wav")
@export var dash_sfx: AudioStream = preload("res://audio/dash.wav")

signal signal_damaged
signal signal_grounded
signal signal_respawn
signal signal_complete

var _dash_vel: Vector2
var _vel: Vector2
var _on_floor_timer := 0.0
var _jump_buffer_timer := 0.0
var _has_air_jump := true

var _is_dashing := false
var _dash_timer := 0.0
var _has_dash := false
var dir_look := 1.0

var _post_dash_jump_timer := 0.0
var _post_dash_dir := 1.0

@warning_ignore("unused_private_class_variable")
var _checkpoint_pos: Vector2 = Vector2.ZERO

var _jump_player: AudioStreamPlayer
var _hyper_player: AudioStreamPlayer
var _dash_player: AudioStreamPlayer
var _death_pixels: CPUParticles2D

@export var collision_shape: CollisionShape2D
@export var hazard_mask: int = 1 << 1
@export var object_mask: int = 3 << 3

func _dash_post_jump_window_sec() -> float:
	return float(dash_post_jump_window_frames_at_60) / 60.0

func _is_overlapping_hazard() -> bool:
	if collision_shape == null or collision_shape.shape == null:
		return false

	var space_state := get_world_2d().direct_space_state

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape.shape
	params.transform = collision_shape.global_transform
	params.collision_mask = hazard_mask
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [self]

	var hits := space_state.intersect_shape(params, 1)
	return hits.size() > 0

func _is_overlapping_object() -> bool:
	if collision_shape == null or collision_shape.shape == null:
		return false

	var space_state := get_world_2d().direct_space_state

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape.shape
	params.transform = collision_shape.global_transform
	params.collision_mask = object_mask
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [self]

	var hits := space_state.intersect_shape(params, 1)
	return hits.size() > 0

func _ready() -> void:
	_setup_sfx()
	_setup_death_pixels()

func _setup_sfx() -> void:
	if jump_sfx != null:
		_jump_player = AudioStreamPlayer.new()
		_jump_player.bus = "sfx"
		_jump_player.stream = jump_sfx
		add_child(_jump_player)

	if dash_sfx != null:
		_dash_player = AudioStreamPlayer.new()
		_dash_player.bus = "sfx"
		_dash_player.stream = dash_sfx
		add_child(_dash_player)
	
	if hyper_sfx != null:
		_hyper_player = AudioStreamPlayer.new()
		_hyper_player.bus = "sfx"
		_hyper_player.stream = hyper_sfx
		add_child(_hyper_player)
		

func _setup_death_pixels() -> void:
	_death_pixels = get_node_or_null("DeathPixels") as CPUParticles2D
	if _death_pixels == null:
		return
	if _death_pixels.texture != null:
		return

	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_death_pixels.texture = ImageTexture.create_from_image(image)

func _die() -> void:
	signal_damaged.emit()

func _respawn() -> void:
	signal_damaged.emit()
	

func _input(event):
	if editor_mode:
		return

	if event.is_action_pressed("player_jump"):
		_jump_buffer_timer = jump_buffer

	if event.is_action_pressed("player_dash") and (not _is_dashing) and _has_dash:
		_start_dash()
		_has_dash = false

func _unhandled_input(event):
	if editor_mode:
		return

	if event.is_action_released("player_jump") and _vel.y < 0:
		_vel.y *= 0.55

func _physics_process(delta):
	if editor_mode:
		return

	var input_dir := Input.get_action_strength("player_right") - Input.get_action_strength("player_left")
	if input_dir < 0.0:
		dir_look = -1.0
	elif input_dir > 0.0:
		dir_look = 1.0

	$Kitty.scale.x = dir_look

	_handle_timers(delta)

	if _is_dashing:
		_dash_step(delta)
		_consume_jump_buffer_while_dashing()
	else:
		_air_ground_step(delta)

	_apply_move()

	if _is_overlapping_hazard():
		_die()

func _handle_timers(delta: float) -> void:

	if is_on_floor():
		signal_grounded.emit()
		_has_dash = true
		_on_floor_timer = coyote_time
		_has_air_jump = true
	else:
		_on_floor_timer = max(0.0, _on_floor_timer - delta)
	
	if is_on_wall():
		var dir = Input.get_action_strength("player_right") - Input.get_action_strength("player_left")
		if abs(dir) > 0:
			pass

	_jump_buffer_timer = max(0.0, _jump_buffer_timer - delta)

	_post_dash_jump_timer = max(0.0, _post_dash_jump_timer - delta)

	if _is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_end_dash(true)

func _consume_jump_buffer_while_dashing() -> void:
	if _jump_buffer_timer <= 0.0:
		return

	var can_ground_jump := _on_floor_timer > 0.0
	var can_air_jump := _has_air_jump
	if not (can_ground_jump or can_air_jump):
		return

	_jump_buffer_timer = 0.0
	_jump(can_air_jump and not can_ground_jump)

func complete_map() -> void:
	emit_signal("signal_complete")

func _air_ground_step(delta: float) -> void:
	_vel.y -= gravity * delta * up_direction.y

	var dir := Input.get_action_strength("player_right") - Input.get_action_strength("player_left")
	var target_x := move_speed * dir

	if is_on_floor():
		_vel.x = move_toward(_vel.x, target_x, ground_accel * delta)
	else:
		_vel.x = move_toward(_vel.x, target_x, air_accel * delta)

	if _jump_buffer_timer > 0.0:
		if _on_floor_timer > 0.0:
			_jump_buffer_timer = 0.0
			_jump(false)
		elif _has_air_jump:
			_jump_buffer_timer = 0.0
			_jump(true)

func _start_dash() -> void:
	_is_dashing = true
	_dash_timer = dash_time

	_dash_vel = Vector2(dash_speed * dir_look, 0.0)

	_post_dash_jump_timer = 0.0

	_play_dash_sfx()

func _dash_step(delta: float) -> void:
	_dash_vel.x = dash_speed * dir_look
	_dash_vel.y += (gravity * - dash_gravity_scale + dash_lift_accel) * delta * up_direction.y

func _end_dash(start_post_window: bool) -> void:
	_is_dashing = false
	_dash_timer = 0.0

	if start_post_window:
		_post_dash_jump_timer = _dash_post_jump_window_sec()
		_post_dash_dir = dir_look

func _jump(is_air_jump: bool) -> void:
	if _post_dash_jump_timer > 0.0 && (Input.get_action_strength("player_right") - Input.get_action_strength("player_left") != 0): # do hyper jump
		_post_dash_jump_timer = 0.0
		var boosted_x := (dash_speed * dash_jump_boost_mult) + dash_jump_boost_add
		_vel.x = boosted_x * _post_dash_dir
		_play_hyper_sfx()
		_vel.y = (jump_speed / 2) * up_direction.y
	else:
		if _is_dashing:
			_end_dash(false)
			_vel.x = 0.0
		_play_jump_sfx()
		_vel.y = jump_speed * up_direction.y

	if is_air_jump:
		_has_air_jump = false
	

func _apply_move() -> void:
	if _is_dashing:
		velocity = _dash_vel
	else:
		velocity = _vel
	move_and_slide()
	_vel = velocity

func _play_jump_sfx() -> void:
	if _jump_player != null:
		_jump_player.play()

func _play_hyper_sfx() -> void:
	if _jump_player != null:
		_hyper_player.play()

func _play_dash_sfx() -> void:
	if _dash_player != null:
		_dash_player.play()
