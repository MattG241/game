extends Node
## All persistent game state, the economy ledger and versioned save/load.

signal cash_changed(value: float)
signal message(text: String, kind: String)
signal upgrades_changed
signal upgrade_bought(id: String)
signal award_earned(id: String)
signal stock_changed
signal settings_changed
signal day_changed

const SAVE_VERSION := 1
const SAVE_PATH := "user://save.json"
const SAVE_TMP := "user://save.tmp"
const SAVE_BAK := "user://save.bak"
const SETTINGS_PATH := "user://settings.json"

var pub_name := "The Crooked Shamrock"
var mode := "career"
var cash := 0.0
var day := 1
var hour := 15.5
var phase := "prep"            # prep, open, last_orders, closing
var reputation := 20.0
var weather := "rain"
var upgrades: Dictionary = {}
var stock: Dictionary = {}     # drink id -> spare packs (kegs, cases...)
var tap_units: Dictionary = {} # drink id -> serves left in the connected keg
var keg_day: Dictionary = {}   # drink id -> day the keg was connected
var prices: Dictionary = {}
var relationships: Dictionary = {}
var staff: Array = []
var applicants: Array = []      # this week's job seekers who answered the card in the window
var applicants_week := -1
var progress: Dictionary = {}   # stories, beer lines, lock-ins: things the pub remembers between days
var bookings: Dictionary = {}  # "day" -> event id
var furniture_placed: Array = []
var objectives_done: Array = []
var deliveries: Array = []
var stats: Dictionary = {}
var today: Dictionary = {}
var history: Array = []
var best_split_mm := -1.0
var tutorial: Dictionary = {}
var in_game := false
var live_atmosphere := 0.0      # live music playing right now (not saved)
var live_stay := 0.0            # customers linger longer during a performance
var live_tips := 0.0            # and tip a little more

var settings: Dictionary = {
	"look_sensitivity": 1.0,
	"button_opacity": 0.85,
	"hud_scale": 1.0,
	"vibration": true,
	"vol_master": 0.9,
	"vol_music": 0.8,
	"vol_ambience": 0.6,
	"vol_weather": 0.45,
	"vol_speech": 1.0,
	"mix_version": 2,
	"vol_effects": 0.9,
	"graphics": "balanced",
	"render_scale": 1.0,
	"fps_limit": 60,
	"reduced_motion": false,
	"reduced_effects": false,
	"pour_assist": false,
	"show_guide": true,
	"colorblind": false,
	"day_length": 10,
	"show_fps": false,
	"subtitles": true,
	"voices": true,
	"high_contrast": false,
	"difficulty": "balanced",
	"music_mode": "auto",
	"music_playlist": "all",
	"music_manual_id": "",
	"invert_look": false,
}


func _ready() -> void:
	load_settings()
	_reset()


func _reset() -> void:
	pub_name = "The Crooked Shamrock"
	mode = "career"
	cash = float(GameData.econ("start_cash", 55))
	day = 1
	hour = 15.5
	phase = "prep"
	reputation = float(GameData.econ("reputation_start", 20))
	weather = "rain"
	upgrades = {}
	stock = {}
	tap_units = {}
	keg_day = {}
	prices = {}
	relationships = {}
	staff = []
	applicants = []
	applicants_week = -1
	progress = {"lines_cleaned_day": 1}
	bookings = {}
	furniture_placed = []
	objectives_done = []
	deliveries = []
	history = []
	best_split_mm = -1.0
	tutorial = {}
	stats = {
		"pints_poured": 0, "perfect_pints": 0, "served": 0, "walkouts": 0,
		"revenue": 0.0, "tips": 0.0, "best_pour": 0, "days": 0, "glasses_washed": 0,
		"spills_cleaned": 0, "darts_wins": 0, "darts_games": 0, "events_hosted": 0,
		"split_attempts": 0, "split_best_score": 0, "split_perfects": 0, "kegs_changed": 0, "own_pints": 0, "rhythm_best": 0,
		"food_served": 0, "quiz_nights": 0, "service_time_ema": 55.0, "service_samples": 0,
	}
	for d in GameData.drinks:
		var id: String = d["id"]
		prices[id] = float(d["price"])
		stock[id] = int(d.get("start_stock", 1))
		tap_units[id] = int(d["units_per_stock"])
		keg_day[id] = 1
	_reset_today()


func _reset_today() -> void:
	today = {
		"sales": 0.0, "tips": 0.0, "cogs": 0.0, "stock_spend": 0.0, "upgrade_spend": 0.0,
		"rent": 0.0, "utilities": 0.0, "wages": 0.0, "event_fees": 0.0, "other": 0.0,
		"served": 0, "walkouts": 0, "satisfaction_sum": 0.0, "quality_sum": 0.0,
		"pours": 0, "wasted_units": 0.0, "complaints": 0, "live_event": "", "live_rating": 0.0, "prizes": 0.0,
	}


func new_game(new_mode := "career", name := "The Crooked Shamrock") -> void:
	_reset()
	mode = new_mode
	pub_name = name
	if mode == "sandbox":
		cash = float(GameData.econ("sandbox_cash", 5000))
	in_game = true
	start_day()


