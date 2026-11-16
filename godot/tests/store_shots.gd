extends Node
## Store screenshot director. Builds a staged scene and captures it:
##   godot --path . res://tests/store_shots.tscn -- --scene=brush --out=/tmp/brush.png
## Scenes: title, brush, wide, buggy, automation, shop, map, beam

var _args := {}
var _frames := 0
var _target := 90
var _boot: Node
var game: Node
var scene := "brush"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	scene = _args.get("scene", "brush")
	_target = int(_args.get("frames", "90"))
	Settings.apply_preset("high")
	Settings.values["view_distance"] = 260.0
	Settings.values["perf_overlay"] = false
	get_tree().root.theme = UIKit.theme()
	_boot = load("res://scripts/boot.gd").new()
	add_child(_boot)
	if scene != "title":
		SaveManager.current_slot = 3
		_boot.start_game(-3)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


func _ground(x: float, z: float, up := 0.2) -> Vector3:
	return TerrainGen.map_ground(x, z, up)


## Serpentine cleaned lanes, like a player sweeping an area.
func _lanes(center: Vector3, dir: Vector3, length: float, lanes: int, spacing: float, radius: float, wobble := 0.0) -> void:
	var right := Vector3(-dir.z, 0, dir.x)
	for l in lanes:
		var off := (l - (lanes - 1) * 0.5) * spacing
		var steps := int(length / maxf(radius * 0.5, 0.1))
		for i in steps:
			var t := float(i) / steps
			var p := center + dir * (t * length) + right * (off + sin(t * 12.0 + l) * wobble)
			GameState.dirt.stamp(DirtMap.Shape.ROUND, TerrainGen.map_ground(p.x, p.z), radius, 0.0, Vector3.ZERO, 1.0, 1e9)


