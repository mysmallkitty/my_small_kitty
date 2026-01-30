class_name MapData
extends RefCounted

const TILE_SIZE := 8
const MIN_CHUNK_SIZE := Vector2i(40, 23)
const COMPACT_VERSION := 7
const INVALID_SOURCE_ID := -2147483648

var version := COMPACT_VERSION
var metadata := _make_metadata()
var chunks: Array[ChunkData] = []
var start_chunk_id := ""
var layers: Dictionary = {}
var spawn := Vector2i(3, 3)

func _init() -> void:
	layers = _make_layers()

static func _make_layers() -> Dictionary:
	return {
		"object": [],
		"deco": [],
		"block": [],
		"terrain": [],
		"hazard": [],
	}

static func _make_metadata() -> Dictionary:
	return {
		"title": "",
		"detail": "",
		"map_id": -1,
		"rating": 1,
		"bg": "",
		"verified_hash": "",
	}

static func _normalize_metadata(raw: Dictionary) -> Dictionary:
	var out := _make_metadata()
	if raw.has("title"):
		out["title"] = str(raw.get("title", ""))
	if raw.has("detail"):
		out["detail"] = str(raw.get("detail", ""))
	if raw.has("map_id"):
		out["map_id"] = int(raw.get("map_id", -1))
	if raw.has("rating"):
		out["rating"] = clampi(int(raw.get("rating", 1)), 1, 8)
	if raw.has("bg"):
		out["bg"] = str(raw.get("bg", ""))
	if raw.has("verified_hash"):
		out["verified_hash"] = str(raw.get("verified_hash", ""))
	return out

static func create_debug() -> MapData:
	var map := MapData.new()
	var chunk_a := ChunkData.new()
	chunk_a.id = _make_chunk_id()
	chunk_a.pos = Vector2i(0, 0)
	chunk_a.size = MIN_CHUNK_SIZE
	map.chunks.append(chunk_a)

	var chunk_b := ChunkData.new()
	chunk_b.id = _make_chunk_id()
	chunk_b.pos = Vector2i(MIN_CHUNK_SIZE.x, 0)
	chunk_b.size = MIN_CHUNK_SIZE
	map.chunks.append(chunk_b)

	map.start_chunk_id = chunk_a.id
	map.spawn = chunk_a.pos + Vector2i(3, 3)
	return map

func to_compact_dict() -> Dictionary:
	var name_table: Array[String] = []
	var name_index: Dictionary = {}
	var scene_table: Array[String] = []
	var scene_index: Dictionary = {}
	var chunks_out: Array = []

	for chunk in chunks:
		chunks_out.append([
			chunk.id,
			chunk.pos.x,
			chunk.pos.y,
			chunk.size.x,
			chunk.size.y,
		])

	var layers_compact := _compact_layers(layers, name_table, name_index, scene_table, scene_index)
	var meta := _normalize_metadata(metadata)
	var out: Dictionary = {
		"v": COMPACT_VERSION,
		"meta": meta,
		"s": start_chunk_id,
		"p": [spawn.x, spawn.y],
		"c": chunks_out,
	}
	if not layers_compact.is_empty():
		out["layers"] = layers_compact
	if name_table.size() > 0:
		out["sn"] = name_table
	if scene_table.size() > 0:
		out["sp"] = scene_table
	return out

static func from_compact_dict(data: Dictionary) -> MapData:
	var map := MapData.new()
	map.version = int(data.get("v", COMPACT_VERSION))
	var meta_raw: Dictionary = data.get("meta", {})
	map.metadata = _normalize_metadata(meta_raw)
	map.start_chunk_id = str(data.get("s", ""))
	var has_spawn := data.has("p")
	if has_spawn:
		map.spawn = _vec2i_from_value(data.get("p", null))

	var name_table: Array = data.get("sn", [])
	var scene_table: Array = data.get("sp", [])
	if data.has("layers") and typeof(data.get("layers", null)) == TYPE_DICTIONARY:
		map.layers = _expand_compact_layers(data.get("layers", {}), name_table, scene_table)
	else:
		map.layers = _make_layers()

	var chunk_list: Array = data.get("c", [])
	for raw_entry in chunk_list:
		if typeof(raw_entry) != TYPE_ARRAY:
			continue
		var entry: Array = raw_entry
		if entry.size() < 5:
			continue
		var chunk := ChunkData.new()
		chunk.id = str(entry[0])
		chunk.pos = Vector2i(int(entry[1]), int(entry[2]))
		chunk.size = Vector2i(int(entry[3]), int(entry[4]))
		map.chunks.append(chunk)
	if not has_spawn:
		_set_default_spawn(map)
	return map

