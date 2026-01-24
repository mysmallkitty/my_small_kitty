extends Node2D

@export var map_path := ""
@export var player_scene: PackedScene = preload("res://objs/player.tscn")
@export var tile_set: TileSet = preload("res://objs/tiles.tres")
@export var camera_zoom := Vector2(1, 1)
@export var camera_transition_time := 0.25
@export var debug_draw_chunks := false
@export var death_fade_time := 0.2
@export var death_fade_hold := 0.2
@export var death_fade_delay := 0.7

var map_data: MapData
var current_chunk: ChunkData
var player: Player
var camera: Camera2D
var renderer: MapRenderer
var background: MapBackground
var pause_menu: Control
var pause_continue: BaseButton
var pause_respawn: BaseButton
var pause_restart: BaseButton
var pause_quit: BaseButton
var pause_dim: ColorRect
var death_fade: ColorRect
var death_particles: Array[CPUParticles2D] = []
var death_sfx: AudioStreamPlayer
var _has_checkpoint := false
var _awaiting_first_step := false
var _pending_chunk_id := ""
var _camera_transition_left := 0.0
var _camera_transition_from := Vector2.ZERO
var _respawning := false

var _total_death = 0
var _playtime = 0

var _death_streams: Array[AudioStream] = [
	preload("res://audio/player/cat_cry0.wav"),
	preload("res://audio/player/cat_cry1.wav"),
	preload("res://audio/player/cat_cry2.wav"),
	preload("res://audio/player/cat_cry3.wav"),
]

func _ready() -> void:
	process_priority = 10
	_load_map()
	_setup_renderer()
	_spawn_player()
	_setup_camera()
	_setup_background()
	_setup_death_fx()
	_setup_pause_menu()
	_update_current_chunk()
	queue_redraw()

func _process(delta: float) -> void:
	if player == null or map_data == null:
		return
	_update_current_chunk()
	_update_checkpoint_on_first_step()
	_update_camera(delta)
	_apply_boundary_rules()
	if debug_draw_chunks:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _draw() -> void:
	if not debug_draw_chunks or map_data == null:
		return
	var start_chunk := _get_start_chunk()
	for chunk in map_data.chunks:
		var rect := _chunk_rect_pixels(chunk)
		var color := Color(0.3, 0.6, 1.0, 0.8)
		if chunk == current_chunk:
			color = Color(1.0, 0.8, 0.2, 0.9)
		draw_rect(rect, color, false, 1.0)
		if chunk == start_chunk:
			var spawn_px := Vector2(map_data.spawn) * MapData.TILE_SIZE
			draw_rect(Rect2(spawn_px, Vector2(MapData.TILE_SIZE * 2, MapData.TILE_SIZE * 2)), color, false, 1.0)

func _load_map() -> void:
	if Game.current_map_data != null:
		map_data = Game.current_map_data
	elif map_path.strip_edges() == "" and Game.current_map_path != "":
		map_path = Game.current_map_path
	if map_data == null and map_path.strip_edges() != "":
		map_data = MapIO.load_map(map_path)
	if map_data == null:
		map_data = MapData.create_debug()
	var spawn_chunk := map_data.get_chunk_at_tile(map_data.spawn)
	if spawn_chunk != null:
		map_data.start_chunk_id = spawn_chunk.id

func _setup_renderer() -> void:
	if tile_set == null or map_data == null:
		return
	renderer = MapRenderer.new()
	renderer.z_index = -100
	renderer.tile_set = tile_set
	add_child(renderer)
	renderer.render_map(map_data)

func _setup_background() -> void:
	background = get_node_or_null("Background") as MapBackground
	if background == null:
		return
	background.set_map_data(map_data)
	if camera != null:
		background.set_follow_camera(camera)

func _spawn_player() -> void:
	if player_scene == null:
		return
	var instance := player_scene.instantiate()
	player = instance as Player
	if player == null:
		instance.queue_free()
		return
	add_child(player)
	player.editor_mode = false
	player.z_index = 10
	player.signal_damaged.connect(_respawn)
	var spawn_chunk := _get_start_chunk()
	current_chunk = spawn_chunk
	player.global_position = _spawn_position()
	if spawn_chunk != null:
		_awaiting_first_step = true
		_pending_chunk_id = spawn_chunk.id

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = camera_zoom
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()

func _setup_death_fx() -> void:
	death_fade = get_node_or_null("UI/DeathFade") as ColorRect
	if death_fade != null:
		death_fade.color = Color(0, 0, 0, 0)
	death_particles.clear()
	if player != null:
		var main_particles := player.get_node_or_null("DeathParticles") as CPUParticles2D
		if main_particles != null:
			death_particles.append(main_particles)
		var pixel_particles := player.get_node_or_null("DeathPixels") as CPUParticles2D
		if pixel_particles != null:
			death_particles.append(pixel_particles)
	death_sfx = AudioStreamPlayer.new()
	death_sfx.bus = "sfx"
	add_child(death_sfx)