# ------------------------------------------------------------------ economy
func earn(amount: float, category := "sales") -> void:
	if amount <= 0.0:
		return
	cash += amount
	today[category] = float(today.get(category, 0.0)) + amount
	if category == "sales":
		stats["revenue"] = float(stats["revenue"]) + amount
	elif category == "tips":
		stats["tips"] = float(stats["tips"]) + amount
	cash_changed.emit(cash)


func can_afford(amount: float) -> bool:
	return cash + 0.0001 >= amount


func spend(amount: float, category := "other", allow_debt := false) -> bool:
	if amount <= 0.0:
		return true
	if not allow_debt and not can_afford(amount):
		return false
	cash -= amount
	today[category] = float(today.get(category, 0.0)) + amount
	cash_changed.emit(cash)
	return true


func price_of(drink_id: String) -> float:
	return float(prices.get(drink_id, GameData.drink(drink_id).get("price", 5.0)))


func set_price(drink_id: String, value: float) -> void:
	var base := float(GameData.drink(drink_id).get("price", 5.0))
	prices[drink_id] = clampf(snappedf(value, 0.1), base * 0.5, base * 2.0)


func unit_cost(drink_id: String) -> float:
	var d := GameData.drink(drink_id)
	return float(d.get("stock_cost", 100)) / float(d.get("units_per_stock", 80))


func drink_available(drink_id: String) -> bool:
	var d := GameData.drink(drink_id)
	if d.is_empty():
		return false
	var unlock: String = d.get("unlock", "")
	return unlock == "" or has_upgrade(unlock)


func available_drinks() -> Array:
	var out := []
	for d in GameData.drinks:
		if drink_available(d["id"]):
			out.append(d["id"])
	return out


## Takes serves from the connected keg. Returns false (and takes nothing) if it runs dry.
func draw_units(drink_id: String, units: float) -> bool:
	var left := float(tap_units.get(drink_id, 0))
	# bottles and syrup boxes are swapped behind the bar as soon as one runs out
	if left < units - 0.0001 and str(GameData.drink(drink_id).get("stock_unit", "keg")) not in ["keg", "cask"] and int(stock.get(drink_id, 0)) > 0:
		change_keg(drink_id)
		left = float(tap_units.get(drink_id, 0))
	if left < units - 0.0001:
		return false
	tap_units[drink_id] = left - units
	today["cogs"] = float(today["cogs"]) + units * unit_cost(drink_id)
	stock_changed.emit()
	return true


func waste_units(drink_id: String, units: float) -> void:
	today["wasted_units"] = float(today["wasted_units"]) + units


func serves_left(drink_id: String) -> float:
	return float(tap_units.get(drink_id, 0))


func change_keg(drink_id: String) -> bool:
	if int(stock.get(drink_id, 0)) <= 0:
		return false
	stock[drink_id] = int(stock[drink_id]) - 1
	var waste := float(tap_units.get(drink_id, 0))
	if waste > 0.0:
		waste_units(drink_id, waste)
	tap_units[drink_id] = int(GameData.drink(drink_id)["units_per_stock"])
	keg_day[drink_id] = day
	stats["kegs_changed"] = int(stats["kegs_changed"]) + 1
	stock_changed.emit()
	return true


## True when there's nothing left to pour and nothing in the cellar: the supplier will then put
## one delivery on the slate, so a broke pub can always trade its way back.
func stock_emergency() -> bool:
	for id in available_drinks():
		if serves_left(id) >= 1.0 or int(stock.get(id, 0)) > 0 or pending_delivery(id) > 0:
			return false
	return true


func order_stock(drink_id: String, packs: int) -> bool:
	var d := GameData.drink(drink_id)
	var cost := float(d["stock_cost"]) * packs + float(GameData.econ("delivery_fee", 6))
	if not spend(cost, "stock_spend", stock_emergency() and packs == 1):
		return false
	deliveries.append({"drink": drink_id, "packs": packs, "day": day + 1})
	stock_changed.emit()
	return true


func pending_delivery(drink_id: String) -> int:
	var n := 0
	for dl in deliveries:
		if dl["drink"] == drink_id:
			n += int(dl["packs"])
	return n


## 1.0 = fresh. Drops after a couple of days on tap; the cooler upgrade halves the decay.
func freshness(drink_id: String) -> float:
	var age := day - int(keg_day.get(drink_id, day))
	var decay := 0.06 * (1.0 + get_mod("freshness_decay_mult"))
	return clampf(1.0 - maxf(0.0, age - 2) * decay, 0.55, 1.0)


## Below this a keg is past its best: customers can taste it, and it's worth swapping early.
const STALE_FRESHNESS := 0.9


## True when the connected keg still has beer in it but has gone stale.
func keg_stale(drink_id: String) -> bool:
	return str(GameData.drink(drink_id).get("stock_unit", "keg")) in ["keg", "cask"] \
		and serves_left(drink_id) >= 1.0 and freshness(drink_id) < STALE_FRESHNESS


# ------------------------------------------------------------------ upgrades
func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