func get_chunk_by_id(chunk_id: String) -> ChunkData:
	for chunk in chunks:
		if chunk.id == chunk_id:
			return chunk
	return null

func get_chunk_at_tile(tile_pos: Vector2i) -> ChunkData:
	for chunk in chunks:
		if _tile_in_chunk(tile_pos, chunk):
			return chunk
	return null

func get_adjacent_chunk(chunk: ChunkData, dir: Vector2i) -> ChunkData:
	var a_min := chunk.pos
	var a_max := chunk.pos + chunk.size
	for other in chunks:
		if other == chunk:
			continue
		var b_min := other.pos
		var b_max := other.pos + other.size
		if dir == Vector2i.LEFT:
			if b_max.x == a_min.x and _ranges_overlap(a_min.y, a_max.y, b_min.y, b_max.y):
				return other
		elif dir == Vector2i.RIGHT:
			if b_min.x == a_max.x and _ranges_overlap(a_min.y, a_max.y, b_min.y, b_max.y):
				return other
		elif dir == Vector2i.UP:
			if b_max.y == a_min.y and _ranges_overlap(a_min.x, a_max.x, b_min.x, b_max.x):
				return other
		elif dir == Vector2i.DOWN:
			if b_min.y == a_max.y and _ranges_overlap(a_min.x, a_max.x, b_min.x, b_max.x):
				return other
	return null

func get_adjacent_chunk_for_tile(chunk: ChunkData, tile_pos: Vector2i, dir: Vector2i) -> ChunkData:
	for other in chunks:
		if other == chunk:
			continue
		if dir == Vector2i.LEFT:
			if other.pos.x + other.size.x == chunk.pos.x and tile_pos.y >= other.pos.y and tile_pos.y < other.pos.y + other.size.y:
				return other
		elif dir == Vector2i.RIGHT:
			if other.pos.x == chunk.pos.x + chunk.size.x and tile_pos.y >= other.pos.y and tile_pos.y < other.pos.y + other.size.y:
				return other
		elif dir == Vector2i.UP:
			if other.pos.y + other.size.y == chunk.pos.y and tile_pos.x >= other.pos.x and tile_pos.x < other.pos.x + other.size.x:
				return other
		elif dir == Vector2i.DOWN:
			if other.pos.y == chunk.pos.y + chunk.size.y and tile_pos.x >= other.pos.x and tile_pos.x < other.pos.x + other.size.x:
				return other
	return null

static func _tile_in_chunk(tile_pos: Vector2i, chunk: ChunkData) -> bool:
	return tile_pos.x >= chunk.pos.x \
		and tile_pos.y >= chunk.pos.y \
		and tile_pos.x < chunk.pos.x + chunk.size.x \
		and tile_pos.y < chunk.pos.y + chunk.size.y

static func _ranges_overlap(a_min: int, a_max: int, b_min: int, b_max: int) -> bool:
	return a_min < b_max and b_min < a_max

static func _make_chunk_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stamp := Time.get_unix_time_from_system()
	return "%s_%s" % [str(stamp), str(rng.randi())]

static func _get_array_from_dict(data: Dictionary, key: String) -> Array:
	if data.has(key) and typeof(data[key]) == TYPE_ARRAY:
		return data[key]
	return []

static func _compact_layers(_layers: Dictionary, name_table: Array[String], name_index: Dictionary, scene_table: Array[String], scene_index: Dictionary) -> Dictionary:
	var layers_compact: Dictionary = {}
	var hazard_entries := _compact_tile_entries(_get_array_from_dict(_layers, "hazard"), name_table, name_index)
	if not hazard_entries.is_empty():
		layers_compact["hazard"] = hazard_entries
	var deco_entries := _compact_tile_entries(_get_array_from_dict(_layers, "deco"), name_table, name_index)
	if not deco_entries.is_empty():
		layers_compact["deco"] = deco_entries
	var block_entries := _compact_tile_entries(_get_array_from_dict(_layers, "block"), name_table, name_index)
	if not block_entries.is_empty():
		layers_compact["block"] = block_entries
	var terrain_entries := _compact_terrain_entries(_get_array_from_dict(_layers, "terrain"), name_table, name_index)
	if not terrain_entries.is_empty():
		layers_compact["terrain"] = terrain_entries
	var object_entries := _compact_scene_entries(_get_array_from_dict(_layers, "object"), scene_table, scene_index)
	if not object_entries.is_empty():
		layers_compact["object"] = object_entries
	return layers_compact

