extends Control
## Campaign county map: a raised Texas cut into counties (CountyMap). Claimed counties take their
## owner's color, open ones are grey. Click a county for its briefing on the right; counties next
## to yours can be fought for (Fight button, Enter, or click it again). Rules: CampaignWar.

const PANEL_X: float = 356.0
const TOP_H: float = 24.0
const SIGN_BG := Color("2b1d14")
const SIGN_TEXT := Color("f4ecd8")
const SURVEY_TERRAIN := preload("res://assets/ui/campaign_map.png")
const ATLAS_SHEET := preload("res://assets/ui/campaign_atlas.png")
const CLIFF_TOP := Color("8a6440")
const CLIFF_BOTTOM := Color("4a321f")
const OPEN_COLOR := Color("9a958b")
const RAISE: int = 7
## Rival HQ house styles, in CampaignWar.RIVALS order.
const HQ_HOUSES: Array[String] = ["house_cabin", "house_ranch", "house_victorian", "house_adobe", "house_mansion"]

var war: CampaignWar
var map: CountyMap
var selected: int = -1
var hover: int = -1
var _t: float = 0.0

var county_uvs: Array[PackedVector2Array] = []
var map_layer: Node2D
var token: CharacterView
var roster_box: VBoxContainer
var panel_box: VBoxContainer
var play_box: VBoxContainer
var hover_label: Label
var hover_sign: PanelContainer
var dollar_label: Label
var lg_label: Label
var popup: Control


func _ready() -> void:
	# First visit: make your tycoon before the first battle.
	if not Profile.character_created():
		Session.customize_mode = "create"
		Session.open_shop("tycoon", "campaign")
		return
	war = Profile.war()
	map = war.map
	for polygon in map.polys:
		var uvs := PackedVector2Array()
		for vertex in polygon:
			uvs.append((vertex - Vector2(0, TOP_H)) / SURVEY_TERRAIN.get_size())
		county_uvs.append(uvs)
	Profile.save() # keeps a brand-new war
	# County clicks are read in _unhandled_input, so the full-screen root must not eat them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backing := ColorRect.new()
	backing.size = Vector2(640, 360)
	backing.color = UiKit.NIGHT
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)
	map_layer = Node2D.new()
	map_layer.draw.connect(_draw_map)
	add_child(map_layer)

	token = CharacterView.new()
	token.setup(Profile.look(), false)
	token.scale = Vector2(0.5, 0.5)
	var home := map.centers[war.home(0)]
	token.position = (home - Vector2(8, 22)).round()
	add_child(token)

	hover_sign = _sign("")
	hover_label = hover_sign.get_child(0)
	hover_sign.visible = false
	add_child(hover_sign)

	_build_top_bar()
	var pnl := UiKit.panel(8)
	pnl.position = Vector2(PANEL_X, TOP_H + 4)
	pnl.custom_minimum_size = Vector2(640 - PANEL_X - 6, 360 - TOP_H - 4 - 6)
	pnl.size = pnl.custom_minimum_size
	pnl.clip_contents = true
	add_child(pnl)
	var outer := UiKit.vbox(4)
	pnl.add_child(outer)
	roster_box = UiKit.vbox(1)
	outer.add_child(roster_box)
	outer.add_child(_rule(_panel_w()))
	# The briefing scrolls if it doesn't fit; the Fight button below it always stays visible.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	panel_box = UiKit.vbox(4)
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_box)
	play_box = UiKit.vbox(3)
	outer.add_child(play_box)

	selected = _first_target()
	_refresh()
	if war.finished():
		_show_victory()


func _process(delta: float) -> void:
	_t += delta
	if map_layer:
		map_layer.queue_redraw()


func _panel_w() -> float:
	return 640 - PANEL_X - 6 - 16 - 8


## Where to point the player first: the next story level next to their land, else any target.
func _first_target() -> int:
	var best := -1
	for c in map.count():
		if not war.attackable(c):
			continue
		var lv := war.level_of[c]
		var best_lv := war.level_of[best] if best >= 0 else -1
		if best < 0 or (lv >= 0 and (best_lv < 0 or lv < best_lv)):
			best = c
	return best if best >= 0 else war.home(0)


func _refresh() -> void:
	dollar_label.text = UiKit.dollar_text(war.dollars)
	lg_label.text = "%d" % Profile.liquid_gold()
	_show_roster()
	_show_briefing()


