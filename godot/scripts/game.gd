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


func _ready() -> void:
	add_to_group("world")
	TerrainGen.setup()
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
	gp.y = maxf(gp.y, TerrainGen.height(gp.x, gp.z) + 0.2)
	player.global_position = gp
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
	if GameState.stat("play_time") < 1.0:
		call_deferred("_intro")


func _intro() -> void:
	menu.show_dialog("WELCOME TO LUNAR CLEANUP CO.",
		"Congratulations on your new job! The Moon is filthy and dust sells for good money back on Earth.\n\nYour equipment: one (1) toothbrush.\n\n- Left thumb: move.   Right thumb: swipe to look.\n- Hold CLEAN and aim at the dusty ground. Slide your thumb while holding CLEAN to sweep.\n- When your tank is full, sell it at the yellow DUST EXCHANGE.\n- Spend credits in the SHOP for bigger and better tools.\n\nGood luck, cleaner.")
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
		var d := Vector2(p.x - fp.x, p.z - fp.z).length()
		var r: float = it["radius"] + (3.5 if current_vehicle else 0.0)
		if d < r and d < best_d and absf(p.y - fp.y) < 8.0:
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


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard/mouse fallback for desktop testing.
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_pressed("clean")
		else:
			_on_released("clean")


func _set_mode(m: String) -> void:
	mode = m
	controls.mode = m
	controls.release_all()
	controls.toggled = {"sprint": player.sprint_toggle} if m == "foot" else {}
	if m == "vehicle":
		controls.defs["clean"]["icon"] = "vacuum"
		controls.defs["clean"]["text"] = "VACUUM"
		controls.defs["jump"]["icon"] = "brake"
		controls.defs["jump"]["text"] = "BRAKE"
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
	GameState.sell(amount, value)


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
		p.y = maxf(p.y, TerrainGen.height(p.x, p.z) + 1.2)
		v.global_transform = Transform3D(Basis(Vector3.UP, float(d.get("yaw", 0.0))), p)
		v.freeze = true
		vehicles.append(v)


func recall_vehicle(i: int) -> void:
	if i >= vehicles.size():
		return
	var v: LunarVehicle = vehicles[i]
	if v == current_vehicle:
		return
	var p := LunarBase.BAY_POS + Vector3(0, 1.5, -6.0 + i * 7.0)
	v.freeze = false
	v.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), p)
	v.linear_velocity = Vector3.ZERO
	v.freeze = true
	GameState.notify.emit("Vehicle returned to the Vehicle Bay", "info")


func enter_vehicle(v: LunarVehicle) -> void:
	if current_vehicle:
		return
	current_vehicle = v
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
	Audio.play("pickup", -4.0)
	_set_mode("vehicle")


func exit_vehicle() -> void:
	var v := current_vehicle
	if v == null:
		return
	v.set_driving(false)
	current_vehicle = null
	var side := v.global_transform * Vector3(-(float(v.info["size"][0]) * 0.5 + 1.3), 0, 0)
	side.y = TerrainGen.height(side.x, side.z) + 0.3
	player.global_position = side
	player.velocity = Vector3.ZERO
	player.yaw = v.global_rotation.y
	player.set_active(true)
	terrain.focus = player
	GameState.player["vehicle"] = -1
	v.save_state()
	_set_mode("foot")


# --------------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if get_tree().paused:
		return
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
	var charging := Vector2(fp.x, fp.z + 2.0).length() < charge_radius
	if not charging:
		for m in GameState.machines:
			if m["id"] == "charging_station" and AutomationSim.v3(m["pos"]).distance_to(fp) < 8.0:
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
			var c := Vector3(lm[1], 0, lm[2])
			if Vector2(c.x - fp.x, c.z - fp.z).length() < float(lm[3]) + 60.0:
				var step := maxf(float(lm[3]) / 14.0, 0.75)
				GameState.landmark_progress[lm[0]] = GameState.dirt.area_clean_fraction(c.x, c.z, float(lm[3]) * 0.92, step)
	if current_vehicle:
		terrain.ensure_collision_near(current_vehicle.global_position)


## Copies live node state into GameState right before saving.
func write_state() -> void:
	if current_vehicle == null:
		var s := player.save_state()
		s["vehicle"] = -1
		GameState.player = s
	else:
		var p := current_vehicle.global_position
		GameState.player = {"pos": [p.x, p.y + 1.0, p.z], "yaw": current_vehicle.global_rotation.y, "pitch": -0.3, "vehicle": current_vehicle.index}
	for v in vehicles:
		(v as LunarVehicle).save_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if GameState.active and is_inside_tree():
			controls.release_all()
