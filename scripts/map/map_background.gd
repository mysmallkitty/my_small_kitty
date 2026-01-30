class_name MapBackground
extends Node2D

@export var background_paths: Array[String] = [
	"res://graphics/backgrounds/forest.png",
	"res://graphics/backgrounds/hill.png",
	"res://graphics/backgrounds/mountain.png",
	"res://graphics/backgrounds/mountain_night.png",
	"res://graphics/backgrounds/city.png",
	"res://graphics/backgrounds/cave.png",
]
@export var show_preview := true

@onready var fallback: Sprite2D = $Fallback
@onready var preview: MapPreview = $MapPreview

var _follow_camera: Camera2D
var _target_size := Vector2.ZERO

func _ready() -> void:
	z_index = -200
	if preview != null:
		preview.z_index = 100
	_show_random()

func set_map_data(map_data: MapData) -> void:
	if map_data == null:
		_show_random()
		return
	if not _set_background_from_map(map_data):
		_show_random()
	if preview != null and show_preview:
		preview.visible = true
		preview.set_map_data(map_data)
	elif preview != null:
		preview.visible = false

func set_follow_camera(camera: Camera2D) -> void:
	_follow_camera = camera
	_sync_to_camera()

func _show_random() -> void:
	if fallback == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if background_paths.is_empty():
		fallback.texture = null
		return
	var path := ""
	if Engine.has_singleton("Game") and Game.random_bg_path != "":
		if ResourceLoader.exists(Game.random_bg_path):
			path = Game.random_bg_path
	if path == "":
		path = background_paths[rng.randi_range(0, background_paths.size() - 1)]
		if Engine.has_singleton("Game"):
			Game.random_bg_path = path
	fallback.texture = load(path)
	fallback.visible = true
	if preview != null:
		preview.visible = false
	_update_fallback_layout()

func _set_background_from_map(map_data: MapData) -> bool:
	if fallback == null or map_data == null:
		return false
	var bg_name := str(map_data.metadata.get("bg", ""))
	if bg_name == "":
		bg_name = "black.png"
	var path := "res://graphics/backgrounds/%s" % bg_name
	if ResourceLoader.exists(path):
		fallback.texture = load(path)
		fallback.visible = true
		_update_fallback_layout()
		return true
	return false

func _update_fallback_layout() -> void:
	if fallback == null:
		return
	fallback.centered = false
	fallback.position = Vector2.ZERO
	if fallback.texture == null:
		return
	var tex_size := fallback.texture.get_size()
	if tex_size == Vector2.ZERO:
		return
	var target_size := _get_target_size()
	if target_size == Vector2.ZERO:
		return
	var _scale := Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)
	fallback.scale = _scale

func _process(_delta: float) -> void:
	if _follow_camera != null:
		_sync_to_camera()

func _sync_to_camera() -> void:
	if _follow_camera == null:
		return
	_target_size = _get_target_size()
	global_position = _follow_camera.global_position - (_target_size * 0.5)
	_update_fallback_layout()

func _get_target_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var size := viewport.get_visible_rect().size
	if _follow_camera != null:
		size /= _follow_camera.zoom
	return size

