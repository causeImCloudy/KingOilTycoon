class_name TestDriver
extends Node
## Development helper: screenshots every screen and bot-plays the human seat of a match.

var out_dir: String = ""
var autoplay_only: bool = false
var _bot_rng := RandomNumberGenerator.new()
var _shot_n: int = 0


var net_role: String = ""
var click_test: bool = false
var editor_test: bool = false
var shop_test: bool = false


func _ready() -> void:
	_bot_rng.seed = 99
	if net_role != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		await _net_test()
		return
	if click_test:
		DirAccess.make_dir_recursive_absolute(out_dir)
		await _click_test()
		return
	if editor_test:
		DirAccess.make_dir_recursive_absolute(out_dir)
		await _editor_test()
		return
	if shop_test:
		DirAccess.make_dir_recursive_absolute(out_dir)
		await _shop_test()
		return
	if autoplay_only:
		_start_match()
		_bot_loop()
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _tour()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_n += 1
	img.save_png(out_dir.path_join("%02d_%s.png" % [_shot_n, name]))
	print("shot ", name)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _tour() -> void:
	for id in ["menu", "setup", "campaign", "shop", "settings", "lobby"]:
		Session.goto(id)
		await _wait(0.6)
		await _shot(id)
		if id == "shop":
			get_tree().current_scene._set_tab("house")
			await _wait(0.3)
			await _shot("shop_homestead")
	# First-time character creation (profile untouched: the screen only saves on changes).
	Session.customize_mode = "create"
	Session.open_shop("tycoon", "campaign")
	await _wait(0.6)
	await _shot("create_tycoon")
	await _campaign_map_progress()
	_start_match()
	await _wait(1.0)
	await _shot("match_draft_banner")
	_bot_loop()
	var t := 0.0
	var taken := {}
	while t < 70.0:
		await _wait(0.25)
		t += 0.25
		var m := get_tree().current_scene
		if m == null or not m.has_method("my_turn"):
			continue
		if m.drill_popup.visible and not taken.has("popup") and m.drill_popup._caption.text.find("Cost") >= 0:
			taken["popup"] = true
			await _shot("drill_popup_reveal")
		elif m.big_card.visible and m.big_card.face_up and not taken.has("card"):
			taken["card"] = true
			await _shot("card_reveal")
		elif m.state.turn_number >= 6 and not taken.has("mid"):
			taken["mid"] = true
			await _shot("match_midgame")
		elif m.state.turn_number >= 20 and not taken.has("late"):
			taken["late"] = true
			await _shot("match_late")
			break
	await _campaign_test()
	await _classic_test()
	get_tree().quit()


## Classic mode (original rules): plays a full game fast, with screenshots of the opening,
## the first auction you bid in, and the result. The bot plays your seat too.
var _hold_bids: bool = false


func _classic_test() -> void:
	var backup: Dictionary = Profile.data.duplicate(true)
	Profile.data.settings.anim_speed = 1.0
	Session.goto("setup")
	await _wait(0.6)
	var setup := get_tree().current_scene
	setup.seed_edit.text = "1974"
	setup._start()
	await _wait(1.2)
	await _shot("classic_start")
	Profile.data.settings.anim_speed = 99.0
	var t := 0.0
	var shot_auction := false
	_hold_bids = true
	while t < 240.0:
		await _wait(0.25)
		t += 0.25
		var m := get_tree().current_scene
		if m == null or not m.has_method("my_turn"):
			continue
		if not shot_auction and m.state.phase == GameConst.PHASE_AUCTION and not m._playing and m._local_bidder() >= 0:
			shot_auction = true
			await _wait(0.3)
			await _shot("classic_auction")
			_hold_bids = false
		if m.result_panel != null:
			await _wait(0.3)
			await _shot("classic_result")
			var worths: Array = []
			for i in m.state.players.size():
				worths.append(m.state.net_worth(i))
			print("CLASSIC result: winner=%d reason=%s turns=%d worths=%s auction_shot=%s" % [m.state.winner, m.state.end_reason, m.state.turn_number, worths, shot_auction])
			break
	if t >= 240.0:
		print("CLASSIC did not finish in time")
	Profile.data = backup
	Session.delete_save()


