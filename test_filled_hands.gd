extends Node
class_name TestFillAllHands
## Debug/test script: connects all four player slots and drops one Card
## into every hand-like area in the game (player hands, play areas, won
## cards, plus the deck and discard piles), so you can eyeball layout and
## click behavior without a live server.
##
## Attach this to a Node in a test scene, assign `game_master` to your
## GameMaster instance in the Inspector, and run the scene.

@export var game_master: GameMaster

const DIRECTIONS: Array[String] = ["S", "W", "N", "E"]

@onready var card_base := preload("res://card.tscn")

func _ready() -> void:
	if game_master == null:
		push_error("TestFillAllHands: no GameMaster assigned")
		return

	for direction in DIRECTIONS:
		game_master.player_connected(direction)

	var num_cards = 7
	for direction in DIRECTIONS:
		for i in range(num_cards):
			game_master.add_to_hand(direction, _make_card())
			game_master.add_to_play_area(direction, _make_card())
			game_master.add_to_won_cards(direction, _make_card())

	for i in range(num_cards):
		game_master.add_to_deck(_make_blank_card())
		game_master.add_to_discard(_make_card())
		
	var extra_hand_names = ["Extra A", "Extra B"]
	for extra_hand_name in extra_hand_names:
		game_master.add_extra_hand(extra_hand_name)
		for i in range(3):
			game_master.add_to_extra_hand(extra_hand_name, _make_card())

	var actionables = ["Draw", "Play", "Discard"]
	for actionable in actionables:
		game_master.add_actionable(actionable, 1)
	print_verbose("TestFillAllHands: added a card to every hand/area")


func _make_card() -> Card:
	var card := card_base.instantiate()
	card.setup("hearts", "king")
	return card

func _make_blank_card() -> Card:
	var card := card_base.instantiate()
	card.setup("", "")
	return card
