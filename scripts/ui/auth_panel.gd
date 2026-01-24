class_name AuthPanel
extends SlidePopup

var login_panel: Control
var register_panel: Control

var login_user: LineEdit
var login_pass: LineEdit
var login_confirm: BaseButton
var login_register: BaseButton
var login_close: BaseButton

var register_user: LineEdit
var register_pass: LineEdit
var register_pass_confirm: LineEdit
var register_confirm: BaseButton
var register_back: BaseButton

func _ready() -> void:
	super()
	_bind_ui()
	_connect_buttons()
	_show_login_panel()

func open_login() -> void:
	_show_login_panel()
	show_popup()

func open_register() -> void:
	_show_register_panel()
	show_popup()

func _connect_buttons() -> void:
	if login_confirm != null and not login_confirm.pressed.is_connected(_on_login_submit):
		login_confirm.pressed.connect(_on_login_submit)
	if login_register != null and not login_register.pressed.is_connected(_on_login_register_pressed):
		login_register.pressed.connect(_on_login_register_pressed)
	if login_close != null and not login_close.pressed.is_connected(_on_login_close):
		login_close.pressed.connect(_on_login_close)
	if register_confirm != null and not register_confirm.pressed.is_connected(_on_register_submit):
		register_confirm.pressed.connect(_on_register_submit)
	if register_back != null and not register_back.pressed.is_connected(_on_register_back):
		register_back.pressed.connect(_on_register_back)

func _bind_ui() -> void:
	login_panel = get_node_or_null("Login") as Control
	register_panel = get_node_or_null("RegisterPanel") as Control

	login_user = get_node_or_null("Login/Username") as LineEdit
	login_pass = get_node_or_null("Login/Password") as LineEdit
	login_confirm = _find_button("Login/Confirm", "Confirm")
	login_register = _find_button("Login/Register", "Register")
	login_close = _find_button("Login/CloseButton", "CloseButton")

	register_user = get_node_or_null("RegisterPanel/Username") as LineEdit
	register_pass = get_node_or_null("RegisterPanel/Password") as LineEdit
	register_pass_confirm = get_node_or_null("RegisterPanel/PasswordConfirm") as LineEdit
	register_confirm = _find_button("RegisterPanel/Confirm", "Confirm")
	register_back = _find_button("RegisterPanel/BackButton", "BackButton")

func _on_login_register_pressed() -> void:
	_show_register_panel()

func _on_login_close() -> void:
	hide_popup()

func _on_register_back() -> void:
	_show_login_panel()

func _show_login_panel() -> void:
	if login_panel != null:
		login_panel.visible = true
	if register_panel != null:
		register_panel.visible = false

func _show_register_panel() -> void:
	if login_panel != null:
		login_panel.visible = false
	if register_panel != null:
		register_panel.visible = true

func _on_login_submit() -> void:
	var username := login_user.text.strip_edges() if login_user != null else ""
	var password := login_pass.text.strip_edges() if login_pass != null else ""
	var validation := AuthService.validate_credentials(username, password)
	if validation != "":
		Alert.push(validation, true)
		return
	var result: Dictionary = await AuthService.login(username, password)
	if not result.get("ok", false):
		Alert.push(ApiClient._error_message(result), true)
		return
	get_tree().call_group("profile_panels", "refresh_from_api")
	get_tree().call_group("user_profile_panels", "refresh_from_api")
	hide_popup()
	

func _on_register_submit() -> void:
	var username := register_user.text.strip_edges() if register_user != null else ""
	var password := register_pass.text.strip_edges() if register_pass != null else ""
	var confirm := register_pass_confirm.text.strip_edges() if register_pass_confirm != null else ""
	var validation := AuthService.validate_credentials(username, password)
	if validation != "":
		Alert.push(validation, true)
		return
	if confirm != password:
		Alert.push("password mismatch", true)
		return
	var result: Dictionary = await AuthService.register(username, password)
	if not result.get("ok", false):
		Alert.push(ApiClient._error_message(result), true)
		return
	_show_login_panel()
	Alert.push("registerd!")
	if login_user != null:
		login_user.text = username
	if login_pass != null:
		login_pass.text = ""

func _find_button(path: String, _name: String) -> BaseButton:
	var node := get_node_or_null(path)
	if node is BaseButton:
		return node
	var fallback := find_child(_name, true, false)
	if fallback is BaseButton:
		return fallback
	return null
