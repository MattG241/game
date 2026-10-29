class_name World
extends Node3D
## Runs a day in the pub: time, customers, glasses, serving, upgrades, lighting and ambience.

signal served(result: Dictionary)
signal order_taken(c: Customer)

const MAX_DIRTY_CARRY := 6

var main: Node
var info: Dictionary
var player: Player
var hud: Node
var pour: Node
var env: Environment
var close_cam: Camera3D
var nav_region: NavigationRegion3D

var customers: Array[Customer] = []
var bar_spots: Array = []         # Customer or null
var queue_slots: Array = []
var seats_taken: Dictionary = {}  # seat index -> Customer
var settle_slots: Array = []      # PintGlass or null
var loose_glasses: Array[PintGlass] = []  # glasses out in the room (dirty on tables etc.)
var rack_clean := 0
var spills: Array[Node3D] = []
var fast_forward := false
var tutorial_step := 0
var _spawn_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _regulars_today: Dictionary = {}
var _rack_visuals: Array[Node3D] = []
var _autosave_t := 0.0
var _first_customer_timer := -1.0
var _day_summary_pending := false
var _door_anim := 0.0
var _church_rung := -1
var _fire_audio: AudioStreamPlayer3D
var _nav_ready := false


func _ready() -> void:
	_rng.randomize()
	_setup_env()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.28
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nav_region.navigation_mesh = nm
	var builder := PubBuilder.new()
	info = builder.build(nav_region)
	nav_region.bake_navigation_mesh(false)
	close_cam = Camera3D.new()
	close_cam.fov = 50.0
	close_cam.near = 0.02
	add_child(close_cam)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = PubLayout.PLAYER_START
	player.rotation.y = PI
	bar_spots.resize(PubLayout.BAR_SPOT_X.size())
	queue_slots.resize(PubLayout.QUEUE_POS.size())
	settle_slots.resize(PubLayout.SETTLE_SLOTS.size())
	rack_clean = GameState.glasses_total() - int(GameState.tutorial.get("dirty_overnight", 0))
	rack_clean = clampi(rack_clean, 0, GameState.glasses_total())
	_restore_overnight_dirty()
	_make_interactables()
	apply_upgrades()
	_refresh_rack()
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	_fire_audio = AudioStreamPlayer3D.new()
	_fire_audio.stream = Sfx.get_stream("fire_loop")
	_fire_audio.bus = "Ambience"
	_fire_audio.unit_size = 3.0
	_fire_audio.position = PubLayout.FIREPLACE + Vector3(0.5, 0.5, 0)
	add_child(_fire_audio)
	_update_lighting(true)
	await get_tree().physics_frame
	_nav_ready = true


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.45, 0.36)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.22, 0.26)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	apply_graphics()


func apply_graphics() -> void:
	var preset: String = GameState.settings.get("graphics", "medium")
	var scale := float(GameState.settings.get("render_scale", 1.0))
	get_viewport().scaling_3d_scale = clampf(scale, 0.5, 1.0)
	get_viewport().msaa_3d = Viewport.MSAA_2X if preset == "high" else Viewport.MSAA_DISABLED
	if env:
		env.glow_enabled = preset != "low" and not GameState.settings.get("reduced_effects", false)
		env.fog_enabled = preset != "low"
	Engine.max_fps = int(GameState.settings.get("fps_limit", 60))
	if info.has("key_light") and info["key_light"]:
		(info["key_light"] as SpotLight3D).shadow_enabled = preset == "high"
	for r in info.get("rain", []):
		(r as CPUParticles3D).amount = 150 if preset == "low" else (350 if preset == "medium" else 600)


# ------------------------------------------------------------------ interactables
func _make_interactables() -> void:
	var I := Interactable
	I.make(self, PubLayout.RACK_POS + Vector3(0, 0.1, 0), "rack", _rack_prompt, _rack_action)
	for id in info["taps"].keys():
		var t: Dictionary = info["taps"][id]
		var tap_id: String = id
		I.make(self, t["glass"] + Vector3(0, 0.25, 0), "tap_" + id, func(): return _tap_prompt(tap_id), func(): _tap_action(tap_id))
	for i in PubLayout.SETTLE_SLOTS.size():
		var idx := i
		I.make(self, PubLayout.SETTLE_SLOTS[i] + Vector3(0, 0.08, 0), "settle", func(): return _settle_prompt(idx), func(): _settle_action(idx), 0.0, 1.5)
	var sink := I.make(self, PubLayout.SINK_POS + Vector3(0, 0.1, 0), "sink", _sink_prompt, _sink_action)
	I.make(self, PubLayout.DOOR_SIGN_POS, "door_sign", _sign_prompt, _sign_action, 0.0, 2.2)
	I.make(self, PubLayout.TILL_POS + Vector3(0, 0.15, 0), "till", func(): return "Check the till & ledger", func(): hud.open_menu("ledger"))
	for id in PubLayout.KEG_POS.keys():
		var kid: String = id
		I.make(self, PubLayout.KEG_POS[id] + Vector3(0, 0.6, 0), "keg_" + id, func(): return _keg_prompt(kid), func(): _keg_action(kid), 1.2)
	I.make(self, PubLayout.STOCK_PILE + Vector3(0, 0.6, 0), "stock", func(): return "Order stock (phone)", func(): hud.open_menu("stock"))


