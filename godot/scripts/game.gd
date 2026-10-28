extends Node3D
## The running game world: assembles environment, terrain, base, landmarks, player,
## vehicles, automation and UI; routes touch input by mode; handles interaction,
## selling, autosave and landmark progress.

var boot: Node
var env: LunarEnv
var terrain: Terrain
var base: LunarBase
var landmarks: Landmarks
var player: Player
var automation: Automation
var hud: HUD
var controls: TouchControls
var menu: GameMenu
var ui: CanvasLayer

var vehicles: Array = []          # LunarVehicle per GameState.vehicles index
var current_vehicle: LunarVehicle
var mode := "foot"

var _interactables := {}          # id -> {pos, radius, text: Callable, action: Callable}
var _target_id := ""
var _interact_t := 0.0
var _autosave_t := 0.0
var _landmark_t := 0.0
var _charge_msg_t := 0.0
var _supervisor_idx := 0
var _mouse_clean := false
var ending: Ending


func _ready() -> void:
	add_to_group("world")
	TerrainGen.setup()
	GameState.dirt.covers.clear()
	_make_gravity()
	HexGrid.setup()
	MapView.prepare()
	env = LunarEnv.new()
	add_child(env)
	terrain = Terrain.new()
	add_child(terrain)
	base = LunarBase.new()
	add_child(base)
	base.build(self)
	landmarks = Landmarks.new()
	add_child(landmarks)
	landmarks.build(self)
	_register_covers()
	add_interactable(LunarBase.at(Vector3(4, 0, 21)), 5.0, _lander_text, _lander_action, "lander")
	# UI
	ui = CanvasLayer.new()
	ui.layer = 5
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = HUD.new()
	hud.world = self
	ui.add_child(hud)
	controls = TouchControls.new()
	ui.add_child(controls)
	controls.blockers = hud.touch_buttons()
	menu = GameMenu.new()
	menu.world = self
	ui.add_child(menu)
	menu.closed.connect(_on_menu_closed)
	controls.pressed.connect(_on_pressed)
	controls.released.connect(_on_released)
	# Player
	player = Player.new()
	add_child(player)
	player.setup(controls, self)
	player.load_state(GameState.player)
	var gp := player.global_position
	if TerrainGen.altitude(gp) < 0.2:
		player.global_position = TerrainGen.surface(gp, 0.2)
	terrain.focus = player
	terrain.prewarm(player.global_position)
	# Automation
	automation = Automation.new()
	add_child(automation)
	automation.setup(self)
	# Vehicles
	_spawn_vehicles()
	GameState.vehicles_changed.connect(_spawn_vehicles)
	GameState.mission_completed.connect(_on_mission)
	GameState.active = true
	Audio.play_music(true)
	Audio.loop("ambient", "ambient_base", true, -14.0)
	var veh_index := int(GameState.player.get("vehicle", -1))
	if veh_index >= 0 and veh_index < vehicles.size():
		call_deferred("enter_vehicle", vehicles[veh_index])
	_update_beacon()
	if GameState.flags.has("automation_refund"):
		var r := float(GameState.flags["automation_refund"])
		GameState.flags.erase("automation_refund")
		call_deferred("_automation_news", r)
	if GameState.stat("play_time") < 1.0:
		call_deferred("_intro")


func _intro() -> void:
	menu.show_dialog("WELCOME TO LUNAR CLEANUP CO.",
		"Congratulations on your new job! The Moon is filthy and dust sells for good money back on Earth.\n\nYour equipment: one (1) toothbrush.\n\n- Left thumb: move.   Right thumb: swipe to look.\n- Hold CLEAN and aim at the dusty ground. Slide your thumb while holding CLEAN to sweep.\n- When your tank is full, sell it at the yellow DUST EXCHANGE.\n- Spend credits in the SHOP for bigger and better tools.\n\nGood luck, cleaner.")
	_pause(true)


## Gravity pulls towards the Moon's centre everywhere (rigid bodies: vehicles, props).
## The player's character body applies the same gravity itself.
func _make_gravity() -> void:
	var a := Area3D.new()
	a.name = "MoonGravity"
	a.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	a.gravity_point = true
	a.gravity_point_center = Vector3.ZERO
	a.gravity_point_unit_distance = 0.0
	a.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	a.collision_layer = 0
	a.collision_mask = 0xFFFF
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = TerrainGen.RADIUS * 10.0
	cs.shape = sh
	a.add_child(cs)
	add_child(a)


