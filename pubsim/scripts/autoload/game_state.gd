extends Node
## All persistent game state, the economy ledger and versioned save/load.

signal cash_changed(value: float)
signal message(text: String, kind: String)
signal upgrades_changed
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

var settings: Dictionary = {
	"look_sensitivity": 1.0,
	"button_opacity": 0.85,
	"hud_scale": 1.0,
	"vibration": true,
	"vol_master": 0.9,
	"vol_music": 0.8,
	"vol_ambience": 0.7,
	"vol_speech": 0.7,
	"vol_effects": 0.9,
	"graphics": "medium",
	"render_scale": 1.0,
	"fps_limit": 60,
	"reduced_motion": false,
	"reduced_effects": false,
	"pour_assist": false,
	"day_length": 10,
	"show_fps": false,
	"subtitles": true,
	"high_contrast": false,
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
		"split_attempts": 0, "kegs_changed": 0, "own_pints": 0, "rhythm_best": 0,
		"food_served": 0, "quiz_nights": 0,
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
		"pours": 0, "wasted_units": 0.0, "complaints": 0,
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
	return can_afford(float(u["cost"]))


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	var u := GameData.upgrade(id)
	spend(float(u["cost"]), "upgrade_spend")
	upgrades[id] = day
	upgrades_changed.emit()
	message.emit("Purchased: %s" % u["name"], "good")
	return true


## Sums an effect key across purchased upgrades, placed furniture and hired staff.
func get_mod(key: String) -> float:
	var total := 0.0
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
	return clampf(20.0 + get_mod("atmosphere"), 0.0, 100.0)


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
	var income := float(today["sales"]) + float(today["tips"])
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
	reputation = clampf(reputation + rep_change, 0.0, 100.0)
	var summary := {
		"day": day, "weekday": weekday_name(), "sales": today["sales"], "tips": today["tips"],
		"cogs": today["cogs"], "stock_spend": today["stock_spend"], "upgrade_spend": today["upgrade_spend"],
		"rent": today["rent"], "utilities": today["utilities"], "wages": today["wages"],
		"event_fees": today["event_fees"], "other": today["other"], "income": income, "expenses": expenses,
		"profit": income - expenses, "gross_margin": float(today["sales"]) - float(today["cogs"]),
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
		"prices": prices, "relationships": relationships, "staff": staff, "bookings": bookings,
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


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()


func notify(text: String, kind := "info") -> void:
	message.emit(text, kind)


func vibrate(ms := 30) -> void:
	if settings.get("vibration", true) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