func _hint(text: String) -> String:
	return "~" + text


func _rack_prompt() -> String:
	if player.held != null:
		if player.held.contents.is_empty() and player.held.dirt < 0.1:
			return "Put the glass back"
		return ""
	if not player.dirty_stack.is_empty():
		return _hint("Wash the dirty glasses at the sink first")
	if rack_clean <= 0:
		return _hint("No clean glasses! Collect and wash some")
	return "Take a clean pint glass (%d)" % rack_clean


func _rack_action() -> void:
	if player.held != null:
		if player.held.contents.is_empty() and player.held.dirt < 0.1:
			var g := player.release_glass()
			g.queue_free()
			rack_clean += 1
			_refresh_rack()
		return
	if not player.dirty_stack.is_empty() or rack_clean <= 0:
		return
	rack_clean -= 1
	var g := PintGlass.new()
	player.take_glass(g)
	_refresh_rack()
	Sfx.play("clink", -8.0)
	_tutorial_event("glass")


func _tap_prompt(id: String) -> String:
	if not GameState.drink_available(id):
		return ""
	var name: String = GameData.drink(id).get("short", id)
	if player.held == null:
		return _hint("Grab a clean glass to pour %s" % name)
	var c := player.held.contents
	if c.drink_id != "" and c.drink_id != id and not c.is_empty():
		return _hint("That glass already has %s in it" % GameData.drink(c.drink_id).get("short", ""))
	if GameState.serves_left(id) <= 0.02:
		return _hint("%s keg is empty. Change it in the cellar" % name)
	if id == "stout" and c.stage >= 2:
		return "Top up the stout"
	return "Pour %s" % name


func _tap_action(id: String) -> void:
	if _tap_prompt(id).begins_with("~") or player.held == null:
		return
	pour.begin(id, info["taps"][id])


func _settle_prompt(i: int) -> String:
	var g: PintGlass = settle_slots[i]
	if g != null:
		if player.has_hands_free():
			var pct := int(g.contents.settled_fraction() * 100.0)
			if pct >= 99:
				return "Pick up the settled %s" % GameData.drink(g.contents.drink_id).get("short", "pint")
			return "Pick up the pint (settling %d%%)" % pct
		return ""
	if player.held != null and not player.held.contents.is_empty():
		return "Leave it here to settle"
	return ""


func _settle_action(i: int) -> void:
	var g: PintGlass = settle_slots[i]
	if g != null and player.has_hands_free():
		settle_slots[i] = null
		player.take_glass(g)
		return
	if g == null and player.held != null and not player.held.contents.is_empty():
		place_on_settle(i, player.release_glass())


func place_on_settle(i: int, g: PintGlass) -> void:
	settle_slots[i] = g
	add_child(g)
	g.global_position = PubLayout.SETTLE_SLOTS[i]
	g.rotation = Vector3.ZERO
	Sfx.play("glass_place", -6.0)
	_tutorial_event("settle")


func free_settle_slot() -> int:
	for i in settle_slots.size():
		if settle_slots[i] == null:
			return i
	return -1


func _sink_prompt() -> String:
	if not player.dirty_stack.is_empty():
		return "Hold to wash a glass (%d dirty)" % player.dirty_stack.size()
	if player.held != null and not player.held.contents.is_empty():
		return "Pour it away"
	if player.held != null and player.held.dirt >= 0.1:
		return "Hold to wash this glass"
	return ""


func _sink_action() -> void:
	if player.held != null and not player.held.contents.is_empty():
		var c := player.held.contents
		GameState.waste_units(c.drink_id, c.total())
		c.reset()
		player.held.set_dirty(0.5)
		Sfx.play("spill", -6.0)
		var g := player.release_glass()
		player.add_dirty(g)
		notify("Poured away. Wash the glass before reusing it.")
		return
	if player.held != null and player.held.dirt >= 0.1:
		player.add_dirty(player.release_glass())
	var g := player.pop_dirty()
	if g == null:
		return
	g.queue_free()
	rack_clean += 1
	GameState.stats["glasses_washed"] = int(GameState.stats["glasses_washed"]) + 1
	_refresh_rack()
	Sfx.play("squeak", -6.0)
	Sfx.play("clink", -10.0)
	_tutorial_event("washed")


func _sign_prompt() -> String:
	match GameState.phase:
		"prep":
			return "Open the pub (flip the sign)"
		"open":
			return "Call last orders early"
		"last_orders", "closing":
			if customers.is_empty():
				return "Close up and cash up"
			return _hint("Waiting for the last customers to leave (%d)" % customers.size())
	return ""


func _sign_action() -> void:
	match GameState.phase:
		"prep":
			GameState.open_pub()
			Sfx.play("door_bell", -4.0)
			_set_sign(true)
			notify("The Crooked Shamrock is open!", "good")
			_tutorial_event("opened")
			if int(GameState.stats["served"]) == 0:
				_first_customer_timer = 3.0
		"open":
			_last_orders()
		"last_orders", "closing":
			if customers.is_empty():
				close_day()


func _set_sign(open: bool) -> void:
	var lbl: Label3D = info.get("door_sign_label")
	if lbl:
		lbl.text = "OPEN" if open else "CLOSED"
		lbl.modulate = Color(0.4, 0.95, 0.5) if open else Color(0.9, 0.3, 0.2)


