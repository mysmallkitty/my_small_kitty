class_name MapEditorTileTool
extends RefCounted

var editor

var tool := 0
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
var last_paint_tile := Vector2i.ZERO

var _terrain_dirty_min := Vector2i.ZERO
var _terrain_dirty_max := Vector2i.ZERO
var _terrain_dirty_valid := false

func setup(editor_ref) -> void:
	editor = editor_ref
	last_paint_tile = editor.INVALID_TILE

func set_tool(new_tool: int) -> void:
	tool = new_tool

func select_tile(prefix: String, source_id: int, atlas_coords: Vector2i) -> void:
	selected_layer = prefix
	selected_source_id = source_id
	selected_atlas = atlas_coords
	selected_alt = 0
	selected_scene_path = ""

func select_scene(scene_path: String) -> void:
	selected_scene_path = scene_path
	selected_layer = "object"
	selected_source_id = TileCatalog.INVALID_SOURCE

func handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_Z:
		rotate_steps = (rotate_steps + 3) % 4
	elif event.keycode == KEY_X:
		rotate_steps = (rotate_steps + 1) % 4
	elif event.keycode == KEY_C:
		flip_h = not flip_h
	elif event.keycode == KEY_V:
		flip_v = not flip_v

func start_paint(button_index: int) -> void:
	if selected_layer == "" and button_index != MOUSE_BUTTON_RIGHT:
		return
	is_painting = true
	paint_button = button_index
	last_paint_tile = editor.INVALID_TILE
	_terrain_dirty_valid = false
	rect_active = tool == editor.Tool.RECT
	if rect_active:
		rect_start = editor._get_mouse_tile()
		rect_end = rect_start
		editor._record_undo()
	else:
		editor._record_undo()
		_apply_paint_at_mouse()

func paint_end() -> void:
	if rect_active:
		_apply_rect_paint()
	rect_active = false
	is_painting = false
	last_paint_tile = editor.INVALID_TILE
	_flush_terrain_dirty()

func apply_paint_at_mouse() -> void:
	if not is_painting:
		return
	_apply_paint_at_mouse()

func update_preview() -> void:
	if editor.preview_layer == null:
		return
	editor.preview_layer.clear()
	if selected_layer == "" or editor.chunk_edit_mode or editor.dragging_spawn:
		return
	if selected_layer == "object":
		return
	if selected_source_id == TileCatalog.INVALID_SOURCE:
		return
	var tile_pos = editor._get_mouse_tile()
	if tool == editor.Tool.RECT and rect_active:
		var min_x: int = int(min(rect_start.x, rect_end.x))
		var max_x: int = int(max(rect_start.x, rect_end.x))
		var min_y: int = int(min(rect_start.y, rect_end.y))
		var max_y: int = int(max(rect_start.y, rect_end.y))
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var flags := _encode_tile_flags()
				editor.preview_layer.set_cell(Vector2i(x, y), selected_source_id, selected_atlas, flags)
	else:
		var flags := _encode_tile_flags()
		editor.preview_layer.set_cell(tile_pos, selected_source_id, selected_atlas, flags)

func has_tile_at(layer_name: String, local_pos: Vector2i) -> bool:
	return _tile_layer_has_cell(layer_name, local_pos)

func _encode_tile_flags() -> int:
	var rot := rotate_steps & 3
	var fh := flip_h
	var fv := flip_v
	var desired := _matrix_mul(_matrix_mul(_flip_matrix(fh, true), _flip_matrix(fv, false)), _rotation_matrix(rot))
	var mapping := _flags_matrix_map()
	var key := _matrix_key(desired)
	var transform := {"flip_h": fh, "flip_v": fv, "transpose": false}
	if mapping.has(key):
		transform = mapping[key]
	var out := 0
	if transform.get("flip_h", false):
		out |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if transform.get("flip_v", false):
		out |= TileSetAtlasSource.TRANSFORM_FLIP_V
	if transform.get("transpose", false):
		out |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
	return out

func _apply_paint_at_mouse() -> void:
	var tile_pos = editor._get_mouse_tile()
	if tile_pos == last_paint_tile:
		return
	var erase := paint_button == MOUSE_BUTTON_RIGHT
	if last_paint_tile == editor.INVALID_TILE:
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
	if editor.map_data == null:
		return
	if editor._is_in_spawn_area(tile_pos):
		return
	var local_pos := tile_pos
	if erase:
		_erase_topmost_at(local_pos)
		return

	match selected_layer:
		"object":
			var object_entries: Array = editor.map_data.layers.get("object", [])
			editor._remove_entry_at(object_entries, local_pos)
			var scene_entry: Dictionary = {}
			if selected_scene_path != "":
				scene_entry = {
					"pos": [local_pos.x, local_pos.y],
					"scene": selected_scene_path,
					"rot": rotate_steps,
					"fh": flip_h,
					"fv": flip_v,
					"data": {},
				}
				object_entries.append(scene_entry)
			editor.map_data.layers["object"] = object_entries
			_update_renderer_scene(local_pos, scene_entry)
		"terrain":
			var terrain_source_id := TileCatalog.INVALID_SOURCE
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				terrain_source_id = selected_source_id
			_update_renderer_tile("block", local_pos, {})
			_update_renderer_terrain(local_pos, terrain_source_id)
			_mark_terrain_dirty(local_pos)
		"block":
			var tile_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				tile_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
			_update_renderer_tile("block", local_pos, tile_entry)
			_update_renderer_terrain(local_pos, TileCatalog.INVALID_SOURCE)
			_mark_terrain_dirty(local_pos)
		"hazard":
			var hazard_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				hazard_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
			_update_renderer_tile("hazard", local_pos, hazard_entry)
		"deco":
			var deco_entry: Dictionary = {}
			if selected_source_id != TileCatalog.INVALID_SOURCE:
				deco_entry = {
					"pos": [local_pos.x, local_pos.y],
					"source_id": selected_source_id,
					"atlas": [selected_atlas.x, selected_atlas.y],
					"alt": _encode_tile_flags(),
				}
			_update_renderer_tile("deco", local_pos, deco_entry)
		_:
			return

