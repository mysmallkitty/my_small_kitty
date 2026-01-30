class_name MapIO
extends RefCounted

static func save_map(path: String, map_data: MapData) -> int:
	var file := _open_map_file(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data: Dictionary = map_data.to_compact_dict()
	var json_text := JSON.stringify(data, "")
	file.store_string(json_text)
	file.close()
	return OK

static func load_map(path: String) -> MapData:
	var file := _open_map_file(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed
	return map_from_dict(data)

static func map_from_dict(data: Dictionary) -> MapData:
	if data.has("v"):
		return MapData.from_compact_dict(data)
	return null

static func _open_map_file(path: String, mode: int) -> FileAccess:
	if _is_kittymap_path(path):
		if mode == FileAccess.READ:
			var raw := FileAccess.open(path, FileAccess.READ)
			if raw == null:
				return null
			var header := raw.get_buffer(4)
			raw.close()
			if header == "GCPF".to_utf8_buffer():
				return FileAccess.open_compressed(path, mode, FileAccess.COMPRESSION_GZIP)
			return FileAccess.open(path, mode)
		return FileAccess.open_compressed(path, mode, FileAccess.COMPRESSION_GZIP)
	return FileAccess.open(path, mode)

static func _is_kittymap_path(path: String) -> bool:
	return path.to_lower().ends_with(".kittymap")

static func map_to_bytes(map_data: MapData) -> PackedByteArray:
	var tmp_path := "user://maps/_tmp_upload_%s.kittymap" % str(Time.get_unix_time_from_system())
	var file := FileAccess.open_compressed(tmp_path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return PackedByteArray()
	var data: Dictionary = map_data.to_compact_dict()
	var json_text := JSON.stringify(data, "")
	file.store_string(json_text)
	file.close()
	var raw := FileAccess.open(tmp_path, FileAccess.READ)
	if raw == null:
		return PackedByteArray()
	var bytes := raw.get_buffer(raw.get_length())
	raw.close()
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	return bytes

