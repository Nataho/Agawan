extends Node
class_name NetworkClient

## Emitted when successfully connected to the server.
signal connected_to_server
## Emitted when disconnected or connection is lost.
signal disconnected_from_server(clean: bool, code: int, reason: String)
## Emitted when connection attempt fails or times out.
signal connection_failed(reason: String)
## Emitted when a signal payload is received from the server.
signal payload_received(signal_name: String, raw_data: Dictionary)

@export var default_host: String = "127.0.0.1"
@export var default_port: int = 8080
@export var default_timeout: float = 5.0

var _peer: WebSocketPeer = WebSocketPeer.new()
var _connection_timer: Timer
var _is_connecting: bool = false
var _last_state: WebSocketPeer.State = WebSocketPeer.STATE_CLOSED


func _ready() -> void:
	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	_connection_timer.timeout.connect(_on_connection_timeout)
	add_child(_connection_timer)


func _process(_delta: float) -> void:
	_peer.poll()
	var state = _peer.get_ready_state()

	# Handle connection lifecycle transitions
	if _is_connecting:
		if state == WebSocketPeer.STATE_OPEN:
			_is_connecting = false
			_connection_timer.stop()
			_last_state = state
			connected_to_server.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			_is_connecting = false
			_connection_timer.stop()
			_last_state = state
			connection_failed.emit("Failed to establish connection to server.")

	elif _last_state == WebSocketPeer.STATE_OPEN and state != WebSocketPeer.STATE_OPEN:
		var code = _peer.get_close_code()
		var reason = _peer.get_close_reason()
		var clean = (state == WebSocketPeer.STATE_CLOSED and code != -1)
		_last_state = state
		disconnected_from_server.emit(clean, code, reason)

	# Read incoming packets when connected
	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			var packet = _peer.get_packet()
			_handle_packet(packet)


## Connects to the server with an optional timeout in seconds. [br]
## Accepts full ws/wss URL (e.g. "ws://127.0.0.1:8080") or IP/hostname.
func connect_to_server(url_or_host: String = "", port: int = 0, timeout_sec: float = -1.0) -> Error:
	disconnect_from_server()

	var target_url: String = url_or_host
	if target_url.is_empty():
		target_url = default_host

	var target_port: int = port if port > 0 else default_port
	var target_timeout: float = timeout_sec if timeout_sec > 0.0 else default_timeout

	# Construct URL if only host/ip was provided
	if not target_url.begins_with("ws://") and not target_url.begins_with("wss://"):
		target_url = "ws://" + target_url + ":" + str(target_port)

	var err = _peer.connect_to_url(target_url)
	if err != OK:
		connection_failed.emit("Failed to initiate connection. Error code: %d" % err)
		return err

	_is_connecting = true
	_last_state = _peer.get_ready_state()
	_connection_timer.start(target_timeout)
	return OK


## Disconnects from the server gracefully.
func disconnect_from_server(code: int = 1000, reason: String = "Normal Closure") -> void:
	_connection_timer.stop()
	_is_connecting = false
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close(code, reason)
	_last_state = WebSocketPeer.STATE_CLOSED


## Sends a signal payload to the server:
## {"signal_name": "[the signal name]", "raw_data": {[the raw data]}}
func send_signal_to_server(signal_name: String, raw_data: Dictionary = {}) -> Error:
	if not is_connected_to_server():
		push_warning("SocketClient: Cannot send signal '%s'. Not connected to server." % signal_name)
		return ERR_UNCONFIGURED

	var payload: Dictionary = {
		"signal_name": signal_name,
		"raw_data": raw_data
	}

	var json_string = JSON.stringify(payload)
	return _peer.send_text(json_string)


## Checks if the socket is currently connected.
func is_connected_to_server() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _on_connection_timeout() -> void:
	if _is_connecting:
		_is_connecting = false
		_peer.close(1002, "Connection timed out")
		_last_state = WebSocketPeer.STATE_CLOSED
		connection_failed.emit("Connection timed out after waiting.")


func _handle_packet(packet: PackedByteArray) -> void:
	var message_text = packet.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(message_text)
	if err != OK:
		push_warning("SocketClient: Received malformed JSON from server.")
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SocketClient: Received JSON payload is not a Dictionary.")
		return

	if data.has("signal_name"):
		var sig_name: String = str(data.get("signal_name", ""))
		var raw_data: Dictionary = {}
		if data.has("raw_data") and typeof(data["raw_data"]) == TYPE_DICTIONARY:
			raw_data = data["raw_data"]

		payload_received.emit(sig_name, raw_data)
