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


func order_stock(drink_id: String, packs: int) -> bool:
	var d := GameData.drink(drink_id)
	var cost := float(d["stock_cost"]) * packs + float(GameData.econ("delivery_fee", 6))
	if not spend(cost, "stock_spend"):
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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 7919)
	var r := rng.randf()
	weather = "rain" if r < 0.45 else ("cloudy" if r < 0.75 else ("clear" if r < 0.93 else "storm"))
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

## Most of each role the pub can take on at once.
const STAFF_LIMIT := {"bartender": 2, "collector": 1}


func is_hired(id: String) -> bool:
	for s in staff:
		if str(s.get("id", "")) == id:
			return true
	return false


func staff_count(role: String) -> int:
	var n := 0
	for s in staff:
		if str(s.get("role", "")) == role:
			n += 1
	return n


## Why a candidate can't be taken on right now ("" if they can).
func hire_block(id: String) -> String:
	var c := GameData.staff_candidate(id)
	if c.is_empty():
		return "Unknown"
	if is_hired(id):
		return "Already working here"
	if reputation < float(c.get("min_rep", 0)):
		return "Needs reputation %d" % int(c.get("min_rep", 0))
	var role := str(c["role"])
	if staff_count(role) >= int(STAFF_LIMIT.get(role, 1)):
		return "No room for another %s" % ("bartender" if role == "bartender" else "glass collector")
	if cash < float(c.get("wage", 0)):
		return "Need €%d for the first night's wages" % int(c.get("wage", 0))
	return ""


func hire(id: String) -> bool:
	if hire_block(id) != "":
		return false
	var c := GameData.staff_candidate(id)
	staff.append({"id": id, "name": c["name"], "role": c["role"], "skill": float(c["skill"]),
		"wage": float(c["wage"]), "model": c.get("model", ""), "gender": c.get("gender", "m"), "hired_day": day})
	staff_changed.emit()
	return true


func fire(id: String) -> void:
	for i in range(staff.size() - 1, -1, -1):
		if str(staff[i].get("id", "")) == id:
			staff.remove_at(i)
	staff_changed.emit()


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
	for s in staff:
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
	var income := float(today["sales"]) + float(today["tips"]) + float(today.get("prizes", 0.0))
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
		"profit": income - expenses, "prizes": today.get("prizes", 0.0), "live_event": today.get("live_event", ""), "gross_margin": float(today["sales"]) - float(today["cogs"]),
		"served": served, "walkouts": today["walkouts"], "avg_satisfaction": avg_sat, "avg_quality": avg_q,
		"reputation": reputation, "rep_change": rep_change, "wasted": today["wasted_units"], "cash": cash,
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
		"prices": prices, "relationships": relationships, "staff": staff, "progress": progress, "bookings": bookings,
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
	staff = d.get("staff", [])
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
