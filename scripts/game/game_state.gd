class_name GameState
extends RefCounted
## The full rules engine. Pure data + logic: no nodes, no scenes, deterministic from its seed.
##
## Drive it with apply(action). Each call returns {ok, error, events}. The presentation layer
## plays the events through its animation queue. Online, only the host owns a GameState with
## secrets; clients get to_dict(false) snapshots plus the event lists.
##
## Actions:
##   {type:"buy", plot}        draft pick, or buy land when the card allows it
##   {type:"draw"}             start of turn: pay pipeline royalties, draw and resolve a card
##   {type:"drill", site}      drill one site on your own land
##   {type:"pipeline", from, to}  build (or upgrade) a pipeline into a rival's adjacent plot
##   {type:"cap", site}        after a Blowout Fire: pick one of your producing wells to cap
##   {type:"bid", amount}      original rules: max bid on the property being auctioned (0 = pass);
##                             every remaining player bids, not just the current one
##   {type:"end_turn"}
##   {type:"trade_offer", to, give_cash, give_plots, land_right, get_cash, get_plots}
##                             current player only, before or after drawing: offer `to` cash and
##                             plots (with their wells and pipelines) for their cash and plots.
##                             land_right = true sells this turn's right to buy land: on accept,
##                             `to` picks any plot for sale (or none) with buy / pass_land. Any plots
##                             may go, even all of a player's land (a player left with none is out).
##   {type:"trade_reply", accept}  the player offered the trade answers it
##   {type:"trade_cancel"}     the proposer withdraws an unanswered offer
##   {type:"buy", plot} / {type:"pass_land"}  the player who got a land right in a trade buys
##                             one plot for sale, or passes; play waits until they do
##
## settings.rules = "original" switches to the 1974 board-game rules (Classic mode): royalties per
## derrick on the target property ($1k/$3k/$5k), $25k pipelines needing 4/5/6 wells on the source,
## must drill at least one well a turn, bankruptcy auctions, wells and pipelines in final scoring.

var settings: Dictionary = {}
var speed: Dictionary = {}
var board: BoardMap
var oil: OilField # null on clients (hidden)
var rng := RandomNumberGenerator.new()

var players: Array = []
var plot_owner: Array[int] = []
var site_state: Array[int] = []
var site_depth: Array[int] = []
var pipelines: Array = []
var bank: int = 0
var draw_pile: Array = []
var discard: Array = []

var phase: String = GameConst.PHASE_DRAFT
var current: int = 0
var turn_number: int = 0
var round_number: int = 1
var round_cap: int = 0
var first_player: int = 0
var draft_order: Array[int] = []
var draft_index: int = 0
var card: Dictionary = {}
var drills_left: int = 0
## Wells the current player still has to cap after a Blowout Fire.
var fire_left: int = 0
var can_buy: bool = false
var winner: int = -1
var end_reason: String = ""
## Wells drilled so far this turn (original rules: at least one is required).
var drilled_this_turn: int = 0
## Original rules: {seller, plots: [], index, bids: {"player": amount}} while the bank auctions land.
var auction: Dictionary = {}
## The trade offer waiting for an answer ({} = none): {from, to, give_cash, give_plots, land_right,
## get_cash, get_plots}. Play waits until it's answered or withdrawn.
var trade: Dictionary = {}
## Player who got this turn's right to buy land in a trade and still has to pick a plot or pass
## (-1 = none). Play waits for them.
var right_holder: int = -1
## Offers the current player has made this turn (no limit; the AI uses it to offer once a turn).
var trade_offers: int = 0

const DEFAULT_MODS: Dictionary = {
	"yield": 1.0, "drill_discount": 0.0, "royalty": 1.0, "fire_resist": 0.0, "start_bonus": 0,
}


# --- Setup ----------------------------------------------------------------------

## settings = {
##   seed: int (0 = random; drives oil, deck, draft order), board_seed: int (optional: the board
##   layout's seed, so a campaign level keeps its board while oil and cards change every match),
##   map_type: "procedural"|"classic", speed: MatchSpeed or dict,
##   players: [{name, is_ai, ai_level, character: {}, mods: {}, net_id}], campaign: bool
## }
static func new_match(match_settings: Dictionary) -> GameState:
	var s := GameState.new()
	s.settings = match_settings.duplicate(true)
	var sp = match_settings.get("speed", "classic")
	if sp is MatchSpeed:
		s.speed = sp.to_dict()
	elif sp is String:
		s.speed = MatchSpeed.load_by_id(sp).to_dict()
	else:
		s.speed = sp.duplicate()
	s.settings.erase("speed")
	s.settings["speed_id"] = s.speed.id
	var seed_value: int = match_settings.get("seed", 0)
	if seed_value == 0:
		seed_value = randi()
		s.settings["seed"] = seed_value
	s.rng.seed = seed_value

	var player_cfgs: Array = match_settings.players
	assert(player_cfgs.size() >= 2 and player_cfgs.size() <= GameConst.MAX_PLAYERS)
	var board_seed: int = int(match_settings.get("board_seed", seed_value))
	s.board = BoardMap.create(match_settings.get("map_type", "procedural"), board_seed, player_cfgs.size(),
		str(match_settings.get("board_id", "")))
	s.oil = OilField.create(s.board, s.rng)
	s.bank = s.speed.bank_size
	for i in player_cfgs.size():
		var cfg: Dictionary = player_cfgs[i]
		var mods := DEFAULT_MODS.duplicate()
		mods.merge(cfg.get("mods", {}), true)
		var start_cash: int = s.speed.starting_cash + int(mods.start_bonus)
		s.bank -= start_cash
		s.players.append({
			"index": i,
			"name": cfg.get("name", "Player %d" % (i + 1)),
			"color": cfg.get("color", i),
			"is_ai": cfg.get("is_ai", false),
			"ai_level": cfg.get("ai_level", GameConst.AI_MEDIUM),
			"character": cfg.get("character", {}).duplicate(true),
			"net_id": cfg.get("net_id", 1),
			"cash": start_cash,
			"bankrupt": false,
			"owed": 0, # money the bank couldn't pay (counted in final scoring)
			"land": [], # plots in the order this player got them (the first one still held has the house)
			"mods": mods,
		})
	for p in s.board.plots:
		s.plot_owner.append(-1)
	for site in s.board.sites:
		s.site_state.append(GameConst.SITE_OPEN)
		s.site_depth.append(GameConst.DEPTH_DRY)
	s.draw_pile = Deck.build(s.settings.get("rules", "") == "original")
	_shuffle(s.draw_pile, s.rng)
	s.round_cap = 0
	if int(s.speed.target_turns) > 0:
		s.round_cap = ceili(float(s.speed.target_turns) / player_cfgs.size())
	for i in player_cfgs.size():
		s.draft_order.append(i)
	_shuffle(s.draft_order, s.rng)
	s.phase = GameConst.PHASE_DRAFT
	s.draft_index = 0
	s.current = s.draft_order[0]
	return s


