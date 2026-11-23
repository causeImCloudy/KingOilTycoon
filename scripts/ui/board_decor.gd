class_name BoardDecor
extends RefCounted
## Map decoration built from the art kit in data/board_kit.json: field textures painted freely
## over the board (not tied to properties), line pieces (roads, rails, creeks, fences, tree lines)
## along cell edges, and props (buildings, trees, animals...). A layout is plain data, saved per map
## in data/boards/<map_id>.json:
##
##   {"theme": id, "default_field": id,
##    "field_grid": {"cell": 4, "ids": [field_id, ...], "rows": ["AAAB...", ...]},
##        # one row string per 4 px of board height, one letter per 4 px of width (A = ids[0])
##    "lines": [{"kind": id, "points": [[cx, cy], ...]}],   # cell-corner coords, axis-aligned steps
##    "props": [{"id": id, "x": px, "y": px, "flip": bool}]} # board pixels (360x240), bottom-center
##
## Presentation only: the rules never read it. auto_layout() is deterministic from its seed, so
## host and clients build the same decoration for random maps.

const KIT_PATH := "res://data/board_kit.json"
const LAYOUT_DIR := "res://data/boards/"
const KIT_DIR := "res://assets/board_kit/"
const BOARD_PX := Vector2(360, 240)
## Lines are drawn in this order (later ones on top).
const LINE_ORDER: Array[String] = ["creek", "tree_line", "fence", "dirt_road", "shell_road", "paved_road", "railroad"]
## Pixels kept clear around each drill site centre inside a prop's footprint.
const SITE_CLEAR: float = 3.0
## Field painting grid: one field per FIELD_CELL x FIELD_CELL board pixels.
const FIELD_CELL := 4
const FIELD_W := 90 # BOARD_PX.x / FIELD_CELL
const FIELD_H := 60
const E := 1
const S := 2
const W := 4
const N := 8

static var _kit: Dictionary = {}
static var _tex: Dictionary = {}


static func kit() -> Dictionary:
	if _kit.is_empty():
		var f := FileAccess.open(KIT_PATH, FileAccess.READ)
		_kit = JSON.parse_string(f.get_as_text())
	return _kit


static func _texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[path]


static func field_texture(id: String) -> Texture2D:
	return _texture(KIT_DIR + "fields/%s.png" % id)


static func line_texture(kind: String, part: String) -> Texture2D:
	return _texture(KIT_DIR + "lines/%s_%s.png" % [kind, part])


static func prop_texture(id: String) -> Texture2D:
	return _texture(KIT_DIR + "props/%s.png" % id)


# --- Layout files ------------------------------------------------------------------------------

## The saved layout's id for a match: campaign levels and the Classic layout have their own.
static func map_id_for(campaign_index: int, board: BoardMap) -> String:
	if campaign_index >= 0:
		return "level_%02d" % (campaign_index + 1)
	if board.map_type in ["classic", "classic_1974"]:
		return board.map_type
	return ""


static func layout_path(map_id: String) -> String:
	return LAYOUT_DIR + map_id + ".json"


