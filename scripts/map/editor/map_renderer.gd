class_name MapRenderer
extends Node2D

@export var tile_set: TileSet = preload("res://objs/tiles.tres")
@export var layer_texture_filter := CanvasItem.TEXTURE_FILTER_NEAREST

var catalog: TileCatalog
var tile_layers: Dictionary = {}
var scene_root: Node2D
var _terrain_map: Dictionary = {}
var _scene_nodes: Dictionary = {}

const LAYER_ORDER := [
	{"name": "deco", "z": -30},
	{"name": "hazard", "z": -20},
	{"name": "terrain", "z": -10},
	{"name": "block", "z": -10},
	{"name": "object", "z": 20},
]

func render_map(map_data: MapData) -> void:
	if tile_set == null or map_data == null:
		return
	catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	_clear_layers()
	_terrain_map.clear()
	_render_layers(map_data)

func _ensure_layers() -> void:
	for entry in LAYER_ORDER:
		var _name := str(entry["name"])
		var _z_index := int(entry["z"])
		if _name == "object":
			if scene_root == null:
				scene_root = Node2D.new()
				scene_root.name = "ObjectTiles"
				add_child(scene_root)
			scene_root.z_index = _z_index
			continue
		if not tile_layers.has(_name):
			var layer := TileMapLayer.new()
			layer.name = _name.capitalize()
			layer.tile_set = tile_set
			layer.z_index = z_index
			layer.texture_filter = layer_texture_filter
			add_child(layer)
			tile_layers[_name] = layer
		else:
			var existing = tile_layers[_name]
			if existing is TileMapLayer:
				var layer := existing as TileMapLayer
				layer.tile_set = tile_set
				layer.z_index = _z_index
				layer.texture_filter = layer_texture_filter

func _clear_layers() -> void:
	for key in tile_layers.keys():
		var layer = tile_layers[key]
		if layer is TileMapLayer:
			(layer as TileMapLayer).clear()
	if scene_root != null:
		for child in scene_root.get_children():
			child.queue_free()
	_scene_nodes.clear()

func _render_layers(map_data: MapData) -> void:
	var terrain_groups: Dictionary = {}
	var layers := map_data.layers
	var base := Vector2i.ZERO
	_apply_layer_tiles("hazard", layers.get("hazard", []), base)
	_apply_layer_tiles("deco", layers.get("deco", []), base)
	_apply_layer_tiles("block", layers.get("block", []), base)
	_collect_terrain_cells(terrain_groups, layers.get("terrain", []), base)
	_spawn_scene_entries(layers.get("object", []), base)
	_apply_terrain_groups(terrain_groups)

func _resolve_tile_layer(layer_name: String) -> String:
	match layer_name:
		"block", "terrain":
			return layer_name
		_:
			return layer_name

func get_tile_layer(layer_name: String) -> TileMapLayer:
	var resolved := _resolve_tile_layer(layer_name)
	if not tile_layers.has(resolved):
		return null
	var layer = tile_layers[resolved]
	if layer is TileMapLayer:
		return layer as TileMapLayer
	return null

func _scene_cell_offset() -> Vector2:
	return Vector2(MapData.TILE_SIZE * 0.5, MapData.TILE_SIZE * 0.5)

func _apply_layer_tiles(layer_name: String, entries: Array, base: Vector2i) -> void:
	var resolved := _resolve_tile_layer(layer_name)
	if not tile_layers.has(resolved):
		return
	var layer = tile_layers[resolved]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var local_pos := _vec2i_from_value(entry.get("pos", null))
		var world_pos := base + local_pos
		var source_id: int = TileCatalog.INVALID_SOURCE
		if entry.has("source_id"):
			source_id = int(entry.get("source_id", TileCatalog.INVALID_SOURCE))
		else:
			var source_name := str(entry.get("source", ""))
			source_id = catalog.get_source_id(source_name)
		if source_id == TileCatalog.INVALID_SOURCE:
			continue
		var atlas := _vec2i_from_value(entry.get("atlas", [0, 0]))
		var flags := int(entry.get("alt", 0))
		tile_layer.set_cell(world_pos, source_id, atlas, flags)