## General Store: buys an outfit, a hat and an upgrade by pressing the real buttons, checks the
## Liquid Gold balance, then restores the profile. Prints PASS/FAIL.
func _shop_test() -> void:
	var had_file := FileAccess.file_exists(Profile.PATH)
	var backup: Dictionary = Profile.data.duplicate(true)
	Profile.data.liquid_gold = 300
	Profile.data.unlocked = []
	Profile.data.upgrades = {}
	Profile.data.look = Cosmetics.DEFAULT_LOOK.duplicate()
	Session.open_shop("outfit", "menu")
	await _wait(0.8)
	var shop := get_tree().current_scene
	await _shot("shop_outfits")
	shop.selected = "outfit_navy"
	shop._show_detail()
	shop.buy_btn.pressed.emit()
	await _wait(0.3)
	var ok1: bool = Profile.is_unlocked("outfit_navy") and Profile.liquid_gold() == 240 and Profile.look().outfit == "outfit_navy"
	print("SHOPTEST buy outfit (and wear it): ", "PASS" if ok1 else "FAIL lg=%d" % Profile.liquid_gold())
	shop._set_tab("hat")
	shop.selected = "hat_tophat"
	shop._show_detail()
	await _wait(0.3)
	await _shot("shop_hats_tryon")
	shop.buy_btn.pressed.emit()
	await _wait(0.2)
	print("SHOPTEST buy top hat: ", "PASS" if Profile.is_unlocked("hat_tophat") and Profile.liquid_gold() == 90 else "FAIL")
	shop.selected = "hat_tengallon"
	shop._show_detail()
	print("SHOPTEST can't afford is disabled: ", "PASS" if shop.buy_btn.disabled else "FAIL")
	shop._set_tab("upgrades")
	shop.buy_btn.pressed.emit()
	await _wait(0.3)
	print("SHOPTEST buy upgrade: ", "PASS" if Profile.upgrade_level("yield") == 1 and Profile.liquid_gold() == 50 else "FAIL")
	await _shot("shop_upgrades")
	shop._set_tab("paint")
	await _wait(0.3)
	await _shot("shop_paint")
	shop._set_tab("siding")
	shop.selected = "siding_yellow"
	shop._show_detail()
	shop.buy_btn.pressed.emit()
	await _wait(0.3)
	print("SHOPTEST buy siding (and use it): ", "PASS" if Profile.look().siding == "siding_yellow" and Profile.liquid_gold() == 20 else "FAIL")
	shop._set_tab("house")
	shop.selected = "house_mansion"
	shop._show_detail()
	await _wait(0.3)
	print("SHOPTEST house too dear is disabled: ", "PASS" if shop.buy_btn.disabled else "FAIL")
	await _shot("shop_houses")
	Profile.data = backup
	if had_file:
		Profile.save()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH))
	get_tree().quit()


