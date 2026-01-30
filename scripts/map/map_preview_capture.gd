class_name MapPreviewCapture
extends Node

@export var tile_set: TileSet = preload("res://objs/tiles.tres")

func capture(map_data: MapData, size: Vector2i, scale: Vector2 = Vector2.ONE) -> Image:
	if map_data == null:
		return null
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var root := Node2D.new()
	viewport.add_child(root)
	var safe_scale := Vector2(max(scale.x, 0.0001), max(scale.y, 0.0001))
	root.scale = safe_scale

	var renderer := MapRenderer.new()
	renderer.tile_set = tile_set
	root.add_child(renderer)
	renderer.render_map(map_data)

	var spawn_center := Vector2(map_data.spawn + Vector2i(1, 1)) * MapData.TILE_SIZE
	renderer.position = -spawn_center + (Vector2(size) * 0.5 / safe_scale)

	await get_tree().process_frame
	await get_tree().process_frame
	var texture := viewport.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	viewport.queue_free()
	return image