func _collect_terrain_cells(groups: Dictionary, entries: Array, base: Vector2i) -> void:
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var info: Dictionary = {}
		if entry.has("source_id"):
			info = catalog.get_terrain_info_by_id(int(entry.get("source_id", TileCatalog.INVALID_SOURCE)))
		else:
			var source_name := str(entry.get("source", ""))
			info = catalog.get_terrain_info(source_name)
		if info.size() == 0:
			continue
		var local_pos := _vec2i_from_value(entry.get("pos", null))
		var world_pos := base + local_pos
		_terrain_map[world_pos] = info
		var key := "%s:%s" % [str(info["terrain_set"]), str(info["terrain"])]
		if not groups.has(key):
			groups[key] = {
				"info": info,
				"cells": [],
			}
		var group: Dictionary = groups[key]
		group["cells"].append(world_pos)

func _apply_terrain_groups(groups: Dictionary) -> void:
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	for key in groups.keys():
		var group: Dictionary = groups[key]
		var info: Dictionary = group.get("info", {})
		var cells: Array = group.get("cells", [])
		if info.size() == 0 or cells.is_empty():
			continue
		var terrain_set := int(info.get("terrain_set", 0))
		var terrain := int(info.get("terrain", 0))
		tile_layer.set_cells_terrain_connect(cells, terrain_set, terrain, true)

func _spawn_scene_entries(entries: Array, base: Vector2i) -> void:
	if scene_root == null:
		return
	var offset := _scene_cell_offset()
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var scene_path := str(entry.get("scene", ""))
		if scene_path == "":
			continue
		var packed := load(scene_path)
		if not (packed is PackedScene):
			continue
		var node = (packed as PackedScene).instantiate()
		if node is Node2D:
			var local_pos = _vec2i_from_value(entry.get("pos", null))
			var world_pos = Vector2(base + local_pos) * MapData.TILE_SIZE + offset
			var node2d := node as Node2D
			node2d.position = world_pos
			var rot := int(entry.get("rot", 0))
			var fh := bool(entry.get("fh", false))
			var fv := bool(entry.get("fv", false))
			if rot != 0:
				node2d.rotation = deg_to_rad(90.0 * float(rot))
			if fh or fv:
				var _scale := node2d.scale
				if fh:
					_scale.x *= -1.0
				if fv:
					_scale.y *= -1.0
				node2d.scale = _scale
		scene_root.add_child(node)
		if node.has_method("apply_map_entry"):
			node.call_deferred("apply_map_entry", entry)
		var key := base + _vec2i_from_value(entry.get("pos", null))
		_scene_nodes[key] = node

func update_tile(layer_name: String, world_pos: Vector2i, entry: Dictionary) -> void:
	if tile_set == null:
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	var resolved := _resolve_tile_layer(layer_name)
	if not tile_layers.has(resolved):
		return
	var layer = tile_layers[resolved]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	if entry.is_empty():
		tile_layer.set_cell(world_pos, -1)
		return
	var source_id: int = TileCatalog.INVALID_SOURCE
	if entry.has("source_id"):
		source_id = int(entry.get("source_id", TileCatalog.INVALID_SOURCE))
	else:
		var source_name := str(entry.get("source", ""))
		source_id = catalog.get_source_id(source_name)
	if source_id == TileCatalog.INVALID_SOURCE:
		tile_layer.set_cell(world_pos, -1)
		return
	var atlas := _vec2i_from_value(entry.get("atlas", [0, 0]))
	var flags := int(entry.get("alt", 0))
	tile_layer.set_cell(world_pos, source_id, atlas, flags)