func _automation_news(refund: float) -> void:
	menu.show_dialog("AUTOMATION, SIMPLIFIED",
		"Machines now work anywhere and sell what they clean by themselves - no power, links or storage - and upgrade from Mk I to Mk V.\n\nYour collectors carried over; drone bays became Drone Hangars and rover garages Hexagon Cleaning Stations. Solar arrays, conveyors, storage, chargers, processors and depots were retired and fully refunded: +%s CR.\n\nSee BUILD > HOW AUTOMATION WORKS." % GameState.fmt(refund))
	_pause(true)


func focus_node() -> Node3D:
	return current_vehicle if current_vehicle else player


# ------------------------------------------------------------- interactables

func add_interactable(pos: Vector3, radius: float, text: Callable, action: Callable, id: String) -> void:
	_interactables[id] = {"pos": pos, "radius": radius, "text": text, "action": action}


func remove_interactable(id: String) -> void:
	_interactables.erase(id)
	if _target_id == id:
		_target_id = ""


func _find_target() -> void:
	var fp := focus_node().global_position
	var best := ""
	var best_d := INF
	for id in _interactables:
		var it: Dictionary = _interactables[id]
		var p: Vector3 = it["pos"]
		var d := AutomationSim.flat_dist(fp, p)
		var r: float = it["radius"] + (3.5 if current_vehicle else 0.0)
		if d < r and d < best_d and absf(p.length() - fp.length()) < 8.0:
			var t: String = it["text"].call()
			if t != "":
				best = id
				best_d = d
	if mode == "foot":
		for v in vehicles:
			var d := (v as Node3D).global_position.distance_to(fp)
			if d < 4.5 and d < best_d:
				best = "vehicle_%d" % (v as LunarVehicle).index
				best_d = d
	_target_id = best
	var text := ""
	if best.begins_with("vehicle_"):
		var vi := int(best.substr(8))
		text = "Drive " + GameData.vehicle(GameState.vehicles[vi]["id"])["name"]
	elif best != "":
		text = _interactables[best]["text"].call()
	hud.set_prompt(text)
	controls.highlight = {"interact": true} if best != "" else {}
	controls.labels["interact"] = "USE" if best == "" else ("SELL" if best == "exchange" else "USE")


func _interact() -> void:
	if _target_id == "":
		return
	if _target_id.begins_with("vehicle_"):
		enter_vehicle(vehicles[int(_target_id.substr(8))])
		return
	var it: Dictionary = _interactables.get(_target_id, {})
	if not it.is_empty():
		Audio.play("ui_click")
		it["action"].call()


# --------------------------------------------------------------------- input

func _on_pressed(id: String) -> void:
	match mode:
		"foot":
			match id:
				"clean":
					if Settings.get_value("clean_toggle", false):
						player.cleaner.cleaning = not player.cleaner.cleaning
						controls.toggled["clean"] = player.cleaner.cleaning
					else:
						player.cleaner.cleaning = true
				"jump":
					player.jump()
				"interact":
					_interact()
				"sprint":
					player.sprint_toggle = not player.sprint_toggle
					controls.toggled["sprint"] = player.sprint_toggle
				"switch":
					GameState.cycle_tool()
					Audio.play("ui_click")
				"menu":
					open_menu("pause")
				"map":
					open_menu("map")
				"missions":
					open_menu("missions")
				"build":
					open_menu("build")
				"shop":
					open_menu("shop")
		"vehicle":
			match id:
				"clean":
					if current_vehicle and float(current_vehicle.info["clean_width"]) > 0.0:
						current_vehicle.cleaning = not current_vehicle.cleaning
						controls.toggled["clean"] = current_vehicle.cleaning
						Audio.play("ui_click")
					else:
						GameState.notify.emit("This vehicle has no cleaning deck", "info")
				"jump":
					if current_vehicle:
						current_vehicle.braking = true
				"exit":
					exit_vehicle()
				"interact":
					_interact()
				"menu":
					open_menu("pause")
				"map":
					open_menu("map")
				"missions":
					open_menu("missions")
				"shop":
					open_menu("shop")
		"place":
			match id:
				"clean":
					if automation.confirm_placement():
						_set_mode("foot")
				"interact":
					automation.cancel_placement()
					_set_mode("foot")
				"switch":
					automation.rotate_ghost()
				"menu":
					automation.cancel_placement()
					_set_mode("foot")


