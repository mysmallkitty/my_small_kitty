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
const PROFILE_SIZE := 16
const PROFILE_CODE_LEN := 256
const PROFILE_ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
const PROFILE_ALPHABET_32 := "lLpXrkbMmKVIGFECDBz6y4juD0mktnQP"
const PLAYER_SIZE_X := 9
const PLAYER_SIZE_Y := 8
const PLAYER_CODE_LEN := 72
const PLAYER_CODE_TOTAL_LEN := 73
const PLAYER_ALPHABET_64 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
var PLAYER_ALPHABET_32 = PLAYER_ALPHABET_64.substr(0, 32)
var _profile_texture_cache: Dictionary = {}
var _profile_palette: Array = []
var _player_texture_cache: Dictionary = {}
var _player_palette: Array = []

func _ready() -> void:
	_apply_audio()
	Engine.max_fps = 60
	_profile_palette = Palatte.new().colors_64
	_player_palette = _build_player_palette()

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

func get_profile_texture(code: String) -> Texture2D:
	if code.length() != PROFILE_CODE_LEN:
		return null
	if _profile_texture_cache.has(code):
		return _profile_texture_cache[code]
	var img := Image.create(PROFILE_SIZE, PROFILE_SIZE, false, Image.FORMAT_RGBA8)
	var idx := 0
	for y in range(PROFILE_SIZE):
		for x in range(PROFILE_SIZE):
			var ch := code.substr(idx, 1)
			var color_index := _profile_index_from_char(ch)
			var color = _profile_palette[color_index]
			img.set_pixel(x, y, color)
			idx += 1
	var tex := ImageTexture.create_from_image(img)
	_profile_texture_cache[code] = tex
	return tex

func get_player_texture(code: String) -> Texture2D:
	if code == "":
		return load("res://graphics/kitty.png")
	var decoded := decode_player_sprite(code)
	if decoded.is_empty():
		return load("res://graphics/kitty.png")
	var cache_key := str(decoded.get("prefix", "0")) + ":" + str(decoded.get("data", ""))
	if _player_texture_cache.has(cache_key):
		return _player_texture_cache[cache_key]
	var data: String = decoded.get("data", "")
	if data.length() != PLAYER_CODE_LEN:
		return load("res://graphics/kitty.png")
	var img := Image.create(PLAYER_SIZE_X, PLAYER_SIZE_Y, false, Image.FORMAT_RGBA8)
	var idx := 0
	for y in range(PLAYER_SIZE_Y):
		for x in range(PLAYER_SIZE_X):
			var ch := data.substr(idx, 1)
			var color_index := _player_index_from_char(ch)
			if color_index < 0 or color_index >= _player_palette.size():
				color_index = 0
			var color: Color = _player_palette[color_index]
			img.set_pixel(x, y, color)
			idx += 1
	var tex := ImageTexture.create_from_image(img)
	_player_texture_cache[cache_key] = tex
	return tex

func get_player_palette() -> Array:
	return _player_palette

func encode_player_sprite(indices: PackedInt32Array) -> String:
	print("debugpoint1")
	print(indices.size())
	if indices.size() != PLAYER_CODE_LEN:
		return ""
	var out := "1"
	var alphabet = PLAYER_ALPHABET_64
	for i in range(indices.size()):
		var idx := int(indices[i])
		if idx < 0 or idx >= alphabet.length():
			idx = 0
		out += alphabet[idx]
	return out

func decode_player_sprite(code: String) -> Dictionary:
	if code.length() == PLAYER_CODE_LEN:
		return {"prefix": "0", "data": code}
	if code.length() != PLAYER_CODE_TOTAL_LEN:
		return {}
	var prefix := code.substr(0, 1)
	var data := code.substr(1, PLAYER_CODE_LEN)
	if prefix != "0" and prefix != "1":
		return {}
	return {"prefix": prefix, "data": data}

func player_indices_from_code(code: String) -> PackedInt32Array:
	var decoded := decode_player_sprite(code)
	var data: String = decoded.get("data", "")
	var out := PackedInt32Array()
	out.resize(PLAYER_CODE_LEN)
	for i in range(PLAYER_CODE_LEN):
		if i >= data.length():
			out[i] = 0
		else:
			out[i] = _player_index_from_char(data.substr(i, 1))
	return out

func player_indices_from_kitty() -> PackedInt32Array:
	var tex := load("res://graphics/kitty.png")
	if tex == null or not (tex is Texture2D):
		return PackedInt32Array()
	var img := (tex as Texture2D).get_image()
	if img == null:
		return PackedInt32Array()
	var out := PackedInt32Array()
	out.resize(PLAYER_CODE_LEN)
	var idx := 0
	var w = min(PLAYER_SIZE_X, img.get_width())
	var h = min(PLAYER_SIZE_Y, img.get_height())
	for y in range(h):
		for x in range(w):
			var color := img.get_pixel(x, y)
			var palette_index := _player_palette_index_from_color(color)
			out[idx] = palette_index
			idx += 1
	for i in range(idx, PLAYER_CODE_LEN):
		out[i] = 0
	return out

func _player_palette_index_from_color(color: Color) -> int:
	if color.a <= 0.0:
		return 0
	for i in range(_player_palette.size()):
		if _player_palette[i].is_equal_approx(color):
			return i
	return 0

func _player_index_from_char(ch: String) -> int:
	var idx := PLAYER_ALPHABET_64.find(ch)
	if idx < 0:
		return 0
	return idx

func _build_player_palette() -> Array:
	var out: Array = []
	out.append(Color(0, 0, 0, 0))
	var base = Palatte.new().colors_64
	for c in base:
		out.append(c)
	return out

func profile_code_from_indices(indices: PackedInt32Array, use_64) -> String:
	var alphabets = PROFILE_ALPHABET if use_64 else PROFILE_ALPHABET_32
	if indices.size() != PROFILE_CODE_LEN:
		return ""
	var out := ""
	for i in range(indices.size()):
		var idx := int(indices[i])
		if idx < 0 or idx >= alphabets.length():
			idx = 0
		out += alphabets[idx]
	return out

func profile_indices_from_code(code: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PROFILE_CODE_LEN)
	for i in range(PROFILE_CODE_LEN):
		if i >= code.length():
			out[i] = 0
		else:
			out[i] = _profile_index_from_char(code.substr(i, 1))
	return out

func _profile_index_from_char(ch: String) -> int:
	var idx := PROFILE_ALPHABET.find(ch)
	if idx < 0:
		return 0
	return idx
