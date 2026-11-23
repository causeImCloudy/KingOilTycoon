class_name Homestead
extends RefCounted
## Your buildings on the board: a house on the first property you buy and a small outbuilding on
## every property after that. Both are styled by the player's look (Cosmetics "house",
## "outbuilding", "siding", "roof"). Presentation only: the rules just record the order land was
## bought in (GameState players[p].land, home_plot()).
##
## Art: assets/sprites/homestead/<kind>_<style>.png, three frames side by side, each frame the
## building's full size: 0 = walls (greyscale, tinted with the siding color), 1 = roof (greyscale,
## tinted with the roof color), 2 = details (full color, drawn on top: outline, door, windows,
## chimney, trim). The bottom-center of a frame is where the building stands.

const DIR := "res://assets/sprites/homestead/"
const KINDS: Array[String] = ["house", "outbuilding"]
const SIZE := {"house": Vector2(20, 20), "outbuilding": Vector2(12, 12)}
## Ground footprint (bottom-center): kept off drill sites; roofs may rise above it.
const FOOT := {"house": Vector2(16, 10), "outbuilding": Vector2(10, 6)}

static var _tex: Dictionary = {}


static func texture(kind: String, style: String) -> Texture2D:
	var path := DIR + "%s_%s.png" % [kind, style]
	if not _tex.has(path):
		_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[path]


static func style_of(look: Dictionary, kind: String) -> String:
	return str(Cosmetics.find(kind, str(look.get(kind, ""))).get("style", ""))


## Draws a building standing at `bottom` (bottom-center). `grow` (0-1) squashes it up out of the
## ground for the build animation. A visible `flag` color adds the owner's pennant on a pole at the
## building's top-left, so players' buildings stand apart from the map's decoration houses.
static func draw(ci: CanvasItem, bottom: Vector2, look: Dictionary, kind: String, grow: float = 1.0,
		flag: Color = Color(0, 0, 0, 0)) -> void:
	var sz: Vector2 = SIZE[kind]
	var h := roundf(sz.y * clampf(grow, 0.0, 1.0))
	if h < 1.0:
		return
	var dest := Rect2((bottom - Vector2(sz.x / 2.0, h)).floor(), Vector2(sz.x, h))
	var walls: Color = Cosmetics.find("siding", str(look.get("siding", ""))).color
	var roof: Color = Cosmetics.find("roof", str(look.get("roof", ""))).color
	var t := texture(kind, style_of(look, kind))
	if t == null:
		ci.draw_rect(dest, walls)
		ci.draw_rect(Rect2(dest.position, Vector2(sz.x, minf(h, sz.y * 0.4))), roof)
		ci.draw_rect(dest, Color("1d1611"), false, 1.0)
	else:
		for i in 3:
			var mod: Color = [walls, roof, Color.WHITE][i]
			ci.draw_texture_rect_region(t, dest, Rect2(i * sz.x, 0, sz.x, sz.y), mod)
	if flag.a > 0.0 and grow >= 1.0:
		_draw_pennant(ci, dest.position + Vector2(2, 0), kind == "house", flag)


## Pole from the building's top-left up past its roof, with a flag in the owner's color.
static func _draw_pennant(ci: CanvasItem, top_left: Vector2, big: bool, c: Color) -> void:
	var ink := Color("1d1611")
	var pole_h := 9.0 if big else 6.0
	var base := top_left + Vector2(0, 4 if big else 3)
	var tip := base - Vector2(0, pole_h)
	ci.draw_rect(Rect2(tip, Vector2(1, pole_h)), ink)
	var fs := Vector2(5, 3) if big else Vector2(4, 3)
	var fr := Rect2(tip + Vector2(1, 0), fs)
	ci.draw_rect(fr.grow(1), ink)
	ci.draw_rect(fr, c)


## Whole sprite rect for a building standing at `bottom`.
static func sprite_rect(kind: String, bottom: Vector2) -> Rect2:
	var sz: Vector2 = SIZE[kind]
	return Rect2(bottom - Vector2(sz.x / 2.0, sz.y), sz)