func _on_released(id: String) -> void:
	if id == "clean" and mode == "foot" and not Settings.get_value("clean_toggle", false):
		player.cleaner.cleaning = false
	if id == "jump" and current_vehicle:
		current_vehicle.braking = false


func _input(event: InputEvent) -> void:
	# A real mouse (never the click Android emulates for the first finger).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_clean = event.pressed and not menu.visible


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard fallback for desktop testing.
	if menu.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _on_pressed("interact")
			KEY_SPACE: _on_pressed("jump")
			KEY_Q: _on_pressed("switch")
			KEY_ESCAPE: _on_pressed("menu")
			KEY_F:
				if mode == "vehicle":
					_on_pressed("exit")
	elif event is InputEventKey and not event.pressed:
		if event.keycode == KEY_SPACE:
			_on_released("jump")


## Desktop testing only: hold the left mouse button to clean. Ignored on touchscreens,
## where Android also reports each first finger as an emulated mouse click.
func _desktop_mouse_cleaning() -> bool:
	return _mouse_clean and not menu.visible


func _set_mode(m: String) -> void:
	mode = m
	controls.mode = m
	controls.release_all()
	controls.toggled = {"sprint": player.sprint_toggle} if m == "foot" else {}
	if m == "vehicle":
		var fly := current_vehicle != null and current_vehicle.flying
		controls.defs["clean"]["icon"] = "vacuum"
		controls.defs["clean"]["text"] = "BEAM" if fly else "VACUUM"
		controls.defs["jump"]["icon"] = "up" if fly else "brake"
		controls.defs["jump"]["text"] = "UP" if fly else "BRAKE"
		controls.defs["interact"]["text"] = "USE"
	elif m == "place":
		controls.defs["clean"]["icon"] = "check"
		controls.defs["clean"]["text"] = "BUILD"
		controls.defs["interact"]["icon"] = "cross"
		controls.labels["interact"] = "CANCEL"
		controls.defs["switch"]["text"] = "ROTATE"
	else:
		controls.defs["clean"]["icon"] = "brush"
		controls.defs["clean"]["text"] = "CLEAN"
		controls.defs["jump"]["icon"] = "up"
		controls.defs["jump"]["text"] = "JUMP"
		controls.defs["interact"]["icon"] = "hand"
		controls.defs["switch"]["text"] = "TOOL"
		controls.labels.erase("interact")
	player.cleaner.cleaning = false
	controls.queue_redraw()


# ---------------------------------------------------------------------- menus

func open_menu(tab: String) -> void:
	if mode == "place":
		automation.cancel_placement()
		_set_mode("foot")
	controls.release_all()
	player.cleaner.cleaning = false
	menu.open(tab)
	Diagnostics.event("menu " + tab)
	_pause(true)


func open_machine_panel(uid: int) -> void:
	controls.release_all()
	menu.show_machine(uid)
	_pause(true)


func supervisor_talk() -> void:
	var tips := [
		"Holding CLEAN while sliding your thumb sweeps the brush across the ground. Long continuous strokes are the fastest way to fill your tank.",
		"Cleaned ground can't be cleaned twice - look for the pale dusty areas. Crater floors hold extra-thick dust.",
		"Buy a bigger tank in Shop > Suit. Fewer trips means more cleaning.",
		"Each region has more valuable dust. Unlock them with permits from the Shop.",
		"Machines need power. Build a Solar Array first, then a Dust Collector within 14 m of the Dust Exchange so it sells automatically.",
		"Conveyor Segments link machines up to 16 m apart. Chain them back to base, or use Storage + a Shipping Depot out in the field.",
		"Cleaning drones and rovers need a Charging Station within 45 m of their bay or garage.",
		"Research makes everything better. Cleaning earns research points; so do salvage crates at the old research facility.",
	]
	var m := GameState.current_mission()
	var text: String = tips[_supervisor_idx % tips.size()]
	_supervisor_idx += 1
	if not m.is_empty():
		text = "Current contract: %s\n%s\n\n%s" % [m["title"], m["hint"], text]
	controls.release_all()
	menu.show_dialog("SUPERVISOR GLEAM", text)
	_pause(true)


