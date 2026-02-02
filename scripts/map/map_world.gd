extends Node2D

@export var map_path := ""
@export var player_scene: PackedScene = preload("res://objs/player.tscn")
@export var ghost_scene: PackedScene = preload("res://objs/ghost_player.tscn")
@export var tile_set: TileSet = preload("res://objs/tiles.tres")
@export var camera_zoom := Vector2(1, 1)
@export var camera_transition_time := 0.25
@export var debug_draw_chunks := false
@export var death_fade_time := 0.2
@export var death_fade_hold := 0.2
@export var death_fade_delay := 0.7

var accum_rate = 0.015
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
var clear_panel: Control
var clear_death_label: Label
var clear_time_label: Label
var clear_button: BaseButton
var ws: WsSession
var ghosts: Dictionary = {}
var _net_accum := 0.0
var _name_cache: Dictionary = {}
var _name_fetching: Dictionary = {}
var _chat_scene: PackedScene = preload("res://scripts/scene/chat.tscn")
var _chat_line: LineEdit
var _chat_open := false
@onready var _total_death_label := $UI/Hud/TotalDeath
@onready var _clear_time_label := $UI/Hud/ClearTime

var _has_checkpoint := false
var _awaiting_first_step := false
var _pending_chunk_id := ""
var _camera_transition_left := 0.0
var _camera_transition_from := Vector2.ZERO
var _respawning := false
var _map_cleared := false

var _total_death = 0
var _cleartime = 0

var _death_streams: Array[AudioStream] = [
	preload("res://audio/player/cat_cry0.wav"),
	preload("res://audio/player/cat_cry1.wav"),
	preload("res://audio/player/cat_cry2.wav"),
	preload("res://audio/player/cat_cry3.wav"),
]

func _ready() -> void:
	process_priority = 10
	_load_map()
	if Game.current_map_id != "":
		Game.last_play_map_id = Game.current_map_id
	_setup_renderer()
	_spawn_player()
	_setup_camera()
	_setup_background()
	_setup_death_fx()
	_setup_pause_menu()
	_setup_clear_panel()
	_setup_chat_ui()
	_setup_network()
	_update_current_chunk()
	queue_redraw()

func _process(delta: float) -> void:
	if player == null or map_data == null:
		return
	_update_current_chunk()
	_update_checkpoint_on_first_step()
	_update_camera(delta)
	_apply_boundary_rules()
	_update_network(delta)
	if debug_draw_chunks:
		queue_redraw()

func _physics_process(_delta):
	if _map_cleared:
		return
	if player:
		_cleartime += 1
	_clear_time_label.text = Game._format_ticks(_cleartime)

func _unhandled_input(event: InputEvent) -> void:
	if _handle_chat_input(event):
		return
	if _chat_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
	if event.is_action_pressed("key_reload"):
		_on_pause_restart()

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
	elif map_path.strip_edges() == "":
		if Game.current_map_path != "":
			map_path = Game.current_map_path
		elif Game.last_editor_map_path != "":
			map_path = Game.last_editor_map_path
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
	_clear_chat_container(player)
	player.signal_damaged.connect(_respawn)
	player.signal_complete.connect(_on_map_cleared)
	_apply_local_player_sprite()
	var spawn_chunk := _get_start_chunk()
	current_chunk = spawn_chunk
	player.global_position = _spawn_position()
	if spawn_chunk != null:
		_awaiting_first_step = false
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
	_refresh_death_particles()
	if death_sfx == null:
		death_sfx = AudioStreamPlayer.new()
		death_sfx.bus = "sfx"
		add_child(death_sfx)

func _refresh_death_particles() -> void:
	death_particles.clear()
	if player == null:
		return
	var main_particles := player.get_node_or_null("DeathParticles") as CPUParticles2D
	if main_particles != null:
		death_particles.append(main_particles)
	var pixel_particles := player.get_node_or_null("DeathPixels") as CPUParticles2D
	if pixel_particles != null:
		death_particles.append(pixel_particles)

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


