class_name MapEditor
extends Node2D

enum Tool {
	CURSOR,
	PEN,
	RECT,
}

const ICON_PEN := preload("res://graphics/ui/16px/editor/tools/pen.png")
const ICON_RECT := preload("res://graphics/ui/16px/editor/tools/square.png")
const ICON_CHUNK := preload("res://graphics/ui/16px/editor/tools/chunk.png")
const ICON_CHUNK_ADD := preload("res://graphics/ui/16px/editor/tools/chunk_add.png")
const ICON_CHUNK_REMOVE := preload("res://graphics/ui/16px/editor/tools/chunk_remove.png")
const ICON_BACK := preload("res://graphics/ui/16px/nav_prev.png")
const BACKGROUND_CATALOG := preload("res://scripts/map/editor/background_catalog.gd")

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
@onready var cursor_button: BaseButton = get_node_or_null("UI/Hud/Tools/CursorButton") as BaseButton
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
@onready var inspector_panel: Control = get_node_or_null("UI/InspectorPanel") as Control
@onready var inspector_header: Label = get_node_or_null("UI/InspectorPanel/Header") as Label
@onready var inspector_options: VBoxContainer = get_node_or_null("UI/InspectorPanel/Options") as VBoxContainer
@onready var inspector_close: BaseButton = get_node_or_null("UI/InspectorPanel/CloseButton") as BaseButton

var tile_tool: MapEditorTileTool
var chunk_tool: MapEditorChunkTool
var cursor_tool: MapEditorCursorTool
var active_tool := Tool.PEN
var cursor_rect := Rect2i()
var cursor_rect_active := false
var cursor_drag_offset := Vector2i.ZERO

var chunk_edit_mode := false
var selected_chunk: ChunkData
var _renderer_dirty := false

var undo_stack: Array[Dictionary] = []
var undo_limit := 50
var current_save_path := ""
var spawn_node: Node2D
var dragging_spawn := false
var spawn_drag_offset := Vector2i.ZERO
var _bg_list: Array[String] = []
var _bg_index := 0
var inspector_text: LineEdit
var inspector_entry_index := -1
var inspector_entry_pos := Vector2i.ZERO

func _ready() -> void:
	process_priority = 20
	_load_map()
	if map_path.strip_edges() != "":
		Game.last_editor_map_path = map_path
	_setup_camera()
	_setup_renderer()
	_setup_preview_layer()
	_setup_tools()
	_setup_spawn()
	_connect_ui()
	_build_palette()
	_bg_list = _load_background_list()
	_apply_background_selection()
	_sync_editor_menu()
	queue_redraw()

func _process(_delta: float) -> void:
	if tile_tool != null and active_tool != Tool.CURSOR:
		tile_tool.update_preview()
	_update_background_layout()
	if _renderer_dirty:
		_renderer_dirty = false
		_refresh_renderer(true)
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
	if map_path.strip_edges() == "":
		if Game.current_map_path != "":
			map_path = Game.current_map_path
		elif Game.last_editor_map_path != "":
			map_path = Game.last_editor_map_path
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

func _setup_tools() -> void:
	tile_tool = MapEditorTileTool.new()
	tile_tool.setup(self)
	tile_tool.set_tool(Tool.PEN)
	chunk_tool = MapEditorChunkTool.new()
	chunk_tool.setup(self)
	cursor_tool = MapEditorCursorTool.new()
	cursor_tool.setup(self)

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
		if cursor_button != null:
			cursor_button.button_group = tool_group
		pen_button.toggle_mode = true
		rect_button.toggle_mode = true
		if cursor_button != null:
			cursor_button.toggle_mode = true
		pen_button.button_pressed = true
		if not pen_button.toggled.is_connected(_on_pen_toggled):
			pen_button.toggled.connect(_on_pen_toggled)
		if not rect_button.toggled.is_connected(_on_rect_toggled):
			rect_button.toggled.connect(_on_rect_toggled)
		if cursor_button != null and not cursor_button.toggled.is_connected(_on_cursor_toggled):
			cursor_button.toggled.connect(_on_cursor_toggled)
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