func _pause(on: bool) -> void:
	get_tree().paused = on
	controls.enabled = not on
	if on:
		Audio.loop("tool", "", false)
		Audio.loop("engine", "", false)
		Audio.loop("vehicle_clean", "", false)


func _on_menu_closed() -> void:
	_pause(false)


func edit_layout() -> void:
	menu.close()
	controls.editing = true
	controls.enabled = true
	GameState.notify.emit("Drag the buttons where you like. Tap the MENU button (top right) when done.", "info")
	controls.pressed.connect(_end_edit_layout, CONNECT_ONE_SHOT)
	controls.mode = "foot"


func _end_edit_layout(_id := "") -> void:
	controls.editing = false
	controls.save_layout()


func begin_placement(id: String) -> void:
	menu.close()
	_pause(false)
	if current_vehicle:
		exit_vehicle()
	_set_mode("place")
	automation.start_placement(id)


func quit_to_menu() -> void:
	SaveManager.save_game(-1, false)
	GameState.active = false
	get_tree().paused = false
	Audio.stop_all_loops()
	boot.show_menu()


func _on_mission(m: Dictionary) -> void:
	pass


# ------------------------------------------------------------------- economy

func vehicle_hopper_amount() -> float:
	return current_vehicle.hopper() if current_vehicle else 0.0


func vehicle_hopper_value() -> float:
	return current_vehicle.hopper_value() if current_vehicle else 0.0


func sell_all() -> void:
	var amount := GameState.tank_dust
	var value := GameState.tank_value
	if current_vehicle:
		var h := current_vehicle.empty_hopper()
		amount += h.x
		value += h.y
	if amount < 0.01:
		GameState.notify.emit("Nothing to sell - go clean something!", "info")
		return
	GameState.tank_dust = 0.0
	GameState.tank_value = 0.0
	GameState.tank_changed.emit(0.0, GameState.tank_capacity())
	var earned := GameState.sell(amount, value)
	# Natural break: occasionally an interstitial, otherwise an optional "double it" offer.
	if not Ads.maybe_show_interstitial() and earned >= float(Ads.config.get("double_sale_min_credits", 25)) \
			and Ads.rewarded_ready():
		hud.offer_double(earned)


## Called when a full-screen ad opens: nothing may stay held underneath it.
func release_input() -> void:
	controls.release_all()
	player.cleaner.cleaning = false
	_mouse_clean = false
	if current_vehicle:
		current_vehicle.throttle = 0.0
		current_vehicle.steer_input = 0.0


# ------------------------------------------------------------------ vehicles

func _spawn_vehicles() -> void:
	for i in GameState.vehicles.size():
		if i < vehicles.size():
			(vehicles[i] as LunarVehicle).refresh_stats()
			continue
		var v := LunarVehicle.new()
		add_child(v)
		v.setup(i)
		var d: Dictionary = GameState.vehicles[i]
		var p := AutomationSim.v3(d["pos"])
		if p.length() < TerrainGen.RADIUS * 0.5:
			p = LunarVehicle.bay_xform().origin
		if TerrainGen.altitude(p) < 1.2:
			p = TerrainGen.surface(p, 1.2)
		v.global_transform = Transform3D(TerrainGen.heading_basis(p, float(d.get("yaw", 0.0))), p)
		v.freeze = true
		vehicles.append(v)


func recall_vehicle(i: int) -> void:
	if i >= vehicles.size():
		return
	var v: LunarVehicle = vehicles[i]
	if v == current_vehicle:
		return
	v.freeze = false
	v.global_transform = LunarBase.at_xform(LunarBase.BAY_POS + Vector3(0, 1.5, -6.0 + i * 7.0), PI * 0.5)
	v.linear_velocity = Vector3.ZERO
	v.freeze = true
	GameState.notify.emit("Vehicle returned to the Vehicle Bay", "info")


