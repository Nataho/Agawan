extends Control

var server: NetworkServer
var client: NetworkClient

# Client UI nodes
@onready var client_status_label: Label = %ClientStatusLabel
@onready var direct_connect_btn: Button = %DirectConnectBtn
@onready var client_ip_edit: LineEdit = %ClientIPEdit
@onready var client_port_edit: LineEdit = %ClientPortEdit
@onready var client_start_btn: Button = %ClientStartBtn
@onready var client_disconnect_btn: Button = %ClientDisconnectBtn
@onready var client_chat_input: LineEdit = %ClientChatInput
@onready var client_chat_send_btn: Button = %ClientChatSendBtn
@onready var send_ping_btn: Button = %SendPingBtn
@onready var client_log: RichTextLabel = %ClientLog

# Server UI nodes
@onready var server_status_label: Label = %ServerStatusLabel
@onready var server_port_edit: LineEdit = %ServerPortEdit
@onready var server_start_btn: Button = %ServerStartBtn
@onready var server_stop_btn: Button = %ServerStopBtn
@onready var server_chat_input: LineEdit = %ServerChatInput
@onready var server_chat_send_btn: Button = %ServerChatSendBtn
@onready var server_log: RichTextLabel = %ServerLog


func _ready() -> void:
	# Instantiate network nodes
	server = NetworkServer.new()
	client = NetworkClient.new()
	add_child(server)
	add_child(client)

	# Connect Server signals
	server.server_started.connect(_on_server_started)
	server.server_stopped.connect(_on_server_stopped)
	server.client_connected.connect(_on_server_client_connected)
	server.client_disconnected.connect(_on_server_client_disconnected)
	server.payload_received.connect(_on_server_payload_received)

	# Connect Client signals
	client.connected_to_server.connect(_on_client_connected)
	client.disconnected_from_server.connect(_on_client_disconnected)
	client.connection_failed.connect(_on_client_connection_failed)
	client.payload_received.connect(_on_client_payload_received)

	# Hook up Client UI events
	direct_connect_btn.pressed.connect(_on_direct_connect_pressed)
	client_start_btn.pressed.connect(_on_client_start_pressed)
	client_disconnect_btn.pressed.connect(_on_client_disconnect_pressed)
	send_ping_btn.pressed.connect(_on_send_ping_pressed)
	client_chat_send_btn.pressed.connect(_on_client_send_chat)
	client_chat_input.text_submitted.connect(func(_text): _on_client_send_chat())

	# Hook up Server UI events
	server_start_btn.pressed.connect(_on_server_start_pressed)
	server_stop_btn.pressed.connect(_on_server_stop_pressed)
	server_chat_send_btn.pressed.connect(_on_server_broadcast_chat)
	server_chat_input.text_submitted.connect(func(_text): _on_server_broadcast_chat())

	_update_ui_state()


# --- UI ACTIONS: CLIENT ---

func _on_direct_connect_pressed() -> void:
	_append_client_log("Direct connecting to 127.0.0.1:8080...")
	client_status_label.text = "Status: Connecting..."
	client.connect_to_server("127.0.0.1", 8080, 5.0)


func _on_client_start_pressed() -> void:
	var ip = client_ip_edit.text.strip_edges()
	var port = int(client_port_edit.text.strip_edges())
	if ip.is_empty():
		ip = "127.0.0.1"
	if port <= 0:
		port = 8080

	_append_client_log("Connecting to %s:%d..." % [ip, port])
	client_status_label.text = "Status: Connecting..."
	client.connect_to_server(ip, port, 5.0)


func _on_client_disconnect_pressed() -> void:
	client.disconnect_from_server()
	client_status_label.text = "Status: Disconnected"
	_append_client_log("Disconnected by user.")
	_update_ui_state()


func _on_send_ping_pressed() -> void:
	var payload = {
		"timestamp": Time.get_ticks_msec(),
		"message": "Hello from Godot Client!"
	}
	var err = client.send_signal_to_server("ping", payload)
	if err == OK:
		_append_client_log("Sent signal 'ping'")
	else:
		_append_client_log("Failed to send ping (code: %d)" % err)


func _on_client_send_chat() -> void:
	var msg = client_chat_input.text.strip_edges()
	if msg.is_empty():
		return

	var payload = {
		"sender": "Client",
		"message": msg,
		"time": Time.get_time_string_from_system()
	}
	var err = client.send_signal_to_server("chat_message", payload)
	if err == OK:
		_append_client_log("[You]: " + msg)
		client_chat_input.clear()
	else:
		_append_client_log("Failed to send chat (code: %d)" % err)