## Map editor: screenshots several maps, then places a prop and draws a line with real clicks
## (nothing is saved). Prints PASS/FAIL.
func _editor_test() -> void:
	Session.goto("board_editor")
	await _wait(0.8)
	var ed := get_tree().current_scene
	for i in [0, 6, 11, 19, 20]:
		ed._on_map_picked(i)
		if ed.map_index != i:
			ed._on_map_picked(i) # second pick discards an unsaved auto-fill
		await _wait(0.4)
		await _shot("editor_" + str(ed.maps[i].id))
	ed._load_map(0)
	await _wait(0.3)
	print("EDITORTEST side panel fits: ", "PASS" if ed.palette.get_parent().get_parent().size.x <= 266.0 else "FAIL")
	var props_before: int = ed.layout.props.size()
	ed._set_tool(ed.T_PROPS)
	ed.selected = "barn_red"
	await _click_canvas(Vector2(6, 26) + Vector2(100, 100))
	await _wait(0.2)
	print("EDITORTEST place prop: ", "PASS" if ed.layout.props.size() == props_before + 1 else "FAIL")
	var lines_before: int = ed.layout.lines.size()
	ed._set_tool(ed.T_LINES)
	ed.selected = "railroad"
	await _click_canvas(Vector2(6, 26) + Vector2(24, 24))
	await _click_canvas(Vector2(6, 26) + Vector2(120, 72))
	ed._finish_line()
	await _wait(0.3)
	var ok_line: bool = ed.layout.lines.size() == lines_before + 1 and ed.layout.lines[-1].points.size() == 3
	print("EDITORTEST draw line with a bend: ", "PASS" if ok_line else "FAIL %s" % [ed.layout.lines.back()])
	await _shot("editor_edited")
	ed._undo()
	ed._undo()
	print("EDITORTEST undo: ", "PASS" if ed.layout.props.size() == props_before and ed.layout.lines.size() == lines_before else "FAIL")

	# Fields: a 16 px brush dab paints just that square, not the whole property; the bucket fills
	# the connected patch; undo puts both back.
	ed._set_tool(ed.T_FIELDS)
	var at := Vector2(150, 110)
	var g := Vector2i(at / BoardDecor.FIELD_CELL)
	var before: String = BoardDecor.field_at(ed.board, ed.layout, g.x, g.y)
	var paint: String = ""
	for id in BoardDecor.kit().fields:
		if id != before:
			paint = id
			break
	ed.selected = paint
	ed._set_brush(4)
	var grid_before: Array = BoardDecor.field_grid(ed.board, ed.layout).rows.duplicate()
	await _click_canvas(Vector2(6, 26) + at)
	await _wait(0.2)
	var painted := 0
	for gy in BoardDecor.FIELD_H:
		for gx in BoardDecor.FIELD_W:
			if BoardDecor.field_at(ed.board, ed.layout, gx, gy) == paint and (grid_before[gy] as String) != (BoardDecor.field_grid(ed.board, ed.layout).rows[gy] as String):
				painted += 1
	var dab_ok: bool = BoardDecor.field_at(ed.board, ed.layout, g.x, g.y) == paint and painted > 0 and painted <= 16
	print("EDITORTEST field brush paints a 16 px square: ", "PASS" if dab_ok else "FAIL (%d cells)" % painted)
	await _shot("editor_fields")
	ed._set_brush(0)
	ed.selected = before
	await _click_canvas(Vector2(6, 26) + at)
	await _wait(0.2)
	print("EDITORTEST field bucket refills the patch: ", "PASS" if BoardDecor.field_grid(ed.board, ed.layout).rows == grid_before else "FAIL")
	ed._undo()
	ed._undo()
	ed._set_brush(2)
	print("EDITORTEST undo field paint: ", "PASS" if BoardDecor.field_grid(ed.board, ed.layout).rows == grid_before else "FAIL")

	# Board editing: paint a cell into another property, add and remove a drill site, make a new
	# property, then undo it all. Nothing is saved.
	var b0: BoardMap = ed.board
	var plots0: int = b0.plots.size()
	var sites0: int = b0.sites.size()
	var cell: int = BoardDecor.cell_size(b0)
	ed._set_tool(ed.T_PLOTS)
	await _wait(0.2)
	await _shot("editor_plots")
	# Find a cell next to another property and paint it into that neighbor.
	var target := Vector2i(-1, -1)
	var into := -1
	for y in b0.height:
		for x in range(1, b0.width):
			var a := b0.cell_plot(x, y)
			var nb := b0.cell_plot(x - 1, y)
			if a >= 0 and nb >= 0 and a != nb and b0.site_at(x, y) < 0:
				target = Vector2i(x, y)
				into = nb
				break
		if target.x >= 0:
			break
	ed.selected = str(into)
	await _click_canvas(Vector2(6, 26) + (Vector2(target) + Vector2(0.5, 0.5)) * cell)
	await _wait(0.2)
	print("EDITORTEST paint a cell into a neighbor: ", "PASS" if ed.board.cell_plot(target.x, target.y) == into and ed.board_dirty else "FAIL")
	ed._set_tool(ed.T_SITES)
	var free := Vector2i(-1, -1)
	for y in ed.board.height:
		for x in ed.board.width:
			if ed.board.cell_plot(x, y) >= 0 and ed.board.site_at(x, y) < 0:
				free = Vector2i(x, y)
				break
		if free.x >= 0:
			break
	var p_free: int = ed.board.cell_plot(free.x, free.y)
	var price0: int = ed.board.plots[p_free].price
	await _click_canvas(Vector2(6, 26) + (Vector2(free) + Vector2(0.5, 0.5)) * cell)
	await _wait(0.2)
	var added: bool = ed.board.sites.size() == sites0 + 1 and ed.board.plots[p_free].price == price0 + 1000
	print("EDITORTEST add a drill site (+$1,000): ", "PASS" if added else "FAIL")
	await _shot("editor_sites")
	ed._set_tool(ed.T_PLOTS)
	ed.selected = ed.NEW_PLOT
	await _click_canvas(Vector2(6, 26) + (Vector2(free) + Vector2(0.5, 0.5)) * cell)
	await _wait(0.2)
	var made_new: bool = ed.board.plots.size() == plots0 + 1 and ed.board.check_playable(1) == ""
	print("EDITORTEST new property (with the site): ", "PASS" if made_new else "FAIL %d plots, %s" % [ed.board.plots.size(), ed.board.check_playable(1)])
	while not ed.undo_stack.is_empty():
		ed._undo()
	var restored: bool = ed.board.plots.size() == plots0 and ed.board.sites.size() == sites0 and ed.board.cell_plot(target.x, target.y) == b0.cell_plot(target.x, target.y)
	print("EDITORTEST undo board edits: ", "PASS" if restored else "FAIL")
	get_tree().quit()


