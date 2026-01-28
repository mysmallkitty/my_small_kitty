class_name MapEditor
extends Node2D

enum Tool {
	PEN,
	RECT,
}

const ICON_PEN := preload("res://graphics/ui/16px/editor/tools/pen.png")
const ICON_RECT := preload("res://graphics/ui/16px/editor/tools/square.png")
const ICON_CHUNK := preload("res://graphics/ui/16px/editor/tools/chunk.png")
const ICON_CHUNK_ADD := preload("res://graphics/ui/16px/editor/tools/chunk_add.png")
const ICON_CHUNK_REMOVE := preload("res://graphics/ui/16px/editor/tools/chunk_remove.png")
const ICON_BACK := preload("res://graphics/ui/16px/nav_prev.png")

const CHUNK_HANDLE_SIZE := 6.0
const CHUNK_HANDLE_HIT := 10.0
const INVALID_TILE := Vector2i(999999, 999999)

@export var tile_set: TileSet = preload("res://objs/tiles.tres")
@export var map_path: String = ""
@export var scene_tile_paths: Array[String] = []
@export var palette_button_scene: PackedScene
@export var spawn_scene: PackedScene = preload("res://objs/spawnpoint.tscn")
@export var debug_palette_log := true
@export var preview_alpha := 0.45
@export var grid_color := Color(0.2, 0.2, 0.2, 0.35)
@export var chunk_color := Color(0.3, 0.6, 1.0, 0.9)
@export var chunk_selected_color := Color(1.0, 0.8, 0.2, 0.95)
@export var zoom_min := 0.5
@export var zoom_max := 4.0
@export var zoom_step := 0.1
@export var palette_cell_size := 8
@export var palette_padding := 2

var map_data: MapData
var catalog: TileCatalog
var palette_root: Control

@onready var camera: Camera2D = $EditorCamera
@onready var renderer: MapRenderer = $Renderer
@onready var preview_layer: TileMapLayer = $PreviewLayer
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: Control = $UI/Hud
@onready var palette_panel: Control = $UI/Hud/Pallete
@onready var background_sprite: Sprite2D = $EditorCamera/Fallback
@onready var pen_button: BaseButton = get_node_or_null("UI/Hud/Tools/PenButton") as BaseButton
@onready var rect_button: BaseButton = get_node_or_null("UI/Hud/Tools/SquareButton") as BaseButton
@onready var chunk_toggle: BaseButton = get_node_or_null("UI/Hud/Tools/ChunkButton") as BaseButton
@onready var save_button: BaseButton = get_node_or_null("UI/Hud/SaveButton") as BaseButton
@onready var menu_button: BaseButton = get_node_or_null("UI/Hud/MenuButton") as BaseButton
@onready var editor_menu: Control = get_node_or_null("UI/EditorMenu") as Control
@onready var editor_menu_title: LineEdit = get_node_or_null("UI/EditorMenu/Panel/Title") as LineEdit
@onready var editor_menu_save: BaseButton = get_node_or_null("UI/EditorMenu/Panel/SaveQuitButton") as BaseButton
@onready var editor_menu_quit: BaseButton = get_node_or_null("UI/EditorMenu/Panel/QuitButton") as BaseButton
@onready var editor_menu_close: BaseButton = get_node_or_null("UI/EditorMenu/CloseButton") as BaseButton
@onready var editor_menu_diff_down: BaseButton = get_node_or_null("UI/EditorMenu/DifficultyDownButton") as BaseButton
@onready var editor_menu_diff_up: BaseButton = get_node_or_null("UI/EditorMenu/DifficultyUpButton") as BaseButton
@onready var editor_menu_bg_prev: BaseButton = get_node_or_null("UI/EditorMenu/BGPrevButton") as BaseButton
@onready var editor_menu_bg_next: BaseButton = get_node_or_null("UI/EditorMenu/BGNextButton") as BaseButton
@onready var editor_menu_diff_icon: TextureRect = get_node_or_null("UI/EditorMenu/DifficultyIcon") as TextureRect

var tool := Tool.PEN
var selected_layer := ""
var selected_source_id := TileCatalog.INVALID_SOURCE
var selected_atlas := Vector2i.ZERO
var selected_alt := 0
var selected_scene_path := ""
var rotate_steps := 0
var flip_h := false
var flip_v := false

var is_painting := false
var paint_button := MOUSE_BUTTON_LEFT
var rect_active := false
var rect_start := Vector2i.ZERO
var rect_end := Vector2i.ZERO
var last_paint_tile := INVALID_TILE

var chunk_edit_mode := false
var selected_chunk: ChunkData
var dragging_chunk := false
var drag_start_tile := Vector2i.ZERO
var drag_chunk_origin := Vector2i.ZERO
var drag_chunk_size := Vector2i.ZERO
var resizing_chunk := false
var resize_handle := ""
var _renderer_dirty := false
var _terrain_dirty_min := Vector2i.ZERO
var _terrain_dirty_max := Vector2i.ZERO
var _terrain_dirty_valid := false

var undo_stack: Array[Dictionary] = []
var undo_limit := 50
var current_save_path := ""
var spawn_node: Node2D
var dragging_spawn := false
var spawn_drag_offset := Vector2i.ZERO
var _bg_list: Array[String] = []
var _bg_index := 0

func _ready() -> void:
	process_priority = 20
	_load_map()
	_setup_camera()
	_setup_renderer()
	_setup_preview_layer()
	_setup_spawn()
	_connect_ui()
	_build_palette()
	_bg_list = _load_background_list()
	_apply_background_selection()
	_sync_editor_menu()
	queue_redraw()

func _process(_delta: float) -> void:
	_update_preview()
	_update_background_layout()
	if _renderer_dirty:
		_renderer_dirty = false
		_refresh_renderer()
	queue_redraw()

func _draw() -> void:
	return

func _input(event: InputEvent) -> void:
	if _ui_blocks_input(event):
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)

func _ui_blocks_input(event: InputEvent) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	if editor_menu != null and editor_menu.visible:
		return true
	if event is InputEventKey:
		var focus := viewport.gui_get_focus_owner()
		if focus != null and focus is LineEdit and focus.is_visible_in_tree():
			return true
		return false
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var hovered := viewport.gui_get_hovered_control()
		if hovered != null and hovered.is_visible_in_tree():
			if hud != null and hovered != hud and hud.is_ancestor_of(hovered):
				return true
	return false

func _load_map() -> void:
	if map_path.strip_edges() == "" and Game.current_map_path != "":
		map_path = Game.current_map_path
	if map_path.strip_edges() != "":
		map_data = MapIO.load_map(map_path)
		current_save_path = map_path
	if map_data == null:
		map_data = MapData.new()
		var chunk := ChunkData.new()
		chunk.id = _make_chunk_id()
		chunk.pos = Vector2i.ZERO
		chunk.size = MapData.MIN_CHUNK_SIZE
		map_data.chunks.append(chunk)
		map_data.spawn = chunk.pos + Vector2i(3, 3)
		map_data.start_chunk_id = chunk.id
		var bg_name := _pick_random_bg()
		if bg_name != "":
			map_data.metadata["bg"] = bg_name
	_sync_start_chunk_from_spawn()
	_remove_spawn_entries()