# --- Top bar -------------------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.11, 0.08, 0.06, 0.95)
	bar.size = Vector2(640, TOP_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var row := UiKit.hbox(6)
	row.position = Vector2(6, 2)
	row.size = Vector2(640 - 12, 20)
	add_child(row)
	row.add_child(UiKit.button("< Back", func(): Session.goto("menu")))
	row.add_child(UiKit.label("Campaign", UiKit.FONT_TITLE, UiKit.PAPER))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var dsign := UiKit.dollar_icon()
	dsign.tooltip_text = "Campaign dollars: won from rivals, spent on upgrades"
	dsign.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(dsign)
	dollar_label = UiKit.label("", 10, UiKit.GOLD)
	dollar_label.tooltip_text = dsign.tooltip_text
	dollar_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(dollar_label)
	var drop := TextureRect.new()
	drop.texture = UiKit.tex("res://assets/ui/icon_liquid_gold.png")
	drop.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	drop.custom_minimum_size = Vector2(16, 18)
	drop.tooltip_text = "Liquid Gold: buys looks in the store"
	row.add_child(drop)
	lg_label = UiKit.label("", 10, UiKit.GOLD)
	row.add_child(lg_label)
	row.add_child(UiKit.button("Upgrades", func(): Session.open_shop("upgrades", "campaign"), 8))
	var restart := UiKit.button("New Campaign", _confirm_restart, 8)
	restart.focus_mode = Control.FOCUS_NONE
	row.add_child(restart)


## A dark wooden sign with light text: high contrast over the map.
func _sign(text: String) -> PanelContainer:
	var sign := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SIGN_BG
	sb.border_color = Color("b8893a")
	sb.set_border_width_all(1)
	sb.content_margin_left = 5 + UiKit.PAD_X
	sb.content_margin_right = 5 + UiKit.PAD_X
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	sign.add_theme_stylebox_override("panel", sb)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(UiKit.label(text, 8, SIGN_TEXT))
	return sign


# --- Map drawing ---------------------------------------------------------------------------------

func _company_color(company: int) -> Color:
	if company < 0:
		return OPEN_COLOR
	return GameConst.PLAYER_COLORS[company % GameConst.PLAYER_COLORS.size()]


func _fill(c: int) -> Color:
	var o := war.owner[c]
	if o < 0:
		return OPEN_COLOR
	return _company_color(o).lerp(Color("f4ecd8"), 0.12)


## Sampling in map coordinates keeps the terrain continuous across county lines and
## moves the same patch of ground with its county on hover.
func _draw_county(c: int, lifted: bool = false) -> void:
	var fill := _fill(c)
	map_layer.draw_colored_polygon(map.polys[c], fill.lightened(0.12) if lifted else fill)
	var coverage := 0.53 if war.owner[c] < 0 else 0.36
	map_layer.draw_colored_polygon(map.polys[c], Color(1, 1, 1, coverage), county_uvs[c], SURVEY_TERRAIN)


func _draw_map() -> void:
	var ci := map_layer
	ci.draw_texture(ATLAS_SHEET, Vector2(0, TOP_H))
	# The state stands up off the table: a shadow, then its edge in layers, then the counties.
	ci.draw_set_transform(Vector2(4, RAISE + 3))
	ci.draw_colored_polygon(map.outline, Color(0, 0, 0, 0.35))
	for k in range(RAISE, 0, -1):
		ci.draw_set_transform(Vector2(0, k))
		ci.draw_colored_polygon(map.outline, CLIFF_BOTTOM.lerp(CLIFF_TOP, 1.0 - float(k) / RAISE))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_colored_polygon(map.outline, OPEN_COLOR)
	for c in map.count():
		if c != hover:
			_draw_county(c)
	for c in map.count():
		if c != hover:
			_outline(map.polys[c], Color(0.11, 0.08, 0.06, 0.55), 1.0)
	_outline(map.outline, UiKit.INK, 1.5)
	# Counties you can fight for pulse.
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	for c in map.count():
		if war.attackable(c) and c != hover:
			_outline(_inset(map.polys[c], map.centers[c], 2.0), Color(1, 0.95, 0.75, 0.35 + 0.5 * pulse), 1.0)
	# The hovered county lifts up a little.
	if hover >= 0:
		var lift := Vector2(0, -3)
		ci.draw_colored_polygon(map.polys[hover], Color(0.1, 0.07, 0.05, 0.8))
		ci.draw_set_transform(lift)
		_draw_county(hover, true)
		_outline(map.polys[hover], UiKit.INK, 1.0)
		ci.draw_set_transform(Vector2.ZERO)
	if selected >= 0:
		var off := Vector2(0, -3) if selected == hover else Vector2.ZERO
		ci.draw_set_transform(off)
		_outline(map.polys[selected], UiKit.GOLD, 2.0)
		ci.draw_set_transform(Vector2.ZERO)
	_draw_markers()


func _draw_markers() -> void:
	var ci := map_layer
	for c in map.count():
		var at := map.centers[c] + (Vector2(0, -3) if c == hover else Vector2.ZERO)
		var hq := war.is_hq(c)
		if hq > 0:
			var look := Cosmetics.complete_look({"house": HQ_HOUSES[hq - 1]}, hq)
			var flag := _company_color(hq) if war.alive(hq) else Color(0, 0, 0, 0)
			Homestead.draw(ci, at + Vector2(0, 7), look, "house", 1.0, flag)
			if not war.alive(hq):
				# A knocked-out rival's HQ: boarded up.
				ci.draw_line(at + Vector2(-7, -9), at + Vector2(7, 5), UiKit.INK, 2)
				ci.draw_line(at + Vector2(7, -9), at + Vector2(-7, 5), UiKit.INK, 2)
		elif war.owner[c] == 0 and c != war.home(0):
			ci.draw_texture(preload("res://assets/sprites/derrick.png"), at - Vector2(4, 11))
		elif war.attackable(c):
			_swords(at)
		if war.level_of[c] >= 0 and war.owner[c] != 0 and hq == 0:
			# Story counties carry a gold star.
			ci.draw_texture(UiKit.tex("res://assets/ui/icon_star.png"), at + Vector2(4, -12))


## Two crossed pick handles: you can fight here.
func _swords(at: Vector2) -> void:
	var ci := map_layer
	for side in [-1, 1]:
		var a := at + Vector2(-4 * side, 4)
		var b := at + Vector2(4 * side, -4)
		ci.draw_line(a, b, UiKit.INK, 3)
		ci.draw_line(a, b, Color("f4ecd8"), 1)
		ci.draw_line(b + Vector2(-2 * side, 0), b + Vector2(0, 2), Color("f4ecd8"), 1)


func _outline(poly: PackedVector2Array, color: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	map_layer.draw_polyline(closed, color, width)


## A county's border pulled toward its center (for inner highlights).
func _inset(poly: PackedVector2Array, center: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (center - p).normalized() * by)
	return out


# --- Panel: rivals -------------------------------------------------------------------------------

func _show_roster() -> void:
	for c in roster_box.get_children():
		c.queue_free()
	var head := UiKit.hbox(4)
	head.add_child(UiKit.label("RIVALS", 8, Color("8a2e1a")))
	var left := UiKit.label("%d of %d left" % [war.alive_rivals().size(), CampaignWar.RIVALS.size()], 8, Color("6a5640"))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(left)
	roster_box.add_child(head)
	var w := _panel_w()
	for r in range(1, CampaignWar.RIVALS.size() + 1):
		var rival := Session.rival_def(r)
		var row := UiKit.hbox(4)
		var chip := ColorRect.new()
		chip.color = _company_color(r) if war.alive(r) else OPEN_COLOR
		chip.custom_minimum_size = Vector2(7, 7)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var nm := UiKit.label(str(rival.get("short", "")), 8, UiKit.INK if war.alive(r) else Color("8a7a66"))
		nm.custom_minimum_size.x = w * 0.36
		nm.clip_text = true
		row.add_child(nm)
		if war.alive(r):
			# Purse bar: how close they are to going broke.
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(w * 0.22, 4)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var frac := clampf(float(war.purse[r - 1]) / CampaignWar.PURSE[r - 1], 0.0, 1.0)
			bar.draw.connect(func():
				bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color("c9b48a"))
				bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * frac, bar.size.y)), Color("2f5d3a"))
				bar.draw_rect(Rect2(Vector2.ZERO, bar.size), UiKit.INK, false, 1.0))
			row.add_child(bar)
			var amt := UiKit.dollar_amount(war.purse[r - 1], 8)
			amt.custom_minimum_size.x = w * 0.24
			row.add_child(amt)
			var land := UiKit.label("%d" % war.counties_of(r).size(), 8, Color("5a4632"))
			land.tooltip_text = "Counties held"
			land.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(land)
		else:
			row.add_child(UiKit.label("BROKE - out", 8, Color("8a2e1a")))
		roster_box.add_child(row)


