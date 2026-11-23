class_name BoardView
extends Node2D
## Draws the oil field: ground, plots (tinted by owner), homestead buildings, drill sites,
## derricks, pipelines.
## Holds its own display copy of the state so animations can reveal changes one event at a time.

signal plot_clicked(plot: int)
signal site_clicked(site: int)
signal hovered(plot: int, site: int)

var board: BoardMap
var cell: int = 12
var players: Array = []
var plot_owner: Array = []
var site_state: Array = []
var pipelines: Array = []

var hover_plot: int = -1
var hover_site: int = -1
var selected_plot: int = -1
var highlight_sites: Array = []
var highlight_plots: Array = []
var show_prices: bool = false
## Ring color for highlighted sites (gold = drill here, red = fire: pick a well to cap).
var highlight_color: Color = Color("f2c14e")
## Land is for sale this turn (not the draft): plots get pulsing outlines and FOR SALE tags.
var sale_mode: bool = false
## Plots in a trade being made or answered, {plot: color}: tinted and outlined in that color.
var trade_marks: Dictionary = {}
var interactive: bool = true

var _t: float = 0.0
var _ground: Texture2D
const TITLE_LOGO := preload("res://assets/ui/title_logo.png")
## Decoration layout (see BoardDecor): field textures, roads/rails/creeks, props. Empty = tiled ground.
var decor: Dictionary = {}
## Hide the props (the map editor's guide view).
var show_props: bool = true
## Map editor hook: called after props are drawn (ghost previews, selection boxes).
var overlay_draw: Callable
## Draw the homestead (house on each player's first plot, outbuildings on the rest).
var show_buildings: bool = true
var _derrick: Texture2D
## Building spots per "plot:kind" (see Homestead.spot), and plots whose building is rising.
var _spots: Dictionary = {}
var _rising: Dictionary = {}
## Decoration props with the ones under buildings left out, rebuilt when ownership changes.
var _shown_props: Dictionary = {}
var _shown_key: String = "-"
var _dry: Texture2D
var _burned: Texture2D
var _font: Font


func setup(b: BoardMap, player_list: Array, max_size: Vector2) -> void:
	board = b
	players = player_list.duplicate(true)
	cell = maxi(6, mini(int(max_size.x / b.width), int(max_size.y / b.height)))
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground = UiKit.tex("res://assets/tilesets/ground_tile.png")
	_derrick = UiKit.tex("res://assets/sprites/derrick.png")
	_dry = UiKit.tex("res://assets/sprites/dry_cap.png")
	_burned = UiKit.tex("res://assets/sprites/burned_well.png")
	_font = UiKit.get_theme().default_font
	clear_building_spots()
	queue_redraw()


## Call after changing the board or its decoration under a live view.
func clear_building_spots() -> void:
	_spots.clear()
	_shown_key = "-"


func pixel_size() -> Vector2:
	return Vector2(board.width * cell, board.height * cell)


func sync_from(s: GameState) -> void:
	players = s.players.duplicate(true)
	plot_owner = Array(s.plot_owner)
	site_state = Array(s.site_state)
	pipelines = s.pipelines.duplicate(true)
	queue_redraw()


func site_pos(sid: int) -> Vector2:
	var st: Dictionary = board.sites[sid]
	return Vector2((st.x + 0.5) * cell, (st.y + 0.5) * cell)


func plot_center(plot: int) -> Vector2:
	var p: Dictionary = board.plots[plot]
	return Vector2(p.center_x * cell, p.center_y * cell)


func plot_at(local: Vector2) -> int:
	return board.cell_plot(floori(local.x / cell), floori(local.y / cell))


func site_near(local: Vector2, radius_cells: float = 0.75) -> int:
	var best := -1
	var best_d := radius_cells * cell
	for s in board.sites:
		var d := site_pos(s.id).distance_to(local)
		if d <= best_d:
			best_d = d
			best = s.id
	return best


func player_color(p: int) -> Color:
	if p < 0 or p >= players.size():
		return Color.WHITE
	return GameConst.PLAYER_COLORS[int(players[p].color) % GameConst.PLAYER_COLORS.size()]