func _keg_prompt(id: String) -> String:
	if not GameState.drink_available(id):
		return ""
	var d := GameData.drink(id)
	var left := GameState.serves_left(id)
	var spare := int(GameState.stock.get(id, 0))
	if left < 6.0 and spare > 0:
		return "Hold to change the %s %s (%d spare)" % [d["short"], d["stock_unit"], spare]
	if left < 6.0:
		return _hint("No spare %s %s. Order more from the stock menu" % [d["short"], d["stock_unit"]])
	return _hint("%s: about %d serves left, %d spare" % [d["short"], int(left), spare])


func _keg_action(id: String) -> void:
	if GameState.serves_left(id) >= 6.0:
		return
	if GameState.change_keg(id):
		Sfx.play("keg", -2.0)
		notify("Fresh %s connected." % GameData.drink(id)["stock_unit"], "good")
		_refresh_stock_pile()


# ------------------------------------------------------------------ glasses
func _refresh_rack() -> void:
	for n in _rack_visuals:
		n.queue_free()
	_rack_visuals.clear()
	var rack: Node3D = info["rack_glasses"]
	var slots: Array = info["rack_slots"]
	for i in mini(rack_clean, slots.size()):
		var g := PintGlass.new()
		rack.add_child(g)
		g.position = slots[i] + Vector3(0, 0.16, 0)
		g.rotation = Vector3(PI, 0, 0)  # stored upside down
		g.set_process(false)
		_rack_visuals.append(g)
	if hud:
		hud.refresh()


func glass_count_check() -> int:
	## Counts every glass in the game so tests can prove none are created or lost.
	var n := rack_clean
	if player.held:
		n += 1
	n += player.dirty_stack.size()
	for g in settle_slots:
		if g != null:
			n += 1
	n += loose_glasses.size()
	for c in customers:
		if c.glass != null:
			n += 1
	if pour and pour.active and pour.glass and player.held != pour.glass:
		n += 1
	return n


func leave_dirty_glass(g: PintGlass, pos: Vector3) -> void:
	add_child(g)
	g.global_position = pos
	g.rotation = Vector3.ZERO
	loose_glasses.append(g)
	var it := Interactable.make(g, pos + Vector3(0, 0.08, 0), "dirty_glass",
		func(): return _collect_prompt(g), func(): _collect_glass(g), 0.0, 1.6)
	_tutorial_event("dirty")


func _collect_prompt(g: PintGlass) -> String:
	if player.held != null:
		return ""
	if player.dirty_stack.size() >= MAX_DIRTY_CARRY:
		return _hint("Hands full. Wash these first")
	return "Collect the empty glass"


func _collect_glass(g: PintGlass) -> void:
	if player.held != null or player.dirty_stack.size() >= MAX_DIRTY_CARRY:
		return
	loose_glasses.erase(g)
	for ch in g.get_children():
		if ch is Interactable:
			ch.queue_free()
	player.add_dirty(g)
	Sfx.play("clink", -8.0)


func _restore_overnight_dirty() -> void:
	var n := int(GameState.tutorial.get("dirty_overnight", 0))
	GameState.tutorial.erase("dirty_overnight")
	for i in n:
		var g := PintGlass.new()
		g.set_dirty(0.7)
		g.lace_top = 0.7
		leave_dirty_glass(g, PubLayout.SINK_POS + Vector3(-0.3 - (i % 4) * 0.09, 0, 0.12 - (i / 4) * 0.1))


# ------------------------------------------------------------------ customers
func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _nav_ready:
		return PackedVector3Array([to])
	var map := get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.size() > 0:
		p.append(to)
	return p


func patience_drain() -> float:
	# good atmosphere and music make waiting easier
	var a := GameState.atmosphere()
	return clampf(1.15 - a / 200.0, 0.6, 1.2)


func drink_speed_mult() -> float:
	return 1.0 / (1.0 + GameState.get_mod("stay_mult"))


func line(kind: String) -> String:
	var arr: Array = GameData.customer_lines.get(kind, ["..."])
	return arr[_rng.randi() % arr.size()]


func order_line(c: Customer) -> String:
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		var lines: Array = r.get("greet", [])
		if not lines.is_empty():
			return lines[_rng.randi() % lines.size()]
	if c.visitor == "tourist" and _rng.randf() < 0.5:
		var tl: Array = GameData.customer_lines.get("tourist_order", [])
		return tl[_rng.randi() % tl.size()] + " (%s it is!)" % GameData.drink(c.drink_id).get("short", "")
	var ol: Dictionary = GameData.customer_lines.get("order", {})
	var arr: Array = ol.get(c.drink_id, ["A drink, please."])
	return arr[_rng.randi() % arr.size()]


