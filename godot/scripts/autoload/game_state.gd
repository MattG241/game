extends Node
## All mutable progression state plus the economy rules that act on it.

signal credits_changed(value: float)
signal tank_changed(amount: float, capacity: float)
signal battery_changed(value: float, capacity: float)
signal tool_changed(id: String)
signal notify(text: String, kind: String)
signal mission_completed(mission: Dictionary)
signal inventory_changed
signal vehicles_changed
signal machines_changed
signal sold(amount: float, credits: float)

const SAVE_VERSION := 3   # 2: the Moon became a real sphere, 3: simpler automation

var dirt := DirtMap.new()

var credits := 0.0
var rp := 0.0
var tank_dust := 0.0
var tank_value := 0.0
var battery := 100.0
var tools := {}               # id -> upgrade level
var equipped := "toothbrush"
var tank_level := 0
var battery_level := 0
var boots_level := 0
var regions := [true, false, false, false, false]
var research_done: Array = []
var missions_done: Array = []
var achievements_done: Array = []
var vehicles: Array = []      # [{id, engine, storage_lvl, clean_lvl, pos, yaw, dust, value}]
var machines: Array = []      # [{uid, id, pos, yaw, buffer, value, ...}] - driven by Automation
var next_uid := 1
var flags := {}
var hexes_done: Array = []       # hexagon sectors cleared (HexGrid cell indices)
var hex_frac := {}               # cell -> fraction clean last measured (for the map)
var hex_work := {}               # cell -> share of the hexagon cleared by machines
var salvage_taken: Array = []
var landmark_progress := {}
var stats := {}
var player := {"pos": [0.0, 1.0, 12.0], "yaw": 0.0, "pitch": -0.25, "vehicle": -1}
var started_at := 0

var _mission_timer := 0.0
var active := false           # true while a game world is running


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	new_game()
	active = false


func _process(delta: float) -> void:
	if not active or get_tree().paused:
		return
	stats["play_time"] = stat("play_time") + delta
	_mission_timer += delta
	if _mission_timer > 0.5:
		_mission_timer = 0.0
		check_missions()


# ------------------------------------------------------------------ lifecycle

func new_game() -> void:
	dirt.reset()
	credits = float(GameData.economy.get("start_credits", 0))
	rp = 0.0
	tank_dust = 0.0
	tank_value = 0.0
	tools = {"toothbrush": 0}
	equipped = "toothbrush"
	tank_level = 0
	battery_level = 0
	boots_level = 0
	regions = [true, false, false, false, false]
	research_done = []
	missions_done = []
	achievements_done = []
	vehicles = []
	machines = []
	next_uid = 1
	flags = {}
	salvage_taken = []
	hexes_done = []
	hex_frac = {}
	hex_work = {}
	landmark_progress = {}
	stats = {}
	var sp := LunarBase.spawn_point()
	player = {"pos": [sp.x, sp.y, sp.z], "yaw": 0.0, "pitch": -0.3, "vehicle": -1}
	battery = battery_capacity()
	started_at = int(Time.get_unix_time_from_system())


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"credits": credits, "rp": rp,
		"tank_dust": tank_dust, "tank_value": tank_value, "battery": battery,
		"tools": tools, "equipped": equipped,
		"tank_level": tank_level, "battery_level": battery_level, "boots_level": boots_level,
		"regions": regions, "research_done": research_done,
		"missions_done": missions_done, "achievements_done": achievements_done,
		"vehicles": vehicles, "machines": machines, "next_uid": next_uid,
		"flags": flags, "salvage_taken": salvage_taken,
		"hexes_done": hexes_done, "hex_frac": hex_frac, "hex_work": hex_work,
		"landmark_progress": landmark_progress, "stats": stats,
		"player": player, "started_at": started_at,
		"clean_chunks": dirt.clean.keys().map(func(k): return [k.x, k.y, k.z]),
	}


