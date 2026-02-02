class_name UserProfileDetail
extends SlidePopup

var user_id = -1

@onready var username_label = $Username
@onready var rank_label = $Rank
@onready var play_label = $PlayCount
@onready var clear_label = $ClearedCount
@onready var death_label = $DeathCount
@onready var created_label = $JoinDate
@onready var close_button = $CloseButton
@onready var country_label = $CountryFlag
@onready var total_pp_label = $TotalPP
@onready var total_pp_icon = $PPIcon
@onready var profile_pic: TextureRect = $ProfilePic
@onready var edit_button = $EditButton

func _ready() -> void:
	super()
	add_to_group("user_profile_panels")
	_connect_buttons()
	refresh_from_api()

func open_with_me(me: Dictionary) -> void:
	_apply_user(me)
	show_popup()

func open_with_user(user: Dictionary) -> void:
	_apply_user(user)
	show_popup()

func refresh_from_api() -> void:
	var me := _get_me_data()
	_apply_user(me)

func _connect_buttons() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if edit_button != null and not edit_button.pressed.is_connected(_on_edit_pressed):
		edit_button.pressed.connect(_on_edit_pressed)
	if profile_pic != null and not profile_pic.gui_input.is_connected(_on_profile_pic_input):
		profile_pic.gui_input.connect(_on_profile_pic_input)

func _on_close_pressed() -> void:
	hide_popup()

func _on_edit_pressed() -> void:
	var panels := get_tree().get_nodes_in_group("profile_edit_panels")
	if panels.is_empty():
		return
	var editor := panels[0]
	if editor != null and editor.has_method("open_for_me"):
		editor.open_for_me()

func _on_profile_pic_input(event: InputEvent) -> void:
	if not _is_me(_get_me_data()):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_edit_pressed()

func _apply_user(user: Dictionary) -> void:
	if not user.is_empty():
		user_id = int(user.get("id", user.get("user_id", -1)))
		username_label.text = str(user.get("username", "guest")) + " (" + str(int(user.get("level", 0))) + ")"
		var rank = user.get("rank", null)
		rank_label.text = "#%s" % str(int(rank)) if rank != null else "#--"
		play_label.text = str(int(user.get("total_attempts", 0)))
		clear_label.text = str(int(user.get("total_clears", 0)))
		death_label.text = str(int(user.get("total_deaths", 0)))
		created_label.text = _format_date(str(user.get("created_at", "")))
		country_label.texture = get_flag_png(user.get("country","unknown"))
		var total_pp = int(user.get("total_pp", 0))
		total_pp_label.text = str(total_pp) + "pp"
		total_pp_icon.texture = load(
			"res://graphics/ui/8px/ranks/" +
			str(Game.get_rank_from_total_pp(total_pp)) +
			".png"
			)
		var sprite_code := str(user.get("profile_sprite", ""))
		if profile_pic != null:
			var tex := Game.get_profile_texture(sprite_code)
			if tex != null:
				profile_pic.texture = tex
			else:
				profile_pic.texture = load("res://graphics/ui/16px/user_guest.png")
	if edit_button != null:
		edit_button.visible = _is_me(user)

func _format_date(value: String) -> String:
	if value == "":
		return "--"
	var parts := value.split("T")
	if parts.size() > 0 and parts[0] != "":
		return parts[0]
	return value

func get_flag_png(code) -> Texture:
	var code_str := str(code).strip_edges().to_lower()
	if code_str == "" or code_str == "unknown":
		return load("res://graphics/ui/flags/unknown.png")
	var path := "res://graphics/ui/flags".path_join(code_str + ".png")
	if ResourceLoader.exists(path):
		return load(path)
	return load("res://graphics/ui/flags/unknown.png")

func _get_me_data() -> Dictionary:
	var me = ApiClient.me
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
			return me.get("data", {})
		return me
	return {}

func _is_me(user: Dictionary) -> bool:
	var me := _get_me_data()
	if me.is_empty():
		return false
	return int(me.get("id", -1)) == int(user.get("id", user.get("user_id", -2)))
