extends Node2D

@export var mode := "play" # "play" or "editor"
@export var map_item_scene: PackedScene = preload("res://ui/panels/map_row.tscn")
@export var row_height := 26.0
@export var scroll_step := 10.0
@export var scroll_anim_step := 5.0
@export var page_size := 20
@export var auto_load_threshold := 24.0

var _items: Array[MapRow] = []
var _entries: Array[Dictionary] = []
var _selected_index := -1
var _scroll_offset := 0.0
var _scroll_target := 0.0
var _scroll_min := 0.0
var _page := 1
var _loading := false
var _has_more := true
var _preview_request_id := 0

func _ready() -> void:
	Game.ensure_dirs()
	_connect_root_buttons()
	_connect_panels()
	_setup_profile_click()
	call_deferred("_refresh_me_after_play")
	_refresh_list()
	set_process(true)
	_update_detail_panel()

func _process(_delta: float) -> void:
	if abs(_scroll_offset - _scroll_target) < 0.01:
		return
	_scroll_offset = _step_towards(_scroll_offset, _scroll_target, scroll_anim_step)
	_update_item_targets()

func _connect_root_buttons() -> void:
	var back_button := get_node_or_null("UI/Hud/Back") as BaseButton
	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	var create_button := get_node_or_null("UI/Hud/Back2") as BaseButton
	if create_button != null and not create_button.pressed.is_connected(_on_create_pressed):
		create_button.pressed.connect(_on_create_pressed)

func _connect_panels() -> void:
	if mode == "play":
		var detail_panel := _get_play_detail_panel()
		if detail_panel != null:
			if not detail_panel.play_pressed.is_connected(_on_play_pressed):
				detail_panel.play_pressed.connect(_on_play_pressed)
			if not detail_panel.leaderboard_pressed.is_connected(_on_leaderboard_pressed):
				detail_panel.leaderboard_pressed.connect(_on_leaderboard_pressed)
			if not detail_panel.stats_pressed.is_connected(_on_stats_pressed):
				detail_panel.stats_pressed.connect(_on_stats_pressed)
		var stats_panel := _get_stats_panel()
		if stats_panel != null and not stats_panel.close_pressed.is_connected(_on_stats_close_pressed):
			stats_panel.close_pressed.connect(_on_stats_close_pressed)
		var leaderboard_panel := _get_leaderboard_panel()
		if leaderboard_panel != null and not leaderboard_panel.close_pressed.is_connected(_on_leaderboard_close_pressed):
			leaderboard_panel.close_pressed.connect(_on_leaderboard_close_pressed)
		if leaderboard_panel != null and not leaderboard_panel.user_selected.is_connected(_on_leaderboard_user_selected):
			leaderboard_panel.user_selected.connect(_on_leaderboard_user_selected)
	else:
		var editor_panel := _get_editor_detail_panel()
		if editor_panel != null:
			if not editor_panel.play_pressed.is_connected(_on_play_pressed):
				editor_panel.play_pressed.connect(_on_play_pressed)
			if not editor_panel.edit_pressed.is_connected(_on_edit_pressed):
				editor_panel.edit_pressed.connect(_on_edit_pressed)
			if not editor_panel.delete_pressed.is_connected(_on_delete_pressed):
				editor_panel.delete_pressed.connect(_on_delete_pressed)
			if not editor_panel.upload_pressed.is_connected(_on_upload_pressed):
				editor_panel.upload_pressed.connect(_on_upload_pressed)
			if not editor_panel.title_changed.is_connected(_on_title_changed):
				editor_panel.title_changed.connect(_on_title_changed)
		var create_panel := _get_create_panel()
		if create_panel != null:
			if create_panel.has_signal("create_requested"):
				var callable = Callable(self, "_on_create_requested")
				if not create_panel.is_connected("create_requested", callable):
					create_panel.connect("create_requested", callable, CONNECT_DEFERRED)
			if create_panel.has_signal("close_pressed"):
				var close_callable = Callable(self, "_on_create_close")
				if not create_panel.is_connected("close_pressed", close_callable):
					create_panel.connect("close_pressed", close_callable, CONNECT_DEFERRED)

