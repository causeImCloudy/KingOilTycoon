class_name AIPlayer
extends RefCounted
## Rule-based opponents. choose_action() looks only at public state (never the hidden oil),
## so the same AI could run on a client.
##
## Easy: random-ish, spends freely. Medium: sensible reserves. Hard: drills near known oil,
## builds pipelines aggressively, and keeps a cash cushion for royalties.

const RESERVE: Array[int] = [3000, 8000, 14000]


## Who has to act next: an auction bidder, the player answering a trade offer, or the current
## player.
static func actor(s: GameState) -> int:
	if s.phase == GameConst.PHASE_AUCTION and not s.auction_bidders_left().is_empty():
		return s.auction_bidders_left()[0]
	if not s.trade.is_empty():
		return int(s.trade.to)
	if s.right_holder >= 0:
		return s.right_holder
	return s.current


static func choose_action(s: GameState, p: int, rng: RandomNumberGenerator) -> Dictionary:
	var level: int = s.players[p].ai_level
	if s.phase == GameConst.PHASE_AUCTION:
		return {"type": "bid", "player": p, "amount": auction_bid(s, p, level, rng)}
	if not s.trade.is_empty():
		if int(s.trade.to) == p:
			return {"type": "trade_reply", "player": p, "accept": trade_reply(s, p, level, rng)}
		return {} # waiting on someone else's answer
	if s.right_holder >= 0:
		if s.right_holder != p:
			return {}
		# Got the land right in a trade: buy the best plot we can afford with a cushion, or pass.
		var pick := _pick_land(s, p, level, rng, false)
		if pick >= 0 and int(s.players[p].cash) >= int(s.board.plots[pick].price) + RESERVE[level] / 2:
			return {"type": "buy", "player": p, "plot": pick}
		return {"type": "pass_land", "player": p}
	match s.phase:
		GameConst.PHASE_DRAFT:
			return {"type": "buy", "player": p, "plot": _pick_land(s, p, level, rng, true)}
		GameConst.PHASE_CARD:
			return {"type": "draw", "player": p}
		GameConst.PHASE_FIRE:
			return {"type": "cap", "player": p, "site": pick_well_to_cap(s, p, level, rng)}
		GameConst.PHASE_ACTIONS:
			# Can't-pay-means-bankrupt: keep enough cash for the royalties owed next turn
			# (easy keeps 1 turn's worth, medium 2, hard 3) on top of a flat cushion.
			var reserve: int = RESERVE[level] + _royalty_exposure(s, p) * (level + 1)
			# Pipelines first (they pay every turn).
			if level >= GameConst.AI_MEDIUM or rng.randf() < 0.3:
				var pl := _best_pipeline(s, p, reserve)
				if not pl.is_empty():
					return pl
			# Original rules: at least one well every turn, money or not.
			if s.must_drill(p):
				var forced := _pick_site(s, p, level, rng)
				if forced >= 0:
					return {"type": "drill", "player": p, "site": forced}
			# Drill.
			if s.drills_left > 0 and s.players[p].cash >= s.max_drill_cost(p) + (reserve / 2):
				var sid := _pick_site(s, p, level, rng)
				if sid >= 0:
					return {"type": "drill", "player": p, "site": sid}
			# Buy land.
			if s.can_buy:
				var plot := _pick_land(s, p, level, rng, false)
				if plot >= 0 and s.players[p].cash >= int(s.board.plots[plot].price) + reserve:
					return {"type": "buy", "player": p, "plot": plot}
			# One trade offer a turn at most: sell land we won't buy, or bid for a neighbor's plot.
			if s.trade_offers == 0:
				var offer := trade_offer(s, p, level, rng, reserve)
				if not offer.is_empty():
					return offer
			return {"type": "end_turn", "player": p}
	return {}


static func _pick_land(s: GameState, p: int, level: int, rng: RandomNumberGenerator, draft: bool) -> int:
	var best := -1
	var best_score := -INF
	var mine := s.plots_of(p)
	for i in s.plot_owner.size():
		if s.plot_owner[i] != -1:
			continue
		var price: int = s.board.plots[i].price
		if price > int(s.players[p].cash):
			continue
		var score := float(s.board.plots[i].sites.size())
		if level == GameConst.AI_EASY:
			score += rng.randf_range(-4.0, 4.0)
		else:
			# Next to my land: pipeline-proof and pipeline-ready.
			for m in mine:
				if s.board.are_adjacent(i, m):
					score += 1.5
			# Next to rivals: pipeline targets (hard likes these).
			if level == GameConst.AI_HARD:
				for nb in s.board.adjacency[i]:
					if s.plot_owner[nb] >= 0 and s.plot_owner[nb] != p:
						score += 0.75
			score += rng.randf_range(-0.5, 0.5)
		if draft:
			score += price / 4000.0
		if score > best_score:
			best_score = score
			best = i
	return best