## Sends a real left click (press + release) at a canvas position, like a mouse would.
func _click_canvas(canvas_pos: Vector2) -> void:
	# push_input with in_local_coords = true takes 640x360 canvas coordinates directly.
	var mv := InputEventMouseMotion.new()
	mv.position = canvas_pos
	mv.global_position = canvas_pos
	get_viewport().push_input(mv, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = canvas_pos
		ev.global_position = canvas_pos
		get_viewport().push_input(ev, true)
		await get_tree().process_frame


## Clicks the board to buy starting land, and clicks a campaign spot to travel. Prints PASS/FAIL.
func _click_test() -> void:
	var had_file := FileAccess.file_exists(Profile.PATH)
	var backup: Dictionary = Profile.data.duplicate(true)
	Profile.data.settings.anim_speed = 2.0
	var players: Array = [{"name": "Clicker", "is_ai": false, "character": Profile.look(), "color": 0},
		{"name": "AI", "is_ai": true, "ai_level": 1, "character": Profile.look(), "color": 1}]
	Session.start_offline({"seed": 4242, "map_type": "procedural", "speed": "blitz", "players": players})
	var m: Node = null
	for i in 80:
		await _wait(0.25)
		m = get_tree().current_scene
		if m and m.has_method("my_turn") and m.my_turn() and m.state.phase == GameConst.PHASE_DRAFT:
			break
	var plot := -1
	for i in m.state.plot_owner.size():
		if m.state.plot_owner[i] == -1 and int(m.state.board.plots[i].price) <= int(m.state.players[0].cash):
			plot = i
			break
	var bv: BoardView = m.board_view
	var at: Vector2 = bv.get_global_transform_with_canvas() * bv.plot_center(plot)
	await _click_canvas(at)
	await _wait(0.2)
	var selected_ok: bool = bv.selected_plot == plot and m.info_buttons.get_child_count() > 0
	print("CLICKTEST select plot: ", "PASS" if selected_ok else "FAIL (selected=%d buttons=%d)" % [bv.selected_plot, m.info_buttons.get_child_count()])
	await _shot("click_selected_plot")
	await _click_canvas(at)
	await _wait(0.5)
	print("CLICKTEST buy plot: ", "PASS" if m.state.plot_owner[plot] == 0 else "FAIL (owner=%d)" % m.state.plot_owner[plot])

	# Fire: give us wells, force a Blowout Fire, draw it, then click a derrick to cap it.
	for i in 120:
		await _wait(0.25)
		if m.my_turn() and m.state.phase == GameConst.PHASE_CARD:
			break
	var mine: Array = m.state.open_sites_of(0)
	for i in mini(6, mine.size()):
		m.state.site_state[mine[i]] = GameConst.SITE_OIL
	m.state.draw_pile.append({"id": 90, "kind": "fire", "rate": 0, "wells": 0, "land": false, "title": "Blowout Fire!", "text": "Pick 1 well per\n5 you own to cap."})
	m._sync_view()
	await _click_canvas(m.deck_rect.get_global_rect().get_center()) # draw by clicking the deck
	for i in 40:
		await _wait(0.25)
		if m.my_turn():
			break
	var fire_ok: bool = m.state.phase == GameConst.PHASE_FIRE and not bv.highlight_sites.is_empty()
	print("CLICKTEST fire asks to pick: ", "PASS" if fire_ok else "FAIL (phase=%s rings=%d)" % [m.state.phase, bv.highlight_sites.size()])
	await _shot("fire_pick_wells")
	var target: int = bv.highlight_sites[0] if not bv.highlight_sites.is_empty() else -1
	if target >= 0:
		# Click the derrick tower, a few pixels above the site.
		await _click_canvas(bv.get_global_transform_with_canvas() * (bv.site_pos(target) + Vector2(0, -6)))
		for i in 20:
			await _wait(0.25)
			if m.my_turn():
				break
	var capped_ok: bool = target >= 0 and m.state.site_state[target] == GameConst.SITE_BURNED
	print("CLICKTEST click derrick caps it: ", "PASS" if capped_ok else "FAIL (state=%d phase=%s)" % [m.state.site_state[target] if target >= 0 else -9, m.state.phase])
	# Cap the rest the same way, then end the turn.
	var guard := 0
	while m.state.phase == GameConst.PHASE_FIRE and guard < 6:
		guard += 1
		var t2: int = bv.highlight_sites[0]
		await _click_canvas(bv.get_global_transform_with_canvas() * (bv.site_pos(t2) + Vector2(0, -6)))
		for i in 20:
			await _wait(0.25)
			if m.my_turn():
				break
	print("CLICKTEST fire finished: ", "PASS" if m.state.phase == GameConst.PHASE_ACTIONS else "FAIL (phase=%s)" % m.state.phase)
	m.end_btn.pressed.emit()

	# Land for sale: force a production card with land and check the board advertises it.
	for i in 120:
		await _wait(0.25)
		if m.my_turn() and m.state.phase == GameConst.PHASE_CARD:
			break
	m.state.draw_pile.append({"id": 91, "kind": "production", "rate": 1000, "wells": 1, "land": true, "title": "Steady Crude", "text": "$1,000 per well.\nDrill up to 1.\nLand for sale!"})
	await _click_canvas(m.deck_rect.get_global_rect().get_center()) # draw by clicking the deck
	for i in 40:
		await _wait(0.25)
		if m.my_turn() and m.state.phase == GameConst.PHASE_ACTIONS:
			break
	await _wait(0.3)
	var sale_ok: bool = m.draw_btn.visible and not m.draw_btn.disabled and bv.sale_mode and not bv.highlight_plots.is_empty()
	print("CLICKTEST deck click drew the card: ", "PASS" if m.state.card.get("id", -1) == 91 else "FAIL (card=%s)" % m.state.card)
	print("CLICKTEST land for sale shown: ", "PASS" if sale_ok else "FAIL (btn=%s sale=%s plots=%d)" % [m.draw_btn.text, bv.sale_mode, bv.highlight_plots.size()])
	await _shot("land_for_sale")

	# Trading: open the deal panel, click the rival's plot on the board, sell the land right with
	# cash. Player 2 plays as a person here (hotseat), accepts, then picks the land to buy.
	m.state.players[1].cash = 40000
	# Start the deal the way a player does: click the rival's name in the player list.
	await _click_canvas(m.panels[1].get_global_rect().get_center())
	await _wait(0.2)
	print("CLICKTEST clicking a name opens the trade panel: ", "PASS" if m._trade_view == "compose" and int(m._deal.to) == 1 else "FAIL (view=%s)" % m._trade_view)
	var rival_plot: int = m.state.plots_of(1)[0]
	var sale_plot := -1
	for i in m.state.plot_owner.size():
		if m.state.plot_owner[i] == -1 and int(m.state.board.plots[i].price) <= 20000:
			sale_plot = i
			break
	await _click_canvas(bv.get_global_transform_with_canvas() * bv.plot_center(rival_plot))
	await _wait(0.2)
	var sell := _find_button(m._trade_panel, "Sell")
	if sell:
		sell.pressed.emit()
	await _wait(0.2)
	var picked_ok: bool = rival_plot in m._deal.get_plots and bool(m._deal.land_right) and bv.trade_marks.has(rival_plot)
	print("CLICKTEST trade picks land and sells the land right: ", "PASS" if picked_ok else "FAIL (deal=%s)" % m._deal)
	m._change_deal_cash("give_cash", 1000, int(m.state.players[0].cash))
	await _shot("trade_compose")
	# Asking for the rival's only plot is allowed (they'd be out); send is enabled.
	var send := _find_button(m._trade_panel, "Send Offer")
	print("CLICKTEST trade allows asking for all their land: ", "PASS" if send and not send.disabled else "FAIL")
	await _click_canvas(bv.get_global_transform_with_canvas() * bv.plot_center(rival_plot))
	await _wait(0.2)
	send = _find_button(m._trade_panel, "Send Offer")
	m.state.players[1].is_ai = false
	var cash_before: int = m.state.players[0].cash
	if send and not send.disabled:
		send.pressed.emit()
	for i in 20:
		await _wait(0.25)
		if not m._playing and m._trade_view == "reply":
			break
	print("CLICKTEST trade offer reaches the other player: ", "PASS" if m._trade_view == "reply" and not m.state.trade.is_empty() else "FAIL (view=%s)" % m._trade_view)
	await _shot("trade_reply")
	var accept := _find_button(m._trade_panel, "Accept")
	if accept:
		accept.pressed.emit()
	for i in 20:
		await _wait(0.25)
		if not m._playing and m.state.trade.is_empty():
			break
	var holds_ok: bool = m.state.right_holder == 1 and bv.sale_mode and sale_plot in bv.highlight_plots \
		and _find_button(m.info_buttons, "Skip, buy nothing") != null
	print("CLICKTEST buyer is asked to pick land: ", "PASS" if holds_ok else "FAIL (holder=%d)" % m.state.right_holder)
	await _shot("trade_pick_land")
	var at_sale: Vector2 = bv.get_global_transform_with_canvas() * bv.plot_center(sale_plot)
	await _click_canvas(at_sale)
	await _wait(0.2)
	await _click_canvas(at_sale)
	for i in 20:
		await _wait(0.25)
		if not m._playing and m.state.right_holder < 0:
			break
	var deal_ok: bool = m.state.plot_owner[sale_plot] == 1 and int(m.state.players[0].cash) == cash_before - 1000 and not m.state.can_buy
	print("CLICKTEST trade accepted: ", "PASS" if deal_ok else "FAIL (owner=%d cash=%d)" % [m.state.plot_owner[sale_plot], m.state.players[0].cash])
	await _wait(0.6)
	await _shot("trade_done")
	m.state.players[1].is_ai = true

	# Campaign map: click spot 2 (requires map 1 won) and check the tycoon walks there.
	Profile.data.character_created = true
	Profile.data.campaign_done = [0]
	Profile.data.campaign_pos = 0
	Session.goto("campaign")
	await _wait(0.6)
	var c := get_tree().current_scene
	await _click_canvas(c._spot(1))
	await _wait(0.8)
	print("CLICKTEST campaign spot: ", "PASS" if c.current == 1 else "FAIL (current=%d)" % c.current)
	Profile.data = backup
	if had_file:
		Profile.save()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH))
	Session.delete_save()
	get_tree().quit()