func _process(delta: float) -> void:
	_t += delta
	if not highlight_sites.is_empty() or not highlight_plots.is_empty() or not trade_marks.is_empty():
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not interactive or board == null:
		return
	if not event is InputEventMouse:
		return
	# Use the event's own position (converted to board space), not the OS cursor.
	var local: Vector2 = (make_input_local(event) as InputEventMouse).position
	if event is InputEventMouseMotion:
		var inside := Rect2(Vector2.ZERO, pixel_size()).has_point(local)
		var hp := plot_at(local) if inside else -1
		var hs := site_near(local) if inside else -1
		if hp != hover_plot or hs != hover_site:
			hover_plot = hp
			hover_site = hs
			hovered.emit(hp, hs)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not Rect2(Vector2.ZERO, pixel_size()).has_point(local):
			return
		var sid := site_near(local, 0.6)
		if not (sid in highlight_sites):
			# Clicking a derrick's tower (drawn above its site) picks that site.
			sid = site_near(local + Vector2(0, 6), 0.8)
		if sid >= 0 and sid in highlight_sites:
			site_clicked.emit(sid)
		else:
			var p := plot_at(local)
			if p >= 0:
				plot_clicked.emit(p)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if board == null:
		return
	var size := pixel_size()
	if not decor.is_empty():
		BoardDecor.draw_fields(self, board, decor)
	elif _ground:
		draw_texture_rect(_ground, Rect2(Vector2.ZERO, size), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("b98a57"))
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)

	# Plot tints.
	for y in board.height:
		for x in board.width:
			var p := board.cell_plot(x, y)
			if p < 0:
				continue
			var r := Rect2(x * cell, y * cell, cell, cell)
			var owner: int = plot_owner[p] if p < plot_owner.size() else -1
			if owner >= 0:
				var c := player_color(owner)
				c.a = 0.38
				draw_rect(r, c)
			elif owner == GameConst.PLOT_CLOSED:
				# Closed after a failed auction: dark, hatched.
				draw_rect(r, Color(0.08, 0.06, 0.05, 0.55))
				if (x + y) % 2 == 0:
					draw_line(r.position, r.end, Color(0, 0, 0, 0.35), 1.0)
			elif decor.is_empty():
				draw_rect(r, Color(0, 0, 0, 0.05 * (p % 3)))
			if p == hover_plot:
				draw_rect(r, Color(1, 1, 1, 0.12))
			if p in highlight_plots:
				draw_rect(r, Color(1, 0.85, 0.3, 0.12 + 0.12 * pulse))
			if trade_marks.has(p):
				var tc: Color = trade_marks[p]
				tc.a = 0.2 + 0.15 * pulse
				draw_rect(r, tc)

	# Decoration over the tints, so buildings keep their own colors.
	var homes := Homestead.buildings(players, plot_owner) if show_buildings else {}
	if not decor.is_empty():
		BoardDecor.draw_lines(self, board, decor)
		if show_props:
			BoardDecor.draw_props(self, _props_clear_of(homes))
	if overlay_draw.is_valid():
		overlay_draw.call(self)

	# Plot borders.
	var ink := Color(0.11, 0.08, 0.06, 0.85)
	for y in board.height:
		for x in board.width:
			var p := board.cell_plot(x, y)
			if board.cell_plot(x + 1, y) != p and x + 1 < board.width:
				draw_line(Vector2((x + 1) * cell, y * cell), Vector2((x + 1) * cell, (y + 1) * cell), ink, 1.0)
			if board.cell_plot(x, y + 1) != p and y + 1 < board.height:
				draw_line(Vector2(x * cell, (y + 1) * cell), Vector2((x + 1) * cell, (y + 1) * cell), ink, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), ink, false, 1.0)
	if selected_plot >= 0:
		_outline_plot(selected_plot, Color("f2c14e"))
	for pl in pipelines:
		_draw_pipeline(pl)
	# Buildings over the borders, so a roof that rises past its property line isn't cut by it.
	_draw_buildings(homes)

	# Sites.
	for s in board.sites:
		if s.plot < plot_owner.size() and plot_owner[s.plot] == GameConst.PLOT_CLOSED:
			continue # closed land: all pieces removed
		var pos := site_pos(s.id)
		var st: int = site_state[s.id] if s.id < site_state.size() else GameConst.SITE_OPEN
		match st:
			GameConst.SITE_OPEN:
				draw_circle(pos, 1.6, Color(0.12, 0.08, 0.05))
				draw_arc(pos, 2.6, 0, TAU, 10, Color(0.3, 0.2, 0.12, 0.7), 1.0)
			GameConst.SITE_OIL:
				var owner: int = plot_owner[s.plot]
				_draw_derrick(pos, owner)
			GameConst.SITE_DRY:
				if _dry:
					draw_texture(_dry, (pos - Vector2(3, 3)).floor())
				else:
					draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), Color(0.5, 0.5, 0.5))
			GameConst.SITE_BURNED:
				if _burned:
					draw_texture(_burned, (pos - Vector2(4, 7)).floor())
		if s.id in highlight_sites:
			# Derricks stand above their site, so ring the middle of the tower.
			var ring_at := pos + (Vector2(0, -5) if st == GameConst.SITE_OIL else Vector2.ZERO)
			var r := (6.5 if st == GameConst.SITE_OIL else 3.0) + pulse * 1.5
			draw_arc(ring_at, r, 0, TAU, 16, highlight_color, 1.5 if st == GameConst.SITE_OIL else 1.0)
			if s.id == hover_site:
				draw_arc(ring_at, r + 1.5, 0, TAU, 16, Color.WHITE, 1.0)

	if board.map_type == "classic_1974":
		# The hub spans columns 23â€“37 across its middle.
		var logo_width := 14.0 * cell
		var logo_size := TITLE_LOGO.get_size() * (logo_width / TITLE_LOGO.get_width())
		var hub_center := Vector2(30.5, 21.0) * cell
		draw_texture_rect(TITLE_LOGO, Rect2((hub_center - logo_size / 2).round(), logo_size), false)

	# Prices.
	if board.map_type == "classic_1974":
		for p in board.plots:
			if show_prices and p.id in highlight_plots:
				continue
			var baseline := plot_center(p.id) + Vector2(-8, 3)
			draw_string_outline(_font, baseline, str(p.id + 1), HORIZONTAL_ALIGNMENT_CENTER, 16, 8, 2, Color("f1e4ba"))
			draw_string(_font, baseline, str(p.id + 1), HORIZONTAL_ALIGNMENT_CENTER, 16, 8, Color("2c2419"))
	if sale_mode:
		var glow := Color("f2c14e")
		glow.a = 0.55 + 0.45 * pulse
		for p in highlight_plots:
			_outline_plot(p, glow)
	for p in trade_marks:
		_outline_plot(p, trade_marks[p])
		_outline_plot_inset(p, trade_marks[p])
	if show_prices:
		# Board tags stay at the font's native 8 px (they sit on the map, not in the UI) and
		# inside the board. Gold tags = for sale this turn.
		var fsz := 8
		var area := Rect2(Vector2.ZERO, pixel_size()).grow(-1)
		for p in highlight_plots:
			var txt := "$%dk" % (int(board.plots[p].price) / 1000)
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
			var box := Rect2((plot_center(p) - tw / 2 - Vector2(3, 1)).round(), tw + Vector2(6, 2))
			box.position = box.position.clamp(area.position, area.end - box.size)
			draw_rect(box, Color("f2c14e") if sale_mode else Color(0.94, 0.89, 0.78, 0.92))
			draw_rect(box, Color("1d1611"), false, 1.0)
			draw_string(_font, box.position + Vector2(3, 1 + _font.get_ascent(fsz)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color("1d1611"))


## Raised steel pipe with a painted inlet valve, bolted collars and a capped outlet.
func _draw_pipeline(pl: Dictionary) -> void:
	var source := plot_center(pl.from)
	var target := plot_center(pl.to)
	var axis := source.direction_to(target)
	if axis == Vector2.ZERO:
		return
	# The opposite direction uses the other side of the centerline.
	var offset := axis.orthogonal() * 4.0
	var a := (source + offset).round()
	var b := (target + offset).round()
	var delta := b - a
	var diagonal := minf(absf(delta.x), absf(delta.y))
	var elbow := (a + delta.sign() * diagonal).round()
	var route := PackedVector2Array([a])
	if elbow != a and elbow != b:
		route.append(elbow)
	route.append(b)
	var owner_paint := player_color(pl.owner)
	var level := clampi(int(pl.level), 1, 3)
	var bore := 2.0 + level
	var steel := Color("71858a")
	var shadow := PackedVector2Array()
	for point in route:
		shadow.append(point + Vector2(1, 2))
	draw_polyline(shadow, Color(0.15, 0.10, 0.07, 0.65), bore + 2)
	draw_polyline(route, Color("293433"), bore + 2)
	draw_polyline(route, steel, bore)
	var glint := PackedVector2Array()
	for point in route:
		glint.append(point - Vector2(0, 1))
	draw_polyline(glint, Color("c8d6cd"), 1)
	for i in route.size() - 1:
		var start := route[i]
		var end := route[i + 1]
		var normal := start.direction_to(end).orthogonal() * (bore / 2 + 1)
		var collars := maxi(1, roundi(start.distance_to(end) / 15))
		for k in collars:
			var joint := start.lerp(end, (k + 0.5) / collars).round()
			draw_line(joint - normal, joint + normal, Color("344447"), 3)
			draw_line(joint - normal, joint + normal, Color("b2c3bb"), 1)
	# Set the valve along the run so buildings and lot numbers at its ends stay clear.
	var run := 0
	if route.size() == 3 and route[1].distance_to(route[2]) > route[0].distance_to(route[1]):
		run = 1
	var seat := route[run].lerp(route[run + 1], 0.4).round()
	var wheel := seat - Vector2(0, 5)
	draw_rect(Rect2(wheel, Vector2(2, 6)), Color("293433"))
	draw_circle(wheel, 4, UiKit.INK)
	draw_circle(wheel, 3, owner_paint.lightened(0.15))
	draw_circle(wheel, 1.8, Color("394648"))
	draw_line(wheel - Vector2(2, 0), wheel + Vector2(2, 0), owner_paint, 1)
	draw_rect(Rect2(wheel, Vector2.ONE), Color("f7e9c5"))
	var cap := route[-2].direction_to(b).orthogonal() * (bore / 2 + 1)
	draw_line(b - cap, b + cap, UiKit.INK, 4)
	draw_line(b - cap, b + cap, owner_paint, 2)


func building_spot(plot: int, kind: String) -> Vector2:
	var key := "%d:%s" % [plot, kind]
	if not _spots.has(key):
		_spots[key] = Homestead.spot(board, plot, kind, cell, decor)
	return _spots[key]


## Lower buildings overlap higher ones.
func _draw_buildings(homes: Dictionary) -> void:
	var order: Array = homes.keys()
	order.sort_custom(func(a, b): return building_spot(a, homes[a]).y < building_spot(b, homes[b]).y)
	for plot in order:
		var owner: int = plot_owner[plot]
		var look: Dictionary = players[owner].get("character", {})
		Homestead.draw(self, building_spot(plot, homes[plot]), look, homes[plot], _rising.get(plot, 1.0), player_color(owner))


## The decoration layout minus props a building stands on (rebuilt only when ownership changes).
func _props_clear_of(homes: Dictionary) -> Dictionary:
	var key := str(homes)
	if key == _shown_key:
		return _shown_props
	var rects: Array[Rect2] = []
	for plot in homes:
		var at := building_spot(plot, homes[plot])
		rects.append(Homestead.sprite_rect(homes[plot], at).grow(-1))
	var keep: Array = []
	for p in decor.get("props", []):
		var hit := false
		var pr := BoardDecor.prop_rect(p)
		for r in rects:
			if r.intersects(pr):
				hit = true
				break
		if not hit:
			keep.append(p)
	_shown_props = decor.duplicate()
	_shown_props["props"] = keep
	_shown_key = key
	return _shown_props


func _draw_derrick(pos: Vector2, owner: int) -> void:
	var paint := Color.WHITE
	if owner >= 0 and owner < players.size():
		var look: Dictionary = players[owner].get("character", {})
		paint = Cosmetics.find("paint", look.get("paint", "paint_plain")).color
	if _derrick:
		var at := (pos - Vector2(4, 12)).floor()
		draw_texture(_derrick, at, Color(0.78, 0.62, 0.42) * paint)
		draw_rect(Rect2(at + Vector2(3, 0), Vector2(3, 2)), player_color(owner))
	else:
		draw_rect(Rect2(pos - Vector2(2, 6), Vector2(4, 7)), player_color(owner))


func _outline_plot(plot: int, c: Color) -> void:
	for y in board.height:
		for x in board.width:
			if board.cell_plot(x, y) != plot:
				continue
			if board.cell_plot(x - 1, y) != plot:
				draw_line(Vector2(x * cell, y * cell), Vector2(x * cell, (y + 1) * cell), c, 1.0)
			if board.cell_plot(x + 1, y) != plot:
				draw_line(Vector2((x + 1) * cell, y * cell), Vector2((x + 1) * cell, (y + 1) * cell), c, 1.0)
			if board.cell_plot(x, y - 1) != plot:
				draw_line(Vector2(x * cell, y * cell), Vector2((x + 1) * cell, y * cell), c, 1.0)
			if board.cell_plot(x, y + 1) != plot:
				draw_line(Vector2(x * cell, (y + 1) * cell), Vector2((x + 1) * cell, (y + 1) * cell), c, 1.0)


## A second outline one pixel inside, so trade marks read as a thick border.
func _outline_plot_inset(plot: int, c: Color) -> void:
	for y in board.height:
		for x in board.width:
			if board.cell_plot(x, y) != plot:
				continue
			var r := Rect2(x * cell, y * cell, cell, cell).grow(-1)
			if board.cell_plot(x - 1, y) != plot:
				draw_line(r.position, Vector2(r.position.x, r.end.y), c, 1.0)
			if board.cell_plot(x + 1, y) != plot:
				draw_line(Vector2(r.end.x, r.position.y), r.end, c, 1.0)
			if board.cell_plot(x, y - 1) != plot:
				draw_line(r.position, Vector2(r.end.x, r.position.y), c, 1.0)
			if board.cell_plot(x, y + 1) != plot:
				draw_line(Vector2(r.position.x, r.end.y), r.end, c, 1.0)


# --- Effects (each returns when finished; `speed` scales duration) ------------------

func strip_sprite(path: String, frames: int, fps: float, loop: bool) -> AnimatedSprite2D:
	var t := UiKit.tex(path)
	var spr := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", loop)
	sf.set_animation_speed("default", fps)
	if t:
		var w := t.get_width() / frames
		for i in frames:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(i * w, 0, w, t.get_height())
			sf.add_frame("default", at)
	spr.sprite_frames = sf
	return spr


func effect_gusher(sid: int, speed: float) -> void:
	var spr := strip_sprite("res://assets/sprites/gusher_strip.png", 6, 10.0 * speed, false)
	spr.position = site_pos(sid) + Vector2(0, -15)
	add_child(spr)
	spr.play()
	Sfx.play("gusher")
	await get_tree().create_timer(0.9 / speed).timeout
	spr.queue_free()


func effect_dust(sid: int, speed: float) -> void:
	var spr := strip_sprite("res://assets/sprites/dust_strip.png", 6, 10.0 * speed, false)
	spr.position = site_pos(sid) + Vector2(0, -5)
	add_child(spr)
	spr.play()
	Sfx.play("dry_hole")
	await get_tree().create_timer(0.7 / speed).timeout
	spr.queue_free()


func effect_drilling(sid: int, speed: float) -> void:
	var rig := Sprite2D.new()
	rig.texture = UiKit.tex("res://assets/sprites/drill_rig.png")
	rig.position = site_pos(sid) + Vector2(0, -12)
	rig.scale = Vector2(0.5, 0.5)
	add_child(rig)
	var tw := create_tween()
	for i in 4:
		tw.tween_property(rig, "position:y", rig.position.y + 1, 0.08 / speed)
		tw.tween_property(rig, "position:y", rig.position.y, 0.08 / speed)
	await tw.finished
	rig.queue_free()


func effect_fire(sids: Array, speed: float) -> void:
	var sprites: Array = []
	for sid in sids:
		var spr := strip_sprite("res://assets/sprites/fire_strip.png", 4, 8.0, true)
		spr.position = site_pos(sid) + Vector2(0, -7)
		add_child(spr)
		spr.play()
		sprites.append(spr)
	Sfx.play("fire")
	await get_tree().create_timer(1.2 / speed).timeout
	for s in sprites:
		s.queue_free()


## The plot's building rises out of the ground (call after the new owner is set).
func effect_build(plot: int, speed: float) -> void:
	_rising[plot] = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_rising[plot] = v
		queue_redraw(), 0.0, 1.0, 0.3 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	_rising.erase(plot)
	queue_redraw()


func effect_flash_plot(plot: int, speed: float) -> void:
	var old := selected_plot
	for i in 3:
		selected_plot = plot
		queue_redraw()
		await get_tree().create_timer(0.08 / speed).timeout
		selected_plot = -1
		queue_redraw()
		await get_tree().create_timer(0.06 / speed).timeout
	selected_plot = old
	queue_redraw()


## Floating text that drifts up and fades (board-local position).
func float_text(at: Vector2, text: String, color: Color, speed: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiKit.fs(8))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("1d1611"))
	l.add_theme_constant_override("outline_size", 2)
	l.position = at - Vector2(10, 10)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 12, 0.8 / speed)
	tw.tween_property(l, "modulate:a", 0.0, 0.8 / speed).set_delay(0.3 / speed)
	tw.finished.connect(l.queue_free)