# --- Queries --------------------------------------------------------------------

func original_rules() -> bool:
	return settings.get("rules", "") == "original"


## Wells a Blowout Fire caps. 1 per 5 wells owned, rounded up; the original card stops at 3
## (1-5 wells: 1, 6-10: 2, 11 or more: 3).
func fire_cap_count(wells: int) -> int:
	var n := ceili(wells / 5.0)
	return mini(n, 3) if original_rules() else n


func player_count() -> int:
	return players.size()


func active_players() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not p.bankrupt:
			out.append(p.index)
	return out


func plots_of(p: int) -> Array[int]:
	var out: Array[int] = []
	for i in plot_owner.size():
		if plot_owner[i] == p:
			out.append(i)
	return out


func producing_wells_on(plot: int) -> int:
	var n := 0
	for sid in board.plots[plot].sites:
		if site_state[sid] == GameConst.SITE_OIL:
			n += 1
	return n


func producing_wells_of(p: int) -> int:
	var n := 0
	for plot in plots_of(p):
		n += producing_wells_on(plot)
	return n


func open_sites_of(p: int) -> Array[int]:
	var out: Array[int] = []
	for plot in plots_of(p):
		for sid in board.plots[plot].sites:
			if site_state[sid] == GameConst.SITE_OPEN:
				out.append(sid)
	return out


func drill_cost(p: int, depth: int) -> int:
	var base: int = GameConst.DRY_HOLE_COST if depth < 0 else GameConst.BASE_DRILL_COST[depth]
	var mods: Dictionary = players[p].mods
	var v := base * float(speed.drill_cost_mult) * (1.0 - float(mods.drill_discount))
	return maxi(100, roundi(v / 100.0) * 100)


## Most a drill could cost this player (players must be able to cover a dry hole).
func max_drill_cost(p: int) -> int:
	return drill_cost(p, GameConst.DEPTH_DRY)


## Cash a player needs on hand before drilling. Original rules: any cash at all (a player short of
## $6,000 may still take a chance; if the hole costs more, they pay what they have and drop to $0).
## Running dry never bankrupts you: only a pipeline royalty you can't pay does, at the start of
## your turn.
func drill_cash_needed(p: int) -> int:
	return 1 if original_rules() else max_drill_cost(p)


## The property a plot's pipeline runs into (-1 = none). Each property pipes into one at most.
func piped_into(plot: int) -> int:
	for pl in pipelines:
		if pl.from == plot:
			return int(pl.to)
	return -1


## Total pipelines (all levels) running out of a plot.
func pipelines_from(plot: int) -> int:
	var n := 0
	for pl in pipelines:
		if pl.from == plot:
			n += int(pl.level)
	return n


## Original rules: a player must drill at least one well each turn (unless a fire was drawn).
func must_drill(p: int) -> bool:
	return original_rules() and phase == GameConst.PHASE_ACTIONS and drilled_this_turn == 0 \
		and card.get("kind", "") != Deck.KIND_FIRE and drills_left > 0 and not open_sites_of(p).is_empty() \
		and int(players[p].cash) > 0 # broke players can't drill, so they aren't forced to


func pipeline_between(from_plot: int, to_plot: int) -> Dictionary:
	for pl in pipelines:
		if pl.from == from_plot and pl.to == to_plot:
			return pl
	return {}


func pipeline_cost() -> int:
	return int(speed.pipeline_cost)


