extends Control
## The match screen. Owns the GameState when offline/hosting; mirrors the host's public state
## as a client. Every state change arrives as a list of events that play through an animation
## queue; the board and panels show a display copy that each event updates.

const SCREEN := Vector2(640, 360)
const TOP_H: float = 22.0
const BOARD_POS := Vector2(6, 26)
const BOARD_MAX := Vector2(360, 248)
## Status panel top: right under the board frame (board ends at y 270, frame at 272).
const STATUS_Y: float = 274.0
const SIDE_X: float = 370.0
const SIDE_W: float = 266.0
## Top of the action panel (deck, card, rig, buttons) in the side column.
const ACT_Y: float = 214.0

var state: GameState
var net_mode: String = "offline"
var ai_rng := RandomNumberGenerator.new()

var board_view: BoardView
var panels: Array[PlayerPanel] = []
var view_players: Array = []

var top_label: Label
var timer_label: Label
var hint_label: Label
## Fixed property fields under the board, by key: value labels that update in place.
var plot_fields: Dictionary = {}
var owner_swatch: ColorRect
var info_buttons: HBoxContainer
var card_label: Label
var deck_rect: TextureRect
var rig_tray: TextureRect
var rig_count: Label
## "Buy Land" when land is for sale (hidden otherwise: you draw by clicking the deck).
var draw_btn: Button
## The deck can be clicked to draw (your turn, before drawing); it glows while it can.
var _deck_ready: bool = false
var _deck_t: float = 0.0
var end_btn: Button
var overlay: Control
var banner: Label
var big_card: CardView
var drill_popup: DrillPopup
var pause_menu: Control
var result_panel: Control

var _queue: Array = []
var _playing: bool = false
var _fast: bool = false
var _dragging: bool = false
var _armed: bool = false
var _drag_ghost: TextureRect
var _ai_pending: bool = false
var _turn_time_left: float = 0.0
## Original rules: the local player's top bid on the property being auctioned.
var _bid_amount: int = 0
var _bid_label: Label
var _rewards_given: bool = false
## The campaign county battle being played (Session.battle_def), or {} outside the campaign.
var _battle: Dictionary = {}
## Trading: the side panel for making a deal ("compose") or answering one ("reply").
var _trade_panel: Control
var _trade_view: String = ""
## The deal being put together: {to, give_cash, get_cash, give_plots, get_plots, land_right}.
var _deal: Dictionary = {}

const GIVE_COLOR := Color("ff8a6a")
const GET_COLOR := Color("b8f08a")


func _ready() -> void:
	if Session.campaign_county >= 0:
		_battle = Session.battle_def(Session.campaign_county)
	net_mode = Session.net_mode
	if not Session.resume_state.is_empty():
		if Session.resume_state.has("oil"):
			state = GameState.from_dict(Session.resume_state)
		else:
			state = GameState.from_dict(Session.resume_state) # client mirror
	else:
		state = GameState.new_match(Session.match_config)
	ai_rng.seed = int(state.settings.get("seed", 1)) ^ 0x5eed
	_build_ui()
	view_players = state.players.duplicate(true)
	board_view.sync_from(state)
	_refresh_all(false)
	Sfx.music("match")
	if net_mode != "offline":
		Net.update_received.connect(_on_net_update)
		Net.action_received.connect(_on_net_action)
		Net.peer_left.connect(_on_peer_left)
		Net.connection_lost.connect(_on_connection_lost)
	if net_mode == "host":
		Net.broadcast_update([], state.to_dict(false))
	if state.turn_number == 0 and state.phase == GameConst.PHASE_DRAFT:
		var first: Array = [{"type": "draft_next", "player": state.current}]
		if not _battle.is_empty():
			first.push_front({"type": "level_intro"})
		_enqueue(first)
	else:
		_enqueue([{"type": "turn_start", "player": state.current, "turn": state.turn_number, "round": state.round_number, "resume": true}])


# --- UI construction ------------------------------------------------------------------

func _build_ui() -> void:
	# The board is a Node2D that reads clicks in _unhandled_input, so no Control may sit on
	# top of (or behind) it with mouse_filter STOP - the root and the board frame included.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color("3a2a1f")
	bg.size = SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Campaign levels have their own background art, dimmed behind the board.
	var level_tex := _level_background()
	if level_tex:
		var level_bg := TextureRect.new()
		level_bg.texture = level_tex
		level_bg.size = SCREEN
		level_bg.stretch_mode = TextureRect.STRETCH_SCALE
		level_bg.modulate = Color(0.4, 0.36, 0.34)
		level_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(level_bg)

	# Top bar.
	var top := ColorRect.new()
	top.color = Color("1d1611")
	top.size = Vector2(SCREEN.x, TOP_H)
	add_child(top)
	top_label = UiKit.label("", 8, Color("efe3c6"))
	top_label.position = Vector2(6, 3)
	add_child(top_label)
	timer_label = UiKit.label("", 8, Color("f2c14e"))
	timer_label.position = Vector2(470, 3)
	add_child(timer_label)
	var menu_btn := UiKit.button("Menu", _toggle_pause, 8)
	menu_btn.position = Vector2(584, 1)
	menu_btn.size = Vector2(52, 20)
	add_child(menu_btn)

	# Board.
	var board_frame := ColorRect.new()
	board_frame.color = Color("1d1611")
	board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_frame)
	board_view = BoardView.new()
	board_view.position = BOARD_POS
	board_view.setup(state.board, state.players, BOARD_MAX)
	board_view.decor = _board_decor()
	var bs := board_view.pixel_size()
	board_view.position = BOARD_POS + ((BOARD_MAX - bs) / 2).floor()
	board_frame.position = board_view.position - Vector2(2, 2)
	board_frame.size = bs + Vector2(4, 4)
	add_child(board_view)
	board_view.plot_clicked.connect(_on_plot_clicked)
	board_view.site_clicked.connect(_on_site_clicked)
	board_view.hovered.connect(_on_hover)

	# Status bar under the board.
	# Layout: turn hint (up to 2 lines), a fixed row of property fields, then action buttons.
	var status := UiKit.panel(4)
	status.position = Vector2(4, STATUS_Y)
	status.size = Vector2(SIDE_X - 8, SCREEN.y - STATUS_Y - 4)
	status.custom_minimum_size = status.size
	status.clip_contents = true
	add_child(status)
	var sv := UiKit.vbox(2)
	status.add_child(sv)
	hint_label = UiKit.label("", 8, Color("7a2a1a"))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(SIDE_X - 40, 0)
	hint_label.max_lines_visible = 2
	hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sv.add_child(hint_label)
	sv.add_child(_build_plot_fields())
	info_buttons = UiKit.hbox(4)
	sv.add_child(info_buttons)

	# Player panels.
	# Scrolls if 5-6 players don't fit at large text sizes.
	var pscroll := ScrollContainer.new()
	pscroll.position = Vector2(SIDE_X, TOP_H + 4)
	pscroll.size = Vector2(SIDE_W, ACT_Y - TOP_H - 8)
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(pscroll)
	var plist := UiKit.vbox(3)
	plist.custom_minimum_size = Vector2(SIDE_W - 2, 0)
	pscroll.add_child(plist)
	for p in state.players:
		var pp := PlayerPanel.new()
		pp.custom_minimum_size = Vector2(SIDE_W - 2, 0)
		pp.build(p, board_view.player_color(p.index))
		plist.add_child(pp)
		pp.clicked.connect(_on_player_clicked)
		panels.append(pp)

	# Action panel: deck + card summary + rig tray on top, Draw / End Turn side by side below.
	var act := UiKit.panel(5)
	act.position = Vector2(SIDE_X, ACT_Y)
	act.custom_minimum_size = Vector2(SIDE_W, SCREEN.y - ACT_Y - 4)
	act.size = act.custom_minimum_size
	add_child(act)
	var av := UiKit.vbox(6)
	act.add_child(av)
	var top_row := UiKit.hbox(6)
	av.add_child(top_row)
	deck_rect = TextureRect.new()
	deck_rect.texture = UiKit.tex("res://assets/sprites/card_back.png")
	deck_rect.stretch_mode = TextureRect.STRETCH_KEEP
	deck_rect.custom_minimum_size = CardView.ART_SIZE
	deck_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	deck_rect.tooltip_text = "Event deck"
	deck_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	deck_rect.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _deck_ready:
			_on_draw_pressed())
	top_row.add_child(deck_rect)
	var right := UiKit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(right)
	card_label = UiKit.label("", 8)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.custom_minimum_size = Vector2(SIDE_W - 2 * (5 + UiKit.PAD_X) - CardView.ART_SIZE.x - 6, 0)
	card_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(card_label)
	var rig_row := UiKit.hbox(6)
	right.add_child(rig_row)
	var tray := PanelContainer.new()
	var tray_sb := StyleBoxFlat.new()
	tray_sb.bg_color = Color("6b4428")
	tray_sb.border_color = Color("1d1611")
	tray_sb.set_border_width_all(1)
	tray.add_theme_stylebox_override("panel", tray_sb)
	tray.tooltip_text = "Drag the rig onto one of your drill sites (or click it, then click a site)"
	rig_row.add_child(tray)
	var tray_box := Control.new()
	tray_box.custom_minimum_size = Vector2(34, 36)
	tray.add_child(tray_box)
	rig_tray = TextureRect.new()
	rig_tray.texture = UiKit.tex("res://assets/sprites/drill_rig.png")
	rig_tray.position = Vector2(5, 2)
	rig_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	rig_tray.mouse_default_cursor_shape = Control.CURSOR_DRAG
	rig_tray.gui_input.connect(_on_rig_input)
	tray_box.add_child(rig_tray)
	rig_count = UiKit.label("", 8, Color("6b4428"))
	rig_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rig_row.add_child(rig_count)
	var btns := UiKit.hbox(6)
	av.add_child(btns)
	draw_btn = UiKit.button("Buy Land", _on_draw_pressed, 8)
	draw_btn.tooltip_text = "Pick a FOR SALE plot on the board"
	draw_btn.visible = false
	draw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(draw_btn)
	end_btn = UiKit.button("End Turn", _on_end_pressed, 8)
	end_btn.tooltip_text = "End your turn (Enter)"
	end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(end_btn)

	# Overlay for animations and pop-ups.
	overlay = Control.new()
	overlay.size = SCREEN
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	banner = UiKit.label("", UiKit.FONT_TITLE, Color("f2c14e"))
	banner.add_theme_color_override("font_outline_color", Color("1d1611"))
	banner.add_theme_constant_override("outline_size", 4)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(SIDE_X - 8, 24)
	banner.position = Vector2(4, 140)
	banner.visible = false
	overlay.add_child(banner)
	big_card = CardView.new()
	big_card.visible = false
	overlay.add_child(big_card)
	drill_popup = DrillPopup.new()
	drill_popup.build(SCREEN)
	add_child(drill_popup)
	_drag_ghost = TextureRect.new()
	_drag_ghost.texture = UiKit.tex("res://assets/sprites/drill_rig.png")
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate = Color(1, 1, 1, 0.85)
	_drag_ghost.visible = false
	add_child(_drag_ghost)


# --- Helpers --------------------------------------------------------------------------

func anim_speed() -> float:
	var s := float(Profile.setting("anim_speed")) * float(state.speed.get("anim_speed", 1.0))
	return s * (4.0 if _fast else 1.0)


func instant() -> bool:
	return float(Profile.setting("anim_speed")) >= 10.0


func my_peer_id() -> int:
	return 1 if net_mode != "client" else multiplayer.get_unique_id()


func is_local(p: int) -> bool:
	if p < 0 or p >= state.players.size():
		return false
	var pl: Dictionary = state.players[p]
	if pl.is_ai:
		return false
	if net_mode == "offline":
		return true
	return int(pl.net_id) == my_peer_id()


func is_authority() -> bool:
	return net_mode != "client"


func my_turn() -> bool:
	return not _playing and state.phase != GameConst.PHASE_GAME_OVER and is_local(state.current)


func pname(p: int) -> String:
	return str(state.players[p].name) if p >= 0 and p < state.players.size() else "The bank"


func wait(sec: float) -> void:
	if instant():
		return
	await get_tree().create_timer(sec / anim_speed()).timeout


# --- Submitting actions --------------------------------------------------------------------

func submit(action: Dictionary) -> void:
	if not action.has("player"):
		action["player"] = state.current
	if net_mode == "client":
		Net.send_action(action)
		_set_controls_enabled(false)
		return
	var r := state.apply(action)
	if not r.ok:
		hint_label.text = r.error
		return
	if net_mode == "host":
		Net.broadcast_update(r.events, state.to_dict(false))
	_enqueue(r.events)


func _on_net_action(peer_id: int, action: Dictionary) -> void:
	# Host only: validate that the sender controls the current player.
	if net_mode != "host":
		return
	var p: int = state.current
	if action.get("type", "") == "bid":
		p = int(action.get("player", -1)) # every remaining player bids at an auction
	elif action.get("type", "") == "trade_reply":
		p = int(state.trade.get("to", -1)) # the player offered the deal answers it
	elif state.right_holder >= 0 and action.get("type", "") in ["buy", "pass_land"]:
		p = state.right_holder # the player who bought the land right picks
	if p < 0 or p >= state.players.size() or int(state.players[p].net_id) != peer_id or state.players[p].is_ai:
		Net.send_error(peer_id, "Not your turn")
		return
	action["player"] = p
	var r := state.apply(action)
	if not r.ok:
		Net.send_error(peer_id, r.error)
		return
	Net.broadcast_update(r.events, state.to_dict(false))
	_enqueue(r.events)


func _on_net_update(events: Array, public_state: Dictionary) -> void:
	if net_mode != "client":
		return
	state = GameState.from_dict(public_state)
	if events.is_empty():
		_after_queue()
	else:
		_enqueue(events)


func _on_peer_left(peer_id: int) -> void:
	if net_mode != "host":
		return
	for p in state.players:
		if int(p.net_id) == peer_id and not p.is_ai:
			p.is_ai = true
			p.ai_level = GameConst.AI_MEDIUM
			p.name = str(p.name) + " (AI)"
	Net.broadcast_update([], state.to_dict(false))
	_after_queue()


func _on_connection_lost() -> void:
	_show_message("Lost connection to the host.", func(): Session.goto("menu"))


# --- Event queue ----------------------------------------------------------------------

func _enqueue(events: Array) -> void:
	_queue.append_array(events)
	if not _playing:
		_play_queue()


func _play_queue() -> void:
	_playing = true
	_set_controls_enabled(false)
	_clear_modes()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await _play_event(ev)
	_playing = false
	_fast = false
	_after_queue()