func _setup_clear_panel() -> void:
	var ui_layer := get_node_or_null("UI") as CanvasLayer
	if ui_layer == null:
		return
	var panel_scene := load("res://ui/panels/level_cleared_panel.tscn")
	if not (panel_scene is PackedScene):
		return
	clear_panel = (panel_scene as PackedScene).instantiate() as Control
	if clear_panel == null:
		return
	clear_panel.visible = false
	ui_layer.add_child(clear_panel)
	clear_panel.position = (get_viewport_rect().size - clear_panel.size) * 0.5
	clear_death_label = clear_panel.get_node_or_null("Panel/TotalDeath") as Label
	clear_time_label = clear_panel.get_node_or_null("Panel/ClearTime") as Label
	clear_button = clear_panel.get_node_or_null("Panel/IconButton") as BaseButton
	if clear_button != null and not clear_button.pressed.is_connected(_on_clear_panel_continue):
		clear_button.pressed.connect(_on_clear_panel_continue)



func _setup_chat_ui() -> void:
	_chat_line = get_node_or_null("UI/ChatLineEdit") as LineEdit
	if _chat_line == null:
		return
	_chat_line.visible = false
	_chat_line.text = ""
	_chat_line.focus_mode = Control.FOCUS_ALL
	if not _chat_line.text_submitted.is_connected(_on_chat_submit):
		_chat_line.text_submitted.connect(_on_chat_submit)

func _handle_chat_input(event: InputEvent) -> bool:
	if _chat_line == null:
		return false
	var key_event := event as InputEventKey
	if key_event == null:
		return false
	if key_event.echo:
		return false
	if key_event.pressed and key_event.keycode == KEY_ENTER:
		if not _chat_open:
			_open_chat()
		return true
	if _chat_open and key_event.pressed and key_event.keycode == KEY_ESCAPE:
		_close_chat()
		return true
	return false

func _open_chat() -> void:
	_chat_open = true
	_chat_line.visible = true
	_chat_line.text = ""
	_chat_line.grab_focus()
	if player != null:
		player.editor_mode = true

func _close_chat() -> void:
	if _chat_line == null:
		return
	_chat_open = false
	_chat_line.visible = false
	_chat_line.text = ""
	_chat_line.release_focus()
	if player != null:
		player.editor_mode = false

func _send_chat_message() -> void:
	if _chat_line == null:
		return
	var msg := _chat_line.text.strip_edges()
	if msg == "":
		return
	_add_chat_bubble(player, msg)
	if ws != null and ws.is_ready():
		ws.send_chat(msg)
	_close_chat()

func _on_chat_submit(text: String) -> void:
	if not _chat_open:
		return
	_chat_line.text = text
	_send_chat_message()

func _add_chat_bubble(target: Node, text: String) -> void:
	if target == null or _chat_scene == null:
		return
	var container := target.get_node_or_null("ChatContainer") as VBoxContainer
	if container == null:
		return
	var bubble := _chat_scene.instantiate() as Label
	if bubble == null:
		return
	bubble.text = text
	container.add_child(bubble)
	while container.get_child_count() > 3:
		var child := container.get_child(0)
		child.queue_free()
func _clear_chat_container(target: Node) -> void:
	if target == null:
		return
	var container := target.get_node_or_null("ChatContainer") as VBoxContainer
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _update_current_chunk() -> void:
	if not player:
		return
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
	var has_up := map_data.get_adjacent_chunk_for_tile(current_chunk, tile_pos, Vector2i.UP) != null
	
	var pos := player.global_position
	var clamped := pos
	if not has_left and pos.x < rect.position.x:
		clamped.x = rect.position.x
	if not has_right and pos.x > rect.position.x + rect.size.x:
		clamped.x = rect.position.x + rect.size.x
	if not has_down and player.up_direction.y <= 0 and pos.y > rect.position.y + rect.size.y + MapData.TILE_SIZE:
		player._die()
		return
	if not has_up and player.up_direction.y >= 0 and pos.y < rect.position.y - MapData.TILE_SIZE:
		player._die()
		return

	if clamped != pos:
		player.global_position = clamped
		_reset_player_velocity()