func _update_chunk_ui() -> void:
	if chunk_tool != null:
		chunk_tool.update_ui()

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
			if tile_tool != null:
				tile_tool.is_painting = false
			dragging_spawn = false
			if tile_tool != null:
				tile_tool.rect_active = false
				tile_tool.paint_end()
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
		if chunk_tool != null:
			chunk_tool.handle_mouse_button(event)
		return

	if active_tool == Tool.CURSOR:
		if cursor_tool != null:
			cursor_tool.handle_mouse_button(event)
		return

	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if tile_tool != null:
				tile_tool.start_paint(event.button_index)
		else:
			if dragging_spawn:
				_end_spawn_drag()
				return
			if tile_tool != null:
				tile_tool.paint_end()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		_pan_camera(event.position)
		return
	if dragging_spawn:
		_update_spawn_drag()
		return
	if chunk_edit_mode and chunk_tool != null:
		chunk_tool.handle_mouse_motion(event)
		return
	if active_tool == Tool.CURSOR:
		if cursor_tool != null:
			cursor_tool.handle_mouse_motion(event)
		return
	if tile_tool != null and tile_tool.is_painting:
		tile_tool.apply_paint_at_mouse()

func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_Z and event.ctrl_pressed:
		_undo()
	elif event.keycode == KEY_F5:
		_save_map()
	elif event.keycode == KEY_F3:
		if chunk_tool != null:
			chunk_tool.set_edit_mode(not chunk_edit_mode)
		if chunk_toggle != null:
			chunk_toggle.button_pressed = chunk_edit_mode
		_set_active_tool(Tool.CURSOR if active_tool != Tool.CURSOR else Tool.PEN)
	elif tile_tool != null:
		tile_tool.handle_key(event)

func _mark_renderer_dirty() -> void:
	_renderer_dirty = true

func _sync_map_data_tile_layers() -> void:
	if map_data == null:
		return
	if map_data.layers == null:
		map_data.layers = MapData._make_layers()
	map_data.layers["hazard"] = _build_tile_entries_from_layer("hazard", true)
	map_data.layers["deco"] = _build_tile_entries_from_layer("deco", true)
	map_data.layers["block"] = _build_tile_entries_from_layer("block", true)
	map_data.layers["terrain"] = _build_tile_entries_from_layer("terrain", false)

func _build_tile_entries_from_layer(layer_name: String, include_alt: bool) -> Array:
	var out: Array = []
	var layer := _get_tile_layer(layer_name)
	if layer == null:
		return out
	var used := layer.get_used_cells()
	for cell in used:
		var source_id := layer.get_cell_source_id(cell)
		if source_id == TileCatalog.INVALID_SOURCE:
			continue
		if include_alt:
			var atlas := layer.get_cell_atlas_coords(cell)
			var alt := layer.get_cell_alternative_tile(cell)
			out.append({
				"pos": [cell.x, cell.y],
				"source_id": source_id,
				"atlas": [atlas.x, atlas.y],
				"alt": alt,
			})
		else:
			out.append({
				"pos": [cell.x, cell.y],
				"source_id": source_id,
			})
	return out

func _get_tile_layer(layer_name: String) -> TileMapLayer:
	if renderer == null:
		return null
	return renderer.get_tile_layer(layer_name)

func _refresh_renderer(sync_tiles: bool = false) -> void:
	if renderer == null:
		return
	if sync_tiles:
		_sync_map_data_tile_layers()
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
			if tile_tool != null and tile_tool.has_tile_at("deco", pos):
				return false
			if tile_tool != null and tile_tool.has_tile_at("block", pos):
				return false
			if tile_tool != null and tile_tool.has_tile_at("terrain", pos):
				return false
			if tile_tool != null and tile_tool.has_tile_at("hazard", pos):
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

func _on_cursor_toggled(pressed: bool) -> void:
	if not pressed:
		return
	_set_active_tool(Tool.CURSOR)

func _on_pen_toggled(pressed: bool) -> void:
	if not pressed or tile_tool == null:
		return
	_set_active_tool(Tool.PEN)
	tile_tool.set_tool(Tool.PEN)
	if chunk_tool != null:
		chunk_tool.update_ui()

