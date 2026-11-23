class_name BoardMap
extends RefCounted
## Grid map of land plots and drill sites. Pure data, no nodes.
##
## cells[y * width + x] = plot index (or -1 for no land).
## plots[i] = {id, name, price, sites: Array[int], center_x, center_y}
## sites[i] = {id, plot, x, y}
## adjacency[i] = Array[int] of neighboring plot ids.

var map_type: String = "procedural"
var map_seed: int = 0
var width: int = 0
var height: int = 0
var cells: PackedInt32Array = PackedInt32Array()
var plots: Array = []
var sites: Array = []
var adjacency: Array = []

const STANDARD_SIZE := Vector2i(30, 20)
const LARGE_SIZE := Vector2i(36, 24)
const STANDARD_PLOTS: int = 18
const LARGE_PLOTS: int = 24

## Hand-designed "Classic" layout: per row, the widths of each plot run, in band order.
## Three bands of six plots each (rows 0-6, 7-12, 13-19). Original to this game.
const CLASSIC_ROWS: Array = [
	[5, 6, 4, 6, 5, 4], [5, 6, 4, 6, 5, 4], [6, 5, 5, 5, 5, 4], [6, 5, 5, 5, 4, 5],
	[5, 6, 6, 4, 4, 5], [4, 7, 6, 4, 5, 4], [4, 6, 6, 5, 5, 4],
	[5, 6, 5, 5, 5, 4], [6, 5, 5, 6, 4, 4], [6, 5, 4, 6, 5, 4], [5, 6, 4, 5, 6, 4],
	[4, 6, 5, 5, 5, 5], [4, 5, 6, 4, 6, 5],
	[5, 5, 6, 5, 5, 4], [5, 5, 6, 5, 5, 4], [6, 5, 5, 6, 4, 4], [6, 5, 4, 6, 5, 4],
	[5, 6, 4, 5, 6, 4], [5, 5, 5, 5, 5, 5], [4, 6, 5, 4, 6, 5],
]
## Drilling sites per property (price = $1,000 per site), matching the original game's 18 properties.
const CLASSIC_SITE_COUNTS: Array[int] = [12, 8, 9, 11, 9, 9, 8, 8, 10, 10, 9, 8, 8, 10, 8, 8, 12, 12]
const CLASSIC_SEED: int = 4417
const Survey := preload("res://scripts/game/classic_survey.gd")


