extends Node
class_name GameMaster
## Coordinates hands, deck, discard, scoreboard and action buttons for a
## round of the game. Ported from a Gosu-based GameMaster: drawing is now
## left to the scene tree, click handling is signal-based (via Hand's
## hand_card_clicked), and card/hand positions come from Node2D markers
## placed in the editor instead of a computed Locator.

const LOCATION_ORDER: Array[String] = ["S", "W", "N", "E"]
const DEFAULT_NAMES: Dictionary = {
	"S": "South",
	"W": "West",
	"N": "North",
	"E": "East",
}
@onready var hand_base = preload("hand.tscn")
func new_hand(hand_name: String = "") -> Hand:
	print("Hand base resource path: %s" % hand_base.resource_path)
	var hand = hand_base.instantiate()
	add_child(hand)
	hand.hand_name = hand_name
	return hand
	
@onready var card_base = preload("card.tscn")
func new_card(suit: String = "", value: String = "") -> Card:
	var card = card_base.instantiate()
	card.setup(suit, value)
	return card

## Scene-placed markers for where each hand/area/pile should sit
@export var player_hand_locations: Array[HandBounds] = []   # Int -> HandBounds
@export var play_area_locations: Array[HandBounds] = []   # Int -> HandBounds
@export var won_cards_locations: Array[HandBounds] = []   # Int -> HandBounds
@export var deck_location: HandBounds
@export var discard_location: HandBounds

## Scene-placed UI
@export var player_name_labels: Array[Label] = []   # Int -> Label
@export var scoreboard_label: RichTextLabel
@export var button_nodepaths: Dictionary = {}   # String -> Button
var buttons: Dictionary = {}
@export var choice_hand_dropdown: OptionButton
@export var updates_label_container: Container

## Mocked by default; Client injects the real sender once connected via
## set_websocket(). Anything assigned here just needs a send_msg(String)
## method — Client itself satisfies that duck type.
var _websocket = MockWebSocket.new()


func set_websocket(websocket) -> void:
	_websocket = websocket

var _player_positions_clockwise_from_front: Array[String] = []
var _front_player: String = "S"

var _deck: Hand
var _deck_visible: bool = true
var _discard: Hand
var _discard_visible: bool = true

var _extra_hands: Dictionary = {}      # String -> Hand
var _choice_hand: Hand

var _player_hands: Dictionary = {}     # String -> Hand
var _play_areas: Dictionary = {}       # String -> Hand
var _won_cards: Dictionary = {}        # String -> Hand
var _play_areas_visible: bool = true
var _won_cards_visible: bool = true

var _connected_players: Array[String] = []
var _player_scores: Dictionary = {}

var _cur_actionables: Dictionary = {}  # String -> int (required selection count)

var _game_title_callback: Callable = Callable()
var _game_name: String = ""


class MockWebSocket:
	func send_msg(msg: String) -> void:
		print_verbose("MockWebSocket send_msg: %s" % msg)


static func num_to_direction(num: int) -> String:
	return LOCATION_ORDER[num % LOCATION_ORDER.size()]

func reset() -> void:
	_player_hands = {}
	_player_scores = {}
	_play_areas = {}
	_won_cards = {}
	_connected_players = []
	_play_areas_visible = true
	_deck_visible = true
	_discard_visible = true
	_extra_hands = {}
	
	if not choice_hand_dropdown.item_selected.is_connected(_on_dropdown_hand_choice_item_selected):
		choice_hand_dropdown.item_selected.connect(_on_dropdown_hand_choice_item_selected)
	
	_player_positions_clockwise_from_front = [
		num_to_direction(0), num_to_direction(1), num_to_direction(2), num_to_direction(3)
	]
	_front_player = num_to_direction(0)

	create_deck(0)
	_deck.set_location(deck_location)

	create_discard()
	_discard.set_location(discard_location)
	
	choice_hand_dropdown.add_item("Won Cards")

	for actionable in button_nodepaths:
		var button: Button = self.get_node(button_nodepaths[actionable])
		buttons[actionable.to_lower()] = button
		button.text = actionable.capitalize()
		button.pressed.connect(_on_button_pressed.bind(actionable))

	_update_scoreboard()

func _ready() -> void:
	reset()


# --- Deck -----------------------------------------------------------------

func create_deck(size: int) -> void:
	if _deck != null:
		_deck.queue_free()  # also removes it from the tree

	_deck = new_hand("Deck")
	_connect_hand_signals(_deck)
	for _i in size:
		_deck.add(new_card())


