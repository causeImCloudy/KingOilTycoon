extends Control
## Classic Game setup: you against 3 AI tycoons on the 18-property board, under the original
## 1974 board-game rules and costs (GameState settings.rules = "original").

const LEVELS := ["Easy", "Medium", "Hard"]
const RIVAL_IDS := ["hardpan", "dolores", "pickett", "ruby", "blackwood"]

var name_edit: LineEdit
var rivals: Array = [] # [{id, level}]
var seed_edit: LineEdit
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	UiKit.backdrop(self)
	UiKit.header(self, "Classic Game", func(): Session.goto("menu"))
	var pnl := UiKit.panel(8)
	pnl.position = Vector2(12, 30)
	pnl.custom_minimum_size = Vector2(308, 0)
	add_child(pnl)
	var v := UiKit.vbox(4)
	pnl.add_child(v)
	var intro := UiKit.label("You against three rival tycoons, played exactly by the original board-game rules.", 8)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(264, 0)
	v.add_child(intro)

	var you := UiKit.hbox(4)
	v.add_child(you)
	var sw := ColorRect.new()
	sw.color = GameConst.PLAYER_COLORS[0]
	sw.custom_minimum_size = Vector2(10, 14)
	you.add_child(sw)
	name_edit = LineEdit.new()
	name_edit.text = Profile.data.name
	name_edit.custom_minimum_size = Vector2(170, 18)
	you.add_child(name_edit)
	you.add_child(UiKit.label("You", 8))

	var ids := RIVAL_IDS.duplicate()
	ids.shuffle()
	for i in 3:
		var row := UiKit.hbox(4)
		v.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = GameConst.PLAYER_COLORS[i + 1]
		swatch.custom_minimum_size = Vector2(10, 14)
		row.add_child(swatch)
		var rid: String = ids[i]
		var rival := {"id": rid, "level": GameConst.AI_MEDIUM}
		rivals.append(rival)
		var nm := UiKit.label(str(Session.campaign.rivals[rid].name), 8)
		nm.custom_minimum_size = Vector2(146, 0)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.tooltip_text = nm.text
		row.add_child(nm)
		row.add_child(UiKit.option(LEVELS, GameConst.AI_MEDIUM, func(k): rival.level = k))

	var row2 := UiKit.hbox(6)
	v.add_child(row2)
	row2.add_child(UiKit.label("Oil field seed", 8))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size = Vector2(90, 16)
	row2.add_child(seed_edit)
	v.add_child(UiKit.button("Start Classic Game", _start))

	var info := UiKit.panel(8)
	info.position = Vector2(328, 30)
	info.size = Vector2(304, 322)
	add_child(info)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.add_child(scroll)
	var iv := UiKit.vbox(2)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(iv)
	iv.add_child(UiKit.label("The rules", 10))
	for line in [
		"$80,000 each. The bank holds the rest of $825,000.",
		"Pick a starting property ($8,000-$12,000).",
		"Each turn: pay royalties, draw a card, collect per well.",
		"Drill 1+ wells a turn: $2k / $4k / $6k, dry $6k. No empty holes: $10k fine.",
		"Pipelines: $25k, need 4/5/6 wells, 3 max. Royalty $1k/$3k/$5k per derrick on the land piped into.",
		"Short on cash? Drilling and fines stop at $0. Only a pipeline royalty you can't pay (at the start of your turn) bankrupts you; the bank auctions your land.",
		"Last one standing wins, or top net worth when the bank runs dry.",
	]:
		var l := UiKit.label("- " + line, 8)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(l)


func _start() -> void:
	var players: Array = []
	var nm := name_edit.text.strip_edges()
	players.append({"name": nm if nm != "" else "You", "is_ai": false, "ai_level": 1,
		"character": Profile.look(), "color": 0})
	for i in rivals.size():
		var r: Dictionary = Session.campaign.rivals[rivals[i].id]
		players.append({"name": str(r.get("short", r.name)), "is_ai": true, "ai_level": rivals[i].level,
			"character": r.look.duplicate(true), "color": i + 1})
	var seed_value := int(seed_edit.text) if seed_edit.text.is_valid_int() else 0
	Session.start_offline({
		"seed": seed_value,
		"map_type": "classic_1974",
		"speed": "original",
		"rules": "original",
		"players": players,
	})
