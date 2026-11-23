class_name PlayerPanel
extends PanelContainer
## One player's side-panel entry: animated portrait, name, cash, wells, land. Clicking it emits
## `clicked` (the match starts a trade with that player).

signal clicked(index: int)

var index: int = -1
var portrait: CharacterView
var _name: Label
var _cash: Label
var _stats: Label
var _turn_marker: ColorRect
var _shown_cash: int = 0


func build(p: Dictionary, color: Color) -> void:
	index = p.index
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("efe3c6")
	sb.border_color = Color("1d1611")
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.content_margin_left = 6 + UiKit.PAD_X
	sb.content_margin_right = 3 + UiKit.PAD_X
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	add_theme_stylebox_override("panel", sb)
	set_color(color)
	var row := UiKit.hbox(6)
	add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(24, 24)
	holder.clip_contents = true
	row.add_child(holder)
	portrait = CharacterView.new()
	portrait.setup(p.get("character", {}), true)
	holder.add_child(portrait)
	# Two lines: name + cash, then wells/land.
	var col := UiKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var line1 := UiKit.hbox(6)
	col.add_child(line1)
	_name = UiKit.label(p.name, 8)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size = Vector2(60, 0)
	line1.add_child(_name)
	_cash = UiKit.label("", 8, Color("2f5d3a"))
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line1.add_child(_cash)
	_stats = UiKit.label("", 8, Color("5a4632"))
	col.add_child(_stats)
	_turn_marker = ColorRect.new()
	_turn_marker.color = Color("f2c14e")
	_turn_marker.custom_minimum_size = Vector2(3, 24)
	row.add_child(_turn_marker)
	_shown_cash = p.cash
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(index))


func set_color(c: Color) -> void:
	var sb := get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = c


func refresh(p: Dictionary, wells: int, plots: int, is_current: bool, animate: bool = false) -> void:
	_turn_marker.visible = is_current
	modulate = Color(1, 1, 1, 0.45) if p.bankrupt else Color.WHITE
	_stats.text = "BANKRUPT" if p.bankrupt else "%d wells  %d land" % [wells, plots]
	var target: int = p.cash
	if animate and target != _shown_cash:
		var tw := create_tween()
		tw.tween_method(func(v: float): _cash.text = UiKit.money(int(v)), float(_shown_cash), float(target), 0.4)
	else:
		_cash.text = UiKit.money(target)
	_shown_cash = target
