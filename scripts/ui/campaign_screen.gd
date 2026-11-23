extends Control
## Campaign world map. Your tycoon stands on a map spot and walks the trail spot to spot
## (arrow keys / A-D, or click a spot). Locked spots block the trail. The briefing panel on
## the right shows the spot you're standing on; Enter or Play starts it.
## Spot positions live in data/campaign.json ("pos").

const PANEL_X: float = 356.0
const SIGN_BG := Color("2b1d14")
const SIGN_TEXT := Color("f4ecd8")
const WALK_TIME: float = 0.22

var maps: Array = []
var current: int = 0
var walking: bool = false
var hover: int = -1

var trail: Node2D
var token: CharacterView
var panel_box: VBoxContainer
var play_box: VBoxContainer
var hover_label: Label
var hover_sign: PanelContainer
var lg_label: Label


func _ready() -> void:
	# First visit: make your tycoon before the first lease.
	if not Profile.character_created():
		Session.customize_mode = "create"
		Session.open_shop("tycoon", "campaign")
		return
	maps = Session.campaign.maps
	# Spot clicks are read in _unhandled_input, so the full-screen root must not eat them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	current = clampi(int(Profile.data.get("campaign_pos", _furthest_unlocked())), 0, maps.size() - 1)
	if not Profile.map_unlocked(current):
		current = _furthest_unlocked()

	var bg := TextureRect.new()
	bg.texture = UiKit.tex("res://assets/ui/campaign_map.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.position = Vector2(0, 24)
	bg.size = Vector2(PANEL_X, 336)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var backing := ColorRect.new()
	backing.position.x = PANEL_X
	backing.size = Vector2(640 - PANEL_X, 360)
	backing.color = UiKit.NIGHT
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)

	trail = Node2D.new()
	trail.draw.connect(_draw_trail)
	add_child(trail)

	token = CharacterView.new()
	token.setup(Profile.look(), false)
	token.scale = Vector2(0.5, 0.5)
	add_child(token)
	_place_token(_spot(current))

	hover_sign = _sign("")
	hover_label = hover_sign.get_child(0)
	hover_sign.visible = false
	add_child(hover_sign)

	_build_top_bar()
	var pnl := UiKit.panel(8)
	pnl.position = Vector2(PANEL_X, 28)
	pnl.custom_minimum_size = Vector2(640 - PANEL_X - 6, 360 - 28 - 6)
	pnl.size = pnl.custom_minimum_size
	pnl.clip_contents = true
	add_child(pnl)
	# Details scroll if they don't fit; the Play button below them always stays visible.
	var outer := UiKit.vbox(6)
	pnl.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	panel_box = UiKit.vbox(4)
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_box)
	play_box = UiKit.vbox(4)
	outer.add_child(play_box)
	_show_briefing()


func _build_top_bar() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.11, 0.08, 0.06, 0.85)
	bar.size = Vector2(640, 24)
	add_child(bar)
	# One row across the whole bar; a spacer pushes Liquid Gold + Upgrades to the right edge.
	var row := UiKit.hbox(8)
	row.position = Vector2(6, 2)
	row.size = Vector2(640 - 12, 20)
	add_child(row)
	row.add_child(UiKit.button("< Back", func(): Session.goto("menu")))
	row.add_child(UiKit.label("Campaign", UiKit.FONT_TITLE, UiKit.PAPER))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var drop := TextureRect.new()
	drop.texture = UiKit.tex("res://assets/ui/icon_liquid_gold.png")
	drop.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	drop.custom_minimum_size = Vector2(16, 18)
	row.add_child(drop)
	lg_label = UiKit.label("%d Liquid Gold" % Profile.liquid_gold(), 10, UiKit.GOLD)
	row.add_child(lg_label)
	row.add_child(UiKit.button("Shop", func(): Session.open_shop("upgrades", "campaign"), 8))


## A dark wooden sign with light text: high contrast over any map art.
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
	var l := UiKit.label(text, 8, SIGN_TEXT)
	sign.add_child(l)
	return sign