func _respawn() -> void:
	if _respawning:
		return
	_respawning = true
	_total_death += 1
	_total_death_label.text = str(_total_death)
	if ws != null and ws.is_ready():
		ws.send_death(player.dir_look)
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
	_replace_player(respawn_pos, used_checkpoint)
	if current_chunk == _get_start_chunk():
		_cleartime = 0
		_total_death = 0
		_total_death_label.text = str(_total_death)
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


func _replace_player(respawn_pos: Vector2, used_checkpoint: bool) -> void:
	if player != null:
		player.queue_free()
		player = null
	if player_scene == null:
		return
	var instance := player_scene.instantiate()
	player = instance as Player
	if player == null:
		instance.queue_free()
		return
	add_child(player)
	player.editor_mode = true
	player.z_index = 10
	player.signal_damaged.connect(_respawn)
	player.signal_complete.connect(_on_map_cleared)
	_apply_local_player_sprite()
	player.global_position = respawn_pos
	player.velocity = Vector2.ZERO
	if used_checkpoint:
		player._checkpoint_pos = respawn_pos
	_refresh_death_particles()
func _on_map_cleared() -> void:
	if _map_cleared:
		return
	_map_cleared = true
	if player != null:
		player.editor_mode = true
		player.velocity = Vector2.ZERO
	if map_data != null:
		map_data.metadata["verified_hash"] = map_data.compute_verified_hash()
		if map_path.strip_edges() != "":
			MapIO.save_map(map_path, map_data)
	_update_clear_panel()
	if ws != null and ws.is_ready():
		ws.send_clear(_cleartime, _total_death)
	if clear_panel != null:
		clear_panel.visible = true

func _update_clear_panel() -> void:
	if clear_death_label != null:
		clear_death_label.text = str(_total_death)
	if clear_time_label != null:
		clear_time_label.text = _format_clear_time(_cleartime)

func _format_clear_time(frames: int) -> String:
	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	if ticks <= 0:
		ticks = 60
	var total_seconds := frames / float(ticks)
	var minutes := int(total_seconds / 60)
	var seconds := int(total_seconds) % 60
	var frac := frames % ticks
	return "%02d:%02d:%02d" % [minutes, seconds, frac]

func _on_clear_panel_continue() -> void:
	_return_to_play_select()

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
	_return_to_play_select()

func _return_to_play_select() -> void:
	if ws != null:
		ws.close()
	var target := "res://roots/map_select_play.tscn"
	if Game.return_scene != "":
		target = Game.return_scene
		Game.return_scene = ""
		if target == "res://roots/map_editor.tscn":
			Game.current_map_data = null
			Game.current_map_id = ""
		elif target == "res://roots/map_select_editor.tscn":
			Game.current_map_data = null
			Game.current_map_id = ""
			Game.current_map_path = ""
		else:
			Game.current_map_data = null
			Game.current_map_path = ""
			Game.current_map_id = ""
	else:
		Game.current_map_data = null
		Game.current_map_path = ""
		Game.current_map_id = ""
	_change_scene(target)

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

func _setup_network() -> void:
	if Game.current_map_id == "":
		return
	ws = WsSession.new()
	add_child(ws)
	ws.peer_joined.connect(_on_peer_joined)
	ws.peer_left.connect(_on_peer_left)
	ws.peer_state.connect(_on_peer_state)
	ws.peer_death.connect(_on_peer_death)
	ws.chat_message.connect(_on_chat_message)
	var pid := _normalize_user_id(_resolve_player_id())
	ws.connect_map(Game.current_map_id, pid)

func _update_network(delta: float) -> void:
	if ws == null or player == null:
		return
	_net_accum += delta
	if _net_accum >= accum_rate and ws.is_ready():
		_net_accum = 0.0
		ws.send_state(player.global_position, player.dir_look)

func _resolve_player_id() -> String:
	var me = ApiClient.me
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("id"):
			return str(me.get("id"))
		if me.has("user_id"):
			return str(me.get("user_id"))
	return "guest-%s" % str(Time.get_unix_time_from_system())

