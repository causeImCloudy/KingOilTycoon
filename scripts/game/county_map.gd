class_name CountyMap
extends RefCounted
## The campaign's county map: a stylized Texas cut into counties (Voronoi cells from a fixed
## seed, relaxed so they come out even), in campaign-screen pixels (640x360 layout, map area left
## of the briefing panel). Pure data, so the campaign rules can be tested headless.
## Changing SEED, COUNTY_COUNT or the outline changes every county: saved campaigns made on the
## old map are restarted (CampaignWar.from_dict checks the county count and MAP_VERSION).

const MAP_VERSION: int = 1
const SEED: int = 1938
const COUNTY_COUNT: int = 40

## Longitude/latitude to screen: x = X0 + (lon - LON0) * KX, y = Y0 + (LAT0 - lat) * KY.
const LON0: float = -106.65
const LAT0: float = 36.5
const KX: float = 24.0
const KY: float = 28.0
const X0: float = 20.0
const Y0: float = 32.0

## Simplified Texas border, clockwise from the panhandle's north-west corner (lon, lat).
const OUTLINE_LL: Array[Vector2] = [
	Vector2(-103.04, 36.50), Vector2(-100.00, 36.50), Vector2(-100.00, 34.56), Vector2(-99.40, 34.38),
	Vector2(-99.00, 34.21), Vector2(-98.50, 34.10), Vector2(-97.95, 33.88), Vector2(-97.40, 33.82),
	Vector2(-96.90, 33.95), Vector2(-96.40, 33.73), Vector2(-95.90, 33.86), Vector2(-95.30, 33.88),
	Vector2(-94.70, 33.68), Vector2(-94.04, 33.55), Vector2(-94.04, 33.00), Vector2(-94.04, 32.20),
	Vector2(-93.90, 31.80), Vector2(-93.55, 31.10), Vector2(-93.72, 30.50), Vector2(-93.84, 29.70),
	Vector2(-94.40, 29.55), Vector2(-94.90, 29.30), Vector2(-95.30, 28.95), Vector2(-95.90, 28.62),
	Vector2(-96.50, 28.35), Vector2(-96.90, 28.05), Vector2(-97.20, 27.70), Vector2(-97.40, 27.20),
	Vector2(-97.40, 26.60), Vector2(-97.15, 25.96), Vector2(-97.60, 25.95), Vector2(-98.20, 26.10),
	Vector2(-98.80, 26.35), Vector2(-99.20, 26.90), Vector2(-99.50, 27.50), Vector2(-99.90, 27.90),
	Vector2(-100.30, 28.30), Vector2(-100.65, 29.05), Vector2(-101.00, 29.55), Vector2(-101.40, 29.78),
	Vector2(-102.00, 29.80), Vector2(-102.40, 29.75), Vector2(-102.70, 29.55), Vector2(-102.90, 29.20),
	Vector2(-103.20, 28.98), Vector2(-103.60, 29.18), Vector2(-104.00, 29.40), Vector2(-104.50, 29.70),
	Vector2(-104.70, 30.20), Vector2(-105.00, 30.65), Vector2(-105.60, 31.10), Vector2(-106.20, 31.50),
	Vector2(-106.63, 31.95), Vector2(-106.62, 32.00), Vector2(-103.06, 32.00),
]
## OUTLINE_LL indices of the Gulf coast (Sabine Pass to the Rio Grande mouth): water is drawn there.
const COAST_FROM: int = 19
const COAST_TO: int = 29

## Where each campaign company starts (lon, lat): 0 = you (Rolling Plains, near the Red River), then the rivals in
## CampaignWar.RIVALS order: Hardpan (Panhandle), Dolores (Hill Country), Judge Pickett (Piney
## Woods), Ruby (Permian Basin), Blackwood (Gulf Coast).
const HOME_LL: Array[Vector2] = [
	Vector2(-99.8, 33.8), Vector2(-101.6, 35.4), Vector2(-99.4, 30.9),
	Vector2(-94.7, 32.0), Vector2(-102.5, 31.5), Vector2(-95.5, 29.6),
]

## Made-up county names (not real Texas counties).
const NAMES: Array[String] = [
	"Mesquite", "Coyote", "Caliche", "Buzzard Flat", "Tumbleweed", "Lariat", "Ocotillo", "Bluebonnet",
	"Pecan Bend", "Red Mesa", "Cottonmouth", "Spur", "Horned Toad", "Saddlehorn", "Agave", "Juniper",
	"Wildcat", "Dry Fork", "Sagebrush", "Cholla", "Rattler", "Longhorn", "Prickly Pear", "Javelina",
	"Roadrunner", "Bandera Gap", "Whiskey Creek", "Silver Sage", "Cattail", "Oxbow", "Bois d'Arc",
	"Turkey Neck", "Cap Rock", "Hackberry", "Tin Cup", "Copper Bluff", "Lone Pine", "Gallows Hill",
	"Pinto", "Stockade",
]