func _setup_profile_click() -> void:
	var profile_panel := get_node_or_null("UI/Hud/ProfilePanel") as Control
	if profile_panel == null:
		return
	profile_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if not profile_panel.gui_input.is_connected(_on_profile_input):
		profile_panel.gui_input.connect(_on_profile_input)

func _on_profile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_logged_in():
				_open_profile_detail()
			else:
				_open_auth_panel()

func _open_auth_panel() -> void:
	var auth_panel := get_node_or_null("UI/AuthPanel") as Control
	if auth_panel == null:
		return
	if auth_panel.has_method("open_login"):
		auth_panel.open_login()
	elif auth_panel.has_method("show_popup"):
		auth_panel.show_popup()
	else:
		auth_panel.visible = true

func _open_profile_detail() -> void:
	var profile_detail := get_node_or_null("UI/UserProfileDetail") as Control
	if profile_detail == null:
		return
	if profile_detail.has_method("open_with_me"):
		profile_detail.open_with_me(_get_me_data())
	elif profile_detail.has_method("show_popup"):
		profile_detail.show_popup()
	else:
		profile_detail.visible = true

func _refresh_list() -> void:
	_items.clear()
	_entries.clear()
	_scroll_offset = 0.0
	_scroll_target = 0.0
	_selected_index = -1
	for child in _get_list_root().get_children():
		child.queue_free()
	if mode == "editor":
		_load_local_maps()
	else:
		_page = 1
		_has_more = true
		_request_next_page()

func _load_local_maps() -> void:
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(Game.WIP_DIR)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var file := dir.get_next()
			if file == "":
				break
			if dir.current_is_dir():
				continue
			var lower := file.to_lower()
			if not lower.ends_with(".kittymap"):
				continue
			var path := "%s/%s" % [Game.WIP_DIR, file]
			var map := MapIO.load_map(path)
			if map == null:
				continue
			entries.append({
				"path": path,
				"metadata": map.metadata,
			})
		dir.list_dir_end()
	entries.sort_custom(func(a, b): return _get_entry_title(a) < _get_entry_title(b))
	_entries = entries
	_rebuild_items()

func _request_next_page() -> void:
	if _loading or not _has_more:
		return
	_loading = true
	var result: Dictionary = await MapService.list_maps(_page, page_size)
	_loading = false
	if not result.get("ok", false):
		_has_more = false
		return
	var items: Array = []
	var payload = result.get("data", null)
	if typeof(payload) == TYPE_ARRAY:
		items = payload
	if items.is_empty():
		_has_more = false
		return
	if items.size() < page_size:
		_has_more = false
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_entries.append(item as Dictionary)
	_page += 1
	_rebuild_items()

func _rebuild_items() -> void:
	for child in _get_list_root().get_children():
		child.queue_free()
	_items.clear()
	for entry in _entries:
		var item := map_item_scene.instantiate() as MapRow
		if item == null:
			continue
		item.set_data(entry)
		item.set_base_position(Vector2(0, _items.size() * row_height))
		item.pressed.connect(_on_item_pressed)
		_get_list_root().add_child(item)
		_items.append(item)
	_update_scroll_limits()
	var preferred := _get_preferred_selection_index()
	if preferred >= 0:
		_selected_index = preferred
	elif _selected_index < 0 and _items.size() > 0:
		_selected_index = 0
	if _selected_index >= 0 and _selected_index < _items.size():
		_items[_selected_index].set_selected(true)
		_center_on_selected()
	_update_detail_panel()
	_request_preview_for_selected()

func _update_scroll_limits() -> void:
	var list_viewport := _get_list_viewport()
	if list_viewport == null:
		return
	var max_offset = max(0.0, (_items.size() - 1) * row_height)
	_scroll_min = -max_offset
	_scroll_offset = clampf(_scroll_offset, _scroll_min, 0.0)
	_scroll_target = clampf(_scroll_target, _scroll_min, 0.0)
	_update_item_targets()

