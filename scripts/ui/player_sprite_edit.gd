class_name PlayerSpriteEdit
extends SlidePopup

@onready var close_button: BaseButton = $Panel2/CloseButton
@onready var upload_button: BaseButton = $Panel2/UploadButton
@onready var palette_root: Control = $Panel2/PaletteRoot
@onready var canvas: PixelCanvas = $Panel2/Canvas
@onready var palette_info: Label = $Panel2/PaletteInfo

var _palette_items: Array = []
var _active_color_index := 0
var _use_64 := false

func _ready() -> void:
	super()
	add_to_group("player_sprite_edit_panels")
	_connect_buttons()
	_build_palette()
	_load_from_me()

func open_for_me() -> void:
	_load_from_me()
	show_popup()

func _connect_buttons() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if upload_button != null and not upload_button.pressed.is_connected(_on_upload_pressed):
		upload_button.pressed.connect(_on_upload_pressed)

func _on_close_pressed() -> void:
	hide_popup()

func _is_supporter() -> bool:
	var me = ApiClient.me
	var data: Dictionary = {}
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
			data = me.get("data", {})
		else:
			data = me
	return str(data.get("role", "")) == "sup"

func _build_palette() -> void:
	if palette_root == null:
		return
	for child in palette_root.get_children():
		child.queue_free()
	_palette_items.clear()
	var colors := Game.get_player_palette()
	var cell := 12
	var padding := 2
	var cols := 8
	for i in range(colors.size()):
		var swatch := ColorRect.new()
		swatch.color = colors[i]
		swatch.custom_minimum_size = Vector2(cell, cell)
		swatch.position = Vector2i((i % cols) * (cell + padding), int(i / cols) * (cell + padding))
		swatch.mouse_filter = Control.MOUSE_FILTER_STOP
		swatch.gui_input.connect(_on_palette_input.bind(i))
		palette_root.add_child(swatch)
		_palette_items.append(swatch)
	if canvas != null:
		canvas.set_palette(colors)
	_set_active_color(0)

func _apply_allowed_palette() -> void:
	var allowed := PackedInt32Array()
	var max_index := 63 if _use_64 else 31
	for i in range(max_index + 1):
		allowed.append(i)
	if canvas != null:
		canvas.set_allowed_indices(allowed)
	for i in range(_palette_items.size()):
		var item = _palette_items[i]
		if item == null:
			continue
		if i <= max_index:
			item.modulate = Color(1, 1, 1, 1)
		else:
			item.modulate = Color(0.3, 0.3, 0.3, 1)
	if palette_info != null:
		palette_info.text = "Palette: %s" % ("64" if _use_64 else "32")

func _on_palette_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var max_index := 63 if _use_64 else 31
			if index > max_index:
				return
			_set_active_color(index)

func _set_active_color(index: int) -> void:
	_active_color_index = clampi(index, 0, _palette_items.size() - 1)
	if canvas != null:
		canvas.set_active_index(_active_color_index)
	for i in range(_palette_items.size()):
		var item = _palette_items[i]
		if item == null:
			continue
		if i == _active_color_index:
			item.modulate = Color(1, 1, 1, 1)
		elif (_use_64 and i <= 63) or (not _use_64 and i <= 31):
			item.modulate = Color(0.7, 0.7, 0.7, 1)

func _load_from_me() -> void:
	if canvas == null:
		return
	var me = ApiClient.me
	var data: Dictionary = {}
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
			data = me.get("data", {})
		else:
			data = me
	var code := str(data.get("player_sprite", ""))
	var decoded := Game.decode_player_sprite(code)
	var supporter := _is_supporter()
	if decoded.is_empty():
		_use_64 = supporter
		canvas.set_pixels(Game.player_indices_from_kitty())
	else:
		_use_64 = supporter and str(decoded.get("prefix", "0")) == "1"
		canvas.set_pixels(Game.player_indices_from_code(code))
	_apply_allowed_palette()

func _on_upload_pressed() -> void:
	if canvas == null:
		return
	var supporter := _is_supporter()
	if not supporter:
		_use_64 = false
	var code := Game.encode_player_sprite(canvas.get_pixels())
	print(code.length())
	if code == "":
		Alert.push("invalid player sprite", true)
		return
	print(code.length())
	var result: Dictionary = await ApiClient.PATCH("/api/v1/user/me", {"player_sprite": code})
	if not result.get("ok", false):
		Alert.push(ApiClient._error_message(result), true)
		return
	if typeof(result.get("data", null)) == TYPE_DICTIONARY:
		ApiClient.me = result.get("data", {})
	get_tree().call_group("profile_panels", "refresh_from_api")
	get_tree().call_group("user_profile_panels", "refresh_from_api")
	Alert.push("player sprite updated", false)
	hide_popup()