func _erase_topmost_at(local_pos: Vector2i) -> void:
	var object_entries: Array = editor.map_data.layers.get("object", [])
	if editor._remove_entry_at(object_entries, local_pos):
		editor.map_data.layers["object"] = object_entries
		_update_renderer_scene(local_pos, {})
		return
	if _tile_layer_has_cell("deco", local_pos):
		_update_renderer_tile("deco", local_pos, {})
		return
	if _tile_layer_has_cell("block", local_pos):
		_update_renderer_tile("block", local_pos, {})
		return
	if _tile_layer_has_cell("terrain", local_pos):
		_update_renderer_terrain(local_pos, TileCatalog.INVALID_SOURCE)
		_mark_terrain_dirty(local_pos)
		return
	if _tile_layer_has_cell("hazard", local_pos):
		_update_renderer_tile("hazard", local_pos, {})

func _update_renderer_tile(layer_name: String, world_pos: Vector2i, entry: Dictionary) -> void:
	if editor.renderer == null:
		editor._mark_renderer_dirty()
		return
	editor.renderer.update_tile(layer_name, world_pos, entry)

func _update_renderer_scene(world_pos: Vector2i, entry: Dictionary) -> void:
	if editor.renderer == null:
		editor._mark_renderer_dirty()
		return
	editor.renderer.update_scene(world_pos, entry)

func _update_renderer_terrain(world_pos: Vector2i, source_id: int) -> void:
	if editor.renderer == null:
		editor._mark_renderer_dirty()
		return
	editor.renderer.update_terrain_cell(world_pos, source_id)

func _tile_layer_has_cell(layer_name: String, local_pos: Vector2i) -> bool:
	if editor.renderer == null:
		return false
	var layer = editor.renderer.get_tile_layer(layer_name)
	if layer == null:
		return false
	return layer.get_cell_source_id(local_pos) != -1

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
	if editor.renderer == null:
		_terrain_dirty_valid = false
		return
	editor.renderer.rebuild_terrain_region(_terrain_dirty_min, _terrain_dirty_max)
	_terrain_dirty_valid = false

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

func _flags_matrix_map() -> Dictionary:
	var mapping: Dictionary = {}
	for transpose in [false, true]:
		for flip_h in [false, true]:
			for flip_v in [false, true]:
				var mat := _flags_to_matrix(flip_h, flip_v, transpose)
				mapping[_matrix_key(mat)] = {
					"flip_h": flip_h,
					"flip_v": flip_v,
					"transpose": transpose,
				}
	return mapping

func _flags_to_matrix(flip_h: bool, flip_v: bool, transpose: bool) -> Array:
	var mat := [1, 0, 0, 1]
	if transpose:
		mat = [0, 1, 1, 0]
	if flip_h:
		mat = _matrix_mul(_flip_matrix(true, true), mat)
	if flip_v:
		mat = _matrix_mul(_flip_matrix(true, false), mat)
	return mat

func _rotation_matrix(rot: int) -> Array:
	match rot & 3:
		1:
			return [0, -1, 1, 0]
		2:
			return [-1, 0, 0, -1]
		3:
			return [0, 1, -1, 0]
		_:
			return [1, 0, 0, 1]

func _flip_matrix(enabled: bool, horizontal: bool) -> Array:
	if not enabled:
		return [1, 0, 0, 1]
	if horizontal:
		return [-1, 0, 0, 1]
	return [1, 0, 0, -1]

func _matrix_mul(a: Array, b: Array) -> Array:
	return [
		int(a[0]) * int(b[0]) + int(a[1]) * int(b[2]),
		int(a[0]) * int(b[1]) + int(a[1]) * int(b[3]),
		int(a[2]) * int(b[0]) + int(a[3]) * int(b[2]),
		int(a[2]) * int(b[1]) + int(a[3]) * int(b[3]),
	]

func _matrix_key(mat: Array) -> String:
	return "%s,%s,%s,%s" % [str(mat[0]), str(mat[1]), str(mat[2]), str(mat[3])]
