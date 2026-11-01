class_name OrderDispatcher
extends RefCounted
## Paces customer orders to what one bartender can actually serve.
##
## People in the pub and orders at the bar are separate things. Customers arrive, sit or stand
## and chat; when they want a drink they join a waiting list. The dispatcher sends them up to
## the bar one at a time, at an interval derived from the player's *measured* serving time and a
## target utilisation (Relaxed 45%, Balanced 60%, Busier 80%), never past the active-order cap,
## and without catching up after a lull. Patience only runs once a customer is actually at the bar.

const UTILISATION := {"relaxed": 0.45, "balanced": 0.6, "busier": 0.8}
const PATIENCE_MULT := {"relaxed": 3.5, "balanced": 2.8, "busier": 2.0}
const BASE_CAP := {"relaxed": [1, 2], "balanced": [2, 3], "busier": [3, 4]}  # [soft, hard] on day 1
const DEFAULT_SERVICE := 55.0     # seconds for a careful two-part pour, handover and payment
const MAX_CAP := 6                # never more than the bar's service spots

var pending: Array = []           # customers who would like to order, oldest first
var credit := 1.0                 # one order may be released when this reaches 1 (no banking beyond 1)
var throttled := false            # true while the cap or the pacing holds orders back
var hard_cap_hit := false
var force_next := false           # tutorial: send the very first customer straight up
var released_times: Array = []    # real seconds since start of each release (for tests and pacing)
var clock := 0.0


static func difficulty() -> String:
	var d := str(GameState.settings.get("difficulty", "balanced"))
	return d if UTILISATION.has(d) else "balanced"


static func service_time() -> float:
	return clampf(float(GameState.stats.get("service_time_ema", DEFAULT_SERVICE)), 25.0, 180.0)


## Bartenders working the bar (the player, plus any hired bar staff).
static func servers() -> float:
	var n := 1.0
	for s in GameState.staff:
		if str(s.get("role", "")) == "bartender":
			n += float(s.get("skill", 0.6))
	return n


## Seconds between new orders: the measured service time stretched to the target utilisation.
func order_interval(live_music := false) -> float:
	var u: float = UTILISATION[difficulty()]
	var interval := service_time() / (u * servers())
	# a gentle first few days, then busier as reputation grows
	var day := GameState.day
	interval *= 1.15 if day <= 1 else (1.07 if day == 2 else 1.0)
	interval /= 1.0 + clampf((GameState.reputation - 20.0) / 100.0, 0.0, 0.3)
	if live_music:
		interval /= 1.2
	# a bigger team can take a faster stream of orders (the floor is per pair of hands)
	return clampf(interval, 28.0 / servers(), 200.0)


## [soft, hard] limit on orders waiting at the bar.
func caps() -> Array:
	var base: Array = BASE_CAP[difficulty()]
	var grow := mini((GameState.day - 1) / 3, 2)
	var staff_bonus := int(servers() - 1.0 + 0.5)
	var hard := mini(int(base[1]) + grow + staff_bonus, MAX_CAP)
	var soft := mini(int(base[0]) + grow + staff_bonus, hard)
	return [soft, hard]


func patience_for(regular_factor := 1.0) -> float:
	var p := service_time() * float(PATIENCE_MULT[difficulty()]) + 45.0
	if GameState.day <= 1:
		p *= 1.5
	return p * regular_factor


func add_pending(c) -> void:
	if not pending.has(c):
		pending.append(c)


func remove(c) -> void:
	pending.erase(c)


## Called every frame with the number of orders currently at the bar.
## Returns the customer to send up, or null.
func tick(dt: float, active: int, live_music := false):
	clock += dt
	# drop anyone who has gone
	pending = pending.filter(func(c): return is_instance_valid(c) and not c.ordering and not c.leaving and c.state in ["mingle", "walk"])
	var c2 := caps()
	var interval := order_interval(live_music)
	if active >= int(c2[0]):
		# at the soft cap time runs at half speed; at the hard cap it stops entirely
		interval *= 2.0
	if active >= int(c2[1]):
		hard_cap_hit = true
		throttled = not pending.is_empty()
		return null
	if hard_cap_hit:
		# after a rush, give the bartender a breather before the next order
		hard_cap_hit = false
		credit = minf(credit, 0.5)
	credit = minf(1.0, credit + dt / interval)
	if pending.is_empty():
		throttled = false
		return null
	if force_next or credit >= 1.0:
		force_next = false
		credit = 0.0
		throttled = false
		released_times.append(clock)
		return pending.pop_front()
	throttled = true
	return null


## Seconds until the next order may be sent up (for the HUD).
func seconds_to_next(live_music := false) -> float:
	return maxf(0.0, (1.0 - credit) * order_interval(live_music))


## How many people the pub should hold right now. Being busy is mostly atmosphere: only some
## of them want a drink at any moment, and the dispatcher decides when they order.
func target_population(hour: float, event_mult: float, max_customers: int) -> int:
	var curve := 0.5
	if hour >= 18.0:
		curve = 0.8
	if hour >= 20.0:
		curve = 1.0
	if hour >= 22.0:
		curve = 0.8
	var rep := clampf(GameState.reputation / 100.0, 0.0, 1.0)
	var t := 2.0 + (4.0 + 10.0 * rep) * curve * event_mult
	if GameState.day <= 1:
		t = minf(t, 5.0)
	return clampi(int(round(t)), 1, max_customers)


## Record how long the player took from taking an order to handing it over.
static func record_service(seconds: float) -> void:
	if seconds <= 1.0 or seconds > 600.0:
		return
	var ema := service_time()
	GameState.stats["service_time_ema"] = clampf(ema * 0.75 + seconds * 0.25, 25.0, 180.0)
	GameState.stats["service_samples"] = int(GameState.stats.get("service_samples", 0)) + 1