func _setup_pause_menu() -> void:
	pause_menu = get_node_or_null("UI/PauseMenu") as Control
	pause_dim = get_node_or_null("UI/Dim") as ColorRect
	if pause_menu == null:
		return
	pause_menu.top_level = true
	pause_continue = pause_menu.get_node_or_null("Button") as BaseButton
	pause_respawn = pause_menu.get_node_or_null("Button3") as BaseButton
	pause_restart = pause_menu.get_node_or_null("Button2") as BaseButton
	pause_quit = pause_menu.get_node_or_null("Button4") as BaseButton
	for button in [pause_continue, pause_respawn, pause_restart, pause_quit]:
		if button != null:
			button.focus_mode = Control.FOCUS_ALL
	if pause_continue != null and not pause_continue.pressed.is_connected(_on_pause_continue):
		pause_continue.pressed.connect(_on_pause_continue)
	if pause_respawn != null and not pause_respawn.pressed.is_connected(_on_pause_respawn):
		pause_respawn.pressed.connect(_on_pause_respawn)
	if pause_restart != null and not pause_restart.pressed.is_connected(_on_pause_restart):
		pause_restart.pressed.connect(_on_pause_restart)
	if pause_quit != null and not pause_quit.pressed.is_connected(_on_pause_quit):
		pause_quit.pressed.connect(_on_pause_quit)

func _update_current_chunk() -> void:
	var tile_pos := _world_to_tile(player.global_position)
	var found := map_data.get_chunk_at_tile(tile_pos)
	if found == null:
		return
	if found != current_chunk:
		current_chunk = found
		_awaiting_first_step = true
		_pending_chunk_id = found.id
		_start_camera_transition()

func _update_camera(delta: float) -> void:
	if current_chunk == null:
		return
	var rect := _chunk_rect_pixels(current_chunk)
	var view_size := get_viewport_rect().size / camera.zoom
	var half_view := view_size * 0.5
	var target := player.global_position
	var min_pos := rect.position + half_view
	var max_pos := rect.position + rect.size - half_view
	if min_pos.x > max_pos.x:
		target.x = rect.position.x + rect.size.x * 0.5
	else:
		target.x = clamp(target.x, min_pos.x, max_pos.x)
	var y_slack := rect.size.y - view_size.y
	if y_slack > 0.0 and y_slack < MapData.TILE_SIZE:
		target.y = max_pos.y
	elif min_pos.y > max_pos.y:
		target.y = rect.position.y + rect.size.y * 0.5
	else:
		target.y = clamp(target.y, min_pos.y, max_pos.y)
	if camera_transition_time <= 0.0:
		camera.global_position = target
		return
	if _camera_transition_left > 0.0:
		_camera_transition_left = max(0.0, _camera_transition_left - delta)
		var t := 1.0 - (_camera_transition_left / camera_transition_time)
		t = _ease_out(t)
		camera.global_position = _camera_transition_from.lerp(target, t)
	else:
		camera.global_position = target

func _start_camera_transition() -> void:
	if camera == null or camera_transition_time <= 0.0:
		return
	_camera_transition_left = camera_transition_time
	_camera_transition_from = camera.global_position

func _ease_out(value: float) -> float:
	var t = float(clamp(value, 0.0, 1.0))
	return 1.0 - pow(1.0 - t, 3.0)

func _apply_boundary_rules() -> void:
	if current_chunk == null:
		return
	var rect := _chunk_rect_pixels(current_chunk)
	var tile_pos := _world_to_tile(player.global_position)
	var has_left := map_data.get_adjacent_chunk_for_tile(current_chunk, tile_pos, Vector2i.LEFT) != null
	var has_right := map_data.get_adjacent_chunk_for_tile(current_chunk, tile_pos, Vector2i.RIGHT) != null
	var has_down := map_data.get_adjacent_chunk_for_tile(current_chunk, tile_pos, Vector2i.DOWN) != null

	var pos := player.global_position
	var clamped := pos
	if not has_left and pos.x < rect.position.x:
		clamped.x = rect.position.x
	if not has_right and pos.x > rect.position.x + rect.size.x:
		clamped.x = rect.position.x + rect.size.x
	if not has_down and pos.y > rect.position.y + rect.size.y + MapData.TILE_SIZE:
		player._die()
		return

	if clamped != pos:
		player.global_position = clamped
		_reset_player_velocity()

