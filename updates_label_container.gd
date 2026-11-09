extends Container

## Emitted when a string has finished its display cycle (the timer hid the children).
signal update_complete

## Extra space (in pixels) between the text and the edge of the ColorRect.
@export var buffer: Vector2 = Vector2(8, 4)

@export var _color_rect: ColorRect
@export var _label: Label
@export var _timer: Timer

var _string_queue: Array[String] = []


func _ready() -> void:
	assert(_color_rect != null, "Container needs a ColorRect child.")
	assert(_label != null, "Container needs a Label child.")
	assert(_timer != null, "Container needs a Timer child.")

	_timer.timeout.connect(_on_timer_timeout)
	update_complete.connect(_on_update_complete)

	_set_display_string(_label.text)

func set_children_visible(visible: bool) -> void:
	self.visible = visible
	_label.visible = visible
	_color_rect.visible = visible

## Shows the string right away if nothing is currently displayed,
## otherwise adds it to the queue.
func queue_display_string(new_text: String) -> void:
	if self.visible:
		_string_queue.append(new_text)
	else:
		_set_display_string(new_text)

func _set_display_string(new_text: String) -> void:
	if _label == null or _color_rect == null:
		return

	_label.text = new_text
	_label.reset_size()  # shrink the label to fit the new text

	var text_size: Vector2 = _label.get_minimum_size()
	var total_size: Vector2 = text_size + buffer * 2.0

	# The container's top-left (local Vector2.ZERO) is the center of the text box,
	# so offset the children by half the total size in the negative direction.
	var top_left: Vector2 = -total_size / 2.0

	_color_rect.position = top_left
	_color_rect.size = total_size

	_label.position = top_left + buffer

	set_children_visible(true)
	_timer.start()  # (re)start the countdown to hiding the children

func _on_timer_timeout() -> void:
	set_children_visible(false)
	update_complete.emit()

func _on_update_complete() -> void:
	if _string_queue.is_empty():
		return
	_set_display_string(_string_queue.pop_front())