static func foot_rect(kind: String, bottom: Vector2) -> Rect2:
	var fs: Vector2 = FOOT[kind]
	return Rect2(bottom - Vector2(fs.x / 2.0, fs.y), fs)


## Which building stands on each owned plot: {plot: kind}. The house goes on each player's home
## plot (the first one they got that they still own); every other owned plot gets an outbuilding.
static func buildings(players: Array, owners: Array) -> Dictionary:
	var out := {}
	for plot in owners.size():
		var p: int = owners[plot]
		if p < 0 or p >= players.size():
			continue
		out[plot] = "outbuilding"
	for p in players.size():
		var home := GameState.home_plot_of(players[p], p, owners)
		if home >= 0:
			out[home] = "house"
	return out


## Where a building stands on a plot (bottom-center, board pixels): inside the plot, clear of
## drill sites and the derricks that rise above them, off the plot's center (pipelines end there
## and the Classic board prints lot numbers there), off roads and rails, and otherwise close to the
## middle. Deterministic, so every player sees the same spot.
static func spot(board: BoardMap, plot: int, kind: String, cell: float, layout: Dictionary = {}) -> Vector2:
	var sz: Vector2 = SIZE[kind]
	var info: Dictionary = board.plots[plot]
	var center := Vector2(float(info.center_x), float(info.center_y)) * cell
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in board.height:
		for x in board.width:
			if board.cell_plot(x, y) == plot:
				lo = lo.min(Vector2(x, y) * cell)
				hi = hi.max(Vector2(x + 1, y + 1) * cell)
	if lo.x == INF:
		return center
	var area := Rect2(Vector2.ZERO, Vector2(board.width, board.height) * cell)
	var near_sites: Array[Vector2] = []
	var bbox := Rect2(lo, hi - lo).grow(sz.x)
	for s in board.sites:
		var sp := Vector2((s.x + 0.5) * cell, (s.y + 0.5) * cell)
		if bbox.has_point(sp):
			near_sites.append(sp)
	var roads: Array[Rect2] = []
	if not layout.is_empty() and is_equal_approx(cell, float(BoardDecor.cell_size(board))):
		roads = BoardDecor.line_rects(board, layout)
	var best := Vector2(-1, -1)
	var best_score := INF
	var y0 := int(lo.y + FOOT[kind].y)
	var y := y0
	while y <= int(hi.y):
		var x := int(lo.x + FOOT[kind].x / 2.0)
		while x <= int(hi.x - FOOT[kind].x / 2.0):
			var pos := Vector2(x, y)
			var score := _score(board, plot, kind, pos, cell, center, area, near_sites, roads)
			if score < best_score:
				best_score = score
				best = pos
			x += 2
		y += 2
	if best.x < 0:
		return (center + Vector2(0, sz.y / 2.0)).round()
	return best


static func _score(board: BoardMap, plot: int, kind: String, pos: Vector2, cell: float, center: Vector2,
		area: Rect2, near_sites: Array[Vector2], roads: Array[Rect2]) -> float:
	var sprite := sprite_rect(kind, pos)
	if not area.encloses(sprite):
		return INF
	var foot := foot_rect(kind, pos)
	var inner := foot.grow(-0.5)
	for c in [inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.end]:
		if board.cell_plot(floori(c.x / cell), floori(c.y / cell)) != plot:
			return INF
	var score := 0.0
	for sp in near_sites:
		if foot.grow(BoardDecor.SITE_CLEAR).has_point(sp):
			score += 100.0 # a drill hole under the house
		elif sprite.intersects(Rect2(sp.x - 5, sp.y - 13, 10, 14)):
			score += 40.0 # a derrick would stand in front of it
		elif sprite.grow(2).has_point(sp):
			score += 15.0
	# Keep clear of the middle: pipelines end there and the Classic board prints the lot number.
	if sprite.intersects(Rect2(center - Vector2(10, 9), Vector2(20, 13))):
		score += 30.0
	for r in roads:
		if foot.intersects(r):
			score += 12.0
	return score + pos.distance_to(center + Vector2(0, SIZE[kind].y / 2.0)) * 0.1
