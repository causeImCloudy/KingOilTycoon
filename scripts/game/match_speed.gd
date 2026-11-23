class_name MatchSpeed
extends Resource
## Match-length preset (like a game-speed setting). Tune values in data/match_speeds/*.tres.

@export var id: String = "classic"
@export var display_name: String = "Classic"
@export_multiline var description: String = ""
## Total money in the bank. The game ends when the bank runs dry, so this is the main pacing lever.
@export var bank_size: int = 1_000_000
@export var starting_cash: int = 80_000
## Multiplier on card income per well.
@export var income_mult: float = 1.0
## Multiplier on drilling costs.
@export var drill_cost_mult: float = 1.0
## Extra wells allowed per production card (added to the card's value). Keep at 0: the rule is
## "drill up to the number on the card".
@export var bonus_drills: int = 0
## Cost per pipeline level.
@export var pipeline_cost: int = 10_000
## Royalty per derrick (producing well) on the property piped into, per pipeline level, each turn.
@export var royalty_per_well: int = 1000
## Approximate total turns before the game is decided on net worth (0 = no cap).
## Converted to a round cap based on player count.
@export var target_turns: int = 0
## Online turn timer in seconds (0 = none).
@export var turn_timer_sec: int = 0
## Default animation speed multiplier for this preset.
@export var anim_speed: float = 1.0

const SPEED_IDS: Array[String] = ["classic", "online", "blitz"]


static func load_by_id(speed_id: String) -> MatchSpeed:
	var path := "res://data/match_speeds/%s.tres" % speed_id
	if ResourceLoader.exists(path):
		return load(path) as MatchSpeed
	push_warning("Unknown match speed '%s', using classic" % speed_id)
	return load("res://data/match_speeds/classic.tres") as MatchSpeed


static func load_all() -> Array[MatchSpeed]:
	var out: Array[MatchSpeed] = []
	for sid in SPEED_IDS:
		out.append(load_by_id(sid))
	return out


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"bank_size": bank_size,
		"starting_cash": starting_cash,
		"income_mult": income_mult,
		"drill_cost_mult": drill_cost_mult,
		"bonus_drills": bonus_drills,
		"pipeline_cost": pipeline_cost,
		"royalty_per_well": royalty_per_well,
		"target_turns": target_turns,
		"turn_timer_sec": turn_timer_sec,
		"anim_speed": anim_speed,
	}