static func _pick_site(s: GameState, p: int, level: int, rng: RandomNumberGenerator) -> int:
	var open := s.open_sites_of(p)
	if open.is_empty():
		return -1
	if level == GameConst.AI_EASY:
		return open[rng.randi_range(0, open.size() - 1)]
	# Oil pools are clumpy: prefer sites near known strikes, away from dry holes.
	var best := open[0]
	var best_score := -INF
	for sid in open:
		var a: Dictionary = s.board.sites[sid]
		var score := rng.randf_range(0.0, 0.4)
		for j in s.board.sites.size():
			var st := s.site_state[j]
			if st == GameConst.SITE_OPEN:
				continue
			var b: Dictionary = s.board.sites[j]
			var d := absi(int(a.x) - int(b.x)) + absi(int(a.y) - int(b.y))
			if d > 4:
				continue
			var w := 1.0 / d
			if st == GameConst.SITE_OIL or st == GameConst.SITE_BURNED:
				score += w * (1.5 if level == GameConst.AI_HARD else 1.0)
			elif st == GameConst.SITE_DRY:
				score -= w
		# Hard also pushes plots toward the 4-well pipeline threshold.
		if level == GameConst.AI_HARD:
			var wells := s.producing_wells_on(a.plot)
			if wells >= 2 and wells < 4:
				score += 0.4
		if score > best_score:
			best_score = score
			best = sid
	return best


static func _best_pipeline(s: GameState, p: int, reserve: int) -> Dictionary:
	if int(s.players[p].cash) < s.pipeline_cost() + reserve:
		return {}
	var best := {}
	var best_val := 0
	for plot in s.plots_of(p):
		for nb in s.board.adjacency[plot]:
			if s.check_pipeline(p, plot, nb) != "":
				continue
			# Royalties are paid per derrick on the land piped into, so aim at the most derricks.
			var val := s.producing_wells_on(nb)
			if val > best_val:
				best_val = val
				best = {"type": "pipeline", "player": p, "from": plot, "to": nb}
	return best


## Picks which producing well to lose to a fire. Easy picks at random; medium and hard keep
## plots that feed pipelines (or are close to the pipeline threshold) intact.
static func pick_well_to_cap(s: GameState, p: int, level: int, rng: RandomNumberGenerator) -> int:
	var wells: Array[int] = []
	for plot in s.plots_of(p):
		for sid in s.board.plots[plot].sites:
			if s.site_state[sid] == GameConst.SITE_OIL:
				wells.append(sid)
	if wells.is_empty():
		return -1
	if level == GameConst.AI_EASY:
		return wells[rng.randi_range(0, wells.size() - 1)]
	var best := wells[0]
	var best_cost := INF
	for sid in wells:
		var plot: int = s.board.sites[sid].plot
		var n := s.producing_wells_on(plot)
		var cost := float(n)
		for pl in s.pipelines:
			if pl.from == plot and pl.owner == p and s.original_rules():
				cost += 10.0 # Classic: too few wells here and the pipeline is torn out
			elif pl.to == plot and pl.owner != p:
				cost -= 4.0 # a rival pipes in: royalties are paid per derrick here
		if n == 4 or n == 5 or n == 6:
			cost += 3.0 # would drop below a pipeline level threshold
		cost += rng.randf_range(0.0, 0.3)
		if cost < best_cost:
			best_cost = cost
			best = sid
	return best


## Original rules: the most this AI will pay for the property being auctioned. Values the land,
## its producing wells (they pay every production card) and its pipelines; keeps a cash cushion.
static func auction_bid(s: GameState, p: int, level: int, rng: RandomNumberGenerator) -> int:
	if s.auction.is_empty():
		return 0
	var plot: int = s.auction.plots[s.auction.index]
	var open := 0
	for sid in s.board.plots[plot].sites:
		if s.site_state[sid] == GameConst.SITE_OPEN:
			open += 1
	var value := open * 600 + s.producing_wells_on(plot) * 3500 + s.pipelines_from(plot) * 15000
	value = int(value * [0.6, 0.75, 0.9][level] * rng.randf_range(0.85, 1.15))
	var cushion: int = RESERVE[level] + _royalty_exposure(s, p) * 2 + 6000
	var most := int(s.players[p].cash) - cushion
	var bid := mini(value, most)
	bid = (bid / GameConst.ORIG_BID_STEP) * GameConst.ORIG_BID_STEP
	return maxi(0, bid)


## Royalties this player currently owes per turn.
static func _royalty_exposure(s: GameState, p: int) -> int:
	var total := 0
	for pl in s.pipelines:
		if s.plot_owner[pl.to] == p and pl.owner != p:
			total += s.royalty_for(pl)
	return total


# --- Trading ------------------------------------------------------------------------

## What a plot is worth to player p: its price, its producing wells (they pay every production
## card), room to drill, the pipelines running out of it, less the royalties paid on pipelines
## running into it. Land next to p's own counts a bit more (safe from p's pipelines, and ready
## to feed them).
static func plot_value(s: GameState, plot: int, p: int) -> float:
	var v := float(s.board.plots[plot].price)
	for sid in s.board.plots[plot].sites:
		var st := s.site_state[sid]
		if st == GameConst.SITE_OIL:
			v += 3500.0
		elif st == GameConst.SITE_OPEN:
			v += 600.0
	var owner := s.plot_owner[plot]
	for pl in s.pipelines:
		if pl.from == plot and pl.owner == owner:
			v += int(pl.level) * s.pipeline_cost() * 0.6
		elif pl.to == plot and pl.owner != p:
			v -= s.royalty_for(pl) * 3.0
	for nb in s.board.adjacency[plot]:
		if s.plot_owner[nb] == p:
			v *= 1.1
			break
	return maxf(v, 0.0)