func pick_drink(c: Customer) -> String:
	var avail := GameState.available_drinks()
	var stocked := avail.filter(func(id): return GameState.serves_left(id) > 0.5 or int(GameState.stock.get(id, 0)) > 0)
	if stocked.is_empty():
		stocked = avail
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		if r["drink"] in stocked:
			return r["drink"]
		if r.has("alt") and r["alt"] in stocked:
			return r["alt"]
	# stout is the house speciality
	var weights := {"stout": 5.0, "lager": 3.0, "ale": 1.5, "cider": 1.5, "zero": 0.8, "whiskey": 1.0, "soft": 1.0}
	var total := 0.0
	for id in stocked:
		total += float(weights.get(id, 1.0))
	var r2 := _rng.randf() * total
	for id in stocked:
		r2 -= float(weights.get(id, 1.0))
		if r2 <= 0.0:
			return id
	return stocked[0]


func max_customers() -> int:
	var preset: String = GameState.settings.get("graphics", "medium")
	var cap := int(GameData.econ("max_customers_" + preset, 14))
	var seats := 0
	for s in info["seats"]:
		if not s.has("upgrade") or GameState.has_upgrade(s["upgrade"]):
			seats += 1
	return mini(cap, seats + bar_spots.size() + 2)


func arrival_rate_per_hour() -> float:
	if GameState.phase != "open":
		return 0.0
	var h := GameState.hour
	var curve := 0.6
	if h >= 18.0:
		curve = 1.0
	if h >= 20.0:
		curve = 1.35
	if h >= 22.0:
		curve = 1.05
	var wd: Array = GameData.econ("weekday_mult", [1, 1, 1, 1, 1, 1, 1])
	var weather_m: Dictionary = GameData.econ("weather_mult", {})
	var wm := float(weather_m.get(GameState.weather, 1.0))
	if GameState.weather in ["rain", "storm"]:
		wm += GameState.get_mod("rain_bonus")
	var rep := 0.55 + GameState.reputation / 45.0
	var arr := 1.0 + GameState.get_mod("arrival_mult")
	return float(GameData.econ("base_arrivals_per_hour", 7.0)) * curve * float(wd[GameState.weekday()]) * wm * rep * arr


func _maybe_spawn(dt: float) -> void:
	if _first_customer_timer > 0.0:
		_first_customer_timer -= dt
		if _first_customer_timer <= 0.0:
			spawn_customer()
		return
	if customers.size() >= max_customers():
		return
	var per_sec := arrival_rate_per_hour() / GameState.seconds_per_game_hour()
	if _rng.randf() < per_sec * dt:
		spawn_customer()


func spawn_customer(force_regular := "") -> Customer:
	var c := Customer.new()
	var look := {}
	var reg := force_regular
	if reg == "" and _rng.randf() < 0.35:
		var options := []
		for r in GameData.regulars:
			if not _regulars_today.has(r["id"]):
				options.append(r["id"])
		if not options.is_empty():
			reg = options[_rng.randi() % options.size()]
	if reg != "":
		var r: Dictionary = GameData.regulars_by_id[reg]
		look = r.get("look", {})
		c.regular_id = reg
		c.display_name = r["name"]
		c.patience_max = 80.0 * float(r.get("patience", 1.0))
		c.tip_mult = float(r.get("tip", 1.0))
		_regulars_today[reg] = true
	else:
		var names: Array = GameData.customer_lines.get("first_names", ["Pat"])
		c.display_name = names[_rng.randi() % names.size()]
		var types: Array = GameData.customer_lines.get("visitor_types", ["local"])
		c.visitor = types[_rng.randi() % types.size()]
		c.patience_max = _rng.randf_range(60.0, 90.0) * (1.2 if c.visitor == "tourist" else 1.0)
		c.tip_mult = _rng.randf_range(0.7, 1.3) * (1.3 if c.visitor == "tourist" else 1.0)
	c.patience = c.patience_max
	c.budget = 1 + int(_rng.randf() < 0.45) + int(_rng.randf() < 0.2)
	c.drink_rate = 1.0 / _rng.randf_range(75.0, 120.0)
	c.speed = _rng.randf_range(1.1, 1.4)
	c.setup(self, look, _rng.randi())
	add_child(c)
	c.drink_id = pick_drink(c)
	var from_left := _rng.randf() < 0.5
	c.global_position = PubLayout.STREET_SPAWN_L if from_left else PubLayout.STREET_SPAWN_R
	c.left_pub.connect(_on_customer_left)
	customers.append(c)
	var name_text := c.display_name if c.regular_id != "" else ""
	c.set_name_tag(name_text)
	var it := Interactable.make(c, c.global_position + Vector3(0, 1.3, 0), "customer",
		func(): return _customer_prompt(c), func(): _customer_action(c), 0.0, 2.3)
	it.position = Vector3(0, 1.3, 0)
	c.walk_to(PubLayout.INSIDE_DOOR, "choose")
	_door_anim = 2.0
	Sfx.play("door_bell", -10.0)
	# price check: very expensive drinks put people off
	return c


func customer_choose(c: Customer) -> void:
	var ratio := GameState.price_of(c.drink_id) / float(GameData.drink(c.drink_id).get("price", 5.0))
	if ratio > 1.0 + float(GameData.econ("price_tolerance", 0.18)) * 2.5 and _rng.randf() < (ratio - 1.3) * 2.0:
		c.say(line("too_dear"), 3.0, Color(1, 0.7, 0.4))
		GameState.today["walkouts"] = int(GameState.today["walkouts"]) + 1
		c.leave()
		return
	var spot := request_bar_spot(c)
	if spot >= 0:
		c.bar_spot = spot
		c.walk_to(bar_spot_pos(spot), "wait_order")
		return
	var q := -1
	for i in queue_slots.size():
		if queue_slots[i] == null:
			q = i
			break
	if q >= 0:
		queue_slots[q] = c
		c.queue_slot = q
		c.walk_to(PubLayout.QUEUE_POS[q], "queue")
	else:
		c.say("Too busy for me tonight.", 2.5)
		c.leave()