## Returns "" if allowed, otherwise the reason. A pipeline needs 4 derricks (producing wells) on
## the source property; level 2 needs 5 and level 3 needs 6. Each property pipes into one
## neighboring rival property only, and never back into a property that already pipes into it
## (in both modes).
func check_pipeline(p: int, from_plot: int, to_plot: int) -> String:
	if from_plot < 0 or from_plot >= plot_owner.size() or to_plot < 0 or to_plot >= plot_owner.size():
		return "No such plot"
	if plot_owner[from_plot] != p:
		return "You must own the source plot"
	var target_owner := plot_owner[to_plot]
	if target_owner < 0 or target_owner == p or players[target_owner].bankrupt:
		return "Pipelines must run into a rival's land"
	if not board.are_adjacent(from_plot, to_plot):
		return "Plots must be next to each other"
	var existing := pipeline_between(from_plot, to_plot)
	var next_level: int = 1 if existing.is_empty() else int(existing.level) + 1
	# A property pipes into one property only; more pipe = a higher level on that same line.
	var other_target := piped_into(from_plot)
	if other_target >= 0 and other_target != to_plot:
		return "%s already pipes into %s (one pipeline per property)" % [board.plots[from_plot].name, board.plots[other_target].name]
	# No piping straight back: if the target already pipes into this property, it can't go both ways.
	var back := pipeline_between(to_plot, from_plot)
	if not back.is_empty():
		return "%s already runs a pipeline into %s" % [players[back.owner].name, board.plots[from_plot].name]
	var need: int
	if original_rules():
		# 4 wells for the first pipeline out of a property, 5 for the second, 6 for the third.
		var out_n := pipelines_from(from_plot)
		if out_n >= GameConst.ORIG_PIPELINE_MAX_FROM_PLOT:
			return "A property can feed at most 3 pipelines"
		need = 4 + out_n
	else:
		if next_level > GameConst.PIPELINE_MAX_LEVEL:
			return "Pipeline is at max level"
		need = GameConst.PIPELINE_WELLS_REQUIRED[next_level - 1]
	if producing_wells_on(from_plot) < need:
		return "Needs %d derricks on %s" % [need, board.plots[from_plot].name]
	if players[p].cash < pipeline_cost():
		return "Not enough cash"
	return ""


func royalty_for(pl: Dictionary) -> int:
	if original_rules():
		# Paid per derrick on the TARGET property: $1k/$3k/$5k for 1/2/3 pipelines from one
		# owner into it. The whole amount is charged on that owner's first pipeline into the plot.
		var n := 0
		for other in pipelines:
			if other.to == pl.to and other.owner == pl.owner:
				if int(other.id) < int(pl.id):
					return 0
				n += int(other.level)
		if n <= 0:
			return 0
		return GameConst.ORIG_ROYALTY_PER_DERRICK[mini(n, 3) - 1] * producing_wells_on(pl.to)
	var owner_mods: Dictionary = players[pl.owner].mods
	# Paid per derrick on the property piped INTO: level multiplier (1x/3x/5x) x rate x its
	# producing wells.
	var mult: int = GameConst.PIPELINE_LEVEL_MULT[clampi(int(pl.level), 1, GameConst.PIPELINE_LEVEL_MULT.size()) - 1]
	var v := mult * int(speed.royalty_per_well) * producing_wells_on(pl.to) * float(owner_mods.royalty)
	return roundi(v / 100.0) * 100


func net_worth(p: int) -> int:
	var w: int = players[p].cash
	if original_rules():
		# Cash + property prices + producing wells at $4,000 + pipelines at $25,000 + money
		# the bank owed but couldn't pay.
		w += int(players[p].get("owed", 0))
		for plot in plots_of(p):
			w += int(board.plots[plot].price) + producing_wells_on(plot) * GameConst.ORIG_WELL_VALUE
		for pl in pipelines:
			if pl.owner == p:
				w += int(pl.level) * pipeline_cost()
		return w
	for plot in plots_of(p):
		w += int(board.plots[plot].price)
	for pl in pipelines:
		if pl.owner == p:
			w += int(pl.level) * pipeline_cost()
	return w


func total_money() -> int:
	var t := bank
	for p in players:
		t += int(p.cash)
	return t


# --- Legality -------------------------------------------------------------------