func update_scene(world_pos: Vector2i, entry: Dictionary) -> void:
	if tile_set == null:
		return
	_ensure_layers()
	_remove_scene_at(world_pos)
	if entry.is_empty():
		return
	var scene_path := str(entry.get("scene", ""))
	if scene_path == "":
		return
	var packed := load(scene_path)
	if not (packed is PackedScene):
		return
	var node = (packed as PackedScene).instantiate()
	if node is Node2D:
		var node2d := node as Node2D
		node2d.position = Vector2(world_pos) * MapData.TILE_SIZE + _scene_cell_offset()
		var rot := int(entry.get("rot", 0))
		var fh := bool(entry.get("fh", false))
		var fv := bool(entry.get("fv", false))
		if rot != 0:
			node2d.rotation = deg_to_rad(90.0 * float(rot))
		if fh or fv:
			var scale := node2d.scale
			if fh:
				scale.x *= -1.0
			if fv:
				scale.y *= -1.0
			node2d.scale = scale
	scene_root.add_child(node)
	if node.has_method("apply_map_entry"):
		node.call_deferred("apply_map_entry", entry)
	_scene_nodes[world_pos] = node

func update_terrain_cell(world_pos: Vector2i, source_id: int) -> void:
	if tile_set == null:
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	if source_id == TileCatalog.INVALID_SOURCE:
		if _terrain_map.has(world_pos):
			_terrain_map.erase(world_pos)
		tile_layer.set_cell(world_pos, -1)
		_update_terrain_neighbors(world_pos)
		return
	var info := catalog.get_terrain_info_by_id(source_id)
	if info.size() == 0:
		if _terrain_map.has(world_pos):
			_terrain_map.erase(world_pos)
		tile_layer.set_cell(world_pos, -1)
		return
	_terrain_map[world_pos] = info
	_update_terrain_neighbors(world_pos)

func set_terrain_cell_raw(world_pos: Vector2i, source_id: int) -> void:
	if tile_set == null:
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	if source_id == TileCatalog.INVALID_SOURCE:
		if _terrain_map.has(world_pos):
			_terrain_map.erase(world_pos)
		tile_layer.set_cell(world_pos, -1)
		return
	var info := catalog.get_terrain_info_by_id(source_id)
	if info.size() == 0:
		if _terrain_map.has(world_pos):
			_terrain_map.erase(world_pos)
		tile_layer.set_cell(world_pos, -1)
		return
	_terrain_map[world_pos] = info

func update_terrain_region(points: Array[Vector2i]) -> void:
	if tile_set == null:
		return
	if points.is_empty():
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	var region: Dictionary = {}
	for pos in points:
		for y in range(-1, 2):
			for x in range(-1, 2):
				region[pos + Vector2i(x, y)] = true
	var groups: Dictionary = {}
	for key in region.keys():
		if typeof(key) != TYPE_VECTOR2I:
			continue
		var pos: Vector2i = key
		if not _terrain_map.has(pos):
			continue
		var info: Dictionary = _terrain_map[pos]
		var terrain_set := int(info.get("terrain_set", 0))
		var terrain := int(info.get("terrain", 0))
		var group_key := "%s:%s" % [str(terrain_set), str(terrain)]
		if not groups.has(group_key):
			groups[group_key] = {
				"terrain_set": terrain_set,
				"terrain": terrain,
				"cells": [],
			}
		var group: Dictionary = groups[group_key]
		group["cells"].append(pos)
	for group_key in groups.keys():
		var group: Dictionary = groups[group_key]
		var cells: Array = group.get("cells", [])
		if cells.is_empty():
			continue
		tile_layer.set_cells_terrain_connect(cells, int(group["terrain_set"]), int(group["terrain"]), true)

