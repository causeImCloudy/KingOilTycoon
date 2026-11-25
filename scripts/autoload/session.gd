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
## Campaign level (campaign.json maps) the county being played uses, or -1: picks its saved
## board decoration and art.
var campaign_index: int = -1
## Campaign county being fought over, or -1 outside the campaign.
var campaign_county: int = -1
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


func start_offline(config: Dictionary, county: int = -1) -> void:
	match_config = config
	net_mode = "offline"
	campaign_county = county
	campaign_index = int(battle_def(county).level) if county >= 0 else -1
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
	campaign_county = int(d.get("campaign_county", -1))
	campaign_index = int(battle_def(campaign_county).level) if campaign_county >= 0 else -1
	match_config = {}
	net_mode = "offline"
	goto("match")
	return true


func save_game(state: GameState) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_var({"state": state.to_dict(true), "campaign_county": campaign_county})


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## A campaign county's battle: {county, level (campaign.json map or -1), title, intro, background,
## board_theme, speed, map_type, board_seed, board_players, reward, unlocks, rivals (company
## numbers), ai_levels}. Counties with a level use its story, art and board; the rest are generated.
func battle_def(county: int) -> Dictionary:
	var w := Profile.war()
	var opp := w.opponents(county)
	var d := {"county": county, "level": w.level_of[county], "rivals": opp,
		"ai_levels": opp.map(func(r): return w.ai_level(r, county)),
		"title": "%s County" % w.map.names[county], "background": "", "board_theme": _nearest_theme(county),
		"speed": "blitz" if opp.size() <= 1 else "online", "map_type": "procedural",
		"board_seed": 5000 + county, "board_players": opp.size() + 1, "reward": 40, "unlocks": []}
	var owner := w.owner[county]
	var names := PackedStringArray(opp.map(func(r): return str(rival_def(r).get("short", ""))))
	var who := " and ".join(names)
	if owner > 0:
		d.intro = "%s holds %s County. Take it and they pay you what it's worth." % [rival_def(owner).get("name", ""), w.map.names[county]]
	else:
		d.intro = "Open range in %s County, and %s %s it too." % [w.map.names[county], who, "wants" if names.size() == 1 else "want"]
	if int(d.level) >= 0:
		var m: Dictionary = campaign.maps[int(d.level)]
		d.title = m.title
		d.intro = m.intro
		d.background = m.get("background", "")
		d.board_theme = m.get("board_theme", "farm")
		d.speed = m.speed
		d.map_type = m.map_type
		d.board_seed = int(m.seed)
		# The level's saved board decoration fits the board it was made for (big boards above 4 players).
		d.board_players = maxi(opp.size(), (m.rivals as Array).size()) + 1
		d.reward = int(m.reward)
		d.unlocks = m.get("unlocks", [])
	return d


## campaign.json rival data for a company number (1-5), or {}.
func rival_def(company: int) -> Dictionary:
	if company < 1 or company > CampaignWar.RIVALS.size():
		return {}
	return campaign.rivals.get(CampaignWar.RIVALS[company - 1], {})


## Generated counties borrow the board look of the nearest county with a level.
func _nearest_theme(county: int) -> String:
	var w := Profile.war()
	var best := -1
	for c in w.map.count():
		if w.level_of[c] >= 0 and (best < 0 or w.map.hops[county][c] < w.map.hops[county][best]):
			best = c
	return str(campaign.maps[w.level_of[best]].get("board_theme", "farm")) if best >= 0 else "farm"


## Builds a GameState config for a campaign county battle.
func campaign_config(county: int) -> Dictionary:
	var d := battle_def(county)
	var players: Array = [{
		"name": Profile.data.name, "is_ai": false, "character": Profile.look(),
		"mods": Profile.campaign_mods(), "color": 0,
	}]
	for k in (d.rivals as Array).size():
		var r: int = d.rivals[k]
		var id: String = CampaignWar.RIVALS[r - 1]
		var rival: Dictionary = rival_def(r)
		# Each rival keeps their map color (company number) in every battle.
		players.append({
			"name": rival.name, "is_ai": true, "ai_level": int(d.ai_levels[k]),
			"character": Cosmetics.complete_look(rival.look, hash(id)), "color": r, "rival": id,
		})
	# The board seed fixes the board (a level's saved decoration fits it); oil, deck, draft order
	# and the AI get a fresh random seed every attempt.
	var cfg := {"seed": 0, "board_seed": int(d.board_seed), "board_players": int(d.board_players), "map_type": d.map_type,
		"speed": d.speed, "players": players, "campaign": true}
	if int(d.level) >= 0:
		cfg.board_id = "level_%02d" % (int(d.level) + 1)
	return cfg