func enter_vehicle(v: LunarVehicle) -> void:
	if current_vehicle:
		return
	current_vehicle = v
	Diagnostics.event("enter vehicle " + str(v.info["id"]))
	player.set_active(false)
	player.cleaner.cleaning = false
	v.set_driving(true)
	terrain.focus = v
	terrain.prewarm(v.global_position)
	GameState.player["vehicle"] = v.index
	# Empty the suit tank into the hopper.
	var moved := v.add_hopper(GameState.tank_dust, GameState.tank_value / maxf(GameState.tank_dust, 0.0001))
	if moved > 0.0:
		var frac := moved / GameState.tank_dust
		GameState.tank_value *= (1.0 - frac)
		GameState.tank_dust -= moved
		GameState.tank_changed.emit(GameState.tank_dust, GameState.tank_capacity())
		GameState.notify.emit("Suit tank emptied into the %s hopper (%s / %s) - keep cleaning, sell it all at the Exchange" % [
			v.info["name"], GameState.fmt(v.hopper()), GameState.fmt(float(GameState.vehicle_stats(v.index)["storage"]))], "info")
	Audio.play("pickup", -4.0)
	_set_mode("vehicle")


func exit_vehicle() -> void:
	var v := current_vehicle
	if v == null:
		return
	v.set_driving(false)
	current_vehicle = null
	var side := TerrainGen.surface(v.global_transform * Vector3(-(float(v.info["size"][0]) * 0.5 + 1.3), 0, 0), 0.3)
	player.global_position = side
	player.velocity = Vector3.ZERO
	player.global_basis = TerrainGen.upright(side, -v.global_basis.z)
	player.set_active(true)
	terrain.focus = player
	GameState.player["vehicle"] = -1
	v.save_state()
	_set_mode("foot")


# --------------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	# Cleaning is driven by the live button state every frame (not by press/release
	# events), so a lost touch-release can never leave the brush stuck on.
	if mode == "foot" and not Settings.get_value("clean_toggle", false):
		player.cleaner.cleaning = controls.is_held("clean") or _desktop_mouse_cleaning()
	if current_vehicle:
		current_vehicle.look(controls.consume_look())
		var mv := controls.move_vector
		var kb := Vector2.ZERO
		if Input.is_key_pressed(KEY_W): kb.y -= 1
		if Input.is_key_pressed(KEY_S): kb.y += 1
		if Input.is_key_pressed(KEY_A): kb.x -= 1
		if Input.is_key_pressed(KEY_D): kb.x += 1
		if kb != Vector2.ZERO:
			mv = kb
		current_vehicle.throttle = -mv.y
		current_vehicle.steer_input = -mv.x
	_interact_t -= delta
	if _interact_t <= 0.0:
		_interact_t = 0.15
		_find_target()
	# Battery recharge at base and charging stations
	var fp := focus_node().global_position
	var charge_radius := float(GameData.economy["base_recharge_radius"])
	var charging := fp.distance_to(AutomationSim.BASE_CENTER) < charge_radius
	if not charging:
		for m in GameState.machines:
			if AutomationSim.v3(m["pos"]).distance_to(fp) < 8.0:
				charging = true
				break
	if charging and GameState.battery < GameState.battery_capacity():
		GameState.charge_battery(float(GameData.economy["base_recharge_per_sec"]) * delta)
	# Autosave
	_autosave_t += delta
	if _autosave_t >= float(GameData.economy["autosave_seconds"]):
		_autosave_t = 0.0
		SaveManager.save_game()
	# Landmark cleaning progress (only when near, every 2 s)
	_landmark_t -= delta
	if _landmark_t <= 0.0:
		_landmark_t = 2.0
		for lm in TerrainGen.LANDMARK_CRATERS:
			var c := TerrainGen.map_point(lm[1], lm[2], 0.0)
			if c.distance_to(fp) < float(lm[3]) + 60.0:
				var step := maxf(float(lm[3]) / 14.0, 0.75)
				GameState.landmark_progress[lm[0]] = GameState.dirt.area_clean_fraction(c, float(lm[3]) * 0.92, step)
	if current_vehicle:
		terrain.ensure_collision_near(current_vehicle.global_position)
	_update_dust_finder(delta)
	_update_hexes(delta)


## Ground under buildings and pads gets no dust: it could never be seen or reached.
func _register_covers() -> void:
	var d := GameState.dirt
	d.add_cover_circle(LunarBase.at(Vector3(4.0, 0, 30.0)), 8.3)          # lander pad
	d.add_cover_box(TerrainGen.map_xform(-19.0, 17.0, 0.0), 5.2, 12.2)   # vehicle bay floor
	for root in [base, landmarks]:
		for body in (root as Node).find_children("*", "StaticBody3D", true, false):
			for cs in body.get_children():
				if not (cs is CollisionShape3D and cs.shape is BoxShape3D):
					continue
				var xf: Transform3D = cs.global_transform
				var size: Vector3 = (cs.shape as BoxShape3D).size * xf.basis.get_scale()
				var p := xf.origin
				# Only boxes that sit on the ground (not raised platforms or roofs).
				if TerrainGen.altitude(p) - size.y * 0.5 > 1.0:
					continue
				d.add_cover_box(xf.orthonormalized(), size.x * 0.5, size.z * 0.5)


# ------------------------------------------------------------------ ending

func can_fly_home() -> bool:
	return GameState.missions_done.has("m_clean_moon")


func _lander_text() -> String:
	return "FLY HOME" if can_fly_home() else "Lander (flies home once the Moon is spotless)"


func _lander_action() -> void:
	if not can_fly_home():
		GameState.notify.emit("Not yet - the Moon still has dust on it (%.1f%% clean)" % (GameState.world_clean_fraction() * 100.0), "info")
		return
	if ending == null:
		ending = Ending.new()
		add_child(ending)
		ending.start(self)


# ------------------------------------------------------------ dust finder

var _dust_target := Vector3.INF
var _dust_t := 0.0


## True during the final "clean every speck" mission, once 60% of the Moon is clean.
func hunting_dust() -> bool:
	return str(GameState.current_mission().get("id", "")) == "m_clean_moon" \
		and GameState.world_clean_fraction() >= HUNT_FROM


## The dust finder only helps once most of the Moon is clean.
const HUNT_FROM := 0.6


## Nearest spot with dust left (refreshed once a second while hunting).
func dust_target() -> Vector3:
	return _dust_target


# ------------------------------------------------------------- hexagons

var _hex_t := 0.0
var _sweeps := []         # [cell, chunks still to sweep, m2 swept, paid by player cleaning]


## Watches the hexagons around the player: once one is CLEAR_AT clean (ground measured
## plus machine work), it is finished: the rest is swept and a bonus paid.
func _update_hexes(delta: float) -> void:
	if not _sweeps.is_empty():
		var job: Array = _sweeps[0]
		var todo: Array = job[1]
		if not todo.is_empty():
			job[2] = float(job[2]) + GameState.dirt.sweep_cell(todo.pop_back(), int(job[0]))
			return
		_sweeps.pop_front()
		_hex_bonus(int(job[0]), float(job[2]))
	_hex_t -= delta
	if _hex_t > 0.0:
		return
	_hex_t = 1.0
	var fd := focus_node().global_position.normalized()
	var near := cos(HexGrid.cell_angle * 1.1)
	for cell in HexGrid.candidates(TerrainGen.key_of(fd)):
		if GameState.hexes_done.has(cell) or HexGrid.centers[cell].dot(fd) < near:
			continue
		var f := hex_fraction(cell)
		GameState.hex_frac[cell] = f
		if AutomationSim.hex_progress(cell) >= HexGrid.CLEAR_AT:
			complete_hex(cell)
			return


## Finishes a hexagon (from cleaning by hand or by machines): it counts as done at
## once, chunks made later start clean, loaded ones are swept over the next frames.
func complete_hex(cell: int) -> void:
	if GameState.hexes_done.has(cell):
		return
	GameState.hexes_done.append(cell)
	GameState.hex_frac[cell] = 1.0
	GameState.hex_work.erase(cell)
	GameState.dirt.swept_cells[cell] = true
	var loaded := []
	for k in HexGrid.chunks_of(cell):
		if GameState.dirt.has_chunk(k):
			loaded.append(k)
	_sweeps.append([cell, loaded, 0.0])