func can_buy_upgrade(id: String) -> bool:
	var u := GameData.upgrade(id)
	if u.is_empty() or has_upgrade(id):
		return false
	var req: String = u.get("requires", "")
	if req != "" and not has_upgrade(req):
		return false
	if reputation < float(u.get("min_rep", 0)):
		return false
	return can_afford(float(u["cost"]))


## The pub's standing, by reputation: each tier opens bigger upgrades.
const REP_TIERS := [[0, "A quiet local"], [15, "Known on the street"], [30, "Talk of the town"], [50, "The county's favourite"], [70, "Best pint in the west"], [90, "A legend of a pub"]]


func rep_tier() -> String:
	var t := str(REP_TIERS[0][1])
	for r in REP_TIERS:
		if reputation >= float(r[0]):
			t = str(r[1])
	return t


## The next tier up: [reputation needed, name], or [] at the top.
func next_rep_tier() -> Array:
	for r in REP_TIERS:
		if reputation < float(r[0]):
			return r
	return []


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	var u := GameData.upgrade(id)
	spend(float(u["cost"]), "upgrade_spend")
	upgrades[id] = day
	upgrades_changed.emit()
	upgrade_bought.emit(id)
	message.emit("Purchased: %s" % u["name"], "good")
	return true


## Sums an effect key across purchased upgrades, placed furniture and hired staff.
func get_mod(key: String) -> float:
	var total := float(festival_today().get("effects", {}).get(key, 0.0))
	for id in upgrades.keys():
		var eff: Dictionary = GameData.upgrade(id).get("effects", {})
		total += float(eff.get(key, 0.0))
	for f in furniture_placed:
		var fd: Dictionary = GameData.furniture_by_id.get(f["id"], {})
		total += float(fd.get("effects", {}).get(key, 0.0))
	return total


func glasses_total() -> int:
	return int(GameData.econ("start_glasses", 6)) + int(get_mod("glasses"))


func atmosphere() -> float:
	return clampf(20.0 + get_mod("atmosphere") + live_atmosphere, 0.0, 100.0)


# ------------------------------------------------------------------ time
func weekday() -> int:
	# Day 1 is a Thursday.
	return (day + 2) % 7


func weekday_name() -> String:
	var names: Array = GameData.econ("weekday_names", ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
	return names[weekday()]


func clock_text() -> String:
	var h := int(floor(hour)) % 24
	var m := int(floor((hour - floor(hour)) * 60.0))
	return "%02d:%02d" % [h, m]


func seconds_per_game_hour() -> float:
	return float(settings.get("day_length", 10)) * 60.0 / 8.0


func start_day() -> void:
	live_atmosphere = 0.0
	live_stay = 0.0
	live_tips = 0.0
	hour = 15.5
	phase = "prep"
	_reset_today()
	var arrived := []
	for dl in deliveries:
		if int(dl["day"]) <= day:
			stock[dl["drink"]] = int(stock.get(dl["drink"], 0)) + int(dl["packs"])
			arrived.append(dl)
	for dl in arrived:
		deliveries.erase(dl)
		message.emit("Delivery arrived: %d × %s" % [int(dl["packs"]), GameData.drink_name(dl["drink"])], "info")
	for id in available_drinks():
		if keg_stale(id):
			var unit := str(GameData.drink(id).get("stock_unit", "keg"))
			if int(stock.get(id, 0)) > 0:
				message.emit("The %s %s has gone stale (%d%% fresh). Swap it for a spare in the cellar." % [GameData.drink(id).get("short", id), unit, int(freshness(id) * 100)], "bad")
			else:
				message.emit("The %s %s has gone stale (%d%% fresh). Order a fresh one from the stock menu." % [GameData.drink(id).get("short", id), unit, int(freshness(id) * 100)], "bad")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 7919)
	var r := rng.randf()
	weather = "rain" if r < 0.45 else ("cloudy" if r < 0.75 else ("clear" if r < 0.93 else "storm"))
	refresh_applicants()
	stock_changed.emit()
	day_changed.emit()


func open_pub() -> void:
	if phase == "prep":
		phase = "open"
		hour = maxf(hour, float(GameData.econ("day_open_hour", 16.0)))


# ------------------------------------------------------------------ daily goals
signal goal_done(goal: Dictionary)


## Today's three goals (always a serving target plus two others), made the first time they're asked for.
func daily_goals() -> Array:
	if today.has("goals"):
		return today["goals"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 104729 + 17)
	var always: Array = []
	var others: Array = []
	for o in GameData.objectives:
		if bool(o.get("always", false)):
			always.append(o)
		elif not (str(o["id"]) == "chat" and day <= 1):
			others.append(o)
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = others[i]
		others[i] = others[j]
		others[j] = t
	var goals: Array = []
	for o in always + others.slice(0, 3 - always.size()):
		var target := 0
		if o.has("base"):
			target = mini(int(round(float(o["base"]) + float(o.get("per_day", 0)) * (day - 1))), int(o.get("max", 99)))
		var text := str(o["text"])
		goals.append({"id": o["id"], "text": text % target if text.contains("%d") else text, "stat": o["stat"],
			"kind": o.get("kind", "count"), "target": target, "min_served": int(o.get("min_served", 0)),
			"reward": float(o.get("reward", 10)), "done": false})
	today["goals"] = goals
	return goals