func _setup() -> void:
	game = get_tree().get_first_node_in_group("world")
	game.menu.close()
	for i in 5:
		GameState.regions[i] = true
	# Each scene shows an objective that matches its stage of the game.
	var stage: int = {"brush": 5, "wide": 13, "beam": 29, "buggy": 23, "automation": 26, "map": 26, "shop": 8}.get(scene, 5)
	GameState.missions_done = []
	for i in stage:
		GameState.missions_done.append(GameData.missions[i]["id"])
	GameState.stats["play_time"] = 3600.0
	GameState.stats["m2_cleaned"] = 640.0 if scene == "wide" else 18400.0
	GameState.rp = 64.0
	var pl: Player = game.player
	game.controls.visible = _args.get("controls", "0") == "1"
	game.hud.visible = _args.get("hud", "1") == "1"
	match scene:
		"brush":
			GameState.credits = 424.0
			GameState.tools = {"toothbrush": 2, "big_toothbrush": 1, "hand_brush": 2}
			GameState.equip("hand_brush")
			GameState.tank_level = 2
			GameState.tank_dust = 162.0
			var c := Vector3(46, 0, -40)
			var pos := _ground(c.x - 10.0, c.z + 12.0)
			pl.global_position = pos
			pl.yaw = _yaw_to(pos, c + Vector3(-6, 0, -6))
			pl.pitch = -0.42
			var fwd := (c - pos).normalized()
			_lanes(pos + fwd * 2.0, fwd, 12.0, 2, 1.7, 0.48, 0.25)
			_lanes(pos + fwd * 2.0 + Vector3(-fwd.z, 0, fwd.x) * 3.4, fwd, 7.0, 1, 0.0, 0.48, 0.25)
			_lanes(pos + fwd * 2.0 - Vector3(-fwd.z, 0, fwd.x) * 3.4, fwd, 9.5, 1, 0.0, 0.48, 0.25)
		"wide":
			GameState.credits = 48250.0
			GameState.tools = {"toothbrush": 5, "hand_brush": 5, "broom": 3, "electric_scrubber": 3, "industrial_vacuum": 3}
			GameState.equip("industrial_vacuum")
			GameState.tank_level = 6
			GameState.tank_dust = 3900.0
			var pos := _ground(205.0, 25.0)
			var look := pos + Vector3(-0.42, 0, -0.83) * 30.0
			pl.global_position = pos
			pl.yaw = _yaw_to(pos, look)
			pl.pitch = -0.24
			var fwd := (look - pos).normalized()
			_lanes(pos + fwd * 3.0, fwd, 26.0, 2, 4.4, 1.9, 0.5)
		"beam":
			GameState.credits = 912400.0
			GameState.tools = {"toothbrush": 5, "rotary_scrubber": 5, "suction_cleaner": 4, "cleaning_beam": 2}
			GameState.equip("cleaning_beam")
			GameState.tank_level = 8
			GameState.tank_dust = 31200.0
			var pos := _ground(30.0, 320.0, 0.4)
			var look := Vector3(20.0, 0.0, 470.0)
			pl.global_position = pos
			pl.yaw = _yaw_to(pos, look)
			pl.pitch = -0.2
			var fwd := (Vector3(look.x, 0, look.z) - Vector3(pos.x, 0, pos.z)).normalized()
			_lanes(pos + fwd * 6.0, fwd, 40.0, 4, 3.6, 1.8, 0.4)
		"buggy":
			GameState.credits = 71800.0
			GameState.buy_vehicle("vacuum_buggy")
			var pos := _ground(-70.0, 80.0, 1.2)
			game.vehicles[0].global_transform = Transform3D(Basis(Vector3.UP, 2.3), pos)
			var back := Basis(Vector3.UP, 2.3) * Vector3(0, 0, 1)
			for i in 40:
				var p := pos + back * (i * 0.8 + 2.5)
				GameState.dirt.stamp(DirtMap.Shape.RECT, TerrainGen.map_ground(p.x, p.z), 1.6, 0.6, back, 1.0, 1e9)
			_lanes(pos + back * 4.0 + Vector3(-back.z, 0, back.x) * 5.0, back, 30.0, 1, 0.0, 1.6, 0.0)
		"automation", "map":
			GameState.credits = 186300.0
			GameState.tools = {"toothbrush": 5, "electric_scrubber": 4, "portable_vacuum": 2}
			GameState.equip("portable_vacuum")
			var auto: Automation = game.automation
			var spots := [["solar_array", -36, 22], ["solar_array", -42, 28], ["solar_array", -36, 34],
				["dust_collector", 34, 6], ["dust_collector", 44, 18], ["dust_collector", 30, 24],
				["conveyor", 22, 2], ["storage_container", 40, 30], ["charging_station", 52, 6],
				["drone_bay", 56, 16], ["processor", 50, 30], ["shipping_depot", 60, 28]]
			for s in spots:
				auto.add_machine(s[0], _ground(s[1], s[2], 0.0), 0.3)
			for m in GameState.machines:
				if m["id"] == "dust_collector":
					var p := AutomationSim.v3(m["pos"])
					for r in [1.5, 3.0, 4.5, 5.8]:
						for k in 24:
							var a := k * TAU / 24.0
							GameState.dirt.stamp(DirtMap.Shape.ROUND, TerrainGen.map_ground(p.x + cos(a) * r, p.z + sin(a) * r), 1.3, 0.0, Vector3.ZERO, 1.0, 1e9)
			for i in 30:
				auto.sim.tick(1.0)
			var pos := _ground(float(_args.get("ax", "20")), float(_args.get("az", "34")), 0.3)
			pl.global_position = pos
			pl.yaw = _yaw_to(pos, Vector3(42, 0, 18))
			pl.pitch = float(_args.get("ap", "-0.16"))
			pl.cleaner.set_visible_rig(false)
			if scene == "map":
				for k in 60:
					var cx := -120.0 + float(k % 10) * 26.0
					var cz := -80.0 + float(k / 10) * 30.0
					_lanes(Vector3(cx, 0, cz), Vector3(1, 0, 0), 22.0, 3, 3.0, 2.0)
		"shop":
			GameState.credits = 48250.0
			GameState.tools = {"toothbrush": 5, "big_toothbrush": 3, "hand_brush": 5, "broom": 2, "electric_scrubber": 1}
			GameState.equip("electric_scrubber")
			pl.global_position = _ground(-11, 4)
			pl.yaw = _yaw_to(pl.global_position, Vector3(-11, 0, -3))
			pl.pitch = -0.1
	game.terrain.prewarm(game.focus_node().global_position)
	game.terrain.refresh_all_textures()
	# Staged progress shouldn't pop "mission complete" toasts into the shot.
	GameState.active = false


func _process(_d: float) -> void:
	_frames += 1
	if scene != "title":
		if _frames == 4:
			_setup()
		if game == null:
			return
		if _frames == 8 and scene == "buggy":
			game.enter_vehicle(game.vehicles[0])
		if _frames > 10:
			game.terrain.refresh_all_textures()
			if scene == "buggy":
				game.controls.move_vector = Vector2(0.1, -1.0)
				game.vehicles[0].cleaning = true
				game.controls.toggled["clean"] = true
			elif scene in ["brush", "wide", "beam"]:
				game.controls.held["clean"] = true
		if _frames == _target - 25:
			if scene == "shop":
				game.open_menu("shop")
			elif scene == "map":
				game.open_menu("map")
	elif _frames == 3 and _args.has("page"):
		_boot.current.call("_show_" + _args["page"])
	if game and _frames == _target - 2:
		for t in game.hud._toasts.get_children():
			t.queue_free()
	if _frames >= _target:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.get("out", "user://store.png"))
		print("saved ", _args.get("out", ""))
		get_tree().quit()
