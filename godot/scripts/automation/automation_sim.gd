class_name AutomationSim
extends RefCounted
## Automation economy. Pure data + rules so it can run headless in tests and for machines
## far from the player.
##
## Machines just work wherever they are placed: no power, links or storage. Whatever
## they clean is sold straight away. Every machine has tiers Mk I-V that multiply what
## it does, so automation keeps up with the rest of the game.
## - Dust Collector: sweeps the ground in a circle around itself and extracts a steady
##   trickle of deep regolith.
## - Hexagon Cleaning Station: clears a whole hexagon (first the one it stands in),
##   then moves on to the nearest unfinished hexagon by itself.
## - Drone Hangar: sends its drone squad to a hexagon picked on the map (or the nearest
##   unfinished one) - anywhere on the Moon.

const MAX_TIER := 5
const TIER_MULT := 1.8          # each tier multiplies output by this
const NEAR_DISTANCE := 150.0
const AWAY_CAP := 4.0 * 3600.0   # machines work for at most this long while the game is closed
const AWAY_SPEED := 0.5          # ...at half speed

static var BASE_POS := LunarBase.at(LunarBase.EXCHANGE_POS)
static var BASE_CENTER := LunarBase.at(Vector3(0, 0, -2))

var dirt: DirtMap
var revenue_rate := 0.0         # credits / minute (smoothed)
var production_rate := 0.0      # dust / minute (smoothed)
## Called with a hexagon index when machines finish clearing it.
var on_hex_cleared: Callable
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


## Distance between two points along the ground (ignoring height).
static func flat_dist(a: Vector3, b: Vector3) -> float:
	var d := b - a
	var up := a.normalized()
	return (d - up * d.dot(up)).length()


func machines() -> Array:
	return GameState.machines


func get_machine(uid: int) -> Dictionary:
	return _by_uid.get(uid, {})


func info(m: Dictionary) -> Dictionary:
	return GameData.machine(m["id"])


# ------------------------------------------------------------------ tiers

static func tier(m: Dictionary) -> int:
	return clampi(int(m.get("tier", 1)), 1, MAX_TIER)


static func tier_name(t: int) -> String:
	return "Mk " + ["I", "II", "III", "IV", "V"][clampi(t, 1, MAX_TIER) - 1]


static func tier_mult(m: Dictionary) -> float:
	return pow(TIER_MULT, tier(m) - 1)


## Credits to take a machine to its next tier, or -1 at the top tier.
func upgrade_cost(m: Dictionary) -> float:
	if tier(m) >= MAX_TIER:
		return -1.0
	return round(float(info(m)["price"]) * 0.9 * pow(2.0, tier(m) - 1))


func upgrade(m: Dictionary) -> bool:
	var c := upgrade_cost(m)
	if c < 0.0 or not GameState.spend(c):
		return false
	m["tier"] = tier(m) + 1
	m["spent"] = float(m.get("spent", info(m)["price"])) + c
	Audio.play("upgrade")
	GameState.notify.emit("%s upgraded to %s" % [info(m)["name"], tier_name(tier(m))], "upgrade")
	GameState.machines_changed.emit()
	return true


## Radius of ground a Dust Collector keeps clean.
func collector_radius(m: Dictionary) -> float:
	return float(info(m).get("radius", 10.0)) * (1.0 + 0.25 * (tier(m) - 1)) * (1.0 + GameState.research_bonus("link"))


## Square metres per second a hexagon machine clears.
func hex_rate(m: Dictionary) -> float:
	return float(info(m).get("rate", 5.0)) * tier_mult(m) * (1.0 + GameState.research_bonus("drone"))


## Area of one hexagon (m2).
static func hex_area() -> float:
	return 4.0 * PI * TerrainGen.RADIUS * TerrainGen.RADIUS / maxf(HexGrid.count(), 1.0)


# ------------------------------------------------------------------ building

