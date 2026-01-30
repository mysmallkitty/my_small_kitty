extends Node2D

@export var editor_path: NodePath

var editor: Node

func _ready() -> void:
	editor = get_node_or_null(editor_path)
	z_index = 200

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if editor == null:
		return
	if not editor.has_method("_get_editor_camera"):
		return
	var camera: Camera2D = editor._get_editor_camera()
	if camera == null:
		return
	_draw_grid(camera)
	_draw_chunks(camera)
	_draw_cursor_selection(camera)

func _draw_grid(camera: Camera2D) -> void:
	var map_data: MapData = editor.map_data
	if map_data == null:
		return
	var grid_color: Color = editor.grid_color
	var view_size := get_viewport_rect().size / camera.zoom
	var center := camera.get_screen_center_position()
	var top_left := center - view_size * 0.5
	var bottom_right := center + view_size * 0.5
	var start_x := int(floor(top_left.x / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var end_x := int(ceil(bottom_right.x / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var start_y := int(floor(top_left.y / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	var end_y := int(ceil(bottom_right.y / MapData.TILE_SIZE)) * MapData.TILE_SIZE
	for x in range(start_x, end_x + 1, MapData.TILE_SIZE):
		draw_line(Vector2(x, start_y), Vector2(x, end_y), grid_color, 1.0)
	for y in range(start_y, end_y + 1, MapData.TILE_SIZE):
		draw_line(Vector2(start_x, y), Vector2(end_x, y), grid_color, 1.0)

func _draw_chunks(camera: Camera2D) -> void:
	var map_data: MapData = editor.map_data
	if map_data == null:
		return
	var chunk_color: Color = editor.chunk_color
	var selected_color: Color = editor.chunk_selected_color
	var start_chunk: ChunkData = map_data.get_chunk_by_id(map_data.start_chunk_id)
	for chunk in map_data.chunks:
		var rect := _chunk_rect_pixels(chunk)
		var color := chunk_color
		if editor.selected_chunk != null and chunk == editor.selected_chunk:
			color = selected_color
		draw_rect(rect, color, false, 2.0)
		if chunk == start_chunk:
			var spawn_px := Vector2(map_data.spawn) * MapData.TILE_SIZE
			draw_rect(Rect2(spawn_px, Vector2(MapData.TILE_SIZE * 2, MapData.TILE_SIZE * 2)), color, false, 2.0)
		if editor.chunk_edit_mode and editor.selected_chunk != null and chunk == editor.selected_chunk:
			_draw_chunk_handles(chunk)

func _chunk_rect_pixels(chunk: ChunkData) -> Rect2:
	var inset := 1.0
	var rect := Rect2(Vector2(chunk.pos) * MapData.TILE_SIZE, Vector2(chunk.size) * MapData.TILE_SIZE)
	rect.position += Vector2(inset, inset)
	rect.size -= Vector2(inset * 2.0, inset * 2.0)
	return rect

func _draw_chunk_handles(chunk: ChunkData) -> void:
	var rect := _chunk_rect_pixels(chunk)
	var half = editor.CHUNK_HANDLE_SIZE * 0.5
	var handle_color = editor.chunk_selected_color
	var left_mid := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)
	var right_mid := Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y * 0.5)
	var top_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	var bottom_mid := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
	draw_rect(Rect2(left_mid - Vector2(half, half), Vector2(editor.CHUNK_HANDLE_SIZE, editor.CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(right_mid - Vector2(half, half), Vector2(editor.CHUNK_HANDLE_SIZE, editor.CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(top_mid - Vector2(half, half), Vector2(editor.CHUNK_HANDLE_SIZE, editor.CHUNK_HANDLE_SIZE)), handle_color, true)
	draw_rect(Rect2(bottom_mid - Vector2(half, half), Vector2(editor.CHUNK_HANDLE_SIZE, editor.CHUNK_HANDLE_SIZE)), handle_color, true)

func _draw_cursor_selection(camera: Camera2D) -> void:
	if editor == null:
		return
	if not editor.has_method("_get_cursor_rect_pixels"):
		return
	if not editor.cursor_rect_active:
		return
	var rect: Rect2 = editor._get_cursor_rect_pixels()
	if rect.size == Vector2.ZERO:
		return
	draw_rect(rect, Color(0, 0, 0, 0.25), true)
	draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
