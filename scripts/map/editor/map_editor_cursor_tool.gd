class_name MapEditorCursorTool
extends RefCounted

var editor

var selecting := false
var dragging := false
var selection_start := Vector2i.ZERO
var selection_end := Vector2i.ZERO
var drag_start := Vector2i.ZERO
var drag_offset := Vector2i.ZERO

var selected_rect := Rect2i()
var selected_entries: Array = []

func setup(editor_ref) -> void:
	editor = editor_ref

func handle_mouse_button(event: InputEventMouseButton) -> void:
	if editor == null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var tile_pos = editor._get_mouse_tile()
			if _has_selection() and _point_in_rect(tile_pos, selected_rect):
				dragging = true
				drag_start = tile_pos
				drag_offset = Vector2i.ZERO
				editor._record_undo()
				return
			selecting = true
			selection_start = tile_pos
			selection_end = tile_pos
			editor._sync_map_data_tile_layers()
			_drag_update_rect()
		else:
			if dragging:
				_apply_drag()
				dragging = false
				return
			if selecting:
				selecting = false
				_finalize_selection()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var tile = editor._get_mouse_tile()
		editor._open_object_inspector_at(tile)

func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if editor == null:
		return
	if selecting:
		selection_end = editor._get_mouse_tile()
		_drag_update_rect()
		return
	if dragging:
		var current = editor._get_mouse_tile()
		drag_offset = current - drag_start
		editor._set_cursor_rect(selected_rect, true, drag_offset)

func _has_selection() -> bool:
	return selected_rect.size.x > 0 and selected_rect.size.y > 0

func _drag_update_rect() -> void:
	var min_x = min(selection_start.x, selection_end.x)
	var min_y = min(selection_start.y, selection_end.y)
	var max_x = max(selection_start.x, selection_end.x)
	var max_y = max(selection_start.y, selection_end.y)
	selected_rect = Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))
	editor._set_cursor_rect(selected_rect, true, Vector2i.ZERO)

func _finalize_selection() -> void:
	if not _has_selection():
		editor._set_cursor_rect(Rect2i(), false, Vector2i.ZERO)
		selected_entries.clear()
		return
	editor._sync_map_data_tile_layers()
	selected_entries = _collect_entries_in_rect(selected_rect)

func _apply_drag() -> void:
	if drag_offset == Vector2i.ZERO:
		editor._set_cursor_rect(selected_rect, true, Vector2i.ZERO)
		return
	if editor.map_data == null:
		return
	editor._sync_map_data_tile_layers()
	var layers = editor.map_data.layers
	var new_entries: Dictionary = {}
	for layer_name in ["hazard", "deco", "block", "terrain", "object"]:
		var entries: Array = layers.get(layer_name, [])
		var kept: Array = []
		for item in entries:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = item
			var pos = editor._vec2i_from_value(entry.get("pos", null))
			if _point_in_rect(pos, selected_rect):
				continue
			kept.append(entry)
		new_entries[layer_name] = kept

	for item in selected_entries:
		var layer := str(item.get("layer", ""))
		var entry: Dictionary = item.get("entry", {}).duplicate(true)
		var pos = editor._vec2i_from_value(entry.get("pos", null))
		var new_pos = pos + drag_offset
		entry["pos"] = [new_pos.x, new_pos.y]
		new_entries[layer].append(entry)

	for layer_name in new_entries.keys():
		layers[layer_name] = new_entries[layer_name]

	editor.map_data.layers = layers
	editor._refresh_renderer()
	selected_rect.position += drag_offset
	drag_offset = Vector2i.ZERO
	selected_entries = _collect_entries_in_rect(selected_rect)
	editor._set_cursor_rect(selected_rect, true, Vector2i.ZERO)

func _collect_entries_in_rect(rect: Rect2i) -> Array:
	var out: Array = []
	if editor == null or editor.map_data == null:
		return out
	if editor.renderer != null:
		for layer_name in ["hazard", "deco", "block", "terrain"]:
			var layer = editor.renderer.get_tile_layer(layer_name)
			if layer == null:
				continue
			for cell in layer.get_used_cells():
				if not _point_in_rect(cell, rect):
					continue
				var entry: Dictionary = {
					"pos": [cell.x, cell.y],
					"source_id": layer.get_cell_source_id(cell),
				}
				if layer_name != "terrain":
					var atlas = layer.get_cell_atlas_coords(cell)
					entry["atlas"] = [atlas.x, atlas.y]
					entry["alt"] = layer.get_cell_alternative_tile(cell)
				out.append({"layer": layer_name, "entry": entry})
	var object_entries: Array = editor.map_data.layers.get("object", [])
	for item in object_entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var pos = editor._vec2i_from_value(entry.get("pos", null))
		if _point_in_rect(pos, rect):
			out.append({"layer": "object", "entry": entry})
	return out

func _point_in_rect(pos: Vector2i, rect: Rect2i) -> bool:
	return pos.x >= rect.position.x and pos.y >= rect.position.y and pos.x < rect.position.x + rect.size.x and pos.y < rect.position.y + rect.size.y