func request_bar_spot(c: Customer) -> int:
	if c.bar_spot >= 0:
		return c.bar_spot
	# prefer spots nearest the stout tap
	var order := range(bar_spots.size())
	order.sort_custom(func(a, b): return absf(PubLayout.BAR_SPOT_X[a] - PubLayout.TAP_X["stout"]) < absf(PubLayout.BAR_SPOT_X[b] - PubLayout.TAP_X["stout"]))
	for i in order:
		if bar_spots[i] == null:
			bar_spots[i] = c
			return i
	return -1


func release_bar_spot(c: Customer) -> void:
	for i in bar_spots.size():
		if bar_spots[i] == c:
			bar_spots[i] = null


func release_queue_slot(c: Customer) -> void:
	if c.queue_slot >= 0 and c.queue_slot < queue_slots.size() and queue_slots[c.queue_slot] == c:
		queue_slots[c.queue_slot] = null
	c.queue_slot = -1


func bar_spot_pos(i: int) -> Vector3:
	return Vector3(PubLayout.BAR_SPOT_X[i], 0, PubLayout.BAR_SPOT_Z)


func request_seat(c: Customer) -> int:
	var seats: Array = info["seats"]
	var best := -1
	var best_score := INF
	for i in seats.size():
		if seats_taken.has(i):
			continue
		var s: Dictionary = seats[i]
		if s.has("upgrade") and not GameState.has_upgrade(s["upgrade"]):
			continue
		var score: float = (s["pos"] as Vector3).distance_to(c.global_position) + _rng.randf() * 3.0
		if s["kind"] == "armchair" and GameState.has_upgrade("fireplace"):
			score -= 3.0
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		seats_taken[best] = c
	return best


func release_seat(i: int) -> void:
	seats_taken.erase(i)


func seat_info(i: int) -> Dictionary:
	return info["seats"][i]


func standing_spot(c: Customer) -> Vector3:
	var spots := [Vector3(-1.5, 0, 4.3), Vector3(1.6, 0, 4.4), Vector3(-6.3, 0, -0.6), Vector3(4.3, 0, 0.2), Vector3(-2.0, 0, 0.0)]
	return spots[_rng.randi() % spots.size()] + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))


func nearest_ledge(p: Vector3) -> Vector3:
	# the bar top in front of the nearest service spot, or a window sill
	var best := Vector3(PubLayout.BAR_SPOT_X[0], PubLayout.BAR_TOP, PubLayout.SERVE_Z)
	var bd := INF
	for x in PubLayout.BAR_SPOT_X:
		var q := Vector3(x + _rng.randf_range(-0.2, 0.2), PubLayout.BAR_TOP, PubLayout.SERVE_Z)
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	for q in [Vector3(-4.2, 0.92, 4.8), Vector3(3.6, 0.92, 4.8)]:
		var d: float = q.distance_to(p)
		if d < bd:
			bd = d
			best = q + Vector3(_rng.randf_range(-0.5, 0.5), 0, 0)
	return best


func exit_point(_c: Customer) -> Vector3:
	return PubLayout.STREET_SPAWN_L if _rng.randf() < 0.5 else PubLayout.STREET_SPAWN_R


func can_reorder(c: Customer) -> bool:
	return GameState.phase == "open" and c.satisfaction_sum / maxf(1.0, c.served_count) > 45.0


func on_customer_at_bar(c: Customer) -> void:
	_tutorial_event("customer_at_bar")


func on_walkout(c: Customer) -> void:
	if c.served_count == 0:
		GameState.today["walkouts"] = int(GameState.today["walkouts"]) + 1
		GameState.stats["walkouts"] = int(GameState.stats["walkouts"]) + 1
		notify("%s gave up waiting and left." % c.display_name, "bad")
		if c.regular_id != "":
			_relationship(c.regular_id, -2)


func _on_customer_left(c: Customer) -> void:
	customers.erase(c)
	release_bar_spot(c)
	release_queue_slot(c)
	if c.seat >= 0:
		release_seat(c.seat)


func _customer_prompt(c: Customer) -> String:
	if not is_instance_valid(c):
		return ""
	match c.state:
		"wait_order":
			return "Take %s's order" % c.display_name
		"wait_drink":
			if player.held != null and not player.held.contents.is_empty():
				return "Serve %s" % c.display_name
			return _hint("%s is waiting for a %s" % [c.display_name, GameData.drink(c.drink_id).get("short", "")])
		"queue":
			return _hint("%s is queueing for the bar" % c.display_name)
		"drinking", "stand_drink":
			if c.regular_id != "" and player.has_hands_free():
				return "Chat with %s" % c.display_name
	return ""


