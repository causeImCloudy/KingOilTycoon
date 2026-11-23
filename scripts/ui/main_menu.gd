extends Control
## Title screen.


func _ready() -> void:
	Sfx.music("menu")
	UiKit.backdrop(self)
	var logo := TextureRect.new()
	logo.texture = UiKit.tex("res://assets/ui/title_logo.png")
	logo.position = Vector2(24, 18)
	add_child(logo)

	var pnl := UiKit.panel(8)
	pnl.position = Vector2(64, 96)
	pnl.custom_minimum_size = Vector2(176, 0)
	add_child(pnl)
	var v := UiKit.vbox(2 if Session.has_save() else 4)
	pnl.add_child(v)
	if Session.has_save():
		v.add_child(UiKit.button("Continue Saved Game", func(): Session.resume_saved()))
	v.add_child(UiKit.button("Campaign", func(): Session.goto("campaign")))
	v.add_child(UiKit.button("Classic Game", func(): Session.goto("setup")))
	v.add_child(UiKit.button("Multiplayer", func(): Session.goto("lobby")))
	v.add_child(UiKit.button("Customize & Store", func(): Session.open_shop("tycoon", "menu")))
	v.add_child(UiKit.button("Settings", func(): Session.goto("settings")))
	if OS.is_debug_build():
		v.add_child(UiKit.button("Map Editor (dev)", func(): Session.goto("board_editor")))
	v.add_child(UiKit.button("Quit", func(): get_tree().quit()))
	for c in v.get_children():
		if c is Button:
			c.custom_minimum_size = Vector2(160, 18)
	(v.get_child(0) as Button).grab_focus.call_deferred()

	var ver := UiKit.label("Prototype build", 8, Color(1, 1, 1, 0.6))
	ver.add_theme_color_override("font_outline_color", UiKit.INK)
	ver.add_theme_constant_override("outline_size", 2)
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position -= Vector2(8, 6)