func check_action(p: int, action: Dictionary) -> String:
	if phase == GameConst.PHASE_GAME_OVER:
		return "The game is over"
	if action.get("type", "") == "bid":
		return _check_bid(p, int(action.get("amount", 0)))
	if phase == GameConst.PHASE_AUCTION:
		return "Wait for the auction to finish"
	if action.get("type", "") == "trade_reply":
		if trade.is_empty():
			return "No trade offer to answer"
		return "" if p == int(trade.to) else "That offer isn't for you"
	if right_holder >= 0:
		if p != right_holder:
			return "Waiting for %s to pick land" % players[right_holder].name
		match action.get("type", ""):
			"pass_land":
				return ""
			"buy":
				var rp: int = action.get("plot", -1)
				if rp < 0 or rp >= plot_owner.size() or plot_owner[rp] != -1:
					return "That land isn't for sale"
				if int(players[p].cash) < int(board.plots[rp].price):
					return "Not enough cash"
				return ""
		return "Pick land to buy, or pass"
	if p != current:
		return "Not your turn"
	if not trade.is_empty():
		if action.get("type", "") == "trade_cancel":
			return ""
		return "Waiting for %s to answer your trade offer" % players[int(trade.to)].name
	match action.get("type", ""):
		"trade_offer":
			return check_trade(p, make_offer(p, action))
		"trade_cancel":
			return "No trade offer to withdraw"
		"buy":
			var plot: int = action.get("plot", -1)
			if plot < 0 or plot >= plot_owner.size():
				return "No such plot"
			if plot_owner[plot] != -1:
				return "That land is already owned"
			if phase == GameConst.PHASE_DRAFT:
				return "" if players[p].cash >= int(board.plots[plot].price) else "Not enough cash"
			if phase != GameConst.PHASE_ACTIONS or not can_buy:
				return "No land for sale this turn"
			if players[p].cash < int(board.plots[plot].price):
				return "Not enough cash"
			return ""
		"draw":
			return "" if phase == GameConst.PHASE_CARD else "You already drew a card"
		"drill":
			if phase != GameConst.PHASE_ACTIONS:
				return "Draw a card first" if phase == GameConst.PHASE_CARD else "Can't drill now"
			if drills_left <= 0:
				return "No drills left this turn"
			var sid: int = action.get("site", -1)
			if sid < 0 or sid >= site_state.size():
				return "No such site"
			if plot_owner[board.sites[sid].plot] != p:
				return "You can only drill your own land"
			if site_state[sid] != GameConst.SITE_OPEN:
				return "That site was already drilled"
			if players[p].cash < drill_cash_needed(p):
				if original_rules():
					return "You're out of cash: no drilling until you earn more"
				return "Need $%d on hand to drill" % drill_cash_needed(p)
			return ""
		"pipeline":
			if phase != GameConst.PHASE_ACTIONS:
				return "Can't build now"
			return check_pipeline(p, action.get("from", -1), action.get("to", -1))
		"cap":
			if phase != GameConst.PHASE_FIRE:
				return "No fire to deal with"
			var csid: int = action.get("site", -1)
			if csid < 0 or csid >= site_state.size():
				return "No such site"
			if plot_owner[board.sites[csid].plot] != p or site_state[csid] != GameConst.SITE_OIL:
				return "Pick one of your producing wells"
			return ""
		"end_turn":
			if phase == GameConst.PHASE_ACTIONS:
				return "You must drill at least one well this turn" if must_drill(p) else ""
			if phase == GameConst.PHASE_FIRE:
				return "Pick %d more well%s to cap first" % [fire_left, "" if fire_left == 1 else "s"]
			return "Draw a card first"
	return "Unknown action"


# --- Actions --------------------------------------------------------------------

func apply(action: Dictionary) -> Dictionary:
	var p: int = action.get("player", current)
	var err := check_action(p, action)
	if err != "":
		return {"ok": false, "error": err, "events": []}
	var events: Array = []
	match action.type:
		"buy":
			if right_holder >= 0:
				_do_right_buy(p, int(action.plot), events)
			else:
				_do_buy(p, action.plot, events)
		"pass_land":
			right_holder = -1
			events.append({"type": "land_passed", "player": p})
		"draw":
			_do_draw(p, events)
		"drill":
			_do_drill(p, action.site, events)
		"pipeline":
			_do_pipeline(p, action.from, action.to, events)
		"cap":
			_do_cap(p, action.site, events)
		"bid":
			_do_bid(p, int(action.get("amount", 0)), events)
		"end_turn":
			_end_turn(events)
		"trade_offer":
			trade = make_offer(p, action)
			trade_offers += 1
			events.append({"type": "trade_offered", "trade": trade.duplicate(true)})
		"trade_reply":
			_do_trade_reply(bool(action.get("accept", false)), events)
		"trade_cancel":
			events.append({"type": "trade_cancelled", "trade": trade.duplicate(true)})
			trade = {}
	_check_game_over(events)
	return {"ok": true, "error": "", "events": events}


## Records that player p got this plot (for the homestead: house on the first, outbuildings after).
func _add_land(p: int, plot: int) -> void:
	if not players[p].has("land"):
		players[p]["land"] = []
	players[p].land.erase(plot) # got back later: it counts from now
	players[p].land.append(plot)


## The plot with player p's house: the first plot they got that they still own (-1 = none).
func home_plot(p: int) -> int:
	return home_plot_of(players[p], p, plot_owner)


## Same, from plain data (the board view keeps its own copies of players and owners).
## Saves from before the land list existed fall back to the player's lowest-numbered plot.
static func home_plot_of(player: Dictionary, p: int, owners: Array) -> int:
	for plot in player.get("land", []):
		if int(plot) < owners.size() and owners[int(plot)] == p:
			return int(plot)
	for i in owners.size():
		if owners[i] == p:
			return i
	return -1


func _do_buy(p: int, plot: int, events: Array) -> void:
	var price: int = board.plots[plot].price
	_pay_bank(p, price)
	plot_owner[plot] = p
	_add_land(p, plot)
	events.append({"type": "plot_bought", "player": p, "plot": plot, "price": price, "draft": phase == GameConst.PHASE_DRAFT})
	if phase == GameConst.PHASE_DRAFT:
		draft_index += 1
		if draft_index < draft_order.size():
			current = draft_order[draft_index]
			events.append({"type": "draft_next", "player": current})
		else:
			# Whoever bought the most expensive starting land goes first.
			var best := draft_order[0]
			var best_price := -1
			for i in draft_order:
				var owned := plots_of(i)
				var pr: int = board.plots[owned[0]].price if owned.size() > 0 else 0
				if pr > best_price:
					best_price = pr
					best = i
			first_player = best
			current = best
			_begin_turn(events)
	else:
		can_buy = false


# --- Trading --------------------------------------------------------------------

