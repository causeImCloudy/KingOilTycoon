extends SceneTree
## Generates placeholder art and one request file per asset in asset_requests/.
##   godot --headless --path . --script res://tools/generate_placeholders.gd
## Existing PNGs are never overwritten, so finished art is safe. Pass `-- --force` to regenerate.

const OUT_REQUESTS := "res://asset_requests/"

var force := false

# Palette: mid-century Texas dust.
const INK := Color("1d1611")
const DIRT := Color("b98a57")
const DIRT_DARK := Color("8a6239")
const DIRT_LIGHT := Color("d9b07a")
const SCRUB := Color("6f7d3c")
const WOOD := Color("7a4e2a")
const WOOD_LIGHT := Color("a8743f")
const OIL := Color("15100d")
const OIL_SHINE := Color("4a3a30")
const GOLD := Color("f2c14e")
const STEEL := Color("8c9399")
const STEEL_DARK := Color("4e555b")
const PAPER := Color("efe3c6")
const SKY := Color("f0a35e")
const WHITE := Color(1, 1, 1)
const GREY := Color(0.75, 0.75, 0.75)
const GREY_DARK := Color(0.5, 0.5, 0.5)
const FIRE_A := Color("f6d24a")
const FIRE_B := Color("e8642a")
const STRATA := [Color("c79a63"), Color("9c6b45"), Color("6b4a35")]


func _init() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REQUESTS))
	var made := 0
	for a in assets():
		if _make(a):
			made += 1
	_write_index()
	write_kit_readme()
	print("Placeholders written: %d (existing files kept)" % made)
	quit()


func assets() -> Array:
	return base_assets() + level_backgrounds() + homestead_assets() + kit_assets()