func can_place(id: String, pos: Vector3) -> String:
	var reg := TerrainGen.region_of(pos)
	if not GameState.region_unlocked(reg):
		return "Region locked"
	if pos.distance_to(BASE_CENTER) < 31.0:
		return "Too close to the base"
	if TerrainGen.flatness(pos) < 0.82:
		return "Ground too steep"
	for m in machines():
		if v3(m["pos"]).distance_to(pos) < 5.0:
			return "Too close to another machine"
	return ""


func add_machine(id: String, pos: Vector3, yaw: float) -> Dictionary:
	var m := {"uid": GameState.next_uid, "id": id, "pos": arr(pos), "yaw": yaw, "tier": 1,
		"spent": float(GameData.machine(id).get("price", 0)), "produced": 0.0, "earned": 0.0,
		"rate": 0.0, "status": "Starting", "phase": 0.0, "target": -1}
	GameState.next_uid += 1
	machines().append(m)
	rebuild()
	return m


## Removes a machine; refunds half of everything spent on it.
func remove_machine(uid: int) -> float:
	var list := machines()
	for i in list.size():
		if int(list[i]["uid"]) == uid:
			var m: Dictionary = list[i]
			var refund := float(m.get("spent", info(m).get("price", 0))) * 0.5
			list.remove_at(i)
			rebuild()
			return refund
	return 0.0


func rebuild() -> void:
	_by_uid.clear()
	for m in machines():
		_by_uid[int(m["uid"])] = m


## The hexagon a machine works on (picking the next one when needed), or -1.
func target_of(m: Dictionary) -> int:
	var t := int(m.get("target", -1))
	if t >= 0 and t < HexGrid.count() and not GameState.hexes_done.has(t) and _hex_open(t):
		return t
	# The nearest unfinished hexagon: for a station that starts with its own.
	t = nearest_unfinished(v3(m["pos"]).normalized())
	m["target"] = t
	if m["id"] == "drone_hangar":
		m["manual"] = false
	return t


func _hex_open(cell: int) -> bool:
	return GameState.region_unlocked(TerrainGen.region_dir(HexGrid.centers[cell]))


## The unfinished hexagon (in an unlocked region) nearest to a direction, or -1.
func nearest_unfinished(d: Vector3) -> int:
	var done := {}
	for c in GameState.hexes_done:
		done[int(c)] = true
	var best := -1
	var bd := -2.0
	for i in HexGrid.count():
		if done.has(i):
			continue
		var dd := HexGrid.centers[i].dot(d)
		if dd > bd and _hex_open(i):
			bd = dd
			best = i
	return best


## Points a Drone Hangar at a hexagon (from the map).
func assign(m: Dictionary, cell: int) -> bool:
	if cell < 0 or GameState.hexes_done.has(cell) or not _hex_open(cell):
		return false
	m["target"] = cell
	m["manual"] = true
	return true


# ------------------------------------------------------------------ running

func tick(dt: float, _near := {}) -> void:
	_time += dt
	for m in machines():
		match m["id"]:
			"dust_collector":
				_collector(m, dt)
			"hex_station", "drone_hangar":
				_hex_worker(m, dt)
	for m in machines():
		var r := float(m.get("rate_acc", 0.0))
		m["rate"] = lerpf(float(m.get("rate", 0.0)), r / dt * 60.0, 0.15)
		m["rate_acc"] = 0.0
	revenue_rate = lerpf(revenue_rate, _revenue_acc / dt * 60.0, 0.1)
	production_rate = lerpf(production_rate, _prod_acc / dt * 60.0, 0.1)
	_revenue_acc = 0.0
	_prod_acc = 0.0