## A clean offer from player p's trade_offer action (ints, no duplicate plots).
func make_offer(p: int, action: Dictionary) -> Dictionary:
	return {
		"from": p, "to": int(action.get("to", -1)),
		"give_cash": int(action.get("give_cash", 0)), "give_plots": _plot_list(action.get("give_plots", [])),
		"land_right": bool(action.get("land_right", false)),
		"get_cash": int(action.get("get_cash", 0)), "get_plots": _plot_list(action.get("get_plots", [])),
	}


static func _plot_list(v) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if not int(x) in out:
				out.append(int(x))
	return out


## Returns "" if player p may offer this trade (from make_offer), otherwise the reason. Also
## re-checked when the trade is accepted.
func check_trade(p: int, t: Dictionary) -> String:
	if phase != GameConst.PHASE_CARD and phase != GameConst.PHASE_ACTIONS:
		return "You can't trade right now"
	var q: int = t.to
	if q < 0 or q >= players.size() or q == p:
		return "Pick another player to trade with"
	if players[q].bankrupt:
		return "%s is out of the game" % players[q].name
	if t.give_cash < 0 or t.get_cash < 0:
		return "Cash can't be negative"
	if t.give_cash == 0 and t.get_cash == 0 and t.give_plots.is_empty() and t.get_plots.is_empty() and not t.land_right:
		return "Put something in the deal"
	for plot in t.give_plots:
		if plot < 0 or plot >= plot_owner.size() or plot_owner[plot] != p:
			return "You can only trade away your own land"
	for plot in t.get_plots:
		if plot < 0 or plot >= plot_owner.size() or plot_owner[plot] != q:
			return "You can only ask for %s's land" % players[q].name
	if t.land_right and (phase != GameConst.PHASE_ACTIONS or not can_buy):
		return "You have no land for sale to offer"
	if t.give_cash > int(players[p].cash):
		return "You don't have %s" % _money(t.give_cash)
	# The other side pays you and the bank out of what they have plus what you hand over.
	if t.get_cash > int(players[q].cash) + t.give_cash:
		return "%s doesn't have %s" % [players[q].name, _money(t.get_cash)]
	return ""


static func _money(v: int) -> String:
	return "$%d,%03d" % [v / 1000, v % 1000] if v >= 1000 else "$%d" % v


func _do_trade_reply(accept: bool, events: Array) -> void:
	var t := trade
	trade = {}
	if not accept:
		events.append({"type": "trade_declined", "trade": t})
		return
	var err := check_trade(int(t.from), t)
	if err != "":
		events.append({"type": "trade_declined", "trade": t, "reason": err})
		return
	var p: int = t.from
	var q: int = t.to
	players[p].cash += int(t.get_cash) - int(t.give_cash)
	players[q].cash += int(t.give_cash) - int(t.get_cash)
	for plot in t.give_plots:
		_move_plot(plot, q)
	for plot in t.get_plots:
		_move_plot(plot, p)
	if bool(t.get("land_right", false)):
		# The right moves on: q picks a plot (or passes) before play goes on.
		can_buy = false
		right_holder = q
	# Pipelines that now run between one owner's own plots are torn out.
	var dropped: Array = []
	for pl in pipelines:
		if plot_owner[pl.to] == pl.owner:
			dropped.append(int(pl.id))
	pipelines = pipelines.filter(func(pl): return plot_owner[pl.to] != pl.owner)
	events.append({"type": "trade_done", "trade": t, "dropped": dropped})
	if right_holder >= 0:
		events.append({"type": "land_right", "player": right_holder})


## The player who got the land right in a trade buys one plot for sale.
func _do_right_buy(p: int, plot: int, events: Array) -> void:
	var price: int = board.plots[plot].price
	_pay_bank(p, price)
	plot_owner[plot] = p
	_add_land(p, plot)
	right_holder = -1
	events.append({"type": "plot_bought", "player": p, "plot": plot, "price": price, "draft": false})


## Hands a plot (its wells and the pipelines running out of it) to player q.
func _move_plot(plot: int, q: int) -> void:
	plot_owner[plot] = q
	_add_land(q, plot)
	for pl in pipelines:
		if pl.from == plot:
			pl.owner = q # royalties from this land now go to the new owner


func _begin_turn(events: Array) -> void:
	phase = GameConst.PHASE_CARD
	turn_number += 1
	card = {}
	drills_left = 0
	drilled_this_turn = 0
	can_buy = false
	trade = {}
	trade_offers = 0
	right_holder = -1
	events.append({"type": "turn_start", "player": current, "turn": turn_number, "round": round_number})


