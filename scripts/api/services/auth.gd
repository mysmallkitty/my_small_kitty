extends Node
class_name AuthService

const USERNAME_MIN := 3
const USERNAME_MAX := 50
const PASSWORD_MIN := 8

static func register(username: String, password: String, email: String = "") -> Dictionary:
	if email.strip_edges() == "":
		email = make_email_for(username)
	var body := {
		"email": email,
		"username": username,
		"password": password,
	}
	return await ApiClient.POST("/api/v1/user/signup", body)

static func login(username: String, password: String) -> Dictionary:
	var body := {
		"username": username,
		"password": password,
		"grant_type": "password",
	}
	var res := await ApiClient.POST_FORM("/api/v1/user/login", body)

	if res.ok and typeof(res.data) == TYPE_DICTIONARY and res.data.has("access_token"):
		ApiClient.set_access_token(str(res.data["access_token"]))
		ApiClient.set_refresh_token(str(res.data.get("refresh_token", "")))
		ApiClient.save_tokens()
		var me_res := await ApiClient.GET("/api/v1/user/me")
		if me_res.get("ok", false) and typeof(me_res.get("data", null)) == TYPE_DICTIONARY:
			ApiClient.me = me_res["data"]
			ApiClient.auth_state_changed.emit(true, "login")
		else:
			ApiClient.me = {}
			ApiClient.auth_state_changed.emit(false, "login_failed")
		
	return res

static func me() -> Dictionary:
	var res = await ApiClient.GET("/api/v1/user/me")
	if res.get("ok", false) and typeof(res.get("data", null)) == TYPE_DICTIONARY:
		ApiClient.me = res["data"]
	else:
		ApiClient.me = {}
	return res

static func logout() -> void:
	ApiClient.clear_access_token()
	ApiClient.clear_tokens()
	ApiClient.me = {}
	ApiClient.auth_state_changed.emit(false, "logout")

static func validate_credentials(username: String, password: String) -> String:
	if username == "":
		return "username required"
	if password == "":
		return "password required"
	if username.length() < USERNAME_MIN or username.length() > USERNAME_MAX:
		return "username length %d-%d" % [USERNAME_MIN, USERNAME_MAX]
	if password.length() < PASSWORD_MIN:
		return "password min %d length" % PASSWORD_MIN
	return ""

static func make_email_for(username: String) -> String:
	var safe := ""
	for ch in username:
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if is_alnum or ch == "_" or ch == "-" or ch == ".":
			safe += ch
		else:
			safe += "_"
	if safe == "":
		safe = "user"
	return "%s@smallkitty.local" % safe

static func check_health() -> Dictionary:
	return await ApiClient.GET("/health")