## Work done while the game was closed: collectors keep extracting, stations and
## hangars finish the hexagon they were on (no new ones). Returns {credits, hexes}.
func run_away(seconds: float) -> Dictionary:
	var credits0 := GameState.credits
	var hexes0 := GameState.hexes_done.size()
	var left := minf(seconds, AWAY_CAP) * AWAY_SPEED
	var first := {}
	for m in machines():
		if m["id"] != "dust_collector":
			first[m["uid"]] = target_of(m)
	while left > 0.0:
		var dt := minf(60.0, left)
		left -= dt
		for m in machines():
			if m["id"] == "dust_collector":
				var p := v3(m["pos"])
				var rinfo := GameData.region(TerrainGen.region_of(p))
				var deep := float(info(m).get("deep_rate", 1.0)) * tier_mult(m) * (1.0 + GameState.research_bonus("deep")) * dt
				_sell(m, deep, float(rinfo["dust_mult"]))
			elif int(first.get(m["uid"], -1)) >= 0 and target_of(m) == int(first[m["uid"]]):
				_hex_worker(m, dt)
	return {"credits": GameState.credits - credits0, "hexes": GameState.hexes_done.size() - hexes0}


## Sells what a machine produced straight away.
func _sell(m: Dictionary, units: float, mult: float) -> void:
	if units <= 0.0:
		return
	var value := units * mult * GameState.dust_price() * (1.0 + GameState.research_bonus("refine"))
	GameState.add_credits(value)
	m["produced"] = float(m.get("produced", 0.0)) + units
	m["earned"] = float(m.get("earned", 0.0)) + value
	m["rate_acc"] = float(m.get("rate_acc", 0.0)) + units
	GameState.add_stat("auto_dust", units)
	_prod_acc += units
	_revenue_acc += value


func _collector(m: Dictionary, dt: float) -> void:
	var i := info(m)
	var p := v3(m["pos"])
	var rinfo := GameData.region(TerrainGen.region_of(p))
	var dpm := float(GameData.economy["dust_per_m2"]) * TerrainGen.thickness(p, float(rinfo["thickness"]))
	var R := collector_radius(m)
	var k := tier_mult(m)
	# A sweeping spiral of cleaning heads covers the whole circle over time.
	m["phase"] = float(m.get("phase", 0.0)) + dt
	var ph: float = m["phase"]
	var fb := TerrainGen.frame(p.normalized())
	var area := 0.0
	var heads := 1 + tier(m)
	for h in heads:
		var a := ph * 0.9 + h * TAU / heads
		var rho := 1.5 + (R - 1.5) * (0.5 + 0.5 * sin(ph * 0.07 + h * 1.7))
		var spot := p + (fb.x * cos(a) + fb.z * sin(a)) * rho
		area += dirt.stamp(DirtMap.Shape.ROUND, spot, 1.6 + 0.3 * tier(m), 0.0, Vector3.ZERO, 2.0 * dt, 1e9)
	var deep := float(i.get("deep_rate", 1.0)) * k * (1.0 + GameState.research_bonus("deep")) * dt
	m["status"] = "Cleaning a %d m circle" % int(R) if area > 0.0 else "Deep extraction (circle clean)"
	_sell(m, area * dpm + deep, float(rinfo["dust_mult"]))


func _hex_worker(m: Dictionary, dt: float) -> void:
	var t := target_of(m)
	if t < 0:
		m["status"] = "Every open hexagon is clean!"
		return
	var c := HexGrid.centers[t]
	var rinfo := GameData.region(TerrainGen.region_dir(c))
	var rate := hex_rate(m) * dt
	var work := float(GameState.hex_work.get(t, 0.0)) + rate / hex_area()
	GameState.hex_work[t] = work
	var dpm := float(GameData.economy["dust_per_m2"]) * float(rinfo["thickness"])
	_sell(m, rate * dpm, float(rinfo["dust_mult"]))
	var frac := hex_progress(t)
	m["status"] = "Clearing hexagon %d: %d%%" % [t + 1, int(frac * 100.0)]
	if frac >= 1.0:
		if on_hex_cleared.is_valid():
			on_hex_cleared.call(t)
		else:
			GameState.hexes_done.append(t)
		GameState.hex_work.erase(t)
		m["target"] = -1


## How far a hexagon is: what was measured on the ground plus machine work.
static func hex_progress(cell: int) -> float:
	if GameState.hexes_done.has(cell):
		return 1.0
	return minf(float(GameState.hex_frac.get(cell, 0.0)) + float(GameState.hex_work.get(cell, 0.0)), 1.0)