func _do_draw(p: int, events: Array) -> void:
	# 1. Pipeline royalties owed on this player's land.
	for pl in pipelines.duplicate():
		if players[p].bankrupt:
			break
		if plot_owner[pl.to] != p or pl.owner == p:
			continue
		var amount := royalty_for(pl)
		if amount <= 0:
			continue
		var paid := mini(amount, int(players[p].cash))
		players[p].cash -= paid
		players[pl.owner].cash += paid
		events.append({"type": "royalty_paid", "player": p, "to": pl.owner, "amount": paid, "pipeline": pl.id})
		if paid < amount:
			# Can't pay: bankrupt. House rules: the pipeline owner takes everything that's left.
			# Original rules: the bank auctions the land.
			_go_bankrupt(p, pl.owner, events)
	if players[p].bankrupt:
		if phase != GameConst.PHASE_AUCTION:
			_advance_turn(events)
		return

	# 2. Draw and resolve a card.
	if draw_pile.is_empty():
		draw_pile = discard
		discard = []
		_shuffle(draw_pile, rng)
		events.append({"type": "deck_shuffled"})
	card = draw_pile.pop_back()
	discard.append(card)
	events.append({"type": "card_drawn", "player": p, "card": card.duplicate()})
	var mods: Dictionary = players[p].mods
	match card.kind:
		Deck.KIND_PRODUCTION:
			var wells := producing_wells_of(p)
			var income := roundi(int(card.rate) * wells * float(speed.income_mult) * float(mods.yield) / 100.0) * 100
			var got := _pay_from_bank(p, income)
			events.append({"type": "income", "player": p, "amount": got, "wells": wells, "rate": card.rate})
			drills_left = int(card.wells) + int(speed.bonus_drills)
			can_buy = bool(card.land)
		Deck.KIND_DEPLETION:
			var got := _pay_from_bank(p, Deck.DEPLETION_BONUS)
			events.append({"type": "income", "player": p, "amount": got, "wells": 0, "rate": 0})
			drills_left = 1
			can_buy = false
		Deck.KIND_FIRE:
			# 1 well per 5 owned (rounded up). The player chooses which ones with "cap" actions.
			drills_left = 0
			can_buy = false
			fire_left = fire_cap_count(producing_wells_of(p))
			events.append({"type": "fire", "player": p, "count": fire_left})
			if fire_left > 0:
				phase = GameConst.PHASE_FIRE
				return
	phase = GameConst.PHASE_ACTIONS


func _do_cap(p: int, sid: int, events: Array) -> void:
	# Fire Crews (campaign upgrade) can save the chosen well; it still counts as dealt with.
	var saved := rng.randf() < float(players[p].mods.fire_resist)
	if not saved:
		site_state[sid] = GameConst.SITE_BURNED
	fire_left -= 1
	events.append({"type": "well_capped", "player": p, "site": sid, "saved": saved, "left": fire_left})
	if original_rules():
		_trim_pipelines(board.sites[sid].plot, events)
	if fire_left <= 0 or producing_wells_of(p) == 0:
		fire_left = 0
		phase = GameConst.PHASE_ACTIONS


func _do_drill(p: int, sid: int, events: Array) -> void:
	var site: Dictionary = board.sites[sid]
	var depth := oil.depth_at(site.x, site.y)
	var cost := drill_cost(p, depth)
	# Original rules: short of the full cost, you pay what you have and drop to $0 (still in the game).
	var short := maxi(0, cost - int(players[p].cash))
	cost -= short
	_pay_bank(p, cost)
	drills_left -= 1
	drilled_this_turn += 1
	site_depth[sid] = depth
	site_state[sid] = GameConst.SITE_OIL if depth >= 0 else GameConst.SITE_DRY
	events.append({"type": "drill", "player": p, "site": sid, "plot": site.plot, "depth": depth, "oil": depth >= 0,
		"cost": cost, "short": short})


func _do_pipeline(p: int, from_plot: int, to_plot: int, events: Array) -> void:
	_pay_bank(p, pipeline_cost())
	var existing := pipeline_between(from_plot, to_plot)
	if existing.is_empty():
		existing = {"id": _next_pipeline_id(), "owner": p, "from": from_plot, "to": to_plot, "level": 1}
		pipelines.append(existing)
	else:
		existing.level += 1
	events.append({"type": "pipeline", "player": p, "pipeline": existing.id, "from": from_plot, "to": to_plot,
		"level": existing.level, "cost": pipeline_cost()})


func _end_turn(events: Array) -> void:
	var p := current
	# Original rules: had to drill but no empty holes anywhere: $10,000 penalty to the bank. Like
	# drilling, it takes what you have and stops at $0; it never bankrupts you.
	if original_rules() and drilled_this_turn == 0 and card.get("kind", "") != Deck.KIND_FIRE and drills_left > 0 \
			and open_sites_of(p).is_empty():
		var fine := mini(GameConst.ORIG_NO_SITE_PENALTY, int(players[p].cash))
		_pay_bank(p, fine)
		events.append({"type": "penalty", "player": p, "amount": fine, "reason": "No empty holes to drill"})
	events.append({"type": "turn_end", "player": p})
	_advance_turn(events)


func _advance_turn(events: Array) -> void:
	if active_players().size() <= 1:
		return
	var n := players.size()
	var nxt := current
	for i in n:
		nxt = (nxt + 1) % n
		# A round ends each time play passes the first player's seat (even if they're out).
		if nxt == first_player:
			round_number += 1
		if not players[nxt].bankrupt:
			break
	current = nxt
	_begin_turn(events)


## Original rules: if a fire leaves a property with too few wells for its pipelines (4/5/6),
## pipelines from it are removed, newest first.
func _trim_pipelines(plot: int, events: Array) -> void:
	var wells := producing_wells_on(plot)
	var allowed := clampi(wells - 3, 0, GameConst.ORIG_PIPELINE_MAX_FROM_PLOT)
	while pipelines_from(plot) > allowed:
		var newest := {}
		for pl in pipelines:
			if pl.from == plot and (newest.is_empty() or int(pl.id) > int(newest.id)):
				newest = pl
		newest.level -= 1
		if int(newest.level) <= 0:
			pipelines.erase(newest)
		events.append({"type": "pipeline_removed", "pipeline": newest.id, "level": newest.level,
			"from": newest.from, "to": newest.to, "player": newest.owner})