func _spot(i: int) -> Vector2:
	var pos: Array = maps[i].get("pos", [40 + i * 15, 300])
	return Vector2(float(pos[0]), float(pos[1]))


func _furthest_unlocked() -> int:
	var best := 0
	for i in maps.size():
		if Profile.map_unlocked(i):
			best = i
	return best


func _place_token(at: Vector2) -> void:
	token.position = (at - Vector2(8, 20)).round()


# The same bend drives the road paint and the travelling tycoon's footsteps.
func _road_point(index: int, progress: float) -> Vector2:
	var a := _spot(index)
	var b := _spot(index + 1)
	var normal := a.direction_to(b).orthogonal()
	var bend := sin(progress * PI) * minf(8, a.distance_to(b) * 0.12)
	return a.lerp(b, progress) + normal * bend * (1 if index % 2 == 0 else -1)


func _draw_trail() -> void:
	for i in maps.size() - 1:
		var points := PackedVector2Array()
		for step in 13:
			points.append(_road_point(i, step / 12.0).round())
		var open := Profile.map_unlocked(i + 1)
		trail.draw_polyline(points, Color("664a30"), 6)
		trail.draw_polyline(points, Color("e5bf85") if open else Color("ad946c"), 4)
		trail.draw_polyline(points, Color("f7d79d") if open else Color("cfb88e"), 1)
		# Timber crossing over the bayou on the approach to The Big Board.
		if maps[i].get("title") == "Hurricane Season":
			for step in range(4, 10):
				var at := points[step]
				var rail := at.direction_to(points[step + 1]).orthogonal() * 3
				trail.draw_line(at - rail, at + rail, Color("816145"), 2)
				for side in [-1, 1]:
					trail.draw_line(at + rail * side, points[step + 1] + rail * side, UiKit.INK, 1)
	for i in maps.size():
		_draw_town(i)


const TOWN_HOUSES := ["cabin", "farmhouse", "ranch", "adobe", "victorian", "mansion"]
const TOWN_SHEDS := ["windmill", "barn", "shed", "bunkhouse", "silo", "office"]
const ROOFS := [Color("ac5040"), Color("638180"), Color("cb854b"), Color("647e50")]


func _draw_town(i: int) -> void:
	var p := _spot(i)
	var open := Profile.map_unlocked(i)
	var house_index := 5 if i == maps.size() - 1 else i % 5
	var roof: Color = ROOFS[i % ROOFS.size()]
	var light := Color.WHITE if open else Color("aaa69d")
	var pad := PackedVector2Array([p + Vector2(-17, -3), p + Vector2(-10, -9),
		p + Vector2(12, -9), p + Vector2(18, -4), p + Vector2(12, 1), p + Vector2(-12, 1)])
	trail.draw_colored_polygon(pad, Color("c4a472"))
	if i in [0, 3, 10, 13, 19]:
		trail.draw_texture(preload("res://assets/sprites/derrick.png"), p + Vector2(4, -20), light)
	_town_building(p + Vector2(-5, -4), "house", TOWN_HOUSES[house_index], roof, light)
	_town_building(p + Vector2(9, -2), "outbuilding", TOWN_SHEDS[i % 6], roof, light)
	if open:
		var flag_at := p + Vector2(13, -6)
		trail.draw_rect(Rect2(flag_at - Vector2(0, 11), Vector2(1, 12)), UiKit.INK)
		var pennant := PackedVector2Array([flag_at + Vector2(1, -11),
			flag_at + Vector2(8, -9), flag_at + Vector2(1, -6)])
		trail.draw_colored_polygon(pennant, Color("1c634e") if Profile.map_done(i) else UiKit.GOLD)
	else:
		# A timber barrier across the entrance to a future lease.
		trail.draw_rect(Rect2(p + Vector2(-4, -3), Vector2(1, 5)), UiKit.INK)
		trail.draw_rect(Rect2(p + Vector2(4, -3), Vector2(1, 5)), UiKit.INK)
		trail.draw_rect(Rect2(p + Vector2(-5, -3), Vector2(11, 2)), Color("76523a"))
		for x in [-4, 0, 4]:
			trail.draw_rect(Rect2(p + Vector2(x, -3), Vector2(2, 2)), UiKit.PAPER)
	if hover == i or (i == current and not walking):
		var edge := Color.WHITE if hover == i else UiKit.GOLD
		for side in [-1, 1]:
			var corner := p + Vector2(side * 17, 2)
			trail.draw_line(corner, corner + Vector2(-side * 5, 0), edge, 2)
			trail.draw_line(corner, corner + Vector2(0, -4), edge, 2)