func from_dict(d: Dictionary) -> void:
	new_game()
	d = migrate(d)
	credits = float(d.get("credits", 0.0))
	rp = float(d.get("rp", 0.0))
	tank_dust = float(d.get("tank_dust", 0.0))
	tank_value = float(d.get("tank_value", 0.0))
	tools = d.get("tools", {"toothbrush": 0})
	for k in tools.keys():
		tools[k] = int(tools[k])
		if GameData.tool(k).is_empty():
			tools.erase(k)
	if not tools.has("toothbrush"):
		tools["toothbrush"] = 0
	equipped = d.get("equipped", "toothbrush")
	if not tools.has(equipped):
		equipped = "toothbrush"
	tank_level = int(d.get("tank_level", 0))
	battery_level = int(d.get("battery_level", 0))
	boots_level = int(d.get("boots_level", 0))
	var r: Array = d.get("regions", regions)
	for i in mini(r.size(), regions.size()):
		regions[i] = bool(r[i])
	regions[0] = true
	research_done = d.get("research_done", [])
	missions_done = d.get("missions_done", [])
	achievements_done = d.get("achievements_done", [])
	vehicles = d.get("vehicles", [])
	machines = d.get("machines", [])
	next_uid = int(d.get("next_uid", machines.size() + 1))
	flags = d.get("flags", {})
	salvage_taken = d.get("salvage_taken", [])
	hexes_done = []
	for c in d.get("hexes_done", []):
		hexes_done.append(int(c))
	hex_frac = {}
	var hf: Dictionary = d.get("hex_frac", {})
	for k in hf:
		hex_frac[int(k)] = float(hf[k])
	hex_work = {}
	var hw: Dictionary = d.get("hex_work", {})
	for k in hw:
		hex_work[int(k)] = float(hw[k])
	dirt.swept_cells.clear()
	for c in hexes_done:
		dirt.swept_cells[int(c)] = true
	landmark_progress = d.get("landmark_progress", {})
	stats = d.get("stats", {})
	player = d.get("player", player)
	started_at = int(d.get("started_at", 0))
	for k in d.get("clean_chunks", []):
		if k is Array and k.size() == 3:
			dirt.clean[Vector3i(int(k[0]), int(k[1]), int(k[2]))] = true
	battery = clampf(float(d.get("battery", battery_capacity())), 0.0, battery_capacity())
	_emit_all()


## Upgrade older save formats in place. Each version bump adds a step here.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 1:
		v = 1
	if v < 2:
		_migrate_to_sphere(d)
	if v < 3:
		_migrate_automation(d)
	d["version"] = SAVE_VERSION
	return d


## Version 3 automation has no power, links or storage. Collectors stay (Mk I); drone
## bays become Drone Hangars and rover garages Hexagon Cleaning Stations (Mk I); the
## rest is removed and fully refunded, along with any dust still held in machines.
static func _migrate_automation(d: Dictionary) -> void:
	var keep := {"dust_collector": "dust_collector", "drone_bay": "drone_hangar", "rover_garage": "hex_station"}
	var refund := 0.0
	var out := []
	for m in d.get("machines", []):
		if not (m is Dictionary):
			continue
		var old: Dictionary = GameData.machine(str(m.get("id", "")))
		refund += (float(m.get("v", 0.0)) + float(m.get("rv", 0.0))) * float(GameData.economy["base_dust_price"])
		if keep.has(m["id"]):
			var nid: String = keep[m["id"]]
			out.append({"uid": m["uid"], "id": nid, "pos": m["pos"], "yaw": m.get("yaw", 0.0), "tier": 1,
				"spent": float(GameData.machine(nid).get("price", 0)), "produced": float(m.get("produced", 0.0)),
				"earned": 0.0, "rate": 0.0, "status": "Starting", "phase": 0.0, "target": -1})
		else:
			refund += float(OLD_PRICES.get(str(m.get("id", "")), old.get("price", 0)))
	d["machines"] = out
	d["credits"] = float(d.get("credits", 0.0)) + refund
	if refund > 0.0:
		var fl: Dictionary = d.get("flags", {})
		fl["automation_refund"] = refund
		d["flags"] = fl


## Prices of machines that were retired with the version 3 automation (for refunds).
const OLD_PRICES := {"solar_array": 3500, "storage_container": 2800, "conveyor": 450,
	"charging_station": 7500, "processor": 32000, "shipping_depot": 21000}


func hex_world_fraction() -> float:
	var n := HexGrid.count()
	if n == 0:
		return 0.0
	var sum := float(hexes_done.size())
	for k in hex_frac:
		if not hexes_done.has(k):
			sum += AutomationSim.hex_progress(k)
	for k in hex_work:
		if not hexes_done.has(k) and not hex_frac.has(k):
			sum += AutomationSim.hex_progress(k)
	return minf(sum / n, 1.0 if hexes_done.size() >= n else 0.999)


## Version 1 saves were made on the flat Moon: positions were (x, height, z). The round
## Moon keeps the same layout as a map around the base (see TerrainGen.map_to_dir), so
## everything is moved to the same spot on the sphere, standing on the ground. Headings
## stay as they were (yaw is measured in the same local map directions). Cleaned ground
## is carried over by DirtMap when it reads the old dust file.
static func _migrate_to_sphere(d: Dictionary) -> void:
	TerrainGen.setup()
	var on_ground := func(a, lift: float) -> Array:
		if not (a is Array) or a.size() < 3:
			var sp := LunarBase.spawn_point()
			return [sp.x, sp.y, sp.z]
		var p := TerrainGen.surface(TerrainGen.map_to_dir(float(a[0]), float(a[2])), lift)
		return [p.x, p.y, p.z]
	var pl: Dictionary = d.get("player", {})
	if not pl.is_empty():
		pl["pos"] = on_ground.call(pl.get("pos"), 0.3)
	for veh in d.get("vehicles", []):
		if veh is Dictionary:
			veh["pos"] = on_ground.call(veh.get("pos"), 1.2)
	for m in d.get("machines", []):
		if not (m is Dictionary):
			continue
		m["pos"] = on_ground.call(m.get("pos"), 0.0)
		if m.has("agent"):
			var a: Dictionary = m["agent"]
			var hp := TerrainGen.surface(AutomationSim.v3(m["pos"]), 1.0)
			a["p"] = [hp.x, hp.y, hp.z]
			a["t"] = m["pos"].duplicate()
			a["s"] = "idle"
	# Clean-chunk keys were flat-grid keys; the sphere's are recounted as chunks load.
	d.erase("clean_chunks")


func _emit_all() -> void:
	credits_changed.emit(credits)
	tank_changed.emit(tank_dust, tank_capacity())
	battery_changed.emit(battery, battery_capacity())
	tool_changed.emit(equipped)
	inventory_changed.emit()


# ---------------------------------------------------------------- statistics

func stat(key: String) -> float:
	match key:
		"machines_count":
			return float(machines.size())
		"vehicles_count":
			return float(vehicles.size())
		"tools_count":
			return float(tools.size())
	return float(stats.get(key, 0.0))