## Whether AI player p takes the offer waiting for them. They add up what they'd get and give
## (cash 1:1, land by plot_value, a land right by what the land is worth over its price), keep
## a cash cushion for royalties, and want a margin that grows with their level.
static func trade_reply(s: GameState, p: int, level: int, rng: RandomNumberGenerator) -> bool:
	var t: Dictionary = s.trade
	if t.is_empty() or s.check_trade(int(t.from), t) != "":
		return false
	# Giving up every plot would put this AI out of the game.
	if t.get_plots.size() >= s.plots_of(p).size() and not bool(t.get("land_right", false)) and t.give_plots.is_empty():
		return false
	var get := float(t.give_cash)
	var give := float(t.get_cash)
	for plot in t.give_plots:
		get += plot_value(s, plot, p)
	for plot in t.get_plots:
		give += plot_value(s, plot, p) * 1.15 # land in hand is worth a bit more than land offered
	var cash_after := int(s.players[p].cash) + int(t.give_cash) - int(t.get_cash)
	if bool(t.get("land_right", false)):
		# Worth what the best plot we could then afford is worth over its price (we may pass).
		get += best_land_surplus(s, p, cash_after - RESERVE[level] / 2)
	if cash_after < RESERVE[level] + _royalty_exposure(s, p) * (level + 1) and cash_after < int(s.players[p].cash):
		return false
	var margin: float = [-0.05, 0.05, 0.12][level] * maxf(give, 1000.0)
	if level == GameConst.AI_EASY:
		margin += rng.randf_range(-1500.0, 1500.0)
	# Hard players don't help whoever is ahead without a better deal.
	if level == GameConst.AI_HARD and s.net_worth(int(t.from)) > s.net_worth(p):
		margin += 0.08 * maxf(give, 1000.0)
	return get - give >= margin


## A trade offer AI player p might make on its turn ({} = none):
## - land for sale it won't buy: sell the right to buy the best plot to whoever can afford it;
## - now and then (medium and hard, with cash to spare): offer cash for a rival's plot next to
##   its own land.
static func trade_offer(s: GameState, p: int, level: int, rng: RandomNumberGenerator, reserve: int) -> Dictionary:
	if s.phase != GameConst.PHASE_ACTIONS:
		return {}
	var others: Array[int] = []
	for q in s.active_players():
		if q != p:
			others.append(q)
	if others.is_empty():
		return {}
	if s.can_buy and rng.randf() < 0.7:
		var best := -1
		var best_v := 0.0
		for plot in s.plot_owner.size():
			if s.plot_owner[plot] != -1:
				continue
			var surplus := plot_value(s, plot, -1) - int(s.board.plots[plot].price)
			if surplus > best_v:
				best_v = surplus
				best = plot
		if best >= 0:
			var price: int = s.board.plots[best].price
			var ask := maxi(1000, roundi(best_v * 0.5 / 500.0) * 500)
			var buyer := -1
			for q in others:
				if int(s.players[q].cash) >= price + ask and (buyer < 0 or int(s.players[q].cash) > int(s.players[buyer].cash)):
					buyer = q
			if buyer >= 0:
				var a := {"type": "trade_offer", "player": p, "to": buyer, "land_right": true, "get_cash": ask}
				if s.check_action(p, a) == "":
					return a
	if level >= GameConst.AI_MEDIUM and rng.randf() < 0.15:
		var target := -1
		var target_v := 0.0
		for plot in s.plots_of(p):
			for nb in s.board.adjacency[plot]:
				var q := s.plot_owner[nb]
				if q < 0 or q == p or s.players[q].bankrupt or s.plots_of(q).size() < 2:
					continue
				var v := plot_value(s, nb, p)
				if v > target_v:
					target_v = v
					target = nb
		if target >= 0:
			var bid := roundi(target_v * 1.1 / 500.0) * 500
			if int(s.players[p].cash) - bid >= reserve + s.max_drill_cost(p):
				var a := {"type": "trade_offer", "player": p, "to": s.plot_owner[target], "give_cash": bid,
					"get_plots": [target]}
				if s.check_action(p, a) == "":
					return a
	return {}


## The most a land right is worth to player p with `budget` to spend: the best plot for sale's
## value over its price (0 if nothing worth buying fits the budget).
static func best_land_surplus(s: GameState, p: int, budget: int) -> float:
	var best := 0.0
	for plot in s.plot_owner.size():
		if s.plot_owner[plot] != -1:
			continue
		var price: int = s.board.plots[plot].price
		if price > budget:
			continue
		best = maxf(best, plot_value(s, plot, p) - price)
	return best
