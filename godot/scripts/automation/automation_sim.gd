class_name AutomationSim
extends RefCounted
## Lightweight automation economy. Pure data + rules so it can run headless in tests
## and for machines far from the player.
##
## Rules
## - Power: solar arrays (+ the base generator) supply power; every other machine draws
##   power. If demand exceeds supply all machines run at supply/demand efficiency.
## - Networks: machines within link range of each other (conveyors reach further) form a
##   network. The base Dust Exchange is a network node that buys everything instantly.
## - Producers (collectors, drone bays, rover garages) fill an internal buffer, then push
##   it into network storage (storage containers, depot hoppers) or straight to the base.
## - Processors refine raw dust stored in their network (3x value).
## - Shipping depots sell the whole network's storage every interval.
## - Drones and rovers need a Charging Station within 45 m of their home.

const BASE_UID := 0
const BASE_POS := Vector3(11, 0, -3)
const BASE_LINK := 14.0
const NEAR_DISTANCE := 150.0

var dirt: DirtMap
var networks: Array = []        # Array of Array[uid]
var net_of := {}                # uid -> network index
var edges: Array = []           # [[uid_a, uid_b]] spanning-tree links (for conveyor visuals)
var supply := 0.0
var demand := 0.0
var efficiency := 1.0
var revenue_rate := 0.0         # credits / minute (smoothed)
var production_rate := 0.0      # dust / minute (smoothed)
var ship_events: Array = []     # uids that launched a rocket this tick
var _revenue_acc := 0.0
var _prod_acc := 0.0
var _time := 0.0
var _by_uid := {}


func _init(d: DirtMap) -> void:
	dirt = d


