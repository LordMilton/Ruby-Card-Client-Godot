extends Node
class_name CardImages
## Fetches and caches Texture2D resources for Cards. Intended to be
## registered as an autoload singleton (Project > Project Settings >
## Autoload) so any Card can call CardImages.card_image(self) without
## needing a per-instance reference wired in.
##
## Card hover text has intentionally NOT been ported here — that's moving
## onto Card itself instead of living in the image/texture provider.

const HIGHLIGHT_IMAGE_NAME := "yellow.png"

## Directory (res:// path) containing per-card images, named like
## "hearts_king.jpg" and "back.jpg", matching Card's suit_value lookup.
@export var card_images_dir: String = "res://cards"
const DEFAULT_CARD_IMAGES = {
	"back": preload("res://cards/back.jpg"),
	"hearts_ace": preload("res://cards/hearts_ace.jpg"),
	"hearts_2": preload("res://cards/hearts_2.jpg"),
	"hearts_3": preload("res://cards/hearts_3.jpg"),
	"hearts_4": preload("res://cards/hearts_4.jpg"),
	"hearts_5": preload("res://cards/hearts_5.jpg"),
	"hearts_6": preload("res://cards/hearts_6.jpg"),
	"hearts_7": preload("res://cards/hearts_7.jpg"),
	"hearts_8": preload("res://cards/hearts_8.jpg"),
	"hearts_9": preload("res://cards/hearts_9.jpg"),
	"hearts_10": preload("res://cards/hearts_10.jpg"),
	"hearts_jack": preload("res://cards/hearts_jack.jpg"),
	"hearts_queen": preload("res://cards/hearts_queen.jpg"),
	"hearts_king": preload("res://cards/hearts_king.jpg"),
	"clubs_ace": preload("res://cards/clubs_ace.jpg"),
	"clubs_2": preload("res://cards/clubs_2.jpg"),
	"clubs_3": preload("res://cards/clubs_3.jpg"),
	"clubs_4": preload("res://cards/clubs_4.jpg"),
	"clubs_5": preload("res://cards/clubs_5.jpg"),
	"clubs_6": preload("res://cards/clubs_6.jpg"),
	"clubs_7": preload("res://cards/clubs_7.jpg"),
	"clubs_8": preload("res://cards/clubs_8.jpg"),
	"clubs_9": preload("res://cards/clubs_9.jpg"),
	"clubs_10": preload("res://cards/clubs_10.jpg"),
	"clubs_jack": preload("res://cards/clubs_jack.jpg"),
	"clubs_queen": preload("res://cards/clubs_queen.jpg"),
	"clubs_king": preload("res://cards/clubs_king.jpg"),
	"diamonds_ace": preload("res://cards/diamonds_ace.jpg"),
	"diamonds_2": preload("res://cards/diamonds_2.jpg"),
	"diamonds_3": preload("res://cards/diamonds_3.jpg"),
	"diamonds_4": preload("res://cards/diamonds_4.jpg"),
	"diamonds_5": preload("res://cards/diamonds_5.jpg"),
	"diamonds_6": preload("res://cards/diamonds_6.jpg"),
	"diamonds_7": preload("res://cards/diamonds_7.jpg"),
	"diamonds_8": preload("res://cards/diamonds_8.jpg"),
	"diamonds_9": preload("res://cards/diamonds_9.jpg"),
	"diamonds_10": preload("res://cards/diamonds_10.jpg"),
	"diamonds_jack": preload("res://cards/diamonds_jack.jpg"),
	"diamonds_queen": preload("res://cards/diamonds_queen.jpg"),
	"diamonds_king": preload("res://cards/diamonds_king.jpg"),
	"spades_ace": preload("res://cards/spades_ace.jpg"),
	"spades_2": preload("res://cards/spades_2.jpg"),
	"spades_3": preload("res://cards/spades_3.jpg"),
	"spades_4": preload("res://cards/spades_4.jpg"),
	"spades_5": preload("res://cards/spades_5.jpg"),
	"spades_6": preload("res://cards/spades_6.jpg"),
	"spades_7": preload("res://cards/spades_7.jpg"),
	"spades_8": preload("res://cards/spades_8.jpg"),
	"spades_9": preload("res://cards/spades_9.jpg"),
	"spades_10": preload("res://cards/spades_10.jpg"),
	"spades_jack": preload("res://cards/spades_jack.jpg"),
	"spades_queen": preload("res://cards/spades_queen.jpg"),
	"spades_king": preload("res://cards/spades_king.jpg")
}

## File extension to load, without the dot. Change if your art is .png.
@export var image_extension: String = "jpg"

var _card_images: Dictionary = {}  # String (card_name) -> Texture2D
var _highlight_image: Texture2D = null


func initialize_images(card_set_path: String = "") -> void:
	print_verbose("Fetching card images")
	_card_images.clear()

	if card_set_path.is_empty():
		_card_images = DEFAULT_CARD_IMAGES.duplicate()
		return

	var is_user_path := card_set_path.begins_with("user://") or card_set_path.begins_with("/") or card_set_path.substr(1, 1) == ":"

	var dir := DirAccess.open(card_set_path)
	if dir == null:
		push_error("CardImages: couldn't open directory %s" % card_set_path)
		return

	for filename in dir.get_files():
		if not filename.ends_with(".%s" % image_extension):
			continue

		var card_name: String = filename.get_basename()
		var full_path: String = "%s/%s" % [card_set_path, filename]
		var texture: Texture2D

		if is_user_path:
			var image := Image.new()
			var err := image.load(full_path)
			if err != OK:
				push_warning("CardImages: failed to load %s" % full_path)
				continue
			texture = ImageTexture.create_from_image(image)
		else:
			texture = ResourceLoader.load(full_path, "Texture2D")
			if texture == null:
				push_warning("CardImages: failed to load %s" % full_path)
				continue

		_card_images[card_name] = texture


func card_image(card: Card) -> Texture2D:
	if _card_images.is_empty():
		initialize_images()

	if card.hidden():
		return _card_images.get("back")

	return _card_images.get("%s_%s" % [card.suit.to_lower(), card.value.to_lower()])


func highlight_image() -> Texture2D:
	if _highlight_image == null:
		var highlight_path: String = "%s/../%s" % [card_images_dir, HIGHLIGHT_IMAGE_NAME]
		_highlight_image = load(highlight_path) as Texture2D
		if _highlight_image == null:
			push_warning("CardImages: failed to load highlight image at %s" % highlight_path)

	return _highlight_image
