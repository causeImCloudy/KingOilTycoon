class_name CampaignWar
extends RefCounted
## Campaign rules: the war for the county map. Pure data (headless-testable); saved in
## Profile.data.war. Companies: 0 = you, 1-5 = the rivals in RIVALS order. Each county is owned
## by a company or open (-1, drawn grey).
##
## You start on one county; each rival holds an HQ and the land around it. Fight a county next to
## yours: the match has 1-3 rivals (its owner, plus the rivals whose HQs are near it). Win and the
## county is yours, and the rivals you beat pay you: the owner its full value, the others a quarter
## (half each for an open county). Lose and you pay a fifth of your dollars to them. A rival with
## no dollars or no land left is out and their counties go open. Knock all five out to win.
## Dollars buy campaign upgrades (Upgrades.DEFS).

const RIVALS: Array[String] = ["hardpan", "dolores", "pickett", "ruby", "blackwood"]
## Base difficulty per rival (AI level 0-2); +1 fighting on or next to their HQ.
const TIER: Array[int] = [0, 0, 1, 1, 2]
## Each rival's starting dollars.
const PURSE: Array[int] = [200000, 240000, 280000, 330000, 400000]
const START_DOLLARS: int = 50000
## Counties each rival holds at the start, HQ included (one fewer if boxed in, like Hardpan).
const TERRITORY: int = 5
## Rivals whose HQ is this many counties away or closer join a battle (1-3 rivals in all).
const NEAR_HOPS: int = 2
const MAX_OPPONENTS: int = 3
const OWNER_SHARE: float = 1.0
const SIDE_SHARE: float = 0.25
const OPEN_SHARE: float = 0.5
const LOSS_SHARE: float = 0.2
const HQ_MIN_VALUE: int = 150000
## The campaign level (data/campaign.json "maps") each rival's HQ county plays, in RIVALS order.
const HQ_LEVELS: Array[int] = [1, 3, 8, 14, 19]

var map: CountyMap
## owner[county] = company, or -1 open.
var owner: Array[int] = []
var dollars: int = START_DOLLARS
## purse[r - 1] = rival r's dollars.
var purse: Array[int] = []
## out[r - 1] = rival r is knocked out.
var out: Array[bool] = []
var battles: int = 0
var wins: int = 0
## Fixed per map (rebuilt from the seed, not saved): county value, campaign level or -1.
var value: Array[int] = []
var level_of: Array[int] = []


## A fresh war. `levels` = the campaign.json maps (their rivals decide where each level sits).
static func create(levels: Array) -> CampaignWar:
	var w := CampaignWar.new()
	w._setup(levels)
	w.owner.resize(w.map.count())
	w.owner.fill(-1)
	w.owner[w.home(0)] = 0
	for r in RIVALS.size():
		w.purse.append(PURSE[r])
		w.out.append(false)
		w.owner[w.home(r + 1)] = r + 1
	# Rivals grow their land one county at a time in turn, nearest to their HQ first, leaving
	# your start and the counties around it open.
	var keep_open: Array = [w.home(0)] + w.map.neighbors[w.home(0)]
	for _step in TERRITORY - 1:
		for r in range(1, RIVALS.size() + 1):
			var best := -1
			for c in w.map.count():
				if w.owner[c] != -1 or c in keep_open or not w._touches(c, r):
					continue
				if best < 0 or w._hq_hops(r, c) < w._hq_hops(r, best):
					best = c
			if best >= 0:
				w.owner[best] = r
	return w


## Restores a saved war; a fresh one if the save is missing or made on another map.
static func from_dict(d: Dictionary, levels: Array) -> CampaignWar:
	var w := CampaignWar.new()
	w._setup(levels)
	if d.is_empty() or int(d.get("map_version", 0)) != CountyMap.MAP_VERSION \
			or (d.get("owner", []) as Array).size() != w.map.count():
		return create(levels)
	for o in d.owner:
		w.owner.append(int(o))
	for p in d.purse:
		w.purse.append(int(p))
	for o in d.out:
		w.out.append(bool(o))
	w.dollars = int(d.get("dollars", START_DOLLARS))
	w.battles = int(d.get("battles", 0))
	w.wins = int(d.get("wins", 0))
	return w


func to_dict() -> Dictionary:
	return {"map_version": CountyMap.MAP_VERSION, "owner": owner.duplicate(), "purse": purse.duplicate(),
		"out": out.duplicate(), "dollars": dollars, "battles": battles, "wins": wins}


func _setup(levels: Array) -> void:
	map = CountyMap.get_map()
	var n := map.count()
	var rng := RandomNumberGenerator.new()
	rng.seed = CountyMap.SEED + 7
	level_of.resize(n)
	level_of.fill(-1)
	# Each rival's HQ plays their big level; the first level sits next to your start; every other
	# level goes to the open spot nearest the HQ of the first rival it names.
	for r in RIVALS.size():
		if HQ_LEVELS[r] < levels.size():
			level_of[home(r + 1)] = HQ_LEVELS[r]
	var first := -1
	for c in map.neighbors[home(0)]:
		if first < 0 or _hq_hops(1, c) < _hq_hops(1, first) or (_hq_hops(1, c) == _hq_hops(1, first) and c < first):
			first = c
	if first >= 0 and levels.size() > 0:
		level_of[first] = 0
	for i in levels.size():
		if i in level_of:
			continue
		var named: Array = levels[i].get("rivals", [])
		var r: int = RIVALS.find(str(named[0])) + 1 if not named.is_empty() else 1
		r = maxi(r, 1)
		var best := -1
		for c in n:
			if level_of[c] != -1 or c == home(0):
				continue
			if best < 0 or _hq_hops(r, c) < _hq_hops(r, best) \
					or (_hq_hops(r, c) == _hq_hops(r, best) and map.hops[home(0)][c] < map.hops[home(0)][best]):
				best = c
		if best >= 0:
			level_of[best] = i
	value.resize(n)
	for c in n:
		var v := 40000 + 5000 * rng.randi_range(0, 8)
		if level_of[c] >= 0:
			v = maxi(v, int(levels[level_of[c]].get("reward", 40)) * 1000)
		value[c] = v
	for r in RIVALS.size():
		value[home(r + 1)] = maxi(value[home(r + 1)], HQ_MIN_VALUE)


# --- Queries -------------------------------------------------------------------------------------

func home(company: int) -> int:
	return map.homes[company]


func is_hq(c: int) -> int:
	for r in range(1, RIVALS.size() + 1):
		if home(r) == c:
			return r
	return 0


func alive(r: int) -> bool:
	return r >= 1 and r <= RIVALS.size() and not out[r - 1]


func alive_rivals() -> Array[int]:
	var list: Array[int] = []
	for r in range(1, RIVALS.size() + 1):
		if alive(r):
			list.append(r)
	return list


func finished() -> bool:
	return alive_rivals().is_empty()


func counties_of(company: int) -> Array[int]:
	var list: Array[int] = []
	for c in owner.size():
		if owner[c] == company:
			list.append(c)
	return list


## You can fight for a county that borders your land (while any rival is left).
func attackable(c: int) -> bool:
	if c < 0 or c >= owner.size() or owner[c] == 0 or finished():
		return false
	for nb in map.neighbors[c]:
		if owner[nb] == 0:
			return true
	return false


## The rivals you face in a county: its owner, then the nearest other HQs (1-3 rivals).
func opponents(c: int) -> Array[int]:
	var list: Array[int] = []
	if alive(owner[c]):
		list.append(owner[c])
	var others: Array[int] = []
	for r in alive_rivals():
		if r != owner[c]:
			others.append(r)
	others.sort_custom(func(a, b): return _hq_hops(a, c) < _hq_hops(b, c) or (_hq_hops(a, c) == _hq_hops(b, c) and a < b))
	var near := list.size()
	for r in others:
		if _hq_hops(r, c) <= NEAR_HOPS:
			near += 1
	var want := clampi(near, 1, MAX_OPPONENTS)
	for r in others:
		if list.size() >= want:
			break
		list.append(r)
	return list


## AI difficulty (0-2) of rival r in county c: their tier, +1 on or next to their HQ.
func ai_level(r: int, c: int) -> int:
	return clampi(TIER[r - 1] + (1 if _hq_hops(r, c) <= 1 else 0), 0, 2)


## What each rival pays you for winning county c: [{rival, amount}].
func win_payments(c: int) -> Array:
	var list: Array = []
	for r in opponents(c):
		var share := OWNER_SHARE if r == owner[c] else (OPEN_SHARE if owner[c] < 0 else SIDE_SHARE)
		list.append({"rival": r, "amount": mini(_round_k(value[c] * share), purse[r - 1])})
	return list


## What you pay the rivals for losing in county c: [{rival, amount}].
func loss_payments(c: int) -> Array:
	var opp := opponents(c)
	var list: Array = []
	var each := _round_k(dollars * LOSS_SHARE / maxf(1.0, opp.size()))
	for r in opp:
		list.append({"rival": r, "amount": each})
	return list


# --- Results -------------------------------------------------------------------------------------

## Applies a finished battle for county c. Returns {won, payments: [{rival, amount}],
## dollars: change for you, knocked_out: [rival], campaign_won}.
func resolve(c: int, won: bool) -> Dictionary:
	battles += 1
	var res := {"won": won, "payments": [], "dollars": 0, "knocked_out": [], "campaign_won": false}
	if won:
		wins += 1
		res.payments = win_payments(c)
		owner[c] = 0
		for p in res.payments:
			purse[int(p.rival) - 1] -= int(p.amount)
			dollars += int(p.amount)
			res.dollars += int(p.amount)
		for r in alive_rivals():
			if purse[r - 1] <= 0 or counties_of(r).is_empty():
				_knock_out(r)
				res.knocked_out.append(r)
		res.campaign_won = finished()
	else:
		res.payments = loss_payments(c)
		for p in res.payments:
			purse[int(p.rival) - 1] += int(p.amount)
			dollars -= int(p.amount)
			res.dollars -= int(p.amount)
	return res


func spend(amount: int) -> bool:
	if amount < 0 or amount > dollars:
		return false
	dollars -= amount
	return true


func _knock_out(r: int) -> void:
	out[r - 1] = true
	purse[r - 1] = 0
	for c in owner.size():
		if owner[c] == r:
			owner[c] = -1


func _hq_hops(r: int, c: int) -> int:
	return map.hops[home(r)][c]


func _touches(c: int, company: int) -> bool:
	for nb in map.neighbors[c]:
		if owner[nb] == company:
			return true
	return false


static func _round_k(v: float) -> int:
	return roundi(v / 1000.0) * 1000
