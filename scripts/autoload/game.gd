extends Node

const WIP_DIR := "user://maps/wip"
const DOWNLOADED_DIR := "user://maps"
const CACHE_DIR := "user://maps/cache"
const MAP_CACHE_DIR := "user://maps/cache/maps"
const PREVIEW_CACHE_DIR := "user://maps/cache/previews"
const CACHE_META_DIR := "user://maps/cache/meta"

var current_map_path: String = ""
var current_map_id: String = ""
var last_play_map_id: String = ""
var last_editor_map_path: String = ""
var return_scene: String = ""
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
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(MAP_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(PREVIEW_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(CACHE_META_DIR)

func cache_map(map_id: String, map_data: MapData) -> void:
	if map_id == "" or map_data == null:
		return
	map_cache[map_id] = map_data

func get_cached_map(map_id: String) -> MapData:
	if map_cache.has(map_id):
		return map_cache[map_id]
	return null

func get_rank_from_total_pp(pp) -> int:
	if pp < 500:
		return 1
	elif pp < 1000:
		return 2
	elif pp < 2500:
		return 3
	elif pp < 5000:
		return 4
	elif pp < 10000:
		return 5
	elif pp < 20000:
		return 6
	return 7

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

func _format_ticks(frames: int) -> String:
	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	if ticks <= 0:
		ticks = 60
	var total_seconds := frames / float(ticks)
	var minutes := int(total_seconds / 60)
	var seconds := int(total_seconds) % 60
	var frac := frames % ticks
	return "%02d:%02d:%02d" % [minutes, seconds, frac]