func _find_button(root: Node, text: String) -> Button:
	if root == null or not is_instance_valid(root):
		return null
	if root is Button and root.text == text:
		return root
	for c in root.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


## World map with some progress: 6 maps won, then the tycoon walks one spot. Profile restored.
func _campaign_map_progress() -> void:
	var had_file := FileAccess.file_exists(Profile.PATH)
	var backup: Dictionary = Profile.data.duplicate(true)
	Profile.data.campaign_done = [0, 1, 2, 3, 4, 5]
	Profile.data.campaign_pos = 5
	Profile.data.liquid_gold = 245
	Session.goto("campaign")
	await _wait(0.6)
	await _shot("campaign_progress")
	var ev := InputEventKey.new()
	ev.keycode = KEY_RIGHT
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.8)
	await _shot("campaign_walked")
	Profile.data = backup
	if had_file:
		Profile.save()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH))


## Plays campaign map 1 to the end at instant speed. The real profile is backed up and restored.
func _campaign_test() -> void:
	var had_file := FileAccess.file_exists(Profile.PATH)
	var backup: Dictionary = Profile.data.duplicate(true)
	# Title card of level 7 at normal speed, then play level 1 at instant speed.
	Profile.data.settings.anim_speed = 1.0
	Session.start_offline(Session.campaign_config(6), 6)
	await _wait(1.2)
	await _shot("level_intro")
	await _wait(0.3)
	await _click_canvas(Vector2(320, 180))
	await _wait(0.8)
	await _shot("level_backdrop")
	Session.delete_save()
	Profile.data.settings.anim_speed = 99.0
	Session.start_offline(Session.campaign_config(0), 0)
	var t := 0.0
	var done := false
	while t < 120.0:
		await _wait(0.5)
		t += 0.5
		var m := get_tree().current_scene
		if m and m.has_method("my_turn") and m.result_panel != null:
			done = true
			await _wait(0.3)
			await _shot("campaign_result")
			print("CAMPAIGN result: winner=%d turns=%d liquid_gold=%d" % [m.state.winner, m.state.turn_number, Profile.liquid_gold()])
			break
	if not done:
		print("CAMPAIGN did not finish in time")
	Profile.data = backup
	if had_file:
		Profile.save()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH))
	Session.delete_save()