## One 640x360 background per campaign level; briefs live in data/campaign.json.
func level_backgrounds() -> Array:
	var out: Array = []
	var f := FileAccess.open("res://data/campaign.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var chapter_of := {}
	for ci in data.chapters.size():
		for mi in data.chapters[ci].maps:
			chapter_of[int(mi)] = ci
	for i in data.maps.size():
		var m: Dictionary = data.maps[i]
		var ch: Dictionary = data.chapters[chapter_of.get(i, 0)]
		var rivals: Array = []
		for r in m.rivals:
			rivals.append(data.rivals[r].name)
		var idx: int = i
		var chi: int = chapter_of.get(i, 0)
		out.append({"path": m.background, "size": "640x360", "frames": "1",
			"desc": ("Background for campaign level %d, \"%s\" (chapter: %s). Rivals: %s.

%s

" +
				"How it's used: shown full-screen behind the level's title card before the match (title at the top, " +
				"intro text in a box across the bottom third, so keep the middle band the most interesting), then dimmed " +
				"to about 40%% behind the match screen. There the board and panels cover most of it; what stays visible is the " +
				"strip between the player list and the card panel on the right (about x 370-636, y 120-210, more with fewer " +
				"players) and thin edges, so put something recognizable (a derrick, a building edge) on the right side. No big text in the art (small painted signs in the scene are fine). " +
				"No transparency: fill every pixel.") % [i + 1, m.title, ch.title, ", ".join(rivals), m.background_desc],
			"draw": func(img): draw_level_bg(img, chi, idx)})
	return out


func base_assets() -> Array:
	return [
		{"path": "res://assets/ui/icon_liquid_gold.png", "size": "16x16", "frames": "1",
			"desc": "Liquid Gold currency icon: a single droplet of crude oil, glossy black with a warm gold highlight/rim so it reads as 'liquid gold'. Used in the campaign HUD, the upgrade shop and reward pop-ups.",
			"draw": draw_droplet},
		{"path": "res://assets/ui/icon_cash.png", "size": "16x16", "frames": "1",
			"desc": "In-match money icon: a green 1950s dollar bill or money bag. Used next to cash amounts in player panels.",
			"draw": draw_cash},
		{"path": "res://assets/sprites/drill_rig.png", "size": "24x32", "frames": "1",
			"desc": "The portable drilling rig the player drags from the side tray onto a drill site. Wooden/steel cable-tool rig with a small engine, readable at small size. Also used as the drag cursor.",
			"draw": draw_rig},
		{"path": "res://assets/sprites/derrick.png", "size": "9x14", "frames": "1",
			"desc": "Board-scale producing oil derrick (wooden lattice tower) that stands on a drill site after a strike. Drawn in greys/white: the game tints a flag or base stripe with the owner's company color, so leave a 3x2 px flag area at the top in pure white.",
			"draw": draw_derrick},
		{"path": "res://assets/sprites/dry_cap.png", "size": "7x5", "frames": "1",
			"desc": "Capped dry hole marker on the board: small concrete/steel cap with a dusty base.",
			"draw": draw_dry_cap},
		{"path": "res://assets/sprites/burned_well.png", "size": "9x9", "frames": "1",
			"desc": "Burned-out well left after a Blowout Fire card: charred stump of a derrick, black/ember colors.",
			"draw": draw_burned},
		{"path": "res://assets/sprites/gusher_strip.png", "size": "16x32 per frame, 6 frames in a row (96x32)", "frames": "6",
			"desc": "On-board gusher animation that plays at a drill site after a strike (other players' drills and sped-up mode). Oil column shooting up and splashing; frames 0-5 loop.",
			"draw": draw_gusher_strip},
		{"path": "res://assets/sprites/dust_strip.png", "size": "16x16 per frame, 6 frames (96x16)", "frames": "6",
			"desc": "Dry-hole puff: dust cloud and a sad little sputter. Plays once at the site.",
			"draw": draw_dust_strip},
		{"path": "res://assets/sprites/fire_strip.png", "size": "12x16 per frame, 4 frames (48x16)", "frames": "4",
			"desc": "Small looping flame for a well caught in a Blowout Fire.",
			"draw": draw_fire_strip},
		{"path": "res://assets/sprites/card_back.png", "size": "64x88", "frames": "1",
			"desc": "Back of the event cards: 1950s oil-company stock-certificate style with an ornate border and a derrick emblem. The deck pile on the HUD uses it.",
			"draw": draw_card_back},
		{"path": "res://assets/sprites/card_front_production.png", "size": "64x88", "frames": "1",
			"desc": "Front frame for Production cards. Leave the top 14 px as a title band and the bottom ~40 px plain (text is drawn by the game). Middle art area: pumping derricks, money.",
			"draw": func(img): draw_card_front(img, Color("4f7d3a"))},
		{"path": "res://assets/sprites/card_front_depletion.png", "size": "64x88", "frames": "1",
			"desc": "Front frame for Depletion Allowance cards (tax break). Same layout as production. Art: government envelope / stamped tax form.",
			"draw": func(img): draw_card_front(img, Color("2f5d8a"))},
		{"path": "res://assets/sprites/card_front_fire.png", "size": "64x88", "frames": "1",
			"desc": "Front frame for Blowout Fire cards. Same layout. Art: derrick engulfed in flames.",
			"draw": func(img): draw_card_front(img, Color("c8402e"))},
		{"path": "res://assets/ui/cutaway_bg.png", "size": "200x120", "frames": "1",
			"desc": "Background for the drill reveal pop-up: a cross-section of Texas ground. Sky strip on top (rows 0-23), surface line at y=24, then three rock strata (shallow y 24-55, medium 56-87, deep 88-119), each a distinct earthy color. The drill pipe descends through the middle (x ~100).",
			"draw": draw_cutaway},
		{"path": "res://assets/sprites/drill_bit.png", "size": "8x12", "frames": "1",
			"desc": "Drill bit tip shown descending in the cut-away. Steel tri-cone bit.",
			"draw": draw_bit},
		{"path": "res://assets/sprites/cutaway_rig.png", "size": "48x48", "frames": "1",
			"desc": "Larger drilling rig standing on the surface in the cut-away pop-up (bottom edge = ground).",
			"draw": draw_big_rig},
		{"path": "res://assets/tilesets/ground_tile.png", "size": "32x32 (seamless tile)", "frames": "1",
			"desc": "Seamlessly tiling West Texas ground for the board: dry dirt, scrub grass tufts, a few pebbles. Plots are tinted on top, so keep it mid-value and low-contrast.",
			"draw": draw_ground},
		{"path": "res://assets/ui/menu_bg.png", "size": "640x360", "frames": "1",
			"desc": "Main menu background: sunset over a 1940s Texas oil boomtown, rows of wooden derricks silhouetted, dusty orange sky. Leave the left third calm for menu buttons.",
			"draw": draw_menu_bg},
		{"path": "res://assets/ui/icon_star.png", "size": "9x9", "frames": "1",
			"desc": "Filled difficulty star (gold with a dark outline). Rival difficulty shows as 1-3 stars: Easy, Medium, Hard. The game draws it at 2x.",
			"draw": func(img): draw_star(img, true)},
		{"path": "res://assets/ui/icon_star_empty.png", "size": "9x9", "frames": "1",
			"desc": "Empty difficulty star: same outline as icon_star.png with a dull or hollow middle.",
			"draw": func(img): draw_star(img, false)},
		{"path": "res://assets/ui/campaign_map.png", "size": "640x360", "frames": "1",
			"desc": "Campaign world map of Texas. The trail of 20 map spots snakes up the left ~350 px (spot positions are in data/campaign.json 'pos'); the right side (x > 356) is covered by the briefing panel, so keep it simple there. Regions from bottom to top: Boomtown Beginnings (dusty boomtown, y 300-360), East Texas Rush (piney woods, y 245-300), Permian Basin (flat caprock and mesas, y 190-245), Gulf Coast Empire (coast and water on the left, y 135-190), The Big Board (Houston-style skyline at the top). Leave the trail area readable: the game draws the dashed trail and spot markers on top.",
			"draw": draw_campaign_map},
		{"path": "res://assets/ui/title_logo.png", "size": "256x64", "frames": "1",
			"desc": "Logo: 'STANDARD OIL' with the subtitle 'An Oil Tycoon Game'. Mid-century gas-station sign lettering, with an oil-drop or derrick motif. Transparent background.",
			"draw": draw_logo},
		{"path": "res://assets/sprites/character/body.png", "size": "32x48 per frame; 4 columns x 4 rows (128x192)", "frames": "16",
			"desc": "Full-body tycoon character, SKIN layer only (head, hands), drawn in greyscale/white: the game tints it with the chosen skin tone. Rows = animations: 0 idle (gentle bob), 1 anticipation (leaning, hands rubbing), 2 cheer (arms up, hat waving, small hop), 3 sulk (head down, kicking dirt). 4 frames each. All character layers must line up pixel-for-pixel.",
			"draw": func(img): draw_figure_sheet(img, "skin")},
		{"path": "res://assets/sprites/character/outfit.png", "size": "same as body.png", "frames": "16",
			"desc": "Character OUTFIT layer (shirt, vest, trousers, boots) in greyscale so it can be tinted with the chosen outfit color. Same rows/frames as body.png.",
			"draw": func(img): draw_figure_sheet(img, "outfit")},
		{"path": "res://assets/sprites/character/face.png", "size": "same as body.png", "frames": "16",
			"desc": "Character FACE/details layer (eyes, mustache, mouth expression, belt buckle), full color, not tinted. Expressions per row: idle neutral, anticipation eager, cheer big grin, sulk frown.",
			"draw": func(img): draw_figure_sheet(img, "face")},
		{"path": "res://assets/sprites/character/hat_stetson.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer: 10-gallon stetson, greyscale for tinting. Follows the head motion in every frame.",
			"draw": func(img): draw_figure_sheet(img, "stetson")},
		{"path": "res://assets/sprites/character/hat_derby.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer: banker's derby/bowler hat, greyscale for tinting.",
			"draw": func(img): draw_figure_sheet(img, "derby")},
		{"path": "res://assets/sprites/character/hat_hardhat.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer: roughneck's tin hard hat, greyscale for tinting.",
			"draw": func(img): draw_figure_sheet(img, "hardhat")},
		{"path": "res://assets/sprites/character/hat_flatcap.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer (General Store item, 70 Liquid Gold): newsboy flat cap, soft wool with a short brim, greyscale for tinting. Follows the head in every frame.",
			"draw": func(img): draw_figure_sheet(img, "flatcap")},
		{"path": "res://assets/sprites/character/hat_tengallon.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer (General Store item, 120 Liquid Gold): oversized showman's ten-gallon hat, very tall crown and wide curled brim, greyscale for tinting. May rise above the head's frame area but stay inside the 32x48 frame.",
			"draw": func(img): draw_figure_sheet(img, "tengallon")},
		{"path": "res://assets/sprites/character/hat_tophat.png", "size": "same as body.png", "frames": "16",
			"desc": "Hat layer (General Store item, 150 Liquid Gold): tall oil-baron top hat with a band, greyscale for tinting (the band can be a slightly darker grey).",
			"draw": func(img): draw_figure_sheet(img, "tophat")},
		{"path": "res://assets/sprites/character/portrait.png", "size": "24x24 per frame; 2 columns x 4 rows (48x96)", "frames": "8",
			"desc": "Head-and-shoulders portrait for each player's side panel, SKIN layer in greyscale. Rows = idle, anticipation, cheer, sulk; 2 frames each. Portrait layers (portrait_outfit, portrait_face, portrait_hat_*) follow the same layout.",
			"draw": func(img): draw_portrait_sheet(img, "skin")},
		{"path": "res://assets/sprites/character/portrait_outfit.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait OUTFIT layer (collar, vest, tie), greyscale for tinting.",
			"draw": func(img): draw_portrait_sheet(img, "outfit")},
		{"path": "res://assets/sprites/character/portrait_face.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait FACE layer (eyes, mouth, mustache), full color, expression per row.",
			"draw": func(img): draw_portrait_sheet(img, "face")},
		{"path": "res://assets/sprites/character/portrait_hat_stetson.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: stetson (greyscale).", "draw": func(img): draw_portrait_sheet(img, "stetson")},
		{"path": "res://assets/sprites/character/portrait_hat_derby.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: derby (greyscale).", "draw": func(img): draw_portrait_sheet(img, "derby")},
		{"path": "res://assets/sprites/character/portrait_hat_hardhat.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: hard hat (greyscale).", "draw": func(img): draw_portrait_sheet(img, "hardhat")},
		{"path": "res://assets/sprites/character/portrait_hat_flatcap.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: flat cap (greyscale).", "draw": func(img): draw_portrait_sheet(img, "flatcap")},
		{"path": "res://assets/sprites/character/portrait_hat_tengallon.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: ten-gallon hat (greyscale). Keep the crown inside the 24x24 frame.", "draw": func(img): draw_portrait_sheet(img, "tengallon")},
		{"path": "res://assets/sprites/character/portrait_hat_tophat.png", "size": "same as portrait.png", "frames": "8",
			"desc": "Portrait hat layer: top hat (greyscale).", "draw": func(img): draw_portrait_sheet(img, "tophat")},
		{"path": "res://assets/ui/panel.png", "size": "24x24 (9-slice, 8 px margins)", "frames": "1",
			"desc": "UI panel frame for HUD panels and menus: weathered painted wood sign or aged paper with a dark border. Used as a 9-slice with 8 px margins.",
			"draw": draw_panel},
		{"path": "res://assets/ui/button.png", "size": "24x16 (9-slice, 6 px margins), plus button_hover.png and button_pressed.png", "frames": "1",
			"desc": "Button background in the same style as the panel: mustard/cream enamel sign. Placeholder only creates the normal state.",
			"draw": draw_button},
	]


func extra_requests() -> Array:
	## Assets that have no image placeholder (fonts, audio). The game runs without them.
	return [
		{"path": "res://assets/fonts/main_font.ttf", "size": "pixel font, designed for 8 px (and 16 px) size",
			"desc": "Main UI pixel font with a 1940s-50s signage/typewriter feel. Needs digits, $ and basic punctuation. See asset_requests/font_fixes.md for the letters that need redrawing (m, M, W, w, v, V, N, r, 1)."},
		{"path": "res://assets/fonts/title_font.ttf", "size": "pixel font, 16 px",
			"desc": "Display font for headings and the game-over screen, Western/wood-type feel. Same letter fixes as the main font: see asset_requests/font_fixes.md."},
		{"path": "res://assets/audio/sfx/drill_loop.ogg", "size": "1-2 s loop", "desc": "Drill engine chugging while the bit descends."},
		{"path": "res://assets/audio/sfx/gusher.ogg", "size": "1-2 s", "desc": "Oil strike: rumble and splash."},
		{"path": "res://assets/audio/sfx/dry_hole.ogg", "size": "<1 s", "desc": "Dry hole: hollow clunk and puff."},
		{"path": "res://assets/audio/sfx/card_flip.ogg", "size": "<0.5 s", "desc": "Card slide and flip."},
		{"path": "res://assets/audio/sfx/cash.ogg", "size": "<1 s", "desc": "Cash register ding for income."},
		{"path": "res://assets/audio/sfx/fire.ogg", "size": "1-2 s", "desc": "Fire whoosh and crackle for Blowout Fire."},
		{"path": "res://assets/audio/sfx/pipeline.ogg", "size": "<1 s", "desc": "Metal clank for laying a pipeline."},
		{"path": "res://assets/audio/sfx/click.ogg", "size": "<0.2 s", "desc": "UI button click."},
		{"path": "res://assets/audio/music/menu.ogg", "size": "1-2 min loop", "desc": "Menu music: western swing / honky-tonk piano, relaxed."},
		{"path": "res://assets/audio/music/match.ogg", "size": "2-3 min loop", "desc": "Match music: low-key Texas swing that doesn't tire over a long game."},
	]


# --- Plumbing -------------------------------------------------------------------

func _make(a: Dictionary) -> bool:
	_write_request(a, true)
	var abs_path := ProjectSettings.globalize_path(a.path)
	if FileAccess.file_exists(abs_path) and not force:
		return false
	var dims := _dims_for(a)
	var img := Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	a.draw.call(img)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	return true


func _dims_for(a: Dictionary) -> Vector2i:
	var known := {
		"gusher_strip": Vector2i(96, 32), "dust_strip": Vector2i(96, 16), "fire_strip": Vector2i(48, 16),
		"body": Vector2i(128, 192), "outfit": Vector2i(128, 192), "face": Vector2i(128, 192),
		"hat_stetson": Vector2i(128, 192), "hat_derby": Vector2i(128, 192), "hat_hardhat": Vector2i(128, 192),
		"hat_flatcap": Vector2i(128, 192), "hat_tengallon": Vector2i(128, 192), "hat_tophat": Vector2i(128, 192),
		"portrait": Vector2i(48, 96), "portrait_outfit": Vector2i(48, 96), "portrait_face": Vector2i(48, 96),
		"portrait_hat_stetson": Vector2i(48, 96), "portrait_hat_derby": Vector2i(48, 96), "portrait_hat_hardhat": Vector2i(48, 96),
		"portrait_hat_flatcap": Vector2i(48, 96), "portrait_hat_tengallon": Vector2i(48, 96), "portrait_hat_tophat": Vector2i(48, 96),
		"panel": Vector2i(24, 24), "button": Vector2i(24, 16),
	}
	var stem: String = a.path.get_file().get_basename()
	if known.has(stem):
		return known[stem]
	var parts: PackedStringArray = a.size.split(" ")[0].split("x")
	return Vector2i(int(parts[0]), int(parts[1]))


func _write_request(a: Dictionary, has_placeholder: bool) -> void:
	var stem: String = a.path.trim_prefix("res://").replace("/", "__").get_basename()
	var dir: String = OUT_REQUESTS + a.get("req_dir", "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if a.has("req_dir"):
		stem = a.path.get_file().get_basename()
		if a.path.contains("/lines/"):
			stem = "line_" + stem
		elif a.path.contains("/fields/"):
			stem = "field_" + stem
	var f := FileAccess.open(dir + stem + ".md", FileAccess.WRITE)
	f.store_string("# %s\n\n" % a.path.get_file())
	f.store_string("- **File:** `%s`\n" % a.path.trim_prefix("res://"))
	f.store_string("- **Size:** %s\n" % a.size)
	if a.has("frames"):
		f.store_string("- **Frames:** %s\n" % a.frames)
	f.store_string("- **Status:** %s\n\n" % ("placeholder generated, replace the file with final art (same name and size)" if has_placeholder else "missing (the game runs without it)"))
	f.store_string("%s\n\n" % a.desc)
	f.store_string("Style: pixel art, mid-1900s Texas oil boom, warm dusty palette, crisp pixels (no anti-aliasing), transparent background unless stated.\n")


func _write_index() -> void:
	for a in extra_requests():
		_write_request(a, false)
	var f := FileAccess.open(OUT_REQUESTS + "README.md", FileAccess.WRITE)
	f.store_string("# Asset requests\n\nEach file here describes one asset the game needs. Placeholder PNGs are generated by\n`tools/generate_placeholders.gd`. Replace a placeholder by saving your art over the same path\nwith the same size and frame layout. The generator never overwrites existing files.\n\n")
	f.store_string("| Asset | Size | Has placeholder |\n|---|---|---|\n")
	for a in assets():
		if a.has("req_dir"):
			continue
		f.store_string("| `%s` | %s | yes |\n" % [a.path.trim_prefix("res://"), a.size])
	f.store_string("| Map decoration kit (%d pieces) | see `board_kit/README.md` | yes |\n" % kit_assets().size())
	for a in extra_requests():
		f.store_string("| `%s` | %s | no |\n" % [a.path.trim_prefix("res://"), a.size])



# --- Homestead (scripts/ui/homestead.gd) ------------------------------------------------------

const HOME_DIR := "res://assets/sprites/homestead/"
const HOME_LAYERS := "Three frames side by side, each the building's full size: frame 1 = WALLS in greyscale " + \
	"(the game tints them with the player's Siding color, so draw them light: white to mid grey, with darker greys " + \
	"for shading, boards and logs), frame 2 = ROOF in greyscale (tinted with the player's Roof color), frame 3 = " + \
	"DETAILS in full color, drawn on top of both: the dark outline, door, windows, chimney, porch posts, steps and " + \
	"anything that should keep its own color. Leave a frame transparent wherever another layer shows. All three " + \
	"frames must line up pixel for pixel."
const HOME_VIEW := "Same view as the map kit: top-down with a slight 3/4 tilt (you see the roof and a sliver of the " + \
	"south-facing wall), light from the top-left. It stands on the bottom-center of the frame. No text, and never " + \
	"anything that looks like an oil derrick."
const HOUSE_STYLES := {
	"farmhouse": ["Farmhouse (free)", "Two-storey clapboard farmhouse with a steep gabled roof, a covered front porch along the south wall and a brick chimney."],
	"cabin": ["Log Cabin (free)", "Squat log cabin: round log ends at the corners, a low pitched roof, a fieldstone chimney on one end and a small plank porch."],
	"ranch": ["Ranch (60 LG)", "Long, low single-storey ranch house with a shallow hip roof, wide eaves, a picture window and a carport or breezeway at one end. Use the full width."],
	"adobe": ["Hacienda (80 LG)", "Flat-roofed adobe with soft rounded corners and a stepped parapet, wooden roof beams (vigas) poking out of the wall, an arched doorway and a little courtyard wall. The ROOF layer is the parapet cap and any terracotta trim."],
	"victorian": ["Victorian (120 LG)", "Tall, narrow Victorian with a round corner turret and a pointed turret cap, steep roof, gingerbread trim and a wraparound porch. The tallest house: let the turret reach the top of the frame."],
	"mansion": ["Mansion (200 LG)", "Grand symmetrical mansion: white two-storey portico with columns (columns go in the DETAILS frame so they stay white), hip roof with two dormers and twin chimneys, a short front walk. The showpiece."],
}
const OUTBUILDING_STYLES := {
	"shed": ["Tool Shed (free)", "Small plank tool shed with a single-slope (lean-to) roof and a plank door."],
	"barn": ["Barn (free)", "Tiny barn with a gambrel (two-slope) roof and a hayloft door with an X brace."],
	"silo": ["Grain Silo (40 LG)", "Round grain silo with a domed cap (the cap is the ROOF layer) and a tiny lean-to at its foot."],
	"bunkhouse": ["Bunkhouse (60 LG)", "Long, low bunkhouse for the crew: a row of small windows, a gabled roof and a stovepipe."],
	"windmill": ["Windmill (60 LG)", "Water-pumping windmill: an open wooden lattice tower over a small round stock tank. The fan wheel and tail vane are the ROOF layer, the tank and tower are WALLS."],
	"office": ["Office (80 LG)", "Lease office shack with a porch awning, a blank sign board over the door (no text) and a hitching rail."],
}


func homestead_assets() -> Array:
	var out: Array = []
	for st in HOUSE_STYLES:
		var info: Array = HOUSE_STYLES[st]
		out.append({"path": HOME_DIR + "house_%s.png" % st, "size": "60x20 (3 frames of 20x20)", "frames": "3",
			"desc": ("Homestead HOUSE: %s. %s\n\nEach player's house stands on the FIRST property they buy in a match " +
				"(players pick the style in Customize and the General Store). It should read clearly as the player's home " +
				"base: a little bigger and more detailed than the map's decoration houses (those are 12-16 px).\n\n" +
				"Frame size 20x20. Ground footprint: the bottom 16x10 px (centered) touches the ground; the roof and " +
				"chimney can rise above it.\n\n%s\n\n%s") % [info[0], info[1], HOME_LAYERS, HOME_VIEW],
			"draw": func(img): draw_homestead(img, "house", st)})
	for st in OUTBUILDING_STYLES:
		var info: Array = OUTBUILDING_STYLES[st]
		out.append({"path": HOME_DIR + "outbuilding_%s.png" % st, "size": "36x12 (3 frames of 12x12)", "frames": "3",
			"desc": ("Homestead OUTBUILDING: %s. %s\n\nOne stands on every property a player buys after their first, so " +
				"a player may have a dozen on the board: keep it simple and readable at a glance, much smaller than the " +
				"house. It uses the same Siding and Roof colors as the house so a player's buildings match.\n\n" +
				"Frame size 12x12. Ground footprint: the bottom 10x6 px (centered).\n\n%s\n\n%s") % [info[0], info[1], HOME_LAYERS, HOME_VIEW],
			"draw": func(img): draw_homestead(img, "outbuilding", st)})
	return out


## Placeholder: walls block, roof block and a details frame with outline, door and windows.
func draw_homestead(img: Image, kind: String, style: String) -> void:
	var fw := 20 if kind == "house" else 12
	var walls := Image.create_empty(fw, fw, false, Image.FORMAT_RGBA8)
	var roof := Image.create_empty(fw, fw, false, Image.FORMAT_RGBA8)
	var det := Image.create_empty(fw, fw, false, Image.FORMAT_RGBA8)
	var wall_c := Color(0.92, 0.92, 0.92)
	var roof_c := Color(0.8, 0.8, 0.8)
	var foot := 16 if kind == "house" else 10
	var x0 := (fw - foot) / 2
	match style:
		"silo":
			rect(walls, 3, 4, 6, 8, wall_c)
			circle(roof, 6.0, 4.0, 3.0, roof_c)
			rect(roof, 2, 5, 8, 3, Color(0, 0, 0, 0))
		"windmill":
			rect(walls, 4, 8, 4, 4, wall_c)
			line(walls, Vector2(5, 8), Vector2(6, 4), GREY_DARK)
			line(walls, Vector2(7, 8), Vector2(6, 4), GREY_DARK)
			circle(roof, 6.0, 3.0, 2.6, roof_c)
		"adobe":
			rect(walls, x0, fw - 11, foot, 11, wall_c)
			rect(roof, x0, fw - 12, foot, 2, roof_c)
			rect(roof, x0 + 4, fw - 13, foot - 8, 1, roof_c)
		"ranch":
			rect(walls, 1, fw - 8, fw - 2, 8, wall_c)
			rect(roof, 0, fw - 12, fw, 5, roof_c)
		_:
			var wall_h := fw / 2
			rect(walls, x0, fw - wall_h, foot, wall_h, wall_c)
			var top := 1 if style in ["victorian", "farmhouse"] else 3
			for y in range(top, fw - wall_h + 1):
				var t := float(y - top) / maxf(1.0, fw - wall_h - top)
				var half := int(round(1 + t * (foot / 2.0)))
				rect(roof, fw / 2 - half, y, half * 2, 1, roof_c)
			if style == "victorian":
				rect(roof, x0, 0, 4, 6, roof_c)
	# Details: door and windows, then one outline around the whole building.
	if style != "windmill":
		var dh := 4 if kind == "house" else 3
		rect(det, fw / 2 - 1, fw - dh, 2, dh, Color("5a3a22"))
	if kind == "house":
		rect(det, x0 + 2, fw - 7, 2, 2, Color("3a4a5a"))
		rect(det, fw - x0 - 4, fw - 7, 2, 2, Color("3a4a5a"))
		if style in ["farmhouse", "cabin", "mansion"]:
			rect(det, fw - x0 - 5, 4 if style == "cabin" else 1, 2, 4, Color("8a4a34"))
	var all := walls.duplicate() as Image
	all.blend_rect(roof, Rect2i(0, 0, fw, fw), Vector2i.ZERO)
	all.blend_rect(det, Rect2i(0, 0, fw, fw), Vector2i.ZERO)
	var edge := all.duplicate() as Image
	outline(edge)
	for y in fw:
		for x in fw:
			if all.get_pixel(x, y).a == 0.0 and edge.get_pixel(x, y).a > 0.0:
				det.set_pixel(x, y, INK)
	img.blit_rect(walls, Rect2i(0, 0, fw, fw), Vector2i(0, 0))
	img.blit_rect(roof, Rect2i(0, 0, fw, fw), Vector2i(fw, 0))
	img.blit_rect(det, Rect2i(0, 0, fw, fw), Vector2i(fw * 2, 0))


# --- Map decoration kit (data/board_kit.json) ------------------------------------------------

const KIT_DIR := "res://assets/board_kit/"
const KIT_REQ := "board_kit/"
const KIT_STYLE := "View: top-down with a slight 3/4 tilt (you see roofs and a sliver of the south-facing wall), " + \
	"like the farm buildings on a 1970s board game. Light from the top-left; draw a soft shadow down-right " + \
	"inside the canvas (semi-transparent dark brown). Crisp pixels, no anti-aliasing, warm dusty mid-century palette."


func kit() -> Dictionary:
	var f := FileAccess.open("res://data/board_kit.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


## Which themes use a kit piece (for the request files).
func _kit_users(k: Dictionary, kind: String, id: String) -> String:
	var out: Array[String] = []
	for tid in k.themes:
		var t: Dictionary = k.themes[tid]
		var used := false
		match kind:
			"field":
				used = id in t.fields
			"line":
				used = t.lines.has(id)
			"prop":
				for sc in t.scatter:
					used = used or sc[0] == id
				for st in t.sets:
					used = used or id in k.sets[st[0]]
		if used:
			out.append(str(t.name))
	return ", ".join(out) if not out.is_empty() else "placed by hand in the map editor"


func kit_assets() -> Array:
	var k := kit()
	var out: Array = []
	for id in k.fields:
		var fd: Dictionary = k.fields[id]
		out.append({"path": KIT_DIR + "fields/%s.png" % id, "size": "32x32 (seamless tile)", "frames": "1", "req_dir": KIT_REQ,
			"desc": ("Field texture: %s. %s\n\nPainted over the board in patches of any shape and size, so it must tile seamlessly in both " +
				"directions (no visible edge when four copies sit side by side). Flat top-down, no shadows, no objects " +
				"taller than the ground. Keep it mid-value and low-contrast: drill holes, derricks and the owner-color " +
				"tint are drawn on top. Fully opaque.\n\nUsed by: %s.") % [fd.name, fd.desc, _kit_users(k, "field", id)],
			"draw": func(img): draw_kit_field(img, fd)})
	for id in k.lines:
		var ld: Dictionary = k.lines[id]
		var users := _kit_users(k, "line", id)
		out.append({"path": KIT_DIR + "lines/%s_straight.png" % id, "size": "16x8", "frames": "1", "req_dir": KIT_REQ,
			"desc": ("Line piece: %s, STRAIGHT. %s\n\nRuns left to right and repeats end to end, so the left and right " +
				"edges must join seamlessly. The line sits on property borders; its center is row 4 (the 8 px height is " +
				"the full width of the road, rail, creek or fence). The game rotates it 90 degrees for north-south runs. " +
				"Transparent outside the line.\n\nUsed by: %s.") % [ld.name, ld.desc, users],
			"draw": func(img): draw_kit_line(img, ld, "straight")})
		out.append({"path": KIT_DIR + "lines/%s_corner.png" % id, "size": "8x8", "frames": "1", "req_dir": KIT_REQ,
			"desc": ("Line piece: %s, CORNER. Joins a straight piece coming in from the RIGHT edge to one leaving " +
				"through the BOTTOM edge (a turn shaped like the top-left corner of a box). It must line up with the " +
				"straight piece's ends at both edges. The game rotates it for the other three turns. Transparent " +
				"outside the line.\n\nUsed by: %s.") % [ld.name, users],
			"draw": func(img): draw_kit_line(img, ld, "corner")})
		out.append({"path": KIT_DIR + "lines/%s_cross.png" % id, "size": "8x8", "frames": "1", "req_dir": KIT_REQ,
			"desc": ("Line piece: %s, CROSSING. Where lines meet from three or four sides (a T or a +): open to all " +
				"four edges, lining up with the straight piece's ends. Transparent outside the line.\n\nUsed by: %s.") % [ld.name, users],
			"draw": func(img): draw_kit_line(img, ld, "cross")})
	for id in k.props:
		var pd: Dictionary = k.props[id]
		var flat: bool = pd.layer == "flat"
		out.append({"path": KIT_DIR + "props/%s.png" % id, "size": "%dx%d" % [pd.size[0], pd.size[1]], "frames": "1", "req_dir": KIT_REQ,
			"desc": ("Map prop (%s): %s. %s\n\nCanvas %dx%d, transparent background. The bottom-center of the canvas " +
				"is where it stands on the ground. Ground footprint: the bottom %dx%d px (centered) is what touches " +
				"the ground; the map keeps drill sites out of it, so keep the base inside that area. %s\n\n%s\n\n" +
				"Scale: one drill-site cell is 12 px (10 px on 5-6 player maps). Used by: %s.") % [
				pd.cat, pd.name, pd.desc, pd.size[0], pd.size[1], pd.foot[0], pd.foot[1],
				"Lies flat on the ground (drawn under standing props): no shadow needed." if flat else
				"Anything taller than the footprint (roofs, crowns, towers) can rise above it.",
				KIT_STYLE, _kit_users(k, "prop", id)],
			"draw": func(img): draw_kit_prop(img, pd)})
	return out


func draw_kit_field(img: Image, fd: Dictionary) -> void:
	var base := Color(fd.ph)
	var r := RandomNumberGenerator.new()
	r.seed = hash(fd.name)
	for y in 32:
		for x in 32:
			var c := base
			match fd.pattern:
				"rows_h":
					if y % 4 == 0: c = base.darkened(0.18)
					elif y % 4 == 1: c = base.lightened(0.06)
				"rows_v":
					if x % 4 == 0: c = base.darkened(0.18)
					elif x % 4 == 1: c = base.lightened(0.06)
				"stripes_d":
					if (x + y) % 8 < 4: c = base.lightened(0.05)
				"ripples":
					if (y + int(2 * sin(x * TAU / 16.0))) % 6 == 0: c = base.darkened(0.1)
				"cracks":
					if x % 11 == 0 or (y + x / 11 * 3) % 9 == 0: c = base.darkened(0.25)
				"grid":
					if y % 8 == 0 or x % 16 == 0: c = base.darkened(0.15)
					elif x % 2 == 0: c = base.lightened(0.08)
				"dots":
					if y % 4 == 0: c = base.darkened(0.12)
					elif (x + y * 3) % 7 == 0: c = Color("f4f0e6")
				"trees":
					var cx := (x % 16) - 8
					var cy := (y % 16) - 8
					if cx * cx + cy * cy < 22: c = Color("4f6a35")
			if fd.pattern in ["speckle", "rows_h", "rows_v", "stripes_d"]:
				var n := r.randf()
				if n < 0.08: c = c.darkened(0.12)
				elif n > 0.93: c = c.lightened(0.1)
			img.set_pixel(x, y, c)


func draw_kit_line(img: Image, ld: Dictionary, part: String) -> void:
	var c := Color(ld.ph)
	var w := img.get_width()
	var cells: Array[Rect2i] = []
	match part:
		"straight": cells = [Rect2i(0, 2, w, 4)]
		"corner": cells = [Rect2i(2, 2, 6, 4), Rect2i(2, 2, 4, 6)]
		"cross": cells = [Rect2i(0, 2, 8, 4), Rect2i(2, 0, 4, 8)]
	for rr in cells:
		rect(img, rr.position.x, rr.position.y, rr.size.x, rr.size.y, c)
	if ld.name == "Railroad" and part == "straight":
		for x in range(0, w, 3):
			rect(img, x, 1, 1, 6, Color("4a3a2a"))
		rect(img, 0, 2, w, 1, Color("a0a0a8"))
		rect(img, 0, 5, w, 1, Color("a0a0a8"))
	elif ld.name == "Barbed-wire fence":
		img.fill(Color(0, 0, 0, 0))
		for rr in cells:
			rect(img, rr.position.x, rr.position.y + 1, rr.size.x, 1, Color("6a6a6a"))
		if part == "straight":
			for x in range(0, w, 8):
				rect(img, x + 3, 2, 2, 3, Color("6a4a2a"))


func draw_kit_prop(img: Image, pd: Dictionary) -> void:
	var w: int = pd.size[0]
	var h: int = pd.size[1]
	var c := Color(pd.ph)
	var fw: int = pd.foot[0]
	var fh: int = pd.foot[1]
	var fx := (w - fw) / 2
	match pd.shape:
		"house":
			rect(img, fx, h - fh, fw, fh, c)
			rect(img, fx, maxi(0, h - fh - 6), fw, mini(fh, 6) + 1, c.darkened(0.35))
		"tall":
			rect(img, fx, 0, fw, h, c)
			rect(img, fx, 0, fw, 3, c.darkened(0.3))
		"round":
			circle(img, w / 2.0, h / 2.0, mini(w, h) / 2.0 - 0.5, c)
		"tree":
			rect(img, w / 2 - 1, h - 4, 2, 4, Color("5a4030"))
			circle(img, w / 2.0, (h - 3) / 2.0, mini(w, h - 3) / 2.0 - 0.5, c)
		"flat":
			rect(img, 0, 0, w, h, c)
			rect(img, 1, 1, w - 2, h - 2, c.lightened(0.1))
		"animal":
			for i in maxi(1, w / 6):
				circle(img, 3 + i * 5, h / 2.0, 2.2, c)
		"vehicle":
			rect(img, 1, 1, w - 2, h - 3, c)
			rect(img, 1, h - 2, 2, 2, INK)
			rect(img, w - 3, h - 2, 2, 2, INK)
	outline(img)


## asset_requests/board_kit/README.md: conventions plus a table of every piece.
func write_kit_readme() -> void:
	var k := kit()
	var f := FileAccess.open(OUT_REQUESTS + KIT_REQ + "README.md", FileAccess.WRITE)
	f.store_string("# Map decoration kit\n\n")
	f.store_string("Small pieces of art that the game (and the map editor) arranges into each map's board, instead of one " +
		"painted picture per map. Replace a placeholder by saving your art over the same file at the same size. Each " +
		"piece has its own description file in this folder.\n\n")
	f.store_string("## How the board is built\n\n")
	f.store_string("1. **Fields** (`assets/board_kit/fields/`, 32x32 seamless): painted over the board in the map editor on a 4 px grid, in any shape (not tied to properties).\n")
	f.store_string("2. **Lines** (`assets/board_kit/lines/`): roads, rails, creeks, fences and tree lines run along property borders. " +
		"Each line type has 3 pieces: `_straight` (16x8, left-right, repeats), `_corner` (8x8, right edge to bottom edge) and " +
		"`_cross` (8x8, all four edges). The game rotates them for other directions.\n")
	f.store_string("3. **Props** (`assets/board_kit/props/`): buildings, trees, animals and vehicles placed on top. Flat props " +
		"(ponds, corrals, arenas) go down first; standing props are sorted so lower ones overlap higher ones.\n")
	f.store_string("4. The game then draws property borders, owner tints, drill holes, derricks and pipelines on top.\n\n")
	f.store_string("## Drawing rules for every piece\n\n")
	f.store_string("- %s\n" % KIT_STYLE)
	f.store_string("- Scale: one drill-site cell is 12x12 px (10x10 on 5-6 player maps). A small house is about one cell.\n")
	f.store_string("- Props stand on the bottom-center of their canvas. Keep their base inside the listed footprint: the map " +
		"keeps drill sites out of the footprint, but roofs, tree crowns and towers may rise above it.\n")
	f.store_string("- Never draw an oil derrick or pump jack: derricks are game pieces, and decoration must not look like one.\n")
	f.store_string("- No readable text on signs (the fonts are drawn by the game).\n\n")
	f.store_string("## Fields (32x32)\n\n| File | What |\n|---|---|\n")
	for id in k.fields:
		f.store_string("| `fields/%s.png` | %s |\n" % [id, k.fields[id].name])
	f.store_string("\n## Lines (each: `_straight` 16x8, `_corner` 8x8, `_cross` 8x8)\n\n| Files | What |\n|---|---|\n")
	for id in k.lines:
		f.store_string("| `lines/%s_*.png` | %s |\n" % [id, k.lines[id].name])
	f.store_string("\n## Props\n\n| File | Size | Footprint | Group | What |\n|---|---|---|---|---|\n")
	for id in k.props:
		var pd: Dictionary = k.props[id]
		f.store_string("| `props/%s.png` | %dx%d | %dx%d | %s | %s |\n" % [id, pd.size[0], pd.size[1], pd.foot[0], pd.foot[1], pd.cat, pd.name])
	f.store_string("\n## Themes\n\nEach campaign level uses a theme (`board_theme` in `data/campaign.json`) that picks its fields, " +
		"lines, building groups and scattered props. The map editor's Auto-fill uses the same themes.\n\n")
	for tid in k.themes:
		var t: Dictionary = k.themes[tid]
		var sets: Array[String] = []
		for st in t.sets:
			sets.append(str(st[0]))
		f.store_string("- **%s** (`%s`): fields %s; groups %s.\n" % [t.name, tid, ", ".join(t.fields), ", ".join(sets)])


# --- Drawing helpers --------------------------------------------------------------

func px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(img, xx, yy, c)


func circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for yy in range(int(cy - r - 1), int(cy + r + 2)):
		for xx in range(int(cx - r - 1), int(cx + r + 2)):
			if Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() <= r:
				px(img, xx, yy, c)


func line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		px(img, roundi(p.x), roundi(p.y), c)


func outline(img: Image, c: Color = INK) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and src.get_pixel(q.x, q.y).a > 0.5:
					img.set_pixel(x, y, c)
					break


# --- Drawings -------------------------------------------------------------------

func draw_droplet(img: Image) -> void:
	for y in range(2, 15):
		var t := (y - 2) / 12.0
		var half := 5.5 * sin(clampf(t * 1.25, 0.0, 1.0) * PI * 0.5) if t < 0.8 else 5.5 * sqrt(maxf(0.0, 1.0 - pow((t - 0.8) / 0.2, 2.0)))
		for x in range(0, 16):
			if absf(x + 0.5 - 8.0) <= half:
				px(img, x, y, OIL)
	circle(img, 8, 10.5, 4.6, OIL)
	px(img, 6, 8, GOLD); px(img, 6, 9, GOLD); px(img, 6, 10, GOLD); px(img, 7, 7, GOLD)
	px(img, 9, 12, OIL_SHINE); px(img, 10, 11, OIL_SHINE)
	outline(img, Color("8a6a1c"))


func draw_cash(img: Image) -> void:
	rect(img, 1, 4, 14, 8, Color("5f8f4e"))
	rect(img, 2, 5, 12, 6, Color("7fb36b"))
	circle(img, 8, 8, 2.2, Color("3d6b33"))
	px(img, 8, 7, Color("cfe8b8")); px(img, 8, 8, Color("cfe8b8")); px(img, 8, 9, Color("cfe8b8"))
	outline(img)


func draw_rig(img: Image) -> void:
	for y in range(2, 26):
		var half := int(1 + (y - 2) * 0.32)
		px(img, 12 - half, y, WOOD_LIGHT)
		px(img, 12 + half, y, WOOD_LIGHT)
		if y % 5 == 0:
			line(img, Vector2(12 - half, y), Vector2(12 + half, y), WOOD)
	rect(img, 11, 1, 3, 2, STEEL)
	line(img, Vector2(12, 3), Vector2(12, 27), STEEL_DARK)
	rect(img, 2, 26, 20, 4, STEEL_DARK)
	rect(img, 15, 22, 7, 4, Color("b0322a"))
	circle(img, 5, 30, 1.5, INK); circle(img, 18, 30, 1.5, INK)
	outline(img)


func draw_derrick(img: Image) -> void:
	for y in range(3, 13):
		var half := int((y - 2) * 0.35)
		px(img, 4 - half, y, GREY_DARK)
		px(img, 4 + half, y, GREY_DARK)
		if y % 3 == 0:
			line(img, Vector2(4 - half, y), Vector2(4 + half, y), GREY)
	rect(img, 3, 0, 3, 2, WHITE) # flag area tinted with company color
	px(img, 4, 2, GREY_DARK)
	rect(img, 0, 13, 9, 1, Color(0.3, 0.3, 0.3))


func draw_dry_cap(img: Image) -> void:
	rect(img, 1, 2, 5, 3, STEEL)
	rect(img, 2, 1, 3, 1, STEEL_DARK)
	rect(img, 0, 4, 7, 1, DIRT_DARK)
	outline(img)


func draw_burned(img: Image) -> void:
	line(img, Vector2(2, 8), Vector2(4, 2), Color("2b2420"))
	line(img, Vector2(6, 8), Vector2(5, 3), Color("2b2420"))
	line(img, Vector2(3, 5), Vector2(6, 5), Color("3b302a"))
	px(img, 4, 7, FIRE_B); px(img, 5, 6, FIRE_A)
	rect(img, 0, 8, 9, 1, Color("3b302a"))


func draw_gusher_strip(img: Image) -> void:
	for f in 6:
		var ox := f * 16
		var h := 6 + mini(f, 3) * 7 + (2 if f >= 4 and f % 2 == 0 else 0)
		for y in range(31 - h, 31):
			var w := 1 + int((31 - y) / 8.0) % 2
			rect(img, ox + 8 - w, y, w * 2, 1, OIL)
		if f >= 2:
			for i in 5 + f:
				var a := float(i) / (5 + f) * PI
				var r := 3.0 + f * 0.8
				circle(img, ox + 8 + cos(a) * r * 1.4, 31 - h + 2 - sin(a) * r * 0.6, 1.2, OIL)
		px(img, ox + 7, 31 - h + 1, OIL_SHINE)
		rect(img, ox + 3, 30, 10, 2, DIRT_DARK)


func draw_dust_strip(img: Image) -> void:
	for f in 6:
		var ox := f * 16
		var r := 2.0 + f * 1.1
		var c := DIRT_LIGHT
		c.a = 1.0 - f * 0.15
		circle(img, ox + 8 - f * 0.6, 12 - f * 0.8, r * 0.7, c)
		circle(img, ox + 8 + f * 0.7, 12 - f * 0.5, r * 0.6, c)
		circle(img, ox + 8, 13, r * 0.5, Color(DIRT, c.a))


func draw_fire_strip(img: Image) -> void:
	for f in 4:
		var ox := f * 12
		var sway: int = [0, 1, 0, -1][f]
		for y in range(2, 16):
			var half := (16 - y) * 0.3 * sin((y - 2) / 14.0 * PI) + 1.0
			for x in range(0, 12):
				var dx := absf(x + 0.5 - 6 - sway * (16 - y) / 14.0)
				if dx <= half:
					px(img, ox + x, y, FIRE_A if dx < half * 0.5 and y > 6 else FIRE_B)


func draw_card_back(img: Image) -> void:
	rect(img, 0, 0, 64, 88, Color("e9dcb8"))
	rect(img, 2, 2, 60, 84, Color("2f5d3a"))
	rect(img, 4, 4, 56, 80, Color("e9dcb8"))
	rect(img, 6, 6, 52, 76, Color("3e7a4c"))
	for i in range(0, 52, 4):
		px(img, 6 + i, 6, GOLD); px(img, 6 + i, 81, GOLD)
	# derrick emblem
	for y in range(26, 62):
		var half := int((y - 24) * 0.33)
		px(img, 32 - half, y, GOLD)
		px(img, 32 + half, y, GOLD)
		if y % 6 == 0:
			line(img, Vector2(32 - half, y), Vector2(32 + half, y), GOLD)
	circle(img, 32, 20, 3, GOLD)


func draw_card_front(img: Image, band: Color) -> void:
	rect(img, 0, 0, 64, 88, INK)
	rect(img, 1, 1, 62, 86, PAPER)
	rect(img, 3, 3, 58, 12, band)
	rect(img, 6, 18, 52, 26, band.lightened(0.55))
	for y in range(30, 44):
		var half := int((y - 28) * 0.4)
		px(img, 32 - half, y, band.darkened(0.3))
		px(img, 32 + half, y, band.darkened(0.3))
	rect(img, 6, 44, 52, 1, band.darkened(0.3))


func draw_cutaway(img: Image) -> void:
	for y in 24:
		rect(img, 0, y, 200, 1, SKY.lerp(Color("f6d39a"), y / 24.0))
	rect(img, 0, 22, 200, 2, SCRUB)
	var bands := [[24, 32], [56, 32], [88, 32]]
	for i in 3:
		rect(img, 0, bands[i][0], 200, bands[i][1], STRATA[i])
		for k in 40:
			var rx := (k * 37 + i * 11) % 200
			var ry: int = bands[i][0] + 3 + (k * 13) % (bands[i][1] - 6)
			px(img, rx, ry, STRATA[i].darkened(0.2))
		rect(img, 0, bands[i][0], 200, 1, STRATA[i].darkened(0.25))


func draw_bit(img: Image) -> void:
	rect(img, 3, 0, 2, 6, STEEL)
	for y in range(6, 12):
		var half := int((12 - y) * 0.6)
		rect(img, 4 - half, y, half * 2, 1, STEEL_DARK)
	outline(img)


func draw_big_rig(img: Image) -> void:
	for y in range(2, 40):
		var half := int(1 + (y - 2) * 0.3)
		px(img, 24 - half, y, WOOD_LIGHT)
		px(img, 24 + half, y, WOOD_LIGHT)
		if y % 6 == 0:
			line(img, Vector2(24 - half, y), Vector2(24 + half, y), WOOD)
	rect(img, 22, 0, 5, 3, STEEL)
	rect(img, 6, 40, 36, 6, STEEL_DARK)
	rect(img, 32, 34, 10, 6, Color("b0322a"))
	outline(img)


func draw_ground(img: Image) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	rect(img, 0, 0, 32, 32, DIRT)
	for i in 70:
		px(img, r.randi_range(0, 31), r.randi_range(0, 31), DIRT_DARK if i % 2 == 0 else DIRT_LIGHT)
	for i in 4:
		var x := r.randi_range(2, 29)
		var y := r.randi_range(3, 29)
		px(img, x, y, SCRUB); px(img, x - 1, y, SCRUB); px(img, x + 1, y - 1, SCRUB); px(img, x, y - 1, SCRUB.lightened(0.2))


func draw_menu_bg(img: Image) -> void:
	for y in 360:
		var t := y / 360.0
		var c := Color("f4c26b").lerp(Color("c8562e"), clampf(t * 1.6, 0, 1))
		if y > 250:
			c = DIRT_DARK.lerp(Color("4a3020"), (y - 250) / 110.0)
		rect(img, 0, y, 640, 1, c)
	circle(img, 470, 220, 34, Color("f7e2a0"))
	for i in 9:
		var x := 260 + i * 44
		var hgt := 60 + (i * 23) % 50
		for y in range(250 - hgt, 250):
			var half := int((y - (250 - hgt)) * 0.18) + 1
			px(img, x - half, y, Color("2b1a12"))
			px(img, x + half, y, Color("2b1a12"))
			if y % 8 == 0:
				line(img, Vector2(x - half, y), Vector2(x + half, y), Color("2b1a12"))


func draw_level_bg(img: Image, chapter: int, idx: int) -> void:
	# Placeholder: chapter-colored sky and ground with a row of derrick silhouettes.
	var skies := [[Color("f4c26b"), Color("c8562e")], [Color("a9c7b0"), Color("3f6b4a")], [Color("f2b07a"), Color("b0503a")],
		[Color("9fd0e0"), Color("3d6f8f")], [Color("2a2a5a"), Color("0f1028")]]
	var grounds := [DIRT_DARK, Color("7a3f2a"), Color("b07a4a"), Color("d8c69a"), Color("2b2018")]
	var sky: Array = skies[chapter]
	var horizon := 230 + (idx % 3) * 10
	for y in 360:
		var c: Color = sky[0].lerp(sky[1], clampf(float(y) / horizon, 0, 1))
		if y > horizon:
			c = grounds[chapter].lerp(Color("2b1a12"), (y - horizon) / float(360 - horizon) * 0.6)
		rect(img, 0, y, 640, 1, c)
	for i in 4 + idx % 5:
		var x := 40 + ((i * 137 + idx * 61) % 560)
		var hgt := 40 + (i * 29 + idx * 13) % 60
		for y in range(horizon - hgt, horizon):
			var half := int((y - (horizon - hgt)) * 0.18) + 1
			px(img, x - half, y, Color("1d1611"))
			px(img, x + half, y, Color("1d1611"))
			if y % 8 == 0:
				line(img, Vector2(x - half, y), Vector2(x + half, y), Color("1d1611"))


func draw_logo(img: Image) -> void:
	rect(img, 0, 8, 256, 40, Color("1d1611"))
	rect(img, 2, 10, 252, 36, Color("c8402e"))
	rect(img, 4, 12, 248, 32, Color("e9dcb8"))
	rect(img, 40, 52, 176, 10, Color("1d1611"))
	# Text is drawn by the UI over this placeholder.


func draw_panel(img: Image) -> void:
	rect(img, 0, 0, 24, 24, INK)
	rect(img, 1, 1, 22, 22, Color("6b4428"))
	rect(img, 2, 2, 20, 20, Color("e9dcb8"))
	rect(img, 3, 3, 18, 18, PAPER)


func draw_button(img: Image) -> void:
	rect(img, 0, 0, 24, 16, INK)
	rect(img, 1, 1, 22, 14, Color("c99a2e"))
	rect(img, 1, 1, 22, 2, GOLD)
	rect(img, 1, 13, 22, 2, Color("8a6a1c"))


# --- Character ------------------------------------------------------------------

## Pose for animation row r, frame f.
func pose(r: int, f: int) -> Dictionary:
	match r:
		0: return {"bob": [0, 0, 1, 1][f], "arm_l": 0.15, "arm_r": -0.15, "head_dy": 0, "jump": 0}
		1: return {"bob": [0, 1, 0, 1][f], "arm_l": 0.9, "arm_r": -0.9, "head_dy": 0, "jump": 0, "lean": 1}
		2: return {"bob": 0, "arm_l": 2.6 + [0.0, 0.3, 0.0, -0.3][f], "arm_r": -2.6 - [0.0, 0.3, 0.0, -0.3][f], "head_dy": 0, "jump": [0, -3, -4, -1][f]}
		_: return {"bob": [1, 1, 2, 1][f], "arm_l": 0.05, "arm_r": -0.05, "head_dy": 2, "jump": 0}


func draw_figure_sheet(img: Image, layer: String) -> void:
	for r in 4:
		for f in 4:
			draw_figure(img, f * 32, r * 48, pose(r, f), r, layer)


func draw_figure(img: Image, ox: int, oy: int, p: Dictionary, row: int, layer: String) -> void:
	var y0: int = oy + int(p.bob) + int(p.jump)
	var lean: int = p.get("lean", 0)
	var hx := ox + 16 + lean
	var hy := y0 + 12 + int(p.head_dy)
	var shoulder := Vector2(ox + 16, y0 + 20)
	match layer:
		"skin":
			circle(img, hx, hy, 5.0, WHITE)
			for side in [-1, 1]:
				var ang: float = p.arm_l if side < 0 else p.arm_r
				var hand := shoulder + Vector2(side * 4, 0) + Vector2(side * sin(absf(ang)) * 7, cos(ang) * 9 if absf(ang) < 1.6 else -cos(PI - absf(ang)) * 9)
				circle(img, hand.x, hand.y, 1.6, WHITE)
		"outfit":
			rect(img, ox + 11, y0 + 18, 11, 13, GREY) # torso
			rect(img, ox + 12, y0 + 31, 4, 12, GREY_DARK) # legs
			rect(img, ox + 17, y0 + 31, 4, 12, GREY_DARK)
			rect(img, ox + 11, y0 + 43, 5, 3, Color(0.25, 0.25, 0.25)) # boots
			rect(img, ox + 17, y0 + 43, 5, 3, Color(0.25, 0.25, 0.25))
			for side in [-1, 1]:
				var ang: float = p.arm_l if side < 0 else p.arm_r
				var s := shoulder + Vector2(side * 4, 0)
				var hand := s + Vector2(side * sin(absf(ang)) * 7, cos(ang) * 9 if absf(ang) < 1.6 else -cos(PI - absf(ang)) * 9)
				line(img, s, hand, GREY)
				line(img, s + Vector2(side, 0), hand + Vector2(side, 0), GREY)
		"face":
			var eye_y := hy - 1
			px(img, hx - 2, eye_y, INK); px(img, hx + 2, eye_y, INK)
			rect(img, hx - 2, hy + 2, 5, 1, Color("5a3a22")) # mustache
			match row:
				2: rect(img, hx - 1, hy + 3, 3, 1, Color("7a1f1f"))
				3: px(img, hx - 1, hy + 4, INK); px(img, hx + 1, hy + 4, INK)
			rect(img, ox + 11, y0 + 29, 11, 1, Color("3a2a1a")) # belt
			px(img, ox + 16, y0 + 29, GOLD)
		"stetson":
			rect(img, hx - 8, hy - 5, 17, 2, GREY)
			rect(img, hx - 4, hy - 9, 9, 4, GREY)
			rect(img, hx - 4, hy - 6, 9, 1, GREY_DARK)
		"derby":
			rect(img, hx - 6, hy - 5, 13, 1, GREY_DARK)
			circle(img, hx, hy - 7, 4, GREY)
		"hardhat":
			rect(img, hx - 7, hy - 4, 15, 1, GREY_DARK)
			circle(img, hx, hy - 5, 5, GREY)
			rect(img, hx - 6, hy - 4, 13, 2, Color(0, 0, 0, 0))
			rect(img, hx - 7, hy - 4, 15, 1, GREY_DARK)
		"flatcap":
			rect(img, hx - 5, hy - 7, 10, 3, GREY)
			rect(img, hx + 2, hy - 5, 6, 1, GREY_DARK)
		"tengallon":
			rect(img, hx - 9, hy - 5, 19, 2, GREY)
			rect(img, hx - 5, hy - 12, 11, 7, GREY)
			rect(img, hx - 5, hy - 7, 11, 1, GREY_DARK)
		"tophat":
			rect(img, hx - 7, hy - 5, 15, 1, GREY_DARK)
			rect(img, hx - 4, hy - 13, 9, 8, GREY)
			rect(img, hx - 4, hy - 7, 9, 1, GREY_DARK)


func draw_portrait_sheet(img: Image, layer: String) -> void:
	for r in 4:
		for f in 2:
			var ox := f * 24
			var oy := r * 24
			var bob := f if r != 2 else -f
			var hx := ox + 12
			var hy := oy + 10 + bob + (2 if r == 3 else 0)
			match layer:
				"skin":
					circle(img, hx, hy, 6.0, WHITE)
				"outfit":
					rect(img, ox + 3, oy + 18, 18, 6, GREY)
					rect(img, ox + 10, oy + 18, 4, 6, Color(0.9, 0.9, 0.9))
				"face":
					px(img, hx - 2, hy - 1, INK); px(img, hx + 2, hy - 1, INK)
					rect(img, hx - 2, hy + 2, 5, 1, Color("5a3a22"))
					if r == 2:
						rect(img, hx - 1, hy + 3, 3, 1, Color("7a1f1f"))
					elif r == 3:
						px(img, hx - 1, hy + 4, INK); px(img, hx + 1, hy + 4, INK)
					elif r == 1:
						px(img, hx - 3, hy - 3, INK); px(img, hx + 3, hy - 3, INK)
					rect(img, ox + 11, oy + 19, 2, 4, Color("7a1f1f")) # tie
				"stetson":
					rect(img, hx - 9, hy - 5, 19, 2, GREY)
					rect(img, hx - 5, hy - 9, 11, 4, GREY)
				"derby":
					rect(img, hx - 7, hy - 5, 15, 1, GREY_DARK)
					circle(img, hx, hy - 7, 4.5, GREY)
				"hardhat":
					circle(img, hx, hy - 5, 6, GREY)
					rect(img, hx - 6, hy - 4, 13, 3, Color(0, 0, 0, 0))
					rect(img, hx - 8, hy - 5, 17, 1, GREY_DARK)
				"flatcap":
					rect(img, hx - 6, hy - 8, 12, 3, GREY)
					rect(img, hx + 2, hy - 5, 7, 1, GREY_DARK)
				"tengallon":
					rect(img, hx - 10, hy - 5, 21, 2, GREY)
					rect(img, hx - 5, hy - 10, 11, 5, GREY)
				"tophat":
					rect(img, hx - 7, hy - 5, 15, 1, GREY_DARK)
					rect(img, hx - 4, hy - 10, 9, 5, GREY)
					rect(img, hx - 4, hy - 6, 9, 1, GREY_DARK)


func draw_campaign_map(img: Image) -> void:
	var bands := [
		[0, 100, Color("6d5a7a"), Color("8c7a94")],   # Big Board: dusky city sky
		[100, 140, Color("c9b27e"), Color("d8c38f")],  # Gulf coast sand
		[140, 192, Color("c7a46a"), Color("d6b77d")],  # Gulf / transition
		[192, 246, Color("d9b780"), Color("e6c995")],  # Permian caprock
		[246, 300, Color("6f7d3c"), Color("85934c")],  # East Texas pines
		[300, 360, Color("b98a57"), Color("c99a65")],  # Boomtown dust
	]
	for b in bands:
		for y in range(b[0], b[1]):
			rect(img, 0, y, 640, 1, (b[2] as Color).lerp(b[3], float(y - b[0]) / (b[1] - b[0])))
	var r := RandomNumberGenerator.new()
	r.seed = 21
	# Gulf water on the left.
	for y in range(130, 200):
		var w := int(46 + 20 * sin(y * 0.09))
		rect(img, 0, y, w, 1, Color("3f7d8c"))
		px(img, w, y, Color("e9dcb8"))
	# Pines.
	for i in 140:
		var x := r.randi_range(0, 639)
		var y := r.randi_range(250, 296)
		for k in 4:
			rect(img, x - k, y + k, 1 + k * 2, 1, Color("3e5a2a"))
		px(img, x, y + 4, WOOD)
	# Mesas.
	for i in 6:
		var x := r.randi_range(10, 600)
		var y := r.randi_range(196, 236)
		rect(img, x, y, r.randi_range(18, 40), 6, Color("b5854f"))
		rect(img, x, y, 40, 1, Color("8a6239"))
	# Skyline.
	var x := 0
	while x < 640:
		var w := r.randi_range(10, 26)
		var h := r.randi_range(20, 70)
		rect(img, x, 100 - h, w - 2, h, Color("3a2a3a"))
		for wy in range(100 - h + 4, 98, 6):
			for wx in range(x + 2, x + w - 4, 4):
				if r.randf() < 0.4:
					px(img, wx, wy, GOLD)
		x += w
	# Boomtown shacks and derricks.
	for i in 22:
		var bx := r.randi_range(0, 630)
		var by := r.randi_range(304, 352)
		if r.randf() < 0.5:
			rect(img, bx, by, 8, 6, Color("7a4e2a"))
			rect(img, bx - 1, by - 2, 10, 2, Color("5a3a1e"))
		else:
			for yy in range(by - 12, by):
				var half := int((yy - (by - 12)) * 0.3)
				px(img, bx - half, yy, Color("4a3020"))
				px(img, bx + half, yy, Color("4a3020"))
	# Dither the band seams.
	for y in [100, 140, 192, 246, 300]:
		for xx in range(0, 640, 2):
			px(img, xx, y, Color(0, 0, 0, 0.25))


func draw_star(img: Image, filled: bool) -> void:
	var rows := [
		"....#....",
		"...###...",
		"...###...",
		"#########",
		".#######.",
		"..#####..",
		"..##.##..",
		".##...##.",
		".#.....#.",
	]
	var top := GOLD if filled else Color("a8987a")
	var low := Color("c98f1e") if filled else Color("857559")
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				px(img, x, y, top if y < 4 else low)
