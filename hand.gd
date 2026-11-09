extends Node2D
class_name Hand
## Represents a hand of cards. Computes fan-out layout (position/scale) for
## its Card children within a bounding rect; visual drawing (border, name
## label, hover text) is left to Godot's own node/theme system.
##
## Tracks clicks on its own cards: each Card added here has its card_clicked
## signal connected internally, and re-broadcast as hand_card_clicked, so
## callers (e.g. GameMaster) can react to "something in this hand was
## clicked" without polling mouse coordinates against every hand.

signal hand_card_clicked(hand: Hand, card: Card)
signal hand_card_selected(hand: Hand, card: Card)
signal hand_card_deselected(hand: Hand, card: Card)

var cards: Array[Card] = []:
	get:
		return cards

var hand_name: String = ""
@export var name_label: Label

var _selectable: bool = false
var _card_selected_this_frame: Card = null

# Bounding box this hand lays itself out within.
var _left_x: float = 0.0
var _top_y: float = 0.0
var _right_x: float = 0.0
var _bottom_y: float = 0.0

# Layout values, recomputed by _calculate_layout().
var _start_x: float = 0.0
var _card_spacing: float = 0.0
var _card_scaling: float = 0.0
var _card_width: float = 0.0
var _card_height: float = 0.0

func _ready() -> void:
	name_label.text = hand_name
	
func _process(delta: float) -> void:
	_card_selected_this_frame = null

## Sets the bounding box this hand lays its cards out within, and
## recalculates card positions/scales immediately.
## Expected order matches the Ruby original: [left_x, top_y, right_x, bottom_y]
func set_location(bounds: HandBounds) -> void:
	_left_x = bounds.position.x
	_top_y = bounds.position.y
	_right_x = bounds.position.x + bounds.size.x
	_bottom_y = bounds.position.y + bounds.size.y
	_calculate_layout(_left_x, _top_y, _right_x, _bottom_y)


func set_selectable(p_selectable: bool) -> void:
	_selectable = p_selectable
	for card in cards:
		card.make_selectable(_selectable)


func selected_cards() -> Array[Card]:
	return cards.filter(func(card): return card.selected)


func selected_card_indexes() -> Array[int]:
	var selected_indexes: Array[int] = []
	for i in cards.size():
		if cards[i].selected:
			selected_indexes.append(i)
	return selected_indexes


func select(index: int) -> Card:
	if index < 0 or index >= cards.size():
		return null
	return cards[index]


func add(card: Card) -> void:
	card.make_selectable(_selectable)
	cards.append(card)
	add_child(card)
	connect_card_signals(card)
	_calculate_layout_same_location()


func remove(index: int) -> Card:
	if index < 0 or index >= cards.size():
		push_warning("Hand '%s' remove() called with out-of-range index %d" % [hand_name, index])
		return null

	var removed: Card = cards[index]
	cards.remove_at(index)
	disconnect_card_signals(removed)
	if removed.get_parent() == self:
		remove_child(removed)
	_calculate_layout_same_location()
	return removed


func connect_card_signals(card: Card) -> void:
	if !card.card_clicked.is_connected(_on_card_clicked):
		card.card_clicked.connect(_on_card_clicked)
	if !card.card_selected.is_connected(_on_card_selected):
		card.card_selected.connect(_on_card_selected)
	if !card.card_deselected.is_connected(_on_card_deselected):
		card.card_deselected.connect(_on_card_deselected)
	
func disconnect_card_signals(card: Card) -> void:
	if card.card_clicked.is_connected(_on_card_clicked):
		card.card_clicked.disconnect(_on_card_clicked)
	if card.card_selected.is_connected(_on_card_selected):
		card.card_selected.disconnect(_on_card_selected)
	if card.card_deselected.is_connected(_on_card_deselected):
		card.card_deselected.disconnect(_on_card_deselected)
	
	
func _on_card_clicked(card: Card) -> void:
	if _card_selected_this_frame != null and _card_selected_this_frame.click_priority > card.click_priority:
		return
	hand_card_clicked.emit(self, card)
	
func _on_card_selected(card: Card) -> void:
	if _card_selected_this_frame != null:
		if _card_selected_this_frame.click_priority > card.click_priority:
			card.public_toggle_selected()
			return
		else:
			_card_selected_this_frame.public_toggle_selected()
			if _card_selected_this_frame.selected:
				hand_card_selected.emit(self, _card_selected_this_frame)
			else:
				hand_card_deselected.emit(self, _card_selected_this_frame)
	_card_selected_this_frame = card
	hand_card_selected.emit(self, card)
	
func _on_card_deselected(card: Card) -> void:
	if _card_selected_this_frame != null:
		if _card_selected_this_frame.click_priority > card.click_priority:
			card.public_toggle_selected()
			return
		else:
			_card_selected_this_frame.public_toggle_selected()
			if _card_selected_this_frame.selected:
				hand_card_selected.emit(self, _card_selected_this_frame)
			else:
				hand_card_deselected.emit(self, _card_selected_this_frame)
	_card_selected_this_frame = card
	hand_card_deselected.emit(self, card)


func _calculate_layout_same_location() -> void:
	_calculate_layout(_left_x, _top_y, _right_x, _bottom_y)


func _calculate_layout(left_x: float, top_y: float, right_x: float, bottom_y: float) -> void:
	if cards.is_empty():
		_start_x = 0.0
		_card_spacing = 0.0
		_card_scaling = 0.0
		return

	var sample_texture: Texture2D = cards[0].texture
	if sample_texture == null:
		push_warning("Hand '%s' can't calculate layout: first card has no texture" % hand_name)
		return

	var center_x: float = (left_x + right_x) / 2.0
	var hand_draw_height: float = bottom_y - top_y
	var hand_draw_width: float = right_x - left_x
	_card_scaling = hand_draw_height * 1.0 / sample_texture.get_size().y

	_card_width = sample_texture.get_size().x * _card_scaling
	_card_height = sample_texture.get_size().y * _card_scaling
	# If the width is less than 0, the hand gets drawn backwards
	var effective_hand_width: float = max(hand_draw_width - _card_width, 0.0)

	if _card_width * cards.size() < effective_hand_width:
		_card_spacing = _card_width
		_start_x = center_x - (_card_width * cards.size() / 2.0)
	elif cards.size() == 1:
		_card_spacing = 0.0
		_start_x = left_x
	else:
		_card_spacing = effective_hand_width * 1.0 / (cards.size() - 1)
		_start_x = left_x

	_update_card_locations()


func _update_card_locations() -> void:
	var next_x: float = _start_x
	var card_prio = 0.0
	for card in cards:
		card.set_click_priority(card_prio)
		card_prio += 1
		
		card.position = Vector2(next_x, _top_y)
		card.scale = Vector2(_card_scaling, _card_scaling)
		next_x += _card_spacing
