extends Node

const client_version: String = "0.0.1"

var base_url := "https://smallkitty.p-e.kr"
var debug_log := false
var access_token: String = ""
var refresh_token: String = ""
var me: Dictionary
var is_server_down = false

func _ready() -> void:
	base_url = _resolve_base_url()
	print(base_url)
	_check_server_health()

func set_base_url(url: String) -> void:
	var trimmed := url.strip_edges()
	if trimmed == "":
		return
	base_url = trimmed

func set_access_token(token: String) -> void:
	access_token = token
func set_refresh_token(token: String) -> void:
	refresh_token = token
func clear_access_token() -> void:
	access_token = ""

func _build_headers(extra_headers: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Accept: application/json")
	var has_content_type := false
	for h in extra_headers:
		if h.to_lower().begins_with("content-type:"):
			has_content_type = true
			break
	if not has_content_type:
		headers.append("Content-Type: application/json")
	headers.append("User-Agent: SmallKitty-Godot/" + client_version)
	headers.append("X-Client-Version: " + client_version)

	if access_token != "":
		headers.append("Authorization: Bearer " + access_token)

	for h in extra_headers:
		headers.append(h)

	return headers

func _check_server_health() -> void:
	var result: Dictionary = await ApiClient.GET("/health")
	if not result.get("ok", false):
		Alert.push("can't connect to server", true)
		return
	var data = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		var status := str(data.get("status", ""))
		Alert.push("server status: %s" % status, status != "ok")
		is_server_down = true

func _make_url(path: String) -> String:
	if path.begins_with("http://") or path.begins_with("https://"):
		return path
	if not path.begins_with("/"):
		path = "/" + path
	return base_url.trim_suffix("/") + path

func _resolve_base_url() -> String:
	var env_url := OS.get_environment("SMALLKITTY_API_URL")
	if env_url != "":
		print("env:" + env_url)
		return env_url
	var setting = ProjectSettings.get_setting("network/api_base_url", "")
	if typeof(setting) == TYPE_STRING:
		var trimmed := str(setting).strip_edges()
		if trimmed != "":
			return trimmed
	return base_url



func request_json(method: int, path: String, body: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var url := _make_url(path)
	var req := HTTPRequest.new()
	add_child(req)

	req.timeout = 3.0

	var headers := _build_headers(extra_headers)

	var payload := ""
	if body != null:
		payload = JSON.stringify(body)

	var err := req.request(url, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"code": -1,
			"data": null,
			"raw_text": "",
			"headers": PackedStringArray(),
			"error": "request() failed: %s" % error_string(err),
		}

	var sig_args: Array = await req.request_completed
	var result: int = sig_args[0]
	var response_code: int = sig_args[1]
	var resp_headers: PackedStringArray = sig_args[2]
	var resp_body: PackedByteArray = sig_args[3]

	req.queue_free()

	var raw_text := resp_body.get_string_from_utf8()
	if debug_log:
		print("HTTP ", method, " ", url, " -> ", response_code, " ", raw_text.left(200))

	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"code": response_code,
			"data": null,
			"raw_text": raw_text,
			"headers": resp_headers,
			"error": "cant connect to server",
		}

	var ok := response_code >= 200 and response_code < 300

	var parsed: Variant = null
	if raw_text.strip_edges() != "":
		parsed = JSON.parse_string(raw_text)

	return {
		"ok": ok,
		"code": response_code,
		"data": parsed,
		"raw_text": raw_text,
		"headers": resp_headers,
		"error": "" if ok else "http error: %d" % response_code,
	}

func request_raw(method: int, path: String, body: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var url := _make_url(path)
	var req := HTTPRequest.new()
	add_child(req)

	req.timeout = 15.0
	var headers := _build_headers(extra_headers)
	var payload := ""
	if body != null:
		payload = JSON.stringify(body)

	var err := req.request(url, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"code": -1,
			"bytes": PackedByteArray(),
			"raw_text": "",
			"headers": PackedStringArray(),
			"error": "request() failed: %s" % error_string(err),
		}

	var sig_args: Array = await req.request_completed
	var result: int = sig_args[0]
	var response_code: int = sig_args[1]
	var resp_headers: PackedStringArray = sig_args[2]
	var resp_body: PackedByteArray = sig_args[3]

	req.queue_free()

	var raw_text := resp_body.get_string_from_utf8()
	if debug_log:
		print("HTTP ", method, " ", url, " -> ", response_code, " ", raw_text.left(200))

	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"code": response_code,
			"bytes": resp_body,
			"raw_text": raw_text,
			"headers": resp_headers,
			"error": "network result failed: %s" % str(result),
		}

	var ok := response_code >= 200 and response_code < 300
	return {
		"ok": ok,
		"code": response_code,
		"bytes": resp_body,
		"raw_text": raw_text,
		"headers": resp_headers,
		"error": "" if ok else "http error: %d" % response_code,
	}

func _encode_form(data: Dictionary) -> String:
	var parts: Array[String] = []
	for key in data.keys():
		var value := str(data[key])
		parts.append("%s=%s" % [str(key).uri_encode(), value.uri_encode()])
	return "&".join(parts)

func GET(path: String, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, path, null, extra_headers)

func POST(path: String, body: Variant, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(HTTPClient.METHOD_POST, path, body, extra_headers)

func PUT(path: String, body: Variant, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(HTTPClient.METHOD_PUT, path, body, extra_headers)

func DELETE(path: String, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_json(HTTPClient.METHOD_DELETE, path, null, extra_headers)

func POST_FORM(path: String, body: Dictionary, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var headers := PackedStringArray()
	headers.append("Content-Type: application/x-www-form-urlencoded")
	for h in extra_headers:
		headers.append(h)
	var url := _make_url(path)
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 15.0
	var payload := _encode_form(body)
	var all_headers := _build_headers(headers)
	var err := req.request(url, all_headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"code": -1,
			"data": null,
			"raw_text": "",
			"headers": PackedStringArray(),
			"error": "request() failed: %s" % error_string(err),
		}
	var sig_args: Array = await req.request_completed
	var result: int = sig_args[0]
	var response_code: int = sig_args[1]
	var resp_headers: PackedStringArray = sig_args[2]
	var resp_body: PackedByteArray = sig_args[3]
	req.queue_free()
	var raw_text := resp_body.get_string_from_utf8()
	if debug_log:
		print("HTTP FORM ", url, " -> ", response_code, " ", raw_text.left(200))
	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"code": response_code,
			"data": null,
			"raw_text": raw_text,
			"headers": resp_headers,
			"error": "network result failed: %s" % str(result),
		}
	var ok := response_code >= 200 and response_code < 300
	var parsed: Variant = null
	if raw_text.strip_edges() != "":
		parsed = JSON.parse_string(raw_text)
	return {
		"ok": ok,
		"code": response_code,
		"data": parsed,
		"raw_text": raw_text,
		"headers": resp_headers,
		"error": "" if ok else "http error: %d" % response_code,
	}

func GET_RAW(path: String, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await request_raw(HTTPClient.METHOD_GET, path, null, extra_headers)

func _error_message(result: Dictionary) -> String:
	var data = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		var detail := str(data.get("detail", ""))
		if detail != "":
			return detail
	var raw := str(result.get("raw_text", ""))
	if raw != "":
		return raw
	var error := str(result.get("error", ""))
	return error if error != "" else "unkwon error"