func _customer_action(c: Customer) -> void:
	match c.state:
		"wait_order":
			c.take_order()
			order_taken.emit(c)
			_tutorial_event("order")
			if hud:
				hud.refresh_orders()
		"wait_drink":
			if player.held != null and not player.held.contents.is_empty():
				serve_customer(c, player.held)
		"drinking", "stand_drink":
			if c.regular_id != "":
				var r: Dictionary = GameData.regulars_by_id[c.regular_id]
				var chat: Array = r.get("chat", [])
				if not chat.is_empty():
					c.say(chat[_rng.randi() % chat.size()], 5.0)
					_relationship(c.regular_id, 1, true)


## Hands a glass to a waiting customer: scores it, takes payment and tips.
func serve_customer(c: Customer, g: PintGlass) -> Dictionary:
	var con := g.contents
	if con.drink_id != c.drink_id:
		c.refuse_drink(line("wrong_drink") + " (%s)" % GameData.drink(c.drink_id).get("short", ""))
		return {"ok": false, "reason": "wrong_drink"}
	var res := con.evaluate(g.dirt, GameState.get_mod("beer_quality") * 0.6)
	var q: int = res["score"]
	if q < 30:
		c.refuse_drink(line("refuse"))
		GameState.today["complaints"] = int(GameState.today["complaints"]) + 1
		c.patience = maxf(c.patience, c.patience_max * 0.4)
		res["ok"] = false
		res["reason"] = "refused"
		notify("%s: %s" % [res["verdict"], ", ".join(res["notes"])], "bad")
		return res
	if player.held == g:
		player.release_glass()
	# payment
	var price := GameState.price_of(c.drink_id)
	var base := float(GameData.drink(c.drink_id).get("price", 5.0))
	var fair := clampf(1.0 - maxf(0.0, price / base - 1.0) * 2.0, 0.0, 1.0)
	var wait_score := clampf(c.patience / c.patience_max, 0.0, 1.0)
	var atmos := GameState.atmosphere() / 100.0
	var sat := q * 0.5 + wait_score * 25.0 + fair * 10.0 + atmos * 10.0 + cleanliness() / 100.0 * 5.0
	sat = clampf(sat, 0.0, 100.0)
	var tip_rate := 0.0
	if q >= 90:
		tip_rate = 0.22
	elif q >= 75:
		tip_rate = 0.12
	elif q >= 60:
		tip_rate = 0.05
	tip_rate *= c.tip_mult * (1.0 + GameState.get_mod("tips_mult")) * (0.6 + wait_score * 0.4) * (0.5 + fair * 0.5)
	var tip := snappedf(price * tip_rate, 0.1)
	GameState.earn(price, "sales")
	GameState.earn(tip, "tips")
	GameState.today["served"] = int(GameState.today["served"]) + 1
	GameState.today["satisfaction_sum"] = float(GameState.today["satisfaction_sum"]) + sat
	GameState.today["quality_sum"] = float(GameState.today["quality_sum"]) + q
	GameState.today["pours"] = int(GameState.today["pours"]) + 1
	GameState.stats["served"] = int(GameState.stats["served"]) + 1
	if c.drink_id in ["stout", "lager", "ale"]:
		GameState.stats["pints_poured"] = int(GameState.stats["pints_poured"]) + 1
	if q >= 90:
		GameState.stats["perfect_pints"] = int(GameState.stats["perfect_pints"]) + 1
	GameState.stats["best_pour"] = maxi(int(GameState.stats["best_pour"]), q)
	c.satisfaction_sum += sat
	c.receive_drink(g)
	var reaction := ""
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		var arr: Array = r.get("praise" if q >= 70 else "complain", [])
		reaction = arr[_rng.randi() % arr.size()] if not arr.is_empty() else ""
		_relationship(c.regular_id, 3 if q >= 85 else (1 if q >= 60 else -1))
	else:
		reaction = line("praise" if q >= 80 else ("ok" if q >= 55 else "complain"))
	c.say(reaction, 3.5, Color(0.7, 1.0, 0.7) if q >= 70 else Color(1.0, 0.85, 0.6))
	Sfx.play("glass_place", -4.0)
	Sfx.play("till", -8.0)
	if tip > 0.0:
		Sfx.play("coins", -6.0)
	GameState.vibrate(25)
	res["ok"] = true
	res["price"] = price
	res["tip"] = tip
	res["satisfaction"] = sat
	res["customer"] = c.display_name
	served.emit(res)
	if hud:
		hud.show_pour_result(res)
		hud.refresh_orders()
	_tutorial_event("served")
	return res


func _relationship(id: String, delta: int, chat := false) -> void:
	var r := int(GameState.relationships.get(id, 0))
	if chat:
		var key := "chat_%s_%d" % [id, GameState.day]
		if GameState.tutorial.has(key):
			return
		GameState.tutorial[key] = true
	GameState.relationships[id] = clampi(r + delta, -10, 100)


func cleanliness() -> float:
	var dirty := 0
	for g in loose_glasses:
		dirty += 1
	return clampf(100.0 - spills.size() * 9.0 - dirty * 3.0, 0.0, 100.0)


# ------------------------------------------------------------------ spills
func add_spill(pos: Vector3, size := 0.12) -> void:
	if randf() < -GameState.get_mod("spill_mess_mult"):
		return
	var s := MeshKit.cyl(self, size, size, 0.004, pos + Vector3(0, 0.003, 0), MeshKit.mat("spill"), 16)
	s.scale = Vector3(1.0, 1.0, randf_range(0.6, 1.0))
	spills.append(s)
	Interactable.make(s, pos + Vector3(0, 0.05, 0), "spill", func(): return "Hold to wipe the spill", func(): _wipe(s), 0.9, 1.8)


