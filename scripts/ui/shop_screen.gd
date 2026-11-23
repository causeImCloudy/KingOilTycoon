extends Control
## Customize & Store: your tycoon's name and look, and the General Store, on one screen. Every
## tab lists all options of one kind: owned ones can be put on (Wear / Use), others bought with
## Liquid Gold (buying also puts it on). Campaign upgrades have their own tab. Pick an item to try
## it on in the preview. Opened from the main menu and the campaign map; Session.shop_tab /
## shop_return say which tab to open and where Back goes.
##
## Session.customize_mode = "create" is first-time character creation before the campaign: a
## welcome line and a "Start the Campaign" button.

## [id, label, row]: row 0 = the tycoon, row 1 = the homestead and campaign upgrades.
const TABS: Array = [
	["tycoon", "Character", 0], ["skin", "Skin", 0], ["outfit", "Outfits", 0], ["hat", "Hats", 0],
	["hat_color", "Hat Colors", 0], ["paint", "Rig Paint", 0],
	["house", "Houses", 1], ["outbuilding", "Sheds", 1], ["siding", "Siding", 1], ["roof", "Roofs", 1],
	["upgrades", "Upgrades", 1],
]
## Tabs previewed on the homestead instead of the tycoon.
const HOME_TABS: Array[String] = ["house", "outbuilding", "siding", "roof"]
## Tabs whose items you "use" rather than "wear".
const USE_TABS: Array[String] = ["tycoon", "skin", "house", "outbuilding", "siding", "roof"]
## Tabs whose cards show your tycoon's head with that option.
const HEAD_TABS: Array[String] = ["tycoon", "skin", "hat"]
const CARD := Vector2(110, 78)
const INK := Color("1d1611")
const GOLD_TXT := Color("7a5a10")
const OWNED := Color("3e7a4c")
const SHORT := Color("a02a1a")

var tab: String = "outfit"
var selected: String = ""
var tab_buttons: Dictionary = {}
var balance: Label
var grid: GridContainer
var scroll: ScrollContainer
var group := ButtonGroup.new()