static func v3(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func machines() -> Array:
	return GameState.machines


func get_machine(uid: int) -> Dictionary:
	return _by_uid.get(uid, {})


func info(m: Dictionary) -> Dictionary:
	return GameData.machine(m["id"])


func link_range(m: Dictionary) -> float:
	return float(info(m).get("link", 0)) * (1.0 + GameState.research_bonus("link"))


func storage_capacity(m: Dictionary) -> float:
	match m["id"]:
		"storage_container":
			return float(info(m).get("capacity", 6000)) * (1.0 + GameState.research_bonus("capacity"))
		"shipping_depot":
			return 1500.0
	return 0.0


func buffer_capacity(m: Dictionary) -> float:
	return float(info(m).get("buffer", 0))


func stored(m: Dictionary) -> float:
	return float(m.get("d", 0.0)) + float(m.get("rd", 0.0))


# ------------------------------------------------------------------ building

func can_place(id: String, pos: Vector3) -> String:
	var reg := TerrainGen.region_at(pos.x, pos.z)
	if not GameState.region_unlocked(reg):
		return "Region locked"
	if Vector2(pos.x, pos.z + 2.0).length() < 31.0:
		return "Too close to the base"
	if Vector2(pos.x, pos.z).length() > TerrainGen.WORLD_RADIUS - 60.0:
		return "Too far out"
	if TerrainGen.normal(pos.x, pos.z).y < 0.82:
		return "Ground too steep"
	for m in machines():
		if v3(m["pos"]).distance_to(pos) < 4.0:
			return "Too close to another machine"
	return ""


func add_machine(id: String, pos: Vector3, yaw: float) -> Dictionary:
	var m := {"uid": GameState.next_uid, "id": id, "pos": arr(pos), "yaw": yaw,
		"d": 0.0, "v": 0.0, "rd": 0.0, "rv": 0.0, "produced": 0.0, "rate": 0.0, "status": "Starting",
		"ship_t": 0.0, "phase": 0.0}
	GameState.next_uid += 1
	if id == "drone_bay" or id == "rover_garage":
		m["agent"] = {"p": arr(pos + Vector3(0, 1, 0)), "s": "idle", "t": [pos.x, pos.z], "load": 0.0, "val": 0.0, "bat": 100.0, "wait": 0.0, "n": 0, "clean_t": 0.0}
	machines().append(m)
	rebuild()
	return m


func remove_machine(uid: int) -> float:
	var list := machines()
	for i in list.size():
		if int(list[i]["uid"]) == uid:
			var m: Dictionary = list[i]
			var refund := float(info(m).get("price", 0)) * 0.5
			list.remove_at(i)
			rebuild()
			return refund
	return 0.0


## Recompute power and network connectivity. Call after any machine changes.
func rebuild() -> void:
	_by_uid.clear()
	var nodes := []
	for m in machines():
		_by_uid[int(m["uid"])] = m
		if link_range(m) > 0.0:
			nodes.append(m)
	# Union-find over nodes (+ virtual base node)
	var uids := [BASE_UID]
	var pos := [BASE_POS]
	var ranges := [BASE_LINK]
	for m in nodes:
		uids.append(int(m["uid"]))
		pos.append(v3(m["pos"]))
		ranges.append(link_range(m))
	var n := uids.size()
	var parent := range(n)
	var candidate_edges := []
	for i in n:
		for j in range(i + 1, n):
			var d: float = (pos[i] as Vector3).distance_to(pos[j])
			if d <= maxf(ranges[i], ranges[j]):
				candidate_edges.append([d, i, j])
	candidate_edges.sort_custom(func(a, b): return a[0] < b[0])
	edges.clear()
	for e in candidate_edges:
		var a := _find(parent, e[1])
		var b := _find(parent, e[2])
		if a != b:
			parent[a] = b
			edges.append([uids[e[1]], uids[e[2]]])
	var groups := {}
	for i in n:
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(uids[i])
	networks.clear()
	net_of.clear()
	for r in groups:
		var g: Array = groups[r]
		if g.size() == 1 and g[0] == BASE_UID:
			continue
		var idx := networks.size()
		networks.append(g)
		for u in g:
			net_of[u] = idx
	_compute_power()


func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _compute_power() -> void:
	supply = float(GameData.economy.get("base_power", 6))
	demand = 0.0
	for m in machines():
		var p := float(info(m).get("power", 0))
		if p < 0.0:
			supply += -p * (1.0 + GameState.research_bonus("solar"))
		else:
			demand += p
	efficiency = 1.0 if demand <= 0.0 else clampf(supply / demand, 0.0, 1.0)


func has_charger(home: Vector3) -> bool:
	for m in machines():
		if m["id"] == "charging_station" and v3(m["pos"]).distance_to(home) <= float(info(m).get("range", 45.0)):
			return true
	return false


# ---------------------------------------------------------------------- tick

## Advance the simulation. near_uids are agents simulated per-frame elsewhere.
func tick(dt: float, near_uids := {}) -> void:
	_time += dt
	ship_events.clear()
	_compute_power()
	for m in machines():
		match m["id"]:
			"dust_collector":
				_collector(m, dt)
			"drone_bay", "rover_garage":
				if not near_uids.has(int(m["uid"])):
					update_agent(m, dt)
	for idx in networks.size():
		_network(networks[idx], dt)
	# Machines not on any network keep their buffers (player can collect manually).
	for m in machines():
		var r := float(m.get("rate_acc", 0.0))
		m["rate"] = lerpf(float(m.get("rate", 0.0)), r / dt * 60.0, 0.15)
		m["rate_acc"] = 0.0
	revenue_rate = lerpf(revenue_rate, _revenue_acc / dt * 60.0, 0.1)
	production_rate = lerpf(production_rate, _prod_acc / dt * 60.0, 0.1)
	_revenue_acc = 0.0
	_prod_acc = 0.0


func _produce(m: Dictionary, units: float, value_per_unit: float) -> float:
	var space := buffer_capacity(m) - float(m.get("d", 0.0))
	var a := minf(units, maxf(space, 0.0))
	if a <= 0.0:
		return 0.0
	m["d"] = float(m.get("d", 0.0)) + a
	m["v"] = float(m.get("v", 0.0)) + a * value_per_unit
	m["produced"] = float(m.get("produced", 0.0)) + a
	m["rate_acc"] = float(m.get("rate_acc", 0.0)) + a
	GameState.add_stat("auto_dust", a)
	_prod_acc += a
	return a


func _collector(m: Dictionary, dt: float) -> void:
	var i := info(m)
	if efficiency <= 0.0:
		m["status"] = "No power"
		return
	if float(m.get("d", 0.0)) >= buffer_capacity(m) - 0.01:
		m["status"] = "Buffer full - link storage"
		return
	var p := v3(m["pos"])
	var rinfo := GameData.region(TerrainGen.region_at(p.x, p.z))
	var thick := TerrainGen.thickness(p.x, p.z, float(rinfo["thickness"]))
	var R := float(i.get("radius", 6.0))
	# A sweeping spiral spot cleans the surface around the collector.
	m["phase"] = float(m.get("phase", 0.0)) + dt
	var ph: float = m["phase"]
	var rho := 0.8 + (R - 1.2) * (0.5 + 0.5 * sin(ph * 0.11))
	var spot := Vector3(p.x + cos(ph * 0.9) * rho, 0, p.z + sin(ph * 0.9) * rho)
	var dpm := float(GameData.economy["dust_per_m2"]) * thick
	var budget := (buffer_capacity(m) - float(m.get("d", 0.0))) / dpm
	var area := dirt.stamp(DirtMap.Shape.ROUND, spot.x, spot.z, 1.2, 0.0, 0.0, 1.6 * efficiency * dt, budget)
	var units := area * dpm
	var deep := float(i.get("deep_rate", 1.0)) * (1.0 + GameState.research_bonus("deep")) * efficiency * dt
	if units < deep:
		m["status"] = "Deep extraction"
		units = deep
	else:
		m["status"] = "Cleaning surface"
	_produce(m, units, float(rinfo["dust_mult"]))


## Drone / rover behaviour. dt may be a full second for remote simulation.
func update_agent(m: Dictionary, dt: float) -> void:
	var a: Dictionary = m["agent"]
	var i := info(m)
	var home := v3(m["pos"])
	var is_drone: bool = m["id"] == "drone_bay"
	var bonus := 1.0 + GameState.research_bonus("drone")
	var speed := float(i.get("speed", 5.0)) * bonus
	var radius := float(i.get("radius", 1.0))
	var strength := float(i.get("strength", 3.0)) * bonus
	var capacity := float(i.get("capacity", 100.0))
	var rng := float(i.get("range", 35.0))
	var p := v3(a["p"])
	if efficiency <= 0.0:
		m["status"] = "No power"
		return
	if not has_charger(home):
		m["status"] = "Needs a Charging Station within 45 m"
		a["s"] = "idle"
		a["p"] = arr(home + Vector3(0, 1, 0))
		return
	match a["s"]:
		"idle":
			if float(a["load"]) > 0.0:
				var moved := _produce(m, float(a["load"]), float(a["val"]) / maxf(float(a["load"]), 0.0001))
				a["val"] = float(a["val"]) * (1.0 - moved / maxf(float(a["load"]), 0.0001))
				a["load"] = float(a["load"]) - moved
			a["bat"] = minf(float(a["bat"]) + 25.0 * dt, 100.0)
			a["wait"] = float(a["wait"]) - dt
			if float(a["load"]) > 0.01:
				m["status"] = "Waiting - buffer full"
			elif float(a["bat"]) >= 99.0 and float(a["wait"]) <= 0.0:
				var t := _pick_target(m, home, rng)
				if t == Vector3.INF:
					m["status"] = "Area clean - move it somewhere dusty"
					a["wait"] = 8.0
				else:
					a["t"] = [t.x, t.z]
					a["s"] = "out"
					m["status"] = "Flying out" if is_drone else "Driving out"
			else:
				m["status"] = "Charging"
		"out":
			var t := Vector3(a["t"][0], 0, a["t"][1])
			p = _move(p, t, speed * dt, is_drone)
			a["bat"] = float(a["bat"]) - dt * 1.5
			if Vector2(p.x - t.x, p.z - t.z).length() < 0.6:
				a["s"] = "clean"
				a["clean_t"] = 0.0
		"clean":
			a["clean_t"] = float(a["clean_t"]) + dt
			var ct: float = a["clean_t"]
			var t := Vector3(a["t"][0], 0, a["t"][1])
			var orbit := 1.0 + fmod(ct * 0.35, 2.5)
			var goal := t + Vector3(cos(ct * 1.3) * orbit, 0, sin(ct * 1.3) * orbit)
			p = _move(p, goal, speed * 0.4 * dt, is_drone)
			var rinfo := GameData.region(TerrainGen.region_at(p.x, p.z))
			var dpm := float(GameData.economy["dust_per_m2"]) * TerrainGen.thickness(p.x, p.z, float(rinfo["thickness"]))
			var budget := (capacity - float(a["load"])) / dpm
			var area := dirt.stamp(DirtMap.Shape.ROUND, p.x, p.z, radius, 0.0, 0.0, strength * efficiency * dt, budget)
			var units := area * dpm
			a["load"] = float(a["load"]) + units
			a["val"] = float(a["val"]) + units * float(rinfo["dust_mult"])
			a["bat"] = float(a["bat"]) - dt * 3.0
			m["status"] = "Cleaning"
			if float(a["load"]) >= capacity - 0.01 or float(a["bat"]) < 20.0 or ct > 40.0:
				a["s"] = "return"
			elif ct > 4.0 and units < 0.05 * dt:
				a["s"] = "return"
		"return":
			p = _move(p, home, speed * dt, is_drone)
			a["bat"] = float(a["bat"]) - dt * 1.5
			m["status"] = "Returning"
			if Vector2(p.x - home.x, p.z - home.z).length() < 0.8:
				a["s"] = "idle"
				a["wait"] = 1.0
	a["p"] = arr(p)


func _move(p: Vector3, target: Vector3, step: float, flying: bool) -> Vector3:
	var flat := Vector2(target.x - p.x, target.z - p.z)
	var d := flat.length()
	var np := p
	if d > 0.001:
		var k := minf(step / d, 1.0)
		np.x += flat.x * k
		np.z += flat.y * k
	var g := TerrainGen.height(np.x, np.z)
	np.y = g + (2.6 if flying else 0.0)
	return np


func _pick_target(m: Dictionary, home: Vector3, rng: float) -> Vector3:
	var a: Dictionary = m["agent"]
	for attempt in 10:
		a["n"] = int(a["n"]) + 1
		var n: int = a["n"]
		var ang := TerrainGen.hashf(int(m["uid"]) * 7 + n, n * 3, 5151) * TAU
		var dist := 4.0 + TerrainGen.hashf(n, int(m["uid"]), 5353) * (rng - 4.0)
		var t := home + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if not GameState.region_unlocked(TerrainGen.region_at(t.x, t.z)):
			continue
		if Vector2(t.x, t.z + 2.0).length() < 30.0:
			continue
		if dirt.sample(t.x, t.z) > 0.35:
			return t
	return Vector3.INF


func _network(net: Array, dt: float) -> void:
	var containers := []
	var producers := []
	var processors := []
	var depots := []
	var has_base := false
	for uid in net:
		if uid == BASE_UID:
			has_base = true
			continue
		var m: Dictionary = _by_uid.get(uid, {})
		if m.is_empty():
			continue
		match m["id"]:
			"storage_container":
				containers.append(m)
			"shipping_depot":
				containers.append(m)
				depots.append(m)
			"dust_collector", "drone_bay", "rover_garage":
				producers.append(m)
			"processor":
				processors.append(m)
	# 1) producers -> base (instant sale) or containers
	for p in producers:
		var d := float(p.get("d", 0.0))
		if d <= 0.0:
			continue
		if has_base:
			_sell(d, float(p.get("v", 0.0)))
			p["d"] = 0.0
			p["v"] = 0.0
			continue
		for c in containers:
			var space := storage_capacity(c) - stored(c)
			if space <= 0.0:
				continue
			var mv := minf(space, float(p["d"]))
			var frac := mv / float(p["d"])
			var val := float(p["v"]) * frac
			c["d"] = float(c.get("d", 0.0)) + mv
			c["v"] = float(c.get("v", 0.0)) + val
			p["d"] = float(p["d"]) - mv
			p["v"] = float(p["v"]) - val
			if float(p["d"]) <= 0.0001:
				break
	# 2) processors refine raw dust inside containers
	for pr in processors:
		if efficiency <= 0.0:
			pr["status"] = "No power"
			continue
		var budget := float(info(pr).get("rate", 8.0)) * (1.0 + GameState.research_bonus("refine")) * efficiency * dt
		var done := 0.0
		for c in containers:
			if budget <= 0.0:
				break
			var raw := float(c.get("d", 0.0))
			if raw <= 0.0:
				continue
			var mv := minf(raw, budget)
			var val := float(c["v"]) * mv / raw
			c["d"] = raw - mv
			c["v"] = float(c["v"]) - val
			c["rd"] = float(c.get("rd", 0.0)) + mv
			c["rv"] = float(c.get("rv", 0.0)) + val * float(GameData.economy["refined_multiplier"])
			budget -= mv
			done += mv
		pr["rate_acc"] = float(pr.get("rate_acc", 0.0)) + done
		pr["produced"] = float(pr.get("produced", 0.0)) + done
		pr["status"] = "Refining" if done > 0.0 else ("No storage linked" if containers.is_empty() else "Waiting for dust")
	# 3) base flushes storage instantly; depots launch on a timer
	if has_base:
		for c in containers:
			_flush(c)
			c["status"] = "Linked to base exchange"
	else:
		var interval := 30.0 / (1.0 + GameState.research_bonus("ship"))
		for dp in depots:
			dp["ship_t"] = float(dp.get("ship_t", 0.0)) + dt * efficiency
			dp["status"] = "Next launch in %ds" % int(maxf(interval - float(dp["ship_t"]), 0.0))
			if float(dp["ship_t"]) >= interval:
				dp["ship_t"] = 0.0
				var total := 0.0
				for c in containers:
					total += stored(c)
					_flush(c)
				if total > 0.0:
					ship_events.append(int(dp["uid"]))
		for c in containers:
			if c["id"] == "storage_container":
				c["status"] = "Stored %d / %d" % [int(stored(c)), int(storage_capacity(c))]


func _flush(c: Dictionary) -> void:
	var amount := stored(c)
	if amount <= 0.0:
		return
	_sell(amount, float(c.get("v", 0.0)) + float(c.get("rv", 0.0)))
	c["d"] = 0.0
	c["v"] = 0.0
	c["rd"] = 0.0
	c["rv"] = 0.0


func _sell(amount: float, value: float) -> void:
	var credits := value * GameState.dust_price()
	GameState.add_credits(credits)
	GameState.add_stat("auto_revenue", credits)
	_revenue_acc += credits


## Move a machine's stored dust into the player's tank. Returns amount moved.
func collect_into_tank(m: Dictionary) -> float:
	var space := GameState.tank_space()
	var total := 0.0
	for k in [["d", "v"], ["rd", "rv"]]:
		var have := float(m.get(k[0], 0.0))
		if have <= 0.0 or space <= 0.0:
			continue
		var mv := minf(have, space)
		var val := float(m.get(k[1], 0.0)) * mv / have
		GameState.tank_dust += mv
		GameState.tank_value += val
		m[k[0]] = have - mv
		m[k[1]] = float(m.get(k[1], 0.0)) - val
		space -= mv
		total += mv
	GameState.tank_changed.emit(GameState.tank_dust, GameState.tank_capacity())
	return total
