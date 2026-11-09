extends Sprite2D
class_name Card
## Represents a Card in a deck.

signal card_clicked(card: Card)
signal card_selected(card: Card)
signal card_deselected(card: Card)

@export var selected_rect: ColorRect

var suit: String
var value: String

var selected: bool = false:
	get:
		return selected

var _selectable: bool = false

@onready var _click_area: Area2D = $ClickArea
var click_priority: int = 0
	

func _ready() -> void:
	if _click_area:
		_click_area.input_event.connect(_on_click_area_input_event)
		_setup_click_shape()
	else:
		push_warning("Card '%s' has no ClickArea child; clicks will not be detected" % to_s_pretty())


## Builds/updates a RectangleShape2D on the ClickArea's CollisionShape2D,
## sized to match this Sprite2D's texture (accounting for centered origin
## and scale), so click bounds always track the visible card art.
func _setup_click_shape() -> void:
	if texture == null:
		texture = CardsImages.card_image(self)
	
	if texture == null:
		push_warning("Card '%s' has no texture; skipping click shape setup" % to_s_pretty())
		return

	var collision_shape: CollisionShape2D = _click_area.get_node_or_null("CollisionShape2D")
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		_click_area.add_child(collision_shape)

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = texture.get_size()
	collision_shape.shape = rect_shape


func setup(p_suit: String, p_value: String) -> void:
	suit = p_suit
	value = p_value
	texture = CardsImages.card_image(self)


func hidden() -> bool:
	return suit.is_empty() and value.is_empty()


func make_selectable(p_selectable: bool) -> void:
	_selectable = p_selectable

func set_click_priority(priority: int) -> void:
	click_priority = priority

## Standard Godot click detection: connected to the ClickArea's (Area2D)
## input_event signal. Fires only for events inside the Area2D's
## CollisionShape2D, so no manual bounds-checking is needed.
func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_toggle_selected()
		print_verbose("Card %s clicked (selected=%s)" % [to_s_pretty(), selected])
		card_clicked.emit(self)


func to_s_pretty() -> String:
	return "%s of %s" % [value.capitalize(), suit.capitalize()]
	
# Allows external classes to toggle this card's selected status without
#  triggering signals
func public_toggle_selected() -> void:
	selected = not selected
	selected_rect.visible = selected

func _toggle_selected() -> void:
	if not _selectable:
		return

	selected = not selected
	selected_rect.visible = selected
	if selected:
		card_selected.emit(self)
	else:
		card_deselected.emit(self)