# Preview / detail column.
var body: CharacterView
var derricks: Array[TextureRect] = []
var house: BuildingView
var sheds: Array[BuildingView] = []
var item_name: Label
var item_status: Label
var item_desc: Label
var buy_btn: Button
var wear_btn: Button
var name_edit: LineEdit
var creating: bool = false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	creating = Session.customize_mode == "create"
	Session.customize_mode = "edit"
	tab = "tycoon" if creating else Session.shop_tab
	UiKit.backdrop(self)
	UiKit.header(self, "Create Your Tycoon" if creating else "Customize & Store",
		func(): Session.goto("menu" if creating else Session.shop_return))

	var bal := UiKit.hbox(3)
	bal.position = Vector2(470, 6)
	var drop := TextureRect.new()
	drop.texture = UiKit.tex("res://assets/ui/icon_liquid_gold.png")
	bal.add_child(drop)
	balance = UiKit.label("", 10, Color("f2c14e"))
	balance.add_theme_color_override("font_outline_color", INK)
	balance.add_theme_constant_override("outline_size", 2)
	bal.add_child(balance)
	add_child(bal)

	# Two tab rows: the tycoon, then the homestead and campaign upgrades.
	var rows: Array[HBoxContainer] = []
	for r in 2:
		var row := UiKit.hbox(3)
		row.position = Vector2(12, 30 + r * 22)
		add_child(row)
		var cap := UiKit.label("Tycoon:" if r == 0 else "Homestead:", 8, Color("f1e4ba"))
		cap.custom_minimum_size = Vector2(54, 0)
		row.add_child(cap)
		rows.append(row)
	var tab_group := ButtonGroup.new()
	for t in TABS:
		var id: String = t[0]
		if id == "upgrades":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			rows[1].add_child(gap)
			rows[1].add_child(UiKit.label("Campaign:", 8, Color("f1e4ba")))
		var b := UiKit.button(t[1], func(): _set_tab(id), 8)
		b.toggle_mode = true
		b.button_group = tab_group
		rows[int(t[2])].add_child(b)
		tab_buttons[id] = b

	var left := UiKit.panel(6)
	left.position = Vector2(12, 74)
	left.custom_minimum_size = Vector2(380, 282)
	left.size = left.custom_minimum_size
	add_child(left)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	var right := UiKit.panel(6)
	right.position = Vector2(400, 74)
	right.custom_minimum_size = Vector2(228, 282)
	right.size = right.custom_minimum_size
	add_child(right)
	var rv := UiKit.vbox(4)
	right.add_child(rv)
	# Your name, and a random look from what you own.
	var name_row := UiKit.hbox(4)
	rv.add_child(name_row)
	name_edit = LineEdit.new()
	name_edit.text = Profile.data.name
	name_edit.max_length = 20
	name_edit.placeholder_text = "Your name"
	name_edit.tooltip_text = "Your tycoon's name"
	name_edit.custom_minimum_size = Vector2(0, 18)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", UiKit.fs(8))
	name_edit.text_changed.connect(func(t):
		Profile.data.name = t.strip_edges() if t.strip_edges() != "" else "Player"
		Profile.save())
	name_row.add_child(name_edit)
	var random_btn := UiKit.button("Random", _randomize, 8)
	random_btn.tooltip_text = "A random look from what you own"
	name_row.add_child(random_btn)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(204, 112)
	stage.clip_contents = true
	rv.add_child(stage)
	var floor_strip := ColorRect.new()
	floor_strip.color = Color(0.45, 0.32, 0.2, 0.35)
	floor_strip.position = Vector2(0, 92)
	floor_strip.size = Vector2(204, 20)
	floor_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(floor_strip)
	body = CharacterView.new()
	body.position = Vector2(8, 8)
	body.scale = Vector2(2, 2)
	stage.add_child(body)
	for i in 3:
		var d := TextureRect.new()
		d.texture = UiKit.tex("res://assets/sprites/derrick.png")
		d.position = Vector2(110 + i * 30, 56)
		d.scale = Vector2(3, 3)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(d)
		derricks.append(d)
	house = BuildingView.new().setup(Profile.look(), "house", 3)
	house.position = Vector2(24, 34)
	house.size = house.custom_minimum_size
	stage.add_child(house)
	for i in 2:
		var b := BuildingView.new().setup(Profile.look(), "outbuilding", 3)
		b.position = Vector2(104 + i * 46, 58)
		b.size = b.custom_minimum_size
		stage.add_child(b)
		sheds.append(b)
	item_name = UiKit.label("", 10)
	rv.add_child(item_name)
	item_status = UiKit.label("", 8, GOLD_TXT)
	rv.add_child(item_status)
	item_desc = UiKit.label("", 8, Color("5a4632"))
	item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_desc.custom_minimum_size = Vector2(204, 0)
	item_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_desc.max_lines_visible = 5
	item_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rv.add_child(item_desc)
	var btns := UiKit.hbox(4)
	rv.add_child(btns)
	buy_btn = UiKit.button("Buy", _buy, 8)
	buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(buy_btn)
	wear_btn = UiKit.button("Wear", _wear, 8)
	wear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(wear_btn)
	if creating:
		# In the header, where the Liquid Gold balance usually sits (none yet on a first visit).
		bal.visible = false
		var start := UiKit.button("Start Campaign >", _finish, 8)
		add_child(start) # in the tree first, so the game theme's styles are the ones copied
		for style in ["normal", "hover", "pressed"]:
			var sb := start.get_theme_stylebox(style).duplicate() as StyleBox
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			start.add_theme_stylebox_override(style, sb)
		start.position = Vector2(480, 3)
		start.size = Vector2(148, 18)

	_set_tab(tab if tab_buttons.has(tab) else "outfit")


func _set_tab(t: String) -> void:
	tab = t
	tab_buttons[t].button_pressed = true
	selected = ""
	if t == "upgrades":
		selected = Upgrades.DEFS[0].id
	else:
		# Start on what you're wearing.
		selected = Profile.look().get(t, "")
	_rebuild()


func _rebuild() -> void:
	balance.text = "%d Liquid Gold" % Profile.liquid_gold()
	for c in grid.get_children():
		c.queue_free()
	if tab == "upgrades":
		grid.columns = 1
		for d in Upgrades.DEFS:
			grid.add_child(_upgrade_card(d))
	else:
		grid.columns = 3
		for o in Cosmetics.CATEGORIES[tab]:
			grid.add_child(_cosmetic_card(o))
	_show_detail()


# --- Cards -------------------------------------------------------------------------------------

func _card_button(id: String, size: Vector2) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = size
	b.clip_contents = true
	b.button_pressed = id == selected
	b.pressed.connect(func():
		Sfx.play("click")
		selected = id
		_show_detail())
	return b


