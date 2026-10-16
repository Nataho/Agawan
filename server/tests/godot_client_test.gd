extends SceneTree
## Headless integration test: real NetworkClient.gd -> Python server.
## Run: godot --headless --path . --script res://server/tests/godot_client_test.gd
## Expects Python server on ws://127.0.0.1:8080 (server/.venv/bin/python -m server.src.main)

var client: NetworkClient
var step: int = 0
var got_pong: bool = false
var got_chat_echo: bool = false
var got_welcome: bool = false
var frames: int = 0
const MAX_FRAMES := 600  # ~10s at 60fps


func _init() -> void:
	print("[GODOT-TEST] starting, creating NetworkClient...")
	client = NetworkClient.new()
	root.add_child(client)
	client.connected_to_server.connect(_on_connected)
	client.connection_failed.connect(_on_failed)
	client.disconnected_from_server.connect(_on_disconnected)
	client.payload_received.connect(_on_payload)
	print("[GODOT-TEST] connecting to 127.0.0.1:8080...")
	client.connect_to_server("127.0.0.1", 8080, 5.0)


func _process(_delta: float) -> bool:
	frames += 1
	if frames >= MAX_FRAMES:
		_report_and_quit(1, "TIMEOUT after %d frames" % MAX_FRAMES)
		return true
	return false


func _on_connected() -> void:
	print("[GODOT-TEST] CONNECTED step=%d" % step)
	step = 1
	# join first (Python server assigns client_id)
	var err = client.send_signal_to_server("join", {"name": "GodotHeadless", "team": "red", "role": "scavenger"})
	print("[GODOT-TEST] sent join err=%d" % err)


func _on_payload(signal_name: String, raw_data: Dictionary) -> void:
	print("[GODOT-TEST] payload '%s' %s" % [signal_name, str(raw_data)])
	match signal_name:
		"welcome":
			got_welcome = true
			step = 2
			client.send_signal_to_server("ping", {"timestamp": Time.get_ticks_msec(), "message": "Hello from Godot Headless!"})
			print("[GODOT-TEST] sent ping")
		"pong":
			got_pong = true
			step = 3
			# verify it's the PYTHON server, not Godot's in-scene server
			var reply: String = str(raw_data.get("reply", ""))
			print("[GODOT-TEST] pong reply='%s'" % reply)
			if reply != "Pong from Python Server!":
				_report_and_quit(1, "WRONG PONG SOURCE: '%s'" % reply)
				return
			client.send_signal_to_server("chat_message", {"sender": "GodotHeadless", "message": "headless hello", "time": Time.get_time_string_from_system()})
			print("[GODOT-TEST] sent chat_message")
		"chat_message":
			# broadcast echo of our own chat
			if str(raw_data.get("message", "")) == "headless hello":
				got_chat_echo = true
				step = 4
				client.send_signal_to_server("exit_base", {})
				print("[GODOT-TEST] sent exit_base")
		"freshness":
			step = 5
			_report_and_quit(0, "ALL CHECKS PASSED")
		"state":
			pass  # 20Hz tick, ignore
		_:
			print("[GODOT-TEST] (ignoring '%s')" % signal_name)


func _on_failed(reason: String) -> void:
	_report_and_quit(1, "CONNECTION FAILED: %s" % reason)


func _on_disconnected(clean: bool, code: int, reason: String) -> void:
	print("[GODOT-TEST] disconnected clean=%s code=%d reason='%s'" % [clean, code, reason])


func _report_and_quit(exit_code: int, msg: String) -> void:
	print("[GODOT-TEST] step=%d welcome=%s pong=%s chat=%s -> %s" % [step, str(got_welcome), str(got_pong), str(got_chat_echo), msg])
	if exit_code == 0:
		print("GODOT_CLIENT_PASS")
	else:
		print("GODOT_CLIENT_FAIL")
	quit(exit_code)
