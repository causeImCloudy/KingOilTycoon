extends Node
## Persistent player profile: Liquid Gold, upgrades, cosmetics, campaign progress, settings.
## Saved to user://profile.save.

signal changed

const PATH := "user://profile.save"

var data: Dictionary = {}


func _ready() -> void:
	load_profile()
	apply_settings()


func defaults() -> Dictionary:
	return {
		"version": 1,
		"name": "Player",
		"liquid_gold": 0,
		"upgrades": {},
		"unlocked": [],
		"look": Cosmetics.DEFAULT_LOOK.duplicate(),
		"campaign_done": [],
		# Set once the player finishes character creation before their first campaign map.
		"character_created": false,
		"settings": {
			"anim_speed": 1.0, "sfx": 0.8, "music": 0.6, "fullscreen": false,
			# "fill" stretches to any window/screen; "pixel" keeps whole-number pixel scaling.
			"scaling": "fill",
			# 0 normal, 1 large, 2 extra large (see UiKit.SIZE_MAPS).
			"text_size": 1,
			# Smooth (antialiased) text reads better at in-between window sizes.
			"smooth_text": true,
		},
	}


func load_profile() -> void:
	data = defaults()
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var loaded = f.get_var()
		if loaded is Dictionary:
			data.merge(loaded, true)
			var s: Dictionary = defaults().settings
			s.merge(data.settings, true)
			data.settings = s


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_var(data)
	changed.emit()


func apply_settings() -> void:
	var s: Dictionary = data.settings
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if bool(s.fullscreen) != is_full:
		DisplayServer.window_set_mode(want)
	get_tree().root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if s.scaling == "pixel" 		else Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func toggle_fullscreen() -> void:
	set_setting("fullscreen", not bool(data.settings.fullscreen))


func _input(event: InputEvent) -> void:
	# F11 or Alt+Enter toggles fullscreen anywhere in the game.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


func setting(key: String):
	return data.settings.get(key)


func set_setting(key: String, value) -> void:
	data.settings[key] = value
	save()
	apply_settings()
	if key == "text_size" or key == "smooth_text":
		UiKit.reset_theme()


# --- Cosmetics --------------------------------------------------------------------

func is_unlocked(id: String) -> bool:
	return id in Cosmetics.STARTER or id in data.unlocked


func unlock(ids: Array) -> Array:
	var fresh: Array = []
	for id in ids:
		if not is_unlocked(id):
			data.unlocked.append(id)
			fresh.append(id)
	return fresh


## General Store: pay Liquid Gold to unlock a cosmetic. False if owned, unknown or too expensive.
func buy_cosmetic(id: String) -> bool:
	var price := Cosmetics.price_of(id)
	if is_unlocked(id) or price <= 0 or price > int(data.liquid_gold):
		return false
	data.liquid_gold -= price
	data.unlocked.append(id)
	save()
	return true


func look() -> Dictionary:
	var l := Cosmetics.DEFAULT_LOOK.duplicate()
	l.merge(data.look, true)
	return l


func set_look(key: String, id: String) -> void:
	if is_unlocked(id):
		data.look[key] = id
		save()


func character_created() -> bool:
	# Profiles from before character creation existed count as created if they have progress.
	return bool(data.get("character_created", false)) or not data.campaign_done.is_empty()


# --- Liquid Gold & upgrades -------------------------------------------------------

func liquid_gold() -> int:
	return data.liquid_gold


func upgrade_level(id: String) -> int:
	return data.upgrades.get(id, 0)


func buy_upgrade(id: String) -> bool:
	var cost := Upgrades.next_cost(id, upgrade_level(id))
	if cost < 0 or cost > data.liquid_gold:
		return false
	data.liquid_gold -= cost
	data.upgrades[id] = upgrade_level(id) + 1
	save()
	return true


func campaign_mods() -> Dictionary:
	return Upgrades.mods_for(data.upgrades)


# --- Campaign ---------------------------------------------------------------------

func map_done(i: int) -> bool:
	return i in data.campaign_done


func map_unlocked(i: int) -> bool:
	return i == 0 or map_done(i - 1) or map_done(i)


## Records a finished campaign map and returns the rewards.
func complete_map(i: int, won: bool, map_def: Dictionary) -> Dictionary:
	var first_win := won and not map_done(i)
	var lg: int = int(map_def.reward) if won else int(map_def.reward) / 4
	if won and not first_win:
		lg = int(map_def.reward) / 2 # replays pay half
	data.liquid_gold += lg
	var unlocked: Array = []
	if first_win:
		data.campaign_done.append(i)
		unlocked = unlock(map_def.get("unlocks", []))
	save()
	return {"liquid_gold": lg, "unlocked": unlocked, "first_win": first_win}