var outline: PackedVector2Array = PackedVector2Array()
## Gulf coast points, Sabine Pass first.
var coast: PackedVector2Array = PackedVector2Array()
var polys: Array[PackedVector2Array] = []
## A point inside each county for its icons and labels.
var centers: Array[Vector2] = []
## neighbors[c] = counties sharing a border with c.
var neighbors: Array = []
var names: Array[String] = []
## homes[company] = that company's starting county (0 = you, 1-5 = rivals).
var homes: Array[int] = []
## hops[a][b] = counties crossed to get from a to b.
var hops: Array = []

static var _cached: CountyMap = null


## The campaign map (built once, then shared).
static func get_map() -> CountyMap:
	if _cached == null:
		_cached = generate()
	return _cached


static func to_screen(ll: Vector2) -> Vector2:
	return Vector2(X0 + (ll.x - LON0) * KX, Y0 + (LAT0 - ll.y) * KY)


static func generate() -> CountyMap:
	var m := CountyMap.new()
	for ll in OUTLINE_LL:
		m.outline.append(to_screen(ll))
	for i in range(COAST_FROM, COAST_TO + 1):
		m.coast.append(m.outline[i])
	var bounds := _bounds(m.outline).grow(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Spread-out seed points inside the state, then a few rounds of Lloyd relaxation.
	var min_d := sqrt(absf(_area(m.outline)) / COUNTY_COUNT) * 0.8
	var seeds: Array[Vector2] = []
	var tries := 0
	while seeds.size() < COUNTY_COUNT:
		tries += 1
		if tries % 3000 == 0:
			min_d *= 0.92
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		if not Geometry2D.is_point_in_polygon(p, m.outline):
			continue
		var ok := true
		for s in seeds:
			if s.distance_to(p) < min_d:
				ok = false
				break
		if ok:
			seeds.append(p)
	for _it in 5:
		for i in seeds.size():
			var cell := _clip_to_state(_cell(seeds, i, bounds), m.outline)
			if cell.size() >= 3:
				var c := _centroid(cell)
				if Geometry2D.is_point_in_polygon(c, m.outline):
					seeds[i] = c
	for i in seeds.size():
		m.polys.append(_clip_to_state(_cell(seeds, i, bounds), m.outline))
		var c := _centroid(m.polys[i]) if m.polys[i].size() >= 3 else seeds[i]
		m.centers.append(c if Geometry2D.is_point_in_polygon(c, m.polys[i]) else seeds[i])
		m.names.append(NAMES[i % NAMES.size()])
	# Neighbors: two counties touch if cell i has two vertices on the line halfway between them.
	for i in seeds.size():
		m.neighbors.append([])
	for i in seeds.size():
		for j in range(i + 1, seeds.size()):
			var on_line: Array[Vector2] = []
			for v in m.polys[i]:
				if absf(v.distance_to(seeds[i]) - v.distance_to(seeds[j])) < 0.1:
					if on_line.is_empty() or on_line[0].distance_to(v) > 0.5:
						on_line.append(v)
			if on_line.size() >= 2:
				m.neighbors[i].append(j)
				m.neighbors[j].append(i)
	for i in seeds.size():
		m.hops.append(m._bfs(i))
	for ll in HOME_LL:
		var at := to_screen(ll)
		var best := -1
		for c in seeds.size():
			if c in m.homes:
				continue
			if best < 0 or m.centers[c].distance_to(at) < m.centers[best].distance_to(at):
				best = c
		m.homes.append(best)
	return m


func count() -> int:
	return polys.size()


## The county under a screen point, or -1.
func county_at(p: Vector2) -> int:
	for c in polys.size():
		if polys[c].size() >= 3 and Geometry2D.is_point_in_polygon(p, polys[c]):
			return c
	return -1


func _bfs(from: int) -> Array[int]:
	var dist: Array[int] = []
	dist.resize(polys.size())
	dist.fill(999)
	dist[from] = 0
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for n in neighbors[c]:
			if dist[n] > dist[c] + 1:
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


# --- Geometry ------------------------------------------------------------------------------------

## Voronoi cell of seed i: the bounds, cut by the half-plane nearer i than each other seed.
static func _cell(seeds: Array[Vector2], i: int, bounds: Rect2) -> PackedVector2Array:
	var poly := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	for j in seeds.size():
		if j != i:
			poly = _clip_half(poly, (seeds[i] + seeds[j]) * 0.5, seeds[j] - seeds[i])
			if poly.size() < 3:
				break
	return poly


## Keeps the part of a convex polygon where (p - at) . normal <= 0.
static func _clip_half(poly: PackedVector2Array, at: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var da := (a - at).dot(normal)
		var db := (b - at).dot(normal)
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## The largest piece of a cell inside the state outline.
static func _clip_to_state(cell: PackedVector2Array, outline: PackedVector2Array) -> PackedVector2Array:
	if cell.size() < 3:
		return PackedVector2Array()
	var best := PackedVector2Array()
	var best_area := 0.0
	for piece in Geometry2D.intersect_polygons(cell, outline):
		var a := absf(_area(piece))
		if a > best_area:
			best_area = a
			best = piece
	return best


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var a := _area(poly)
	if absf(a) < 0.001:
		return poly[0]
	var c := Vector2.ZERO
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var cross := p.x * q.y - q.x * p.y
		c += (p + q) * cross
	return c / (6.0 * a)


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