func add_to_deck(card: Card) -> void:
	_deck.add(card)


func remove_from_deck(index: int = 0) -> Card:
	return _deck.remove(index)


func deck_selectable(selectable: bool) -> void:
	_deck.set_selectable(selectable)


func deck_visible(visible: bool) -> void:
	_deck_visible = visible
	_deck.visible = visible


# --- Discard ----------------------------------------------------------------

func create_discard(cards: Hand = null) -> void:
	var discard_hand: Hand = cards
	if discard_hand == null:
		discard_hand = new_hand("Discard")

	if _discard != null and _discard.get_parent() == self:
		remove_child(_discard)
		_discard.queue_free()

	discard_hand.set_location(discard_location)
	if discard_hand.get_parent() == null:
		add_child(discard_hand)
	_discard = discard_hand
	_connect_hand_signals(_discard)


func add_to_discard(card: Card) -> void:
	_discard.add(card)


func remove_from_discard(index: int) -> Card:
	return _discard.remove(index)


func discard_selectable(selectable: bool) -> void:
	_discard.set_selectable(selectable)


func discard_visible(visible: bool) -> void:
	_discard_visible = visible
	_discard.visible = visible


# --- Player hands -----------------------------------------------------------

func _create_player_hand(hash_dir: String, hand: Hand = null) -> bool:
	if not _player_slot_exists(hash_dir):
		return false

	if not _player_hands.has(hash_dir):
		var player_hand: Hand = hand if hand != null else new_hand(DEFAULT_NAMES[hash_dir])
		if player_hand.get_parent() == null:
			add_child(player_hand)
		_connect_hand_signals(player_hand)
		_player_hands[hash_dir] = player_hand

	_reposition_hands()
	return true


func add_to_hand(hash_dir: String, card: Card) -> bool:
	if _player_slot_exists(hash_dir):
		_player_hands[hash_dir].add(card)
		return true
	return false


func remove_from_hand(hash_dir: String, index: int) -> Card:
	if _player_slot_exists(hash_dir):
		return _player_hands[hash_dir].remove(index)
	return null


# --- Play areas ---------------------------------------------------------------

func _create_play_area(hash_dir: String, hand: Hand = null) -> bool:
	if not _player_slot_exists(hash_dir):
		return false

	if not _play_areas.has(hash_dir):
		var play_area: Hand = hand if hand != null else new_hand("Play Area")
		if play_area.get_parent() == null:
			add_child(play_area)
		_connect_hand_signals(play_area)
		_play_areas[hash_dir] = play_area

	_reposition_hands()
	return true


func play_areas_visible(visible: bool) -> void:
	_play_areas_visible = visible
	for play_area in _play_areas.values():
		play_area.visible = visible


func add_to_play_area(hash_dir: String, card: Card) -> bool:
	if _player_slot_exists(hash_dir):
		_play_areas[hash_dir].add(card)
		return true
	return false


func remove_from_play_area(hash_dir: String, index: int) -> Card:
	if _player_slot_exists(hash_dir):
		return _play_areas[hash_dir].remove(index)
	return null


# --- Won cards ----------------------------------------------------------------

func _create_won_cards(hash_dir: String, hand: Hand = null) -> bool:
	if not _player_slot_exists(hash_dir):
		return false

	if not _won_cards.has(hash_dir):
		var won_hand: Hand = hand if hand != null else new_hand("Cards Won")
		if won_hand.get_parent() == null:
			add_child(won_hand)
		_connect_hand_signals(won_hand)
		_won_cards[hash_dir] = won_hand

	_reposition_hands()
	return true


func won_cards_visible(visible: bool) -> void:
	_won_cards_visible = visible
	for won_hand in _won_cards.values():
		won_hand.visible = visible


func add_to_won_cards(hash_dir: String, card: Card) -> bool:
	if _player_slot_exists(hash_dir):
		_won_cards[hash_dir].add(card)
		return true
	return false


func remove_from_won_cards(hash_dir: String, index: int) -> Card:
	if _player_slot_exists(hash_dir):
		return _won_cards[hash_dir].remove(index)
	return null
	
# --- Extra Hands ----------------------------------------------------------

func add_extra_hand(hand_name: String) -> void:
	var extra_hand = new_hand(hand_name)
	extra_hand.set_location(won_cards_locations[0])
	extra_hand.visible = false
	_extra_hands.set(hand_name, extra_hand)
	choice_hand_dropdown.add_item(hand_name)

