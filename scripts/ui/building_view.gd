class_name BuildingView
extends Control
## A homestead building (see Homestead) drawn at a whole-number zoom, for menus and the store.
## The building stands on the bottom-center of the control.

var look: Dictionary = {}
var kind: String = "house"
var zoom: int = 2


func setup(p_look: Dictionary, p_kind: String, p_zoom: int = 2) -> BuildingView:
	look = p_look
	kind = p_kind
	zoom = p_zoom
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Homestead.SIZE[kind] * zoom
	queue_redraw()
	return self


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
	var bottom := Vector2(size.x / zoom / 2.0, size.y / zoom).floor()
	Homestead.draw(self, bottom, look, kind)