func cell_plot(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return cells[y * width + x]


func site_at(x: int, y: int) -> int:
	for s in sites:
		if s.x == x and s.y == y:
			return s.id
	return -1


func are_adjacent(a: int, b: int) -> bool:
	return b in adjacency[a]


# --- Generation ---------------------------------------------------------------

## board_id names a hand-edited board (data/boards/<board_id>.board.json, made in the map editor).
## Campaign levels pass "level_XX"; the Classic layouts use their map type as the id. When no
## edited board exists, the map is generated as usual.
static func create(map_type_id: String, seed_value: int, player_count: int, board_id: String = "") -> BoardMap:
	if board_id == "" and map_type_id in ["classic", "classic_1974"]:
		board_id = map_type_id
	if board_id != "":
		var custom := load_custom(board_id)
		if custom != null:
			return custom
	if map_type_id == "classic_1974" and player_count <= 4:
		return create_survey()
	if map_type_id == "classic" and player_count <= 4:
		return create_classic()
	return create_procedural(seed_value, player_count)


static func create_survey() -> BoardMap:
	var m := BoardMap.new()
	m.map_type = "classic_1974"
	m.map_seed = CLASSIC_SEED
	m.width = Survey.ROWS[0].length()
	m.height = Survey.ROWS.size()
	var fixed_sites := []
	for i in STANDARD_PLOTS:
		fixed_sites.append([])
	for y in m.height:
		var row: String = Survey.ROWS[y]
		for x in m.width:
			var symbol := row.substr(x, 1)
			var plot := -1 if symbol == "." else symbol.to_lower().unicode_at(0) - 97
			m.cells.append(plot)
			if plot >= 0 and symbol == symbol.to_upper():
				fixed_sites[plot].append(Vector2i(x, y))
	m._build_plots(STANDARD_PLOTS, null, CLASSIC_SITE_COUNTS, fixed_sites)
	for p in m.plots:
		p.name = "Property %d" % (p.id + 1)
		p.center_x = Survey.LABELS[p.id].x + 0.5
		p.center_y = Survey.LABELS[p.id].y + 0.5
	return m


static func create_classic() -> BoardMap:
	var m := BoardMap.new()
	m.map_type = "classic"
	m.map_seed = CLASSIC_SEED
	m.width = STANDARD_SIZE.x
	m.height = STANDARD_SIZE.y
	m.cells.resize(m.width * m.height)
	for y in m.height:
		var band: int = 0 if y <= 6 else (1 if y <= 12 else 2)
		var x := 0
		var row: Array = CLASSIC_ROWS[y]
		for i in row.size():
			for _w in int(row[i]):
				m.cells[y * m.width + x] = band * 6 + i
				x += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = CLASSIC_SEED
	m._build_plots(STANDARD_PLOTS, rng, CLASSIC_SITE_COUNTS)
	return m


static func create_procedural(seed_value: int, player_count: int) -> BoardMap:
	var m := BoardMap.new()
	m.map_type = "procedural"
	m.map_seed = seed_value
	var large := player_count > 4
	var size: Vector2i = LARGE_SIZE if large else STANDARD_SIZE
	var plot_count: int = LARGE_PLOTS if large else STANDARD_PLOTS
	m.width = size.x
	m.height = size.y
	m.cells.resize(m.width * m.height)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Spread plot seeds with a minimum distance, then assign cells to the nearest seed.
	var seeds: Array[Vector2] = []
	var min_dist := sqrt(float(m.width * m.height) / plot_count) * 0.8
	var attempts := 0
	while seeds.size() < plot_count:
		var p := Vector2(rng.randf_range(1.0, m.width - 1.0), rng.randf_range(1.0, m.height - 1.0))
		var ok := true
		for s in seeds:
			if s.distance_to(p) < min_dist:
				ok = false
				break
		attempts += 1
		if ok or attempts > 4000:
			seeds.append(p)
	# Slightly stretched distance gives wider, field-like plots.
	for y in m.height:
		for x in m.width:
			var best := 0
			var best_d := INF
			for i in seeds.size():
				var d := Vector2((x + 0.5 - seeds[i].x) * 0.85, y + 0.5 - seeds[i].y).length_squared()
				if d < best_d:
					best_d = d
					best = i
			m.cells[y * m.width + x] = best
	var counts: Array[int] = []
	for i in plot_count:
		counts.append(rng.randi_range(8, 12))
	m._build_plots(plot_count, rng, counts)
	return m


func _build_plots(plot_count: int, rng: RandomNumberGenerator, site_counts: Array[int], fixed_sites: Array = []) -> void:
	plots.clear()
	sites.clear()
	adjacency.clear()
	var plot_cells: Array = []
	for i in plot_count:
		plot_cells.append([])
		adjacency.append([])
	for y in height:
		for x in width:
			var p := cells[y * width + x]
			if p >= 0:
				plot_cells[p].append(Vector2i(x, y))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q := cell_plot(x + d.x, y + d.y)
				if p >= 0 and q >= 0 and q != p and not (q in adjacency[p]):
					adjacency[p].append(q)
					adjacency[q].append(p)

	var names := GameConst.PLOT_NAMES.duplicate()
	if map_type == "procedural":
		_shuffle(names, rng)
	for i in plot_count:
		var pc: Array = plot_cells[i]
		var want := mini(site_counts[i], maxi(1, pc.size() / 2))
		var chosen: Array = _pick_spread(pc, want, rng) if fixed_sites.is_empty() else fixed_sites[i]
		var site_ids: Array = []
		var cx := 0.0
		var cy := 0.0
		for c: Vector2i in pc:
			cx += c.x
			cy += c.y
		for c: Vector2i in chosen:
			var sid := sites.size()
			sites.append({"id": sid, "plot": i, "x": c.x, "y": c.y})
			site_ids.append(sid)
		plots.append({
			"id": i,
			"name": names[i % names.size()],
			"price": chosen.size() * 1000,
			"sites": site_ids,
			"center_x": cx / maxf(1.0, pc.size()) + 0.5,
			"center_y": cy / maxf(1.0, pc.size()) + 0.5,
		})


## Picks `count` cells, preferring ones not touching an already chosen cell or the plot edge.
func _pick_spread(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var candidates := pool.duplicate()
	_shuffle(candidates, rng)
	var chosen: Array = []
	for pass_i in 3:
		for c: Vector2i in candidates:
			if chosen.size() >= count:
				break
			if c in chosen:
				continue
			var ok := true
			if pass_i < 2:
				for o: Vector2i in chosen:
					if absi(o.x - c.x) <= 1 and absi(o.y - c.y) <= 1:
						ok = false
						break
			if ok and pass_i == 0:
				var own := cell_plot(c.x, c.y)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if cell_plot(c.x + d.x, c.y + d.y) != own:
						ok = false
						break
			if ok:
				chosen.append(c)
	return chosen


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- Hand-edited boards (map editor) ----------------------------------------------

const CUSTOM_DIR := "res://data/boards/"


static func custom_path(board_id: String) -> String:
	return CUSTOM_DIR + board_id + ".board.json"


static func has_custom(board_id: String) -> bool:
	return board_id != "" and FileAccess.file_exists(custom_path(board_id))


## Loads an edited board, or null if there is none (or it's broken).
static func load_custom(board_id: String) -> BoardMap:
	if not has_custom(board_id):
		return null
	var f := FileAccess.open(custom_path(board_id), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or not d.has("cells"):
		push_warning("Broken edited board %s; using the generated one" % board_id)
		return null
	var site_cells: Array[Vector2i] = []
	for s in d.get("sites", []):
		site_cells.append(Vector2i(int(s[0]), int(s[1])))
	var cells := PackedInt32Array()
	for c in d.cells:
		cells.append(int(c))
	return from_cells(str(d.get("map_type", "custom")), int(d.get("map_seed", 0)), int(d.width), int(d.height),
		cells, site_cells, d.get("names", []), d.get("labels", []))


## Builds a board from a property grid and drill-site cells. Plots are numbered by their cell
## values (0..max); a plot's price is $1,000 per drill site. labels[i] = [x, y] cell where the
## property number is drawn (kept while that cell still belongs to the plot, else the centroid).
static func from_cells(type_id: String, seed_value: int, w: int, h: int, cell_data: PackedInt32Array,
		site_cells: Array[Vector2i], names: Array = [], labels: Array = []) -> BoardMap:
	var m := BoardMap.new()
	m.map_type = type_id
	m.map_seed = seed_value
	m.width = w
	m.height = h
	m.cells = cell_data.duplicate()
	var count := 0
	for c in m.cells:
		count = maxi(count, c + 1)
	var plot_cells: Array = []
	for i in count:
		plot_cells.append([])
		m.adjacency.append([])
	for y in h:
		for x in w:
			var p := m.cell_plot(x, y)
			if p < 0:
				continue
			plot_cells[p].append(Vector2i(x, y))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q := m.cell_plot(x + d.x, y + d.y)
				if q >= 0 and q != p and not (q in m.adjacency[p]):
					m.adjacency[p].append(q)
					m.adjacency[q].append(p)
	var plot_sites: Array = []
	for i in count:
		plot_sites.append([])
	var seen := {}
	for c in site_cells:
		var p := m.cell_plot(c.x, c.y)
		if p < 0 or seen.has(c):
			continue
		seen[c] = true
		plot_sites[p].append(c)
	for i in count:
		var site_ids: Array = []
		for c: Vector2i in plot_sites[i]:
			site_ids.append(m.sites.size())
			m.sites.append({"id": m.sites.size(), "plot": i, "x": c.x, "y": c.y})
		var pc: Array = plot_cells[i]
		var cx := 0.0
		var cy := 0.0
		for c: Vector2i in pc:
			cx += c.x
			cy += c.y
		var center := Vector2(cx / maxf(1.0, pc.size()) + 0.5, cy / maxf(1.0, pc.size()) + 0.5)
		if i < labels.size() and labels[i] is Array and labels[i].size() == 2 \
				and m.cell_plot(int(labels[i][0]), int(labels[i][1])) == i:
			center = Vector2(int(labels[i][0]) + 0.5, int(labels[i][1]) + 0.5)
		m.plots.append({
			"id": i,
			"name": str(names[i]) if i < names.size() else GameConst.PLOT_NAMES[i % GameConst.PLOT_NAMES.size()],
			"price": site_ids.size() * 1000,
			"sites": site_ids,
			"center_x": center.x,
			"center_y": center.y,
		})
	return m


## The editable form of this board (what the map editor saves).
func to_custom() -> Dictionary:
	var site_list: Array = []
	for s in sites:
		site_list.append([int(s.x), int(s.y)])
	var names: Array = []
	var labels: Array = []
	for p in plots:
		names.append(p.name)
		labels.append([floori(float(p.center_x)), floori(float(p.center_y))])
	return {"map_type": map_type, "map_seed": map_seed, "width": width, "height": height,
		"cells": Array(cells), "sites": site_list, "names": names, "labels": labels}


static func save_custom(board_id: String, board: BoardMap) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CUSTOM_DIR))
	var f := FileAccess.open(custom_path(board_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(board.to_custom(), "\t") + "\n")
	return true


## Problems that stop a board from being played ("" if fine): every property needs land and at
## least one drill site, and there must be enough properties for the players.
func check_playable(players: int) -> String:
	if plots.size() < players:
		return "Only %d properties for %d players" % [plots.size(), players]
	for p in plots:
		if p.sites.is_empty():
			return "Property %d (%s) has no drill sites" % [p.id + 1, p.name]
	var counts := {}
	for c in cells:
		counts[c] = counts.get(c, 0) + 1
	for p in plots:
		if not counts.has(p.id):
			return "Property %d has no land" % (p.id + 1)
	return ""


## Properties split into separate pieces (allowed, but usually a painting slip).
func split_plots() -> Array[int]:
	var out: Array[int] = []
	for p in plots:
		var start := Vector2i(-1, -1)
		var total := 0
		for y in height:
			for x in width:
				if cell_plot(x, y) == p.id:
					total += 1
					if start.x < 0:
						start = Vector2i(x, y)
		if total == 0:
			continue
		var seen := {start: true}
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := c + d
				if not seen.has(n) and cell_plot(n.x, n.y) == p.id:
					seen[n] = true
					stack.append(n)
		if seen.size() < total:
			out.append(p.id)
	return out


# --- Serialization --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"map_type": map_type, "map_seed": map_seed, "width": width, "height": height,
		"cells": cells, "plots": plots.duplicate(true), "sites": sites.duplicate(true),
		"adjacency": adjacency.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BoardMap:
	var m := BoardMap.new()
	m.map_type = d.map_type
	m.map_seed = d.map_seed
	m.width = d.width
	m.height = d.height
	m.cells = d.cells
	m.plots = d.plots.duplicate(true)
	m.sites = d.sites.duplicate(true)
	m.adjacency = d.adjacency.duplicate(true)
	return m