func _setup_camera() -> void:
	if camera == null:
		return
	camera.position_smoothing_enabled = false
	camera.make_current()

func _setup_renderer() -> void:
	if renderer == null:
		return
	renderer.z_index = -100
	if background_sprite != null:
		background_sprite.z_index = -200
	renderer.tile_set = tile_set
	renderer.render_map(map_data)

func _setup_preview_layer() -> void:
	if preview_layer == null:
		return
	preview_layer.tile_set = tile_set
	preview_layer.z_index = 100
	preview_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_layer.modulate = Color(1, 1, 1, preview_alpha)

func _setup_spawn() -> void:
	if spawn_scene == null:
		return
	if spawn_node != null:
		spawn_node.queue_free()
	var instance := spawn_scene.instantiate()
	if instance is Node2D:
		spawn_node = instance as Node2D
		spawn_node.z_index = 150
		add_child(spawn_node)
		_update_spawn_node()

func _update_spawn_node() -> void:
	if spawn_node == null or map_data == null:
		return
	spawn_node.position = Vector2(map_data.spawn) * MapData.TILE_SIZE

func _set_spawn(tile_pos: Vector2i) -> void:
	if map_data == null:
		return
	map_data.spawn = tile_pos
	_update_spawn_node()
	_sync_start_chunk_from_spawn()

func _sync_start_chunk_from_spawn() -> void:
	if map_data == null:
		return
	var chunk: ChunkData = map_data.get_chunk_at_tile(map_data.spawn)
	if chunk != null:
		map_data.start_chunk_id = chunk.id
	elif map_data.chunks.size() > 0:
		map_data.start_chunk_id = map_data.chunks[0].id
		_set_spawn(_clamp_spawn_to_chunk(map_data.spawn, map_data.chunks[0]))

func _clamp_spawn_to_chunk(tile_pos: Vector2i, chunk: ChunkData) -> Vector2i:
	if chunk == null:
		return tile_pos
	var min_x := chunk.pos.x
	var min_y := chunk.pos.y
	var max_x := chunk.pos.x + chunk.size.x - 2
	var max_y := chunk.pos.y + chunk.size.y - 2
	return Vector2i(clampi(tile_pos.x, min_x, max_x), clampi(tile_pos.y, min_y, max_y))

func _is_in_spawn_area(tile_pos: Vector2i) -> bool:
	if map_data == null:
		return false
	return tile_pos.x >= map_data.spawn.x and tile_pos.y >= map_data.spawn.y \
		and tile_pos.x < map_data.spawn.x + 2 and tile_pos.y < map_data.spawn.y + 2

func _remove_spawn_entries() -> void:
	if map_data == null or spawn_scene == null:
		return
	var spawn_path := spawn_scene.resource_path
	if spawn_path == "":
		return
	var object_entries: Array = map_data.layers.get("object", [])
	for i in range(object_entries.size() - 1, -1, -1):
		var entry = object_entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("scene", "")) == spawn_path:
			object_entries.remove_at(i)
	map_data.layers["object"] = object_entries

func _connect_ui() -> void:
	if pen_button != null and rect_button != null:
		var tool_group := ButtonGroup.new()
		pen_button.button_group = tool_group
		rect_button.button_group = tool_group
		pen_button.toggle_mode = true
		rect_button.toggle_mode = true
		pen_button.button_pressed = true
		if not pen_button.toggled.is_connected(_on_pen_toggled):
			pen_button.toggled.connect(_on_pen_toggled)
		if not rect_button.toggled.is_connected(_on_rect_toggled):
			rect_button.toggled.connect(_on_rect_toggled)
		if not pen_button.pressed.is_connected(_on_new_chunk_pressed):
			pen_button.pressed.connect(_on_new_chunk_pressed)
		if not rect_button.pressed.is_connected(_on_chunk_delete_pressed):
			rect_button.pressed.connect(_on_chunk_delete_pressed)
	if save_button != null and not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if chunk_toggle != null and not chunk_toggle.toggled.is_connected(_on_chunk_edit_toggled):
		chunk_toggle.toggle_mode = true
		chunk_toggle.toggled.connect(_on_chunk_edit_toggled)
	if menu_button != null and not menu_button.pressed.is_connected(_on_menu_pressed):
		menu_button.pressed.connect(_on_menu_pressed)
	_connect_editor_menu()
	_update_chunk_ui()

func _connect_editor_menu() -> void:
	if editor_menu == null:
		return
	editor_menu.visible = false
	if editor_menu_save != null and not editor_menu_save.pressed.is_connected(_on_menu_save_quit):
		editor_menu_save.pressed.connect(_on_menu_save_quit)
	if editor_menu_quit != null and not editor_menu_quit.pressed.is_connected(_on_menu_quit):
		editor_menu_quit.pressed.connect(_on_menu_quit)
	if editor_menu_close != null and not editor_menu_close.pressed.is_connected(_on_menu_close):
		editor_menu_close.pressed.connect(_on_menu_close)
	if editor_menu_title != null and not editor_menu_title.text_changed.is_connected(_on_menu_title_changed):
		editor_menu_title.text_changed.connect(_on_menu_title_changed)
	if editor_menu_diff_down != null and not editor_menu_diff_down.pressed.is_connected(_on_menu_diff_down):
		editor_menu_diff_down.pressed.connect(_on_menu_diff_down)
	if editor_menu_diff_up != null and not editor_menu_diff_up.pressed.is_connected(_on_menu_diff_up):
		editor_menu_diff_up.pressed.connect(_on_menu_diff_up)
	if editor_menu_bg_prev != null and not editor_menu_bg_prev.pressed.is_connected(_on_menu_bg_prev):
		editor_menu_bg_prev.pressed.connect(_on_menu_bg_prev)
	if editor_menu_bg_next != null and not editor_menu_bg_next.pressed.is_connected(_on_menu_bg_next):
		editor_menu_bg_next.pressed.connect(_on_menu_bg_next)

func _build_palette() -> void:
	if tile_set == null:
		return
	catalog = TileCatalog.build(tile_set)
	if debug_palette_log:
		_log_palette_sources()
	_build_palette_all()

func _build_palette_all() -> void:
	var root := _get_palette_root()
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()
	var buttons: Array[Dictionary] = []
	_append_palette_tiles(buttons, "terrain", "terrain", true)
	_append_palette_tiles(buttons, "block", "block")
	_append_palette_tiles(buttons, "hazard", "hazard")
	_append_palette_tiles(buttons, "deco", "deco")
	_append_palette_scenes(buttons, "object")
	_layout_palette_buttons(root, buttons)

func _log_palette_sources() -> void:
	if tile_set == null:
		print("Palette: tile_set is null.")
		return
	print("Palette: source_count=", tile_set.get_source_count())
	var prefixes := ["terrain", "block", "hazard", "deco", "object"]
	for prefix in prefixes:
		var names: Array = []
		if catalog != null and catalog.sources_by_prefix.has(prefix):
			names = catalog.sources_by_prefix[prefix]
		print("Palette prefix ", prefix, ": ", names)
		for source_name in names:
			var source_id := catalog.get_source_id(str(source_name))
			var coords := _get_source_coords(source_id)
			print("  - ", str(source_name), " id=", source_id, " coords=", coords)
	if not scene_tile_paths.is_empty():
		print("Palette object tiles: ", scene_tile_paths)

func _append_palette_tiles(out: Array[Dictionary], prefix: String, layer_name: String, single_tile: bool = false) -> void:
	if catalog == null:
		return
	var source_names: Array = []
	if catalog.sources_by_prefix.has(prefix):
		source_names = catalog.sources_by_prefix[prefix]
	for source_name in source_names:
		var source_id := catalog.get_source_id(str(source_name))
		if source_id == TileCatalog.INVALID_SOURCE:
			continue
		var source = tile_set.get_source(source_id)
		if source is TileSetScenesCollectionSource:
			continue
		var coords_list := _get_source_coords(source_id)
		if single_tile and coords_list.size() > 1:
			coords_list = [coords_list[0]]
		for atlas_coords in coords_list:
			var button := _make_tile_button(source_id, atlas_coords)
			if button == null:
				continue
			button.pressed.connect(_on_tile_button_pressed.bind(layer_name, source_id, atlas_coords))
			out.append({
				"button": button,
				"size": Vector2i.ONE,
			})

func _append_palette_scenes(out: Array[Dictionary], prefix: String) -> void:
	if tile_set == null or catalog == null:
		return
	var added_paths: Dictionary = {}
	var source_names: Array = []
	if catalog.sources_by_prefix.has(prefix):
		source_names = catalog.sources_by_prefix[prefix]
	for source_name in source_names:
		var source_id := catalog.get_source_id(str(source_name))
		if source_id == TileCatalog.INVALID_SOURCE:
			continue
		var source := tile_set.get_source(source_id)
		if not (source is TileSetScenesCollectionSource):
			continue
		var scene_source := source as TileSetScenesCollectionSource
		var count := int(scene_source.get_scene_tiles_count())
		for i in range(count):
			var tile_id := scene_source.get_scene_tile_id(i)
			var packed := scene_source.get_scene_tile_scene(tile_id)
			if not (packed is PackedScene):
				continue
			var scene_path := (packed as PackedScene).resource_path
			if scene_path == "" or added_paths.has(scene_path):
				continue
			var placeholder: Texture2D = null
			if packed:
				var raw_placeholder = packed.instantiate()
				if raw_placeholder.icon is Texture2D:
					placeholder = raw_placeholder.icon
			var button := _make_scene_button(scene_path, placeholder)
			button.pressed.connect(_on_scene_button_pressed.bind(scene_path))
			out.append({
				"button": button,
				"size": Vector2i.ONE,
			})
			added_paths[scene_path] = true
	for scene_path in scene_tile_paths:
		if scene_path == "" or added_paths.has(scene_path):
			continue
		var button := _make_scene_button(scene_path, null)
		button.pressed.connect(_on_scene_button_pressed.bind(scene_path))
		out.append({
			"button": button,
			"size": Vector2i.ONE,
		})
		added_paths[scene_path] = true

func _get_palette_root() -> Control:
	if palette_root != null:
		return palette_root
	if palette_panel == null:
		return null
	var existing := palette_panel.get_node_or_null("PaletteGrid") as Control
	if existing == null:
		existing = palette_panel.get_node_or_null("GridContainer") as Control
	if existing == null:
		existing = palette_panel.get_node_or_null("PaletteRoot") as Control
	if existing != null:
		palette_root = existing
		return palette_root
	var root := Control.new()
	root.name = "PaletteRoot"
	root.size = palette_panel.size
	palette_panel.add_child(root)
	palette_root = root
	return palette_root

func _layout_palette_buttons(root: Control, buttons: Array[Dictionary]) -> void:
	if root == null:
		return
	var cell = max(1, palette_cell_size)
	var cols = max(1, int(floor(root.size.x / float(cell + palette_padding))))
	var occupied: Array = []
	for entry in buttons:
		var button: BaseButton = entry.get("button", null)
		if button == null:
			continue
		var size_cells: Vector2i = entry.get("size", Vector2i.ONE)
		var slot := _find_palette_slot(occupied, cols, size_cells)
		var pos := Vector2(slot.x * (cell + palette_padding), slot.y * (cell + palette_padding))
		var size := Vector2(size_cells.x * cell, size_cells.y * cell)
		button.position = pos
		button.custom_minimum_size = size
		button.size = size
		root.add_child(button)

func _find_palette_slot(occupied: Array, cols: int, size_cells: Vector2i) -> Vector2i:
	var rows := occupied.size()
	if rows == 0:
		rows = 1
		occupied.append(_make_palette_row(cols))
	for y in range(rows + 64):
		if y >= occupied.size():
			occupied.append(_make_palette_row(cols))
		for x in range(cols):
			if _palette_fits(occupied, cols, Vector2i(x, y), size_cells):
				_mark_palette(occupied, cols, Vector2i(x, y), size_cells)
				return Vector2i(x, y)
	return Vector2i.ZERO

func _make_palette_row(cols: int) -> Array:
	var row: Array = []
	for _i in range(cols):
		row.append(false)
	return row

func _palette_fits(occupied: Array, cols: int, pos: Vector2i, size_cells: Vector2i) -> bool:
	for y in range(size_cells.y):
		var row_idx := pos.y + y
		if row_idx >= occupied.size():
			return false
		for x in range(size_cells.x):
			var col_idx := pos.x + x
			if col_idx >= cols:
				return false
			var row: Array = occupied[row_idx]
			if row[col_idx]:
				return false
	return true

func _mark_palette(occupied: Array, cols: int, pos: Vector2i, size_cells: Vector2i) -> void:
	for y in range(size_cells.y):
		var row_idx := pos.y + y
		while row_idx >= occupied.size():
			occupied.append(_make_palette_row(cols))
		var row: Array = occupied[row_idx]
		for x in range(size_cells.x):
			var col_idx := pos.x + x
			if col_idx < cols:
				row[col_idx] = true