## Where a goal's counter stands today.
func goal_value(g: Dictionary) -> float:
	match str(g["stat"]):
		"avg_quality":
			return float(today["quality_sum"]) / maxi(1, int(today["pours"]))
		"tips":
			return float(today["tips"])
	return float(today.get(str(g["stat"]), 0))


## Counting goals pay out the moment they're reached; "nobody walks out" and averages at closing.
func check_goals(closing := false) -> void:
	for g in daily_goals():
		if g["done"]:
			continue
		var met := false
		match str(g["kind"]):
			"count":
				met = goal_value(g) >= float(g["target"])
			"zero":
				met = closing and goal_value(g) <= 0.0 and int(today["served"]) >= int(g["min_served"])
			"avg":
				met = closing and goal_value(g) >= float(g["target"]) and int(today["pours"]) >= int(g["min_served"])
		if met:
			g["done"] = true
			earn(float(g["reward"]), "prizes")
			goal_done.emit(g)


func bump_today(key: String, n := 1) -> void:
	today[key] = int(today.get(key, 0)) + n


# ------------------------------------------------------------------ staff
signal staff_changed

## Most of each role the pub can take on at once, and the second bartender waits for a busier pub.
const STAFF_LIMIT := {"bartender": 2, "collector": 1}
const SECOND_BARTENDER_REP := 50.0
## What makes each person different on the job.
const TRAITS := {
	"quick": {"name": "Quick", "desc": "Works about 15% faster"},
	"steady": {"name": "Steady hand", "desc": "Pours closer to perfect"},
	"charmer": {"name": "Charmer", "desc": "Customers tip them a fifth more"},
	"tireless": {"name": "Tireless", "desc": "Needs fewer breaks"},
	"cellar": {"name": "Cellar hand", "desc": "Changes empty and stale kegs without being asked"},
	"keen": {"name": "Keen learner", "desc": "Gets better twice as fast"},
}
const ROLE_TRAITS := {"bartender": ["quick", "steady", "charmer", "tireless", "cellar", "keen"],
	"collector": ["quick", "tireless", "cellar", "keen"]}
const MORALE_WORDS := [[0.0, "fed up"], [0.2, "unhappy"], [0.4, "getting on with it"], [0.6, "content"], [0.8, "happy"]]


func is_hired(id: String) -> bool:
	return not staff_entry(id).is_empty()


func staff_entry(id: String) -> Dictionary:
	for s in staff:
		if str(s.get("id", "")) == id:
			return s
	return {}


func staff_count(role: String) -> int:
	var n := 0
	for s in staff:
		if str(s.get("role", "")) == role:
			n += 1
	return n


## A candidate by id: this week's applicants first, then the well-known names in data/staff.json.
func candidate(id: String) -> Dictionary:
	for a in applicants:
		if str(a.get("id", "")) == id:
			return a
	return GameData.staff_candidate(id)


## Everyone who could be taken on right now (or soon): the named people and this week's applicants.
func job_seekers() -> Array:
	var out: Array = []
	for c in GameData.staff_pool:
		if not is_hired(str(c["id"])):
			out.append(c)
	for a in applicants:
		if not is_hired(str(a["id"])):
			out.append(a)
	return out


static func staff_level(skill: float) -> int:
	return clampi(int(round(skill * 5.0)), 1, 5)


static func morale_word(m: float) -> String:
	var w := ""
	for mw in MORALE_WORDS:
		if m >= float(mw[0]):
			w = str(mw[1])
	return w


## Why a candidate can't be taken on right now ("" if they can).
func hire_block(id: String) -> String:
	var c := candidate(id)
	if c.is_empty():
		return "Unknown"
	if is_hired(id):
		return "Already working here"
	if reputation < float(c.get("min_rep", 0)):
		return "Needs reputation %d" % int(c.get("min_rep", 0))
	var role := str(c["role"])
	if staff_count(role) >= int(STAFF_LIMIT.get(role, 1)):
		return "No room for another %s" % ("bartender" if role == "bartender" else "glass collector")
	if role == "bartender" and staff_count("bartender") >= 1 and reputation < SECOND_BARTENDER_REP:
		return "A second bartender needs reputation %d" % int(SECOND_BARTENDER_REP)
	var upfront := hire_fee(id) + float(c.get("wage", 0))
	if cash < upfront:
		return "Need €%d (agency fee and the first night's wages)" % int(upfront)
	return ""


## The one-off agency fee for taking someone on (paid when hired, like a recruitment fee).
func hire_fee(id: String) -> float:
	return float(candidate(id).get("fee", 0))


func hire(id: String) -> bool:
	if hire_block(id) != "":
		return false
	var c := candidate(id)
	spend(hire_fee(id), "wages")
	var e := {"id": id, "name": c["name"], "role": c["role"], "skill": float(c["skill"]),
		"wage": float(c["wage"]), "model": c.get("model", ""), "gender": c.get("gender", "m"), "hired_day": day}
	_staff_defaults(e, c)
	staff.append(e)
	staff_changed.emit()
	return true