func _on_dropdown_hand_choice_item_selected(index: int) -> void:
	var item_text: String = choice_hand_dropdown.get_item_text(index)
	var new_hand: Hand = _resolve_hand_choice(item_text)

	if _choice_hand != null:
		_choice_hand.visible = false

	if new_hand == null:
		push_warning("Dropdown_Hand_Choice selected '%s' but no matching hand was found" % item_text)
	else:
		new_hand.visible = true

	_choice_hand = new_hand

func _resolve_hand_choice(item_text: String) -> Hand:
	if item_text == "Won Cards":
		return _won_cards.get(_front_player)
	return _extra_hands.get(item_text)
	
func add_to_extra_hand(extra_hand_name: String, card: Card) -> bool:
	if !_extra_hands.has(extra_hand_name):
		return false
		
	_extra_hands[extra_hand_name].add(card)
	return true
	
func remove_from_extra_hand(extra_hand_name: String, index: int) -> Card:
	var extra_hand = _extra_hands[extra_hand_name]
	if extra_hand == null || extra_hand.size() <= index || index < 0:
		return null
		
	var removed_card = extra_hand.remove(index)
	return removed_card

# --- Scoring --------------------------------------------------------------

func add_score(hash_dir: String, score: int = 0) -> void:
	if not _player_scores.has(hash_dir):
		_player_scores[hash_dir] = score
	_update_scoreboard()


func add_to_score(hash_dir: String, score_to_add: int) -> void:
	_player_scores[hash_dir] += score_to_add
	updates_label_container.queue_display_string("%s received %d points" % [DEFAULT_NAMES[hash_dir], score_to_add])
	_update_scoreboard()


func set_score(hash_dir: String, score: int) -> void:
	_player_scores[hash_dir] = score
	updates_label_container.queue_display_string("%s score set to %d" % [DEFAULT_NAMES[hash_dir], score])
	_update_scoreboard()

func _update_scoreboard() -> void:
	if scoreboard_label == null:
		return
	var initial_line = "Scores:"
	var lines: Array[String] = [initial_line]
	for hash_dir in DEFAULT_NAMES:
		var score: int = _player_scores.get(hash_dir, 0)
		lines.append("%s: %d" % [DEFAULT_NAMES[hash_dir], score])
	scoreboard_label.text = "\n".join(lines)


# --- Actionables / buttons --------------------------------------------------

func add_actionable(actionable: String, count: int) -> void:
	print_verbose("Adding potential actionable: %s" % actionable)
	var actionable_lower = actionable.to_lower()
	_cur_actionables[actionable_lower] = count
	if actionable_lower == "play" or actionable_lower == "discard":
		_front_player_hand().set_selectable(true)
	elif actionable_lower == "draw":
		deck_selectable(true)
	_enable_disable_buttons()
	updates_label_container.queue_display_string("%s %d" % [actionable.capitalize(), count])

func reset_actionables() -> void:
	_cur_actionables = {}
	for hand in _player_hands.values():
		hand.set_selectable(false)
	for button in buttons.values():
		button.disabled = true
	deck_selectable(false)
	discard_selectable(false)


func _on_hand_card_clicked(_hand: Hand, _card: Card) -> void:
	pass
	
func _on_hand_card_selected(_hand: Hand, _card: Card) -> void:
	_enable_disable_buttons()

func _on_hand_card_deselected(_hand: Hand, _card: Card) -> void:
	_enable_disable_buttons()


func _on_button_pressed(actionable: String) -> void:
	var actionable_lower = actionable.to_lower()
	var msg: Dictionary = {"action": actionable_lower}
	if actionable_lower == "draw":
		msg["subject"] = "deck"
	else:
		msg["subject"] = "hand"
		msg["index"] = _front_player_hand().selected_card_indexes()
	_send_message(msg)
	reset_actionables()


func _enable_disable_buttons() -> void:
	for button in buttons.values():
		button.disabled = true

	for actionable in _cur_actionables:
		var count: int = _cur_actionables[actionable]
		var hand_to_check: Hand = _deck if actionable == "draw" else _front_player_hand()
		var selected_in_hand: Array[Card] = hand_to_check.selected_cards()
		if buttons.has(actionable):
			if selected_in_hand.size() == count:
				buttons[actionable].disabled = false
			else:
				buttons[actionable].disabled = true


# --- Game title / front player ----------------------------------------------

