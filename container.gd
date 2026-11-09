extends Container
 
## Extra space (in pixels) between the text and the edge of the ColorRect.
@export var buffer: Vector2 = Vector2(8, 4)
 
@export var _color_rect: ColorRect
@export var _label: Label
 
 
func _ready() -> void:
	assert(_color_rect != null, "Container needs a ColorRect child.")
	assert(_label != null, "Container needs a Label child.")
 
	set_display_string(_label.text)
 
func set_children_visible(visible: bool) -> void:
	_label.visible = visible
	_color_rect.visible = visible
 
func set_display_string(new_text: String) -> void:
	if _label == null or _color_rect == null:
		return
 
	_label.text = new_text
	_label.reset_size()  # shrink the label to fit the new text
 
	var text_size: Vector2 = _label.get_minimum_size()
	var total_size: Vector2 = text_size + buffer * 2.0
 
	_color_rect.position = Vector2.ZERO
	_color_rect.size = total_size
 
	_label.position = buffer
 
	# Let parent containers know how much room this container needs.
	custom_minimum_size = total_size
	size = total_size
