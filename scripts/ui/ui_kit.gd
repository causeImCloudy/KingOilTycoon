class_name UiKit
extends RefCounted
## Small helpers for building UI in code, plus the shared theme.

const INK := Color("1d1611")
const PAPER := Color("efe3c6")
const PAPER_DARK := Color("d9c9a3")
const DUST := Color("b98a57")
const NIGHT := Color("2a1d15")
const GOLD := Color("f2c14e")
const RED := Color("c8402e")
const GREEN := Color("4f7d3a")

## Size roles used at call sites. fs() turns them into the size actually rendered.
const FONT_SMALL: int = 8
const FONT_BODY: int = 10
const FONT_TITLE: int = 16
## Rendered sizes per text-size setting (Profile "text_size": 0 normal, 1 large, 2 extra large).
## The fonts are 8 px pixel fonts. Only multiples of 4 (8, 12, 16, 20) land on whole pixels at
## the usual 2x window scale; in-between sizes (10, 14, 18) render thinner and uneven and look
## like a different font. Keep every size here a multiple of 4.
const SIZE_MAPS: Array = [
	{8: 8, 10: 12, 16: 16},
	{8: 12, 10: 12, 16: 16},
	{8: 12, 10: 16, 16: 20},
]
## Extra pixels between wrapped lines.
const LINE_SPACING: int = 3
## Extra left/right padding inside panels, buttons and fields. The pixel fonts have no side
## bearing, so text otherwise sits right against vertical borders.
const PAD_X: int = 6

const MAIN_FONT := "res://assets/fonts/main_font.ttf"
const TITLE_FONT := "res://assets/fonts/title_font.ttf"
static var _fonts: Dictionary = {}

static var _theme: Theme


static func money(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if neg else "$") + s + out


## Campaign dollars are written with their own $ sign (icon_dollar.png) and no "$" in the text.
const DOLLAR_ICON := "res://assets/ui/icon_dollar.png"


## "250,000": a campaign-dollar amount without the $ (the icon stands in for it).
static func dollar_text(v: int) -> String:
	return money(v).replace("$", "")


## The campaign-dollar sign.
static func dollar_icon() -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(DOLLAR_ICON)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A campaign-dollar amount: the $ sign and the number.
static func dollar_amount(v: int, size: int = 8, color: Color = INK) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if v < 0:
		row.add_child(label("-", size, color))
	row.add_child(dollar_icon())
	row.add_child(label(dollar_text(absi(v)), size, color))
	return row


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Rendered font size for a size role (8 small, 10 body, 16 title).
static func fs(size: int) -> int:
	var level := clampi(int(Profile.setting("text_size")), 0, SIZE_MAPS.size() - 1)
	return SIZE_MAPS[level].get(size, size)


## Loads a font, antialiased when the "smooth_text" setting is on.
static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		var src := load(path) as FontFile
		if src:
			var ff := src.duplicate() as FontFile
			var smooth := bool(Profile.setting("smooth_text"))
			ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if smooth else TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_LIGHT if smooth else TextServer.HINTING_NORMAL
			f = ff
	_fonts[path] = f
	return f


## Rebuilds the theme after a text setting changes (screens pick it up when reopened).
static func reset_theme() -> void:
	_theme = null
	_fonts.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.theme = get_theme()


static func label(text: String, size: int = FONT_BODY, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	if size == FONT_TITLE:
		var tf := font(TITLE_FONT)
		if tf:
			l.add_theme_font_override("font", tf)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, size: int = FONT_BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs(size))
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	b.focus_mode = Control.FOCUS_ALL
	return b


