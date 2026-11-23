extends Node
## Scene routing and the match being set up or played.

const SCENES: Dictionary = {
	"menu": "res://scenes/ui/main_menu.tscn",
	"setup": "res://scenes/ui/match_setup.tscn",
	"campaign": "res://scenes/ui/campaign.tscn",
	"shop": "res://scenes/ui/shop.tscn",
	"lobby": "res://scenes/ui/lobby.tscn",
	"settings": "res://scenes/ui/settings.tscn",
	"match": "res://scenes/board/match.tscn",
	"board_editor": "res://scenes/ui/board_editor.tscn",
}

const SAVE_PATH := "user://savegame.save"

## Settings passed to GameState.new_match().
var match_config: Dictionary = {}
## "offline", "host" or "client".
var net_mode: String = "offline"
## Campaign map index being played, or -1.
var campaign_index: int = -1
## A saved or received state to resume instead of starting fresh.
var resume_state: Dictionary = {}
var campaign: Dictionary = {}
## Customize & Store screen: "edit" normally, "create" for first-time character creation.
var customize_mode: String = "edit"
## General Store: which tab to open and where its Back button goes.
var shop_tab: String = "tycoon"
var shop_return: String = "menu"


## Opens the General Store on a tab; Back returns to `from`.
func open_shop(tab: String, from: String) -> void:
	shop_tab = tab
	shop_return = from
	goto("shop")


func _ready() -> void:
	get_tree().root.theme = UiKit.get_theme()
	var f := FileAccess.open("res://data/campaign.json", FileAccess.READ)
	if f:
		campaign = JSON.parse_string(f.get_as_text())


func goto(scene_id: String) -> void:
	get_tree().change_scene_to_file.call_deferred(SCENES[scene_id])


func start_offline(config: Dictionary, campaign_map: int = -1) -> void:
	match_config = config
	net_mode = "offline"
	campaign_index = campaign_map
	resume_state = {}
	goto("match")


func resume_saved() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = f.get_var()
	if not (d is Dictionary and d.has("state")):
		return false
	resume_state = d.state
	campaign_index = d.get("campaign_index", -1)
	match_config = {}
	net_mode = "offline"
	goto("match")
	return true


func save_game(state: GameState) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_var({"state": state.to_dict(true), "campaign_index": campaign_index})


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Builds a GameState config for campaign map i.
func campaign_config(i: int) -> Dictionary:
	var m: Dictionary = campaign.maps[i]
	var players: Array = [{
		"name": Profile.data.name, "is_ai": false, "character": Profile.look(),
		"mods": Profile.campaign_mods(), "color": 0,
	}]
	for r in m.rivals.size():
		var rival: Dictionary = campaign.rivals[m.rivals[r]]
		players.append({
			"name": rival.name, "is_ai": true, "ai_level": int(m.ai_levels[r]),
			"character": Cosmetics.complete_look(rival.look, hash(str(m.rivals[r]))), "color": r + 1, "rival": m.rivals[r],
		})
	# The level's seed fixes its board (its saved decoration fits that board); oil, deck, draft
	# order and the AI get a fresh random seed every attempt.
	return {"seed": 0, "board_seed": int(m.seed), "map_type": m.map_type, "speed": m.speed, "players": players, "campaign": true,
		"board_id": "level_%02d" % (i + 1)}
