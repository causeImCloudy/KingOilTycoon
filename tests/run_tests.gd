extends SceneTree
## Headless rules tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any check fails. Also prints simulated game lengths per speed preset.

var failures: int = 0
var checks: int = 0


func _init() -> void:
	test_deck()
	test_maps()
	test_edited_boards()
	test_classic_notches()
	test_draft_and_turns()
	test_drill_rules()
	test_fire_choice()
	test_bankruptcy()
	test_pipelines()
	test_original_rules()
	test_board_seed()
	test_homestead()
	test_trading()
	test_serialization()
	test_full_games()
	test_original_games()
	print("\n%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func make_settings(n: int, speed_id: String = "classic", map_type: String = "procedural", seed_value: int = 1234) -> Dictionary:
	var players: Array = []
	for i in n:
		players.append({"name": "AI %d" % i, "is_ai": true, "ai_level": i % 3})
	return {"seed": seed_value, "map_type": map_type, "speed": speed_id, "players": players}


func test_deck() -> void:
	var cards := Deck.build()
	check(cards.size() == 32, "deck has 32 cards (got %d)" % cards.size())
	var prod := cards.filter(func(c): return c.kind == Deck.KIND_PRODUCTION)
	check(prod.size() == 25, "25 production cards")
	check(prod.filter(func(c): return c.land).size() == 7, "7 production cards sell land")
	check(cards.filter(func(c): return c.kind == Deck.KIND_FIRE).size() == 2, "2 fire cards")


func test_maps() -> void:
	for n in [2, 4, 6]:
		var m := BoardMap.create_procedural(99 + n, n)
		var expected := BoardMap.LARGE_PLOTS if n > 4 else BoardMap.STANDARD_PLOTS
		check(m.plots.size() == expected, "%d-player map has %d plots" % [n, expected])
		for plot in m.plots:
			check(plot.sites.size() >= 4, "plot %s has sites (%d)" % [plot.name, plot.sites.size()])
			check(int(plot.price) == plot.sites.size() * 1000, "price = $1000 per site")
			check(m.adjacency[plot.id].size() > 0, "plot %d has neighbors" % plot.id)
	var c := BoardMap.create_classic()
	check(c.plots.size() == 18, "classic map has 18 plots")
	for y in c.height:
		for x in c.width:
			check(c.cell_plot(x, y) >= 0, "classic cell %d,%d has a plot" % [x, y])
	var a := BoardMap.create_procedural(5, 4)
	var b := BoardMap.create_procedural(5, 4)
	check(a.cells == b.cells, "procedural maps are deterministic per seed")
	var survey := BoardMap.create("classic_1974", 123, 4)
	check(survey.plots.size() == 18 and survey.sites.size() == 169, "1974 board has all properties and holes")
	check(survey.cell_plot(30, 20) == -1, "central hub is outside the properties")
	for p in survey.plots:
		check(p.sites.size() == BoardMap.CLASSIC_SITE_COUNTS[p.id], "hole count on " + p.name)
		check(survey.cell_plot(floori(p.center_x), floori(p.center_y)) == p.id, "label inside " + p.name)
		for sid in p.sites:
			var site: Dictionary = survey.sites[sid]
			check(survey.cell_plot(site.x, site.y) == p.id, "hole inside " + p.name)


func test_classic_notches() -> void:
	var board := BoardMap.create_classic()
	var seen := {}
	for seed_value in 40:
		var r := RandomNumberGenerator.new()
		r.seed = seed_value + 1
		var f := OilField.create(board, r)
		seen[str(f.notches)] = true
	check(seen.size() > 30, "classic notches vary between games")


func test_draft_and_turns() -> void:
	var s := GameState.new_match(make_settings(3))
	check(s.phase == GameConst.PHASE_DRAFT, "starts in draft")
	var money := s.total_money()
	check(money == int(s.speed.bank_size), "money is conserved at start")
	var bad := s.apply({"type": "draw", "player": s.current})
	check(not bad.ok, "can't draw during draft")
	var rng := RandomNumberGenerator.new()
	for i in 3:
		var a := AIPlayer.choose_action(s, AIPlayer.actor(s), rng)
		check(s.apply(a).ok, "draft pick ok")
	check(s.phase == GameConst.PHASE_CARD, "after draft, first turn waits for a card")
	var richest := 0
	for p in 3:
		var pr: int = s.board.plots[s.plots_of(p)[0]].price
		if pr > richest:
			richest = pr
	check(int(s.board.plots[s.plots_of(s.current)[0]].price) == richest, "most expensive buyer goes first")
	var wrong := (s.current + 1) % 3
	check(not s.apply({"type": "draw", "player": wrong}).ok, "can't act out of turn")
	check(s.total_money() == money, "money conserved after draft")


func test_drill_rules() -> void:
	var s := GameState.new_match(make_settings(2))
	var rng := RandomNumberGenerator.new()
	while s.phase == GameConst.PHASE_DRAFT:
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
	var p := s.current
	# Force a production card for a predictable test.
	s.draw_pile.append({"id": 99, "kind": "production", "rate": 1000, "wells": 2, "land": false, "title": "t", "text": ""})
	var r := s.apply({"type": "draw", "player": p})
	check(r.ok and s.drills_left == 2, "production card grants drills")
	var other_site: int = s.board.plots[s.plots_of(1 - p)[0]].sites[0]
	check(not s.apply({"type": "drill", "player": p, "site": other_site}).ok, "can't drill rival land")
	var sid: int = s.open_sites_of(p)[0]
	var cash_before: int = s.players[p].cash
	r = s.apply({"type": "drill", "player": p, "site": sid})
	check(r.ok, "drill own site")
	var ev: Dictionary = r.events[0]
	var expected_cost := s.drill_cost(p, ev.depth)
	check(cash_before - int(s.players[p].cash) == expected_cost, "drill cost charged by depth")
	check(expected_cost > 0, "shallow drilling is not free (sim bug fixed)")
	check(s.site_state[sid] == (GameConst.SITE_OIL if ev.oil else GameConst.SITE_DRY), "dry hole is not counted as oil")
	check(not s.apply({"type": "drill", "player": p, "site": sid}).ok, "can't redrill a site")
	r = s.apply({"type": "end_turn", "player": p})
	check(r.ok and s.current == 1 - p, "turn passes to the other player (no skipped seats)")


func test_fire_choice() -> void:
	var s := GameState.new_match(make_settings(2))
	var rng := RandomNumberGenerator.new()
	while s.phase == GameConst.PHASE_DRAFT:
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
	var p := s.current
	# Give the player 6 producing wells, then force a fire card.
	var sites := s.open_sites_of(p)
	for i in mini(6, sites.size()):
		s.site_state[sites[i]] = GameConst.SITE_OIL
	var wells := s.producing_wells_of(p)
	s.draw_pile.append({"id": 98, "kind": "fire", "rate": 0, "wells": 0, "land": false, "title": "t", "text": ""})
	var r := s.apply({"type": "draw", "player": p})
	var expect := ceili(wells / 5.0)
	check(r.ok and s.phase == GameConst.PHASE_FIRE and s.fire_left == expect, "fire asks to cap %d well(s)" % expect)
	check(not s.apply({"type": "end_turn", "player": p}).ok, "can't end turn before capping")
	var rival_site: int = s.board.plots[s.plots_of(1 - p)[0]].sites[0]
	check(not s.apply({"type": "cap", "player": p, "site": rival_site}).ok, "can't cap a rival's well")
	var chosen: int = -1
	for plot in s.plots_of(p):
		for sid in s.board.plots[plot].sites:
			if s.site_state[sid] == GameConst.SITE_OIL and chosen < 0:
				chosen = sid
	for i in expect:
		var pick := chosen if i == 0 else AIPlayer.pick_well_to_cap(s, p, 1, rng)
		r = s.apply({"type": "cap", "player": p, "site": pick})
		check(r.ok, "cap chosen well")
	check(s.site_state[chosen] == GameConst.SITE_BURNED, "the chosen well is the one capped")
	check(s.phase == GameConst.PHASE_ACTIONS and s.producing_wells_of(p) == wells - expect, "fire done, wells reduced")
	check(s.apply({"type": "end_turn", "player": p}).ok, "turn can end after capping")


func test_bankruptcy() -> void:
	var s := GameState.new_match(make_settings(3))
	var rng := RandomNumberGenerator.new()
	while s.phase == GameConst.PHASE_DRAFT:
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
	var debtor := s.current
	var creditor := (debtor + 1) % 3
	var money := s.total_money()
	# Creditor owns a plot next to the debtor's plot with a pipeline into it.
	var dplot: int = s.plots_of(debtor)[0]
	var cplot: int = s.board.adjacency[dplot][0]
	s.plot_owner[cplot] = creditor
	for sid in s.board.plots[cplot].sites:
		s.site_state[sid] = GameConst.SITE_OIL
	s.site_state[s.board.plots[dplot].sites[0]] = GameConst.SITE_OIL
	s.pipelines.append({"id": 0, "owner": creditor, "from": cplot, "to": dplot, "level": 3})
	var owed := s.royalty_for(s.pipelines[0])
	s.players[debtor].cash = owed - 1000
	s.bank += int(s.speed.starting_cash) - (owed - 1000) # keep money conserved in this setup
	var debtor_plots := s.plots_of(debtor)
	var before: int = s.players[creditor].cash
	var r := s.apply({"type": "draw", "player": debtor})
	check(r.ok and s.players[debtor].bankrupt, "can't pay royalties -> bankrupt")
	check(int(s.players[creditor].cash) == before + owed - 1000, "creditor gets all the debtor's cash")
	var all_taken := true
	for plot in debtor_plots:
		if s.plot_owner[plot] != creditor:
			all_taken = false
	check(all_taken, "creditor gets all the debtor's land")
	check(s.site_state[s.board.plots[dplot].sites[0]] == GameConst.SITE_OIL, "wells come with the land")
	check(s.current != debtor, "turn moves past the bankrupt player")
	check(s.phase != GameConst.PHASE_GAME_OVER, "3-player game continues with 2 left")

	# Campaign: the moment the (human) player goes bankrupt, the match ends.
	var cfg := make_settings(3)
	cfg["campaign"] = true
	cfg.players[0].is_ai = false
	var cm := GameState.new_match(cfg)
	while cm.phase == GameConst.PHASE_DRAFT:
		cm.apply(AIPlayer.choose_action(cm, AIPlayer.actor(cm), rng))
	var cev: Array = []
	cm._bankrupt(0, 1, cev)
	cm._check_game_over(cev)
	check(cm.phase == GameConst.PHASE_GAME_OVER and cm.end_reason == "player_out" and cm.winner != 0,
		"campaign: going bankrupt ends the match at once")
	var rivals_out := GameState.new_match(cfg)
	while rivals_out.phase == GameConst.PHASE_DRAFT:
		rivals_out.apply(AIPlayer.choose_action(rivals_out, AIPlayer.actor(rivals_out), rng))
	cev = []
	rivals_out._bankrupt(2, 1, cev)
	rivals_out._check_game_over(cev)
	check(rivals_out.phase != GameConst.PHASE_GAME_OVER, "campaign: a rival going bankrupt doesn't end it")

	# Two players: bankrupting the other ends the game.
	var t := GameState.new_match(make_settings(2))
	while t.phase == GameConst.PHASE_DRAFT:
		t.apply(AIPlayer.choose_action(t, AIPlayer.actor(t), rng))
	var d := t.current
	var c := 1 - d
	var dp: int = t.plots_of(d)[0]
	var cp := -1
	for nb in t.board.adjacency[dp]:
		if t.plot_owner[nb] == -1:
			cp = nb
	if cp >= 0:
		t.plot_owner[cp] = c
		for sid in t.board.plots[cp].sites:
			t.site_state[sid] = GameConst.SITE_OIL
		t.site_state[t.board.plots[dp].sites[0]] = GameConst.SITE_OIL # royalties are per derrick on dp
		t.pipelines.append({"id": 0, "owner": c, "from": cp, "to": dp, "level": 3})
		t.players[d].cash = 0
		t.apply({"type": "draw", "player": d})
		check(t.phase == GameConst.PHASE_GAME_OVER and t.winner == c, "last tycoon standing wins")


func original_settings(seed_value: int = 77) -> Dictionary:
	var st := make_settings(4, "original", "classic_1974", seed_value)
	st["rules"] = "original"
	return st


## Draft every seat, then hand back a state at the start of a turn.
func drafted(st: Dictionary) -> GameState:
	var s := GameState.new_match(st)
	var rng := RandomNumberGenerator.new()
	while s.phase == GameConst.PHASE_DRAFT:
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
	return s


## Pipelines: 4 derricks for level 1, 5 for level 2, 6 for level 3, one target per property.
func test_pipelines() -> void:
	for rules in ["", "original"]:
		var cfg := make_settings(3)
		cfg["rules"] = rules
		var s := GameState.new_match(cfg)
		var src := -1
		for plot in s.board.plots.size():
			if s.board.plots[plot].sites.size() >= 6 and s.board.adjacency[plot].size() >= 2:
				src = plot
				break
		check(src >= 0, "a plot with 6 sites and 2 neighbors")
		var nb1: int = s.board.adjacency[src][0]
		var nb2: int = s.board.adjacency[src][1]
		s.plot_owner[src] = 0
		s.plot_owner[nb1] = 1
		s.plot_owner[nb2] = 2
		s.phase = GameConst.PHASE_ACTIONS
		s.current = 0
		s.players[0].cash = 500000
		var sites: Array = s.board.plots[src].sites
		var set_derricks := func(n: int):
			for i in sites.size():
				s.site_state[sites[i]] = GameConst.SITE_OIL if i < n else GameConst.SITE_DRY
		var tag := "classic" if rules == "original" else "house"
		set_derricks.call(3)
		check(s.check_pipeline(0, src, nb1) != "", "%s: 3 derricks: no pipeline" % tag)
		set_derricks.call(4)
		check(s.apply({"type": "pipeline", "player": 0, "from": src, "to": nb1}).ok, "%s: 4 derricks: level 1" % tag)
		set_derricks.call(6)
		check(s.check_pipeline(0, src, nb2).contains("one pipeline"), "%s: one property pipes into one property only" % tag)
		set_derricks.call(4)
		check(s.check_pipeline(0, src, nb1) != "", "%s: 4 derricks: no level 2" % tag)
		set_derricks.call(5)
		check(s.apply({"type": "pipeline", "player": 0, "from": src, "to": nb1}).ok, "%s: 5 derricks: level 2" % tag)
		check(s.check_pipeline(0, src, nb1) != "", "%s: 5 derricks: no level 3" % tag)
		set_derricks.call(6)
		check(s.apply({"type": "pipeline", "player": 0, "from": src, "to": nb1}).ok, "%s: 6 derricks: level 3" % tag)
		check(s.pipelines.size() == 1 and int(s.pipelines[0].level) == 3, "%s: one pipeline at level 3" % tag)
		check(s.check_pipeline(0, src, nb1) != "", "%s: nothing past level 3" % tag)
		# The rival can't pipe straight back into the property piping into theirs.
		s.current = 1
		s.players[1].cash = 500000
		for sid in s.board.plots[nb1].sites:
			s.site_state[sid] = GameConst.SITE_OIL
		check(s.check_pipeline(1, nb1, src).contains("already runs"), "%s: no pipeline straight back" % tag)
		s.current = 0
		# Royalties: per derrick on the property piped into, not on the source.
		var target_sites: Array = s.board.plots[nb1].sites
		for i in target_sites.size():
			s.site_state[target_sites[i]] = GameConst.SITE_OIL if i < 2 else GameConst.SITE_DRY
		var two := s.royalty_for(s.pipelines[0])
		set_derricks.call(4)
		check(s.royalty_for(s.pipelines[0]) == two, "%s: source derricks don't change the royalty" % tag)
		s.site_state[target_sites[0]] = GameConst.SITE_DRY
		check(s.royalty_for(s.pipelines[0]) * 2 == two and two > 0, "%s: royalty is per derrick on the piped property" % tag)
		if rules == "":
			check(two == 5 * int(s.speed.royalty_per_well) * 2, "house: level 3 pays 5x rate x 2 derricks")


func test_original_rules() -> void:
	var s := drafted(original_settings())
	check(s.original_rules(), "Classic mode uses the original rules")
	check(s.total_money() == 825000, "money supply is $825,000 (got %d)" % s.total_money())
	var prices: Array = s.board.plots.map(func(pl): return int(pl.price))
	check(prices == [12000, 8000, 9000, 11000, 9000, 9000, 8000, 8000, 10000, 10000, 9000, 8000, 8000, 10000, 8000, 8000, 12000, 12000],
		"18 properties at the original prices (got %s)" % [prices])
	for i in s.board.plots.size():
		check(s.board.plots[i].sites.size() * 1000 == int(s.board.plots[i].price), "property %d: $1,000 per site" % i)
	check(s.drill_cost(0, GameConst.DEPTH_SHALLOW) == 2000 and s.drill_cost(0, GameConst.DEPTH_MEDIUM) == 4000 \
		and s.drill_cost(0, GameConst.DEPTH_DEEP) == 6000 and s.drill_cost(0, GameConst.DEPTH_DRY) == 6000, "drilling $2k/$4k/$6k, dry $6k")
	check(s.pipeline_cost() == 25000, "pipelines cost $25,000")
	check(s.drill_cash_needed(0) == 1, "may drill with any cash, even under $6,000")
	check([1, 5, 6, 10, 11, 20].map(func(w): return s.fire_cap_count(w)) == [1, 1, 2, 2, 3, 3],
		"fire caps 1 well (1-5), 2 (6-10), 3 (11+)")

	# Pipelines and royalties.
	var a := s.current
	var b := (a + 1) % 4
	var ap: int = s.plots_of(a)[0]
	var bp: int = s.board.adjacency[ap][0]
	s.plot_owner[bp] = b
	for i in 6:
		s.site_state[s.board.plots[ap].sites[i]] = GameConst.SITE_OIL
	for i in 3:
		s.site_state[s.board.plots[bp].sites[i]] = GameConst.SITE_OIL
	s.players[a].cash = 200000
	s.players[b].cash = 200000
	s.bank = 825000 - 400000 # keep the money check honest below
	for i in s.players.size():
		if i != a and i != b:
			s.bank -= int(s.players[i].cash)
	s.phase = GameConst.PHASE_ACTIONS
	check(s.check_pipeline(a, ap, bp) == "", "4+ wells: first pipeline allowed")
	s.apply({"type": "pipeline", "player": a, "from": ap, "to": bp})
	check(s.royalty_for(s.pipelines[0]) == 3 * 1000, "1 pipeline: $1,000 per derrick on the target (3 derricks)")
	s.apply({"type": "pipeline", "player": a, "from": ap, "to": bp})
	check(s.royalty_for(s.pipelines[0]) == 3 * 3000, "2 pipelines: $3,000 per derrick")
	s.apply({"type": "pipeline", "player": a, "from": ap, "to": bp})
	check(s.royalty_for(s.pipelines[0]) == 3 * 5000, "3 pipelines: $5,000 per derrick")
	check(s.check_pipeline(a, ap, bp) != "", "at most 3 pipelines out of one property")
	s.site_state[s.board.plots[bp].sites[3]] = GameConst.SITE_OIL
	s.site_state[s.board.plots[bp].sites[4]] = GameConst.SITE_OIL
	s.site_state[s.board.plots[bp].sites[5]] = GameConst.SITE_OIL
	s.current = b
	check(s.check_pipeline(b, bp, ap).contains("already runs"), "can't pipe straight back into the source")
	# Fire on the source drops pipelines it can no longer support (6 wells -> 5 supports 2).
	s.current = a
	s.phase = GameConst.PHASE_FIRE
	s.fire_left = 1
	s.apply({"type": "cap", "player": a, "site": s.board.plots[ap].sites[0]})
	check(s.pipelines_from(ap) == 2, "fire removes a pipeline the wells no longer support")

	# Must drill at least one well; final scoring counts wells and pipelines.
	s.phase = GameConst.PHASE_ACTIONS
	s.card = {"kind": Deck.KIND_PRODUCTION}
	s.drills_left = 2
	s.drilled_this_turn = 0
	check(s.check_action(a, {"type": "end_turn"}) != "", "can't end the turn without drilling")
	var worth := s.net_worth(a)
	var expect: int = s.players[a].cash + 2 * 25000
	for plot in s.plots_of(a):
		expect += int(s.board.plots[plot].price) + s.producing_wells_on(plot) * 4000
	check(worth == expect, "net worth = cash + land + $4k/well + $25k/pipeline")

	# No empty holes: $10,000 penalty.
	var t := drafted(original_settings(91))
	var q := t.current
	for plot in t.plots_of(q):
		for sid in t.board.plots[plot].sites:
			t.site_state[sid] = GameConst.SITE_DRY
	t.phase = GameConst.PHASE_ACTIONS
	t.card = {"kind": Deck.KIND_PRODUCTION}
	t.drills_left = 1
	var before: int = t.players[q].cash
	t.apply({"type": "end_turn", "player": q})
	check(int(t.players[q].cash) == before - 10000, "no place to drill: $10,000 penalty")

	# The fine stops at $0 too: it never bankrupts.
	t = drafted(original_settings(92))
	q = t.current
	for plot in t.plots_of(q):
		for sid in t.board.plots[plot].sites:
			t.site_state[sid] = GameConst.SITE_DRY
	t.bank += int(t.players[q].cash) - 3000
	t.players[q].cash = 3000
	t.phase = GameConst.PHASE_ACTIONS
	t.card = {"kind": Deck.KIND_PRODUCTION}
	t.drills_left = 1
	t.apply({"type": "end_turn", "player": q})
	check(int(t.players[q].cash) == 0 and not t.players[q].bankrupt, "penalty with $3,000 on hand: down to $0, still in")

	# Running dry while drilling: pay what you have, drop to $0, stay in the game.
	var r := drafted(original_settings(55))
	var dd := r.current
	var mm := r.total_money()
	r.bank += int(r.players[dd].cash) - 1000
	r.players[dd].cash = 1000 # any hole costs at least $2,000
	r.phase = GameConst.PHASE_ACTIONS
	r.card = {"kind": Deck.KIND_PRODUCTION}
	r.drills_left = 2
	r.drilled_this_turn = 0
	r.apply({"type": "drill", "player": dd, "site": r.open_sites_of(dd)[0]})
	check(not r.players[dd].bankrupt and int(r.players[dd].cash) == 0 and r.phase == GameConst.PHASE_ACTIONS,
		"short on a hole: pay what you have, stay in at $0")
	check(r.total_money() == mm, "short drill conserves money")
	check(r.check_action(dd, {"type": "drill", "site": r.open_sites_of(dd)[0]}) != "", "at $0 you can't drill")
	r.drilled_this_turn = 0
	check(r.check_action(dd, {"type": "end_turn"}) == "", "at $0 you aren't forced to drill")
	r.apply({"type": "end_turn", "player": dd})
	check(not r.players[dd].bankrupt and int(r.players[dd].cash) == 0, "no penalty while broke with empty holes")

	# Only a pipeline royalty you can't pay bankrupts you (at the start of your turn): land to auction.
	var u := drafted(original_settings(55))
	var d := u.current
	var money := u.total_money()
	var dplot: int = u.plots_of(d)[0]
	var cplot: int = u.board.adjacency[dplot][0]
	for nb in u.board.adjacency[dplot]:
		if u.plot_owner[nb] == -1:
			cplot = nb
			break
	var cred := (d + 1) % 4
	u.plot_owner[cplot] = cred
	u.site_state[u.board.plots[dplot].sites[0]] = GameConst.SITE_OIL
	u.pipelines.append({"id": 0, "owner": cred, "from": cplot, "to": dplot, "level": 1})
	u.bank += int(u.players[d].cash)
	u.players[d].cash = 0
	u.apply({"type": "draw", "player": d})
	if true:
		check(u.players[d].bankrupt and u.phase == GameConst.PHASE_AUCTION, "can't pay a royalty: bankrupt, land to auction")
		var lot: int = u.auction.plots[0]
		var bidders := u.auction_bidders_left()
		check(bidders.size() == 3, "the three others bid")
		u.apply({"type": "bid", "player": bidders[0], "amount": 9000})
		u.apply({"type": "bid", "player": bidders[1], "amount": 4000})
		check(u.check_action(bidders[2], {"type": "bid", "amount": 750}) != "", "bids go in $500 steps")
		var cash_before: int = u.players[bidders[0]].cash
		u.apply({"type": "bid", "player": bidders[2], "amount": 0})
		check(u.plot_owner[lot] == bidders[0], "highest bidder gets the property")
		check(int(u.players[bidders[0]].cash) == cash_before - 4500, "pays $500 over the next bid")
		check(u.phase != GameConst.PHASE_AUCTION and u.current != d, "auction over, play moves on")
		check(u.total_money() == money, "auction conserves money")


func test_original_games() -> void:
	print("\nSimulated Classic (original rules) games, 4 AI players:")
	var turns: Array[int] = []
	var reasons := {}
	var auctions := 0
	for g in 10:
		var s := GameState.new_match(original_settings(500 + g * 31))
		var start_money := s.total_money()
		var rng := RandomNumberGenerator.new()
		rng.seed = g
		var guard := 0
		while s.phase != GameConst.PHASE_GAME_OVER and guard < 40000:
			guard += 1
			var a := AIPlayer.choose_action(s, AIPlayer.actor(s), rng)
			var r := s.apply(a)
			if not r.ok:
				check(false, "AI chose illegal action %s: %s" % [a, r.error])
				break
			for ev in r.events:
				if ev.type == "auction_lot":
					auctions += 1
		check(s.phase == GameConst.PHASE_GAME_OVER, "classic game %d ends" % g)
		check(s.total_money() == start_money, "classic game %d conserves money" % g)
		turns.append(s.turn_number)
		reasons[s.end_reason] = reasons.get(s.end_reason, 0) + 1
	turns.sort()
	print("  original 4p: median %4d turns (min %d, max %d)  %s  auction lots: %d" % [turns[turns.size() / 2], turns[0], turns[-1], reasons, auctions])


## Map editor boards: a board saved as data/boards/<id>.board.json is what matches load.
func test_edited_boards() -> void:
	var gen := BoardMap.create_procedural(321, 4)
	var copy := BoardMap.from_cells(gen.map_type, gen.map_seed, gen.width, gen.height, gen.cells,
		_site_cells_of(gen), gen.to_custom().names, gen.to_custom().labels)
	check(copy.plots.size() == gen.plots.size() and copy.sites.size() == gen.sites.size(), "edited board keeps plots and sites")
	var same_adj := true
	for i in gen.plots.size():
		var a: Array = gen.adjacency[i].duplicate()
		var b: Array = copy.adjacency[i].duplicate()
		a.sort()
		b.sort()
		same_adj = same_adj and a == b and int(gen.plots[i].price) == int(copy.plots[i].price)
	check(same_adj, "edited board keeps adjacency and prices")
	# Move one site and save under a test id; a match on that board id loads the edit.
	var sites := _site_cells_of(gen)
	var moved := sites[0]
	sites.remove_at(0)
	var edited := BoardMap.from_cells(gen.map_type, gen.map_seed, gen.width, gen.height, gen.cells, sites)
	check(edited.check_playable(4) == "", "edited board is playable")
	check(BoardMap.save_custom("zz_test", edited), "edited board saves")
	var st := make_settings(4)
	st["board_id"] = "zz_test"
	var s := GameState.new_match(st)
	check(s.board.sites.size() == gen.sites.size() - 1 and s.board.site_at(moved.x, moved.y) < 0, "match loads the edited board")
	var p0: int = gen.sites[0].plot
	check(int(s.board.plots[p0].price) == int(gen.plots[p0].price) - 1000, "price follows the drill sites")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BoardMap.custom_path("zz_test")))
	check(BoardMap.create("procedural", 321, 4, "zz_test").sites.size() == gen.sites.size(), "no edited board: generated one")
	# A property with no drill sites is not playable.
	var bare: Array[Vector2i] = []
	var empty := BoardMap.from_cells(gen.map_type, 0, gen.width, gen.height, gen.cells, bare)
	check(empty.check_playable(2) != "", "board without drill sites is rejected")