## Fills in everything a member of staff carries (for new hires and saves from before the rota).
func _staff_defaults(e: Dictionary, c := {}) -> void:
	if c.is_empty():
		c = candidate(str(e.get("id", "")))
	if not e.has("trait"):
		e["trait"] = str(c.get("trait", ""))
	if not e.has("potential"):
		e["potential"] = maxf(float(e.get("skill", 0.5)), float(c.get("potential", float(e.get("skill", 0.5)) + 0.2)))
	for k in ["xp", "raise_ask", "notice", "in_a_row"]:
		if not e.has(k):
			e[k] = 0
	if not e.has("morale"):
		e["morale"] = 0.75
	if not e.has("rota") or (e["rota"] as Array).size() != 7:
		e["rota"] = [true, true, true, true, true, true, true]
	if not e.has("totals"):
		e["totals"] = {"served": 0, "glasses": 0, "spills": 0, "kegs": 0, "nights": 0}


## Letting someone go: they get a night's wages as notice, and leave straight away.
func fire(id: String) -> void:
	var e := staff_entry(id)
	if e.is_empty():
		return
	spend(float(e.get("wage", 0)), "wages", true)
	staff.erase(e)
	staff_changed.emit()


# ---- the rota: who works which night (wages are only paid for nights worked)
func works_on(e: Dictionary, wd: int) -> bool:
	var rota: Array = e.get("rota", [])
	return rota.size() != 7 or bool(rota[wd])


func works_today(e: Dictionary) -> bool:
	return works_on(e, weekday())


func staff_on_today() -> Array:
	return staff.filter(func(e): return works_today(e))


func set_rota(id: String, wd: int, on: bool) -> void:
	var e := staff_entry(id)
	if e.is_empty() or wd < 0 or wd > 6:
		return
	# tonight's shift is fixed once the doors are open
	if wd == weekday() and phase != "prep":
		return
	(e["rota"] as Array)[wd] = on
	staff_changed.emit()


## How busy a night of the week looks: 1.0 is an ordinary night; matches and festivals add on.
func busy_forecast(days_ahead: int) -> float:
	var d := day + days_ahead
	var wd := (d + 2) % 7      # the same reckoning as weekday(): day 1 is a Thursday
	var mults: Array = GameData.econ("weekday_mult", [1, 1, 1, 1, 1, 1, 1])
	var f := float(mults[wd])
	if has_upgrade("big_screen") and wd in [2, 6]:
		f += 0.2
	var fd := (d - 1) % FESTIVAL_CYCLE + 1
	for fe in GameData.festivals:
		if int(fe["day"]) == fd:
			f += 0.35
	return f


static func busy_word(f: float) -> String:
	if f >= 1.4:
		return "Packed"
	if f >= 1.15:
		return "Busy"
	if f >= 0.95:
		return "Steady"
	return "Quiet"


# ---- experience, skill, morale and pay
## Records a piece of work: experience (the trade is learned on the job), and tonight's tally.
func staff_note(id: String, kind: String, amount := 1.0) -> void:
	var e := staff_entry(id)
	if e.is_empty():
		return
	var log: Dictionary = today.get("staff_log", {})
	if not log.has(id):
		log[id] = {"served": 0, "glasses": 0, "spills": 0, "kegs": 0, "tips": 0.0}
	var rec: Dictionary = log[id]
	rec[kind] = float(rec.get(kind, 0)) + amount
	today["staff_log"] = log
	var gain := {"served": 1.0, "glasses": 0.3, "spills": 0.5, "kegs": 0.5}.get(kind, 0.0) as float
	if gain <= 0.0:
		return
	if str(e.get("trait", "")) == "keen":
		gain *= 2.0
	e["xp"] = float(e.get("xp", 0)) + gain
	var before := staff_level(float(e["skill"]))
	e["skill"] = minf(float(e.get("potential", e["skill"])), float(e["skill"]) + gain * 0.0035)
	var after := staff_level(float(e["skill"]))
	if after > before and float(e.get("raise_ask", 0)) <= 0.0:
		e["raise_ask"] = roundf(float(e["wage"]) * 1.15 + 1.0)
		message.emit("%s is getting good at this (skill %d/5) and would like a raise to €%d a night. See the Staff tab." % [str(e["name"]).split(" ")[0], after, int(e["raise_ask"])], "info")


func agree_raise(id: String) -> void:
	var e := staff_entry(id)
	if e.is_empty() or float(e.get("raise_ask", 0)) <= 0.0:
		return
	e["wage"] = float(e["raise_ask"])
	e["raise_ask"] = 0
	e["morale"] = minf(1.0, float(e["morale"]) + 0.25)
	staff_changed.emit()


func refuse_raise(id: String) -> void:
	var e := staff_entry(id)
	if e.is_empty():
		return
	e["raise_ask"] = 0
	e["morale"] = maxf(0.0, float(e["morale"]) - 0.25)
	staff_changed.emit()


## A word and a bonus (two nights' wages) for someone who's fed up or has handed in their notice.
func bonus_cost(id: String) -> float:
	return float(staff_entry(id).get("wage", 0)) * 2.0