## Two local instances over ENet: the host adds one AI seat and starts; both bot-play their seat.
func _net_test() -> void:
	Profile.data.settings.anim_speed = 2.0 # not saved
	if net_role == "host":
		Profile.data.name = "Host"
		Net.host_lan("127.0.0.1") # loopback only: no firewall prompt
		var t := 0.0
		while Net.slots.filter(func(s): return s.kind == "human").size() < 2 and t < 20.0:
			await _wait(0.25)
			t += 0.25
		Net.set_slot_kind(2, "ai")
		await _wait(0.5)
		Net.start_match()
	else:
		Profile.data.name = "Client"
		await _wait(1.5)
		Net.join_lan("127.0.0.1")
	_bot_loop()
	await _wait(35.0)
	var m := get_tree().current_scene
	if m and m.has_method("my_turn"):
		await _shot("net_" + net_role)
		var s: GameState = m.state
		print("NETSTATE %s turn=%d bank=%d cash=%s owners=%s sites=%s" % [net_role, s.turn_number, s.bank,
			str(s.players.map(func(p): return p.cash)), str(s.plot_owner), str(s.site_state).hash()])
	else:
		print("NETSTATE %s not in match" % net_role)
	get_tree().quit()


func _start_match() -> void:
	var players: Array = [{"name": "You (bot)", "is_ai": false, "character": Profile.look(), "color": 0}]
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 3:
		players.append({"name": ["Hardpan", "Dolores", "Judge Pickett"][i], "is_ai": true, "ai_level": i % 3,
			"character": Cosmetics.random_look(r), "color": i + 1})
	Session.start_offline({"seed": 777, "map_type": "procedural", "speed": "blitz", "players": players})