func _wipe(s: Node3D) -> void:
	spills.erase(s)
	s.queue_free()
	Sfx.play("squeak", -4.0)
	GameState.stats["spills_cleaned"] = int(GameState.stats["spills_cleaned"]) + 1


# ------------------------------------------------------------------ day flow
func _process(delta: float) -> void:
	if GameState.phase != "prep":
		var gh := delta / GameState.seconds_per_game_hour()
		GameState.hour += gh
		var close_h := float(GameData.econ("close_hour", 24.0))
		var last_h := float(GameData.econ("last_orders_hour", 23.5))
		if GameState.phase == "open" and GameState.hour >= last_h:
			_last_orders()
		if GameState.phase == "last_orders" and GameState.hour >= close_h:
			GameState.phase = "closing"
			for c in customers.duplicate():
				if c.state in ["queue", "wait_order"]:
					c.say("Ah, closing time. Night!", 2.0)
					c.leave()
		if GameState.hour >= close_h + 0.75:
			# nobody stays past a quarter to one
			for c in customers.duplicate():
				if c.state != "walk":
					c.leave()
		_maybe_spawn(delta)
	# settle every pint in the building
	var settle_s := float(GameData.econ("settle_seconds", 12.0))
	for g in settle_slots:
		if g != null:
			g.contents.settle(delta, settle_s)
	if player.held:
		player.held.contents.settle(delta, settle_s)
	for c in customers:
		if c.glass:
			c.glass.contents.settle(delta, settle_s)
	player.update_focus()
	_update_lighting(false)
	_update_audio()
	_update_door(delta)
	if fast_forward and not can_fast_forward():
		set_fast_forward(false)
	_autosave_t += delta
	if _autosave_t > 45.0:
		_autosave_t = 0.0
		autosave()
	_check_church_bell()


func _last_orders() -> void:
	if GameState.phase != "open":
		return
	GameState.phase = "last_orders"
	Sfx.play("till", -2.0)
	notify("Last orders, please! No new customers tonight.", "info")


func can_fast_forward() -> bool:
	if pour and pour.active:
		return false
	for c in customers:
		if c.state in ["wait_order", "wait_drink", "queue"]:
			return false
	return true


func set_fast_forward(on: bool) -> void:
	fast_forward = on and can_fast_forward()
	Engine.time_scale = 3.0 if fast_forward else 1.0


func close_day() -> void:
	if not customers.is_empty():
		return
	set_fast_forward(false)
	# glasses that weren't washed stay dirty overnight
	var dirty := loose_glasses.size() + player.dirty_stack.size()
	for g in settle_slots:
		if g != null:
			dirty += 1
	if player.held:
		dirty += 1
	GameState.tutorial["dirty_overnight"] = dirty
	var summary := GameState.end_day()
	if hud:
		hud.show_day_summary(summary)


func autosave() -> void:
	# mid-day saves keep the clock, cash and stock; the room resets to opening state on load
	GameState.save_game()


func _update_door(delta: float) -> void:
	var door: Node3D = info.get("door")
	if door == null:
		return
	_door_anim = maxf(0.0, _door_anim - delta)
	var target := -1.2 if _door_anim > 0.0 else 0.0
	door.rotation.y = lerp(door.rotation.y, target, minf(1.0, delta * 4.0))


func _check_church_bell() -> void:
	var h := int(GameState.hour)
	if GameState.phase != "prep" and h != _church_rung and GameState.hour - h < 0.02 and h in [18, 21, 24]:
		_church_rung = h
		Sfx.play("church_bell", -14.0, 0.0, "Ambience")


func _update_audio() -> void:
	var rain := 0.0
	if GameState.weather == "rain":
		rain = 0.45
	elif GameState.weather == "storm":
		rain = 0.8
	Sfx.set_loop("rain", "rain_loop", rain)
	var crowd := clampf(customers.size() / 10.0, 0.0, 1.0)
	Sfx.set_loop("crowd", "crowd_loop", crowd * 0.8, "Speech")
	var lit := GameState.has_upgrade("fireplace")
	if lit and not _fire_audio.playing:
		_fire_audio.play()
	elif not lit and _fire_audio.playing:
		_fire_audio.stop()


