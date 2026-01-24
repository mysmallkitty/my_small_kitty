class_name UserProfileDetail
extends SlidePopup

var user_id = -1

@onready var username_label = $Username
@onready var rank_label = $Rank
@onready var 	play_label = $PlayCount
@onready var 	clear_label = $ClearedCount
@onready var 	death_label = $DeathCount
@onready var 	created_label = $JoinDate
@onready var 	level_label = $LevelCreated
@onready var 	close_button = $CloseButton
@onready var 	country_label = $CountryFlag

func _ready() -> void:
	super()
	add_to_group("user_profile_panels")
	_connect_buttons()
	refresh_from_api()

func open_with_me(me: Dictionary) -> void:
	_apply_user(me)
	show_popup()

func refresh_from_api() -> void:
	var me := _get_me_data()
	_apply_user(me)


func _connect_buttons() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	hide_popup()

func _apply_user(user: Dictionary) -> void:
	if not user.is_empty():
		username_label.text = str(user.get("username", "guest")) + " (" + str(int(user.get("level", 0))) + ")"
		var rank = user.get("rank", null)
		rank_label.text = "#%s" % str(int(rank)) if rank != null else "#--"
		play_label.text = str(int(user.get("total_attempts", 0)))
		clear_label.text = str(int(user.get("total_clears", 0)))
		death_label.text = str(int(user.get("total_deaths", 0)))
		created_label.text = _format_date(str(user.get("created_at", "")))
		country_label.texture = get_flag_png(user.get("country","unknown"))

func _format_date(value: String) -> String:
	if value == "":
		return "--"
	var parts := value.split("T")
	if parts.size() > 0 and parts[0] != "":
		return parts[0]
	return value

func get_flag_png(code: String) -> Texture:
	var path := "res://graphics/ui/flags".path_join(code + ".png")
	if FileAccess.file_exists(path):
		var t = load(path)
		return t
	return load("res://graphics/ui/flags/unkown.png")

func _get_me_data() -> Dictionary:
	var me = ApiClient.me
	if typeof(me) == TYPE_DICTIONARY:
		if me.has("data") and typeof(me.get("data", null)) == TYPE_DICTIONARY:
			return me.get("data", {})
		return me
	return {}