func give_bonus(id: String) -> bool:
	var e := staff_entry(id)
	if e.is_empty() or not spend(bonus_cost(id), "wages"):
		return false
	e["morale"] = minf(1.0, float(e["morale"]) + 0.35)
	e["notice"] = 0
	staff_changed.emit()
	return true


## How much faster (or slower) someone works: their trait and how they feel about the job.
func staff_pace(e: Dictionary) -> float:
	var p := lerpf(0.88, 1.08, clampf(float(e.get("morale", 0.75)), 0.0, 1.0))
	if str(e.get("trait", "")) == "quick":
		p *= 1.15
	return p


## The close of the night for the staff: totals, morale, and anyone handing in (or working) notice.
## Returns one line per person for the end-of-day summary.
func _staff_end_of_night() -> Array:
	var lines: Array = []
	var log: Dictionary = today.get("staff_log", {})
	var busy := float(today.get("served", 0)) >= 30.0
	for e in staff.duplicate():
		var id := str(e["id"])
		var first := str(e["name"]).split(" ")[0]
		var rec: Dictionary = log.get(id, {})
		var m := float(e.get("morale", 0.75))
		if works_today(e):
			e["in_a_row"] = int(e.get("in_a_row", 0)) + 1
			var tot: Dictionary = e["totals"]
			tot["nights"] = int(tot.get("nights", 0)) + 1
			for k in ["served", "glasses", "spills", "kegs"]:
				tot[k] = int(tot.get(k, 0)) + int(rec.get(k, 0))
			m -= 0.02 + (0.03 if busy else 0.0)
			if int(e["in_a_row"]) > 5:
				m -= 0.05     # six or seven nights on the trot wears anyone down
			var bits: Array = []
			if int(rec.get("served", 0)) > 0:
				bits.append("served %d" % int(rec["served"]))
			if int(rec.get("glasses", 0)) > 0:
				bits.append("washed %d glasses" % int(rec["glasses"]))
			if int(rec.get("spills", 0)) > 0:
				bits.append("wiped %d spills" % int(rec["spills"]))
			if int(rec.get("kegs", 0)) > 0:
				bits.append("changed %d kegs" % int(rec["kegs"]))
			lines.append("%s %s (€%d) · %s" % [first, ", ".join(bits) if not bits.is_empty() else "had a quiet one", int(e["wage"]), morale_word(clampf(m, 0.0, 1.0))])
		else:
			e["in_a_row"] = 0
			m += 0.08
		e["morale"] = clampf(m, 0.0, 1.0)
		if int(e.get("notice", 0)) > 0:
			e["notice"] = int(e["notice"]) - 1
			if int(e["notice"]) <= 0:
				staff.erase(e)
				message.emit("%s has worked their notice and left." % first, "bad")
				lines.append("%s has left" % first)
		elif float(e["morale"]) < 0.15:
			e["notice"] = 2
			message.emit("%s is fed up and has handed in their notice: two more nights. A word and a bonus might change their mind (Staff tab)." % first, "bad")
	staff_changed.emit()
	return lines


# ---- this week's applicants
const FIRST_NAMES := {"m": ["Cian", "Darragh", "Eoin", "Fionn", "Oisín", "Pádraig", "Rory", "Tadhg", "Colm", "Declan", "Liam", "Seán"],
	"f": ["Aoife", "Caoimhe", "Clodagh", "Niamh", "Orla", "Saoirse", "Sinéad", "Úna", "Gráinne", "Méabh", "Eimear", "Ciara"]}
const SURNAMES := ["Brennan", "Byrne", "Carroll", "Daly", "Dunne", "Farrell", "Gallagher", "Hayes", "Keane", "Lynch", "Murphy", "Nolan", "O'Brien", "Power", "Quigley", "Walsh"]
const BLURBS := {"bartender": ["Pulled pints through college in Galway.", "Two years in a hotel bar in Killarney.", "New to the trade but keen to learn.", "Worked the summer season in Doolin.", "Back from London and looking for a local."],
	"collector": ["Wants evening work around school hours.", "Retired, and likes to keep busy.", "Fast on their feet and not afraid of a sink.", "Looking for a few nights a week."]}