static func load_layout(map_id: String) -> Dictionary:
	if map_id == "" or not FileAccess.file_exists(layout_path(map_id)):
		return {}
	var f := FileAccess.open(layout_path(map_id), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func save_layout(map_id: String, layout: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAYOUT_DIR))
	var f := FileAccess.open(layout_path(map_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(layout, "\t") + "\n")
	return true


## The decoration for a match: the saved layout if there is one, else an auto layout.
static func layout_for(campaign_index: int, board: BoardMap, theme_id: String) -> Dictionary:
	var saved := load_layout(map_id_for(campaign_index, board))
	if not saved.is_empty():
		return saved
	return auto_layout(board, theme_id, board.map_seed)


# --- Geometry ------------------------------------------------------------------------------------

static func cell_size(board: BoardMap) -> int:
	return int(BOARD_PX.x) / board.width


static func prop_def(id: String) -> Dictionary:
	return kit().props.get(id, {})


## Whole sprite rect (board pixels).
static func prop_rect(p: Dictionary) -> Rect2:
	var d := prop_def(p.id)
	var sz := Vector2(d.size[0], d.size[1]) if not d.is_empty() else Vector2(8, 8)
	return Rect2(Vector2(float(p.x) - sz.x / 2.0, float(p.y) - sz.y), sz)


## Ground footprint rect (bottom-centre of the sprite).
static func foot_rect(id: String, x: float, y: float) -> Rect2:
	var d := prop_def(id)
	var fs := Vector2(d.foot[0], d.foot[1]) if not d.is_empty() else Vector2(8, 8)
	return Rect2(Vector2(x - fs.x / 2.0, y - fs.y), fs)


## Drill sites a footprint covers (with the clearance margin).
static func sites_in(board: BoardMap, r: Rect2) -> int:
	var cell := cell_size(board)
	var grown := r.grow(SITE_CLEAR)
	var n := 0
	for s in board.sites:
		if grown.has_point(Vector2((s.x + 0.5) * cell, (s.y + 0.5) * cell)):
			n += 1
	return n


## How many drill sites a prop may cover: none for most, a little for big flat ones (ponds, arenas).
static func site_allowance(id: String) -> int:
	var d := prop_def(id)
	if d.is_empty():
		return 0
	return int(d.foot[0] * d.foot[1]) / 300


static func plot_at_px(board: BoardMap, pos: Vector2) -> int:
	var cell := cell_size(board)
	return board.cell_plot(floori(pos.x / cell), floori(pos.y / cell))


## The plot a rect sits in, or -1 if it straddles a border or the board edge.
static func plot_of_rect(board: BoardMap, r: Rect2) -> int:
	if not Rect2(Vector2.ZERO, BOARD_PX).encloses(r):
		return -1
	var a := r.grow(-0.5)
	var p := plot_at_px(board, a.position)
	for c in [Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), a.end]:
		if plot_at_px(board, c) != p:
			return -1
	return p


## Unit edges of all lines as rects (for keeping props off roads and rails).
static func line_rects(board: BoardMap, layout: Dictionary) -> Array[Rect2]:
	var cell := cell_size(board)
	var out: Array[Rect2] = []
	for ln in layout.get("lines", []):
		var pts: Array = ln.points
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i][0], pts[i][1]) * cell
			var b := Vector2(pts[i + 1][0], pts[i + 1][1]) * cell
			out.append(Rect2(a.min(b), (b - a).abs()).grow(5))
	return out


# --- Drawing -------------------------------------------------------------------------------------

# --- Field grid ----------------------------------------------------------------------------------

## The layout's field grid, built on first use from older layouts (one field per property) or
## filled with the default field.
static func field_grid(board: BoardMap, layout: Dictionary) -> Dictionary:
	if layout.has("field_grid"):
		return layout.field_grid
	var fallback: String = layout.get("default_field", "dirt")
	var g := {"cell": FIELD_CELL, "ids": [fallback], "rows": []}
	var per_plot: Dictionary = layout.get("fields", {})
	var full := "A".repeat(FIELD_W)
	for gy in FIELD_H:
		if per_plot.is_empty():
			g.rows.append(full)
			continue
		var row := ""
		for gx in FIELD_W:
			var p := plot_at_px(board, Vector2((gx + 0.5) * FIELD_CELL, (gy + 0.5) * FIELD_CELL))
			row += _grid_letter(g, str(per_plot.get(str(p), fallback)))
		g.rows.append(row)
	layout["field_grid"] = g
	layout.erase("fields")
	return g


static func _grid_letter(g: Dictionary, id: String) -> String:
	var i: int = g.ids.find(id)
	if i < 0:
		g.ids.append(id)
		i = g.ids.size() - 1
	return String.chr(65 + i)


## Field id at a grid cell ("" outside the board).
static func field_at(board: BoardMap, layout: Dictionary, gx: int, gy: int) -> String:
	if gx < 0 or gy < 0 or gx >= FIELD_W or gy >= FIELD_H:
		return ""
	var g := field_grid(board, layout)
	return g.ids[(g.rows[gy] as String).unicode_at(gx) - 65]


## Paints the field into every listed grid cell ([Vector2i]); returns how many changed.
static func paint_field(board: BoardMap, layout: Dictionary, cells: Array, id: String) -> int:
	var g := field_grid(board, layout)
	var letter := _grid_letter(g, id)
	var by_row := {}
	for c in cells:
		if c.x >= 0 and c.y >= 0 and c.x < FIELD_W and c.y < FIELD_H:
			if not by_row.has(c.y):
				by_row[c.y] = []
			by_row[c.y].append(c.x)
	var changed := 0
	for gy in by_row:
		var row: String = g.rows[gy]
		for gx in by_row[gy]:
			if row[gx] != letter:
				row = row.substr(0, gx) + letter + row.substr(gx + 1)
				changed += 1
		g.rows[gy] = row
	return changed


## Grid cells whose centers lie in a property.
static func grid_cells_of_plot(board: BoardMap, plot: int) -> Array:
	var out: Array = []
	for gy in FIELD_H:
		for gx in FIELD_W:
			if plot_at_px(board, Vector2((gx + 0.5) * FIELD_CELL, (gy + 0.5) * FIELD_CELL)) == plot:
				out.append(Vector2i(gx, gy))
	return out


## The connected area of one field around a grid cell (4-way flood fill).
static func grid_region(board: BoardMap, layout: Dictionary, start: Vector2i) -> Array:
	var id := field_at(board, layout, start.x, start.y)
	if id == "":
		return []
	var seen := {start: true}
	var todo: Array = [start]
	var out: Array = []
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and field_at(board, layout, n.x, n.y) == id:
				seen[n] = true
				todo.append(n)
	return out


## Drops field ids no cell uses any more (keeps saved files tidy).
static func compact_field_grid(board: BoardMap, layout: Dictionary) -> void:
	var g := field_grid(board, layout)
	var used := {}
	for row in g.rows:
		for i in (row as String).length():
			used[(row as String).unicode_at(i) - 65] = true
	if used.size() == g.ids.size():
		return
	var ids: Array = []
	var remap := {}
	for i in g.ids.size():
		if used.has(i):
			remap[String.chr(65 + i)] = String.chr(65 + ids.size())
			ids.append(g.ids[i])
	var rows: Array = []
	for row in g.rows:
		var r := ""
		for i in (row as String).length():
			r += remap[row[i]]
		rows.append(r)
	g.ids = ids
	g.rows = rows


## Field textures from the field grid (each run of one field is one rect), then water where the
## board has no land. The canvas item must have texture repeat enabled.
static func draw_fields(ci: CanvasItem, board: BoardMap, layout: Dictionary) -> void:
	var g := field_grid(board, layout)
	var tex: Array = []
	for id in g.ids:
		tex.append(field_texture(id))
	var fc := float(FIELD_CELL)
	for gy in FIELD_H:
		var row: String = g.rows[gy]
		var start := 0
		while start < FIELD_W:
			var code := row.unicode_at(start)
			var end := start + 1
			while end < FIELD_W and row.unicode_at(end) == code:
				end += 1
			var r := Rect2(start * fc, gy * fc, (end - start) * fc, fc)
			var t: Texture2D = tex[code - 65]
			if t:
				ci.draw_texture_rect_region(t, r, r) # region in board space: tiles seamlessly
			else:
				ci.draw_rect(r, Color("b98a57"))
			start = end
	var cell := cell_size(board)
	for y in board.height:
		for x in board.width:
			if board.cell_plot(x, y) < 0:
				ci.draw_rect(Rect2(x * cell, y * cell, cell, cell), Color("20524c"))


## Roads, rails, creeks, fences and tree lines. All lines of one kind are merged into a graph,
## so corners and crossings get their own pieces wherever lines meet.
static func draw_lines(ci: CanvasItem, board: BoardMap, layout: Dictionary) -> void:
	var cell := cell_size(board)
	for kind in LINE_ORDER:
		var mask := _line_mask(layout, kind)
		if mask.is_empty():
			continue
		var straight := line_texture(kind, "straight")
		var corner := line_texture(kind, "corner")
		var cross := line_texture(kind, "cross")
		# Straight runs (horizontal, then vertical), split only where a corner or crossing sits.
		for pt: Vector2i in mask:
			for dir in [E, S]:
				var back := W if dir == E else N
				if not (mask[pt] & dir):
					continue
				if (mask[pt] & back) and not _needs_piece(mask[pt]):
					continue # inside a run that started earlier
				var step := Vector2i(1, 0) if dir == E else Vector2i(0, 1)
				var end := pt + step
				while mask.get(end, 0) == (E | W if dir == E else N | S):
					end += step
				var trim_a := 4.0 if _needs_piece(mask[pt]) else 0.0
				var trim_b := 4.0 if _needs_piece(mask.get(end, 0)) else 0.0
				var length := float((end - pt).length()) * cell - trim_a - trim_b
				if length <= 0:
					continue
				var origin := Vector2(pt) * cell + Vector2(step) * trim_a
				ci.draw_set_transform(origin, 0.0 if dir == E else PI / 2.0)
				if straight:
					ci.draw_texture_rect(straight, Rect2(0, -4, length, 8), true)
				else:
					ci.draw_rect(Rect2(0, -2, length, 4), Color("8a6a4a"))
		# Corner and crossing pieces.
		for pt: Vector2i in mask:
			var m: int = mask[pt]
			if not _needs_piece(m):
				continue
			var tex := cross
			var rot := 0.0
			if _bits(m) == 2:
				tex = corner
				match m:
					E | S: rot = 0.0
					S | W: rot = PI / 2.0
					W | N: rot = PI
					N | E: rot = PI * 1.5
			ci.draw_set_transform(Vector2(pt) * cell, rot)
			if tex:
				ci.draw_texture_rect(tex, Rect2(-4, -4, 8, 8), false)
		ci.draw_set_transform(Vector2.ZERO, 0.0)


## Direction bits (E/S/W/N) at every cell corner a line of this kind touches.
static func _line_mask(layout: Dictionary, kind: String) -> Dictionary:
	var mask := {}
	for ln in layout.get("lines", []):
		if ln.kind != kind:
			continue
		var pts: Array = ln.points
		for i in range(pts.size() - 1):
			var a := Vector2i(pts[i][0], pts[i][1])
			var b := Vector2i(pts[i + 1][0], pts[i + 1][1])
			var d := (b - a).sign()
			if d.x != 0 and d.y != 0:
				continue # not axis-aligned: ignored
			var p := a
			while p != b:
				var q := p + d
				var fwd := E if d.x > 0 else (W if d.x < 0 else (S if d.y > 0 else N))
				var rev: int = {E: W, W: E, S: N, N: S}[fwd]
				mask[p] = int(mask.get(p, 0)) | fwd
				mask[q] = int(mask.get(q, 0)) | rev
				p = q
	return mask


static func _bits(m: int) -> int:
	return int(m & 1 > 0) + int(m & 2 > 0) + int(m & 4 > 0) + int(m & 8 > 0)


## A corner or crossing piece goes where a line turns or branches (not on straight-throughs or ends).
static func _needs_piece(m: int) -> bool:
	return _bits(m) >= 2 and m != (E | W) and m != (N | S)


## Props: flat ones first, then standing ones from back (top) to front (bottom).
static func draw_props(ci: CanvasItem, layout: Dictionary, tint: Callable = Callable()) -> void:
	var props: Array = layout.get("props", []).duplicate()
	props.sort_custom(func(a, b):
		var fa: bool = prop_def(a.id).get("layer", "stand") == "flat"
		var fb: bool = prop_def(b.id).get("layer", "stand") == "flat"
		if fa != fb:
			return fa
		return float(a.y) < float(b.y))
	for i in props.size():
		var p: Dictionary = props[i]
		var t := prop_texture(p.id)
		var r := prop_rect(p)
		var mod: Color = tint.call(p) if tint.is_valid() else Color.WHITE
		if t == null:
			ci.draw_rect(r, Color(1, 0, 1, 0.5))
			continue
		if p.get("flip", false):
			ci.draw_texture_rect(t, Rect2(r.position + Vector2(r.size.x, 0), Vector2(-r.size.x, r.size.y)), false, mod)
		else:
			ci.draw_texture_rect(t, r, false, mod)


# --- Auto layout ---------------------------------------------------------------------------------

## Builds a layout from a theme: fields per property, lines along property borders, building groups
## and scattered props kept off drill sites. Deterministic for a given board, theme and seed.
static func auto_layout(board: BoardMap, theme_id: String, seed_value: int) -> Dictionary:
	var k := kit()
	if not k.themes.has(theme_id):
		theme_id = "farm"
	var t: Dictionary = k.themes[theme_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [theme_id, seed_value, board.plots.size()])
	var layout := {"theme": theme_id, "default_field": t.fields[0], "fields": {}, "lines": [], "props": []}

	# Fields: start one per property, no two neighbours alike where possible. field_grid() below
	# turns that into the free-paint grid, which the map editor repaints without regard to properties.
	for i in board.plots.size():
		var options: Array = t.fields.duplicate()
		_shuffle(options, rng)
		var pick: String = options[0]
		for f in options:
			var clash := false
			for nb in board.adjacency[i]:
				if layout.fields.get(str(nb), "") == f:
					clash = true
			if not clash:
				pick = f
				break
		layout.fields[str(i)] = pick
	field_grid(board, layout)

	# Lines.
	var graph := _border_graph(board)
	var used := {}
	var lines: Dictionary = t.lines
	for kind in ["railroad"]:
		for n in int(lines.get(kind, 0)):
			layout.lines.append(_straight_line(board, rng, n))
	for kind in ["paved_road", "dirt_road", "shell_road", "creek"]:
		for n in int(lines.get(kind, 0)):
			var path := _border_path(board, graph, rng, n % 2 == 1, used, 3.0 if kind == "creek" else 0.6)
			if path.size() >= 2:
				layout.lines.append({"kind": kind, "points": _compress(path)})
	for n in int(lines.get("fence", 0)):
		for chain in _plot_outline(board, rng.randi_range(0, board.plots.size() - 1)):
			layout.lines.append({"kind": "fence", "points": _compress(chain)})
	for n in int(lines.get("tree_line", 0)):
		var outline := _plot_outline(board, rng.randi_range(0, board.plots.size() - 1))
		if outline.is_empty():
			continue
		var chain: Array = outline[0]
		var len_n := mini(chain.size(), rng.randi_range(4, 8))
		var start := rng.randi_range(0, chain.size() - len_n)
		layout.lines.append({"kind": "tree_line", "points": _compress(chain.slice(start, start + len_n))})

	# Props: groups first (the first item anchors the rest nearby), then scattered extras.
	var blocked := line_rects(board, layout)
	for st in t.sets:
		for n in int(st[1]):
			var items: Array = k.sets[st[0]]
			var anchor := Vector2(-1, -1)
			for id in items:
				var spot := _find_spot(board, id, rng, blocked, anchor, 90 if anchor.x < 0 else 50)
				if spot.x < 0:
					if anchor.x < 0:
						break # no room for the main building: skip the group
					continue
				if anchor.x < 0:
					anchor = spot
				_place(layout, blocked, id, spot, rng)
	for sc in t.scatter:
		for n in int(sc[1]):
			var spot := _find_spot(board, sc[0], rng, blocked, Vector2(-1, -1), 30)
			if spot.x >= 0:
				_place(layout, blocked, sc[0], spot, rng)
	return layout


static func _place(layout: Dictionary, blocked: Array[Rect2], id: String, spot: Vector2, rng: RandomNumberGenerator) -> void:
	var flippable: bool = prop_def(id).get("layer", "stand") != "flat" and prop_def(id).get("cat", "") in ["plant", "animal", "vehicle"]
	layout.props.append({"id": id, "x": spot.x, "y": spot.y, "flip": flippable and rng.randf() < 0.5})
	blocked.append(foot_rect(id, spot.x, spot.y).grow(1))


## True if a prop can stand here: inside one property, off lines and other props, and clear of
## drill sites (big flat props may cover a few).
static func spot_ok(board: BoardMap, id: String, pos: Vector2, blocked: Array[Rect2]) -> bool:
	var r := foot_rect(id, pos.x, pos.y)
	if plot_of_rect(board, r) < 0:
		return false
	# Tall sprites must not poke out over the board's top edge.
	if not Rect2(Vector2.ZERO, BOARD_PX).encloses(prop_rect({"id": id, "x": pos.x, "y": pos.y})):
		return false
	for b in blocked:
		if b.intersects(r):
			return false
	return sites_in(board, r) <= site_allowance(id)


static func _find_spot(board: BoardMap, id: String, rng: RandomNumberGenerator, blocked: Array[Rect2],
		near: Vector2, tries: int) -> Vector2:
	var d := prop_def(id)
	if d.is_empty():
		return Vector2(-1, -1)
	for i in tries:
		var pos: Vector2
		if near.x >= 0:
			pos = near + Vector2(rng.randf_range(-30, 30), rng.randf_range(-24, 24))
		else:
			pos = Vector2(rng.randf_range(0, BOARD_PX.x), rng.randf_range(0, BOARD_PX.y))
		pos = pos.round()
		if spot_ok(board, id, pos, blocked):
			return pos
	return Vector2(-1, -1)


## Straight railroad across the board on a cell-row boundary (every other one runs north-south).
static func _straight_line(board: BoardMap, rng: RandomNumberGenerator, n: int) -> Dictionary:
	if n % 2 == 0:
		var y := rng.randi_range(3, board.height - 3)
		return {"kind": "railroad", "points": [[0, y], [board.width, y]]}
	var x := rng.randi_range(4, board.width - 4)
	return {"kind": "railroad", "points": [[x, 0], [x, board.height]]}


