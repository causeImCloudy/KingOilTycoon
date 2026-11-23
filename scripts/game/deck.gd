class_name Deck
extends RefCounted
## Builds the 32-card Wildcat-style deck. Card text is original to this game.
##
## Card dict: {id, kind: "production"|"depletion"|"fire", rate, wells, land, title, text}

const KIND_PRODUCTION: String = "production"
const KIND_DEPLETION: String = "depletion"
const KIND_FIRE: String = "fire"

## [max wells to drill, income per well, total cards, cards with land for sale]
const PRODUCTION_TABLE: Array = [
	[1, 1000, 1, 1], [1, 2000, 1, 1], [1, 3000, 1, 0], [1, 4000, 1, 0],
	[2, 500, 5, 2], [2, 1000, 1, 1], [2, 2000, 1, 0], [2, 3000, 1, 0], [2, 4000, 1, 0],
	[3, 500, 1, 0], [3, 1000, 1, 1], [3, 2000, 2, 0], [3, 3000, 1, 0], [3, 4000, 1, 0],
	[4, 500, 2, 1], [4, 2000, 2, 0], [4, 3000, 1, 0], [4, 4000, 1, 0],
]
const DEPLETION_COUNT: int = 5
const FIRE_COUNT: int = 2
const DEPLETION_BONUS: int = 500

const PRODUCTION_TITLES: Dictionary = {
	500: "Slow Week at the Pumps",
	1000: "Steady Crude",
	2000: "Good Pressure",
	3000: "Boom Times",
	4000: "Gusher Season",
}


static func build(original_rules: bool = false) -> Array:
	var cards: Array = []
	for row in PRODUCTION_TABLE:
		for i in int(row[2]):
			var land: bool = i < int(row[3])
			cards.append({
				"id": cards.size(), "kind": KIND_PRODUCTION, "rate": row[1], "wells": row[0], "land": land,
				"title": PRODUCTION_TITLES[row[1]],
				"text": "$%s per well.\nDrill up to %d.%s" % [_money(row[1]), row[0], "\nLand for sale!" if land else ""],
			})
	for i in DEPLETION_COUNT:
		cards.append({
			"id": cards.size(), "kind": KIND_DEPLETION, "rate": 0, "wells": 1, "land": false,
			"title": "Depletion Allowance",
			"text": "Tax break:\ncollect $500.\nDrill 1 well.",
		})
	for i in FIRE_COUNT:
		cards.append({
			"id": cards.size(), "kind": KIND_FIRE, "rate": 0, "wells": 0, "land": false,
			"title": "Blowout Fire!",
			"text": "Cap 1 well (1-5),\n2 (6-10) or 3\n(11+ wells)." if original_rules else "Pick 1 well per\n5 you own to cap.",
		})
	return cards


static func _money(v: int) -> String:
	var s := str(v)
	if v >= 1000:
		s = "%d,%03d" % [v / 1000, v % 1000]
	return s