## Every Monday a few new people answer the card in the window (the unhired ones move on).
func refresh_applicants(force := false) -> void:
	var week := (day - 1) / 7
	if applicants_week == week and not force:
		return
	applicants_week = week
	applicants = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(week * 7717 + 3)
	var used_models: Array = []
	for e in staff:
		used_models.append(str(e.get("model", "")))
	for c in GameData.staff_pool:
		used_models.append(str(c.get("model", "")))
	var models := {"m": ["m_young_a", "m_young_c", "m_mid_a", "m_mid_b", "m_old_a"], "f": ["f_young_a", "f_young_c", "f_mid_a", "f_mid_c", "f_old_a"]}
	for i in 3:
		var role := "bartender" if i < 2 else "collector"
		var g := "m" if rng.randf() < 0.5 else "f"
		var pool: Array = (models[g] as Array).filter(func(mm): return not used_models.has(mm))
		if pool.is_empty():
			pool = models[g]
		var model := str(pool[rng.randi() % pool.size()])
		used_models.append(model)
		var skill := snappedf(clampf(rng.randf_range(0.35, 0.68) + reputation * 0.002, 0.3, 0.8), 0.01)
		var potential := snappedf(clampf(skill + rng.randf_range(0.12, 0.35), skill, 0.95), 0.01)
		var traits: Array = ROLE_TRAITS[role]
		var wage: float = roundf((9.0 + skill * 24.0) if role == "bartender" else (7.0 + skill * 12.0))
		var fn: Array = FIRST_NAMES[g]
		var blurbs: Array = BLURBS[role]
		applicants.append({"id": "app_%d_%d" % [week, i], "name": "%s %s" % [fn[rng.randi() % fn.size()], SURNAMES[rng.randi() % SURNAMES.size()]],
			"role": role, "skill": skill, "potential": potential, "trait": str(traits[rng.randi() % traits.size()]),
			"wage": wage, "fee": roundf(wage * 3.0), "min_rep": 25 if role == "bartender" else 10, "model": model, "gender": g,
			"blurb": str(blurbs[rng.randi() % blurbs.size()]), "applicant": true})


# ------------------------------------------------------------------ the calendar
const FESTIVAL_CYCLE := 28


## Today's festival, if any (they come round every four weeks).
func festival_today() -> Dictionary:
	var d := (day - 1) % FESTIVAL_CYCLE + 1
	for f in GameData.festivals:
		if int(f["day"]) == d:
			return f
	return {}


## The next festival: [days away, festival].
func next_festival() -> Array:
	for k in range(1, FESTIVAL_CYCLE + 1):
		var d := (day - 1 + k) % FESTIVAL_CYCLE + 1
		for f in GameData.festivals:
			if int(f["day"]) == d:
				return [k, f]
	return []


## Matches on the big screen: Sunday afternoons, Wednesday evenings and any final. [start, end] hours or [].
func match_today() -> Array:
	if not has_upgrade("big_screen"):
		return []
	if bool(festival_today().get("match", false)):
		return [18.0, 20.0]
	match weekday_name().substr(0, 3):
		"Sun":
			return [17.0, 19.0]
		"Wed":
			return [20.0, 22.0]
	return []


# ------------------------------------------------------------------ beer lines
## Draught pints lose quality as the lines go a week or more without cleaning.
func line_penalty() -> float:
	var days := day - int(progress.get("lines_cleaned_day", day))
	return clampf((days - 5) * 2.0, 0.0, 12.0)


func clean_lines() -> bool:
	var cost := float(GameData.econ("line_clean_cost", 8))
	if not spend(cost, "other"):
		return false
	progress["lines_cleaned_day"] = day
	return true


func wages_today() -> float:
	var w := 0.0
	for s in staff_on_today():
		w += float(s.get("wage", 0))
	return w


## Settles the day's overheads and returns the summary shown on the end-of-day screen.
func end_day() -> Dictionary:
	var rent := float(GameData.econ("rent_per_day", 30))
	var utilities := float(GameData.econ("utilities_per_day", 8)) + get_mod("utilities")
	var wages := wages_today()
	if mode == "sandbox":
		rent = 0.0
	spend(rent, "rent", true)
	spend(utilities, "utilities", true)
	spend(wages, "wages", true)
	var staff_lines := _staff_end_of_night()
	var income := float(today["sales"]) + float(today["tips"]) + float(today.get("prizes", 0.0)) + float(today.get("refunds", 0.0))
	var expenses := float(today["stock_spend"]) + float(today["upgrade_spend"]) + float(today["rent"]) \
		+ float(today["utilities"]) + float(today["wages"]) + float(today["event_fees"]) + float(today["other"])
	var served := int(today["served"])
	var avg_sat := float(today["satisfaction_sum"]) / served if served > 0 else 0.0
	var avg_q := float(today["quality_sum"]) / maxi(1, int(today["pours"]))
	var rep_change := 0.0
	if served > 0:
		rep_change += (avg_sat - 55.0) / 12.0 * clampf(served / 6.0, 0.3, 2.0)
	rep_change -= int(today["walkouts"]) * 0.6
	rep_change += get_mod("rep_gain")
	# a well-received live night gets the town talking
	if str(today.get("live_event", "")) != "":
		rep_change += float(today.get("live_rating", 0.5)) * 2.5
	reputation = clampf(reputation + rep_change, 0.0, 100.0)
	var summary := {
		"day": day, "weekday": weekday_name(), "sales": today["sales"], "tips": today["tips"],
		"cogs": today["cogs"], "stock_spend": today["stock_spend"], "upgrade_spend": today["upgrade_spend"],
		"rent": today["rent"], "utilities": today["utilities"], "wages": today["wages"],
		"event_fees": today["event_fees"], "other": today["other"], "income": income, "expenses": expenses,
		"profit": income - expenses, "prizes": today.get("prizes", 0.0), "refunds": today.get("refunds", 0.0), "live_event": today.get("live_event", ""), "gross_margin": float(today["sales"]) - float(today["cogs"]),
		"served": served, "walkouts": today["walkouts"], "avg_satisfaction": avg_sat, "avg_quality": avg_q,
		"reputation": reputation, "rep_change": rep_change, "wasted": today["wasted_units"], "cash": cash,
		"staff_lines": staff_lines,
	}
	history.append(summary)
	if history.size() > 14:
		history.pop_front()
	stats["days"] = int(stats["days"]) + 1
	day += 1
	start_day()
	save_game()
	return summary