## Can't pay: house rules hand everything to the creditor; original rules go to auction.
func _go_bankrupt(p: int, creditor: int, events: Array) -> void:
	if original_rules():
		_bankrupt_to_auction(p, creditor, events)
	else:
		_bankrupt(p, creditor, events)


## Original rules: the player is out. The bank auctions each property (with its wells and
## pipelines) to the highest bidder in $500 steps; unsold land is closed for the game.
func _bankrupt_to_auction(p: int, creditor: int, events: Array) -> void:
	var cash: int = players[p].cash
	players[p].bankrupt = true
	players[p].cash = 0
	bank += cash
	var lots := plots_of(p)
	events.append({"type": "bankrupt", "player": p, "creditor": creditor, "plots": lots,
		"cash": 0, "pipelines": 0, "reason": "auction"})
	# Pipelines the bankrupt player ran into other people's land stay with that land's source
	# plot (they're sold with it); pipelines into the bankrupt player's land stay too.
	if active_players().size() <= 1 or lots.is_empty():
		_close_lots(lots, events)
		return
	auction = {"seller": p, "plots": lots, "index": 0, "bids": {}}
	phase = GameConst.PHASE_AUCTION
	events.append({"type": "auction_lot", "plot": lots[0], "index": 0, "total": lots.size()})


func _close_lots(lots: Array, events: Array) -> void:
	for plot in lots:
		plot_owner[plot] = GameConst.PLOT_CLOSED
		pipelines = pipelines.filter(func(pl): return pl.from != plot and pl.to != plot)
		events.append({"type": "auction_closed", "plot": plot})


## Players who still have to bid on the current lot.
func auction_bidders_left() -> Array[int]:
	var out: Array[int] = []
	if phase != GameConst.PHASE_AUCTION:
		return out
	for i in active_players():
		if not auction.bids.has(str(i)):
			out.append(i)
	return out


func _check_bid(p: int, amount: int) -> String:
	if phase != GameConst.PHASE_AUCTION:
		return "No auction right now"
	if p < 0 or p >= players.size() or players[p].bankrupt:
		return "You're out of the game"
	if auction.bids.has(str(p)):
		return "You already bid on this property"
	if amount < 0 or amount % GameConst.ORIG_BID_STEP != 0:
		return "Bids go up in $500 steps"
	if amount > int(players[p].cash):
		return "Not enough cash"
	return ""


## Sealed maximum bids, settled like an open auction: the highest bidder wins and pays $500 over
## the next-highest bid (or their own bid, if lower). Ties go to the earliest seat after the seller.
func _do_bid(p: int, amount: int, events: Array) -> void:
	auction.bids[str(p)] = amount
	events.append({"type": "bid_placed", "player": p})
	if not auction_bidders_left().is_empty():
		return
	var plot: int = auction.plots[auction.index]
	var n := players.size()
	var best := -1
	var best_bid := 0
	var second := 0
	for k in range(1, n + 1):
		var i := (int(auction.seller) + k) % n
		if not auction.bids.has(str(i)):
			continue
		var b: int = auction.bids[str(i)]
		if b > best_bid:
			second = best_bid
			best_bid = b
			best = i
		elif b > second:
			second = b
	if best < 0:
		_close_lots([plot], events)
	else:
		var price := mini(best_bid, maxi(GameConst.ORIG_BID_STEP, second + GameConst.ORIG_BID_STEP))
		_pay_bank(best, price)
		plot_owner[plot] = best
		_add_land(best, plot)
		for pl in pipelines:
			if pl.from == plot:
				pl.owner = best # royalties from this land now go to the new owner
		pipelines = pipelines.filter(func(pl): return plot_owner[pl.to] != pl.owner)
		events.append({"type": "auction_won", "plot": plot, "player": best, "price": price,
			"bids": auction.bids.duplicate()})
	auction.index += 1
	auction.bids = {}
	if auction.index < auction.plots.size():
		events.append({"type": "auction_lot", "plot": auction.plots[auction.index], "index": auction.index, "total": auction.plots.size()})
		return
	# Auction over: play moves on from the bankrupt player.
	auction = {}
	phase = GameConst.PHASE_ACTIONS
	events.append({"type": "auction_over"})
	_advance_turn(events)


## Eliminates player p. A creditor (the player they couldn't pay) takes ALL of p's assets:
## remaining cash, every plot with its wells, and p's pipelines. With no creditor
## (creditor = -1), the land goes back on the market and the cash goes to the bank.
func _bankrupt(p: int, creditor: int, events: Array, reason: String = "debt") -> void:
	var cash: int = players[p].cash
	players[p].bankrupt = true
	players[p].cash = 0
	if creditor >= 0:
		players[creditor].cash += cash
	else:
		bank += cash
	var taken: Array[int] = []
	for plot in plots_of(p):
		plot_owner[plot] = creditor
		if creditor >= 0:
			_add_land(creditor, plot)
		taken.append(plot)
	var pipes := 0
	for pl in pipelines:
		if pl.owner == p:
			pl.owner = creditor
			pipes += 1
	# Drop pipelines that now run between one owner's own plots, or that nobody owns.
	pipelines = pipelines.filter(func(pl): return pl.owner >= 0 and plot_owner[pl.to] >= 0 and plot_owner[pl.to] != pl.owner)
	events.append({"type": "bankrupt", "player": p, "creditor": creditor, "plots": taken,
		"cash": cash, "pipelines": pipes, "reason": reason})


