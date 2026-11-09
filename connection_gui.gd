extends Node
class_name ConnectionGui
## Emitted once a TCP connection to the given ip:port succeeds. The
## StreamPeerTCP is left open and handed off here — whatever opens this
## scene should connect to this instead of passing in a connect_callback
## closure, and take ownership of the socket from that point on.
signal connected(ip: String, port: int, tcp: StreamPeerTCP)

@export var ip_box: LineEdit
@export var port_box: LineEdit
@export var connect_button: Button
@export var error_label: Label
@export var info_label: Label

var _connecting: bool = false
var _tcp: StreamPeerTCP
var _pending_ip: String = ""
var _pending_port: int = 0


func _ready() -> void:
	get_window().title = "Connect to Server"

	if ip_box and ip_box.text.is_empty():
		ip_box.text = "127.0.0.1"
	if port_box:
		if port_box.text.is_empty():
			port_box.text = "25252"
		port_box.text_changed.connect(_on_port_text_changed)

	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)

	_clear_error()
	set_process(false)


## Equivalent of the Ruby handle_first_frame: resets transient state when
## this screen becomes active again (e.g. after a failed prior attempt).
func reset() -> void:
	_clear_error()
	_indicate_connecting(false)
	set_process(false)


func _on_port_text_changed(new_text: String) -> void:
	# Equivalent of TextBox's allowed_chars: /[0-9]/ — strip non-digits.
	var filtered := ""
	for c in new_text:
		if c >= "0" and c <= "9":
			filtered += c

	if filtered != new_text:
		var caret := port_box.caret_column
		port_box.text = filtered
		port_box.caret_column = min(caret, filtered.length())


func _on_connect_pressed() -> void:
	_attempt_connection()


func _attempt_connection() -> void:
	if _connecting:
		return

	_indicate_connecting(true)
	_clear_error()

	var ip: String = ip_box.text
	var port_text: String = port_box.text

	if not port_text.is_valid_int():
		_show_error("Port must be a number")
		_indicate_connecting(false)
		return

	_pending_ip = ip
	_pending_port = port_text.to_int()

	_tcp = StreamPeerTCP.new()
	var err: Error = _tcp.connect_to_host(_pending_ip, _pending_port)
	if err != OK:
		_show_error("Failed to connect to server at %s:%d" % [_pending_ip, _pending_port])
		_indicate_connecting(false)
		_tcp = null
		return

	# Poll the connection attempt each frame instead of blocking a thread.
	set_process(true)

func _indicate_connecting(_connecting: bool) -> void:
	self._connecting = _connecting
	connect_button.disabled = _connecting
	ip_box.editable = !_connecting
	port_box.editable = !_connecting
	if _connecting:
		_show_info("Connecting to server")
	else:
		_clear_info()

func _process(_delta: float) -> void:
	if _tcp == null:
		set_process(false)
		return

	_tcp.poll()
	match _tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			set_process(false)
			_indicate_connecting(false)
			_show_info("Connected to server")
			var ip := _pending_ip
			var port := _pending_port
			var tcp := _tcp
			_tcp = null
			connected.emit(ip, port, tcp)
		StreamPeerTCP.STATUS_ERROR:
			set_process(false)
			_indicate_connecting(false)
			_show_error("Failed to connect to server at %s:%d" % [_pending_ip, _pending_port])
			_tcp = null
		StreamPeerTCP.STATUS_CONNECTING:
			pass  # keep polling
		StreamPeerTCP.STATUS_NONE:
			pass


func _show_error(message: String) -> void:
	push_error(message)
	if error_label:
		error_label.text = message
		error_label.visible = true


func _clear_error() -> void:
	if error_label:
		error_label.text = ""
		error_label.visible = false
		
		
func _show_info(message: String) -> void:
	print_verbose(message)
	if info_label:
		info_label.text = message
		info_label.visible = true


func _clear_info() -> void:
	if info_label:
		info_label.text = ""
		info_label.visible = false
