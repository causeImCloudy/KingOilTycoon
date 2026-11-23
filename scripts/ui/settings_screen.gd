extends Control
## Settings: display, text, animation speed, audio.

const LABEL_W: float = 130.0


func _ready() -> void:
	UiKit.backdrop(self)
	UiKit.header(self, "Settings", func(): Session.goto("menu"))
	var pnl := UiKit.panel(10)
	pnl.position = Vector2(110, 34)
	pnl.custom_minimum_size = Vector2(420, 0)
	add_child(pnl)
	var v := UiKit.vbox(8)
	pnl.add_child(v)

	v.add_child(UiKit.label("Display", 10, Color("7a2a1a")))
	var full := CheckBox.new()
	full.text = "Fullscreen  (F11 or Alt+Enter)"
	full.add_theme_font_size_override("font_size", UiKit.fs(10))
	full.add_theme_color_override("font_color", UiKit.INK)
	full.add_theme_color_override("font_hover_color", UiKit.INK)
	full.add_theme_color_override("font_pressed_color", UiKit.INK)
	full.button_pressed = bool(Profile.setting("fullscreen"))
	full.toggled.connect(func(on): Profile.set_setting("fullscreen", on))
	v.add_child(full)
	var scalings := ["fill", "pixel"]
	_row(v, "Scaling", UiKit.option(["Fill the screen", "Pixel-perfect (may add borders)"],
		maxi(0, scalings.find(str(Profile.setting("scaling")))),
		func(i): Profile.set_setting("scaling", scalings[i])))

	v.add_child(UiKit.label("Text", 10, Color("7a2a1a")))
	_row(v, "Text size", UiKit.option(["Normal", "Large", "Extra large"], int(Profile.setting("text_size")),
		func(i):
			Profile.set_setting("text_size", i)
			Session.goto("settings")))
	var smooth := CheckBox.new()
	smooth.text = "Smooth text (easier to read)"
	smooth.add_theme_font_size_override("font_size", UiKit.fs(10))
	smooth.add_theme_color_override("font_color", UiKit.INK)
	smooth.add_theme_color_override("font_hover_color", UiKit.INK)
	smooth.add_theme_color_override("font_pressed_color", UiKit.INK)
	smooth.button_pressed = bool(Profile.setting("smooth_text"))
	smooth.toggled.connect(func(on):
		Profile.set_setting("smooth_text", on)
		Session.goto("settings"))
	v.add_child(smooth)

	v.add_child(UiKit.label("Gameplay", 10, Color("7a2a1a")))
	var speeds := [0.75, 1.0, 1.5, 2.0, 99.0]
	var names := ["Slow", "Normal", "Fast", "Faster", "Instant (skip)"]
	_row(v, "Animations", UiKit.option(names, maxi(0, speeds.find(float(Profile.setting("anim_speed")))),
		func(i): Profile.set_setting("anim_speed", speeds[i])))

	v.add_child(UiKit.label("Audio", 10, Color("7a2a1a")))
	for key in ["sfx", "music"]:
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Profile.setting(key))
		s.custom_minimum_size = Vector2(180, 14)
		var k: String = key
		s.value_changed.connect(func(val): Profile.set_setting(k, val))
		_row(v, "Sound effects" if key == "sfx" else "Music", s)


func _row(parent: Control, text: String, control: Control) -> void:
	var r := UiKit.hbox(8)
	var l := UiKit.label(text, 10)
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	r.add_child(l)
	r.add_child(control)
	parent.add_child(r)