func _get_preferred_selection_index() -> int:
	if _items.is_empty():
		return -1
	if mode == "play":
		var target_id := Game.last_play_map_id
		if target_id == "":
			target_id = Game.current_map_id
		if target_id != "":
			for i in range(_items.size()):
				if str(_items[i].data.get("id", "")) == target_id:
					return i
	else:
		var target_path := Game.last_editor_map_path
		if target_path == "":
			target_path = Game.current_map_path
		if target_path != "":
			for i in range(_items.size()):
				if str(_items[i].data.get("path", "")) == target_path:
					return i
	return -1

func _update_item_targets() -> void:
	var base_y := _get_center_base_y()
	for i in range(_items.size()):
		var item := _items[i]
		item.set_base_position(Vector2(0, base_y + (i * row_height) + _scroll_offset))

func _center_on_selected() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	_scroll_target = -(_selected_index * row_height)
	_scroll_target = clampf(_scroll_target, _scroll_min, 0.0)

func _on_item_pressed(item: MapRow) -> void:
	_selected_index = _items.find(item)
	for i in range(_items.size()):
		_items[i].set_selected(i == _selected_index)
	_center_on_selected()
	_update_detail_panel()
	_request_preview_for_selected()

func _update_detail_panel() -> void:
	var has_selection := _selected_index >= 0 and _selected_index < _items.size()
	if mode == "play":
		var panel := _get_play_detail_panel()
		if panel != null:
			panel.visible = has_selection
			if has_selection:
				panel.set_entry(_items[_selected_index].data)
		return
	var editor_panel := _get_editor_detail_panel()
	if editor_panel == null:
		return
	editor_panel.visible = has_selection
	if not has_selection:
		return
	var entry: Dictionary = _items[_selected_index].data
	var path := str(entry.get("path", ""))
	var file_name := path.get_file()
	var is_verified := false
	var can_upload := false
	if path != "":
		var map := MapIO.load_map(path)
		if map != null:
			var stored_hash := str(map.metadata.get("verified_hash", ""))
			var computed_hash := map.compute_verified_hash()
			is_verified = stored_hash != "" and stored_hash == computed_hash
			can_upload = is_verified and _is_logged_in()
	editor_panel.set_state(entry, file_name, is_verified, can_upload)

func _request_preview_for_selected() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	_preview_request_id += 1
	var request_id := _preview_request_id
	var entry: Dictionary = _items[_selected_index].data
	var map_data: MapData = null
	if mode == "editor":
		var path := str(entry.get("path", ""))
		if path != "":
			map_data = MapIO.load_map(path)
	else:
		var map_id := str(entry.get("id", ""))
		if map_id == "":
			_set_background_preview(null)
			return
		var detail := await _fetch_map_detail(map_id)
		if request_id != _preview_request_id:
			return
		if detail.size() > 0:
			_apply_detail_to_entry(entry, detail)
			_entries[_selected_index] = entry
			_items[_selected_index].set_data(entry)
			_update_detail_panel()
		map_data = await _download_preview_data(map_id, entry)
		if map_data == null:
			map_data = await _download_map_data(map_id, entry)
		if request_id != _preview_request_id:
			return
	_set_background_preview(map_data)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var list_viewport := _get_list_viewport()
			if list_viewport != null and list_viewport.get_global_rect().has_point(mb.position):
				var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_scroll_target = clampf(_scroll_target + (scroll_step * dir), _scroll_min, 0.0)
				if mode == "play" and _scroll_target <= _scroll_min + auto_load_threshold:
					_request_next_page()

func _on_play_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	if mode == "editor":
		var path := str(entry.get("path", ""))
		if path != "":
			Game.current_map_path = path
			Game.current_map_data = null
			Game.current_map_id = ""
			Game.last_editor_map_path = path
			Game.return_scene = "res://roots/map_select_editor.tscn"
			_change_scene("res://roots/map_play.tscn")
			return
	else:
		var map_id := str(entry.get("id", ""))
		if map_id == "":
			return
		var entry_data: Dictionary = _items[_selected_index].data
		entry_data = await _ensure_detail_for_entry(entry_data)
		var cached := Game.get_cached_map(map_id)
		if cached != null:
			Game.current_map_data = cached
		else:
			var map_data := await _download_map_data(map_id, entry_data)
			if map_data == null:
				return
			Game.cache_map(map_id, map_data)
			Game.current_map_data = map_data
		Game.current_map_id = map_id
		Game.current_map_path = ""
		Game.last_play_map_id = map_id
		Game.return_scene = ""
		_change_scene("res://roots/map_play.tscn")

func _on_edit_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	var path := str(entry.get("path", ""))
	if path == "":
		return
	Game.current_map_path = path
	Game.current_map_data = null
	Game.last_editor_map_path = path
	_change_scene("res://roots/map_editor.tscn")

func _on_delete_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	var path := str(entry.get("path", ""))
	if path == "":
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_refresh_list()

func _on_back_pressed() -> void:
	if mode == "play":
		Game.last_play_map_id = ""
		Game.current_map_id = ""
		Game.current_map_data = null
		Game.current_map_path = ""
	elif mode == "editor":
		Game.last_editor_map_path = ""
		Game.current_map_path = ""
		Game.current_map_data = null
		Game.current_map_id = ""
	_change_scene("res://roots/main_menu.tscn")

func _on_create_pressed() -> void:
	var create_panel := _get_create_panel()
	if create_panel == null:
		return
	if create_panel.has_method("reset_focus"):
		create_panel.reset_focus()
	_show_popup(create_panel)

func _on_create_close() -> void:
	var create_panel := _get_create_panel()
	_show_hide_popup(create_panel, false)

func _on_create_requested(title: String) -> void:
	_create_new_map(title)

func _on_leaderboard_pressed() -> void:
	var leaderboard_panel := _get_leaderboard_panel()
	if leaderboard_panel == null:
		return
	if leaderboard_panel.visible:
		_show_hide_popup(leaderboard_panel, false)
		return
	_show_hide_popup(_get_stats_panel(), false)
	_show_popup(leaderboard_panel)
	_load_leaderboard()

func _on_stats_pressed() -> void:
	var stats_panel := _get_stats_panel()
	if stats_panel == null:
		return
	if stats_panel.visible:
		_show_hide_popup(stats_panel, false)
		return
	if _selected_index >= 0 and _selected_index < _items.size():
		var entry: Dictionary = _items[_selected_index].data
		entry = await _ensure_detail_for_entry(entry)
		_items[_selected_index].set_data(entry)
	_show_hide_popup(_get_leaderboard_panel(), false)
	_update_stats_panel()
	_show_popup(stats_panel)

func _on_stats_close_pressed() -> void:
	_show_hide_popup(_get_stats_panel(), false)

func _on_leaderboard_close_pressed() -> void:
	_show_hide_popup(_get_leaderboard_panel(), false)

func _update_stats_panel() -> void:
	var stats_panel := _get_stats_panel()
	if stats_panel == null:
		return
	var best := "--:--"
	var tries := 0
	var deaths := 0
	if _selected_index >= 0 and _selected_index < _items.size():
		var entry: Dictionary = _items[_selected_index].data
		var raw_best = entry.get("best_time", null)
		if raw_best:
			best = Game._format_ticks(int(raw_best))
		tries = int(entry.get("user_attempts", entry.get("total_attempts", 0)))
		deaths = int(entry.get("user_deaths", entry.get("total_deaths", 0)))
	stats_panel.set_stats(tries, deaths, best)

func _on_title_changed(new_text: String) -> void:
	_apply_title_change(new_text)

func _apply_title_change(new_text: String) -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	var title := new_text.strip_edges()
	var meta = entry.get("metadata", null)
	if typeof(meta) == TYPE_DICTIONARY:
		meta["title"] = title
	var path := str(entry.get("path", ""))
	if path == "":
		return
	var map := MapIO.load_map(path)
	if map == null:
		return
	map.metadata["title"] = title
	MapIO.save_map(path, map)
	_items[_selected_index].set_data(entry)

func _load_leaderboard() -> void:
	var leaderboard_panel := _get_leaderboard_panel()
	if leaderboard_panel == null:
		return
	var rows: Array = []
	if mode == "play" and _selected_index >= 0 and _selected_index < _items.size():
		var entry: Dictionary = _items[_selected_index].data
		var map_id := str(entry.get("id", ""))
		if map_id != "":
			var result: Dictionary = await MapService.fetch_leaderboard(map_id)
			if result.get("ok", false):
				var data = result.get("data", null)
				if typeof(data) == TYPE_DICTIONARY:
					var items: Array = data.get("leaderboard", [])
					if typeof(items) == TYPE_ARRAY:
						rows = items
	leaderboard_panel.set_rows(rows)

func _on_leaderboard_user_selected(user_id: int) -> void:
	if user_id <= 0:
		return
	var result: Dictionary = await ApiClient.GET("/api/v1/user/%s" % str(user_id))
	if not result.get("ok", false):
		Alert.push(ApiClient._error_message(result), true)
		return
	var data = result.get("data", null)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_open_user_profile_detail(data as Dictionary)

func _refresh_me_after_play() -> void:
	if ApiClient.access_token == "":
		return
	await AuthService.me()
	for panel in get_tree().get_nodes_in_group("profile_panels"):
		if panel != null and panel.has_method("refresh_from_api"):
			panel.refresh_from_api()
	for panel in get_tree().get_nodes_in_group("user_profile_panels"):
		if panel != null and panel.has_method("refresh_from_api"):
			panel.refresh_from_api()

func _open_user_profile_detail(user: Dictionary) -> void:
	var profile_detail := get_node_or_null("UI/UserProfileDetail") as Control
	if profile_detail == null:
		return
	if profile_detail.has_method("open_with_user"):
		profile_detail.open_with_user(user)
	elif profile_detail.has_method("show_popup"):
		profile_detail.show_popup()
	else:
		profile_detail.visible = true

func _show_popup(panel: Control) -> void:
	_show_hide_popup(panel, true)

func _show_hide_popup(panel: Control, visible: bool) -> void:
	if panel == null:
		return
	if visible:
		if panel.has_method("show_popup"):
			panel.show_popup()
		else:
			panel.visible = true
	else:
		if panel.has_method("hide_popup"):
			panel.hide_popup()
		else:
			panel.visible = false

func _change_scene(path: String) -> void:
	var root := get_tree().root
	if root != null:
		var fader: Node = root.get_node_or_null("SceneFader")
		if fader != null and fader.has_method("change_scene"):
			fader.change_scene(path)
			return
	get_tree().change_scene_to_file(path)

func _create_new_map(title: String) -> void:
	if mode != "editor":
		return
	Game.ensure_dirs()
	var map := MapData.new()
	var chunk := ChunkData.new()
	chunk.id = _make_chunk_id()
	chunk.pos = Vector2i.ZERO
	chunk.size = MapData.MIN_CHUNK_SIZE
	map.chunks.append(chunk)
	map.spawn = chunk.pos + Vector2i(3, 3)
	map.start_chunk_id = chunk.id
	var trimmed := title.strip_edges()
	map.metadata["title"] = trimmed
	map.metadata["map_id"] = -1
	map.metadata["rating"] = 1
	map.metadata["bg"] = _pick_random_bg()
	map.metadata["verified_hash"] = ""
	var path := _make_new_map_path()
	MapIO.save_map(path, map)
	_show_hide_popup(_get_create_panel(), false)
	Game.current_map_path = path
	Game.current_map_data = null
	Game.current_map_id = ""
	Game.last_editor_map_path = path
	Game.return_scene = "res://roots/map_select_editor.tscn"
	_change_scene("res://roots/map_select_editor.tscn")

func _make_new_map_path() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var name := "map_%s_%s.kittymap" % [str(Time.get_unix_time_from_system()), str(rng.randi())]
		var path := "%s/%s" % [Game.WIP_DIR, name]
		if not FileAccess.file_exists(path):
			return path
	return "%s/map.kittymap" % Game.WIP_DIR

func _make_chunk_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stamp := Time.get_unix_time_from_system()
	return "%s_%s" % [str(stamp), str(rng.randi())]

func _pick_random_bg() -> String:
	var choices: Array[String] = []
	var dir := DirAccess.open("res://graphics/backgrounds")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			if name.to_lower().ends_with(".png"):
				choices.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	if choices.is_empty():
		return ""
	choices.sort()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return choices[rng.randi_range(0, choices.size() - 1)]

func _on_upload_pressed() -> void:
	if mode != "editor":
		return
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	var path_str := str(entry.get("path", ""))
	if path_str == "":
		return
	if not _is_logged_in():
		_open_auth_panel()
		return
	var map := MapIO.load_map(path_str)
	if map == null:
		Alert.push("map load failed", true)
		return
	var stored_hash := str(map.metadata.get("verified_hash", ""))
	var computed_hash := map.compute_verified_hash()
	if stored_hash == "" or stored_hash != computed_hash:
		Alert.push("map not verified", true)
		return
	var preview_map := map.make_preview_map_data(Vector2i(320, 180))
	var map_bytes := MapIO.map_to_bytes(map)
	var preview_bytes := MapIO.map_to_bytes(preview_map)
	var map_id := int(map.metadata.get("map_id", -1))
	var result: Dictionary = await MapService.upload_map(map, map_bytes, preview_bytes, map_id)
	if not result.get("ok", false):
		Alert.push(ApiClient._error_message(result), true)
		return
	if typeof(result.get("data", null)) == TYPE_DICTIONARY:
		var data: Dictionary = result.get("data", {})
		var new_id := int(data.get("id", map_id))
		if new_id > 0:
			map.metadata["map_id"] = new_id
			MapIO.save_map(path_str, map)
	Alert.push("upload complete", false)

func _fetch_map_detail(map_id: String) -> Dictionary:
	var result: Dictionary = await MapService.fetch_detail(map_id)
	if not result.get("ok", false):
		return {}
	var data = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func _download_map_data(map_id: String, entry: Dictionary) -> MapData:
	var updated_at := str(entry.get("updated_at", ""))
	var map_hash := str(entry.get("hash", ""))
	var cached := _load_cached_map(map_id, map_hash, false)
	if cached != null:
		return cached
	var result: Dictionary = await MapService.download_map(map_id)
	if not result.get("ok", false):
		return null
	var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
	if bytes.is_empty():
		return null
	var downloaded_at := str(Time.get_unix_time_from_system())
	var path := _cache_file_path(map_id, downloaded_at, false)
	if not _write_cache_file(path, bytes):
		return null
	var meta := _load_cache_meta(map_id)
	meta["updated_at"] = updated_at
	meta["hash"] = map_hash
	meta["map_path"] = path
	meta["map_downloaded_at"] = downloaded_at
	_save_cache_meta(map_id, meta)
	return MapIO.load_map(path)

func _download_preview_data(map_id: String, entry: Dictionary) -> MapData:
	var updated_at := str(entry.get("updated_at", ""))
	var map_hash := str(entry.get("hash", ""))
	var cached := _load_cached_map(map_id, map_hash, true)
	if cached != null:
		return cached
	var result: Dictionary = await MapService.download_preview(map_id)
	if not result.get("ok", false):
		return null
	var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
	if bytes.is_empty():
		return null
	var downloaded_at := str(Time.get_unix_time_from_system())
	var path := _cache_file_path(map_id, downloaded_at, true)
	if not _write_cache_file(path, bytes):
		return null
	var meta := _load_cache_meta(map_id)
	meta["updated_at"] = updated_at
	meta["hash"] = map_hash
	meta["preview_path"] = path
	meta["preview_downloaded_at"] = downloaded_at
	_save_cache_meta(map_id, meta)
	return MapIO.load_map(path)

func _cache_meta_path(map_id: String) -> String:
	return "%s/%s.json" % [Game.CACHE_META_DIR, map_id]

func _load_cache_meta(map_id: String) -> Dictionary:
	var path := _cache_meta_path(map_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

func _save_cache_meta(map_id: String, data: Dictionary) -> void:
	var path := _cache_meta_path(map_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, ""))
	file.close()

func _cache_file_path(map_id: String, downloaded_at: String, is_preview: bool) -> String:
	var base := Game.PREVIEW_CACHE_DIR if is_preview else Game.MAP_CACHE_DIR
	var suffix := "_preview" if is_preview else ""
	return "%s/%s_%s%s.kittymap" % [base, map_id, downloaded_at, suffix]

func _write_cache_file(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true

func _load_cached_map(map_id: String, map_hash: String, is_preview: bool) -> MapData:
	var meta := _load_cache_meta(map_id)
	var meta_hash := str(meta.get("hash", ""))
	if meta_hash != map_hash:
		return null
	var key := "preview_path" if is_preview else "map_path"
	var path := str(meta.get(key, ""))
	if path == "" or not FileAccess.file_exists(path):
		return null
	return null

func _ensure_detail_for_entry(entry: Dictionary) -> Dictionary:
	if str(entry.get("updated_at", "")) == "":
		var map_id := str(entry.get("id", ""))
		if map_id != "":
			var detail := await _fetch_map_detail(map_id)
			if detail.size() > 0:
				_apply_detail_to_entry(entry, detail)
	return entry

func _apply_detail_to_entry(entry: Dictionary, detail: Dictionary) -> void:
	for key in ["title", "creator", "rating", "total_attempts", "total_deaths", "total_clears", "created_at", "updated_at", "thumbnail_url", "map_url", "hash", "is_ranked", "loved_count", "user_attempts", "user_deaths", "best_time", "is_loved"]:
		if detail.has(key):
			entry[key] = detail.get(key)

func _set_background_preview(map_data: MapData) -> void:
	var bg := get_node_or_null("Background")
	if bg != null and bg.has_method("set_map_data"):
		bg.set_map_data(map_data)

func _step_towards(value: float, target: float, step: float) -> float:
	if abs(target - value) <= step:
		return target
	return value + step * sign(target - value)

func _get_center_base_y() -> float:
	var list_viewport := _get_list_viewport()
	if list_viewport == null:
		return 0.0
	return (list_viewport.size.y * 0.5) - (row_height * 0.5)

func _is_logged_in() -> bool:
	return ApiClient.access_token != "" and not _get_me_data().is_empty()

func _get_me_data() -> Dictionary:
	var me = ApiClient.me
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
			return me.get("data", {})
		return me
	return {}

func _get_list_root() -> Control:
	return get_node("UI/Hud/ListViewport/ListRoot") as Control

func _get_list_viewport() -> Control:
	return get_node("UI/Hud/ListViewport") as Control

func _get_play_detail_panel() -> MapSelectDetailPlay:
	return get_node_or_null("UI/Hud/DetailPanel") as MapSelectDetailPlay

func _get_editor_detail_panel() -> MapSelectDetailEditor:
	return get_node_or_null("UI/Hud/DetailPanel") as MapSelectDetailEditor

func _get_stats_panel() -> MapSelectStatsPanel:
	return get_node_or_null("UI/MapStats") as MapSelectStatsPanel

func _get_leaderboard_panel() -> MapSelectLeaderboardPanel:
	return get_node_or_null("UI/LeaderBoard") as MapSelectLeaderboardPanel

func _get_create_panel() -> Control:
	var panel := get_node_or_null("UI/CreateNewMap") as Control
	if panel == null:
		panel = get_node_or_null("UI/Hud/CreateNewMap") as Control
	if panel == null:
		panel = find_child("CreateNewMap", true, false) as Control
	return panel

func _get_entry_title(entry: Dictionary) -> String:
	var meta = entry.get("metadata", null)
	if typeof(meta) == TYPE_DICTIONARY:
		var title := str(meta.get("title", ""))
		return title
	return str(entry.get("title", ""))