func update_terrain_rect(min_pos: Vector2i, max_pos: Vector2i) -> void:
	if tile_set == null:
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	var start_x = min(min_pos.x, max_pos.x)
	var end_x = max(min_pos.x, max_pos.x)
	var start_y = min(min_pos.y, max_pos.y)
	var end_y = max(min_pos.y, max_pos.y)
	var groups: Dictionary = {}
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var pos := Vector2i(x, y)
			if not _terrain_map.has(pos):
				continue
			var info: Dictionary = _terrain_map[pos]
			var terrain_set := int(info.get("terrain_set", 0))
			var terrain := int(info.get("terrain", 0))
			var group_key := "%s:%s" % [str(terrain_set), str(terrain)]
			if not groups.has(group_key):
				groups[group_key] = {
					"terrain_set": terrain_set,
					"terrain": terrain,
					"cells": [],
				}
			var group: Dictionary = groups[group_key]
			group["cells"].append(pos)
	for group_key in groups.keys():
		var group: Dictionary = groups[group_key]
		var cells: Array = group.get("cells", [])
		if cells.is_empty():
			continue
		tile_layer.set_cells_terrain_connect(cells, int(group["terrain_set"]), int(group["terrain"]), true)

func rebuild_terrain_region(min_pos: Vector2i, max_pos: Vector2i) -> void:
	if tile_set == null:
		return
	if catalog == null:
		catalog = TileCatalog.build(tile_set)
	_ensure_layers()
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	var pad := Vector2i(1, 1)
	var min_x := int(min(min_pos.x, max_pos.x)) - pad.x
	var max_x := int(max(min_pos.x, max_pos.x)) + pad.x
	var min_y := int(min(min_pos.y, max_pos.y)) - pad.y
	var max_y := int(max(min_pos.y, max_pos.y)) + pad.y
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			tile_layer.set_cell(Vector2i(x, y), -1)
	var groups: Dictionary = {}
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2i(x, y)
			if not _terrain_map.has(pos):
				continue
			var info: Dictionary = _terrain_map[pos]
			var terrain_set := int(info.get("terrain_set", 0))
			var terrain := int(info.get("terrain", 0))
			var group_key := "%s:%s" % [str(terrain_set), str(terrain)]
			if not groups.has(group_key):
				groups[group_key] = {
					"terrain_set": terrain_set,
					"terrain": terrain,
					"cells": [],
				}
			var group: Dictionary = groups[group_key]
			group["cells"].append(pos)
	for group_key in groups.keys():
		var group: Dictionary = groups[group_key]
		var cells: Array = group.get("cells", [])
		if cells.is_empty():
			continue
		tile_layer.set_cells_terrain_connect(cells, int(group["terrain_set"]), int(group["terrain"]), true)

func _update_terrain_neighbors(center: Vector2i) -> void:
	if not tile_layers.has("terrain"):
		return
	var layer = tile_layers["terrain"]
	if not (layer is TileMapLayer):
		return
	var tile_layer := layer as TileMapLayer
	var groups: Dictionary = {}
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var pos := Vector2i(x, y)
			if not _terrain_map.has(pos):
				continue
			var info: Dictionary = _terrain_map[pos]
			var terrain_set := int(info.get("terrain_set", 0))
			var terrain := int(info.get("terrain", 0))
			var key := "%s:%s" % [str(terrain_set), str(terrain)]
			if not groups.has(key):
				groups[key] = {
					"terrain_set": terrain_set,
					"terrain": terrain,
					"cells": [],
				}
			var group: Dictionary = groups[key]
			group["cells"].append(pos)
	for key in groups.keys():
		var group: Dictionary = groups[key]
		var cells: Array = group.get("cells", [])
		if cells.is_empty():
			continue
		tile_layer.set_cells_terrain_connect(cells, int(group["terrain_set"]), int(group["terrain"]), true)

func _remove_scene_at(world_pos: Vector2i) -> void:
	if _scene_nodes.has(world_pos):
		var node = _scene_nodes[world_pos]
		if node is Node:
			node.queue_free()
		_scene_nodes.erase(world_pos)
		return
	if scene_root == null:
		return
	var target_pos := Vector2(world_pos) * MapData.TILE_SIZE + _scene_cell_offset()
	for child in scene_root.get_children():
		if child is Node2D:
			var node2d := child as Node2D
			if node2d.position == target_pos:
				child.queue_free()
				return

func _vec2i_from_value(value) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO



