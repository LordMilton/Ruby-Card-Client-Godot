@tool
extends Node2D
class_name HandBounds
## Defines a Hand's layout bounding box, positioned and sized directly in
## the Godot editor (drag this node for position, edit `size` in the
## Inspector — the rect is drawn live so you can see what you're setting).
## Replaces the old metadata-based Node2D + "size" guess: pass the result
## of to_rect() straight into Hand.set_location().

@export var size: Vector2 = Vector2(400, 150):
	set(value):
		size = value
		queue_redraw()

## Editor-only visuals — a plain Node2D has no bounds to see otherwise.
@export var editor_color: Color = Color(0.2, 0.8, 1.0, 0.35)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), editor_color, true)
	draw_rect(Rect2(Vector2.ZERO, size), editor_color.lightened(0.4), false, 2.0)


## The Rect2 this node defines, in this node's parent's local space —
## matches what Hand.set_location(bounds: Rect2) expects.
func to_rect() -> Rect2:
	return Rect2(position, size)