func add_stat(key: String, amount: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func research_bonus(key: String) -> float:
	var total := 0.0
	for id in research_done:
		var r := GameData.research_item(id)
		if r.has("effect"):
			total += float(r["effect"].get(key, 0.0))
	return total


# ------------------------------------------------------------- derived stats

func tank_capacity() -> float:
	var lv: Array = GameData.economy["tank_levels"]
	return float(lv[clampi(tank_level, 0, lv.size() - 1)]["capacity"]) * (1.0 + research_bonus("capacity"))


func battery_capacity() -> float:
	var lv: Array = GameData.economy["battery_levels"]
	return float(lv[clampi(battery_level, 0, lv.size() - 1)]["capacity"]) * (1.0 + research_bonus("battery"))


func move_stats() -> Dictionary:
	var lv: Array = GameData.economy["boots_levels"]
	var b: Dictionary = lv[clampi(boots_level, 0, lv.size() - 1)]
	var k := 1.0 + research_bonus("move")
	return {"walk": b["walk"] * k, "sprint": b["sprint"] * k, "jump": b["jump"] * (1.0 + research_bonus("move") * 0.5),
		"jetpack": research_bonus("jetpack") > 0.0, "hover": has_hover_pack()}


const HOVER_PACK_COST := 250000


## Sustained hovering (and cleaning from up to 6 m in the air). Drains the suit battery.
func has_hover_pack() -> bool:
	return bool(flags.get("hover_pack", false))


func buy_hover_pack() -> bool:
	if has_hover_pack() or not spend(HOVER_PACK_COST):
		return false
	flags["hover_pack"] = true
	Audio.play("upgrade")
	notify.emit("Hover Pack fitted: hold JUMP in the air to hover (uses suit battery)", "upgrade")
	inventory_changed.emit()
	return true


func dust_price() -> float:
	return float(GameData.economy["base_dust_price"]) * (1.0 + research_bonus("price"))


func tool_level(id: String) -> int:
	return int(tools.get(id, -1))


## Effective stats of a tool including upgrades and research.
func tool_stats(id: String) -> Dictionary:
	var base := GameData.tool(id)
	if base.is_empty():
		return {}
	var s := base.duplicate()
	var lvl := maxi(tool_level(id), 0)
	var up: Dictionary = GameData.economy["tool_upgrade"]
	var sk := (1.0 + lvl * float(up["strength_per_level"])) * (1.0 + research_bonus("strength"))
	var rk := 1.0 + lvl * float(up["radius_per_level"])
	s["strength"] = float(base["strength"]) * sk
	s["radius"] = float(base.get("radius", 0.5)) * rk
	s["half_width"] = float(base.get("half_width", 0.5)) * rk
	s["half_length"] = float(base.get("half_length", 0.5)) * (1.0 + lvl * float(up["radius_per_level"]) * 0.5)
	s["level"] = lvl
	return s


func tool_upgrade_cost(id: String) -> int:
	var up: Dictionary = GameData.economy["tool_upgrade"]
	var lvl := maxi(tool_level(id), 0)
	var price := float(GameData.tool(id).get("price", 0))
	var base := maxf(price * float(up["cost_factor"]), float(up["min_cost"]))
	return int(round(base * pow(float(up["cost_growth"]), lvl)))


func max_tool_level() -> int:
	var m := 0
	for k in tools:
		m = maxi(m, int(tools[k]))
	return m


func region_info(index: int) -> Dictionary:
	return GameData.region(index)


func region_unlocked(index: int) -> bool:
	return index >= 0 and index < regions.size() and regions[index]


# ------------------------------------------------------------------- economy

func add_credits(amount: float, earned := true) -> void:
	credits += amount
	if earned and amount > 0.0:
		add_stat("credits_earned", amount)
	credits_changed.emit(credits)


func can_afford(cost: float) -> bool:
	return credits + 0.001 >= cost


func spend(cost: float) -> bool:
	if not can_afford(cost):
		notify.emit("Not enough credits", "error")
		return false
	credits -= cost
	credits_changed.emit(credits)
	return true


func tank_space() -> float:
	return maxf(tank_capacity() - tank_dust, 0.0)


## Adds dust to the suit tank. Returns the amount accepted.
func add_dust(amount: float, value_per_unit: float) -> float:
	var accepted := minf(amount, tank_space())
	if accepted <= 0.0:
		return 0.0
	tank_dust += accepted
	tank_value += accepted * value_per_unit
	add_stat("dust_collected", accepted)
	tank_changed.emit(tank_dust, tank_capacity())
	return accepted


## Records cleaning statistics (area in m2 of fully-cleaned equivalent).
func record_clean(area_m2: float) -> void:
	add_stat("m2_cleaned", area_m2)
	rp += area_m2 * float(GameData.economy["rp_per_m2"])


## Sell a quantity with a known total base value. Returns credits earned.
func sell(amount: float, value: float) -> float:
	if amount <= 0.0:
		return 0.0
	var earned := value * dust_price()
	add_credits(earned)
	add_stat("dust_sold", amount)
	add_stat("sell_count", 1)
	sold.emit(amount, earned)
	return earned


func sell_tank() -> float:
	if tank_dust <= 0.01:
		notify.emit("Your dust tank is empty", "info")
		return 0.0
	var earned := sell(tank_dust, tank_value)
	tank_dust = 0.0
	tank_value = 0.0
	tank_changed.emit(tank_dust, tank_capacity())
	return earned


func use_battery(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if battery <= 0.0:
		return false
	battery = maxf(battery - amount, 0.0)
	battery_changed.emit(battery, battery_capacity())
	return battery > 0.0


func charge_battery(amount: float) -> void:
	var cap := battery_capacity()
	if battery >= cap:
		return
	battery = minf(battery + amount * (1.0 + research_bonus("battery")), cap)
	battery_changed.emit(battery, cap)


# ----------------------------------------------------------------- purchases

func buy_tool(id: String) -> bool:
	if tools.has(id):
		return false
	var t := GameData.tool(id)
	if t.is_empty() or not spend(float(t["price"])):
		return false
	tools[id] = 0
	equip(id)
	Audio.play("purchase")
	notify.emit("Purchased " + t["name"], "purchase")
	inventory_changed.emit()
	return true


func upgrade_tool(id: String) -> bool:
	if not tools.has(id):
		return false
	var up: Dictionary = GameData.economy["tool_upgrade"]
	if tools[id] >= int(up["max_level"]):
		return false
	if not spend(tool_upgrade_cost(id)):
		return false
	tools[id] += 1
	Audio.play("upgrade")
	notify.emit("%s upgraded to level %d" % [GameData.tool(id)["name"], tools[id]], "upgrade")
	inventory_changed.emit()
	tool_changed.emit(equipped)
	return true


func equip(id: String) -> void:
	if not tools.has(id):
		return
	equipped = id
	tool_changed.emit(id)


func cycle_tool(dir := 1) -> void:
	var owned: Array = []
	for t in GameData.tools:
		if tools.has(t["id"]):
			owned.append(t["id"])
	if owned.size() <= 1:
		return
	var i := owned.find(equipped)
	equip(owned[(i + dir + owned.size()) % owned.size()])


func _level_purchase(levels_key: String, current: int) -> int:
	var lv: Array = GameData.economy[levels_key]
	if current + 1 >= lv.size():
		return -1
	return int(lv[current + 1]["cost"])


func next_tank_cost() -> int:
	return _level_purchase("tank_levels", tank_level)


func next_battery_cost() -> int:
	return _level_purchase("battery_levels", battery_level)


func next_boots_cost() -> int:
	return _level_purchase("boots_levels", boots_level)


func buy_tank_upgrade() -> bool:
	var c := next_tank_cost()
	if c < 0 or not spend(c):
		return false
	tank_level += 1
	Audio.play("upgrade")
	notify.emit("Dust tank expanded to %d" % int(tank_capacity()), "upgrade")
	tank_changed.emit(tank_dust, tank_capacity())
	inventory_changed.emit()
	return true


func buy_battery_upgrade() -> bool:
	var c := next_battery_cost()
	if c < 0 or not spend(c):
		return false
	battery_level += 1
	battery = battery_capacity()
	Audio.play("upgrade")
	notify.emit("Suit battery upgraded", "upgrade")
	battery_changed.emit(battery, battery_capacity())
	inventory_changed.emit()
	return true


func buy_boots_upgrade() -> bool:
	var c := next_boots_cost()
	if c < 0 or not spend(c):
		return false
	boots_level += 1
	Audio.play("upgrade")
	notify.emit("Moon boots upgraded", "upgrade")
	inventory_changed.emit()
	return true


func permit_requirement_met(index: int) -> bool:
	var req: String = GameData.region(index).get("requires", "")
	return req == "" or missions_done.has(req)


func buy_permit(index: int) -> bool:
	if region_unlocked(index):
		return false
	if not permit_requirement_met(index):
		notify.emit("Complete earlier missions first", "error")
		return false
	var info := GameData.region(index)
	if not spend(float(info["permit"])):
		return false
	regions[index] = true
	Audio.play("mission")
	notify.emit(info["name"] + " unlocked!", "mission")
	inventory_changed.emit()
	return true


func owns_vehicle(id: String) -> bool:
	for v in vehicles:
		if v["id"] == id:
			return true
	return false


func buy_vehicle(id: String) -> bool:
	if owns_vehicle(id):
		return false
	var info := GameData.vehicle(id)
	if info.is_empty() or not spend(float(info["price"])):
		return false
	var slot := vehicles.size()
	vehicles.append({"id": id, "engine": 0, "storage_lvl": 0, "clean_lvl": 0,
		"pos": LunarBase.at_array(Vector3(-18.0, 1.5, 10.0 + slot * 7.0)), "yaw": PI * 0.5, "dust": 0.0, "value": 0.0, "new": true})
	Audio.play("purchase")
	notify.emit(info["name"] + " delivered to the Vehicle Bay", "purchase")
	vehicles_changed.emit()
	inventory_changed.emit()
	return true


func vehicle_stats(index: int) -> Dictionary:
	var v: Dictionary = vehicles[index]
	var info := GameData.vehicle(v["id"]).duplicate()
	var up := GameData.vehicle_upgrade
	info["max_speed"] = float(info["max_speed"]) * (1.0 + int(v["engine"]) * float(up["speed_per_level"]))
	info["engine"] = float(info["engine"]) * (1.0 + int(v["engine"]) * float(up["speed_per_level"]) * 1.5)
	info["storage"] = float(info["storage"]) * (1.0 + int(v["storage_lvl"]) * float(up["storage_per_level"])) * (1.0 + research_bonus("capacity"))
	info["clean_strength"] = float(info["clean_strength"]) * (1.0 + int(v["clean_lvl"]) * float(up["clean_per_level"])) * (1.0 + research_bonus("strength"))
	return info


func vehicle_upgrade_cost(index: int, kind: String) -> int:
	var v: Dictionary = vehicles[index]
	var up := GameData.vehicle_upgrade
	var lvl := int(v.get(kind, 0))
	if lvl >= int(up["max_level"]):
		return -1
	var price := float(GameData.vehicle(v["id"])["price"])
	return int(round(price * float(up["cost_factor"]) * pow(float(up["cost_growth"]), lvl)))


func upgrade_vehicle(index: int, kind: String) -> bool:
	var c := vehicle_upgrade_cost(index, kind)
	if c < 0 or not spend(c):
		return false
	vehicles[index][kind] = int(vehicles[index].get(kind, 0)) + 1
	Audio.play("upgrade")
	notify.emit("Vehicle upgraded", "upgrade")
	vehicles_changed.emit()
	inventory_changed.emit()
	return true


func research_available(id: String) -> bool:
	if research_done.has(id):
		return false
	for req in GameData.research_item(id).get("requires", []):
		if not research_done.has(req):
			return false
	return true


func do_research(id: String) -> bool:
	var r := GameData.research_item(id)
	if r.is_empty() or not research_available(id):
		return false
	if rp + 0.001 < float(r["rp"]):
		notify.emit("Not enough research points", "error")
		return false
	if not spend(float(r["credits"])):
		return false
	rp -= float(r["rp"])
	research_done.append(id)
	Audio.play("upgrade")
	notify.emit("Research complete: " + r["name"], "upgrade")
	tank_changed.emit(tank_dust, tank_capacity())
	battery_changed.emit(battery, battery_capacity())
	inventory_changed.emit()
	return true


func add_salvage(id: String, credits_amount: float, rp_amount: float) -> void:
	if salvage_taken.has(id):
		return
	salvage_taken.append(id)
	add_stat("salvage", 1)
	add_credits(credits_amount)
	rp += rp_amount
	Audio.play("pickup")
	notify.emit("Salvage recovered  +%s CR  +%d RP" % [fmt(credits_amount), int(rp_amount)], "purchase")


# ------------------------------------------------------------------ missions

func mission_progress(m: Dictionary) -> Vector2:
	match m["type"]:
		"stat":
			return Vector2(stat(m["stat"]), float(m["value"]))
		"credits":
			return Vector2(credits, float(m["value"]))
		"own_tool":
			return Vector2(1.0 if tools.has(m["tool"]) else 0.0, 1.0)
		"tool_level":
			return Vector2(max_tool_level(), float(m["value"]))
		"tank_level":
			return Vector2(tank_level, float(m["value"]))
		"region":
			return Vector2(1.0 if region_unlocked(GameData.region_index(m["region"])) else 0.0, 1.0)
		"own_vehicle":
			if m["vehicle"] == "any":
				return Vector2(mini(vehicles.size(), 1), 1.0)
			return Vector2(1.0 if owns_vehicle(m["vehicle"]) else 0.0, 1.0)
		"tier":
			var best := 0
			for mc in machines:
				if mc["id"] == m["machine"]:
					best = maxi(best, int(mc.get("tier", 1)))
			return Vector2(best, float(m["value"]))
		"build":
			var n := 0
			for mc in machines:
				if mc["id"] == m["machine"]:
					n += 1
			return Vector2(n, float(m["value"]))
		"landmark":
			return Vector2(float(landmark_progress.get(m["landmark"], 0.0)), float(m["value"]))
		"flag":
			return Vector2(1.0 if flags.get(m["flag"], false) else 0.0, 1.0)
		"research_count":
			return Vector2(research_done.size(), float(m["value"]))
		"world_clean":
			return Vector2(world_clean_fraction(), 1.0)
		"hexes":
			return Vector2(hexes_done.size(), float(m["value"]))
	return Vector2(0, 1)


var _world_frac := -1.0
var _world_frac_t := 0


## Cleaned fraction of the whole Moon (cached for a second; it scans ~900 chunks).
func world_clean_fraction() -> float:
	var now := Time.get_ticks_msec()
	if _world_frac < 0.0 or now - _world_frac_t > 1000:
		_world_frac = maxf(dirt.world_fraction(), hex_world_fraction())
		_world_frac_t = now
	return _world_frac


func current_mission() -> Dictionary:
	for m in GameData.missions:
		if not missions_done.has(m["id"]):
			return m
	return {}


func check_missions() -> void:
	for m in GameData.missions:
		if missions_done.has(m["id"]):
			continue
		var p := mission_progress(m)
		if p.x + 0.0001 >= p.y:
			missions_done.append(m["id"])
			add_credits(float(m.get("reward", 0)))
			rp += float(m.get("rp", 0))
			Audio.play("mission")
			Settings.vibrate(40, 0.6)
			notify.emit("MISSION COMPLETE: %s  +%s CR" % [m["title"], fmt(float(m.get("reward", 0)))], "mission")
			mission_completed.emit(m)
	for a in GameData.achievements:
		if achievements_done.has(a["id"]):
			continue
		var p := mission_progress(a)
		if p.x + 0.0001 >= p.y:
			achievements_done.append(a["id"])
			notify.emit("ACHIEVEMENT: " + a["title"], "achievement")


static func fmt(v: float) -> String:
	var neg := v < 0.0
	var n := int(round(absf(v)))
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func fmt_short(v: float) -> String:
	var a := absf(v)
	if a >= 1e9:
		return "%.2fB" % (v / 1e9)
	if a >= 1e6:
		return "%.2fM" % (v / 1e6)
	if a >= 1e5:
		return "%.0fK" % (v / 1e3)
	return fmt(v)