## A player with no land left is out of the game.
func _eliminate_landless(events: Array) -> void:
	for pl in players:
		if not pl.bankrupt and plots_of(pl.index).is_empty():
			_bankrupt(pl.index, -1, events, "no_land")
			if pl.index == current and active_players().size() > 1:
				_advance_turn(events)


func _check_game_over(events: Array) -> void:
	if phase == GameConst.PHASE_GAME_OVER or phase == GameConst.PHASE_DRAFT:
		return
	if phase == GameConst.PHASE_AUCTION:
		if _campaign_player_out():
			auction = {}
			_finish(_richest(), "player_out", events)
		return
	_eliminate_landless(events)
	var act := active_players()
	if _campaign_player_out():
		# Campaign: once you're out, the match is over (no watching the rivals play on).
		_finish(_richest(), "player_out", events)
	elif act.size() == 1:
		_finish(act[0], "last_standing", events)
	elif bank <= 0:
		_finish(_richest(), "bank_empty", events)
	elif round_cap > 0 and round_number > round_cap:
		_finish(_richest(), "round_cap", events)


## Campaign only: every human player is out of the game.
func _campaign_player_out() -> bool:
	if not settings.get("campaign", false):
		return false
	var humans := 0
	for pl in players:
		if not pl.is_ai:
			humans += 1
			if not pl.bankrupt:
				return false
	return humans > 0


func _richest() -> int:
	var best := -1
	var best_w := -1
	for p in active_players():
		var w := net_worth(p)
		if w > best_w:
			best_w = w
			best = p
	return best


func _finish(w: int, reason: String, events: Array) -> void:
	phase = GameConst.PHASE_GAME_OVER
	winner = w
	end_reason = reason
	var worths: Array = []
	for p in players:
		worths.append(net_worth(p.index))
	events.append({"type": "game_over", "winner": w, "reason": reason, "net_worths": worths})


# --- Money ----------------------------------------------------------------------

func _pay_bank(p: int, amount: int) -> void:
	players[p].cash -= amount
	bank += amount


## Bank pays out what it can. When it runs dry the game ends.
func _pay_from_bank(p: int, amount: int) -> int:
	var paid := mini(amount, bank)
	bank -= paid
	players[p].cash += paid
	if paid < amount:
		players[p].owed = int(players[p].get("owed", 0)) + amount - paid
	return paid


func _next_pipeline_id() -> int:
	var m := -1
	for pl in pipelines:
		m = maxi(m, int(pl.id))
	return m + 1


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- Serialization --------------------------------------------------------------

## include_secret=false strips the hidden oil and the deck order (for online clients).
func to_dict(include_secret: bool = true) -> Dictionary:
	var d := {
		"settings": settings.duplicate(true), "speed": speed.duplicate(), "board": board.to_dict(),
		"players": players.duplicate(true), "plot_owner": plot_owner.duplicate(),
		"site_state": site_state.duplicate(), "site_depth": site_depth.duplicate(),
		"pipelines": pipelines.duplicate(true), "bank": bank, "discard": discard.duplicate(true),
		"draw_count": draw_pile.size(), "phase": phase, "current": current, "turn_number": turn_number,
		"round_number": round_number, "round_cap": round_cap, "first_player": first_player,
		"draft_order": draft_order.duplicate(), "draft_index": draft_index, "card": card.duplicate(true),
		"drills_left": drills_left, "fire_left": fire_left, "can_buy": can_buy, "winner": winner, "end_reason": end_reason,
		"drilled_this_turn": drilled_this_turn, "auction": auction.duplicate(true),
		"trade": trade.duplicate(true), "trade_offers": trade_offers, "right_holder": right_holder,
	}
	if include_secret:
		d["oil"] = oil.to_dict()
		d["draw_pile"] = draw_pile.duplicate(true)
		d["rng_seed"] = rng.seed
		d["rng_state"] = rng.state
	return d


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.settings = d.settings.duplicate(true)
	s.speed = d.speed.duplicate()
	s.board = BoardMap.from_dict(d.board)
	s.players = d.players.duplicate(true)
	s.plot_owner.assign(d.plot_owner)
	s.site_state.assign(d.site_state)
	s.site_depth.assign(d.site_depth)
	s.pipelines = d.pipelines.duplicate(true)
	s.bank = d.bank
	s.discard = d.discard.duplicate(true)
	s.phase = d.phase
	s.current = d.current
	s.turn_number = d.turn_number
	s.round_number = d.round_number
	s.round_cap = d.round_cap
	s.first_player = d.first_player
	s.draft_order.assign(d.draft_order)
	s.draft_index = d.draft_index
	s.card = d.card.duplicate(true)
	s.drills_left = d.drills_left
	s.fire_left = d.get("fire_left", 0)
	s.drilled_this_turn = d.get("drilled_this_turn", 0)
	s.auction = d.get("auction", {}).duplicate(true)
	s.trade = d.get("trade", {}).duplicate(true)
	s.trade_offers = int(d.get("trade_offers", 0))
	s.right_holder = int(d.get("right_holder", -1))
	s.can_buy = d.can_buy
	s.winner = d.winner
	s.end_reason = d.end_reason
	if d.has("oil"):
		s.oil = OilField.from_dict(d.oil)
		s.draw_pile = d.draw_pile.duplicate(true)
		s.rng.seed = d.rng_seed
		s.rng.state = d.rng_state
	else:
		# Client copy: keep the pile size so the UI can show it.
		for i in int(d.get("draw_count", 0)):
			s.draw_pile.append({})
	return s