# --- Panel: county briefing ----------------------------------------------------------------------

func _show_briefing() -> void:
	for c in panel_box.get_children():
		c.queue_free()
	for c in play_box.get_children():
		c.queue_free()
	if selected < 0:
		return
	var c := selected
	var w := _panel_w()
	var muted := Color("5a4632")
	var d := Session.battle_def(c)
	var owner := war.owner[c]
	var owner_text := "Open range" if owner < 0 else ("Your land" if owner == 0 else "%s's land" % Session.rival_def(owner).get("short", ""))
	if war.is_hq(c) > 0 and war.alive(war.is_hq(c)):
		owner_text = "%s's HQ" % Session.rival_def(war.is_hq(c)).get("short", "")
	elif c == war.home(0):
		owner_text = "Your home county"

	var head := UiKit.hbox(4)
	var chip := ColorRect.new()
	chip.color = _company_color(owner)
	chip.custom_minimum_size = Vector2(7, 7)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chip)
	var where := UiKit.label(("%s County - %s" % [map.names[c], owner_text]).to_upper(), 8, Color("8a2e1a"))
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.custom_minimum_size = Vector2(w - 12, 0)
	head.add_child(where)
	panel_box.add_child(head)
	var title := UiKit.label(d.title, UiKit.FONT_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(w, 0)
	panel_box.add_child(title)

	if owner == 0:
		var mine := UiKit.label("This county is yours. Fight for the counties next to your land to push out.", 8, muted)
		mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mine.custom_minimum_size = Vector2(w, 0)
		panel_box.add_child(mine)
		_add_fight_button(c)
		return
	var intro := UiKit.label(d.intro, 8)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(w, 0)
	panel_box.add_child(intro)
	var facts := UiKit.hbox(3)
	facts.add_child(UiKit.label("Worth", 8, muted))
	facts.add_child(UiKit.dollar_amount(war.value[c], 8, muted))
	panel_box.add_child(facts)
	var speed := MatchSpeed.load_by_id(d.speed)
	panel_box.add_child(UiKit.label("%d players, %s pace" % [(d.rivals as Array).size() + 1, speed.display_name], 8, muted))
	panel_box.add_child(_rule(w))
	if (d.rivals as Array).is_empty():
		return
	# Who you face here: portrait, difficulty, name.
	var faces := HFlowContainer.new()
	faces.add_theme_constant_override("h_separation", 8)
	faces.add_theme_constant_override("v_separation", 4)
	faces.custom_minimum_size = Vector2(w, 0)
	for k in (d.rivals as Array).size():
		var r: int = d.rivals[k]
		var rival := Session.rival_def(r)
		var col := UiKit.vbox(2)
		col.add_child(_portrait(Cosmetics.complete_look(rival.look, hash(CampaignWar.RIVALS[r - 1])), 2))
		col.add_child(_stars(int(d.ai_levels[k]), 2))
		var nm := UiKit.label(rival.get("short", ""), 8)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		faces.add_child(col)
	panel_box.add_child(faces)
	# What's at stake.
	var gain := 0
	for p in war.win_payments(c):
		gain += int(p.amount)
	var cost := 0
	for p in war.loss_payments(c):
		cost += int(p.amount)
	# The stakes sit by the Fight button, so they're always in view.
	var stakes := UiKit.hbox(3)
	stakes.alignment = BoxContainer.ALIGNMENT_CENTER
	stakes.add_child(UiKit.label("Win", 8, Color("2f5d3a")))
	stakes.add_child(UiKit.dollar_amount(gain, 8, Color("2f5d3a")))
	stakes.add_child(UiKit.label("   Lose", 8, Color("7a2a1a")))
	stakes.add_child(UiKit.dollar_amount(-cost, 8, Color("7a2a1a")))
	stakes.tooltip_text = "Win: the county, and the rivals you beat pay you. Lose: you pay them a fifth of your dollars."
	stakes.mouse_filter = Control.MOUSE_FILTER_PASS
	play_box.add_child(stakes)
	var unlocks: Array = d.unlocks
	if not unlocks.is_empty() and not Profile.map_done(int(d.level)):
		var u := UiKit.label("Win to unlock: " + ", ".join(unlocks.map(func(id): return Cosmetics.name_of(id))), 8, UiKit.GREEN)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.custom_minimum_size = Vector2(w, 0)
		panel_box.add_child(u)
	_add_fight_button(c)


func _add_fight_button(c: int) -> void:
	var ok := war.attackable(c)
	var label := "Fight!"
	if war.finished():
		label = "Texas is yours"
	elif war.owner[c] == 0:
		label = "Your county"
	elif not ok:
		label = "Out of reach"
	var fight := UiKit.button(label, _fight, 10)
	fight.tooltip_text = "Fight for %s County (Enter)" % map.names[c]
	fight.custom_minimum_size = Vector2(0, 22)
	fight.focus_mode = Control.FOCUS_NONE
	fight.disabled = not ok
	if not ok and war.owner[c] != 0 and not war.finished():
		fight.tooltip_text = "Win a county next to it first."
	play_box.add_child(fight)
	var hint := UiKit.label("Click a county to see it. Enter: fight", 8, Color("6a5640"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_box.add_child(hint)


func _rule(w: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.36, 0.25, 0.15, 0.5)
	r.custom_minimum_size = Vector2(w, 1)
	return r


## Animated head-and-shoulders portrait, at a whole-number scale (24 px art).
func _portrait(look: Dictionary, zoom: int = 1) -> Control:
	var holder := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("d9c9a3")
	sb.border_color = UiKit.INK
	sb.set_border_width_all(1)
	holder.add_theme_stylebox_override("panel", sb)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var area := Control.new()
	area.custom_minimum_size = Vector2(24, 24) * zoom
	area.clip_contents = true
	holder.add_child(area)
	var cv := CharacterView.new()
	cv.setup(look, true)
	cv.scale = Vector2(zoom, zoom)
	area.add_child(cv)
	return holder


## Difficulty as 1-3 stars (Easy, Medium, Hard).
func _stars(level: int, zoom: int = 2) -> HBoxContainer:
	var row := UiKit.hbox(1)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var full := UiKit.tex("res://assets/ui/icon_star.png")
	var empty := UiKit.tex("res://assets/ui/icon_star_empty.png")
	for k in 3:
		var t := TextureRect.new()
		t.texture = full if k <= level else empty
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.custom_minimum_size = Vector2(9, 9) * zoom
		t.tooltip_text = GameConst.AI_LEVEL_NAMES[level]
		row.add_child(t)
	return row


# --- Actions -------------------------------------------------------------------------------------

func _fight() -> void:
	if popup != null or selected < 0 or not war.attackable(selected):
		return
	Session.start_offline(Session.campaign_config(selected), selected)


func _select(c: int) -> void:
	if c == selected:
		return
	selected = c
	Sfx.play("click")
	_show_briefing()


func _confirm_restart() -> void:
	_popup("Start a new campaign? The map, your campaign dollars and your upgrades all start over. Liquid Gold and your looks stay.",
		"Start Over", func():
			Profile.new_campaign()
			Session.goto("campaign"))


func _show_victory() -> void:
	_popup("Every rival is broke and out. Texas is yours, %s!\nWon %d of %d battles." % [Profile.data.name, war.wins, war.battles],
		"New Campaign", func():
			Profile.new_campaign()
			Session.goto("campaign"), "Main Menu")


## A small dialog over the map: text, a confirm button and a cancel button.
func _popup(text: String, ok_text: String, on_ok: Callable, cancel_text: String = "Cancel") -> void:
	if popup != null:
		return
	popup = Control.new()
	popup.size = Vector2(640, 360)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(popup)
	var dim := ColorRect.new()
	dim.size = popup.size
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(dim)
	var center := CenterContainer.new()
	center.size = popup.size
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(center)
	var pnl := UiKit.panel(8)
	center.add_child(pnl)
	var v := UiKit.vbox(6)
	pnl.add_child(v)
	var l := UiKit.label(text, 10)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(260, 0)
	v.add_child(l)
	var row := UiKit.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button(cancel_text, func():
		if cancel_text == "Main Menu":
			Session.goto("menu")
		popup.queue_free()
		popup = null))
	row.add_child(UiKit.button(ok_text, on_ok))


# --- Input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if war == null or popup != null:
		return
	if event is InputEventMouseMotion:
		var p := (make_input_local(event) as InputEventMouse).position
		var h := map.county_at(p) if p.x < PANEL_X else -1
		if h != hover:
			hover = h
			if h >= 0:
				var o := war.owner[h]
				var who := "open" if o < 0 else ("yours" if o == 0 else str(Session.rival_def(o).get("short", "")))
				hover_label.text = "%s County (%s)" % [map.names[h], who]
				hover_sign.reset_size()
				var sw := hover_sign.get_combined_minimum_size().x
				var at := map.centers[h]
				hover_sign.position = Vector2(clampf(at.x - sw / 2, 2, PANEL_X - sw - 4), maxf(TOP_H + 2, at.y - 34))
				hover_sign.visible = true
			else:
				hover_sign.visible = false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := (make_input_local(event) as InputEventMouse).position
		if p.x >= PANEL_X:
			return
		var c := map.county_at(p)
		if c < 0:
			return
		if c == selected and war.attackable(c):
			_fight()
		else:
			_select(c)


func _input(event: InputEvent) -> void:
	if war == null:
		return # redirected to character creation
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				_fight()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				if popup != null:
					popup.queue_free()
					popup = null
				else:
					Session.goto("menu")