func _town_building(at: Vector2, kind: String, style: String, roof: Color, light: Color) -> void:
	var texture := Homestead.texture(kind, style)
	if texture == null:
		return
	var sz: Vector2 = Homestead.SIZE[kind]
	var dest := Rect2(at - Vector2(sz.x / 2, sz.y), sz)
	var colors := [Color("f2d5a0"), roof, Color.WHITE]
	for layer in 3:
		trail.draw_texture_rect_region(texture, dest, Rect2(Vector2(layer * sz.x, 0), sz), colors[layer] * light)


# --- Briefing panel ------------------------------------------------------------------

func _chapter_of(i: int) -> Dictionary:
	for ch in Session.campaign.chapters:
		# JSON numbers load as floats, so compare as ints.
		for mi in ch.maps:
			if int(mi) == i:
				return ch
	return {"title": ""}


func _show_briefing() -> void:
	for c in panel_box.get_children():
		c.queue_free()
	for c in play_box.get_children():
		c.queue_free()
	var i := current
	var m: Dictionary = maps[i]
	var w := 640 - PANEL_X - 6 - 16 - 8
	var muted := Color("5a4632")

	panel_box.add_child(UiKit.label(_chapter_of(i).title.to_upper(), 8, Color("8a2e1a")))
	var title := UiKit.label("%d. %s" % [i + 1, m.title], UiKit.FONT_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(w, 0)
	panel_box.add_child(title)
	panel_box.add_child(_rule(w))

	var intro := UiKit.label(m.intro, 10)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(w, 0)
	panel_box.add_child(intro)

	# One line: players and pace on the left, Liquid Gold reward on the right.
	var speed := MatchSpeed.load_by_id(m.speed)
	var facts := UiKit.hbox(4)
	var info := UiKit.label("%d players, %s pace" % [m.rivals.size() + 1, speed.display_name], 8, muted)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_child(info)
	var drop := TextureRect.new()
	drop.texture = UiKit.tex("res://assets/ui/icon_liquid_gold.png")
	drop.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	drop.tooltip_text = "Liquid Gold reward" + (" (half on replay)" if Profile.map_done(i) else "")
	facts.add_child(drop)
	facts.add_child(UiKit.label("%d%s" % [int(m.reward), " (1/2)" if Profile.map_done(i) else ""], 8, Color("7a5a10")))
	panel_box.add_child(facts)
	panel_box.add_child(_rule(w))

	if m.rivals.size() == 1:
		var rival: Dictionary = Session.campaign.rivals[m.rivals[0]]
		var row := UiKit.hbox(8)
		row.add_child(_portrait(rival.look, 2))
		var col := UiKit.vbox(4)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nm := UiKit.label(rival.name, 8)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(w - 60, 0)
		col.add_child(nm)
		col.add_child(_stars(int(m.ai_levels[0])))
		row.add_child(col)
		panel_box.add_child(row)
	else:
		# Several rivals side by side: portrait, stars, short name in each column.
		var zoom := 2 if m.rivals.size() <= 3 else 1
		var faces := HFlowContainer.new()
		faces.add_theme_constant_override("h_separation", 8)
		faces.add_theme_constant_override("v_separation", 6)
		faces.custom_minimum_size = Vector2(w, 0)
		for r in m.rivals.size():
			var rival: Dictionary = Session.campaign.rivals[m.rivals[r]]
			var col := UiKit.vbox(3)
			col.add_child(_portrait(rival.look, zoom))
			col.add_child(_stars(int(m.ai_levels[r]), zoom))
			var nm := UiKit.label(rival.get("short", rival.name), 8)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(nm)
			faces.add_child(col)
		panel_box.add_child(faces)
	if m.unlocks.size() > 0 and not Profile.map_done(i):
		var u := UiKit.label("Win to unlock: " + ", ".join(m.unlocks.map(func(id): return Cosmetics.name_of(id))), 8, UiKit.GREEN)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.custom_minimum_size = Vector2(w, 0)
		panel_box.add_child(u)
	var play := UiKit.button("Play" if not Profile.map_done(i) else "Replay", _play, 16)
	play.custom_minimum_size = Vector2(0, 26)
	play.focus_mode = Control.FOCUS_NONE
	play_box.add_child(play)
	var hint := UiKit.label("Arrow keys: travel    Enter: play", 8, Color("6a5640"))
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


func _play() -> void:
	if walking or not Profile.map_unlocked(current):
		return
	Session.start_offline(Session.campaign_config(current), current)


# --- Travel ----------------------------------------------------------------------

func _walk_to(target: int) -> void:
	if walking or target == current or target < 0 or target >= maps.size():
		return
	if not Profile.map_unlocked(target):
		_flash_locked(target)
		return
	walking = true
	trail.queue_redraw()
	token.play("walk")
	var dir := 1 if target > current else -1
	while current != target:
		var nxt := current + dir
		var tw := create_tween()
		var segment := mini(current, nxt)
		token.face_left(_spot(nxt).x < _spot(current).x)
		tw.tween_method(func(t: float): _place_token(_road_point(segment, t)),
			0.0 if dir > 0 else 1.0, 1.0 if dir > 0 else 0.0, WALK_TIME)
		await tw.finished
		current = nxt
	walking = false
	token.face_left(false)
	trail.queue_redraw()
	token.play("cheer", 0.6)
	Profile.data["campaign_pos"] = current
	Profile.save()
	_show_briefing()


func _flash_locked(i: int) -> void:
	hover_label.text = "Locked: win map %d first" % i
	hover_sign.reset_size()
	var w := hover_sign.get_combined_minimum_size().x
	hover_sign.position = Vector2(clampf(_spot(i).x - w / 2, 2, PANEL_X - w - 4), maxf(26, _spot(i).y - 40))
	hover_sign.visible = true


func _spot_at(p: Vector2) -> int:
	for i in maps.size():
		if Rect2(_spot(i) - Vector2(17, 24), Vector2(36, 31)).has_point(p):
			return i
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if maps.is_empty():
		return # redirected to character creation
	if event is InputEventMouseMotion:
		var h := _spot_at((make_input_local(event) as InputEventMouse).position)
		if h != hover:
			hover = h
			trail.queue_redraw()
			if h >= 0:
				hover_label.text = ("%d. %s" % [h + 1, maps[h].title]) if Profile.map_unlocked(h) else "%d. Locked" % (h + 1)
				hover_sign.reset_size()
				var w := hover_sign.get_combined_minimum_size().x
				hover_sign.position = Vector2(clampf(_spot(h).x - w / 2, 2, PANEL_X - w - 4), maxf(26, _spot(h).y - 70))
				hover_sign.visible = true
			else:
				hover_sign.visible = false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := _spot_at((make_input_local(event) as InputEventMouse).position)
		if s >= 0:
			if s == current:
				_play()
			else:
				_walk_to(s)



func _input(event: InputEvent) -> void:
	if maps.is_empty():
		return # redirected to character creation
	# Keys are read before the GUI so focused buttons don't swallow the arrow keys.
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		match event.keycode:
			KEY_RIGHT, KEY_D, KEY_UP, KEY_W:
				_walk_to(current + 1)
			KEY_LEFT, KEY_A, KEY_DOWN, KEY_S:
				_walk_to(current - 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_play()
			KEY_ESCAPE:
				Session.goto("menu")
