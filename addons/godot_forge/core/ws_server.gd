@tool
extends RefCounted
## Loopback WebSocket server that MCP bridges connect to. Speaks a tiny JSON-RPC dialect:
##   request  {"id": 1, "method": "scene.get_tree", "params": {...}}
##   response {"id": 1, "result": ...} | {"id": 1, "error": {"message": ..., "hint": ...}}
##   event    {"event": "log", "data": {...}}
## The first request of every connection must be "hello" with the session token.

const U = preload("res://addons/godot_forge/core/util.gd")
const BUFFER_SIZE := 1 << 25 # 32 MiB, screenshots and big trees fit comfortably

signal client_connected(peer_id: int, info: Dictionary)
signal client_disconnected(peer_id: int)

var router
var port := 0
var token := ""
var _tcp := TCPServer.new()
var _peers := {}
var _next_id := 1
## Time of the last request (plugin uses it to un-throttle the editor while AI works).
var activity_msec := 0


func _init(p_router) -> void:
	router = p_router
	token = Crypto.new().generate_random_bytes(24).hex_encode()


func start(base_port: int, attempts: int = 30) -> bool:
	for p in range(base_port, base_port + attempts):
		if _tcp.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	return false


func stop() -> void:
	for id in _peers:
		_peers[id].ws.close(1001, "Editor closing")
	_peers.clear()
	_tcp.stop()


func client_count() -> int:
	var n := 0
	for id in _peers:
		if _peers[id].authed:
			n += 1
	return n


func clients() -> Array:
	var out := []
	for id in _peers:
		if _peers[id].authed:
			out.append(_peers[id].info)
	return out


func poll() -> void:
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER_SIZE
		ws.outbound_buffer_size = BUFFER_SIZE
		ws.max_queued_packets = 4096
		if ws.accept_stream(conn) != OK:
			continue
		_peers[_next_id] = {"ws": ws, "authed": false, "info": {}, "since": Time.get_ticks_msec()}
		_next_id += 1

	for id in _peers.keys():
		var peer: Dictionary = _peers[id]
		var ws: WebSocketPeer = peer.ws
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				_on_message(id, pkt.get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSED:
			var was_authed: bool = peer.authed
			_peers.erase(id)
			if was_authed:
				client_disconnected.emit(id)
		elif state == WebSocketPeer.STATE_CONNECTING and not peer.authed and Time.get_ticks_msec() - peer.since > 10000:
			ws.close()


func send(peer_id: int, data: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var ws: WebSocketPeer = _peers[peer_id].ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(data))


func broadcast(event: String, data) -> void:
	var msg := JSON.stringify({"event": event, "data": data})
	for id in _peers:
		if _peers[id].authed and _peers[id].ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_peers[id].ws.send_text(msg)


func _on_message(peer_id: int, text: String) -> void:
	var msg = JSON.parse_string(text)
	if not (msg is Dictionary):
		send(peer_id, {"id": null, "error": {"message": "Invalid JSON message."}})
		return
	var id = msg.get("id")
	var method := str(msg.get("method", ""))
	var params = msg.get("params", {})
	if not (params is Dictionary):
		params = {}
	var peer: Dictionary = _peers[peer_id]

	if method == "hello":
		if str(params.get("token", "")) != token:
			send(peer_id, {"id": id, "error": {"message": "Invalid session token.", "hint": "Re-read .godot/forge/session.json; the editor regenerates the token on every start."}})
			peer.ws.close(4001, "bad token")
			return
		peer.authed = true
		peer.info = {"client": params.get("client", "unknown"), "version": params.get("version", "?")}
		send(peer_id, {"id": id, "result": router.hello_info()})
		client_connected.emit(peer_id, peer.info)
		return

	if not peer.authed:
		send(peer_id, {"id": id, "error": {"message": "Not authenticated. Send 'hello' with the session token first."}})
		return
	activity_msec = Time.get_ticks_msec()

	_dispatch(peer_id, id, method, params)


func _dispatch(peer_id: int, id, method: String, params: Dictionary) -> void:
	var result = await router.dispatch(method, params)
	activity_msec = Time.get_ticks_msec()
	if U.is_err(result):
		var e: Dictionary = result.duplicate()
		e.erase("__forge_error")
		send(peer_id, {"id": id, "error": e})
	else:
		send(peer_id, {"id": id, "result": U.encode(result) if not (result is Dictionary and result.get("__raw", false)) else result})