## How much of a hexagon is clean (0..1), from points spread over it.
func hex_fraction(cell: int) -> float:
	var pts := HexGrid.samples(cell)
	if pts.is_empty():
		return 1.0
	var n_clean := 0
	for d in pts:
		if GameState.dirt.sample(d * TerrainGen.RADIUS) < 0.05:
			n_clean += 1
	return float(n_clean) / pts.size()


func _hex_bonus(cell: int, swept_m2: float) -> void:
	var c := HexGrid.center_point(cell)
	var rinfo := GameData.region(TerrainGen.region_of(c))
	var mult := float(rinfo["dust_mult"])
	# The swept dust is sold straight away, plus a bonus that grows as you go.
	var dust := swept_m2 * float(GameData.economy["dust_per_m2"]) * float(rinfo["thickness"])
	var bonus := (1500.0 + 150.0 * GameState.hexes_done.size()) * mult + dust * mult * GameState.dust_price()
	GameState.add_credits(bonus)
	GameState.rp += 3
	Audio.play("mission")
	Settings.vibrate(120, 0.6)
	GameState.notify.emit("HEXAGON CLEARED  %d / %d   +%s CR  +3 RP" % [GameState.hexes_done.size(), HexGrid.count(), GameState.fmt(bonus)], "mission")
	Diagnostics.event("hex %d cleared" % cell)
	GameState.check_missions()


## Fraction clean of the hexagon the player is in (for the HUD), -1 when unknown.
func current_hex_fraction() -> float:
	var cell := HexGrid.cell_of(focus_node().global_position)
	if not GameState.hex_frac.has(cell) and not GameState.hex_work.has(cell):
		return -1.0
	return AutomationSim.hex_progress(cell)


# ------------------------------------------------------------- waypoint

var _beacon: MeshInstance3D


## The player's map waypoint (world position on the ground), or Vector3.INF.
func waypoint() -> Vector3:
	var w = GameState.flags.get("waypoint")
	return AutomationSim.v3(w) if w is Array and w.size() == 3 else Vector3.INF


func set_waypoint(p: Vector3) -> void:
	var g := TerrainGen.surface(p)
	GameState.flags["waypoint"] = [g.x, g.y, g.z]
	_update_beacon()
	GameState.notify.emit("Waypoint set - follow the blue arrow and beam", "info")


func clear_waypoint() -> void:
	GameState.flags.erase("waypoint")
	_update_beacon()


## A tall light beam standing on the waypoint, visible from far away.
func _update_beacon() -> void:
	var w := waypoint()
	if not w.is_finite():
		if _beacon:
			_beacon.visible = false
		return
	if _beacon == null:
		_beacon = Meshes.part(self, Meshes.cyl(0.9, 160.0, 12), Meshes.energy(Color(0.3, 0.85, 1.0), 0.7, 0.5, 2.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_beacon.visible = true
	_beacon.global_transform = Transform3D(TerrainGen.upright(w, Vector3.ZERO), w + w.normalized() * 80.0)


func _update_dust_finder(delta: float) -> void:
	_dust_t -= delta
	if _dust_t > 0.0:
		return
	_dust_t = 1.0
	var w := waypoint()
	if w.is_finite() and AutomationSim.flat_dist(focus_node().global_position, w) < 6.0:
		clear_waypoint()
		GameState.notify.emit("Waypoint reached", "info")
	_dust_target = GameState.dirt.nearest_dust(focus_node().global_position) if hunting_dust() else Vector3.INF


## Copies live node state into GameState right before saving.
func write_state() -> void:
	if current_vehicle == null:
		var s := player.save_state()
		s["vehicle"] = -1
		GameState.player = s
	else:
		var p := TerrainGen.surface(current_vehicle.global_position, 1.0)
		GameState.player = {"pos": [p.x, p.y, p.z], "yaw": TerrainGen.yaw_of(p, current_vehicle.global_basis), "pitch": -0.3, "vehicle": current_vehicle.index}
	for v in vehicles:
		(v as LunarVehicle).save_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if GameState.active and is_inside_tree():
			controls.release_all()
