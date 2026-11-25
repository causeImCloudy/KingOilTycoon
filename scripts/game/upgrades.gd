class_name Upgrades
extends RefCounted
## Campaign-only upgrades bought with campaign dollars (CampaignWar.dollars). They never apply outside the campaign.
## Each maps to a GameState player mod (see GameState.DEFAULT_MODS).

const DEFS: Array = [
	{"id": "yield", "name": "Better Pumps", "desc": "+10% income from every producing well.",
		"mod": "yield", "per_level": 0.10, "costs": [20000, 40000, 70000, 110000, 160000]},
	{"id": "drill_discount", "name": "Sharper Bits", "desc": "Drilling costs 5% less.",
		"mod": "drill_discount", "per_level": 0.05, "costs": [15000, 30000, 55000, 90000, 130000]},
	{"id": "royalty", "name": "Pipeline Valves", "desc": "+10% royalties from your pipelines.",
		"mod": "royalty", "per_level": 0.10, "costs": [25000, 50000, 85000, 125000, 175000]},
	{"id": "fire_resist", "name": "Fire Crews", "desc": "15% chance per well to stop a Blowout Fire.",
		"mod": "fire_resist", "per_level": 0.15, "costs": [20000, 40000, 65000, 100000]},
	{"id": "start_bonus", "name": "Bank Credit", "desc": "Start each campaign battle with $5,000 more.",
		"mod": "start_bonus", "per_level": 5000, "costs": [15000, 30000, 55000, 90000, 130000]},
]


static func get_def(id: String) -> Dictionary:
	for d in DEFS:
		if d.id == id:
			return d
	return {}


static func next_cost(id: String, level: int) -> int:
	var d := get_def(id)
	if d.is_empty() or level >= d.costs.size():
		return -1
	return d.costs[level]


## Converts upgrade levels ({id: level}) into GameState mods.
static func mods_for(levels: Dictionary) -> Dictionary:
	var mods := {}
	for d in DEFS:
		var lv: int = levels.get(d.id, 0)
		if lv <= 0:
			continue
		match d.mod:
			"yield", "royalty":
				mods[d.mod] = 1.0 + lv * float(d.per_level)
			"drill_discount", "fire_resist":
				mods[d.mod] = lv * float(d.per_level)
			"start_bonus":
				mods[d.mod] = lv * int(d.per_level)
	return mods