func _cosmetic_card(o: Dictionary) -> Button:
	var id: String = o.id
	var b := _card_button(id, CARD)
	var v := UiKit.vbox(1)
	v.position = Vector2(4, 3)
	v.size = CARD - Vector2(8, 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(76, 26)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon)
	if tab in HEAD_TABS:
		var look := Profile.look()
		look[tab] = id
		var head := CharacterView.new()
		head.setup(look, true)
		head.position = Vector2(26, 1)
		icon.add_child(head)
	elif tab in HOME_TABS:
		# The building itself (siding and roof colors shown on your house).
		var look := Profile.look()
		look[tab] = id
		var kind := "outbuilding" if tab == "outbuilding" else "house"
		var bv := BuildingView.new().setup(look, kind, 2 if kind == "outbuilding" else 1)
		bv.size = bv.custom_minimum_size
		bv.position = Vector2((76 - bv.size.x) / 2.0, 26 - bv.size.y)
		icon.add_child(bv)
	else:
		var sw := ColorRect.new()
		sw.color = INK
		sw.position = Vector2(20, 4)
		sw.size = Vector2(36, 18)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(sw)
		var fill := ColorRect.new()
		fill.color = _swatch_color(o)
		fill.position = Vector2(1, 1)
		fill.size = Vector2(34, 16)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(fill)
	var n := UiKit.label(o.name, 8)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_vertical = Control.SIZE_EXPAND_FILL
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.custom_minimum_size = Vector2(76, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var st := _status(id)
	var s := UiKit.label(st[0], 8, st[1])
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(76, 0)
	v.add_child(s)
	return b


## Paint tints a wood-colored derrick, so show the tinted wood, not the raw tint.
func _swatch_color(o: Dictionary) -> Color:
	return Color(0.78, 0.62, 0.42) * (o.color as Color) if tab == "paint" else o.color


func _upgrade_card(d: Dictionary) -> Button:
	var id: String = d.id
	var b := _card_button(id, Vector2(352, 50))
	var h := UiKit.hbox(8)
	h.position = Vector2(6, 4)
	h.size = Vector2(340, 42)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var lv := Profile.upgrade_level(id)
	var info := UiKit.vbox(1)
	info.custom_minimum_size = Vector2(250, 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(info)
	info.add_child(UiKit.label(d.name, 10))
	var desc := UiKit.label(d.desc, 8, Color("5a4632"))
	desc.clip_text = true
	desc.custom_minimum_size = Vector2(250, 0)
	info.add_child(desc)
	var right := UiKit.vbox(1)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	var pips := ""
	for i in d.costs.size():
		pips += "#" if i < lv else "-"
	right.add_child(UiKit.label("[%s]" % pips, 8, GOLD_TXT))
	var cost := Upgrades.next_cost(id, lv)
	right.add_child(UiKit.label("Maxed" if cost < 0 else "%d LG" % cost, 8,
		OWNED if cost < 0 else (GOLD_TXT if cost <= Profile.liquid_gold() else SHORT)))
	return b


## [text, color] for a cosmetic's card: Wearing / Owned / price.
func _status(id: String) -> Array:
	if Profile.look().get(tab, "") == id:
		return ["In use" if tab in USE_TABS else "Wearing", Color("493016")]
	if Profile.is_unlocked(id):
		return ["Owned", OWNED]
	var price := Cosmetics.price_of(id)
	return ["%d LG" % price, GOLD_TXT if price <= Profile.liquid_gold() else SHORT]


# --- Detail column -----------------------------------------------------------------------------

func _show_detail() -> void:
	var look := Profile.look()
	if tab == "upgrades":
		_show_upgrade()
	else:
		look[tab] = selected
		_show_cosmetic()
	var homestead := tab in HOME_TABS
	body.visible = not homestead
	body.setup(look, false)
	body.play("cheer" if tab != "upgrades" else "idle")
	var paint: Color = Cosmetics.find("paint", look.paint).color
	for d in derricks:
		d.visible = not homestead
		d.modulate = Color(0.78, 0.62, 0.42) * paint
	house.visible = homestead
	house.setup(look, "house", 3)
	for b in sheds:
		b.visible = homestead
		b.setup(look, "outbuilding", 3)


func _show_cosmetic() -> void:
	var o := Cosmetics.find(tab, selected)
	item_name.text = o.get("name", "")
	wear_btn.visible = true
	var owned := Profile.is_unlocked(selected)
	var wearing: bool = Profile.look().get(tab, "") == selected
	var price := Cosmetics.price_of(selected)
	var lg := Profile.liquid_gold()
	if wearing:
		item_status.text = "You're using it." if tab in USE_TABS else "You're wearing it."
	elif owned:
		item_status.text = "You own this."
	elif price <= lg:
		item_status.text = "%d Liquid Gold" % price
	else:
		item_status.text = "%d Liquid Gold (need %d more)" % [price, price - lg]
	item_status.add_theme_color_override("font_color", SHORT if not owned and price > lg else GOLD_TXT)
	var notes: Array[String] = []
	notes.append(_use_note())
	var reward := _campaign_reward(selected)
	if reward != "" and not owned:
		notes.append("Also free for winning %s." % reward)
	elif price > 0 and reward == "":
		notes.append("Only sold here.")
	if creating:
		notes.push_front("Texas, 1938: tell folks who you are.")
	item_desc.text = " ".join(notes)
	var home := tab in USE_TABS
	buy_btn.text = "Owned" if owned else ("Buy & Use" if home else "Buy & Wear")
	buy_btn.disabled = owned or price > lg
	wear_btn.text = ("In use" if wearing else "Use") if home else ("Wearing" if wearing else "Wear")
	wear_btn.disabled = wearing or not owned


func _use_note() -> String:
	match tab:
		"tycoon": return "Your tycoon on the board, the player list and the campaign map."
		"skin": return "Your tycoon's skin tone."
		"paint": return "Paints your derricks and drill rig."
		"house": return "Your house stands on the first property you buy in every match."
		"outbuilding": return "One stands on every property you buy after your first."
		"siding": return "Wall color for your house and outbuildings."
		"roof": return "Roof color for your house and outbuildings."
	return "Shown in the preview on your tycoon."


func _show_upgrade() -> void:
	var d := Upgrades.get_def(selected)
	var lv := Profile.upgrade_level(selected)
	var cost := Upgrades.next_cost(selected, lv)
	item_name.text = d.name
	wear_btn.visible = false
	item_status.text = "Level %d of %d" % [lv, d.costs.size()]
	item_status.add_theme_color_override("font_color", GOLD_TXT)
	var now := _effect(d, lv)
	var nxt := _effect(d, lv + 1) if cost >= 0 else ""
	item_desc.text = "%s\nNow: %s%s\nCampaign only: Classic and online matches use base stats." % [
		d.desc, now, ("\nNext: " + nxt) if nxt != "" else ""]
	buy_btn.text = "Maxed" if cost < 0 else "Buy level %d (%d)" % [lv + 1, cost]
	buy_btn.disabled = cost < 0 or cost > Profile.liquid_gold()


func _effect(d: Dictionary, lv: int) -> String:
	if lv <= 0:
		return "no bonus"
	var v: float = lv * float(d.per_level)
	match d.mod:
		"yield", "royalty":
			return "+%d%%" % roundi(v * 100)
		"drill_discount":
			return "-%d%% drilling cost" % roundi(v * 100)
		"fire_resist":
			return "%d%% chance to save a well" % roundi(v * 100)
		"start_bonus":
			return "+%s starting cash" % UiKit.money(int(v))
	return str(v)


func _campaign_reward(id: String) -> String:
	for i in Session.campaign.maps.size():
		if id in Session.campaign.maps[i].get("unlocks", []):
			return "campaign map %d (%s)" % [i + 1, Session.campaign.maps[i].title]
	return ""


# --- Buying ------------------------------------------------------------------------------------

func _buy() -> void:
	var ok := false
	if tab == "upgrades":
		ok = Profile.buy_upgrade(selected)
	else:
		ok = Profile.buy_cosmetic(selected)
		if ok:
			Profile.set_look(tab, selected)
	if ok:
		Sfx.play("cash")
	_rebuild()


func _wear() -> void:
	Profile.set_look(tab, selected)
	_rebuild()


## A random look from the options you own.
func _randomize() -> void:
	for cat in Cosmetics.CATEGORIES:
		var opts: Array = Cosmetics.CATEGORIES[cat].filter(func(o): return Profile.is_unlocked(o.id))
		if not opts.is_empty():
			Profile.data.look[cat] = opts[rng.randi_range(0, opts.size() - 1)].id
	Profile.save()
	Sfx.play("click")
	selected = Profile.look().get(tab, selected) if tab != "upgrades" else selected
	_rebuild()


## Character creation done: on to the campaign.
func _finish() -> void:
	var n := name_edit.text.strip_edges()
	Profile.data.name = n if n != "" else "Player"
	Profile.data.character_created = true
	Profile.save()
	Session.goto("campaign")
