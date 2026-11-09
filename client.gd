extends Node
class_name Client
## App root: owns the ConnectionGui and GameMaster as children, and speaks
## to the server over a raw, persistent StreamPeerTCP — the server is a
## plain TCP socket server (not a real WebSocket server), so there's no
## HTTP handshake; messages are newline-delimited JSON strings in both
## directions. Polled once per frame in _process (no Mutex/threads
## needed — everything happens on the main thread). The StreamPeerTCP
## handed off by ConnectionGui.connected is reused directly as the live
## connection rather than being closed and reopened.

## Emitted when the connection drops for any reason, after GameMaster is
## hidden and ConnectionGui is shown again. Anything that wants to react
## further (logging, analytics, a retry prompt) can connect to this
## instead of Client handling it all internally.
signal disconnected

const NEWLINE_BYTE := 10  # "\n"

@export var connection_gui: ConnectionGui
@export var game_master: GameMaster

var _tcp: StreamPeerTCP
var _tcp_was_connected: bool = false
var _recv_buffer: PackedByteArray = PackedByteArray()


func _ready() -> void:
	assert(game_master)
	if game_master:
		game_master.visible = false
	if connection_gui:
		connection_gui.visible = true
		connection_gui.connected.connect(_on_connection_gui_connected)


func _on_connection_gui_connected(_ip: String, _port: int, tcp: StreamPeerTCP) -> void:
	# ConnectionGui already opened and confirmed this socket; reuse it
	# directly as the live connection instead of closing it and dialing a
	# separate WebSocket connection (the server doesn't speak WebSocket —
	# it's a plain TCP socket expecting newline-delimited JSON).
	_tcp = tcp
	_tcp_was_connected = false
	_recv_buffer.clear()
	set_process(true)


func _process(_delta: float) -> void:
	if _tcp == null:
		set_process(false)
		return

	_tcp.poll()
	var status: StreamPeerTCP.Status = _tcp.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			if not _tcp_was_connected:
				_tcp_was_connected = true
				print_verbose("Connected to server")
				_on_tcp_connected()

			_read_available_lines()

		StreamPeerTCP.STATUS_CONNECTING:
			pass  # keep polling until connected

		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			set_process(false)
			_tcp = null
			_on_tcp_disconnect()


func _read_available_lines() -> void:
	var available: int = _tcp.get_available_bytes()
	if available <= 0:
		return

	var chunk: PackedByteArray = _tcp.get_partial_data(available)[1]
	_recv_buffer.append_array(chunk)

	var newline_index: int = _recv_buffer.find(NEWLINE_BYTE)
	while newline_index != -1:
		var line_bytes: PackedByteArray = _recv_buffer.slice(0, newline_index)
		_recv_buffer = _recv_buffer.slice(newline_index + 1)

		var line: String = line_bytes.get_string_from_utf8()
		if not line.is_empty():
			_on_message(line)

		newline_index = _recv_buffer.find(NEWLINE_BYTE)


func _on_tcp_connected() -> void:
	if game_master:
		game_master.set_websocket(self)
		connection_gui.visible = false
		game_master.visible = true

	_send_message({"action": "request_place"})


## Duck-typed send_msg so GameMaster can treat this Client exactly like the
## MockWebSocket it defaults to (see GameMaster.set_websocket).
func send_msg(msg: String) -> void:
	if _tcp == null or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		push_warning("Tried to send a message with no open connection: %s" % msg)
		return
	print_verbose("Sending message to server: %s" % [msg])
	_tcp.put_data((msg + "\n").to_utf8_buffer())


func _send_message(msg: Dictionary) -> void:
	send_msg(JSON.stringify(msg))


func _on_tcp_disconnect() -> void:
	print_verbose("Disconnected from server")

	if game_master:
		game_master.visible = false
		game_master.reset()
	if connection_gui:
		connection_gui.visible = true
		connection_gui.reset()

	disconnected.emit()


# --- Incoming message handling -----------------------------------------------