static func _compact_tile_entries(entries: Array, name_table: Array[String], name_index: Dictionary) -> Array:
	var out: Array = []
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var pos := _vec2i_from_value(entry.get("pos", null))
		var source_id := _encode_source_id(entry, name_table, name_index)
		if source_id == INVALID_SOURCE_ID:
			continue
		var atlas := _vec2i_from_value(entry.get("atlas", [0, 0]))
		var alt := int(entry.get("alt", 0))
		out.append(pos.x)
		out.append(pos.y)
		out.append(source_id)
		out.append(atlas.x)
		out.append(atlas.y)
		out.append(alt)
	return out

static func _compact_terrain_entries(entries: Array, name_table: Array[String], name_index: Dictionary) -> Array:
	var out: Array = []
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var pos := _vec2i_from_value(entry.get("pos", null))
		var source_id := _encode_source_id(entry, name_table, name_index)
		if source_id == INVALID_SOURCE_ID:
			continue
		out.append(pos.x)
		out.append(pos.y)
		out.append(source_id)
	return out

static func _compact_scene_entries(entries: Array, scene_table: Array[String], scene_index: Dictionary) -> Array:
	var out: Array = []
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var scene_path := str(entry.get("scene", ""))
		if scene_path == "":
			continue
		var index: int
		if scene_index.has(scene_path):
			index = int(scene_index[scene_path])
		else:
			index = scene_table.size()
			scene_table.append(scene_path)
			scene_index[scene_path] = index
		var pos := _vec2i_from_value(entry.get("pos", null))
		var rot := int(entry.get("rot", 0))
		var fh := bool(entry.get("fh", false))
		var fv := bool(entry.get("fv", false))
		var flags := (rot & 3) | (4 if fh else 0) | (8 if fv else 0)
		var data = entry.get("data", {})
		if typeof(data) != TYPE_DICTIONARY:
			data = {}
		out.append(pos.x)
		out.append(pos.y)
		out.append(index)
		out.append(flags)
		out.append(data)
	return out

static func _encode_source_id(entry: Dictionary, name_table: Array[String], name_index: Dictionary) -> int:
	if entry.has("source_id"):
		var raw_id = entry.get("source_id", INVALID_SOURCE_ID)
		if typeof(raw_id) == TYPE_INT or typeof(raw_id) == TYPE_FLOAT:
			return int(raw_id)
	var source_name := str(entry.get("source", ""))
	if source_name == "":
		return INVALID_SOURCE_ID
	if name_index.has(source_name):
		return -int(name_index[source_name]) - 1
	var index := name_table.size()
	name_table.append(source_name)
	name_index[source_name] = index
	return -index - 1

static func _expand_compact_layers(data: Dictionary, name_table: Array, scene_table: Array) -> Dictionary:
	var _layers := _make_layers()
	if data.has("hazard") and typeof(data["hazard"]) == TYPE_ARRAY:
		_layers["hazard"] = _expand_tile_entries(data["hazard"], name_table)
	if data.has("deco") and typeof(data["deco"]) == TYPE_ARRAY:
		_layers["deco"] = _expand_tile_entries(data["deco"], name_table)
	if data.has("block") and typeof(data["block"]) == TYPE_ARRAY:
		_layers["block"] = _expand_tile_entries(data["block"], name_table)
	if data.has("terrain") and typeof(data["terrain"]) == TYPE_ARRAY:
		_layers["terrain"] = _expand_terrain_entries(data["terrain"], name_table)
	if data.has("object") and typeof(data["object"]) == TYPE_ARRAY:
		_layers["object"] = _expand_scene_entries(data["object"], scene_table)
	return _layers