func _play_event(ev: Dictionary) -> void:
	var sp := anim_speed()
	match ev.type:
		"level_intro":
			await _show_level_intro()
		"draft_next":
			_refresh_all(false)
			await _show_banner("%s: choose your starting land" % pname(ev.player), 0.9)
		"turn_start":
			_refresh_all(false)
			if net_mode == "offline" and is_authority() and not ev.get("resume", false):
				Session.save_game(state)
			_turn_time_left = float(state.speed.get("turn_timer_sec", 0))
			if ev.player < panels.size():
				panels[ev.player].portrait.play("anticipate", 1.2)
			await _show_banner("%s's turn" % pname(ev.player), 0.8)
		"plot_bought":
			view_players[ev.player].cash -= int(ev.price)
			board_view.plot_owner[ev.plot] = ev.player
			_note_land(ev.player, ev.plot)
			_refresh_panels(true)
			Sfx.play("cash")
			board_view.float_text(board_view.plot_center(ev.plot), "-" + UiKit.money(ev.price), Color("f4ecd8"), sp)
			board_view.effect_build(ev.plot, sp)
			await board_view.effect_flash_plot(ev.plot, sp)
		"plot_sold":
			view_players[ev.player].cash += int(ev.amount)
			board_view.plot_owner[ev.plot] = -1
			board_view.pipelines = board_view.pipelines.filter(func(pl): return pl.from != ev.plot and pl.to != ev.plot)
			_refresh_panels(true)
			board_view.float_text(board_view.plot_center(ev.plot), "SOLD +" + UiKit.money(ev.amount), Color("f2c14e"), sp)
			await board_view.effect_flash_plot(ev.plot, sp)
		"royalty_paid":
			view_players[ev.player].cash -= int(ev.amount)
			view_players[ev.to].cash += int(ev.amount)
			_refresh_panels(true)
			var pl := _find_pipeline(ev.pipeline)
			if not pl.is_empty():
				board_view.float_text(board_view.plot_center(pl.to), "-" + UiKit.money(ev.amount), Color("ff8a6a"), sp)
				board_view.float_text(board_view.plot_center(pl.from), "+" + UiKit.money(ev.amount), Color("b8f08a"), sp)
			hint_label.text = "%s pays %s in pipeline royalties to %s" % [pname(ev.player), UiKit.money(ev.amount), pname(ev.to)]
			await wait(0.6)
		"deck_shuffled":
			hint_label.text = "The deck is reshuffled."
			await wait(0.3)
		"card_drawn":
			await _animate_card(ev.card, ev.player)
			if ev.card.get("land", false) and is_local(ev.player):
				Sfx.play("cash")
				await _show_banner("LAND FOR SALE!", 0.8)
		"income":
			view_players[ev.player].cash += int(ev.amount)
			_refresh_panels(true)
			if int(ev.amount) > 0:
				Sfx.play("cash")
				panels[ev.player].portrait.play("cheer", 1.0)
				hint_label.text = "%s collects %s" % [pname(ev.player), UiKit.money(ev.amount)] + \
					(" from %d wells" % ev.wells if int(ev.wells) > 0 else "")
			else:
				hint_label.text = "%s has no producing wells yet." % pname(ev.player)
			await wait(0.5)
		"fire":
			panels[ev.player].portrait.play("sulk", 1.5)
			var count: int = ev.get("count", 0)
			if count > 0:
				await _show_banner("BLOWOUT FIRE!", 0.6)
				if not instant():
					await board_view.effect_fire(_wells_on_board(ev.player), sp)
				hint_label.text = "%s must cap %d well%s." % [pname(ev.player), count, "" if count == 1 else "s"]
			else:
				hint_label.text = "Fire on the lease, but %s has no wells to lose." % pname(ev.player)
				await wait(0.4)
		"well_capped":
			if not instant():
				await board_view.effect_fire([ev.site], sp * 1.5)
			if ev.saved:
				board_view.float_text(board_view.site_pos(ev.site), "Saved by fire crew!", Color("b8f08a"), sp)
			else:
				board_view.site_state[ev.site] = GameConst.SITE_BURNED
				board_view.float_text(board_view.site_pos(ev.site), "Capped", Color("ff8a6a"), sp)
			board_view.queue_redraw()
			_refresh_panels(false)
			hint_label.text = ("%d more to cap." % ev.left) if int(ev.left) > 0 else "The fire is out."
			await wait(0.3)
		"drill":
			await _animate_drill(ev)
		"pipeline":
			view_players[ev.player].cash -= int(ev.cost)
			var existing := _find_pipeline(ev.pipeline)
			if existing.is_empty():
				board_view.pipelines.append({"id": ev.pipeline, "owner": ev.player, "from": ev.from, "to": ev.to, "level": ev.level})
			else:
				existing.level = ev.level
			board_view.queue_redraw()
			_refresh_panels(true)
			Sfx.play("pipeline")
			hint_label.text = "%s lays a level %d pipeline into %s" % [pname(ev.player), ev.level, state.board.plots[ev.to].name]
			board_view.float_text(board_view.plot_center(ev.to), "PIPELINE", Color("f2c14e"), sp)
			await wait(0.6)
		"bankrupt":
			var creditor: int = ev.creditor
			view_players[ev.player].cash = 0
			view_players[ev.player].bankrupt = true
			if creditor >= 0:
				view_players[creditor].cash += int(ev.get("cash", 0))
				panels[creditor].portrait.play("cheer", 1.5)
			for plot in ev.plots:
				board_view.plot_owner[plot] = creditor
			for pl in board_view.pipelines:
				if pl.owner == ev.player:
					pl.owner = creditor
			board_view.pipelines = board_view.pipelines.filter(func(pl): return pl.owner >= 0 and board_view.plot_owner[pl.to] != pl.owner)
			board_view.queue_redraw()
			_refresh_panels(false)
			panels[ev.player].portrait.play("sulk")
			if ev.get("reason", "") == "auction":
				hint_label.text = "%s can't pay and is out of the game. The bank auctions their land." % pname(ev.player)
				await _show_banner("%s is BANKRUPT!" % pname(ev.player), 1.2)
			elif ev.get("reason", "") == "no_land":
				hint_label.text = "%s has no land left and is out of the game." % pname(ev.player)
				await _show_banner("%s is OUT!" % pname(ev.player), 1.4)
			else:
				hint_label.text = "%s takes everything: %s, %d plot%s with their wells%s." % [
					pname(creditor), UiKit.money(int(ev.get("cash", 0))), ev.plots.size(), "" if ev.plots.size() == 1 else "s",
					(", and %d pipeline%s" % [ev.pipelines, "" if int(ev.pipelines) == 1 else "s"]) if int(ev.get("pipelines", 0)) > 0 else ""]
				await _show_banner("%s is BANKRUPT!" % pname(ev.player), 1.2)
				for plot in ev.plots:
					board_view.effect_flash_plot(plot, anim_speed())
				await wait(0.8)
		"penalty":
			view_players[ev.player].cash -= int(ev.amount)
			_refresh_panels(true)
			panels[ev.player].portrait.play("sulk", 1.2)
			hint_label.text = "%s pays a %s penalty: %s." % [pname(ev.player), UiKit.money(ev.amount), str(ev.reason).to_lower()]
			await _show_banner("PENALTY %s" % UiKit.money(ev.amount), 0.9)
		"pipeline_removed":
			var gone := _find_pipeline(ev.pipeline)
			if not gone.is_empty():
				gone.level = int(ev.level)
				if gone.level <= 0:
					board_view.pipelines.erase(gone)
			board_view.queue_redraw()
			hint_label.text = "Too few wells left on %s: one of %s's pipelines is torn out." % [state.board.plots[ev.from].name, pname(ev.player)]
			await wait(0.6)
		"auction_lot":
			board_view.selected_plot = ev.plot
			board_view.queue_redraw()
			hint_label.text = "The bank auctions %s (%d of %d)." % [state.board.plots[ev.plot].name, int(ev.index) + 1, ev.total]
			await _show_banner("AUCTION: %s" % state.board.plots[ev.plot].name, 0.8)
			await board_view.effect_flash_plot(ev.plot, sp)
		"bid_placed":
			pass
		"auction_won":
			view_players[ev.player].cash -= int(ev.price)
			board_view.plot_owner[ev.plot] = ev.player
			_note_land(ev.player, ev.plot)
			board_view.effect_build(ev.plot, sp)
			for pl in board_view.pipelines:
				if pl.from == ev.plot:
					pl.owner = ev.player
			board_view.pipelines = board_view.pipelines.filter(func(pl): return board_view.plot_owner[pl.to] != pl.owner)
			board_view.queue_redraw()
			_refresh_panels(true)
			Sfx.play("cash")
			panels[ev.player].portrait.play("cheer", 1.0)
			var bid_txt: Array[String] = []
			for k in ev.bids:
				bid_txt.append("%s %s" % [pname(int(k)), UiKit.money(ev.bids[k]) if int(ev.bids[k]) > 0 else "passed"])
			hint_label.text = "SOLD to %s for %s.\nTop bids: %s" % [pname(ev.player), UiKit.money(ev.price), ", ".join(bid_txt)]
			board_view.float_text(board_view.plot_center(ev.plot), "SOLD " + UiKit.money(ev.price), Color("f2c14e"), sp)
			await wait(1.0)
		"auction_closed":
			board_view.plot_owner[ev.plot] = GameConst.PLOT_CLOSED
			board_view.pipelines = board_view.pipelines.filter(func(pl): return pl.from != ev.plot and pl.to != ev.plot)
			board_view.queue_redraw()
			hint_label.text = "Nobody bid on %s. It's closed for the rest of the game." % state.board.plots[ev.plot].name
			await wait(0.8)
		"auction_over":
			board_view.selected_plot = -1
		"trade_offered":
			var t: Dictionary = ev.trade
			Sfx.play("click")
			hint_label.text = "%s offers %s a deal." % [pname(int(t.from)), pname(int(t.to))]
			board_view.trade_marks = _trade_marks(t)
			if is_local(int(t.to)) and not is_local(int(t.from)):
				await _show_banner("TRADE OFFER!", 0.7)
			else:
				await wait(0.4)
		"trade_declined":
			var t: Dictionary = ev.trade
			board_view.trade_marks = {}
			panels[int(t.from)].portrait.play("sulk", 1.0)
			hint_label.text = "%s turns down %s's offer." % [pname(int(t.to)), pname(int(t.from))]
			if ev.has("reason"):
				hint_label.text = "The deal fell through: %s." % str(ev.reason).to_lower()
			await wait(0.7)
		"trade_cancelled":
			board_view.trade_marks = {}
			hint_label.text = "%s withdraws the offer." % pname(int(ev.trade.from))
			await wait(0.3)
		"trade_done":
			await _play_trade(ev, sp)
		"land_right":
			hint_label.text = "%s now holds the right to buy land this turn." % pname(int(ev.player))
			if is_local(int(ev.player)):
				await _show_banner("PICK YOUR LAND!", 0.8)
			else:
				await wait(0.4)
		"land_passed":
			hint_label.text = "%s passes on the land." % pname(int(ev.player))
			await wait(0.5)
		"turn_end":
			pass
		"game_over":
			_sync_view()
			await _show_banner("%s wins!" % pname(ev.winner), 1.2)
			_show_results(ev)


func _after_queue() -> void:
	_sync_view()
	if state.phase == GameConst.PHASE_GAME_OVER:
		return
	if state.phase == GameConst.PHASE_AUCTION:
		if is_authority() and _next_ai_bidder() >= 0:
			_run_ai()
			return
		_update_controls()
		return
	if not state.trade.is_empty():
		# A deal waits for its answer: AI players answer at once, people on the trade panel.
		if is_authority() and state.players[int(state.trade.to)].is_ai:
			_run_ai()
			return
		_update_controls()
		return
	if state.right_holder >= 0:
		# Someone bought the land right in a trade and has to pick a plot (or pass).
		if is_authority() and state.players[state.right_holder].is_ai:
			_run_ai()
			return
		_update_controls()
		return
	if is_authority() and state.players[state.current].is_ai:
		_run_ai()
		return
	_update_controls()


func _next_ai_bidder() -> int:
	for i in state.auction_bidders_left():
		if state.players[i].is_ai:
			return i
	return -1


## The local human who still has to bid on the current lot (-1 if none).
func _local_bidder() -> int:
	for i in state.auction_bidders_left():
		if is_local(i):
			return i
	return -1


func _sync_view() -> void:
	view_players = state.players.duplicate(true)
	board_view.sync_from(state)
	_refresh_all(false)


## Keeps the board's display copy of who got which land when (it decides where the house goes).
func _note_land(p: int, plot: int) -> void:
	var land: Array = board_view.players[p].get("land", [])
	land.erase(plot)
	land.append(plot)
	board_view.players[p]["land"] = land


func _find_pipeline(id: int) -> Dictionary:
	for pl in board_view.pipelines:
		if int(pl.id) == id:
			return pl
	return {}


func _run_ai() -> void:
	if _ai_pending:
		return
	_ai_pending = true
	# Always yield at least a frame so long AI-only stretches never recurse.
	await get_tree().process_frame
	await wait(0.35)
	_ai_pending = false
	if _playing or state.phase == GameConst.PHASE_GAME_OVER:
		return
	if state.phase == GameConst.PHASE_AUCTION:
		var bidder := _next_ai_bidder()
		if bidder < 0:
			return
		var br := state.apply(AIPlayer.choose_action(state, bidder, ai_rng))
		if not br.ok:
			br = state.apply({"type": "bid", "player": bidder, "amount": 0})
		if net_mode == "host":
			Net.broadcast_update(br.events, state.to_dict(false))
		_enqueue(br.events)
		return
	if not state.trade.is_empty():
		var to := int(state.trade.to)
		if not state.players[to].is_ai:
			return
		var tr := state.apply(AIPlayer.choose_action(state, to, ai_rng))
		if not tr.ok:
			tr = state.apply({"type": "trade_reply", "player": to, "accept": false})
		if net_mode == "host":
			Net.broadcast_update(tr.events, state.to_dict(false))
		_enqueue(tr.events)
		return
	if state.right_holder >= 0:
		var holder := state.right_holder
		if not state.players[holder].is_ai:
			return
		var lr := state.apply(AIPlayer.choose_action(state, holder, ai_rng))
		if not lr.ok:
			lr = state.apply({"type": "pass_land", "player": holder})
		if net_mode == "host":
			Net.broadcast_update(lr.events, state.to_dict(false))
		_enqueue(lr.events)
		return
	if not state.players[state.current].is_ai:
		return
	var a := AIPlayer.choose_action(state, state.current, ai_rng)
	if a.is_empty():
		a = {"type": "end_turn"}
	var r := state.apply(a)
	if not r.ok:
		r = state.apply({"type": "end_turn", "player": state.current})
		if not r.ok:
			r = state.apply({"type": "draw", "player": state.current})
	if net_mode == "host":
		Net.broadcast_update(r.events, state.to_dict(false))
	_enqueue(r.events)


# --- Animations -------------------------------------------------------------------------