func _respawn() -> void:
	if _respawning:
		return
	_respawning = true
	if player != null:
		player.editor_mode = true
		player.velocity = Vector2.ZERO
		_set_player_sprite_alpha(0.0)
	_play_death_fx()
	if death_fade_delay > 0.0:
		await get_tree().create_timer(death_fade_delay).timeout
	await _fade_death(1.0)
	var respawn_chunk: ChunkData = null
	var respawn_pos := Vector2.ZERO
	var used_checkpoint := false
	if _has_checkpoint:
		var tile_pos := _world_to_tile(player._checkpoint_pos)
		respawn_chunk = map_data.get_chunk_at_tile(tile_pos)
		if respawn_chunk != null:
			respawn_pos = player._checkpoint_pos
			used_checkpoint = true
	if respawn_chunk == null:
		respawn_chunk = _get_start_chunk()
		respawn_pos = _spawn_position()
	current_chunk = respawn_chunk
	player.global_position = respawn_pos
	_reset_player_velocity()
	if used_checkpoint:
		_awaiting_first_step = false
		_pending_chunk_id = ""
	else:
		if respawn_chunk != null:
			_awaiting_first_step = true
			_pending_chunk_id = respawn_chunk.id
	await _fade_death(0.0)
	if player != null:
		player.editor_mode = false
		_set_player_sprite_alpha(1.0)
	_respawning = false

func _reset_player_velocity() -> void:
	if player == null:
		return
	player.velocity = Vector2.ZERO

func _update_checkpoint_on_first_step() -> void:
	if not _awaiting_first_step:
		return
	if player == null or current_chunk == null:
		return
	if current_chunk.id != _pending_chunk_id:
		return
	if not player.is_on_floor():
		return
	var foot_tile := _world_to_tile(player.global_position) + Vector2i(0, 1)
	var spawn_tile := foot_tile + Vector2i(0, -1)
	player._checkpoint_pos = Vector2(spawn_tile) * MapData.TILE_SIZE
	_has_checkpoint = true
	_awaiting_first_step = false

func _get_start_chunk() -> ChunkData:
	if map_data == null:
		return null
	var start_chunk := map_data.get_chunk_by_id(map_data.start_chunk_id)
	if start_chunk == null and map_data.chunks.size() > 0:
		start_chunk = map_data.chunks[0]
	return start_chunk

func _spawn_position() -> Vector2:
	if map_data == null:
		return Vector2.ZERO
	return Vector2(map_data.spawn) * MapData.TILE_SIZE

func _chunk_rect_pixels(chunk: ChunkData) -> Rect2:
	return Rect2(Vector2(chunk.pos) * MapData.TILE_SIZE, Vector2(chunk.size) * MapData.TILE_SIZE)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / MapData.TILE_SIZE), floor(world_pos.y / MapData.TILE_SIZE))

func _play_death_fx() -> void:
	_play_death_sound()
	_emit_death_particles()

func _emit_death_particles() -> void:
	if death_particles.is_empty() or player == null:
		return
	for particles in death_particles:
		if particles == null:
			continue
		particles.global_position = player.global_position
		particles.emitting = false
		particles.restart()
		particles.emitting = true

func _play_death_sound() -> void:
	if death_sfx == null:
		return
	if _death_streams.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	death_sfx.stream = _death_streams[rng.randi_range(0, _death_streams.size() - 1)]
	death_sfx.play()

func _fade_death(alpha: float) -> void:
	if death_fade == null:
		return
	var tween := create_tween()
	tween.tween_property(death_fade, "color:a", alpha, death_fade_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if alpha >= 1.0 and death_fade_hold > 0.0:
		await get_tree().create_timer(death_fade_hold).timeout

func _toggle_pause() -> void:
	if _respawning:
		return
	var paused := not get_tree().paused
	_set_paused(paused)

func _set_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	get_tree().paused = paused
	if pause_menu != null:
		pause_menu.visible = paused
		if paused and pause_continue != null:
			pause_continue.grab_focus()
	if pause_dim != null:
		pause_dim.visible = paused
		pause_dim.color = Color(0, 0, 0, 0.5) if paused else Color(0, 0, 0, 0)

func _on_pause_continue() -> void:
	_set_paused(false)

func _on_pause_respawn() -> void:
	_set_paused(false)
	_respawn()

func _on_pause_restart() -> void:
	_has_checkpoint = false
	_set_paused(false)
	_respawn()

func _on_pause_quit() -> void:
	_set_paused(false)
	_change_scene("res://roots/map_select_play.tscn")

func _change_scene(path: String) -> void:
	var root := get_tree().root
	if root != null:
		var fader: Node = root.get_node_or_null("SceneFader")
		if fader != null and fader.has_method("change_scene"):
			fader.change_scene(path)
			return
	get_tree().change_scene_to_file(path)

func _set_player_sprite_alpha(alpha: float) -> void:
	if player == null:
		return
	var sprite := player.get_node_or_null("Kitty") as Sprite2D
	if sprite == null:
		return
	var color := sprite.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	sprite.modulate = color
