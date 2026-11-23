class_name CardView
extends Control
## An event card drawn at 2x its 64x88 art (128x176), so the art scales by a whole number
## and the text gets real room. Flips between back and front.
##
## Text areas follow the card art layout (in 1x art pixels): title band y 3-14,
## picture y 15-44, text box y 46-85.

const ART_SIZE := Vector2(64, 88)
const SCALE: float = 2.0
const SIZE := ART_SIZE * SCALE
## Card text sizes are fixed (the card art is a fixed size), independent of the text setting.
const TITLE_SIZE: int = 12
const BODY_SIZE: int = 12

var card: Dictionary = {}
var face_up: bool = false
var _tex: TextureRect
var _title: Label
var _body: Label


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = TextureRect.new()
	_tex.size = SIZE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)

	_title = UiKit.label("", 8, Color("f4ecd8"))
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 1)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.position = Vector2(4, 3 * SCALE)
	_title.size = Vector2(SIZE.x - 8, 12 * SCALE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title)

	_body = UiKit.label("", 8)
	_body.add_theme_font_size_override("font_size", BODY_SIZE)
	_body.add_theme_constant_override("line_spacing", 2)
	_body.position = Vector2(4 * SCALE, 47 * SCALE)
	_body.size = Vector2(SIZE.x - 8 * SCALE, 37 * SCALE)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_body)
	show_back()


func show_back() -> void:
	face_up = false
	_tex.texture = UiKit.tex("res://assets/sprites/card_back.png")
	_title.visible = false
	_body.visible = false


func show_front(c: Dictionary) -> void:
	card = c
	face_up = true
	_tex.texture = UiKit.tex("res://assets/sprites/card_front_%s.png" % c.get("kind", "production"))
	_title.text = c.get("title", "")
	_body.text = c.get("text", "")
	_title.visible = true
	_body.visible = true


## Flips to the front with a squash animation, keeping whatever scale the card has.
func flip_to(c: Dictionary, duration: float) -> void:
	var sx := scale.x
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, duration * 0.5)
	await tw.finished
	show_front(c)
	Sfx.play("card_flip")
	tw = create_tween()
	tw.tween_property(self, "scale:x", sx, duration * 0.5)
	await tw.finished