static func panel(padding: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := get_theme().get_stylebox("panel", "PanelContainer").duplicate() as StyleBox
	sb.content_margin_left = padding + PAD_X
	sb.content_margin_right = padding + PAD_X
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep: int = 4) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep: int = 4) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(selected)
	o.add_theme_font_size_override("font_size", fs(FONT_BODY))
	o.item_selected.connect(cb)
	return o


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func _build_theme() -> Theme:
	var t := Theme.new()
	var main := font(MAIN_FONT)
	if main == null:
		var fb := ThemeDB.fallback_font
		if fb is FontFile:
			var ff := (fb as FontFile).duplicate() as FontFile
			ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			main = ff
		else:
			main = fb
	t.default_font = main
	t.default_font_size = fs(FONT_BODY)
	t.set_constant("line_spacing", "Label", LINE_SPACING)
	t.set_font_size("font_size", "LineEdit", fs(FONT_SMALL))
	t.set_font_size("font_size", "PopupMenu", fs(FONT_BODY))
	t.set_font_size("font_size", "TooltipLabel", fs(FONT_SMALL))
	t.set_constant("separation", "BoxContainer", 6)

	var panel_tex := tex("res://assets/ui/panel.png")
	var panel_sb: StyleBox
	if panel_tex:
		var st := StyleBoxTexture.new()
		st.texture = panel_tex
		st.texture_margin_left = 8
		st.texture_margin_right = 8
		st.texture_margin_top = 8
		st.texture_margin_bottom = 8
		panel_sb = st
	else:
		var sf := StyleBoxFlat.new()
		sf.bg_color = PAPER
		sf.border_color = INK
		sf.set_border_width_all(1)
		panel_sb = sf
	panel_sb.content_margin_left = 6 + PAD_X
	panel_sb.content_margin_right = 6 + PAD_X
	panel_sb.content_margin_top = 6
	panel_sb.content_margin_bottom = 6
	t.set_stylebox("panel", "PanelContainer", panel_sb)
	t.set_stylebox("panel", "Panel", panel_sb)
	t.set_stylebox("panel", "PopupPanel", panel_sb)

	var btn_tex := tex("res://assets/ui/button.png")
	var focus_ring := StyleBoxFlat.new()
	focus_ring.draw_center = false
	focus_ring.border_color = Color("fff1ad")
	focus_ring.set_border_width_all(1)
	focus_ring.set_expand_margin_all(1)
	for control_type in ["Button", "OptionButton", "CheckBox", "LineEdit"]:
		t.set_stylebox("focus", control_type, focus_ring)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox
		if btn_tex:
			var st := StyleBoxTexture.new()
			st.texture = btn_tex
			st.texture_margin_left = 6
			st.texture_margin_right = 6
			st.texture_margin_top = 6
			st.texture_margin_bottom = 6
			match state:
				"hover": st.texture = preload("res://assets/ui/button_hover.png")
				"pressed": st.texture = preload("res://assets/ui/button_pressed.png")
				"disabled": st.modulate_color = Color(0.6, 0.6, 0.6, 0.8)
			sb = st
		else:
			var sf := StyleBoxFlat.new()
			sf.bg_color = GOLD if state != "disabled" else Color(0.6, 0.6, 0.6)
			sf.border_color = INK
			sf.set_border_width_all(1)
			sb = sf
		sb.content_margin_left = 6 + PAD_X
		sb.content_margin_right = 6 + PAD_X
		sb.content_margin_top = 3
		sb.content_margin_bottom = 4
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state, "OptionButton", sb)
	for c in ["Button", "OptionButton"]:
		t.set_color("font_color", c, INK)
		t.set_color("font_hover_color", c, INK)
		t.set_color("font_pressed_color", c, INK)
		t.set_color("font_focus_color", c, INK)
		t.set_color("font_disabled_color", c, Color(0.25, 0.22, 0.2))
	t.set_color("font_color", "Label", INK)
	# Checkboxes: plain text with a box, not button-styled.
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckBox", INK)

	var line_sb := StyleBoxFlat.new()
	line_sb.bg_color = Color("fff8e6")
	line_sb.border_color = INK
	line_sb.set_border_width_all(1)
	line_sb.content_margin_left = 3 + PAD_X
	line_sb.content_margin_right = 3 + PAD_X
	line_sb.content_margin_top = 2
	line_sb.content_margin_bottom = 2
	t.set_stylebox("normal", "LineEdit", line_sb)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color("716047"))
	t.set_color("caret_color", "LineEdit", INK)

	var popup_sb := StyleBoxFlat.new()
	popup_sb.bg_color = PAPER
	popup_sb.border_color = INK
	popup_sb.set_border_width_all(1)
	popup_sb.content_margin_left = 4
	popup_sb.content_margin_right = 4
	popup_sb.content_margin_top = 3
	popup_sb.content_margin_bottom = 3
	t.set_stylebox("panel", "PopupMenu", popup_sb)
	t.set_constant("item_start_padding", "PopupMenu", 4 + PAD_X)
	t.set_constant("item_end_padding", "PopupMenu", 4 + PAD_X)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = GOLD
	t.set_stylebox("hover", "PopupMenu", hover_sb)
	t.set_stylebox("panel", "ItemList", line_sb)
	t.set_stylebox("selected", "ItemList", hover_sb)
	t.set_stylebox("selected_focus", "ItemList", hover_sb)
	t.set_stylebox("focus", "ItemList", focus_ring)
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_color("font_hovered_color", "ItemList", INK)

	var tip := StyleBoxFlat.new()
	tip.bg_color = PAPER
	tip.border_color = INK
	tip.set_border_width_all(1)
	tip.content_margin_left = 3 + PAD_X
	tip.content_margin_right = 3 + PAD_X
	tip.content_margin_top = 2
	tip.content_margin_bottom = 2
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)

	var sbar := StyleBoxFlat.new()
	sbar.bg_color = PAPER_DARK
	sbar.content_margin_left = 3
	sbar.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", sbar)
	var grab := StyleBoxFlat.new()
	grab.bg_color = DUST
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)

	var slider_sb := StyleBoxFlat.new()
	slider_sb.bg_color = DUST
	slider_sb.content_margin_top = 2
	slider_sb.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider_sb)
	return t


## Builds a background that fills the screen: menu art if present, otherwise a dusk gradient.
static func backdrop(parent: Control) -> void:
	var bg := TextureRect.new()
	bg.texture = tex("res://assets/ui/menu_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.06, 0.03, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)


## Standard screen header: title + back button.
static func header(parent: Control, title: String, back: Callable) -> void:
	var bar := hbox(10)
	bar.position = Vector2(8, 4)
	bar.size = Vector2(624, 22)
	var b := button("< Back", back)
	bar.add_child(b)
	var l := label(title, FONT_TITLE, PAPER)
	l.add_theme_color_override("font_shadow_color", INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	bar.add_child(l)
	parent.add_child(bar)