func compute_verified_hash() -> String:
	var parts: Array[String] = []
	parts.append("spawn:%d,%d" % [spawn.x, spawn.y])
	parts.append("chunks:%s" % _hash_chunks())
	parts.append("layers:%s" % _hash_layers())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(String("\n").join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()

func make_preview_map_data(view_px: Vector2i) -> MapData:
	var tiles_w := int(ceil(view_px.x / float(TILE_SIZE)))
	var tiles_h := int(ceil(view_px.y / float(TILE_SIZE)))
	tiles_w = max(1, tiles_w)
	tiles_h = max(1, tiles_h)

	var spawn_chunk := get_chunk_at_tile(spawn)
	if spawn_chunk == null and chunks.size() > 0:
		spawn_chunk = chunks[0]
	if spawn_chunk != null:
		tiles_w = min(tiles_w, spawn_chunk.size.x)
		tiles_h = min(tiles_h, spawn_chunk.size.y)
		tiles_w = max(1, tiles_w)
		tiles_h = max(1, tiles_h)

	var center := Vector2(spawn) + Vector2(1, 1)
	var half := Vector2(tiles_w, tiles_h) * 0.5
	var min_x := int(floor(center.x - half.x))
	var min_y := int(floor(center.y - half.y))
	var max_x := min_x + tiles_w - 1
	var max_y := min_y + tiles_h - 1

	if spawn_chunk != null:
		var chunk_min_x := spawn_chunk.pos.x
		var chunk_min_y := spawn_chunk.pos.y
		var chunk_max_x := spawn_chunk.pos.x + spawn_chunk.size.x - 1
		var chunk_max_y := spawn_chunk.pos.y + spawn_chunk.size.y - 1
		if min_x < chunk_min_x:
			min_x = chunk_min_x
			max_x = min_x + tiles_w - 1
		if max_x > chunk_max_x:
			max_x = chunk_max_x
			min_x = max_x - tiles_w + 1
		if min_y < chunk_min_y:
			min_y = chunk_min_y
			max_y = min_y + tiles_h - 1
		if max_y > chunk_max_y:
			max_y = chunk_max_y
			min_y = max_y - tiles_h + 1

	var offset := Vector2i(min_x, min_y)

	var preview := MapData.new()
	preview.metadata = metadata.duplicate(true)
	preview.layers = _make_layers()
	var chunk := ChunkData.new()
	chunk.id = _make_chunk_id()
	chunk.pos = Vector2i.ZERO
	chunk.size = Vector2i(tiles_w, tiles_h)
	preview.chunks.append(chunk)
	preview.start_chunk_id = chunk.id
	preview.spawn = Vector2i(spawn.x - offset.x, spawn.y - offset.y)
	preview.spawn.x = clampi(preview.spawn.x, 0, max(0, tiles_w - 2))
	preview.spawn.y = clampi(preview.spawn.y, 0, max(0, tiles_h - 2))

	for layer_name in ["hazard", "deco", "block", "terrain", "object"]:
		var entries: Array = layers.get(layer_name, [])
		var out: Array = []
		for item in entries:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = item
			var pos := _vec2i_from_value(entry.get("pos", null))
			if pos.x < min_x or pos.x > max_x or pos.y < min_y or pos.y > max_y:
				continue
			var new_entry: Dictionary = entry.duplicate(true)
			new_entry["pos"] = [pos.x - offset.x, pos.y - offset.y]
			out.append(new_entry)
		preview.layers[layer_name] = out
	return preview

func _hash_chunks() -> String:
	var chunk_items: Array[String] = []
	for chunk in chunks:
		chunk_items.append("%d,%d,%d,%d" % [chunk.pos.x, chunk.pos.y, chunk.size.x, chunk.size.y])
	chunk_items.sort()
	return String("|").join(chunk_items)

func _hash_layers() -> String:
	var layer_order := ["hazard", "deco", "block", "terrain", "object"]
	var layer_parts: Array[String] = []
	for layer_name in layer_order:
		var entries: Array = layers.get(layer_name, [])
		var entry_parts: Array[String] = []
		match layer_name:
			"object":
				for item in entries:
					if typeof(item) != TYPE_DICTIONARY:
						continue
					var entry: Dictionary = item
					var pos := _vec2i_from_value(entry.get("pos", null))
					var scene_path := str(entry.get("scene", ""))
					var rot := int(entry.get("rot", 0))
					var fh := bool(entry.get("fh", false))
					var fv := bool(entry.get("fv", false))
					entry_parts.append("%d,%d,%s,%d,%d,%d" % [pos.x, pos.y, scene_path, rot, (1 if fh else 0), (1 if fv else 0)])
			"terrain":
				for item in entries:
					if typeof(item) != TYPE_DICTIONARY:
						continue
					var entry: Dictionary = item
					var pos := _vec2i_from_value(entry.get("pos", null))
					var source_id := _encode_source_id_for_hash(entry)
					entry_parts.append("%d,%d,%s" % [pos.x, pos.y, source_id])
			_:
				for item in entries:
					if typeof(item) != TYPE_DICTIONARY:
						continue
					var entry: Dictionary = item
					var pos := _vec2i_from_value(entry.get("pos", null))
					var source_id := _encode_source_id_for_hash(entry)
					var atlas := _vec2i_from_value(entry.get("atlas", [0, 0]))
					var alt := int(entry.get("alt", 0))
					entry_parts.append("%d,%d,%s,%d,%d,%d" % [pos.x, pos.y, source_id, atlas.x, atlas.y, alt])
		entry_parts.sort()
		layer_parts.append("%s=%s" % [layer_name, String("|").join(entry_parts)])
	return String(";").join(layer_parts)

static func _encode_source_id_for_hash(entry: Dictionary) -> String:
	if entry.has("source_id"):
		var raw_id = entry.get("source_id", INVALID_SOURCE_ID)
		if typeof(raw_id) == TYPE_INT or typeof(raw_id) == TYPE_FLOAT:
			return "id:%d" % int(raw_id)
	var source_name := str(entry.get("source", ""))
	if source_name != "":
		return "name:%s" % source_name
	return "id:%d" % INVALID_SOURCE_ID

static func _expand_tile_entries(raw: Array, name_table: Array) -> Array:
	var out: Array = []
	var idx := 0
	while idx + 5 < raw.size():
		var x := int(raw[idx])
		var y := int(raw[idx + 1])
		var source_id := int(raw[idx + 2])
		var ax := int(raw[idx + 3])
		var ay := int(raw[idx + 4])
		var alt := int(raw[idx + 5])
		var entry := {
			"pos": [x, y],
			"atlas": [ax, ay],
			"alt": alt,
		}
		if source_id >= 0:
			entry["source_id"] = source_id
		else:
			var name_index := -source_id - 1
			if name_index >= 0 and name_index < name_table.size():
				entry["source"] = str(name_table[name_index])
			else:
				idx += 6
				continue
		out.append(entry)
		idx += 6
	return out

static func _expand_terrain_entries(raw: Array, name_table: Array) -> Array:
	var out: Array = []
	var idx := 0
	while idx + 2 < raw.size():
		var x := int(raw[idx])
		var y := int(raw[idx + 1])
		var source_id := int(raw[idx + 2])
		var entry := {
			"pos": [x, y],
		}
		if source_id >= 0:
			entry["source_id"] = source_id
		else:
			var name_index := -source_id - 1
			if name_index >= 0 and name_index < name_table.size():
				entry["source"] = str(name_table[name_index])
			else:
				idx += 3
				continue
		out.append(entry)
		idx += 3
	return out

static func _expand_scene_entries(raw: Array, scene_table: Array) -> Array:
	var out: Array = []
	var idx := 0
	while idx + 3 < raw.size():
		var x := int(raw[idx])
		var y := int(raw[idx + 1])
		var scene_idx := int(raw[idx + 2])
		if scene_idx < 0 or scene_idx >= scene_table.size():
			idx += 4
			if idx < raw.size() and typeof(raw[idx]) == TYPE_DICTIONARY:
				idx += 1
			continue
		var entry := {
			"pos": [x, y],
			"scene": str(scene_table[scene_idx]),
		}
		var flags := int(raw[idx + 3])
		var rot := flags & 3
		var fh := (flags & 4) != 0
		var fv := (flags & 8) != 0
		entry["rot"] = rot
		entry["fh"] = fh
		entry["fv"] = fv
		idx += 4
		var data := {}
		if idx < raw.size() and typeof(raw[idx]) == TYPE_DICTIONARY:
			data = raw[idx]
			idx += 1
		if typeof(data) == TYPE_DICTIONARY and not data.is_empty():
			entry["data"] = data
		out.append(entry)
	return out

static func _set_default_spawn(map: MapData) -> void:
	var start_chunk := map.get_chunk_by_id(map.start_chunk_id)
	if start_chunk == null and map.chunks.size() > 0:
		start_chunk = map.chunks[0]
	if start_chunk != null:
		map.spawn = start_chunk.pos + Vector2i(3, 3)
	else:
		map.spawn = Vector2i(3, 3)

static func _vec2i_from_value(value) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO
