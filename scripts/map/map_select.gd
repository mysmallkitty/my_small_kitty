extends Node2D

@export var mode := "play" # "play" or "editor"
@export var map_item_scene: PackedScene = preload("res://ui/panels/map_row.tscn")
@export var row_height := 26.0
@export var scroll_step := 12.0
@export var scroll_anim_step := 1.0
@export var page_size := 20
@export var auto_load_threshold := 24.0

@onready var list_viewport: Control = get_node_or_null("UI/Hud/ListViewport") as Control
@onready var list_root: Control = get_node_or_null("UI/Hud/ListViewport/ListRoot") as Control
@onready var back_button: BaseButton = get_node_or_null("UI/Hud/Back") as BaseButton
@onready var create_button: BaseButton = get_node_or_null("UI/Hud/Back2") as BaseButton
@onready var dim: ColorRect = get_node_or_null("UI/Dim") as ColorRect
@onready var profile_panel: Control = get_node_or_null("UI/Hud/ProfilePanel") as Control
@onready var auth_panel: Control = get_node_or_null("UI/AuthPanel") as Control
@onready var profile_detail: Control = get_node_or_null("UI/UserProfileDetail") as Control

var detail_panel: Control
var detail_title: Label
var detail_creator: Label
var detail_play_count: Label
var detail_death_count: Label
var detail_clear_count: Label
var detail_upload_date: Label
var detail_difficulty_icon: TextureRect
var play_button: BaseButton
var leaderboard_button: BaseButton
var stats_button: BaseButton

var edit_button: BaseButton
var delete_button: BaseButton
var title_edit: LineEdit
var file_label: Label
var verified_label: Label

var stats_panel: Control
var stats_play_label: Label
var stats_death_label: Label
var stats_best_label: Label
var stats_close_button: BaseButton

var leaderboard_panel: Control
var leaderboard_rows: Control
var leaderboard_close_button: BaseButton
var leaderboard_empty_label: Label

var create_panel: Control
var create_title: LineEdit
var create_confirm: BaseButton
var create_close: BaseButton

var _items: Array[MapRow] = []
var _entries: Array[Dictionary] = []
var _selected_index := -1
var _scroll_offset := 0.0
var _scroll_target := 0.0
var _scroll_min := 0.0
var _page := 1
var _loading := false
var _has_more := true
var _ignore_title_signal := false
var _preview_request_id := 0

func _ready() -> void:
	Game.ensure_dirs()
	_bind_ui()
	_connect_buttons()
	_setup_profile_click()
	_refresh_list()
	set_process(true)
	_update_detail_panel()

func _process(_delta: float) -> void:
	if abs(_scroll_offset - _scroll_target) < 0.01:
		return
	_scroll_offset = _step_towards(_scroll_offset, _scroll_target, scroll_anim_step)
	_update_item_targets()

func _bind_ui() -> void:
	if detail_panel == null:
		detail_panel = get_node_or_null("UI/DetailPanel") as Control
	if detail_panel == null:
		detail_panel = get_node_or_null("UI/Hud/DetailPanel") as Control
	if mode == "play":
		_bind_play_detail_panel()
		_bind_stats_panel()
		_bind_leaderboard_panel()
	else:
		_bind_editor_detail_panel()
		_bind_create_panel()

func _bind_play_detail_panel() -> void:
	if detail_panel == null:
		return
	detail_title = detail_panel.get_node_or_null("Panel/Title") as Label
	detail_creator = detail_panel.get_node_or_null("Panel/Creator") as Label
	detail_play_count = detail_panel.get_node_or_null("Panel/PlayCount") as Label
	detail_death_count = detail_panel.get_node_or_null("Panel/DeathCount") as Label
	detail_clear_count = detail_panel.get_node_or_null("Panel/ClearCount") as Label
	detail_upload_date = detail_panel.get_node_or_null("Panel/UploadDate") as Label
	detail_difficulty_icon = detail_panel.get_node_or_null("Panel/DifficultyIcon") as TextureRect
	play_button = detail_panel.get_node_or_null("Panel/PlayButton") as BaseButton
	leaderboard_button = detail_panel.get_node_or_null("Panel/LeaderBoardButton") as BaseButton
	stats_button = detail_panel.get_node_or_null("Panel/StatsButton") as BaseButton

func _bind_editor_detail_panel() -> void:
	if detail_panel == null:
		return
	title_edit = detail_panel.get_node_or_null("Panel/Title") as LineEdit
	file_label = detail_panel.get_node_or_null("Panel/FileName") as Label
	verified_label = detail_panel.get_node_or_null("Panel/Verified") as Label
	detail_difficulty_icon = detail_panel.get_node_or_null("Panel/DifficultyIcon") as TextureRect
	play_button = detail_panel.get_node_or_null("Panel/PlayButton") as BaseButton
	edit_button = detail_panel.get_node_or_null("Panel/EditButton") as BaseButton
	delete_button = detail_panel.get_node_or_null("Panel/DeleteMap") as BaseButton

func _bind_stats_panel() -> void:
	stats_panel = get_node_or_null("UI/MapStats") as Control
	if stats_panel == null:
		stats_panel = get_node_or_null("UI/Hud/MapStats") as Control
	if stats_panel == null:
		return
	stats_play_label = stats_panel.get_node_or_null("Panel/PlayCount") as Label
	stats_death_label = stats_panel.get_node_or_null("Panel/DeathCount") as Label
	stats_best_label = stats_panel.get_node_or_null("Panel/BestTime") as Label
	stats_close_button = stats_panel.get_node_or_null("Panel/CloseButton") as BaseButton

func _bind_create_panel() -> void:
	create_panel = get_node_or_null("UI/CreateNewMap") as Control
	if create_panel == null:
		create_panel = get_node_or_null("UI/Hud/CreateNewMap") as Control
	if create_panel == null:
		return
	create_title = create_panel.get_node_or_null("LineEdit") as LineEdit
	create_confirm = create_panel.get_node_or_null("Confirm") as BaseButton
	create_close = create_panel.get_node_or_null("CloseButton") as BaseButton

func _bind_leaderboard_panel() -> void:
	leaderboard_panel = get_node_or_null("UI/LeaderBoard") as Control
	if leaderboard_panel == null:
		leaderboard_panel = get_node_or_null("UI/Hud/LeaderBoard") as Control
	if leaderboard_panel == null:
		return
	leaderboard_rows = leaderboard_panel.get_node_or_null("Panel/RecordContainer") as Control
	leaderboard_close_button = leaderboard_panel.get_node_or_null("Panel/CloseButton") as BaseButton
	leaderboard_empty_label = leaderboard_panel.get_node_or_null("Panel/no_records_yet") as Label

func _connect_buttons() -> void:
	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	if create_button != null and not create_button.pressed.is_connected(_on_create_pressed):
		create_button.pressed.connect(_on_create_pressed)
	if play_button != null and not play_button.pressed.is_connected(_on_play_pressed):
		play_button.pressed.connect(_on_play_pressed)
	if edit_button != null and not edit_button.pressed.is_connected(_on_edit_pressed):
		edit_button.pressed.connect(_on_edit_pressed)
	if delete_button != null and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)
	if leaderboard_button != null and not leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	if stats_button != null and not stats_button.pressed.is_connected(_on_stats_pressed):
		stats_button.pressed.connect(_on_stats_pressed)
	if stats_close_button != null and not stats_close_button.pressed.is_connected(_on_stats_close_pressed):
		stats_close_button.pressed.connect(_on_stats_close_pressed)
	if leaderboard_close_button != null and not leaderboard_close_button.pressed.is_connected(_on_leaderboard_close_pressed):
		leaderboard_close_button.pressed.connect(_on_leaderboard_close_pressed)
	if title_edit != null:
		if not title_edit.text_submitted.is_connected(_on_title_submitted):
			title_edit.text_submitted.connect(_on_title_submitted)
		if not title_edit.focus_exited.is_connected(_on_title_focus_exited):
			title_edit.focus_exited.connect(_on_title_focus_exited)
	if create_confirm != null and not create_confirm.pressed.is_connected(_on_create_confirm):
		create_confirm.pressed.connect(_on_create_confirm)
	if create_close != null and not create_close.pressed.is_connected(_on_create_close):
		create_close.pressed.connect(_on_create_close)
	if create_title != null and not create_title.text_submitted.is_connected(_on_create_title_submitted):
		create_title.text_submitted.connect(_on_create_title_submitted)

func _setup_profile_click() -> void:
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
	if auth_panel == null:
		return
	if auth_panel.has_method("open_login"):
		auth_panel.open_login()
	elif auth_panel.has_method("show_popup"):
		auth_panel.show_popup()
	else:
		auth_panel.visible = true

func _open_profile_detail() -> void:
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
	for child in list_root.get_children():
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
			if not file.to_lower().ends_with(".json"):
				continue
			var path := "%s/%s" % [Game.WIP_DIR, file]
			var map := MapIO.load_map(path)
			var meta := map.metadata if map != null else {}
			var title := str(meta.get("title", ""))
			if title.strip_edges() == "":
				title = "Untitled"
			entries.append({
				"title": title,
				"creator": "",
				"difficulty": int(meta.get("difficulty", 1)),
				"plays": 0,
				"deaths": 0,
				"clears": 0,
				"upload_date": "",
				"best_time": "",
				"tries": 0,
				"is_verified": bool(meta.get("is_verified", false)),
				"map_id": int(meta.get("map_id", -1)),
				"path": path,
				"bg": str(meta.get("bg", "")),
			})
		dir.list_dir_end()
	entries.sort_custom(func(a, b): return str(a.get("title", "")) < str(b.get("title", "")))
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
		var entry: Dictionary = item as Dictionary
		_entries.append({
			"id": str(entry.get("id", "")),
			"title": str(entry.get("title", "")),
			"creator": str(entry.get("creator", "")),
			"difficulty": int(entry.get("level", 1)),
			"level": int(entry.get("level", 1)),
			"plays": int(entry.get("download_count", 0)),
			"deaths": 0,
			"clears": 0,
			"upload_date": "",
			"best_time": "",
			"tries": int(entry.get("download_count", 0)),
			"is_verified": bool(entry.get("is_ranked", false)),
			"thumbnail_url": str(entry.get("thumbnail_url", "")),
			"loved_count": int(entry.get("loved_count", 0)),
			"download_count": int(entry.get("download_count", 0)),
		})
	_page += 1
	_rebuild_items()

func _rebuild_items() -> void:
	for child in list_root.get_children():
		child.queue_free()
	_items.clear()
	for entry in _entries:
		var item := map_item_scene.instantiate() as MapRow
		if item == null:
			continue
		item.set_data(entry)
		item.set_base_position(Vector2(0, _items.size() * row_height))
		item.pressed.connect(_on_item_pressed)
		list_root.add_child(item)
		_items.append(item)
	_update_scroll_limits()
	if _selected_index < 0 and _items.size() > 0:
		_selected_index = 0
		_items[0].set_selected(true)
		_center_on_selected()
	_update_detail_panel()
	_request_preview_for_selected()

func _update_scroll_limits() -> void:
	if list_viewport == null:
		return
	var max_offset = max(0.0, (_items.size() - 1) * row_height)
	_scroll_min = -max_offset
	_scroll_offset = clampf(_scroll_offset, _scroll_min, 0.0)
	_scroll_target = clampf(_scroll_target, _scroll_min, 0.0)
	_update_item_targets()

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
	if detail_panel != null:
		detail_panel.visible = _selected_index >= 0 and _selected_index < _items.size()
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	if mode == "play":
		if detail_title != null:
			detail_title.text = str(entry.get("title", ""))
		if detail_creator != null:
			detail_creator.text = str(entry.get("creator", ""))
		if detail_play_count != null:
			detail_play_count.text = str(entry.get("plays", 0))
		if detail_death_count != null:
			detail_death_count.text = str(entry.get("deaths", 0))
		if detail_clear_count != null:
			detail_clear_count.text = str(entry.get("clears", 0))
		if detail_upload_date != null:
			var date_text := str(entry.get("upload_date", ""))
			detail_upload_date.text = date_text if date_text != "" else "--"
	else:
		if title_edit != null:
			_ignore_title_signal = true
			title_edit.text = str(entry.get("title", ""))
			_ignore_title_signal = false
		if file_label != null:
			var path := str(entry.get("path", ""))
			file_label.text = path.get_file()
		if verified_label != null:
			verified_label.text = "verified" if bool(entry.get("is_verified", false)) else "unverified"
	_update_difficulty_icon(int(entry.get("difficulty", 1)))

func _update_difficulty_icon(difficulty: int) -> void:
	if detail_difficulty_icon == null:
		return
	var diff := clampi(difficulty, 1, 8)
	var path := "res://graphics/ui/16px/difficulty/%s.png" % str(diff)
	if ResourceLoader.exists(path):
		detail_difficulty_icon.texture = load(path)

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
			_merge_detail_entry(entry, detail)
			_entries[_selected_index] = entry
			_items[_selected_index].set_data(entry)
			_update_detail_panel()
		map_data = await _download_map_data(map_id)
		if request_id != _preview_request_id:
			return
	_set_background_preview(map_data)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
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
	else:
		var map_id := str(entry.get("id", ""))
		if map_id == "":
			return
		var cached := Game.get_cached_map(map_id)
		if cached != null:
			Game.current_map_data = cached
		else:
			var map_data := await _download_map_data(map_id)
			if map_data == null:
				return
			Game.cache_map(map_id, map_data)
			Game.current_map_data = map_data
		Game.current_map_id = map_id
		Game.current_map_path = ""
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
	_change_scene("res://roots/main_menu.tscn")

func _on_create_pressed() -> void:
	if create_panel == null:
		return
	if create_title != null:
		create_title.text = ""
		create_title.grab_focus()
	_show_popup(create_panel)

func _on_create_close() -> void:
	_hide_popup(create_panel)

func _on_create_confirm() -> void:
	var title := ""
	if create_title != null:
		title = create_title.text.strip_edges()
	_create_new_map(title)

func _on_create_title_submitted(new_text: String) -> void:
	_create_new_map(new_text.strip_edges())

func _on_leaderboard_pressed() -> void:
	if leaderboard_panel == null:
		return
	if leaderboard_panel.visible:
		_hide_popup(leaderboard_panel)
		return
	_hide_popup(stats_panel)
	_show_popup(leaderboard_panel)
	_load_leaderboard()

func _on_stats_pressed() -> void:
	if stats_panel == null:
		return
	if stats_panel.visible:
		_hide_popup(stats_panel)
		return
	_hide_popup(leaderboard_panel)
	_update_stats_panel()
	_show_popup(stats_panel)

func _on_stats_close_pressed() -> void:
	_hide_popup(stats_panel)

func _on_leaderboard_close_pressed() -> void:
	_hide_popup(leaderboard_panel)

func _update_stats_panel() -> void:
	var best := "--:--"
	var tries := 0
	var deaths := 0
	if _selected_index >= 0 and _selected_index < _items.size():
		var entry: Dictionary = _items[_selected_index].data
		var time := str(entry.get("best_time", ""))
		if time != "":
			best = time
		tries = int(entry.get("tries", 0))
		deaths = int(entry.get("deaths", 0))
	if stats_play_label != null:
		stats_play_label.text = str(tries)
	if stats_death_label != null:
		stats_death_label.text = str(deaths)
	if stats_best_label != null:
		stats_best_label.text = best

func _on_title_submitted(new_text: String) -> void:
	if _ignore_title_signal:
		return
	_apply_title_change(new_text)

func _on_title_focus_exited() -> void:
	if _ignore_title_signal:
		return
	if title_edit == null:
		return
	_apply_title_change(title_edit.text)

func _apply_title_change(new_text: String) -> void:
	if _selected_index < 0 or _selected_index >= _items.size():
		return
	var entry: Dictionary = _items[_selected_index].data
	var title := new_text.strip_edges()
	if title == "":
		title = "Untitled"
	entry["title"] = title
	_entries[_selected_index]["title"] = title
	_items[_selected_index].set_data(entry)
	var path := str(entry.get("path", ""))
	if path == "":
		return
	var map := MapIO.load_map(path)
	if map == null:
		return
	map.metadata["title"] = title
	MapIO.save_map(path, map, true)

func _load_leaderboard() -> void:
	if leaderboard_rows == null:
		return
	for child in leaderboard_rows.get_children():
		child.queue_free()
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
	if rows.is_empty():
		if leaderboard_empty_label != null:
			leaderboard_empty_label.visible = true
		return
	if leaderboard_empty_label != null:
		leaderboard_empty_label.visible = false
	var y := 0.0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry_dict: Dictionary = row as Dictionary
		var row_node := load("res://ui/panels/record_row.tscn").instantiate() as Control
		if row_node == null:
			continue
		row_node.position = Vector2(0, y)
		var name_label := row_node.get_node_or_null("Panel/username") as Label
		if name_label != null:
			name_label.text = str(entry_dict.get("username", entry_dict.get("name", "")))
		var time_label := row_node.get_node_or_null("Panel/HBoxContainer/ClearTime") as Label
		if time_label != null:
			time_label.text = str(entry_dict.get("clear_time", entry_dict.get("time", "")))
		var death_label := row_node.get_node_or_null("Panel/HBoxContainer/DeathCount") as Label
		if death_label != null:
			death_label.text = str(entry_dict.get("deaths", entry_dict.get("death", 0)))
		leaderboard_rows.add_child(row_node)
		y += row_node.size.y

func _show_popup(panel: Control) -> void:
	if panel == null:
		return
	if panel.has_method("show_popup"):
		panel.show_popup()
	else:
		panel.visible = true

func _hide_popup(panel: Control) -> void:
	if panel == null:
		return
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
	map.metadata["title"] = trimmed if trimmed != "" else "Untitled"
	map.metadata["map_id"] = -1
	map.metadata["difficulty"] = 1
	map.metadata["bg"] = _pick_random_bg()
	map.metadata["is_verified"] = false
	var path := _make_new_map_path()
	MapIO.save_map(path, map, true)
	_hide_popup(create_panel)
	Game.current_map_path = path
	Game.current_map_data = null
	Game.current_map_id = ""
	_change_scene("res://roots/map_editor.tscn")

func _make_new_map_path() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var name := "map_%s_%s.json" % [str(Time.get_unix_time_from_system()), str(rng.randi())]
		var path := "%s/%s" % [Game.WIP_DIR, name]
		if not FileAccess.file_exists(path):
			return path
	return "%s/map.json" % Game.WIP_DIR

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

func _fetch_map_detail(map_id: String) -> Dictionary:
	var result: Dictionary = await MapService.fetch_detail(map_id)
	if not result.get("ok", false):
		return {}
	var data = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func _download_map_data(map_id: String) -> MapData:
	var result: Dictionary = await MapService.download_map(map_id)
	if not result.get("ok", false):
		return null
	var raw_text := str(result.get("raw_text", ""))
	if raw_text.strip_edges() == "":
		var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
		raw_text = bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return MapIO.map_from_dict(parsed)

func _merge_detail_entry(entry: Dictionary, detail: Dictionary) -> void:
	entry["title"] = str(detail.get("title", entry.get("title", "")))
	entry["creator"] = str(detail.get("creator", entry.get("creator", "")))
	var level := int(detail.get("level", entry.get("level", entry.get("difficulty", 1))))
	entry["difficulty"] = level
	entry["level"] = level
	entry["is_verified"] = bool(detail.get("is_ranked", entry.get("is_verified", false)))
	entry["plays"] = int(detail.get("download_count", entry.get("plays", 0)))
	entry["tries"] = int(detail.get("total_attempts", entry.get("tries", 0)))
	entry["deaths"] = int(detail.get("total_deaths", entry.get("deaths", 0)))
	entry["clears"] = int(detail.get("total_clears", entry.get("clears", 0)))
	entry["upload_date"] = _format_date(detail.get("created_at", entry.get("upload_date", "")))
	entry["thumbnail_url"] = str(detail.get("thumbnail_url", entry.get("thumbnail_url", "")))
	entry["map_url"] = str(detail.get("map_url", entry.get("map_url", "")))

func _format_date(value: Variant) -> String:
	var text := str(value)
	if text == "":
		return ""
	var parts := text.split("T")
	if parts.size() > 0:
		return parts[0]
	return text

func _set_background_preview(map_data: MapData) -> void:
	var bg := get_node_or_null("Background")
	if bg != null and bg.has_method("set_map_data"):
		bg.set_map_data(map_data)

func _step_towards(value: float, target: float, step: float) -> float:
	if abs(target - value) <= step:
		return target
	return value + step * sign(target - value)

func _get_center_base_y() -> float:
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