func _on_rect_toggled(pressed: bool) -> void:
	if not pressed or tile_tool == null:
		return
	_set_active_tool(Tool.RECT)
	tile_tool.set_tool(Tool.RECT)
	if chunk_tool != null:
		chunk_tool.update_ui()

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
	Game.current_map_path = ""
	Game.current_map_data = null
	Game.current_map_id = ""
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
	var diff := clampi(int(map_data.metadata.get("rating", 1)) + delta, 1, 8)
	map_data.metadata["rating"] = diff
	_update_difficulty_icon()

func _update_difficulty_icon() -> void:
	if editor_menu_diff_icon == null or map_data == null:
		return
	var diff := clampi(int(map_data.metadata.get("rating", 1)), 1, 8)
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
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				if name.to_lower().ends_with(".png"):
					out.append(name)
			name = dir.get_next()
		dir.list_dir_end()
	if out.is_empty():
		out = _load_background_fallback()
	out.sort()
	return out

func _load_background_fallback() -> Array[String]:
	var out: Array[String] = []
	for name in BACKGROUND_CATALOG.BACKGROUND_FILES:
		var path := "res://graphics/backgrounds/%s" % name
		if ResourceLoader.exists(path):
			out.append(name)
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
	if chunk_tool != null:
		chunk_tool.add_new_chunk()

func _on_chunk_edit_toggled(pressed: bool) -> void:
	if chunk_tool != null:
		chunk_tool.set_edit_mode(pressed)
	else:
		chunk_edit_mode = pressed
	_update_chunk_ui()

func _on_chunk_delete_pressed() -> void:
	if not chunk_edit_mode:
		return
	if chunk_tool != null:
		chunk_tool.delete_selected_chunk()

func _on_tile_button_pressed(prefix: String, source_id: int, atlas_coords: Vector2i) -> void:
	if tile_tool == null:
		return
	tile_tool.select_tile(prefix, source_id, atlas_coords)


func _on_scene_button_pressed(scene_path: String) -> void:
	if tile_tool == null:
		return
	tile_tool.select_scene(scene_path)

func _save_map() -> void:
	Game.ensure_dirs()
	if current_save_path == "":
		current_save_path = _make_new_map_path()
	else:
		current_save_path = _ensure_kittymap_path(current_save_path)
	_sync_map_data_tile_layers()
	MapIO.save_map(current_save_path, map_data)

func build_preview_map_data(size_px: Vector2i = Vector2i(320, 180)) -> MapData:
	_sync_map_data_tile_layers()
	return map_data.make_preview_map_data(size_px)

func capture_preview_image(size: Vector2i, scale: Vector2 = Vector2.ONE) -> Image:
	var capture := MapPreviewCapture.new()
	capture.tile_set = tile_set
	add_child(capture)
	var image: Image = await capture.capture(map_data, size, scale)
	capture.queue_free()
	return image

func _make_new_map_path() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var name := "map_%s_%s.kittymap" % [str(Time.get_unix_time_from_system()), str(rng.randi())]
		var path := "%s/%s" % [Game.WIP_DIR, name]
		if not FileAccess.file_exists(path):
			return path
	return "%s/map.kittymap" % Game.WIP_DIR