func _on_message(text: String) -> void:
	var msg = JSON.parse_string(text)
	if msg == null or not (msg is Dictionary):
		push_warning("Received malformed message: %s" % text)
		return

	print_verbose("Received message: %s" % [msg])

	match msg.get("type"):
		"action":
			_handle_action(msg.get("msg", {}))
		"actionable":
			_handle_actionable(msg)
		"info":
			_handle_info(msg.get("msg", {}))
		_:
			push_warning("Received message with an unknown type %s" % [msg.get("type")])


func _handle_action(action_msg: Dictionary) -> void:
	match action_msg.get("type"):
		"set_player_location":
			game_master.set_front_player(action_msg["location"])
		"player_connected":
			game_master.player_connected(action_msg["location"])
		"player_disconnected":
			game_master.player_disconnected(action_msg["location"])
		"change_score":
			_change_score(action_msg)
		"add_card":
			_add_card(action_msg)
		"remove_card":
			_remove_card(action_msg)
		_:
			push_warning("Received action message with unknown type %s" % [action_msg.get("type")])


func _handle_actionable(msg: Dictionary) -> void:
	game_master.reset_actionables()

	var actionables: Dictionary = msg.get("msg", {}).get("actionables", {})
	var action_prefix := "action_"
	var cur_action_num := 1
	var cur_action = actionables.get("%s%d" % [action_prefix, cur_action_num])

	while cur_action != null:
		print_verbose("Adding potential actionable: %s" % [cur_action])
		game_master.add_actionable(cur_action["action"], cur_action["count"])

		cur_action_num += 1
		cur_action = actionables.get("%s%d" % [action_prefix, cur_action_num])


func _handle_info(info_msg: Dictionary) -> void:
	match info_msg.get("type"):
		"set_visibility":
			var visible: bool = info_msg.get("visible") == "true"
			match info_msg.get("subject"):
				"deck":
					game_master.deck_visible(visible)
				"discard":
					game_master.discard_visible(visible)
				_:
					push_warning("Received set_visibility message with unknown subject %s" % [info_msg.get("subject")])
		"extra_hand":
			var extra_hand_name: String = info_msg.get("subject")
			game_master.add_extra_hand(extra_hand_name)
		_:
			push_warning("Received info message with unknown type %s" % [info_msg.get("type")])


func _change_score(msg: Dictionary) -> void:
	var subject = msg["subject"]
	var effect = msg["effect"]
	var value = msg["value"]

	match effect:
		"set":
			game_master.set_score(subject, value)
		"add":
			game_master.add_to_score(subject, value)


func _add_card(msg: Dictionary) -> void:
	var card_data: Dictionary = msg["card"]
	var suit = card_data.get("suit", "")
	if suit == null:
		suit = ""
	var value = card_data.get("value", "")
	if value == null:
		value = ""
	var new_card := game_master.new_card(suit, value)

	var subject = msg["subject"]
	var subject_spec = msg.get("subject_specifier")

	match subject:
		"deck":
			game_master.add_to_deck(new_card)
		"discard":
			game_master.add_to_discard(new_card)
		"hand":
			game_master.add_to_hand(subject_spec, new_card)
		"play_area":
			game_master.add_to_play_area(subject_spec, new_card)
		"won_cards":
			game_master.add_to_won_cards(subject_spec, new_card)
		_:
			if !game_master.add_to_extra_hand(subject, new_card):
				push_warning("Received add_card message with unknown subject %s" % [subject])


func _remove_card(msg: Dictionary) -> void:
	var index = msg["index"]
	var subject = msg["subject"]
	var subject_spec = msg.get("subject_specifier")

	match subject:
		"deck":
			game_master.remove_from_deck(index)
		"discard":
			game_master.remove_from_discard(index)
		"hand":
			game_master.remove_from_hand(subject_spec, index)
		"play_area":
			game_master.remove_from_play_area(subject_spec, index)
		"won_cards":
			game_master.remove_from_won_cards(subject_spec, index)
		_:
			if !game_master.remove_from_extra_hand(subject, index):
				push_warning("Received remove_card message with unknown subject %s" % [subject])