# ------------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "pub_name": pub_name, "mode": mode, "cash": cash, "day": day,
		"hour": hour, "phase": phase, "reputation": reputation, "weather": weather,
		"upgrades": upgrades, "stock": stock, "tap_units": tap_units, "keg_day": keg_day,
		"prices": prices, "relationships": relationships, "staff": staff, "applicants": applicants, "applicants_week": applicants_week, "progress": progress, "bookings": bookings,
		"furniture_placed": furniture_placed, "objectives_done": objectives_done,
		"deliveries": deliveries, "stats": stats, "today": today, "history": history,
		"best_split_mm": best_split_mm, "tutorial": tutorial,
		"saved_at": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	_reset()
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		push_warning("Save is from a newer version; loading what we understand.")
	pub_name = str(d.get("pub_name", pub_name))
	mode = str(d.get("mode", mode))
	cash = float(d.get("cash", cash))
	day = int(d.get("day", day))
	hour = float(d.get("hour", hour))
	phase = str(d.get("phase", phase))
	if phase == "closing":
		phase = "last_orders"
	reputation = float(d.get("reputation", reputation))
	weather = str(d.get("weather", weather))
	upgrades = d.get("upgrades", {})
	for k in ["stock", "tap_units", "keg_day", "prices"]:
		var src: Dictionary = d.get(k, {})
		var dst: Dictionary = get(k)
		for id in src.keys():
			dst[id] = src[id]
	for id in stock.keys():
		stock[id] = int(stock[id])
		keg_day[id] = int(keg_day.get(id, day))
	relationships = d.get("relationships", {})
	applicants = d.get("applicants", [])
	applicants_week = int(d.get("applicants_week", -1))
	staff = d.get("staff", [])
	for e in staff:
		_staff_defaults(e)
	progress = d.get("progress", {"lines_cleaned_day": day})
	bookings = d.get("bookings", {})
	furniture_placed = d.get("furniture_placed", [])
	objectives_done = d.get("objectives_done", [])
	deliveries = d.get("deliveries", [])
	var st: Dictionary = d.get("stats", {})
	for k in st.keys():
		stats[k] = st[k]
	var td: Dictionary = d.get("today", {})
	for k in td.keys():
		today[k] = td[k]
	history = d.get("history", [])
	best_split_mm = float(d.get("best_split_mm", -1.0))
	tutorial = d.get("tutorial", {})
	in_game = true


## Atomic save: write a temp file, keep the previous save as a backup, then swap.
func save_game() -> bool:
	var json := JSON.stringify(to_dict(), "\t")
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(json)
	f.flush()
	f.close()
	# verify what we wrote parses before replacing the real save
	var check: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_TMP))
	if typeof(check) != TYPE_DICTIONARY:
		push_error("Save verification failed")
		return false
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BAK):
			dir.remove(SAVE_BAK.get_file())
		dir.rename(SAVE_PATH.get_file(), SAVE_BAK.get_file())
	var err := dir.rename(SAVE_TMP.get_file(), SAVE_PATH.get_file())
	return err == OK


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BAK)


func load_game() -> bool:
	for path in [SAVE_PATH, SAVE_BAK]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			from_dict(parsed)
			if path == SAVE_BAK:
				message.emit("Main save was damaged; restored the backup.", "warn")
			return true
	return false


func delete_save() -> void:
	var dir := DirAccess.open("user://")
	for p in [SAVE_PATH, SAVE_BAK, SAVE_TMP]:
		if FileAccess.file_exists(p):
			dir.remove(p.get_file())


func save_summary() -> String:
	if not has_save():
		return ""
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else SAVE_BAK
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	return "%s · Day %d · €%.2f" % [parsed.get("pub_name", "Pub"), int(parsed.get("day", 1)), float(parsed.get("cash", 0))]


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
	settings_changed.emit()


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed.keys():
			settings[k] = parsed[k]
		if int(parsed.get("mix_version", 1)) < 2:
			# the first mix had the rain over the voices: move older settings onto the new balance
			settings["vol_speech"] = maxf(float(settings.get("vol_speech", 0.7)), 1.0)
			settings["vol_ambience"] = minf(float(settings.get("vol_ambience", 0.7)), 0.6)
			settings["mix_version"] = 2
	settings["graphics"] = graphics_preset()


const GRAPHICS_PRESETS := ["performance", "balanced", "high", "ultra"]


## The graphics preset, with the names used by earlier versions mapped onto the new ones.
func graphics_preset() -> String:
	var g := str(settings.get("graphics", "balanced"))
	match g:
		"low":
			return "performance"
		"medium":
			return "balanced"
	return g if g in GRAPHICS_PRESETS else "balanced"


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()


func notify(text: String, kind := "info") -> void:
	message.emit(text, kind)


func vibrate(ms := 30) -> void:
	if settings.get("vibration", true) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