## Board decoration: the saved layout for this campaign level or the Classic layout, otherwise
## an auto layout in the level's theme (farm country for random fields).
func _board_decor() -> Dictionary:
	var theme := str(_battle.get("board_theme", "farm"))
	return BoardDecor.layout_for(Session.campaign_index, state.board, theme)


## The current campaign county's background art (counties with a level), or null.
func _level_background() -> Texture2D:
	var path: String = _battle.get("background", "")
	return UiKit.tex(path) if path != "" and ResourceLoader.exists(path) else null


## Title card before a campaign level: the level's art full-screen, its title and intro.
## Click (or wait) to start.
func _show_level_intro() -> void:
	if instant():
		return
	var map_def: Dictionary = _battle
	var card := Control.new()
	card.size = SCREEN
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.04, 0.8)
	dim.size = SCREEN
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dim)
	var art := TextureRect.new()
	art.texture = _level_background()
	art.size = SCREEN
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	var county_name: String = Profile.war().map.names[int(map_def.county)] + " County"
	var title := UiKit.label(map_def.title if map_def.title == county_name else "%s: %s" % [county_name, map_def.title],
		UiKit.FONT_TITLE, Color("f2c14e"))
	title.add_theme_color_override("font_outline_color", Color("1d1611"))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(SCREEN.x, 24)
	title.position = Vector2(0, 14)
	card.add_child(title)
	var box := UiKit.panel(6)
	box.position = Vector2(60, 262)
	box.custom_minimum_size = Vector2(SCREEN.x - 120, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var bv := UiKit.vbox(4)
	box.add_child(bv)
	var intro := UiKit.label(map_def.get("intro", ""), 10)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(SCREEN.x - 120 - 2 * (6 + UiKit.PAD_X), 0)
	bv.add_child(intro)
	var hint := UiKit.label("Click to start", 8, Color("7a2a1a"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bv.add_child(hint)
	box.reset_size()
	box.position.y = SCREEN.y - box.size.y - 10
	card.modulate.a = 0.0
	var tin := create_tween()
	tin.tween_property(card, "modulate:a", 1.0, 0.3)
	await tin.finished
	var done := [false]
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			done[0] = true)
	var t := 0.0
	while not done[0] and t < 8.0 and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
	var tout := create_tween()
	tout.tween_property(card, "modulate:a", 0.0, 0.25)
	await tout.finished
	card.queue_free()


func _show_banner(text: String, hold: float) -> void:
	banner.text = text
	banner.visible = true
	if instant():
		banner.visible = false
		return
	banner.modulate.a = 0.0
	banner.position.x = -40
	var tw := create_tween().set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.15 / anim_speed())
	tw.tween_property(banner, "position:x", 6.0, 0.15 / anim_speed())
	await tw.finished
	await wait(hold)
	var out := create_tween()
	out.tween_property(banner, "modulate:a", 0.0, 0.15 / anim_speed())
	await out.finished
	banner.visible = false


func _card_summary(card: Dictionary) -> String:
	match card.get("kind", ""):
		Deck.KIND_PRODUCTION:
			return "%s\n%s a well%s" % [card.title, UiKit.money(int(card.rate)), "\nLand for sale" if card.land else ""]
		Deck.KIND_DEPLETION:
			return "%s\n+$500" % card.title
		Deck.KIND_FIRE:
			return "%s\nPick wells to cap" % card.title
	return str(card.get("title", ""))


func _animate_card(card: Dictionary, p: int) -> void:
	card_label.text = _card_summary(card)
	if instant():
		return
	# The card is 128x176 (2x art). It leaves the deck at half size (= the 64x88 deck art),
	# grows to full size over the board, flips, then returns.
	var start := deck_rect.global_position
	var center := (board_view.position + board_view.pixel_size() / 2 - CardView.SIZE / 2).round()
	big_card.show_back()
	big_card.visible = true
	big_card.modulate.a = 1.0
	big_card.pivot_offset = Vector2.ZERO
	big_card.scale = Vector2(0.5, 0.5)
	big_card.position = start
	var tw := create_tween().set_parallel(true)
	tw.tween_property(big_card, "position", center, 0.3 / anim_speed()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(big_card, "scale", Vector2.ONE, 0.3 / anim_speed())
	Sfx.play("card_flip")
	await tw.finished
	big_card.scale = Vector2.ONE
	big_card.pivot_offset = CardView.SIZE / 2
	await big_card.flip_to(card, 0.25 / anim_speed())
	big_card.scale = Vector2.ONE
	match card.kind:
		Deck.KIND_FIRE:
			panels[p].portrait.play("sulk", 1.2)
		Deck.KIND_PRODUCTION:
			if int(card.rate) >= 2000:
				panels[p].portrait.play("cheer", 1.0)
	await wait(1.3)
	big_card.pivot_offset = Vector2.ZERO
	var back := create_tween().set_parallel(true)
	back.tween_property(big_card, "position", start, 0.25 / anim_speed())
	back.tween_property(big_card, "scale", Vector2(0.5, 0.5), 0.25 / anim_speed())
	back.tween_property(big_card, "modulate:a", 0.0, 0.25 / anim_speed())
	await back.finished
	big_card.visible = false
	big_card.modulate.a = 1.0
	big_card.scale = Vector2.ONE


func _animate_drill(ev: Dictionary) -> void:
	var p: int = ev.player
	view_players[p].cash -= int(ev.cost)
	if instant():
		pass
	elif is_local(p) and anim_speed() < 3.0:
		await drill_popup.play(ev, state.players[p].character, pname(p), anim_speed())
	else:
		await board_view.effect_drilling(ev.site, anim_speed())
		if ev.oil:
			await board_view.effect_gusher(ev.site, anim_speed())
		else:
			await board_view.effect_dust(ev.site, anim_speed())
	board_view.site_state[ev.site] = GameConst.SITE_OIL if ev.oil else GameConst.SITE_DRY
	board_view.queue_redraw()
	panels[p].portrait.play("cheer" if ev.oil else "sulk", 1.2)
	_refresh_panels(true)
	var txt := ("%s strike! " % GameConst.DEPTH_NAMES[ev.depth]) if ev.oil else "Dry hole. "
	hint_label.text = "%s: %s(cost %s)" % [pname(p), txt, UiKit.money(ev.cost)]
	if int(ev.get("short", 0)) > 0:
		hint_label.text = "%s: %s%s couldn't cover it all: paid %s and is down to $0." % [pname(p), txt, pname(p), UiKit.money(ev.cost)]
	board_view.float_text(board_view.site_pos(ev.site), "-" + UiKit.money(ev.cost), Color("f4ecd8"), anim_speed())


# --- Refresh ----------------------------------------------------------------------------

func _refresh_all(animate: bool) -> void:
	_refresh_panels(animate)
	_refresh_top()
	_refresh_card_label()


func _refresh_panels(animate: bool) -> void:
	for i in panels.size():
		var wells := 0
		var plots := 0
		for plot in board_view.plot_owner.size():
			if board_view.plot_owner[plot] == i:
				plots += 1
				for sid in state.board.plots[plot].sites:
					if board_view.site_state[sid] == GameConst.SITE_OIL:
						wells += 1
		panels[i].refresh(view_players[i], wells, plots, i == state.current and state.phase != GameConst.PHASE_GAME_OVER, animate)


func _refresh_top() -> void:
	var round_txt := "Round %d" % state.round_number
	if state.round_cap > 0:
		round_txt += "/%d" % state.round_cap
	if state.phase == GameConst.PHASE_DRAFT:
		round_txt = "Land draft"
	var pace_txt: String = "Original rules" if state.original_rules() else "%s pace" % state.speed.display_name
	top_label.text = "STANDARD OIL   %s   Bank %s   %s   Deck %d" % [
		round_txt, UiKit.money(state.bank), pace_txt, state.draw_pile.size()]


func _refresh_card_label() -> void:
	if state.card.is_empty() or state.phase == GameConst.PHASE_DRAFT:
		card_label.text = "No card drawn yet."
	else:
		card_label.text = _card_summary(state.card)


# --- Controls ---------------------------------------------------------------------------

func _set_controls_enabled(on: bool) -> void:
	draw_btn.disabled = not on
	if not on:
		_set_deck_ready(false)
	end_btn.disabled = not on
	rig_tray.modulate = Color.WHITE if on else Color(0.5, 0.5, 0.5)


func _clear_modes() -> void:
	_armed = false
	_dragging = false
	_drag_ghost.visible = false
	board_view.highlight_sites = []
	board_view.highlight_plots = []
	board_view.show_prices = false
	board_view.selected_plot = -1
	board_view.trade_marks = {}
	board_view.queue_redraw()
	for c in info_buttons.get_children():
		c.queue_free()
	_fit_hint()


func _update_controls() -> void:
	_clear_modes()
	var p := state.current
	var mine := my_turn()
	# The left button is contextual: Draw Card, or Buy Land when land is for sale.
	var buying: bool = mine and state.phase == GameConst.PHASE_ACTIONS and state.can_buy and not _buyable_plots(p).is_empty()
	draw_btn.visible = buying
	draw_btn.disabled = not buying
	_set_deck_ready(mine and state.phase == GameConst.PHASE_CARD and state.trade.is_empty() and state.right_holder < 0)
	end_btn.disabled = not (mine and state.phase == GameConst.PHASE_ACTIONS) or state.must_drill(p)
	end_btn.tooltip_text = "You must drill at least one well first" if state.must_drill(p) else "End your turn (Enter)"
	board_view.highlight_color = Color("f2c14e")
	board_view.sale_mode = false
	var can_drill: bool = mine and state.phase == GameConst.PHASE_ACTIONS and state.drills_left > 0 \
		and state.players[p].cash >= state.drill_cash_needed(p) and not state.open_sites_of(p).is_empty()
	rig_tray.modulate = Color.WHITE if can_drill else Color(0.45, 0.45, 0.45)
	rig_count.text = ("%d drill%s left" % [state.drills_left, "" if state.drills_left == 1 else "s"]) \
		if state.phase == GameConst.PHASE_ACTIONS else "Drill rig"
	_update_tradeable()
	if state.phase == GameConst.PHASE_AUCTION:
		_close_trade_panel()
		_show_auction_controls()
		return
	if not state.trade.is_empty():
		_show_trade_waiting()
		return
	if state.right_holder >= 0:
		_close_trade_panel()
		_show_land_pick()
		return
	if _trade_view == "reply" or (_trade_view == "compose" and not _can_start_trade()):
		_close_trade_panel()
	if _trade_view == "compose":
		_refresh_trade_compose()
		return
	if not mine:
		hint_label.text = ("Waiting for %s to pick wells to cap..." if state.phase == GameConst.PHASE_FIRE else "Waiting for %s...") % pname(p)
		return
	match state.phase:
		GameConst.PHASE_DRAFT:
			hint_label.text = "%s: click a glowing plot to pick your starting land." % pname(p)
			board_view.highlight_plots = _buyable_plots(p)
			board_view.show_prices = true
		GameConst.PHASE_CARD:
			hint_label.text = "%s: click the deck to draw a card, or click a rival's name to trade." % pname(p)
		GameConst.PHASE_FIRE:
			hint_label.text = "BLOWOUT FIRE! Click %d of your derricks to cap (they stop producing)." % state.fire_left
			board_view.highlight_sites = _wells_on_board(p)
			board_view.highlight_color = Color("ff5a3a")
		GameConst.PHASE_ACTIONS:
			# Kept to 2 lines: the hint box has room for no more.
			var parts: Array[String] = []
			if can_drill:
				parts.append("drag the rig to a site (%d left)" % state.drills_left)
			elif state.drills_left > 0 and state.players[p].cash < state.drill_cash_needed(p):
				parts.append("out of cash, so no drilling" if state.original_rules() else "need %s to drill" % UiKit.money(state.drill_cash_needed(p)))
			if buying:
				board_view.highlight_plots = _buyable_plots(p)
				board_view.show_prices = true
				board_view.sale_mode = true
			if not buying and not state.must_drill(p):
				parts.append("click your land to lay pipe")
			parts.append("then End Turn")
			var lead := ""
			if buying:
				lead += "LAND FOR SALE: click a glowing plot. "
			if state.must_drill(p):
				lead += "Drill at least 1 well. "
			var body := ", ".join(parts)
			hint_label.text = lead + body[0].to_upper() + body.substr(1) + "."
	board_view.queue_redraw()


## Original rules: bid controls for the property the bank is auctioning.
func _show_auction_controls() -> void:
	var lot: int = state.auction.plots[state.auction.index]
	board_view.selected_plot = lot
	board_view.queue_redraw()
	_show_plot_info(lot, false) # the lot fills the property fields
	var bidder := _local_bidder()
	if bidder < 0:
		hint_label.text = "Auction: waiting for the other bids on %s..." % state.board.plots[lot].name
		_fit_hint()
		return
	var cash: int = state.players[bidder].cash
	_bid_amount = clampi(_bid_amount, 0, (cash / GameConst.ORIG_BID_STEP) * GameConst.ORIG_BID_STEP)
	hint_label.text = "AUCTION %d/%d: set your top bid. Winner pays $500 over the next bid." % [
		int(state.auction.index) + 1, state.auction.plots.size()]
	for c in info_buttons.get_children():
		c.queue_free()
	info_buttons.add_child(UiKit.button("-5k", func(): _change_bid(-5000, cash), 8))
	info_buttons.add_child(UiKit.button("-500", func(): _change_bid(-500, cash), 8))
	_bid_label = UiKit.label(UiKit.money(_bid_amount), 8)
	_bid_label.custom_minimum_size = Vector2(48, 0)
	_bid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_buttons.add_child(_bid_label)
	info_buttons.add_child(UiKit.button("+500", func(): _change_bid(500, cash), 8))
	info_buttons.add_child(UiKit.button("+5k", func(): _change_bid(5000, cash), 8))
	info_buttons.add_child(UiKit.button("Bid", func(): submit({"type": "bid", "player": bidder, "amount": _bid_amount}), 8))
	info_buttons.add_child(UiKit.button("Pass", func(): submit({"type": "bid", "player": bidder, "amount": 0}), 8))
	for control in info_buttons.get_children():
		if control is Button and not control.is_queued_for_deletion():
			_compact(control)
	_fit_hint()


## Narrower side margins, for rows of small buttons.
func _compact(b: Button, margin: int = 6) -> void:
	for style in ["normal", "hover", "pressed", "disabled"]:
		var compact := b.get_theme_stylebox(style).duplicate() as StyleBox
		compact.content_margin_left = margin
		compact.content_margin_right = margin
		b.add_theme_stylebox_override(style, compact)


func _change_bid(delta: int, cash: int) -> void:
	_bid_amount = clampi(_bid_amount + delta, 0, (cash / GameConst.ORIG_BID_STEP) * GameConst.ORIG_BID_STEP)
	if _bid_label:
		_bid_label.text = UiKit.money(_bid_amount)


func _buyable_plots(p: int) -> Array:
	var out: Array = []
	for i in state.plot_owner.size():
		if state.plot_owner[i] == -1 and int(state.board.plots[i].price) <= int(state.players[p].cash):
			out.append(i)
	return out


func _drill_targets() -> Array:
	return Array(state.open_sites_of(state.current))


func _on_draw_pressed() -> void:
	if not my_turn():
		return
	if state.phase == GameConst.PHASE_CARD:
		submit({"type": "draw"})
	elif state.phase == GameConst.PHASE_ACTIONS and state.can_buy:
		# "Buy Land": point at the plots for sale.
		hint_label.text = "LAND FOR SALE: click a glowing plot, then click it again (or press Buy) to buy it."
		for plot in board_view.highlight_plots:
			board_view.effect_flash_plot(plot, 2.0)


## Producing wells the player owns, as shown on the board right now.
func _wells_on_board(p: int) -> Array:
	var out: Array = []
	for plot in board_view.plot_owner.size():
		if board_view.plot_owner[plot] != p:
			continue
		for sid in state.board.plots[plot].sites:
			if board_view.site_state[sid] == GameConst.SITE_OIL:
				out.append(sid)
	return out


func _on_end_pressed() -> void:
	if my_turn() and state.phase == GameConst.PHASE_ACTIONS:
		submit({"type": "end_turn"})


func _on_plot_clicked(plot: int) -> void:
	if _playing:
		_fast = true
		return
	if _trade_view == "compose":
		_toggle_deal_plot(plot)
		return
	if state.right_holder >= 0 and is_local(state.right_holder):
		_pick_land_click(plot)
		return
	# Second click on the selected, buyable plot buys it.
	if plot == board_view.selected_plot and my_turn() and state.plot_owner[plot] == -1 \
			and state.check_action(state.current, {"type": "buy", "plot": plot}) == "":
		submit({"type": "buy", "plot": plot})
		return
	board_view.selected_plot = plot
	board_view.queue_redraw()
	_show_plot_info(plot, true)


func _on_site_clicked(sid: int) -> void:
	if state.phase == GameConst.PHASE_FIRE and my_turn():
		submit({"type": "cap", "site": sid})
		return
	if _armed and my_turn():
		_armed = false
		submit({"type": "drill", "site": sid})


func _on_hover(plot: int, _site: int) -> void:
	if board_view.selected_plot < 0 and plot >= 0:
		_show_plot_info(plot, false)


func _show_plot_info(plot: int, with_buttons: bool) -> void:
	var pd: Dictionary = state.board.plots[plot]
	var owner: int = board_view.plot_owner[plot]
	var wells := 0
	var dry := 0
	for sid in pd.sites:
		match board_view.site_state[sid]:
			GameConst.SITE_OIL: wells += 1
			GameConst.SITE_DRY, GameConst.SITE_BURNED: dry += 1
	_set_field("name", pd.name)
	_set_field("owner", "Closed" if owner == GameConst.PLOT_CLOSED else ("For sale" if owner < 0 else pname(owner)))
	owner_swatch.color = board_view.player_color(owner) if owner >= 0 else Color(0, 0, 0, 0)
	_set_field("price", UiKit.money(pd.price))
	_set_field("sites", str(pd.sites.size()))
	_set_field("wells", str(wells))
	_set_field("dry", str(dry))
	if not with_buttons:
		return
	for c in info_buttons.get_children():
		c.queue_free()
	if not my_turn():
		_fit_hint()
		return
	var p := state.current
	if owner < 0:
		var err := state.check_action(p, {"type": "buy", "plot": plot})
		if err == "":
			info_buttons.add_child(UiKit.button("Buy %s for %s" % [pd.name, UiKit.money(pd.price)], func(): submit({"type": "buy", "plot": plot}), 8))
			hint_label.text = "Click the plot again or press Buy to purchase it."
		elif state.phase != GameConst.PHASE_CARD:
			hint_label.text = "%s: %s" % [pd.name, err]
	elif owner == p and state.phase == GameConst.PHASE_ACTIONS:
		var shown := 0
		var reason := ""
		for nb in state.board.adjacency[plot]:
			var no: int = state.plot_owner[nb]
			if no < 0 or no == p:
				continue
			var err := state.check_pipeline(p, plot, nb)
			if err == "":
				var existing := state.pipeline_between(plot, nb)
				var lvl := 1 if existing.is_empty() else int(existing.level) + 1
				var label := ("Pipe L1 > %s" if lvl == 1 else "Upgrade to L%d > %%s" % lvl) % state.board.plots[nb].name
				if state.original_rules():
					label = "Pipe #%d > %s" % [state.pipelines_from(plot) + 1, state.board.plots[nb].name]
				hint_label.text = "Lay a pipeline from %s for %s:" % [pd.name, UiKit.money(state.pipeline_cost())]
				var target: int = nb
				info_buttons.add_child(UiKit.button(label, func(): submit({"type": "pipeline", "from": plot, "to": target}), 8))
				shown += 1
				if shown >= 2:
					break
			elif reason == "":
				reason = err
		if shown == 0:
			hint_label.text = "No pipeline from %s: %s." % [pd.name, (reason if reason != "" else "no rival land next door").to_lower()]
	_fit_hint()


## The fixed property fields: a caption over a value for each, in one row. Shows "-" until a
## property is hovered or selected.
func _build_plot_fields() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e3d3ae")
	sb.border_color = Color("b89b6a")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(3)
	box.add_child(row)
	# Widths fit the ~332 px inside the status panel. Long names end in "..." (full name on hover).
	for f in [["name", "PROPERTY", 96], ["owner", "OWNER", 76], ["price", "PRICE", 56], ["sites", "SITES", 30],
			["wells", "WELLS", 34], ["dry", "DRY", 22]]:
		var cell := UiKit.vbox(0)
		cell.custom_minimum_size = Vector2(f[2], 0)
		row.add_child(cell)
		cell.add_child(UiKit.label(f[1], 8, Color("8a6a44")))
		var value := UiKit.label("-", 8)
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.custom_minimum_size = Vector2(f[2], 0)
		if f[0] == "owner":
			var line := UiKit.hbox(2)
			owner_swatch = ColorRect.new()
			owner_swatch.custom_minimum_size = Vector2(5, 8)
			owner_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			owner_swatch.color = Color(0, 0, 0, 0)
			line.add_child(owner_swatch)
			value.custom_minimum_size = Vector2(f[2] - 7, 0)
			line.add_child(value)
			cell.add_child(line)
		else:
			cell.add_child(value)
		plot_fields[f[0]] = value
	return box


## The hint gets 2 lines, or 1 when action buttons need the space below the property fields.
func _fit_hint() -> void:
	var has_buttons := info_buttons.get_children().any(func(c): return not c.is_queued_for_deletion())
	hint_label.max_lines_visible = 1 if has_buttons else 2


func _set_field(key: String, text: String) -> void:
	var l: Label = plot_fields[key]
	l.text = text
	l.tooltip_text = text


# --- Rig drag & drop -----------------------------------------------------------------------

func _on_rig_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if not my_turn() or state.phase != GameConst.PHASE_ACTIONS or state.drills_left <= 0:
		return
	if int(state.players[state.current].cash) < state.drill_cash_needed(state.current):
		hint_label.text = "You're out of cash: no drilling until you earn more." \
			if state.original_rules() else "Need %s on hand to drill." % UiKit.money(state.drill_cash_needed(state.current))
		return
	_dragging = true
	_armed = true
	_drag_ghost.visible = true
	_drag_ghost.position = get_global_mouse_position() - Vector2(12, 28)
	board_view.highlight_sites = _drill_targets()
	board_view.queue_redraw()
	hint_label.text = "Drop the rig on a glowing site (or click a site). Right-click to cancel."
	Sfx.play("click")


func _input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseMotion:
		_drag_ghost.position = get_global_mouse_position() - Vector2(12, 28)
	elif _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		_drag_ghost.visible = false
		var local := board_view.to_local(get_global_mouse_position())
		var sid := board_view.site_near(local, 0.9)
		if sid >= 0 and sid in board_view.highlight_sites:
			_armed = false
			board_view.highlight_sites = []
			submit({"type": "drill", "site": sid})
		elif rig_tray.get_global_rect().has_point(get_global_mouse_position()):
			pass # clicked the rig: stay armed, pick a site with a click
		else:
			_snap_rig_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _armed:
			_snap_rig_back()
		board_view.selected_plot = -1
		board_view.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if _playing:
					_fast = true
				elif _trade_view == "":
					_on_draw_pressed()
			KEY_ENTER, KEY_KP_ENTER:
				if _trade_view == "":
					_on_end_pressed()
			KEY_ESCAPE:
				_toggle_pause()
	elif event is InputEventMouseButton and event.pressed and _playing and event.button_index == MOUSE_BUTTON_LEFT:
		_fast = true


func _snap_rig_back() -> void:
	_armed = false
	_dragging = false
	_drag_ghost.visible = false
	board_view.highlight_sites = []
	board_view.queue_redraw()
	if my_turn():
		_update_controls()


# --- Trading ----------------------------------------------------------------------------
# A trade starts by clicking a rival's name in the player list. The deal panel then covers the
# side column (the board stays clickable): who it's with, then a "You give" and a "They give"
# section, each with cash and the land picked on the board, then Send / Cancel.

## Width of a value next to its row label inside a section.
const TRADE_VALUE_W: float = SIDE_W - 2 * (6 + UiKit.PAD_X) - 2 * (5 + UiKit.PAD_X) - 4 - 34


func _trade_partners() -> Array[int]:
	var out: Array[int] = []
	for q in state.active_players():
		if q != state.current:
			out.append(q)
	return out


func _can_start_trade() -> bool:
	return my_turn() and (state.phase == GameConst.PHASE_CARD or state.phase == GameConst.PHASE_ACTIONS) \
		and state.trade.is_empty() and not _trade_partners().is_empty()


## Player list click: start a deal with that player.
func _on_player_clicked(q: int) -> void:
	if _playing or not _can_start_trade() or not q in _trade_partners():
		return
	Sfx.play("click")
	if _trade_view == "compose":
		_set_deal_partner(q)
		return
	_deal = {"to": q, "give_cash": 0, "get_cash": 0, "give_plots": [], "get_plots": [], "land_right": false}
	_trade_view = "compose"
	_update_controls()


## Player names are clickable (trade) only while you could start a deal.
func _update_tradeable() -> void:
	var can := _can_start_trade()
	for i in panels.size():
		var on := can and i in _trade_partners()
		panels[i].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
		panels[i].tooltip_text = ("Click to trade with %s" % pname(i)) if on else ""


func _close_trade_panel() -> void:
	if _trade_panel and is_instance_valid(_trade_panel):
		_trade_panel.queue_free()
	_trade_panel = null
	_trade_view = ""
	board_view.trade_marks = {}
	board_view.queue_redraw()


## A fresh side panel over the player list and action panel (the board stays clickable).
func _trade_frame() -> VBoxContainer:
	if _trade_panel and is_instance_valid(_trade_panel):
		_trade_panel.queue_free()
	var pnl := UiKit.panel(6)
	pnl.position = Vector2(SIDE_X, TOP_H + 4)
	pnl.custom_minimum_size = Vector2(SIDE_W, SCREEN.y - TOP_H - 8)
	pnl.size = pnl.custom_minimum_size
	pnl.clip_contents = true
	add_child(pnl)
	_trade_panel = pnl
	var v := UiKit.vbox(5)
	pnl.add_child(v)
	return v


## A boxed section with a colored title (and an optional note on the right).
func _trade_section(parent: Control, title: String, color: Color, note: String = "") -> VBoxContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e4d4ad")
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.content_margin_left = 5 + UiKit.PAD_X
	sb.content_margin_right = 5 + UiKit.PAD_X
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	parent.add_child(box)
	var v := UiKit.vbox(3)
	box.add_child(v)
	var head := UiKit.hbox(4)
	var t := UiKit.label(title, 8, Color("2f5d3a") if color == GET_COLOR else Color("8a2e1c"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if note != "":
		head.add_child(UiKit.label(note, 8, Color("6b4428")))
	v.add_child(head)
	return v


## One "Label  value" row in a section; the value wraps.
func _trade_row(parent: Control, key: String, value: Control) -> void:
	var row := UiKit.hbox(4)
	var k := UiKit.label(key, 8, Color("6b4428"))
	k.custom_minimum_size = Vector2(34, 0)
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	row.add_child(value)
	parent.add_child(row)


func _trade_text(text: String, color: Color = UiKit.INK) -> Label:
	var l := UiKit.label(text, 8, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(TRADE_VALUE_W, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Text spanning the whole panel width.
func _trade_note(text: String, color: Color) -> Label:
	var l := UiKit.label(text, 8, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIDE_W - 2 * (6 + UiKit.PAD_X), 0)
	return l


func _deal_action() -> Dictionary:
	var a := _deal.duplicate(true)
	a["type"] = "trade_offer"
	a["player"] = state.current
	return a


func _plot_text(plot: int) -> String:
	var txt := str(state.board.plots[plot].name)
	var wells := state.producing_wells_on(plot)
	if wells > 0:
		txt += " (%d well%s)" % [wells, "" if wells == 1 else "s"]
	return txt


func _plots_text(plots: Array) -> String:
	var names: Array[String] = []
	for plot in plots:
		names.append(_plot_text(int(plot)))
	return ", ".join(names)


## "Trading with" / "Offer from" and the player's name in their color.
func _trade_title(lead: String, q: int) -> HBoxContainer:
	var row := UiKit.hbox(6)
	row.add_child(UiKit.label(lead, UiKit.FONT_BODY, Color("6b4428")))
	var chip := ColorRect.new()
	chip.color = board_view.player_color(q)
	chip.custom_minimum_size = Vector2(8, 8)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var n := UiKit.label(pname(q), UiKit.FONT_BODY)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	return row


func _trade_marks(t: Dictionary) -> Dictionary:
	var marks := {}
	for plot in t.get("give_plots", []):
		marks[int(plot)] = GIVE_COLOR
	for plot in t.get("get_plots", []):
		marks[int(plot)] = GET_COLOR
	return marks


## Players a deal would leave with no land (they'd be out of the game).
func _left_landless(t: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var a := int(t.from)
	var b := int(t.to)
	if state.plots_of(a).size() - t.give_plots.size() + t.get_plots.size() <= 0:
		out.append(a)
	if state.plots_of(b).size() - t.get_plots.size() + t.give_plots.size() <= 0:
		out.append(b)
	return out


## Cash stepper for one side of the deal (`key` = give_cash or get_cash, up to `most`).
func _cash_row(key: String, most: int) -> HBoxContainer:
	var row := UiKit.hbox(2)
	for step in [-5000, -500, 0, 500, 5000]:
		if step == 0:
			var amount := UiKit.label(UiKit.money(int(_deal[key])), 8)
			amount.custom_minimum_size = Vector2(50, 0)
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(amount)
			continue
		var b := UiKit.button("%+d" % step if absi(step) < 1000 else "%+dk" % (step / 1000), func(): _change_deal_cash(key, step, most), 8)
		_compact(b, 3)
		row.add_child(b)
	return row


func _change_deal_cash(key: String, delta: int, most: int) -> void:
	_deal[key] = clampi(int(_deal[key]) + delta, 0, maxi(0, most))
	_refresh_trade_compose()


func _set_deal_partner(q: int) -> void:
	if q == int(_deal.to):
		return
	_deal.to = q
	_deal.get_plots = []
	_deal.get_cash = 0
	_refresh_trade_compose()


## Board click while making a deal: your land = give it, the partner's = ask for it, another
## player's = switch partner and ask for it.
func _toggle_deal_plot(plot: int) -> void:
	var me := state.current
	var owner := state.plot_owner[plot]
	if owner == me:
		_toggle_in(_deal.give_plots, plot)
	elif owner >= 0 and not state.players[owner].bankrupt:
		if owner != int(_deal.to):
			_set_deal_partner(owner)
		_toggle_in(_deal.get_plots, plot)
	else:
		return
	Sfx.play("click")
	_refresh_trade_compose()


func _can_sell_right() -> bool:
	return state.phase == GameConst.PHASE_ACTIONS and state.can_buy


func _toggle_in(list: Array, plot: int) -> void:
	if plot in list:
		list.erase(plot)
	else:
		list.append(plot)


## The deal panel: partner, "You give" and "They give" sections, Send / Cancel.
func _refresh_trade_compose() -> void:
	var me := state.current
	var q := int(_deal.to)
	var v := _trade_frame()
	v.add_child(_trade_title("Trading with", q))

	var give := _trade_section(v, "YOU GIVE", GIVE_COLOR, "you have %s" % UiKit.money(int(state.players[me].cash)))
	_trade_row(give, "Cash", _cash_row("give_cash", int(state.players[me].cash)))
	var give_land := _plots_text(_deal.give_plots)
	_trade_row(give, "Land", _trade_text(give_land if give_land != "" else "click your land on the board",
		UiKit.INK if give_land != "" else Color("8a7458")))
	if _can_sell_right():
		# This turn's right to buy land: they pick the plot (or none) once the deal is done.
		var right_row := UiKit.hbox(4)
		var on := bool(_deal.land_right)
		var rt := _trade_text("to buy land (they pick)" if on else "keep your right to buy land",
			UiKit.INK if on else Color("8a7458"))
		rt.custom_minimum_size.x = TRADE_VALUE_W - 52
		right_row.add_child(rt)
		var tb := UiKit.button("Remove" if on else "Sell", func():
			_deal.land_right = not bool(_deal.land_right)
			Sfx.play("click")
			_refresh_trade_compose(), 8)
		_compact(tb, 4)
		tb.custom_minimum_size.x = 48
		tb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		right_row.add_child(tb)
		_trade_row(give, "Right", right_row)

	var get := _trade_section(v, "%s GIVES" % pname(q).to_upper(), GET_COLOR, "has %s" % UiKit.money(int(state.players[q].cash)))
	_trade_row(get, "Cash", _cash_row("get_cash", int(state.players[q].cash)))
	var get_land := _plots_text(_deal.get_plots)
	_trade_row(get, "Land", _trade_text(get_land if get_land != "" else "click their land on the board",
		UiKit.INK if get_land != "" else Color("8a7458")))

	var err := state.check_action(me, _deal_action())
	if err == "Put something in the deal":
		err = ""
	var offer := state.make_offer(me, _deal_action())
	var notes: Array[String] = []
	for who in _left_landless(offer):
		notes.append("%s would have no land left and be out of the game." % ("You" if who == me else pname(who)))
	if err != "":
		v.add_child(_trade_note(err, Color("c8402e")))
	elif not notes.is_empty():
		v.add_child(_trade_note(" ".join(notes), Color("c8402e")))
	var btns := UiKit.hbox(6)
	var send := UiKit.button("Send Offer", func():
		var a := _deal_action()
		_close_trade_panel()
		submit(a), 8)
	send.disabled = state.check_action(me, _deal_action()) != ""
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(send)
	var cancel := UiKit.button("Cancel", func():
		_close_trade_panel()
		_update_controls(), 8)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(cancel)
	v.add_child(btns)
	board_view.trade_marks = _trade_marks(_deal)
	board_view.queue_redraw()
	hint_label.text = "Trading with %s: click land on the board to add it to the deal. To trade with someone else, Cancel and click their name." % pname(q)
	_fit_hint()


## A deal is waiting for an answer: the player it's for gets the reply panel; the one who made
## it can withdraw it.
func _show_trade_waiting() -> void:
	var t: Dictionary = state.trade
	var from := int(t.from)
	var to := int(t.to)
	board_view.trade_marks = _trade_marks(t)
	board_view.queue_redraw()
	draw_btn.disabled = true
	end_btn.disabled = true
	rig_tray.modulate = Color(0.45, 0.45, 0.45)
	if is_local(to):
		_show_trade_reply(t)
		hint_label.text = "%s, %s offers you a deal: Accept or Decline on the right." % [pname(to), pname(from)]
	else:
		_close_trade_panel()
		board_view.trade_marks = _trade_marks(t)
		if is_local(from):
			hint_label.text = "Waiting for %s to answer your offer..." % pname(to)
			var withdraw := UiKit.button("Withdraw Offer", func(): submit({"type": "trade_cancel", "player": from}), 8)
			info_buttons.add_child(withdraw)
		else:
			hint_label.text = "%s offered %s a deal. Waiting for an answer..." % [pname(from), pname(to)]
	_fit_hint()


## The offer as the player it's for sees it: "You get" and "You give" sections, Accept / Decline.
func _show_trade_reply(t: Dictionary) -> void:
	var from := int(t.from)
	var to := int(t.to)
	var v := _trade_frame()
	_trade_view = "reply"
	v.add_child(_trade_title("Offer from", from))
	var dim := Color("8a7458")
	var get := _trade_section(v, "YOU GET", GET_COLOR)
	_trade_row(get, "Cash", _trade_text(UiKit.money(int(t.give_cash)), UiKit.INK if int(t.give_cash) > 0 else dim))
	var get_land := _plots_text(t.give_plots)
	_trade_row(get, "Land", _trade_text(get_land if get_land != "" else "none", UiKit.INK if get_land != "" else dim))
	if bool(t.get("land_right", false)):
		_trade_row(get, "Right", _trade_text("to buy one plot for sale: you pick it (and pay the bank), or skip"))
	var give := _trade_section(v, "YOU GIVE", GIVE_COLOR)
	_trade_row(give, "Cash", _trade_text(UiKit.money(int(t.get_cash)), UiKit.INK if int(t.get_cash) > 0 else dim))
	var give_land := _plots_text(t.get_plots)
	_trade_row(give, "Land", _trade_text(give_land if give_land != "" else "none", UiKit.INK if give_land != "" else dim))
	var after := int(state.players[to].cash) + int(t.give_cash) - int(t.get_cash)
	v.add_child(_trade_note("Your cash after: %s (now %s)" % [UiKit.money(after), UiKit.money(int(state.players[to].cash))], UiKit.INK))
	v.add_child(_trade_note("Wells and the pipelines running out of traded land go with it.", Color("6b4428")))
	if to in _left_landless(t):
		v.add_child(_trade_note("You'd have no land left and be out of the game.", Color("c8402e")))
	var err := state.check_trade(from, t)
	if err != "":
		v.add_child(_trade_note(err, Color("c8402e")))
	var btns := UiKit.hbox(6)
	var accept := UiKit.button("Accept", func(): submit({"type": "trade_reply", "player": to, "accept": true}), 8)
	accept.disabled = err != ""
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(accept)
	var decline := UiKit.button("Decline", func(): submit({"type": "trade_reply", "player": to, "accept": false}), 8)
	decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(decline)
	v.add_child(btns)


## The player who bought the land right picks a plot for sale (click it twice, or Buy) or skips.
func _show_land_pick() -> void:
	var holder := state.right_holder
	draw_btn.disabled = true
	end_btn.disabled = true
	rig_tray.modulate = Color(0.45, 0.45, 0.45)
	if not is_local(holder):
		hint_label.text = "Waiting for %s to pick land (or pass)..." % pname(holder)
		_fit_hint()
		return
	board_view.highlight_plots = _buyable_plots(holder)
	board_view.show_prices = true
	board_view.sale_mode = true
	board_view.queue_redraw()
	hint_label.text = "%s: pick a glowing plot to buy, or Skip." % pname(holder)
	_add_skip_button(holder)
	_fit_hint()


func _add_skip_button(holder: int) -> void:
	info_buttons.add_child(UiKit.button("Skip, buy nothing", func(): submit({"type": "pass_land", "player": holder}), 8))


func _pick_land_click(plot: int) -> void:
	var holder := state.right_holder
	var buy := {"type": "buy", "player": holder, "plot": plot}
	if plot == board_view.selected_plot and state.check_action(holder, buy) == "":
		submit(buy)
		return
	board_view.selected_plot = plot
	board_view.queue_redraw()
	_show_plot_info(plot, false)
	for c in info_buttons.get_children():
		c.queue_free()
	var err := state.check_action(holder, buy)
	if err == "":
		var pd: Dictionary = state.board.plots[plot]
		info_buttons.add_child(UiKit.button("Buy %s for %s" % [pd.name, UiKit.money(pd.price)], func(): submit(buy), 8))
		hint_label.text = "Click the plot again or press Buy to purchase it."
	else:
		hint_label.text = "%s: %s" % [state.board.plots[plot].name, err]
	_add_skip_button(holder)
	_fit_hint()


func _play_trade(ev: Dictionary, sp: float) -> void:
	var t: Dictionary = ev.trade
	var a := int(t.from)
	var b := int(t.to)
	board_view.trade_marks = {}
	view_players[a].cash += int(t.get_cash) - int(t.give_cash)
	view_players[b].cash += int(t.give_cash) - int(t.get_cash)
	var moved: Array = []
	for plot in t.give_plots:
		_view_move_plot(int(plot), b)
		moved.append(int(plot))
	for plot in t.get_plots:
		_view_move_plot(int(plot), a)
		moved.append(int(plot))
	board_view.pipelines = board_view.pipelines.filter(func(pl): return not int(pl.id) in ev.dropped)
	for plot in moved:
		board_view.effect_build(plot, sp)
	board_view.queue_redraw()
	_refresh_panels(true)
	Sfx.play("cash")
	panels[a].portrait.play("cheer", 1.0)
	panels[b].portrait.play("cheer", 1.0)
	hint_label.text = "%s and %s shake on it." % [pname(a), pname(b)]
	if not ev.dropped.is_empty():
		hint_label.text += " %d pipeline%s inside one owner's land %s torn out." % [
			ev.dropped.size(), "" if ev.dropped.size() == 1 else "s", "is" if ev.dropped.size() == 1 else "are"]
	for plot in moved:
		board_view.effect_flash_plot(plot, sp)
	await _show_banner("DEAL!", 0.8)


## Display copy: a plot (and the pipelines running out of it) changes hands.
func _view_move_plot(plot: int, q: int) -> void:
	board_view.plot_owner[plot] = q
	_note_land(q, plot)
	for pl in board_view.pipelines:
		if pl.from == plot:
			pl.owner = q


# --- Turn timer -------------------------------------------------------------------------

## Turns the deck's click-to-draw (and its glow) on or off.
func _set_deck_ready(on: bool) -> void:
	_deck_ready = on
	deck_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	deck_rect.tooltip_text = "Click to draw a card (Space)" if on else "Event deck"
	if not on:
		deck_rect.modulate = Color.WHITE


func _process(delta: float) -> void:
	if _deck_ready:
		_deck_t += delta
		var glow := 1.0 + 0.22 * (0.5 + 0.5 * sin(_deck_t * 5.0))
		deck_rect.modulate = Color(glow, glow, glow * 0.85)
	var limit := int(state.speed.get("turn_timer_sec", 0))
	if net_mode == "offline" or limit <= 0 or state.phase == GameConst.PHASE_GAME_OVER or state.phase == GameConst.PHASE_DRAFT:
		timer_label.text = ""
		return
	if _playing:
		return
	_turn_time_left -= delta
	timer_label.text = "Turn timer %ds" % maxi(0, ceili(_turn_time_left))
	# A deal waiting on a person runs on the same clock; time out = turned down.
	var waiting_on: int = state.current if state.trade.is_empty() else int(state.trade.to)
	if state.right_holder >= 0:
		waiting_on = state.right_holder
	if _turn_time_left <= 0.0 and net_mode == "host" and not state.players[waiting_on].is_ai:
		_turn_time_left = float(limit)
		var a := {"type": "end_turn"}
		if not state.trade.is_empty() or state.right_holder >= 0:
			a = {"type": "trade_reply", "accept": false, "player": waiting_on}
			if state.right_holder >= 0:
				a = {"type": "pass_land", "player": waiting_on}
			var tr := state.apply(a)
			if tr.ok:
				Net.broadcast_update(tr.events, state.to_dict(false))
				_enqueue(tr.events)
			return
		if state.phase == GameConst.PHASE_CARD:
			a = {"type": "draw"}
		elif state.phase == GameConst.PHASE_FIRE:
			a = {"type": "cap", "site": AIPlayer.pick_well_to_cap(state, state.current, GameConst.AI_MEDIUM, ai_rng)}
		a["player"] = state.current
		var r := state.apply(a)
		if r.ok:
			Net.broadcast_update(r.events, state.to_dict(false))
			_enqueue(r.events)


# --- Pause / results -----------------------------------------------------------------------

func _toggle_pause() -> void:
	if pause_menu and is_instance_valid(pause_menu):
		pause_menu.queue_free()
		pause_menu = null
		return
	pause_menu = Control.new()
	pause_menu.size = SCREEN
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = SCREEN
	pause_menu.add_child(dim)
	var pnl := UiKit.panel(10)
	pnl.custom_minimum_size = Vector2(180, 0)
	var center := CenterContainer.new()
	center.size = SCREEN
	pause_menu.add_child(center)
	center.add_child(pnl)
	var v := UiKit.vbox(5)
	pnl.add_child(v)
	v.add_child(UiKit.label("Paused", UiKit.FONT_TITLE))
	v.add_child(UiKit.button("Resume", _toggle_pause))
	var speeds := [0.75, 1.0, 1.5, 2.0, 99.0]
	var names := ["Slow", "Normal", "Fast", "Faster", "Instant"]
	var cur := speeds.find(float(Profile.setting("anim_speed")))
	v.add_child(UiKit.label("Animation speed", 8))
	v.add_child(UiKit.option(names, maxi(0, cur), func(i): Profile.set_setting("anim_speed", speeds[i])))
	if net_mode == "offline":
		v.add_child(UiKit.button("Save & Quit", func():
			Session.save_game(state)
			Session.goto("menu")))
	v.add_child(UiKit.button("Quit to Menu", func():
		if net_mode != "offline":
			Net.leave()
		Session.goto("menu")))
	add_child(pause_menu)


func _show_results(ev: Dictionary) -> void:
	if net_mode == "offline":
		Session.delete_save()
	result_panel = Control.new()
	result_panel.size = SCREEN
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = SCREEN
	result_panel.add_child(dim)
	var pnl := UiKit.panel(10)
	pnl.custom_minimum_size = Vector2(440, 0)
	var center := CenterContainer.new()
	center.size = SCREEN
	result_panel.add_child(center)
	center.add_child(pnl)
	var v := UiKit.vbox(4)
	pnl.add_child(v)
	var reasons := {"last_standing": "Last tycoon standing", "bank_empty": "The bank ran dry", "round_cap": "Time's up",
		"player_out": "You went bankrupt"}
	v.add_child(UiKit.label("%s wins!" % pname(ev.winner), UiKit.FONT_TITLE))
	v.add_child(UiKit.label(reasons.get(ev.reason, ""), 8))
	var order: Array = range(state.players.size())
	order.sort_custom(func(a, b): return int(ev.net_worths[a]) > int(ev.net_worths[b]))
	for i in order:
		var row := UiKit.hbox(6)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(24, 24)
		var cv := CharacterView.new()
		cv.setup(state.players[i].character, true)
		cv.play("cheer" if i == ev.winner else ("sulk" if state.players[i].bankrupt else "idle"))
		holder.add_child(cv)
		row.add_child(holder)
		var name_label := UiKit.label(pname(i), 8)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = pname(i)
		row.add_child(name_label)
		if state.players[i].bankrupt:
			row.add_child(UiKit.label("Bankrupt", 8, Color("7a2a1a")))
		var worth := UiKit.label("Net worth %s" % UiKit.money(ev.net_worths[i]), 8)
		worth.custom_minimum_size.x = 144
		worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(worth)
		v.add_child(row)
	if not _battle.is_empty() and not _rewards_given:
		_rewards_given = true
		_campaign_rewards(v, ev.winner == 0)
	var btns := UiKit.hbox(6)
	v.add_child(btns)
	if not _battle.is_empty():
		btns.add_child(UiKit.button("County Map", func(): Session.goto("campaign")))
	btns.add_child(UiKit.button("Main Menu", func():
		if net_mode != "offline":
			Net.leave()
		Session.goto("menu")))
	add_child(result_panel)


## Campaign results: the county changes hands (or not), dollars move, rivals may be knocked out.
func _campaign_rewards(v: VBoxContainer, won: bool) -> void:
	var county := int(_battle.county)
	var cname: String = Profile.war().map.names[county]
	var res: Dictionary = Profile.finish_battle(county, won, _battle)
	v.add_child(UiKit.label(("%s County is yours!" if won else "%s County holds out.") % cname, 10,
		Color("2f5d3a") if won else Color("7a2a1a")))
	for p in res.payments:
		var r := int(p.rival)
		var row := UiKit.hbox(3)
		var who: String = Session.rival_def(r).get("short", "")
		var col := Color("2f5d3a") if won else Color("7a2a1a")
		row.add_child(UiKit.label(("%s pays you" if won else "You pay %s") % who, 8, col))
		row.add_child(UiKit.dollar_amount(int(p.amount), 8, col))
		v.add_child(row)
	var bal := UiKit.hbox(3)
	bal.add_child(UiKit.label("Campaign dollars:", 8))
	bal.add_child(UiKit.dollar_amount(Profile.dollars()))
	bal.add_child(UiKit.label("   ", 8))
	var drop := TextureRect.new()
	drop.texture = UiKit.tex("res://assets/ui/icon_liquid_gold.png")
	bal.add_child(drop)
	bal.add_child(UiKit.label("+%d Liquid Gold" % int(res.liquid_gold), 8, Color("7a5a10")))
	v.add_child(bal)
	for id in res.unlocked:
		v.add_child(UiKit.label("Unlocked: %s" % Cosmetics.name_of(id), 8, Color("2f5d3a")))
	for r in res.knocked_out:
		v.add_child(UiKit.label("%s is broke and out of the running!" % Session.rival_def(int(r)).get("name", ""), 8, Color("8a2e1a")))
	if res.campaign_won:
		v.add_child(UiKit.label("Every rival is beaten. Texas is yours!", 10, Color("7a5a10")))
	elif won and not (_battle.rivals as Array).is_empty():
		var rival: Dictionary = Session.rival_def(int(_battle.rivals[0]))
		var quote := UiKit.label("\"%s\" - %s" % [rival.get("lose", ""), rival.get("name", "")], 8)
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quote.custom_minimum_size.x = 300
		v.add_child(quote)


func _show_message(text: String, then: Callable) -> void:
	var pnl := UiKit.panel(10)
	pnl.position = Vector2(200, 140)
	var v := UiKit.vbox(6)
	pnl.add_child(v)
	v.add_child(UiKit.label(text))
	v.add_child(UiKit.button("OK", then))
	add_child(pnl)
