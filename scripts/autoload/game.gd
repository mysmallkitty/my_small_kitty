extends Node

const WIP_DIR := "user://maps/wip"
const DOWNLOADED_DIR := "user://maps"

var current_map_path: String = ""
var current_map_id: String = ""
var current_map_data: MapData
var map_cache: Dictionary = {}
var random_bg_path: String = ""
var master_volume := 1.0
var bgm_volume := 1.0
var sfx_volume := 1.0

func _ready() -> void:
	_apply_audio()
	Engine.max_fps = 60

func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(WIP_DIR)
	DirAccess.make_dir_recursive_absolute(DOWNLOADED_DIR)

func cache_map(map_id: String, map_data: MapData) -> void:
	if map_id == "" or map_data == null:
		return
	map_cache[map_id] = map_data

func get_cached_map(map_id: String) -> MapData:
	if map_cache.has(map_id):
		return map_cache[map_id]
	return null

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()

func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("bgm", bgm_volume)
	_set_bus_volume("sfx", sfx_volume)

func _set_bus_volume(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := linear_to_db(value)
	AudioServer.set_bus_volume_db(idx, db)