func _make_scene_button(scene_path: String, icon: Texture2D) -> BaseButton:
	var button := _instantiate_palette_button()
	var icon_rect := button.get_node_or_null("Icon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = icon
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var size := Vector2(MapData.TILE_SIZE, MapData.TILE_SIZE)
		icon_rect.custom_minimum_size = size
		icon_rect.size = size
		if icon != null:
			print("hello")
			pass
	button.tooltip_text = scene_path.get_file()
	return button

func _make_tile_button(source_id: int, atlas_coords: Vector2i) -> BaseButton:
	var source = tile_set.get_source(source_id)
	if source == null:
		return null
	var texture: Texture2D = null
	var region := Rect2i(Vector2i.ZERO, Vector2i.ONE)
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		texture = atlas_source.texture
		var region_size: Vector2i = atlas_source.texture_region_size
		region = Rect2i(atlas_coords * region_size, region_size)
	var icon: Texture2D = texture
	if texture != null:
		var atlas_tex := AtlasTexture.new()
		atlas_tex.atlas = texture
		atlas_tex.region = region
		icon = atlas_tex
	var button := _instantiate_palette_button()
	var icon_rect := button.get_node_or_null("Icon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = icon
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var size := Vector2(MapData.TILE_SIZE, MapData.TILE_SIZE)
		icon_rect.custom_minimum_size = size
		icon_rect.size = size
	return button

func _encode_tile_flags() -> int:
	var flags := rotate_steps & 3
	if flip_h:
		flags |= 4
	if flip_v:
		flags |= 8
	return flags

func _get_preview_alt_id(flags: int) -> int:
	if renderer == null:
		return 0
	return renderer.get_alt_id_for_flags(selected_source_id, selected_atlas, flags)

func _instantiate_palette_button() -> BaseButton:
	if palette_button_scene != null:
		var instance = palette_button_scene.instantiate()
		if instance is BaseButton:
			return instance
	var fallback := TextureButton.new()
	fallback.focus_mode = Control.FOCUS_NONE
	fallback.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fallback.stretch_mode = TextureButton.STRETCH_KEEP
	fallback.custom_minimum_size = Vector2(8, 8)
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
	fallback.add_child(icon_rect)
	return fallback

func _get_source_coords(source_id: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var source = tile_set.get_source(source_id)
	if source == null:
		return coords
	if source is TileSetAtlasSource:
		var atlas_source := source as TileSetAtlasSource
		if atlas_source.has_method("get_tiles_count") and atlas_source.has_method("get_tile_id"):
			var count := int(atlas_source.get_tiles_count())
			for i in range(count):
				var tile_id = atlas_source.get_tile_id(i)
				if typeof(tile_id) == TYPE_VECTOR2I:
					coords.append(tile_id)
				elif typeof(tile_id) == TYPE_VECTOR2:
					var v: Vector2 = tile_id
					coords.append(Vector2i(int(v.x), int(v.y)))
				elif atlas_source.has_method("get_tile_atlas_coords"):
					coords.append(atlas_source.get_tile_atlas_coords(tile_id))
		if coords.is_empty():
			var region_size := atlas_source.texture_region_size
			var texture := atlas_source.texture
			if texture != null and region_size.x > 0 and region_size.y > 0:
				var tex_size := texture.get_size()
				var cols := int(tex_size.x / region_size.x)
				var rows := int(tex_size.y / region_size.y)
				for y in range(rows):
					for x in range(cols):
						coords.append(Vector2i(x, y))
		return _sort_coords_row_major(coords)

	if source.has_method("get_tiles_ids"):
		var ids = source.get_tiles_ids()
		for tile_id in ids:
			if typeof(tile_id) == TYPE_VECTOR2I:
				coords.append(tile_id)
			elif typeof(tile_id) == TYPE_VECTOR2:
				var v: Vector2 = tile_id
				coords.append(Vector2i(int(v.x), int(v.y)))
			elif source.has_method("get_tile_atlas_coords"):
				coords.append(source.get_tile_atlas_coords(tile_id))
		if not coords.is_empty():
			return _sort_coords_row_major(coords)
	if source.has_method("get_tiles_count") and source.has_method("get_tile_id") and source.has_method("get_tile_atlas_coords"):
		var count := int(source.get_tiles_count())
		for i in range(count):
			var tile_id := source.get_tile_id(i)
			coords.append(source.get_tile_atlas_coords(tile_id))
		return _sort_coords_row_major(coords)
	if source.has_method("get_tile_atlas_coords"):
		coords.append(source.get_tile_atlas_coords(0))
	return _sort_coords_row_major(coords)

func _sort_coords_row_major(coords: Array[Vector2i]) -> Array[Vector2i]:
	if coords.size() <= 1:
		return coords
	coords.sort_custom(func(a, b): return (a.x < b.x) if a.y == b.y else (a.y < b.y))
	return coords

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_painting = false
			dragging_chunk = false
			dragging_spawn = false
			rect_active = false
			_paint_end()
			_start_pan(event.position)
		else:
			_stop_pan()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(event)
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var tile_pos := _get_mouse_tile()
			if _is_in_spawn_area(tile_pos):
				_start_spawn_drag(tile_pos)
				return
		else:
			if dragging_spawn:
				_end_spawn_drag()
				return

	if chunk_edit_mode:
		_handle_chunk_edit_mouse_button(event)
		return

	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_start_paint(event.button_index)
		else:
			if dragging_spawn:
				_end_spawn_drag()
				return
			_paint_end()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		_pan_camera(event.position)
		return
	if dragging_spawn:
		_update_spawn_drag()
		return
	if chunk_edit_mode and resizing_chunk:
		_resize_chunk()
		return
	if chunk_edit_mode and dragging_chunk:
		_drag_chunk()
		return
	if is_painting:
		_apply_paint_at_mouse()

func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_Z and event.ctrl_pressed:
		_undo()
	elif event.keycode == KEY_F5:
		_save_map()
	elif event.keycode == KEY_F3:
		chunk_edit_mode = not chunk_edit_mode
		if chunk_toggle != null:
			chunk_toggle.button_pressed = chunk_edit_mode
		_update_chunk_ui()
	elif event.keycode == KEY_Z:
		rotate_steps = (rotate_steps + 3) % 4
	elif event.keycode == KEY_X:
		rotate_steps = (rotate_steps + 1) % 4
	elif event.keycode == KEY_C:
		flip_h = not flip_h
	elif event.keycode == KEY_V:
		flip_v = not flip_v

func _start_paint(button_index: int) -> void:
	if selected_layer == "" and button_index != MOUSE_BUTTON_RIGHT:
		return
	is_painting = true
	paint_button = button_index
	last_paint_tile = INVALID_TILE
	_terrain_dirty_valid = false
	rect_active = tool == Tool.RECT
	if rect_active:
		rect_start = _get_mouse_tile()
		rect_end = rect_start
		_record_undo()
	else:
		_record_undo()
		_apply_paint_at_mouse()

func _paint_end() -> void:
	if rect_active:
		_apply_rect_paint()
	rect_active = false
	is_painting = false
	last_paint_tile = INVALID_TILE
	_flush_terrain_dirty()

func _apply_paint_at_mouse() -> void:
	var tile_pos := _get_mouse_tile()
	if tile_pos == last_paint_tile:
		return
	var erase := paint_button == MOUSE_BUTTON_RIGHT
	if last_paint_tile == INVALID_TILE:
		_apply_paint(tile_pos, erase)
	else:
		for pos in _get_line_tiles(last_paint_tile, tile_pos):
			_apply_paint(pos, erase)
	last_paint_tile = tile_pos

func _apply_rect_paint() -> void:
	var min_x: int = int(min(rect_start.x, rect_end.x))
	var max_x: int = int(max(rect_start.x, rect_end.x))
	var min_y: int = int(min(rect_start.y, rect_end.y))
	var max_y: int = int(max(rect_start.y, rect_end.y))
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			_apply_paint(Vector2i(x, y), paint_button == MOUSE_BUTTON_RIGHT)

func _apply_paint(tile_pos: Vector2i, erase: bool) -> void:
	if map_data == null:
		return
	if _is_in_spawn_area(tile_pos):
		return
	var local_pos := tile_pos
	if erase:
		_erase_topmost_at(local_pos)
		return

	match selected_layer:
		"object":
			var object_entries: Array = map_data.layers.get("object", [])
			_remove_entry_at(object_entries, local_pos)
			var scene_entry: Dictionary = {}
			if selected_scene_path != "":
				scene_entry = {
					"pos": [local_pos.x, local_pos.y],
					"scene": selected_scene_path,
					"rot": rotate_steps,
					"fh": flip_h,
					"fv": flip_v,
				}
				object_entries.append(scene_entry)
			map_data.layers["object"] = object_entries
			_update_renderer_scene(local_pos, scene_entry)
		"terrain":
			var terrain_entries: Array = map_data.layers.get("terrain", [])
			var block_entries: Array = map_data.layers.get("block", [])
			_remove_entry_at(terrain_entries, local_pos)
			_remove_entry_at(block_entries, local_pos)
			var terrain_source_id := TileCatalog.INVALID_SOURCE
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				terrain_entries.append({
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
				})
				terrain_source_id = selected_source_id
			map_data.layers["terrain"] = terrain_entries
			map_data.layers["block"] = block_entries
			_update_renderer_tile("block", local_pos, {})
			_update_renderer_terrain(local_pos, terrain_source_id)
			_mark_terrain_dirty(local_pos)
		"block":
			var block_entries: Array = map_data.layers.get("block", [])
			var terrain_entries: Array = map_data.layers.get("terrain", [])
			_remove_entry_at(block_entries, local_pos)
			_remove_entry_at(terrain_entries, local_pos)
			var tile_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				tile_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
				block_entries.append(tile_entry)
			map_data.layers["block"] = block_entries
			map_data.layers["terrain"] = terrain_entries
			_update_renderer_tile("block", local_pos, tile_entry)
			_update_renderer_terrain(local_pos, TileCatalog.INVALID_SOURCE)
			_mark_terrain_dirty(local_pos)
		"hazard":
			var hazard_entries: Array = map_data.layers.get("hazard", [])
			_remove_entry_at(hazard_entries, local_pos)
			var hazard_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				hazard_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
				hazard_entries.append(hazard_entry)
			map_data.layers["hazard"] = hazard_entries
			_update_renderer_tile("hazard", local_pos, hazard_entry)
		"deco":
			var deco_entries: Array = map_data.layers.get("deco", [])
			_remove_entry_at(deco_entries, local_pos)
			var deco_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				deco_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
				deco_entries.append(deco_entry)
			map_data.layers["deco"] = deco_entries
			_update_renderer_tile("deco", local_pos, deco_entry)
		_:
			return

func _erase_topmost_at(local_pos: Vector2i) -> void:
	var object_entries: Array = map_data.layers.get("object", [])
	if _remove_entry_at(object_entries, local_pos):
		map_data.layers["object"] = object_entries
		_update_renderer_scene(local_pos, {})
		return
	var deco_entries: Array = map_data.layers.get("deco", [])
	if _remove_entry_at(deco_entries, local_pos):
		map_data.layers["deco"] = deco_entries
		_update_renderer_tile("deco", local_pos, {})
		return
	var block_entries: Array = map_data.layers.get("block", [])
	if _remove_entry_at(block_entries, local_pos):
		map_data.layers["block"] = block_entries
		_update_renderer_tile("block", local_pos, {})
		return
	var terrain_entries: Array = map_data.layers.get("terrain", [])
	if _remove_entry_at(terrain_entries, local_pos):
		map_data.layers["terrain"] = terrain_entries
		_update_renderer_terrain(local_pos, TileCatalog.INVALID_SOURCE)
		_mark_terrain_dirty(local_pos)
		return
	var hazard_entries: Array = map_data.layers.get("hazard", [])
	if _remove_entry_at(hazard_entries, local_pos):
		map_data.layers["hazard"] = hazard_entries
		_update_renderer_tile("hazard", local_pos, {})

func _mark_renderer_dirty() -> void:
	_renderer_dirty = true

func _mark_terrain_dirty(pos: Vector2i) -> void:
	if not _terrain_dirty_valid:
		_terrain_dirty_valid = true
		_terrain_dirty_min = pos
		_terrain_dirty_max = pos
		return
	_terrain_dirty_min = Vector2i(min(_terrain_dirty_min.x, pos.x), min(_terrain_dirty_min.y, pos.y))
	_terrain_dirty_max = Vector2i(max(_terrain_dirty_max.x, pos.x), max(_terrain_dirty_max.y, pos.y))

func _flush_terrain_dirty() -> void:
	if not _terrain_dirty_valid:
		return
	if renderer == null:
		_terrain_dirty_valid = false
		return
	renderer.rebuild_terrain_region(_terrain_dirty_min, _terrain_dirty_max)
	_terrain_dirty_valid = false

func _update_renderer_tile(layer_name: String, world_pos: Vector2i, entry: Dictionary) -> void:
	if renderer == null:
		_mark_renderer_dirty()
		return
	renderer.update_tile(layer_name, world_pos, entry)

func _update_renderer_scene(world_pos: Vector2i, entry: Dictionary) -> void:
	if renderer == null:
		_mark_renderer_dirty()
		return
	renderer.update_scene(world_pos, entry)

func _update_renderer_terrain(world_pos: Vector2i, source_id: int) -> void:
	if renderer == null:
		_mark_renderer_dirty()
		return
	renderer.update_terrain_cell(world_pos, source_id)

func _get_line_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 = from.x
	var y0 = from.y
	var x1 = to.x
	var y1 = to.y
	var dx = abs(x1 - x0)
	var sx = 1 if x0 < x1 else -1
	var dy = -abs(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err = dx + dy
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out

func _refresh_renderer() -> void:
	if renderer == null:
		return
	renderer.render_map(map_data)

func _remove_entry_at(entries: Array, local_pos: Vector2i) -> bool:
	var removed := false
	for i in range(entries.size() - 1, -1, -1):
		var entry = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos := _vec2i_from_value(entry.get("pos", null))
		if pos == local_pos:
			entries.remove_at(i)
			removed = true
	return removed

func _update_preview() -> void:
	if preview_layer == null:
		return
	preview_layer.clear()
	if selected_layer == "" or chunk_edit_mode or dragging_spawn:
		return
	if selected_layer == "object":
		return
	if selected_source_id == TileCatalog.INVALID_SOURCE:
		return
	var tile_pos := _get_mouse_tile()
	if tool == Tool.RECT and rect_active:
		var min_x: int = int(min(rect_start.x, rect_end.x))
		var max_x: int = int(max(rect_start.x, rect_end.x))
		var min_y: int = int(min(rect_start.y, rect_end.y))
		var max_y: int = int(max(rect_start.y, rect_end.y))
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var flags := _encode_tile_flags()
				var alt_id := _get_preview_alt_id(flags)
				preview_layer.set_cell(Vector2i(x, y), selected_source_id, selected_atlas, alt_id)
	else:
		var flags := _encode_tile_flags()
		var alt_id := _get_preview_alt_id(flags)
		preview_layer.set_cell(tile_pos, selected_source_id, selected_atlas, alt_id)

func _draw_grid() -> void:
	if camera == null:
		return
	var view_size := get_viewport_rect().size / camera.zoom
	var center := camera.get_screen_center_position()
	var top_left := center - view_size * 0.5
	var bottom_right := center + view_size * 0.5
	var start_x := int(floor(top_left.x / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var end_x := int(ceil(bottom_right.x / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var start_y := int(floor(top_left.y / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var end_y := int(ceil(bottom_right.y / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	for x in range(start_x, end_x + 1, MapData.TILE_SIZE):
		draw_line(Vector2(x, start_y), Vector2(x, end_y), grid_color, 1.0)
	for y in range(start_y, end_y + 1, MapData.TILE_SIZE):
		draw_line(Vector2(start_x, y), Vector2(end_x, y), grid_color, 1.0)

func _draw_chunks() -> void:
	var start_chunk := map_data.get_chunk_by_id(map_data.start_chunk_id)
	for chunk in map_data.chunks:
		var rect := _chunk_rect_pixels(chunk)
		var color := chunk_color
		if chunk == selected_chunk:
			color = chunk_selected_color
		draw_rect(rect, color, false, 2.0)
		if chunk == start_chunk:
			var spawn_px := Vector2(map_data.spawn) * MapData.TILE_SIZE
			draw_rect(Rect2(spawn_px, Vector2(MapData.TILE_SIZE * 2, MapData.TILE_SIZE * 2)), color, false, 2.0)
		if chunk_edit_mode:
			if chunk == selected_chunk:
				_draw_chunk_handles(chunk)

func _chunk_rect_pixels(chunk: ChunkData) -> Rect2:
	return Rect2(Vector2(chunk.pos) * MapData.TILE_SIZE, Vector2(chunk.size) * MapData.TILE_SIZE)

func _draw_chunk_handles(chunk: ChunkData) -> void:
	var rect := _chunk_rect_pixels(chunk)
	var half := CHUNK_HANDLE_SIZE * 0.5
	var handle_color := chunk_selected_color
	var left_mid := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)
	var right_mid := Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5)
	var top_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	var bottom_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
	draw_rect(Rect2(left_mid - Vector2(half, half), Vector2(CHUNK_HANDLE_SIZE, CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(right_mid - Vector2(half, half), Vector2(CHUNK_HANDLE_SIZE, CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(top_mid - Vector2(half, half), Vector2(CHUNK_HANDLE_SIZE, CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(bottom_mid - Vector2(half, half), Vector2(CHUNK_HANDLE_SIZE, CHUNK_HANDLE_SIZE)), handle_color, true)

func _get_chunk_handle_at_pos(chunk: ChunkData, world_pos: Vector2) -> String:
	var rect := _chunk_rect_pixels(chunk)
	var hit := CHUNK_HANDLE_HIT
	var half := hit * 0.5
	var left_mid := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)
	var right_mid := Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5)
	var top_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	var bottom_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
	if Rect2(left_mid - Vector2(half, half), Vector2(hit, hit)).has_point(world_pos):
		return "left"
	if Rect2(right_mid - Vector2(half, half), Vector2(hit, hit)).has_point(world_pos):
		return "right"
	if Rect2(top_mid - Vector2(half, half), Vector2(hit, hit)).has_point(world_pos):
		return "top"
	if Rect2(bottom_mid - Vector2(half, half), Vector2(hit, hit)).has_point(world_pos):
		return "bottom"
	return ""

func _chunk_overlaps(pos: Vector2i, size: Vector2i, ignore: ChunkData) -> bool:
	if map_data == null:
		return false
	var rect := Rect2i(pos, size)
	for other in map_data.chunks:
		if other == ignore:
			continue
		var other_rect := Rect2i(other.pos, other.size)
		if rect.intersects(other_rect):
			return true
	return false

func _ranges_overlap(a_min: int, a_max: int, b_min: int, b_max: int) -> bool:
	return a_min < b_max and b_min < a_max

func _tile_in_chunk(tile_pos: Vector2i, chunk: ChunkData) -> bool:
	return tile_pos.x >= chunk.pos.x \
		and tile_pos.y >= chunk.pos.y \
		and tile_pos.x < chunk.pos.x + chunk.size.x \
		and tile_pos.y < chunk.pos.y + chunk.size.y

func _find_non_overlapping_position(start_pos: Vector2i, size: Vector2i) -> Vector2i:
	if map_data == null:
		return start_pos
	if not _chunk_overlaps(start_pos, size, null):
		return start_pos
	var radius := 1
	while radius < 32:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var candidate := start_pos + Vector2i(dx, dy)
				if not _chunk_overlaps(candidate, size, null):
					return candidate
		radius += 1
	return start_pos

func _update_chunk_ui() -> void:
	var show_controls := chunk_edit_mode
	if pen_button != null:
		pen_button.toggle_mode = not show_controls
		pen_button.button_pressed = (not show_controls and tool == Tool.PEN)
		var pen_icon := pen_button as IconButton
		if pen_icon != null:
			pen_icon.icon_texture = ICON_CHUNK_ADD if show_controls else ICON_PEN
	if rect_button != null:
		rect_button.toggle_mode = not show_controls
		rect_button.button_pressed = (not show_controls and tool == Tool.RECT)
		var rect_icon := rect_button as IconButton
		if rect_icon != null:
			rect_icon.icon_texture = ICON_CHUNK_REMOVE if show_controls else ICON_RECT
	var can_delete := map_data != null and map_data.chunks.size() > 1 and selected_chunk != null
	if rect_button != null:
		rect_button.disabled = show_controls and not can_delete
	var icon_button := chunk_toggle as IconButton
	if icon_button != null:
		icon_button.icon_texture = ICON_BACK if show_controls else ICON_CHUNK

var _is_panning := false
var _pan_start_screen := Vector2.ZERO
var _pan_start_camera := Vector2.ZERO

func _start_pan(screen_pos: Vector2) -> void:
	_is_panning = true
	_pan_start_screen = screen_pos
	_pan_start_camera = camera.global_position

func _stop_pan() -> void:
	_is_panning = false

func _pan_camera(screen_pos: Vector2) -> void:
	if camera == null:
		return
	var delta := (screen_pos - _pan_start_screen) / camera.zoom
	camera.global_position = _pan_start_camera - delta

func _apply_zoom(event: InputEventMouseButton) -> void:
	if camera == null:
		return
	var zoom := camera.zoom.x
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom = max(zoom - zoom_step, zoom_min)
	else:
		zoom = min(zoom + zoom_step, zoom_max)
	camera.zoom = Vector2(zoom, zoom)

func _start_spawn_drag(tile_pos: Vector2i) -> void:
	if map_data == null:
		return
	_record_undo()
	dragging_spawn = true
	spawn_drag_offset = tile_pos - map_data.spawn

func _update_spawn_drag() -> void:
	if map_data == null:
		return
	var tile_pos := _get_mouse_tile() - spawn_drag_offset
	if _is_spawn_area_clear(tile_pos):
		_set_spawn(tile_pos)

func _end_spawn_drag() -> void:
	dragging_spawn = false

func _get_mouse_tile() -> Vector2i:
	var world_pos := get_global_mouse_position()
	return Vector2i(floor(world_pos.x / MapData.TILE_SIZE), floor(world_pos.y / MapData.TILE_SIZE))

func _is_spawn_area_clear(tile_pos: Vector2i) -> bool:
	if map_data == null:
		return false
	if not _spawn_area_in_chunk(tile_pos):
		return false
	for y in range(2):
		for x in range(2):
			var pos := tile_pos + Vector2i(x, y)
			if _has_entry_at(map_data.layers.get("object", []), pos):
				return false
			if _has_entry_at(map_data.layers.get("deco", []), pos):
				return false
			if _has_entry_at(map_data.layers.get("block", []), pos):
				return false
			if _has_entry_at(map_data.layers.get("terrain", []), pos):
				return false
			if _has_entry_at(map_data.layers.get("hazard", []), pos):
				return false
	return true

func _spawn_area_in_chunk(tile_pos: Vector2i) -> bool:
	if map_data == null:
		return false
	var base_chunk := map_data.get_chunk_at_tile(tile_pos)
	if base_chunk == null:
		return false
	for y in range(2):
		for x in range(2):
			var chunk := map_data.get_chunk_at_tile(tile_pos + Vector2i(x, y))
			if chunk != base_chunk:
				return false
	return true

func _has_entry_at(entries: Array, local_pos: Vector2i) -> bool:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos := _vec2i_from_value(entry.get("pos", null))
		if pos == local_pos:
			return true
	return false

func _handle_chunk_edit_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var world_pos := get_global_mouse_position()
		var handle_chunk: ChunkData = null
		var handle := ""
		for candidate in map_data.chunks:
			var found := _get_chunk_handle_at_pos(candidate, world_pos)
			if found != "":
				handle_chunk = candidate
				handle = found
				break
		if handle_chunk != null:
			selected_chunk = handle_chunk
			resize_handle = handle
			resizing_chunk = true
			drag_start_tile = _get_mouse_tile()
			drag_chunk_origin = handle_chunk.pos
			drag_chunk_size = handle_chunk.size
			_record_undo()
			_update_chunk_ui()
			return
		var tile_pos := _get_mouse_tile()
		var chunk := map_data.get_chunk_at_tile(tile_pos)
		if chunk != null:
			selected_chunk = chunk
			dragging_chunk = true
			drag_start_tile = tile_pos
			drag_chunk_origin = chunk.pos
			drag_chunk_size = chunk.size
			_record_undo()
			_update_chunk_ui()
	else:
		if resizing_chunk:
			resizing_chunk = false
			resize_handle = ""
			_sync_start_chunk_from_spawn()
			_clamp_spawn_after_chunk_change()
			_refresh_renderer()
		elif dragging_chunk:
			dragging_chunk = false
			_sync_start_chunk_from_spawn()
			_clamp_spawn_after_chunk_change()
			_refresh_renderer()

func _drag_chunk() -> void:
	var tile_pos := _get_mouse_tile()
	var delta := tile_pos - drag_start_tile
	if selected_chunk != null:
		var new_pos := drag_chunk_origin + delta
		if not _chunk_overlaps(new_pos, selected_chunk.size, selected_chunk):
			selected_chunk.pos = new_pos

func _resize_chunk() -> void:
	if selected_chunk == null or map_data == null:
		return
	var tile_pos := _get_mouse_tile()
	var min_size := MapData.MIN_CHUNK_SIZE
	var left := drag_chunk_origin.x
	var right := drag_chunk_origin.x + drag_chunk_size.x
	var top := drag_chunk_origin.y
	var bottom := drag_chunk_origin.y + drag_chunk_size.y
	match resize_handle:
		"left":
			var new_left: int = int(min(right - min_size.x, tile_pos.x))
			var limit_left := -1000000
			for other in map_data.chunks:
				if other == selected_chunk:
					continue
				if _ranges_overlap(top, bottom, other.pos.y, other.pos.y + other.size.y):
					limit_left = max(limit_left, other.pos.x + other.size.x)
			if limit_left > -1000000:
				new_left = max(new_left, limit_left)
			new_left = min(new_left, right - min_size.x)
			selected_chunk.pos.x = new_left
			selected_chunk.size.x = right - new_left
		"right":
			var new_right: int = int(max(left + min_size.x, tile_pos.x + 1))
			var limit_right := 1000000
			for other in map_data.chunks:
				if other == selected_chunk:
					continue
				if _ranges_overlap(top, bottom, other.pos.y, other.pos.y + other.size.y):
					limit_right = min(limit_right, other.pos.x)
			if limit_right < 1000000:
				new_right = min(new_right, limit_right)
			new_right = max(new_right, left + min_size.x)
			selected_chunk.pos.x = left
			selected_chunk.size.x = new_right - left
		"top":
			var new_top: int = int(min(bottom - min_size.y, tile_pos.y))
			var limit_top := -1000000
			for other in map_data.chunks:
				if other == selected_chunk:
					continue
				if _ranges_overlap(left, right, other.pos.x, other.pos.x + other.size.x):
					limit_top = max(limit_top, other.pos.y + other.size.y)
			if limit_top > -1000000:
				new_top = max(new_top, limit_top)
			new_top = min(new_top, bottom - min_size.y)
			selected_chunk.pos.y = new_top
			selected_chunk.size.y = bottom - new_top
		"bottom":
			var new_bottom: int = int(max(top + min_size.y, tile_pos.y + 1))
			var limit_bottom := 1000000
			for other in map_data.chunks:
				if other == selected_chunk:
					continue
				if _ranges_overlap(left, right, other.pos.x, other.pos.x + other.size.x):
					limit_bottom = min(limit_bottom, other.pos.y)
			if limit_bottom < 1000000:
				new_bottom = min(new_bottom, limit_bottom)
			new_bottom = max(new_bottom, top + min_size.y)
			selected_chunk.pos.y = top
			selected_chunk.size.y = new_bottom - top

func _clamp_spawn_after_chunk_change() -> void:
	if map_data == null:
		return
	var chunk := map_data.get_chunk_at_tile(map_data.spawn)
	if chunk == null and selected_chunk != null:
		chunk = selected_chunk
	if chunk == null:
		chunk = map_data.get_chunk_by_id(map_data.start_chunk_id)
	if chunk == null:
		return
	var clamped := _clamp_spawn_to_chunk(map_data.spawn, chunk)
	if clamped != map_data.spawn:
		_set_spawn(clamped)

func _on_pen_toggled(pressed: bool) -> void:
	if pressed:
		tool = Tool.PEN
	else:
		tool = Tool.RECT

func _on_rect_toggled(pressed: bool) -> void:
	if pressed:
		tool = Tool.RECT
	else:
		tool = Tool.PEN

func _on_save_pressed() -> void:
	_save_map()

func _on_menu_pressed() -> void:
	if editor_menu != null:
		_sync_editor_menu()
		if editor_menu.has_method("show_popup"):
			editor_menu.show_popup()
		else:
			editor_menu.visible = true

func _sync_editor_menu() -> void:
	if map_data == null:
		return
	if editor_menu_title != null:
		editor_menu_title.text = str(map_data.metadata.get("title", ""))
	if _bg_list.is_empty():
		_bg_list = _load_background_list()
	var bg_name := str(map_data.metadata.get("bg", ""))
	_bg_index = _bg_list.find(bg_name)
	if _bg_index < 0:
		_bg_index = 0
	_update_difficulty_icon()

func _on_menu_save_quit() -> void:
	_save_map()
	_on_menu_quit()

func _on_menu_quit() -> void:
	var root := get_tree().root
	if root != null:
		var fader: Node = root.get_node_or_null("SceneFader")
		if fader != null and fader.has_method("change_scene"):
			fader.change_scene("res://roots/map_select_editor.tscn")
			return
	get_tree().change_scene_to_file("res://roots/map_select_editor.tscn")

func _on_menu_close() -> void:
	if editor_menu != null:
		if editor_menu.has_method("hide_popup"):
			editor_menu.hide_popup()
		else:
			editor_menu.visible = false

func _on_menu_title_changed(new_text: String) -> void:
	if map_data == null:
		return
	map_data.metadata["title"] = new_text

func _on_menu_diff_down() -> void:
	_adjust_difficulty(-1)

func _on_menu_diff_up() -> void:
	_adjust_difficulty(1)

func _adjust_difficulty(delta: int) -> void:
	if map_data == null:
		return
	var diff := clampi(int(map_data.metadata.get("difficulty", 1)) + delta, 1, 8)
	map_data.metadata["difficulty"] = diff
	_update_difficulty_icon()

func _update_difficulty_icon() -> void:
	if editor_menu_diff_icon == null or map_data == null:
		return
	var diff := clampi(int(map_data.metadata.get("difficulty", 1)), 1, 8)
	var path := "res://graphics/ui/16px/difficulty/%s.png" % str(diff)
	if ResourceLoader.exists(path):
		editor_menu_diff_icon.texture = load(path)

func _on_menu_bg_prev() -> void:
	_adjust_bg(-1)

func _on_menu_bg_next() -> void:
	_adjust_bg(1)

func _adjust_bg(delta: int) -> void:
	if map_data == null:
		return
	if _bg_list.is_empty():
		_bg_list = _load_background_list()
	if _bg_list.is_empty():
		return
	_bg_index = (_bg_index + delta) % _bg_list.size()
	if _bg_index < 0:
		_bg_index = _bg_list.size() - 1
	map_data.metadata["bg"] = _bg_list[_bg_index]
	_apply_background_selection()

func _apply_background_selection() -> void:
	if background_sprite == null or map_data == null:
		return
	var bg_name := str(map_data.metadata.get("bg", ""))
	if bg_name == "":
		return
	var path := "res://graphics/backgrounds/%s" % bg_name
	if ResourceLoader.exists(path):
		background_sprite.texture = load(path)
		_update_background_layout()

func _update_background_layout() -> void:
	if background_sprite == null or camera == null:
		return
	if background_sprite.texture == null:
		return
	var tex_size := background_sprite.texture.get_size()
	if tex_size == Vector2.ZERO:
		return
	var view_size := get_viewport_rect().size / camera.zoom
	var scale := Vector2(view_size.x / tex_size.x, view_size.y / tex_size.y)
	background_sprite.centered = false
	background_sprite.scale = scale
	background_sprite.position = -view_size * 0.5

func _load_background_list() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://graphics/backgrounds")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			if name.to_lower().ends_with(".png"):
				out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

func _pick_random_bg() -> String:
	var choices := _load_background_list()
	if choices.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var index := rng.randi_range(0, choices.size() - 1)
	return choices[index]

func _on_new_chunk_pressed() -> void:
	if not chunk_edit_mode:
		return
	var chunk := ChunkData.new()
	chunk.id = _make_chunk_id()
	var center := camera.get_screen_center_position()
	var center_tile := Vector2i(floor(center.x / MapData.TILE_SIZE), floor(center.y / MapData.TILE_SIZE))
	var desired_pos := center_tile - (MapData.MIN_CHUNK_SIZE / 2)
	chunk.pos = _find_non_overlapping_position(desired_pos, MapData.MIN_CHUNK_SIZE)
	chunk.size = MapData.MIN_CHUNK_SIZE
	map_data.chunks.append(chunk)
	selected_chunk = chunk
	_refresh_renderer()
	_update_chunk_ui()

func _on_chunk_edit_toggled(pressed: bool) -> void:
	chunk_edit_mode = pressed
	if not pressed:
		dragging_chunk = false
		resizing_chunk = false
		resize_handle = ""
	_update_chunk_ui()

func _on_chunk_delete_pressed() -> void:
	if not chunk_edit_mode:
		return
	if map_data == null or selected_chunk == null:
		return
	if map_data.chunks.size() <= 1:
		return
	var index := map_data.chunks.find(selected_chunk)
	if index == -1:
		return
	_record_undo()
	var spawn_in_removed := _tile_in_chunk(map_data.spawn, selected_chunk)
	var removed_id := selected_chunk.id
	map_data.chunks.remove_at(index)
	selected_chunk = null
	if spawn_in_removed and map_data.chunks.size() > 0:
		_set_spawn(map_data.chunks[0].pos + Vector2i(3, 3))
	if removed_id == map_data.start_chunk_id:
		_sync_start_chunk_from_spawn()
	if selected_chunk == null and not map_data.chunks.is_empty():
		var pick_index: int = clampi(index - 1, 0, map_data.chunks.size() - 1)
		selected_chunk = map_data.chunks[pick_index]
	_refresh_renderer()
	_update_chunk_ui()

func _on_tile_button_pressed(prefix: String, source_id: int, atlas_coords: Vector2i) -> void:
	selected_source_id = source_id
	selected_atlas = atlas_coords
	selected_alt = 0
	selected_scene_path = ""
	selected_layer = prefix


func _on_scene_button_pressed(scene_path: String) -> void:
	selected_scene_path = scene_path
	selected_layer = "object"
	selected_source_id = TileCatalog.INVALID_SOURCE

func _save_map() -> void:
	Game.ensure_dirs()
	if current_save_path == "":
		current_save_path = _make_new_map_path()
	MapIO.save_map(current_save_path, map_data, true)

func _make_new_map_path() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var name := "map_%s_%s.json" % [str(Time.get_unix_time_from_system()), str(rng.randi())]
		var path := "%s/%s" % [Game.WIP_DIR, name]
		if not FileAccess.file_exists(path):
			return path
	return "%s/map.json" % Game.WIP_DIR

func _record_undo() -> void:
	var snapshot := map_data.to_compact_dict()
	undo_stack.append(snapshot)
	if undo_stack.size() > undo_limit:
		undo_stack.pop_front()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	var last: Dictionary = undo_stack.pop_back()
	map_data = MapData.from_compact_dict(last)
	selected_chunk = map_data.get_chunk_by_id(map_data.start_chunk_id)
	_update_spawn_node()
	_sync_start_chunk_from_spawn()
	_refresh_renderer()
	_update_chunk_ui()

func _make_chunk_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stamp := Time.get_unix_time_from_system()
	return "%s_%s" % [str(stamp), str(rng.randi())]

func _vec2i_from_value(value) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

func _get_editor_camera() -> Camera2D:
	return camera

func _make_line_edit_flat(edit: LineEdit) -> void:
	if edit == null:
		return
	var empty := StyleBoxEmpty.new()
	edit.add_theme_stylebox_override("normal", empty)
	edit.add_theme_stylebox_override("focus", empty)
	edit.add_theme_stylebox_override("read_only", empty)