func _site_cells_of(b: BoardMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in b.sites:
		out.append(Vector2i(int(s.x), int(s.y)))
	return out


## Campaign levels: same board every attempt (board_seed), but fresh oil and deck (seed).
func test_board_seed() -> void:
	var a_cfg := make_settings(3, "classic", "procedural", 11)
	a_cfg["board_seed"] = 202
	var b_cfg := make_settings(3, "classic", "procedural", 99)
	b_cfg["board_seed"] = 202
	var a := GameState.new_match(a_cfg)
	var b := GameState.new_match(b_cfg)
	var same_board := a.board.plots.size() == b.board.plots.size() and a.board.sites.size() == b.board.sites.size()
	for i in mini(a.board.plots.size(), b.board.plots.size()):
		if a.board.plots[i].sites != b.board.plots[i].sites:
			same_board = false
	check(same_board, "same board_seed: same board")
	var oil_differs := false
	for site in a.board.sites:
		if a.oil.depth_at(site.x, site.y) != b.oil.depth_at(site.x, site.y):
			oil_differs = true
	check(oil_differs, "different match seed: different oil")
	check(a.draw_pile != b.draw_pile, "different match seed: different deck order")
	var plain := GameState.new_match(make_settings(3, "classic", "procedural", 202))
	check(plain.board.sites.size() == a.board.sites.size(), "board_seed defaults to the match seed")


func test_homestead() -> void:
	var s := GameState.new_match(make_settings(3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var picks := {}
	while s.phase == GameConst.PHASE_DRAFT:
		var who := s.current
		var a := AIPlayer.choose_action(s, who, rng)
		s.apply(a)
		picks[who] = int(a.plot)
	for p in 3:
		check(s.home_plot(p) == picks[p], "house goes on the plot bought in the draft")
	# Play on and check the land list matches ownership every step.
	var ok_list := true
	var ok_home := true
	for step in 400:
		if s.phase == GameConst.PHASE_GAME_OVER:
			break
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
		for p in 3:
			for plot in s.plots_of(p):
				if not (plot in s.players[p].land):
					ok_list = false
			var home := s.home_plot(p)
			if s.plots_of(p).is_empty():
				ok_home = ok_home and home == -1
			else:
				ok_home = ok_home and s.plot_owner[home] == p and home == _first_held(s, p)
	check(ok_list, "every owned plot is in its owner's land list")
	check(ok_home, "the house is on the first plot still held")
	var back := GameState.from_dict(s.to_dict())
	check(back.home_plot(0) == s.home_plot(0) and back.players[0].land == s.players[0].land, "land order survives a save")
	# Old saves without a land list fall back to the lowest-numbered plot.
	var old := {"name": "Old"}
	check(GameState.home_plot_of(old, 1, [-1, 0, 1, 1]) == 2, "old saves: house on the lowest plot")

	# Buildings: one house per player, outbuildings on the rest, placed inside their plot.
	var homes := Homestead.buildings(s.players, Array(s.plot_owner))
	var houses := 0
	for plot in homes:
		if homes[plot] == "house":
			houses += 1
	var holders := 0
	for p in 3:
		if not s.plots_of(p).is_empty():
			holders += 1
	check(houses == holders, "one house per landholder")
	for mt in ["procedural", "classic_1974"]:
		var b := BoardMap.create(mt, 5, 4)
		var cell := float(BoardDecor.cell_size(b))
		var inside := true
		var clear := 0
		for plot in b.plots.size():
			for kind in Homestead.KINDS:
				var at := Homestead.spot(b, plot, kind, cell)
				var foot := Homestead.foot_rect(kind, at)
				var c := foot.get_center()
				if b.cell_plot(floori(c.x / cell), floori(c.y / cell)) != plot:
					inside = false
				if BoardDecor.sites_in(b, foot) == 0:
					clear += 1
		check(inside, "%s: every building stands on its own plot" % mt)
		check(clear >= b.plots.size() * 2 * 0.9, "%s: buildings keep off drill holes (%d of %d clear)" % [mt, clear, b.plots.size() * 2])


func test_trading() -> void:
	var s := GameState.new_match(make_settings(3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	while s.phase == GameConst.PHASE_DRAFT:
		s.apply(AIPlayer.choose_action(s, s.current, rng))
	var p := s.current
	var q := (p + 1) % 3
	var r := (p + 2) % 3
	check(s.phase == GameConst.PHASE_CARD, "trading test starts before the draw")
	var money := s.total_money()
	var only_p: int = s.plots_of(p)[0]
	var only_q: int = s.plots_of(q)[0]
	check(s.check_action(p, {"type": "trade_offer", "to": q, "give_plots": [only_p]}) == "", "you may offer your last plot")
	check(s.check_action(p, {"type": "trade_offer", "to": q, "get_plots": [only_q], "give_cash": 1000}) == "",
		"you may ask for a player's last plot")
	check(not s.apply({"type": "trade_offer", "player": q, "to": p, "give_cash": 1000}).ok, "only the current player offers")
	check(not s.apply({"type": "trade_offer", "player": p, "to": p, "give_cash": 1000}).ok, "can't trade with yourself")
	check(not s.apply({"type": "trade_offer", "player": p, "to": q}).ok, "an empty offer is refused")
	check(not s.apply({"type": "trade_offer", "player": p, "to": q, "get_cash": int(s.players[q].cash) + 500}).ok,
		"can't ask for more cash than they have")
	check(not s.apply({"type": "trade_offer", "player": p, "to": q, "give_plots": [only_q, only_p]}).ok, "can't give a rival's land")

	# Give everyone a second plot.
	var spare: Array[int] = []
	for plot in s.plot_owner.size():
		if s.plot_owner[plot] == -1 and spare.size() < 4:
			spare.append(plot)
	for i in 3:
		var who: int = [p, q, r][i]
		s.plot_owner[spare[i]] = who
		s.players[who].land.append(spare[i])
	var free_plot := spare[3]

	# A plot plus cash for a plot.
	var cash_p: int = s.players[p].cash
	var cash_q: int = s.players[q].cash
	var res := s.apply({"type": "trade_offer", "player": p, "to": q, "give_cash": 2000, "give_plots": [spare[0]], "get_plots": [only_q]})
	check(res.ok and res.events[0].type == "trade_offered", "trade offered")
	check(not s.apply({"type": "draw", "player": p}).ok, "play waits on the answer")
	check(not s.apply({"type": "trade_reply", "player": r, "accept": true}).ok, "only the player offered can answer")
	var back := GameState.from_dict(s.to_dict())
	check(back.trade == s.trade, "a waiting offer survives a save")
	res = s.apply({"type": "trade_reply", "player": q, "accept": true})
	check(res.ok and res.events[0].type == "trade_done", "trade accepted")
	check(s.plot_owner[spare[0]] == q and s.plot_owner[only_q] == p, "plots change hands")
	check(int(s.players[p].cash) == cash_p - 2000 and int(s.players[q].cash) == cash_q + 2000, "cash changes hands")
	check(spare[0] in s.players[q].land and only_q in s.players[p].land, "traded land joins the land list")
	check(s.home_plot(q) == _first_held(s, q) and s.home_plot(q) == spare[1], "house moves to the next plot held")
	check(s.trade.is_empty() and s.total_money() == money, "trade settles and keeps the money supply")

	# Declined and withdrawn offers change nothing.
	var owners := s.plot_owner.duplicate()
	res = s.apply({"type": "trade_offer", "player": p, "to": r, "get_cash": 500})
	check(res.ok, "second offer")
	res = s.apply({"type": "trade_reply", "player": r, "accept": false})
	check(res.ok and res.events[0].type == "trade_declined" and s.plot_owner == owners, "declined trade changes nothing")
	res = s.apply({"type": "trade_offer", "player": p, "to": r, "get_cash": 500})
	check(res.ok, "third offer")
	check(not s.apply({"type": "trade_cancel", "player": r}).ok, "only the proposer withdraws")
	check(s.apply({"type": "trade_cancel", "player": p}).ok and s.trade.is_empty(), "offer withdrawn")
	check(s.apply({"type": "trade_offer", "player": p, "to": r, "get_cash": 500}).ok, "no limit on offers a turn")
	s.apply({"type": "trade_cancel", "player": p})
	s.trade_offers = 0

	# Selling the right to buy land: only with land for sale, after drawing.
	check(not s.apply({"type": "trade_offer", "player": p, "to": r, "land_right": true, "get_cash": 1000}).ok,
		"no land right to sell before drawing")
	s.phase = GameConst.PHASE_ACTIONS
	s.can_buy = true
	var price: int = s.board.plots[free_plot].price
	var cash_r: int = s.players[r].cash
	var bank := s.bank
	res = s.apply({"type": "trade_offer", "player": p, "to": r, "land_right": true, "get_cash": 1000})
	check(res.ok, "land right offered")
	res = s.apply({"type": "trade_reply", "player": r, "accept": true})
	check(res.ok and s.right_holder == r and not s.can_buy, "the land right moves to the buyer")
	check(res.events.any(func(e): return e.type == "land_right" and e.player == r), "land right event")
	check(not s.apply({"type": "end_turn", "player": p}).ok, "play waits for the land pick")
	check(not s.apply({"type": "buy", "player": p, "plot": free_plot}).ok, "the seller can't buy any more")
	check(GameState.from_dict(s.to_dict()).right_holder == r, "a waiting land pick survives a save")
	res = s.apply({"type": "buy", "player": r, "plot": free_plot})
	check(res.ok and s.plot_owner[free_plot] == r and s.right_holder == -1, "buyer picks the land they want")
	check(int(s.players[r].cash) == cash_r - 1000 - price and s.bank == bank + price, "buyer pays the bank the land price")
	check(not s.apply({"type": "buy", "player": r, "plot": free_plot}).ok, "one plot per right")
	check(s.total_money() == money, "land right sale keeps the money supply")
	# Or they pass and buy nothing.
	s.can_buy = true
	s.apply({"type": "trade_offer", "player": p, "to": q, "land_right": true})
	s.apply({"type": "trade_reply", "player": q, "accept": true})
	var owned_before := s.plots_of(q).size()
	res = s.apply({"type": "pass_land", "player": q})
	check(res.ok and s.right_holder == -1 and s.plots_of(q).size() == owned_before, "the land right can be passed up")
	check(s.check_action(p, {"type": "end_turn"}) == "", "play goes on after the pick")
	s.trade_offers = 0

	# Pipelines go with the land they start on; one that ends up inside one owner's land is torn out.
	var into_q := {"id": 90, "owner": r, "from": spare[2], "to": spare[0], "level": 1}
	var into_r := {"id": 91, "owner": q, "from": spare[1], "to": spare[2], "level": 1}
	s.pipelines.append(into_q)
	s.pipelines.append(into_r)
	s.trade_offers = 0
	s.current = q
	res = s.apply({"type": "trade_offer", "player": q, "to": r, "give_plots": [spare[1]], "get_cash": 500})
	res = s.apply({"type": "trade_reply", "player": r, "accept": true})
	check(res.ok and 91 in res.events[0].dropped, "pipeline between one owner's plots is torn out")
	check(s.pipeline_between(spare[2], spare[0]).get("owner", -1) == r, "other pipelines stay")
	s.current = p

	# AI answers: a gift is taken, a robbery isn't.
	s.players[q].is_ai = true
	s.apply({"type": "trade_offer", "player": p, "to": q, "give_cash": 3000})
	check(AIPlayer.choose_action(s, q, rng).get("accept", false), "AI takes free money")
	s.apply({"type": "trade_cancel", "player": p})
	s.players[r].is_ai = true
	var r_plots := s.plots_of(r)
	check(s.apply({"type": "trade_offer", "player": p, "to": r, "get_plots": [r_plots[0]], "give_cash": 500}).ok, "lowball offer made")
	check(not AIPlayer.choose_action(s, r, rng).get("accept", true), "AI turns down a lowball offer")
	s.apply({"type": "trade_cancel", "player": p})

	# Trading away every plot puts you out of the game (and play moves on).
	var u := GameState.new_match(make_settings(3))
	while u.phase == GameConst.PHASE_DRAFT:
		u.apply(AIPlayer.choose_action(u, u.current, rng))
	var giver := u.current
	var taker := (giver + 1) % 3
	var all_mine := u.plots_of(giver)
	check(u.apply({"type": "trade_offer", "player": giver, "to": taker, "give_plots": all_mine}).ok, "offer of all your land")
	res = u.apply({"type": "trade_reply", "player": taker, "accept": true})
	var out_ev: Array = res.events.filter(func(e): return e.type == "bankrupt")
	check(res.ok and u.players[giver].bankrupt and not out_ev.is_empty() and out_ev[0].reason == "no_land",
		"giving away all your land puts you out")
	check(u.current != giver and u.plots_of(taker).size() == 1 + all_mine.size(), "play moves on and the land changed hands")


func _first_held(s: GameState, p: int) -> int:
	for plot in s.players[p].land:
		if s.plot_owner[plot] == p:
			return plot
	return -1


func test_serialization() -> void:
	var s := GameState.new_match(make_settings(4, "online", "classic"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		if s.phase == GameConst.PHASE_GAME_OVER:
			break
		s.apply(AIPlayer.choose_action(s, AIPlayer.actor(s), rng))
	var copy := GameState.from_dict(s.to_dict(true))
	check(copy.to_dict(true).hash() == s.to_dict(true).hash(), "save/load round trip")
	var pub := s.to_dict(false)
	check(not pub.has("oil") and not pub.has("draw_pile"), "public snapshot hides oil and deck")
	# Determinism: same seed + same actions = same result.
	var a := GameState.new_match(make_settings(3, "blitz", "procedural", 42))
	var b := GameState.new_match(make_settings(3, "blitz", "procedural", 42))
	var ra := RandomNumberGenerator.new()
	ra.seed = 3
	var rb := RandomNumberGenerator.new()
	rb.seed = 3
	for i in 60:
		if a.phase == GameConst.PHASE_GAME_OVER:
			break
		a.apply(AIPlayer.choose_action(a, AIPlayer.actor(a), ra))
		b.apply(AIPlayer.choose_action(b, AIPlayer.actor(b), rb))
	check(a.to_dict().hash() == b.to_dict().hash(), "games are deterministic")


func test_full_games() -> void:
	print("\nSimulated AI games (turns until the game ends):")
	for speed_id in MatchSpeed.SPEED_IDS:
		for n in [2, 4, 6]:
			var turns: Array[int] = []
			var reasons := {}
			var offers := 0
			var deals := 0
			for g in 12:
				var s := GameState.new_match(make_settings(n, speed_id, "procedural", 1000 + g * 17 + n))
				var start_money := s.total_money()
				var rng := RandomNumberGenerator.new()
				rng.seed = g
				var guard := 0
				while s.phase != GameConst.PHASE_GAME_OVER and guard < 20000:
					guard += 1
					var a := AIPlayer.choose_action(s, AIPlayer.actor(s), rng)
					var r := s.apply(a)
					if not r.ok:
						check(false, "AI chose illegal action %s: %s" % [a, r.error])
						s.apply({"type": "end_turn", "player": s.current})
					for ev in r.events:
						if ev.type == "trade_offered":
							offers += 1
						elif ev.type == "trade_done":
							deals += 1
				check(s.phase == GameConst.PHASE_GAME_OVER, "%s %dp game %d ends" % [speed_id, n, g])
				check(s.total_money() == start_money, "%s %dp game %d conserves money" % [speed_id, n, g])
				for p in s.players:
					check(int(p.cash) >= 0, "no negative cash")
				turns.append(s.turn_number)
				reasons[s.end_reason] = reasons.get(s.end_reason, 0) + 1
			turns.sort()
			print("  %-7s %dp: median %4d turns (min %d, max %d)  %s  trades %d/%d offers" % [speed_id, n, turns[turns.size() / 2], turns[0], turns[-1], reasons, deals, offers])