## Cell-corner graph of every edge between two different properties (inner borders only), plus
## the board edge points where those borders start.
static func _border_graph(board: BoardMap) -> Dictionary:
	var g := {}
	for y in range(0, board.height + 1):
		for x in range(0, board.width + 1):
			# Horizontal edge (x,y)-(x+1,y) separates cell (x,y-1) and (x,y).
			if x < board.width and y > 0 and y < board.height and board.cell_plot(x, y - 1) != board.cell_plot(x, y):
				_link(g, Vector2i(x, y), Vector2i(x + 1, y))
			# Vertical edge (x,y)-(x,y+1) separates cell (x-1,y) and (x,y).
			if y < board.height and x > 0 and x < board.width and board.cell_plot(x - 1, y) != board.cell_plot(x, y):
				_link(g, Vector2i(x, y), Vector2i(x, y + 1))
	return g


static func _link(g: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not g.has(a):
		g[a] = []
	if not g.has(b):
		g[b] = []
	g[a].append(b)
	g[b].append(a)


## A path along property borders from one side of the board to the other (left-right, or
## top-bottom when vertical), with random edge costs. Edges already used cost more.
static func _border_path(board: BoardMap, g: Dictionary, rng: RandomNumberGenerator, vertical: bool,
		used: Dictionary, wiggle: float) -> Array:
	var starts: Array[Vector2i] = []
	var goal_x := board.width
	var goal_y := board.height
	for p: Vector2i in g:
		if (not vertical and p.x == 0) or (vertical and p.y == 0):
			starts.append(p)
	if starts.is_empty():
		return []
	var start: Vector2i = starts[rng.randi_range(0, starts.size() - 1)]
	var cost := {start: 0.0}
	var prev := {}
	var open: Array = [start]
	var goal := Vector2i(-1, -1)
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if (not vertical and cur.x == goal_x) or (vertical and cur.y == goal_y):
			goal = cur
			break
		for nb: Vector2i in g[cur]:
			var key := _edge_key(cur, nb)
			var c: float = cost[cur] + 1.0 + rng.randf() * wiggle + (8.0 if used.has(key) else 0.0)
			if c < cost.get(nb, INF):
				cost[nb] = c
				prev[nb] = cur
				if not (nb in open):
					open.append(nb)
	if goal.x < 0:
		return []
	var path: Array = [goal]
	while path[0] != start:
		path.push_front(prev[path[0]])
	for i in range(path.size() - 1):
		used[_edge_key(path[i], path[i + 1])] = true
	return path


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%d,%d-%d,%d" % [lo.x, lo.y, hi.x, hi.y]


## A property's inner borders as chains of cell corners (for fences and tree lines).
static func _plot_outline(board: BoardMap, plot: int) -> Array:
	var g := {}
	for y in range(0, board.height + 1):
		for x in range(0, board.width + 1):
			if x < board.width and y > 0 and y < board.height:
				var a := board.cell_plot(x, y - 1)
				var b := board.cell_plot(x, y)
				if a != b and (a == plot or b == plot):
					_link(g, Vector2i(x, y), Vector2i(x + 1, y))
			if y < board.height and x > 0 and x < board.width:
				var c := board.cell_plot(x - 1, y)
				var d := board.cell_plot(x, y)
				if c != d and (c == plot or d == plot):
					_link(g, Vector2i(x, y), Vector2i(x, y + 1))
	var chains: Array = []
	var seen := {}
	for p: Vector2i in g:
		for nb: Vector2i in g[p]:
			if seen.has(_edge_key(p, nb)):
				continue
			var chain: Array = [p]
			var cur := p
			var nxt := nb
			while true:
				seen[_edge_key(cur, nxt)] = true
				chain.append(nxt)
				var cont := Vector2i(-1, -1)
				for c2: Vector2i in g[nxt]:
					if not seen.has(_edge_key(nxt, c2)):
						cont = c2
						break
				if cont.x < 0:
					break
				cur = nxt
				nxt = cont
			chains.append(chain)
	return chains


## Drops points in the middle of straight runs; returns [[x, y], ...].
static func _compress(path: Array) -> Array:
	var out: Array = []
	for i in path.size():
		var p: Vector2i = path[i]
		if i > 0 and i < path.size() - 1:
			var d1: Vector2i = p - (path[i - 1] as Vector2i)
			var d2: Vector2i = (path[i + 1] as Vector2i) - p
			if d1 == d2:
				continue
		out.append([p.x, p.y])
	return out


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