func _on_peer_joined(peer_id: String) -> void:
	var pid := _normalize_user_id(peer_id)
	_spawn_ghost(pid, _cached_name(pid))
	_ensure_name_async(pid)

func _on_peer_left(peer_id: String) -> void:
	var pid := _normalize_user_id(peer_id)
	if ghosts.has(pid):
		var g: Node = ghosts[pid]
		if g != null:
			g.queue_free()
		ghosts.erase(pid)

func _on_peer_state(peer_id: String, pos: Vector2, dir: float = 0.0) -> void:
	var pid := _normalize_user_id(peer_id)
	var ghost = _spawn_ghost(pid, _cached_name(pid))
	if ghost != null:
		ghost.apply_state(pos, dir, true)
		_ensure_name_async(pid)

func _on_peer_death(peer_id: String) -> void:
	var pid := _normalize_user_id(peer_id)
	var ghost = ghosts.get(pid, null)
	if ghost != null:
		ghost.play_death()

func _on_chat_message(peer_id: String, text: String) -> void:
	var pid := _normalize_user_id(peer_id)
	var target: Node = ghosts.get(pid, null)
	if target == null and pid == _normalize_user_id(_resolve_player_id()):
		target = player
	if target == null:
		target = _spawn_ghost(pid, _cached_name(pid))
	_add_chat_bubble(target, text)
	_ensure_name_async(pid)


func _spawn_ghost(peer_id: String, nickname: String) -> GhostPlayer:
	if ghost_scene == null:
		return null
	var pid := _normalize_user_id(peer_id)
	if ghosts.has(pid):
		return ghosts[pid]
	var inst := ghost_scene.instantiate()
	var ghost := inst as GhostPlayer
	if ghost == null:
		inst.queue_free()
		return null
	add_child(ghost)
	_clear_chat_container(ghost)
	ghost.z_index = 5
	ghost.set_nickname(nickname)
	ghosts[pid] = ghost
	return ghost


func _ensure_name_async(user_id: String) -> void:
	var uid := _normalize_user_id(user_id)
	if _name_cache.has(uid):
		return
	if _name_fetching.has(uid):
		return
	if uid.begins_with("guest-"):
		_name_cache[uid] = "(guest)"
		return
	_name_fetching[uid] = true
	await _do_fetch_user_name(uid)

func _fetch_user_name(user_id: String) -> void:
	await _do_fetch_user_name(_normalize_user_id(user_id))

func _do_fetch_user_name(user_id: String) -> void:
	var uid := _normalize_user_id(user_id)
	var url := "/api/v1/user/%s" % uid
	var result: Dictionary = await ApiClient.GET(url)
	var _name := "(guest)"
	if result.get("ok", false) and typeof(result.get("data", null)) == TYPE_DICTIONARY:
		var data: Dictionary = result.get("data", {})
		_name = str(data.get("username", data.get("name", _name)))
		var sprite_code := str(data.get("player_sprite", ""))
		var g = ghosts.get(uid, null)
		if g != null and g.has_method("set_sprite_texture"):
			g.set_sprite_texture(Game.get_player_texture(sprite_code))
	_name_cache[uid] = _name
	_name_fetching.erase(uid)
	var g = ghosts.get(uid, null)
	if g != null:
		g.set_nickname(_name)

func _apply_local_player_sprite() -> void:
	if player == null:
		return
	var me = ApiClient.me
	if typeof(me) != TYPE_DICTIONARY:
		return
	var data: Dictionary = {}
	if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
		data = me.get("data", {})
	else:
		data = me
	var sprite_code := str(data.get("player_sprite", ""))
	var tex := Game.get_player_texture(sprite_code)
	if tex != null and player.has_method("set_sprite_texture"):
		player.set_sprite_texture(tex)

func _cached_name(user_id: String) -> String:
	var uid := _normalize_user_id(user_id)
	return str(_name_cache.get(uid, "(guest)"))

func _normalize_user_id(user_id: String) -> String:
	var uid := str(user_id)
	if uid.ends_with(".0"):
		return uid.substr(0, uid.length() - 2)
	return uid