# --- UI ACTIONS: SERVER ---

func _on_server_start_pressed() -> void:
	var port = int(server_port_edit.text.strip_edges())
	if port <= 0:
		port = 8080
	server.start_server(port, "*")


func _on_server_stop_pressed() -> void:
	server.stop_server()


func _on_server_broadcast_chat() -> void:
	var msg = server_chat_input.text.strip_edges()
	if msg.is_empty():
		return

	var payload = {
		"sender": "Server",
		"message": msg,
		"time": Time.get_time_string_from_system()
	}
	server.broadcast("chat_message", payload)
	_append_server_log("[Server Broadcast]: " + msg)
	server_chat_input.clear()


# --- SERVER EVENT HANDLERS ---

func _on_server_started(port: int, bind_address: String) -> void:
	server_status_label.text = "Status: Running on port %d" % port
	_append_server_log("Server started on %s:%d" % [bind_address, port])
	_update_ui_state()


func _on_server_stopped() -> void:
	server_status_label.text = "Status: Stopped"
	_append_server_log("Server stopped.")
	_update_ui_state()


func _on_server_client_connected(client_id: int) -> void:
	_append_server_log("Client %d connected." % client_id)


func _on_server_client_disconnected(client_id: int) -> void:
	_append_server_log("Client %d disconnected." % client_id)


func _on_server_payload_received(client_id: int, signal_name: String, raw_data: Dictionary) -> void:
	if signal_name == "ping":
		_append_server_log("Received 'ping' from Client %d. Responding with 'pong'." % client_id)
		server.send_to_sender(client_id, "pong", {
			"reply": "Pong from Godot Server!",
			"client_id": client_id
		})

	elif signal_name == "chat_message":
		var user = raw_data.get("sender", "Client %d" % client_id)
		var text = raw_data.get("message", "")
		_append_server_log("[%s]: %s" % [user, text])
		
		# Relay / broadcast message to all clients so everyone in the room gets it
		server.broadcast("chat_message", {
			"sender": user,
			"message": text,
			"time": raw_data.get("time", Time.get_time_string_from_system())
		})
	else:
		_append_server_log("Received signal '%s' from Client %d: %s" % [signal_name, client_id, str(raw_data)])


# --- CLIENT EVENT HANDLERS ---

func _on_client_connected() -> void:
	client_status_label.text = "Status: Connected"
	_append_client_log("Connected to server successfully!")
	_update_ui_state()


func _on_client_disconnected(clean: bool, code: int, reason: String) -> void:
	client_status_label.text = "Status: Disconnected"
	_append_client_log("Disconnected from server. (Clean: %s, Code: %d, Reason: '%s')" % [clean, code, reason])
	_update_ui_state()


func _on_client_connection_failed(reason: String) -> void:
	client_status_label.text = "Status: Connection Failed"
	_append_client_log("Connection failed: %s" % reason)
	_update_ui_state()


func _on_client_payload_received(signal_name: String, raw_data: Dictionary) -> void:
	if signal_name == "chat_message":
		var sender_name = raw_data.get("sender", "Unknown")
		var msg = raw_data.get("message", "")
		_append_client_log("[%s]: %s" % [sender_name, msg])
	elif signal_name == "pong":
		_append_client_log("[Server Pong]: " + str(raw_data.get("reply", "Pong!")))
	else:
		_append_client_log("Received signal '%s' with data: %s" % [signal_name, str(raw_data)])


# --- UI HELPERS ---

func _update_ui_state() -> void:
	var client_is_connected = client.is_connected_to_server()
	var server_is_running = server.is_running()

	# If client is already connected to a server, disable the Server Start button
	server_start_btn.disabled = server_is_running or client_is_connected
	server_stop_btn.disabled = not server_is_running
	server_chat_send_btn.disabled = not server_is_running
	server_chat_input.editable = server_is_running

	# Client button states
	direct_connect_btn.disabled = client_is_connected
	client_start_btn.disabled = client_is_connected
	client_disconnect_btn.disabled = not client_is_connected
	send_ping_btn.disabled = not client_is_connected
	client_chat_send_btn.disabled = not client_is_connected
	client_chat_input.editable = client_is_connected


func _append_client_log(text: String) -> void:
	client_log.append_text("[color=lightblue]" + text + "[/color]\n")
	print("[Client] ", text)


func _append_server_log(text: String) -> void:
	server_log.append_text("[color=lightgreen]" + text + "[/color]\n")
	print("[Server] ", text)