func game_title_callback(callback: Callable) -> void:
	_game_title_callback = callback
	_set_game_title()


func _set_game_title() -> void:
	if not _game_title_callback.is_valid():
		return
	_game_title_callback.call("%s (%s)" % [_game_name, DEFAULT_NAMES[_front_player]])


func set_front_player(hash_dir: String) -> bool:
	print_verbose("Setting position %s to be the front player" % hash_dir)
	if not _player_slot_exists(hash_dir):
		push_warning("Tried to set non-existant slot '%s' as front player")
		return false

	var difference: int = LOCATION_ORDER.find(hash_dir) - LOCATION_ORDER.find(_front_player)
	for i in _player_positions_clockwise_from_front.size():
		var pos: String = _player_positions_clockwise_from_front[i]
		_player_positions_clockwise_from_front[i] = num_to_direction(LOCATION_ORDER.find(pos) + difference)
	print_verbose("Changed player positions clockwise from front to %s" % _player_positions_clockwise_from_front)

	_front_player = hash_dir
	_reposition_hands()
	_set_game_title()
	updates_label_container.queue_display_string("You have been moved to seat %s" % [DEFAULT_NAMES[_front_player]])
	return true


# --- Player connection ------------------------------------------------------

func player_connected(player_dir: String) -> void:
	print_verbose("Including player slot %s in game" % player_dir)
	if not _connected_players.has(player_dir):
		_connected_players.append(player_dir)
		_create_player_hand(player_dir)
		_create_play_area(player_dir)
		_create_won_cards(player_dir)
		add_score(player_dir)
	else:
		print_verbose("Ignoring duplicate player connected")
	_reposition_hands()
	updates_label_container.queue_display_string("Player '%s' has connected" % [DEFAULT_NAMES[player_dir]])


func player_disconnected(player_dir: String) -> void:
	_connected_players.erase(player_dir)
	_reposition_hands()
	updates_label_container.queue_display_string("Player '%s' has disconnected" % [DEFAULT_NAMES[player_dir]])


# --- Internal helpers ---------------------------------------------------------
func _indicate_update(update: String) -> void:
	updates_label_container.set_children_visible()
	updates_label_container.set_display_string(update)

func _front_player_hand() -> Hand:
	return _player_hands.get(_front_player)

func _connect_hand_signals(hand: Hand) -> void:
	if !hand.hand_card_clicked.is_connected(_on_hand_card_clicked):
		hand.hand_card_clicked.connect(_on_hand_card_clicked)
	if !hand.hand_card_selected.is_connected(_on_hand_card_selected):
		hand.hand_card_selected.connect(_on_hand_card_selected)
	if !hand.hand_card_deselected.is_connected(_on_hand_card_deselected):
		hand.hand_card_deselected.connect(_on_hand_card_deselected)

func _reposition_hands() -> void:
	for hash_dir in _player_positions_clockwise_from_front:
		pass
	
	for i in range(_player_positions_clockwise_from_front.size()):
		var cur_dir = _player_positions_clockwise_from_front[i]
			
		var hand: Hand = _player_hands.get(cur_dir)
		if hand != null:
			hand.set_location(player_hand_locations[i])
		var play_area: Hand = _play_areas.get(cur_dir)
		if play_area != null:
			play_area.set_location(play_area_locations[i])
		var won_cards: Hand = _won_cards.get(cur_dir)
		if won_cards != null:
			won_cards.set_location(won_cards_locations[i])
		if _player_positions_clockwise_from_front[i] == _front_player:
			_choice_hand = won_cards
		var cur_dir_name = DEFAULT_NAMES[cur_dir]
		if i == 0:
			cur_dir_name += " (you)"
		var label = player_name_labels[i]
		if label != null:
			label.text = cur_dir_name


func _player_slot_exists(hash_dir: String) -> bool:
	return LOCATION_ORDER.has(hash_dir)


## Adapter so Hand.set_location(Rect2) keeps working off editor-placed
## HandBounds nodes. Revisit if/when Hand's location API changes to take
## a HandBounds/Node2D directly instead of a raw Rect2.
func _to_rect(bounds: HandBounds) -> Rect2:
	if bounds == null:
		push_warning("GameMaster: missing HandBounds location, defaulting to Rect2() at origin")
		return Rect2()
	return bounds.to_rect()


func _send_message(msg: Dictionary) -> void:
	_websocket.send_msg(JSON.stringify(msg))