func _update_lighting(force: bool) -> void:
	var h := GameState.hour
	var dusk := clampf((h - 17.5) / 2.5, 0.0, 1.0)  # 0 = late afternoon, 1 = night
	env.background_color = Color(0.36, 0.4, 0.46).lerp(Color(0.02, 0.025, 0.045), dusk)
	env.fog_light_color = env.background_color
	var lamps_restored := GameState.has_upgrade("lamps")
	var lamp_e := (1.3 if lamps_restored else 0.7) * (0.8 + 0.2 * dusk)
	for l in info["lamps"]:
		(l as OmniLight3D).light_energy = lamp_e
		(l as OmniLight3D).omni_range = 4.8 if lamps_restored else 3.2
	env.ambient_light_energy = lerpf(0.6, 0.42, dusk) + (0.08 if lamps_restored else 0.0)
	env.ambient_light_color = Color(0.55, 0.5, 0.45).lerp(Color(0.5, 0.38, 0.28), dusk)
	for m in info["window_mats"]:
		(m as StandardMaterial3D).emission = Color(0.45, 0.5, 0.55).lerp(Color(0.02, 0.03, 0.05), dusk)
	for sl in info["street_lights"]:
		(sl as OmniLight3D).visible = dusk > 0.3
	for r in info["rain"]:
		(r as CPUParticles3D).emitting = GameState.weather in ["rain", "storm"]
	var fl: OmniLight3D = info.get("fire_light")
	if fl and fl.is_visible_in_tree():
		fl.light_energy = 1.4 + 0.35 * sin(Time.get_ticks_msec() * 0.011) + 0.2 * sin(Time.get_ticks_msec() * 0.027)
	var hands: Array = info.get("clock_hands", [])
	if hands.size() == 2:
		(hands[0] as Node3D).rotation.z = -fmod(h, 12.0) / 12.0 * TAU
		(hands[1] as Node3D).rotation.z = -fmod(h, 1.0) * TAU


# ------------------------------------------------------------------ upgrades
func _on_upgrades_changed() -> void:
	var before := rack_clean + _glasses_out()
	var total := GameState.glasses_total()
	if total > before:
		rack_clean += total - before
	apply_upgrades()
	_refresh_rack()


func _glasses_out() -> int:
	return glass_count_check() - rack_clean


func apply_upgrades() -> void:
	for id in info["upgrade_show"].keys():
		var owned := GameState.has_upgrade(id)
		for n in info["upgrade_show"][id]:
			(n as Node3D).visible = owned
	for id in info["upgrade_hide"].keys():
		var owned2 := GameState.has_upgrade(id)
		for n in info["upgrade_hide"][id]:
			(n as Node3D).visible = not owned2
	var fl: OmniLight3D = info.get("fire_light")
	if fl:
		fl.visible = GameState.has_upgrade("fireplace")
	var name_l: Label3D = info.get("facade_label")
	if name_l:
		name_l.text = GameState.pub_name
	_refresh_stock_pile()
	_update_lighting(true)


func _refresh_stock_pile() -> void:
	var pile: Node3D = info.get("stock_pile")
	if pile == null:
		return
	for ch in pile.get_children():
		ch.queue_free()
	var i := 0
	for id in GameState.stock.keys():
		if not GameState.drink_available(id):
			continue
		for k in mini(int(GameState.stock[id]), 4):
			var p := Vector3((i % 3) * 0.45 - 0.45, 0, -(i / 3) * 0.45)
			if GameData.drink(id).get("stock_unit", "keg") in ["keg", "cask"]:
				MeshKit.cyl(pile, 0.2, 0.2, 0.6, p + Vector3(0, 0.3, 0), MeshKit.mat("steel_keg"), 16)
			else:
				MeshKit.box(pile, Vector3(0.4, 0.3, 0.3), p + Vector3(0, 0.15, 0), MeshKit.mat("cardboard"))
			i += 1


# ------------------------------------------------------------------ tutorial & messages
func notify(text: String, kind := "info") -> void:
	GameState.notify(text, kind)


func subtitle(who: String, text: String, c: Node3D) -> void:
	if hud and player and c.global_position.distance_to(player.global_position) < 7.0:
		hud.subtitle(who, text)


func _tutorial_event(ev: String) -> void:
	if GameState.tutorial.get("done", false):
		return
	var steps := {
		"start": "Welcome to The Crooked Shamrock! Walk round the end of the bar to the front door and flip the sign to OPEN.",
		"opened": "You're open. Your first customer is on the way. Head back behind the bar.",
		"customer_at_bar": "A customer is waiting at the bar (look for the !). Walk up behind the bar and take their order.",
		"order": "Grab a clean pint glass from the rack on the back counter behind you.",
		"glass": "Take the glass to the brass stout tap on the bar and start pouring.",
		"settle": "While it settles you can serve, wash glasses or wait. Pick it up when it's dark, then top it up at the tap.",
		"served": "Paid! Earnings go in the till. Open the menu (top right) to buy your first upgrade when you can afford it.",
		"dirty": "Customers leave empty glasses behind. Collect them and wash them at the sink beside the rack.",
		"washed": "Clean glass back on the rack. That's the loop. Close up after midnight to finish the day.",
	}
	var order := ["start", "opened", "customer_at_bar", "order", "glass", "settle", "served", "dirty", "washed"]
	var idx := order.find(ev)
	if idx < 0 or idx < tutorial_step:
		return
	tutorial_step = idx + 1
	if hud:
		hud.set_tip(steps[ev])
	if ev == "washed":
		GameState.tutorial["done"] = true


func on_ready_with_hud() -> void:
	_set_sign(GameState.phase != "prep")
	if GameState.phase == "prep":
		notify("Day %d · %s · %s. Flip the sign by the door to open." % [GameState.day, GameState.weekday_name(), GameState.weather.capitalize()])
	start_tutorial()


func start_tutorial() -> void:
	if GameState.tutorial.get("done", false):
		return
	if GameState.phase == "prep":
		_tutorial_event("start")
