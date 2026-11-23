class_name Cosmetics
extends RefCounted
## Character, derrick and homestead customization options. Each option has an id and a Liquid Gold price.
## Ids in STARTER are free from the start (price 0). Everything else can be bought in the
## General Store; some are also campaign rewards (data/campaign.json "unlocks") and come free
## with that win.

const TYCOONS: Array = [
	{"id": "tycoon_classic", "name": "Man", "face": "face", "price": 0},
	{"id": "tycoon_bob", "name": "Woman (bob)", "face": "face_bob", "price": 0},
	{"id": "tycoon_braid", "name": "Woman (braid)", "face": "face_braid", "price": 0},
]

const SKINS: Array = [
	{"id": "skin_1", "name": "Fair", "color": Color("f2d0b0"), "price": 0},
	{"id": "skin_2", "name": "Light", "color": Color("e0b48a"), "price": 0},
	{"id": "skin_3", "name": "Tan", "color": Color("c48c5e"), "price": 0},
	{"id": "skin_4", "name": "Bronze", "color": Color("a06a42"), "price": 0},
	{"id": "skin_5", "name": "Brown", "color": Color("7a4b2e"), "price": 0},
	{"id": "skin_6", "name": "Deep", "color": Color("553420"), "price": 0},
]

const OUTFITS: Array = [
	{"id": "outfit_denim", "name": "Denim Blue", "color": Color("2f5d8a"), "price": 0},
	{"id": "outfit_khaki", "name": "Khaki", "color": Color("b5a271"), "price": 0},
	{"id": "outfit_brown", "name": "Saddle Brown", "color": Color("7a4e2a"), "price": 0},
	{"id": "outfit_red", "name": "Rodeo Red", "color": Color("b0322a"), "price": 40},
	{"id": "outfit_sand", "name": "Desert Sand", "color": Color("d8c090"), "price": 40},
	{"id": "outfit_mustard", "name": "Mustard Gold", "color": Color("c89a2a"), "price": 45},
	{"id": "outfit_black", "name": "Undertaker", "color": Color("2b2624"), "price": 50},
	{"id": "outfit_green", "name": "Money Green", "color": Color("3e7a4c"), "price": 50},
	{"id": "outfit_grey", "name": "Charcoal", "color": Color("4a4a4e"), "price": 50},
	{"id": "outfit_white", "name": "Banker White", "color": Color("e8e2d2"), "price": 60},
	{"id": "outfit_navy", "name": "Pinstripe Navy", "color": Color("2a3a5a"), "price": 60},
	{"id": "outfit_purple", "name": "Oil Baron Plum", "color": Color("6a3d7a"), "price": 90},
]

## "style" picks the hat art: assets/sprites/character/hat_<style>.png and portrait_hat_<style>.png.
const HATS: Array = [
	{"id": "hat_none", "name": "Bare Head", "style": "none", "price": 0},
	{"id": "hat_stetson", "name": "Stetson", "style": "stetson", "price": 0},
	{"id": "hat_hardhat", "name": "Hard Hat", "style": "hardhat", "price": 50},
	{"id": "hat_flatcap", "name": "Flat Cap", "style": "flatcap", "price": 70},
	{"id": "hat_derby", "name": "Derby", "style": "derby", "price": 80},
	{"id": "hat_tengallon", "name": "Ten-Gallon", "style": "tengallon", "price": 120},
	{"id": "hat_tophat", "name": "Top Hat", "style": "tophat", "price": 150},
]

const HAT_COLORS: Array = [
	{"id": "hatc_cream", "name": "Cream", "color": Color("e8dcc0"), "price": 0},
	{"id": "hatc_tan", "name": "Tan", "color": Color("b98a57"), "price": 0},
	{"id": "hatc_black", "name": "Black", "color": Color("2b2624"), "price": 0},
	{"id": "hatc_brown", "name": "Brown", "color": Color("6a4426"), "price": 25},
	{"id": "hatc_tin", "name": "Tin", "color": Color("b8bec4"), "price": 30},
	{"id": "hatc_mustard", "name": "Mustard", "color": Color("e0a826"), "price": 30},
	{"id": "hatc_red", "name": "Rodeo Red", "color": Color("b0322a"), "price": 30},
	{"id": "hatc_navy", "name": "Navy", "color": Color("2a3a5a"), "price": 30},
	{"id": "hatc_white", "name": "White", "color": Color("f4f1ea"), "price": 35},
	{"id": "hatc_silver", "name": "Silver Belly", "color": Color("d0d4d8"), "price": 45},
]

## Building paint: tint for derricks and the drill rig.
const DERRICK_PAINTS: Array = [
	{"id": "paint_plain", "name": "Weathered Wood", "color": Color("ffffff"), "price": 0},
	{"id": "paint_rust", "name": "Rust Red", "color": Color("e09a7a"), "price": 40},
	{"id": "paint_steel", "name": "Gunmetal", "color": Color("a8b4c0"), "price": 60},
	{"id": "paint_patina", "name": "Patina Green", "color": Color("9ad0b0"), "price": 70},
	{"id": "paint_navy", "name": "Navy Blue", "color": Color("8aa0d0"), "price": 70},
	{"id": "paint_candy", "name": "Candy Red", "color": Color("ff8a80"), "price": 70},
	{"id": "paint_black", "name": "Tar Black", "color": Color("7a7470"), "price": 80},
	{"id": "paint_chrome", "name": "Chrome", "color": Color("e4ecf4"), "price": 90},
	{"id": "paint_gold", "name": "Gilded", "color": Color("ffe08a"), "price": 150},
]

## Homestead: the house on your first property and the small outbuilding on each one after it.
## "style" picks the art: assets/sprites/homestead/house_<style>.png / outbuilding_<style>.png.
const HOUSES: Array = [
	{"id": "house_farmhouse", "name": "Farmhouse", "style": "farmhouse", "price": 0},
	{"id": "house_cabin", "name": "Log Cabin", "style": "cabin", "price": 0},
	{"id": "house_ranch", "name": "Ranch", "style": "ranch", "price": 60},
	{"id": "house_adobe", "name": "Hacienda", "style": "adobe", "price": 80},
	{"id": "house_victorian", "name": "Victorian", "style": "victorian", "price": 120},
	{"id": "house_mansion", "name": "Mansion", "style": "mansion", "price": 200},
]

const OUTBUILDINGS: Array = [
	{"id": "outb_shed", "name": "Tool Shed", "style": "shed", "price": 0},
	{"id": "outb_barn", "name": "Barn", "style": "barn", "price": 0},
	{"id": "outb_silo", "name": "Grain Silo", "style": "silo", "price": 40},
	{"id": "outb_bunkhouse", "name": "Bunkhouse", "style": "bunkhouse", "price": 60},
	{"id": "outb_windmill", "name": "Windmill", "style": "windmill", "price": 60},
	{"id": "outb_office", "name": "Office", "style": "office", "price": 80},
]

## Wall color for the house and outbuildings (tints the greyscale walls layer).
const SIDINGS: Array = [
	{"id": "siding_white", "name": "Whitewash", "color": Color("f4f1ea"), "price": 0},
	{"id": "siding_red", "name": "Barn Red", "color": Color("b5483a"), "price": 0},
	{"id": "siding_grey", "name": "Weathered", "color": Color("a8a49c"), "price": 0},
	{"id": "siding_yellow", "name": "Buttercup", "color": Color("ecd27a"), "price": 30},
	{"id": "siding_sage", "name": "Sage", "color": Color("a6b88e"), "price": 30},
	{"id": "siding_blue", "name": "Sky Blue", "color": Color("9cc0dc"), "price": 30},
	{"id": "siding_clay", "name": "Adobe Clay", "color": Color("d49a6a"), "price": 40},
	{"id": "siding_mint", "name": "Mint", "color": Color("b4e0c8"), "price": 40},
	{"id": "siding_brick", "name": "Brick", "color": Color("9a4a34"), "price": 50},
	{"id": "siding_plum", "name": "Plum", "color": Color("9a6aa8"), "price": 60},
]

## Roof color for the house and outbuildings (tints the greyscale roof layer).
const ROOFS: Array = [
	{"id": "roof_tin", "name": "Tin", "color": Color("b8bec4"), "price": 0},
	{"id": "roof_cedar", "name": "Cedar", "color": Color("8a5a36"), "price": 0},
	{"id": "roof_slate", "name": "Slate", "color": Color("5a6068"), "price": 0},
	{"id": "roof_tile", "name": "Red Tile", "color": Color("c0583a"), "price": 30},
	{"id": "roof_green", "name": "Green", "color": Color("4a7a4a"), "price": 30},
	{"id": "roof_tar", "name": "Tar Black", "color": Color("3a3634"), "price": 30},
	{"id": "roof_copper", "name": "Copper", "color": Color("d08850"), "price": 60},
	{"id": "roof_gold", "name": "Gilded", "color": Color("f2c14e"), "price": 150},
]

const STARTER: Array[String] = [
	"tycoon_classic", "tycoon_bob", "tycoon_braid",
	"skin_1", "skin_2", "skin_3", "skin_4", "skin_5", "skin_6",
	"outfit_denim", "outfit_khaki", "outfit_brown",
	"hat_none", "hat_stetson",
	"hatc_cream", "hatc_tan", "hatc_black",
	"paint_plain",
	"house_farmhouse", "house_cabin", "outb_shed", "outb_barn",
	"siding_white", "siding_red", "siding_grey", "roof_tin", "roof_cedar", "roof_slate",
]

const CATEGORIES: Dictionary = {
	"tycoon": TYCOONS,
	"skin": SKINS, "outfit": OUTFITS, "hat": HATS, "hat_color": HAT_COLORS, "paint": DERRICK_PAINTS,
	"house": HOUSES, "outbuilding": OUTBUILDINGS, "siding": SIDINGS, "roof": ROOFS,
}

const DEFAULT_LOOK: Dictionary = {
	"tycoon": "tycoon_classic",
	"skin": "skin_2", "outfit": "outfit_denim", "hat": "hat_stetson", "hat_color": "hatc_cream", "paint": "paint_plain",
	"house": "house_farmhouse", "outbuilding": "outb_barn", "siding": "siding_white", "roof": "roof_tin",
}


static func find(category: String, id: String) -> Dictionary:
	for o in CATEGORIES.get(category, []):
		if o.id == id:
			return o
	var list: Array = CATEGORIES.get(category, [])
	return list[0] if list.size() > 0 else {}


## The category an option id belongs to ("" if unknown).
static func category_of(id: String) -> String:
	for cat in CATEGORIES:
		for o in CATEGORIES[cat]:
			if o.id == id:
				return cat
	return ""


static func name_of(id: String) -> String:
	for cat in CATEGORIES.values():
		for o in cat:
			if o.id == id:
				return o.name
	return id


## Liquid Gold price in the General Store (0 = free starter, -1 = unknown id).
static func price_of(id: String) -> int:
	if id in STARTER:
		return 0
	var cat := category_of(id)
	if cat == "":
		return -1
	return int(find(cat, id).get("price", 0))


## Random look for AI rivals.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"skin": SKINS[rng.randi_range(0, SKINS.size() - 1)].id,
		"outfit": OUTFITS[rng.randi_range(0, OUTFITS.size() - 1)].id,
		"hat": HATS[rng.randi_range(1, HATS.size() - 1)].id,
		"hat_color": HAT_COLORS[rng.randi_range(0, HAT_COLORS.size() - 1)].id,
		"paint": DERRICK_PAINTS[rng.randi_range(0, DERRICK_PAINTS.size() - 1)].id,
		"house": HOUSES[rng.randi_range(0, HOUSES.size() - 1)].id,
		"outbuilding": OUTBUILDINGS[rng.randi_range(0, OUTBUILDINGS.size() - 1)].id,
		"siding": SIDINGS[rng.randi_range(0, SIDINGS.size() - 1)].id,
		"roof": ROOFS[rng.randi_range(0, ROOFS.size() - 1)].id,
		"tycoon": TYCOONS[rng.randi_range(0, TYCOONS.size() - 1)].id,
	}


## Fills in look keys a saved or hand-written look is missing (campaign rivals predate the
## homestead), picking them from a seed so the same rival always gets the same buildings.
static func complete_look(look: Dictionary, seed_value: int) -> Dictionary:
	var out := look.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var extra := random_look(rng)
	for k in DEFAULT_LOOK:
		if not out.has(k):
			out[k] = DEFAULT_LOOK[k] if k == "tycoon" else extra[k]
	return out