## Plays the human seat through the same code paths as a real player (submit()).
func _bot_loop() -> void:
	while is_inside_tree():
		await _wait(0.4)
		var m := get_tree().current_scene
		if m == null or not m.has_method("my_turn"):
			continue
		if m.state.phase == GameConst.PHASE_AUCTION and not m._playing and m._local_bidder() >= 0:
			if _hold_bids:
				continue
			var bidder: int = m._local_bidder()
			m.submit({"type": "bid", "player": bidder, "amount": AIPlayer.auction_bid(m.state, bidder, 1, _bot_rng)})
			continue
		if not m.state.trade.is_empty() and not m._playing and m.is_local(int(m.state.trade.to)):
			var to := int(m.state.trade.to)
			m.submit({"type": "trade_reply", "player": to, "accept": AIPlayer.trade_reply(m.state, to, 1, _bot_rng)})
			continue
		if m.state.right_holder >= 0 and not m._playing and m.is_local(m.state.right_holder):
			m.submit(AIPlayer.choose_action(m.state, m.state.right_holder, _bot_rng))
			continue
		if not m.my_turn() or not m.state.trade.is_empty() or m.state.right_holder >= 0:
			continue
		var a := AIPlayer.choose_action(m.state, m.state.current, _bot_rng)
		if a.is_empty():
			continue
		m.submit(a)
