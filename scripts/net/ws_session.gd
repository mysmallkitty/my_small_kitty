class_name WsSession
extends Node

signal connected
signal disconnected
signal peer_joined(peer_id: String)
signal peer_left(peer_id: String)
signal peer_state(peer_id: String, position: Vector2)
signal peer_death(peer_id: String)
signal chat_message(peer_id: String, text: String)

const TPS := 20.0

var _peer: WebSocketPeer = WebSocketPeer.new()
var _map_id: String = ""
var _player_id: String = ""
var _url: String = ""
var _ready := false
var _pending_queue: Array[String] = []
var _known_peers := {}

func connect_map(map_id: String, player_id: String, _nickname: String = "") -> void:
	_map_id = str(map_id)
	_player_id = _normalize_peer_id(str(player_id))
	_url = _build_ws_url(_map_id)
	_ready = false
	_pending_queue.clear()
	_known_peers.clear()
	if _url == "":
		return
	_peer = WebSocketPeer.new()
	var err = _peer.connect_to_url(_url, TLSOptions.client())
	if err != OK:
		push_warning("ws connect failed: %s" % error_string(err))

func _process(_delta: float) -> void:
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		if _ready:
			_ready = false
			disconnected.emit()
		return
	if state == WebSocketPeer.STATE_CONNECTING:
		return
	if state == WebSocketPeer.STATE_OPEN:
		if not _ready:
			_ready = true
			connected.emit()
		for msg in _pending_queue:
			_send_raw(msg)
		_pending_queue.clear()
		_poll_packets()

func send_state(pos: Vector2) -> void:
	if not _ready:
		return
	_send_json({
		"type": "position",
		"pos": {"x": pos.x, "y": pos.y},
	})

func send_death() -> void:
	if not _ready:
		return
	_send_json({
		"type": "death",
	})

func send_chat(text: String) -> void:
	if not _ready:
		return
	if text.strip_edges() == "":
		return
	_send_json({
		"type": "chat",
		"text": text,
	})

func close() -> void:
	if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(1000, "bye")
	_ready = false
	_known_peers.clear()

func is_ready() -> bool:
	return _ready

func _poll_packets() -> void:
	while _peer.get_available_packet_count() > 0:
		var packet: PackedByteArray = _peer.get_packet()
		var text := packet.get_string_from_utf8()
		var obj = JSON.parse_string(text)
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		_handle_message(obj)

func _handle_message(msg: Dictionary) -> void:
	var t := str(msg.get("type", ""))
	match t:
		"ghost_position":
			var pid := _normalize_peer_id(str(msg.get("user_id", "")))
			if pid == _player_id:
				return
			var pos_dict = msg.get("pos", {})
			var pos := Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
			if not _known_peers.has(pid):
				_known_peers[pid] = true
				peer_joined.emit(pid)
			peer_state.emit(pid, pos)
		"death":
			var pid := _normalize_peer_id(str(msg.get("player_id", "")))
			if pid != _player_id and pid != "":
				if not _known_peers.has(pid):
					_known_peers[pid] = true
					peer_joined.emit(pid)
				peer_death.emit(pid)
		"chat":
			var pid := _normalize_peer_id(str(msg.get("user_id", "")))
			var text := str(msg.get("text", ""))
			if text.strip_edges() != "":
				chat_message.emit(pid, text)
		"death_ack":
			pass
		"session_started":
			pass
		"error":
			push_warning(str(msg.get("message", "")))
		_:
			pass

func _send_json(data: Dictionary) -> void:
	var text := JSON.stringify(data)
	_send_raw(text)

func _send_raw(text: String) -> void:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_pending_queue.append(text)
		return
	_peer.send_text(text)

func _build_ws_url(map_id: String) -> String:
	var mid = int(map_id)
	var base := ApiClient.base_url.trim_suffix("/")
	var proto := "wss://"
	var host := base
	if base.begins_with("https://"):
		host = base.substr(8)
	elif base.begins_with("http://"):
		proto = "ws://"
		host = base.substr(7)
	var token_q := ""
	if ApiClient.access_token != "":
		token_q = "?token=%s" % ApiClient.access_token
	return "%s%s/api/v1/%s/play%s" % [proto, host, mid, token_q]

func _auth_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	if ApiClient.access_token != "":
		headers.append("Authorization: Bearer %s" % ApiClient.access_token)
	return headers

func _normalize_peer_id(pid: String) -> String:
	var p := str(pid)
	if p.ends_with(".0"):
		return p.substr(0, p.length() - 2)
	return p