func _ensure_kittymap_path(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed == "":
		return trimmed
	var lower := trimmed.to_lower()
	if lower.ends_with(".kittymap"):
		return trimmed
	var sep = max(trimmed.rfind("/"), trimmed.rfind("\\"))
	var dot = trimmed.rfind(".")
	if dot > sep:
		trimmed = trimmed.substr(0, dot)
	return "%s.kittymap" % trimmed

func _record_undo() -> void:
	_sync_map_data_tile_layers()
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

func _set_active_tool(new_tool: int) -> void:
	if active_tool == new_tool:
		return
	active_tool = new_tool
	if active_tool == Tool.CURSOR:
		if preview_layer != null:
			preview_layer.clear()
	else:
		_clear_cursor_selection()

func _clear_cursor_selection() -> void:
	cursor_rect = Rect2i()
	cursor_rect_active = false
	cursor_drag_offset = Vector2i.ZERO

func _set_cursor_rect(rect: Rect2i, active: bool, drag_offset: Vector2i) -> void:
	cursor_rect = rect
	cursor_rect_active = active
	cursor_drag_offset = drag_offset

func _get_cursor_rect_pixels() -> Rect2:
	if not cursor_rect_active:
		return Rect2()
	var rect_pos := cursor_rect.position + cursor_drag_offset
	var rect_size := cursor_rect.size
	var pos_px := Vector2(rect_pos) * MapData.TILE_SIZE
	var size_px := Vector2(rect_size) * MapData.TILE_SIZE
	return Rect2(pos_px, size_px)

func _open_object_inspector_at(tile_pos: Vector2i) -> void:
	if map_data == null:
		return
	var info := _find_object_entry_at(tile_pos)
	if info.is_empty():
		return
	var entry: Dictionary = info.get("entry", {})
	var scene_path := str(entry.get("scene", ""))
	if not _is_inspectable_scene(scene_path):
		return
	_ensure_object_inspector()
	if inspector_text == null:
		return
	inspector_entry_index = int(info.get("index", -1))
	inspector_entry_pos = tile_pos
	var data = entry.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	inspector_text.text = str(data.get("text", ""))
	_open_inspector_panel()

func _find_object_entry_at(tile_pos: Vector2i) -> Dictionary:
	var entries: Array = map_data.layers.get("object", [])
	for i in range(entries.size() - 1, -1, -1):
		var entry = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos := _vec2i_from_value(entry.get("pos", null))
		if pos == tile_pos:
			return {"index": i, "entry": entry}
	return {}

func _is_inspectable_scene(scene_path: String) -> bool:
	return scene_path.ends_with("info_sign.tscn")

func _ensure_object_inspector() -> void:
	if inspector_panel == null:
		return
	if inspector_panel.visible:
		inspector_panel.visible = false
	if inspector_close != null and not inspector_close.pressed.is_connected(_close_inspector_panel):
		inspector_close.pressed.connect(_close_inspector_panel)
	if inspector_options == null:
		return
	if inspector_text != null:
		return
	for child in inspector_options.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "Text"
	inspector_text = LineEdit.new()
	inspector_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not inspector_text.text_changed.is_connected(_on_inspector_text_changed):
		inspector_text.text_changed.connect(_on_inspector_text_changed)
	inspector_options.add_child(label)
	inspector_options.add_child(inspector_text)

func _open_inspector_panel() -> void:
	if inspector_panel == null:
		return
	inspector_panel.visible = true
	if inspector_header != null:
		inspector_header.text = "Inspector"
	var view := get_viewport_rect().size
	var pos := get_viewport().get_mouse_position() + Vector2(12, 12)
	var size := inspector_panel.size
	pos.x = clamp(pos.x, 8.0, max(8.0, view.x - size.x - 8.0))
	pos.y = clamp(pos.y, 8.0, max(8.0, view.y - size.y - 8.0))
	inspector_panel.position = pos

func _close_inspector_panel() -> void:
	if inspector_panel != null:
		inspector_panel.visible = false

func _on_inspector_text_changed(new_text: String) -> void:
	_apply_inspector_text(new_text)

func _apply_inspector_text(new_text: String) -> void:
	if map_data == null:
		return
	if inspector_entry_index < 0:
		return
	var entries: Array = map_data.layers.get("object", [])
	if inspector_entry_index >= entries.size():
		return
	var entry = entries[inspector_entry_index]
	if typeof(entry) != TYPE_DICTIONARY:
		return
	_record_undo()
	var data = entry.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	data["text"] = new_text
	entry["data"] = data
	entries[inspector_entry_index] = entry
	map_data.layers["object"] = entries
	if renderer != null:
		renderer.update_scene(inspector_entry_pos, entry)

func _get_editor_camera() -> Camera2D:
	return camera

func _make_line_edit_flat(edit: LineEdit) -> void:
	if edit == null:
		return
	var empty := StyleBoxEmpty.new()
	edit.add_theme_stylebox_override("normal", empty)
	edit.add_theme_stylebox_override("focus", empty)
	edit.add_theme_stylebox_override("read_only", empty)
