extends Node
class_name NetworkServer

## Emitted when the server starts listening successfully.
signal server_started(port: int, bind_address: String)
## Emitted when the server stops listening.
signal server_stopped
## Emitted when a new client connects.
signal client_connected(client_id: int)
## Emitted when a client disconnects.
signal client_disconnected(client_id: int)
## Emitted when a valid signal payload is received from a client.
signal payload_received(client_id: int, signal_name: String, raw_data: Dictionary)

@export var default_port: int = 8080
@export var default_bind_address: String = "*"
@export var max_pending_connections: int = 16

var _tcp_server: TCPServer = TCPServer.new()
# Dictionary of client_id (int) -> WebSocketPeer
var _clients: Dictionary = {}
var _next_client_id: int = 1
var _is_running: bool = false


func _process(_delta: float) -> void:
	if not _is_running:
		return

	_poll_incoming_connections()
	_poll_clients()


## Starts the WebSocket server listening on the specified port and bind address.
## bind_address="*" listens on all interfaces (or "127.0.0.1" for local only).
func start_server(port: int = 0, bind_address: String = "") -> Error:
	stop_server()

	var target_port: int = port if port > 0 else default_port
	var target_address: String = bind_address if not bind_address.is_empty() else default_bind_address

	var err = _tcp_server.listen(target_port, target_address)
	if err != OK:
		push_error("SocketServer: Failed to start listening on %s:%d. Error code: %d" % [target_address, target_port, err])
		return err

	_is_running = true
	server_started.emit(target_port, target_address)
	return OK


## Stops the server and disconnects all connected clients.
func stop_server() -> void:
	if not _is_running:
		return

	# Disconnect existing clients
	for client_id in _clients.keys():
		var peer: WebSocketPeer = _clients[client_id]
		if peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			peer.close(1001, "Server shutting down")

	_clients.clear()
	_tcp_server.stop()
	_is_running = false
	server_stopped.emit()


## Sends a signal payload back to the client that sent the message.
func send_to_sender(sender_id: int, signal_name: String, raw_data: Dictionary = {}) -> Error:
	return send_to_client(sender_id, signal_name, raw_data)


## Sends a signal payload to a specific client by ID.
## Payload format: {"signal_name": "[the signal name]", "raw_data": {[the raw data]}}
func send_to_client(client_id: int, signal_name: String, raw_data: Dictionary = {}) -> Error:
	if not _clients.has(client_id):
		push_warning("SocketServer: Client %d not found." % client_id)
		return ERR_DOES_NOT_EXIST

	var peer: WebSocketPeer = _clients[client_id]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("SocketServer: Client %d is not connected (state: %d)." % [client_id, peer.get_ready_state()])
		return ERR_UNCONFIGURED

	return _send_payload_to_peer(peer, signal_name, raw_data)


## Broadcasts a signal payload to all connected clients.
## Optionally pass excluded_id to avoid echoing to a specific client (e.g. sender).
func broadcast(signal_name: String, raw_data: Dictionary = {}, excluded_id: int = -1) -> void:
	var payload_json: String = _make_payload_string(signal_name, raw_data)
	for client_id in _clients.keys():
		if client_id == excluded_id:
			continue
		var peer: WebSocketPeer = _clients[client_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(payload_json)


## Returns all currently active client IDs.
func get_connected_client_ids() -> Array:
	var ids: Array = []
	for client_id in _clients.keys():
		var peer: WebSocketPeer = _clients[client_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ids.append(client_id)
	return ids


## Returns whether the server is currently listening.
func is_running() -> bool:
	return _is_running


# Poll incoming TCP connections and perform WebSocket handshake
func _poll_incoming_connections() -> void:
	while _tcp_server.is_connection_available():
		var tcp_conn: StreamPeerTCP = _tcp_server.take_connection()
		if tcp_conn:
			var peer = WebSocketPeer.new()
			var err = peer.accept_stream(tcp_conn)
			if err == OK:
				var client_id = _next_client_id
				_next_client_id += 1
				_clients[client_id] = peer
			else:
				push_warning("SocketServer: Failed to accept WebSocket connection. Error: %d" % err)


# Poll existing clients for state changes and incoming packets
func _poll_clients() -> void:
	var disconnected_ids: Array[int] = []

	for client_id in _clients.keys():
		var peer: WebSocketPeer = _clients[client_id]
		peer.poll()
		var state = peer.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			# If this client just reached STATE_OPEN from handshake
			if not peer.get_meta("handshake_completed", false):
				peer.set_meta("handshake_completed", true)
				client_connected.emit(client_id)

			while peer.get_available_packet_count() > 0:
				var packet = peer.get_packet()
				_handle_packet(client_id, packet)

		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected_ids.append(client_id)

	# Clean up disconnected peers
	for client_id in disconnected_ids:
		_clients.erase(client_id)
		client_disconnected.emit(client_id)


func _handle_packet(client_id: int, packet: PackedByteArray) -> void:
	var message_text = packet.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(message_text)
	if err != OK:
		push_warning("SocketServer: Received malformed JSON from client %d." % client_id)
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SocketServer: Received JSON payload from client %d is not a Dictionary." % client_id)
		return

	if data.has("signal_name"):
		var sig_name: String = str(data.get("signal_name", ""))
		var raw_data: Dictionary = {}
		if data.has("raw_data") and typeof(data["raw_data"]) == TYPE_DICTIONARY:
			raw_data = data["raw_data"]

		payload_received.emit(client_id, sig_name, raw_data)


func _make_payload_string(signal_name: String, raw_data: Dictionary) -> String:
	var payload: Dictionary = {
		"signal_name": signal_name,
		"raw_data": raw_data
	}
	return JSON.stringify(payload)


func _send_payload_to_peer(peer: WebSocketPeer, signal_name: String, raw_data: Dictionary) -> Error:
	var json_str = _make_payload_string(signal_name, raw_data)
	return peer.send_text(json_str)
