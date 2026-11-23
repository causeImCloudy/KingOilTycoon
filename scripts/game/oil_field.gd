class_name OilField
extends RefCounted
## Hidden oil: three stacked strata (shallow, medium, deep). A drill hits the first
## stratum that holds oil at that cell; if none do, the hole is dry.
##
## Procedural fields grow oil "pools" per stratum from the match seed.
## The Classic map uses three fixed strata patterns that are each slid to one of
## 12 notches at match start (12^3 = 1,728 boards), like rotating board discs.

const LAYERS: int = 3
const NOTCHES: int = 12
## Target fraction of cells holding oil in each stratum (shallow, medium, deep).
const DENSITY: Array[float] = [0.14, 0.17, 0.21]

var width: int = 0
var height: int = 0
var layers: Array = [] # Array of PackedByteArray, 1 = oil
var notches: Array[int] = [0, 0, 0]


func depth_at(x: int, y: int) -> int:
	for l in LAYERS:
		if layers[l][y * width + x] == 1:
			return l
	return GameConst.DEPTH_DRY


static func create(board: BoardMap, rng: RandomNumberGenerator) -> OilField:
	var f := OilField.new()
	f.width = board.width
	f.height = board.height
	if board.map_type in ["classic", "classic_1974"]:
		var base_rng := RandomNumberGenerator.new()
		base_rng.seed = BoardMap.CLASSIC_SEED * 31 + 7
		var base := _grow_layers(f.width, f.height, base_rng)
		for l in LAYERS:
			f.notches[l] = rng.randi_range(0, NOTCHES - 1)
			f.layers.append(_shift(base[l], f.width, f.height, roundi(f.notches[l] * f.width / float(NOTCHES))))
	else:
		f.layers = _grow_layers(f.width, f.height, rng)
	return f


static func _grow_layers(w: int, h: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for l in LAYERS:
		var layer := PackedByteArray()
		layer.resize(w * h)
		var target := int(DENSITY[l] * w * h)
		var filled := 0
		var guard := 0
		while filled < target and guard < 500:
			guard += 1
			var cx := rng.randf_range(0, w)
			var cy := rng.randf_range(0, h)
			var r := rng.randf_range(1.2, 3.2)
			var stretch := rng.randf_range(0.6, 1.6)
			for y in range(maxi(0, int(cy - r - 2)), mini(h, int(cy + r + 2))):
				for x in range(maxi(0, int(cx - r * stretch - 2)), mini(w, int(cx + r * stretch + 2))):
					var dx := (x + 0.5 - cx) / stretch
					var dy := y + 0.5 - cy
					var edge := r + rng.randf_range(-0.6, 0.6)
					if dx * dx + dy * dy <= edge * edge and layer[y * w + x] == 0:
						layer[y * w + x] = 1
						filled += 1
		out.append(layer)
	return out


static func _shift(layer: PackedByteArray, w: int, h: int, dx: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			out[y * w + posmod(x + dx, w)] = layer[y * w + x]
	return out


func to_dict() -> Dictionary:
	return {"width": width, "height": height, "layers": layers.duplicate(true), "notches": notches.duplicate()}


static func from_dict(d: Dictionary) -> OilField:
	var f := OilField.new()
	f.width = d.width
	f.height = d.height
	f.layers = d.layers.duplicate(true)
	f.notches.assign(d.notches)
	return f
