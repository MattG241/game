extends Node
## Screenshot harness: godot --path . res://tests/shot.tscn -- --mode=game --out=/tmp/a.png --frames=120
## Used during development and in CI to capture what the game actually renders.

var _args := {}
var _frames := 0
const SHOWER_SKIP := 12.0   # jump into the shower's peak
var _target := 120
var _boot: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_target = int(_args.get("frames", "120"))
	get_tree().root.theme = UIKit.theme()
	_boot = load("res://scripts/boot.gd").new()
	if _args.get("mode", "menu") == "game":
		# Start a fresh game without touching the real save slots.
		SaveManager.current_slot = 3
		_boot.set("current", null)
		add_child(_boot)
		_boot.start_game(-3)
		if _args.has("credits"):
			GameState.credits = float(_args["credits"])
	else:
		add_child(_boot)


func _process(_d: float) -> void:
	_frames += 1
	var game := get_tree().get_first_node_in_group("world")
	if game == null and _args.has("page") and _frames == 5:
		_boot.current.call("_show_" + _args["page"])
	if game == null and _args.has("scroll") and _frames == 8:
		for sc in _boot.current.find_children("*", "ScrollContainer", true, false):
			(sc as ScrollContainer).scroll_vertical = int(_args["scroll"])
	if game and _frames == 5:
		game.menu.close()
		var pl: Node = game.player
		if _args.has("yaw"):
			pl.yaw = float(_args["yaw"])
		if _args.has("pitch"):
			pl.pitch = float(_args["pitch"])
		if _args.has("pos"):
			# Map coordinates x,z[,height above the ground]
			var p: PackedStringArray = _args["pos"].split(",")
			pl.global_position = TerrainGen.map_ground(float(p[0]), float(p[1]), float(p[2]) if p.size() > 2 else 0.2)
			game.terrain.prewarm(pl.global_position)
			if _args.has("yaw"):
				pl.yaw = float(_args["yaw"])
		if _args.has("unlock"):
			for i in GameState.regions.size():
				GameState.regions[i] = true
		if _args.has("tool"):
			GameState.tools[_args["tool"]] = 0
			GameState.equip(_args["tool"])
	if game and _args.has("vehicle"):
		if _frames == 6:
			GameState.credits = 1e7
			GameState.buy_vehicle(_args["vehicle"])
		if _frames == 8:
			game.enter_vehicle(game.vehicles[0])
		if _frames > 12:
			game.controls.move_vector = Vector2(0.15, -1.0)
			game.vehicles[0].cleaning = true
	if game and _args.has("clean") and _frames > 10 and _frames < _target - 5:
		game.controls.held["clean"] = true
		game.player.yaw += 0.01 * sin(_frames * 0.05)
	if game and _args.has("place") and _frames == 10:
		GameState.credits = 1e6
		if _args.has("prebuild"):
			game.automation.add_machine("solar_array", TerrainGen.map_ground(40, 4), 0.0)
			game.automation.add_machine("charging_station", TerrainGen.map_ground(46, 10), 0.0)
		game.begin_placement(_args["place"])
	if game and _args.has("film"):
		# The finale as at the end of a long game: everything clean, real-looking stats.
		if _frames == 4:
			for i in GameState.regions.size():
				GameState.regions[i] = true
			GameState.stats["play_time"] = 5 * 3600 + 12 * 60
			GameState.stats["m2_cleaned"] = 1130000.0
			GameState.stats["credits_earned"] = 48250000.0
			GameState.stats["dust_sold"] = 9200000.0
			GameState.hexes_done.clear()
			for c in HexGrid.count():
				GameState.hexes_done.append(c)
				GameState.dirt.swept_cells[c] = true
			for key in GameState.dirt.chunks.keys():
				for c in HexGrid.candidates(key):
					GameState.dirt.sweep_cell(key, c)
		if _frames == 12:
			GameState.missions_done.append("m_clean_moon")
			game._lander_action()
	if game and _args.has("shower") and _frames == 6:
		game.env.start_shower()
		game.env._shower_t = SHOWER_SKIP
	if game and _args.has("nugget") and _frames == 20:
		game.nuggets._next = 0.0
		game.nuggets._last_m2 = -1.0
		print("nugget spawned: ", game.nuggets.spawn(), " count ", game.nuggets.count(), " at ", game.nuggets._list[0]["pos"] if game.nuggets.count() > 0 else "-", " player ", game.player.global_position, " dirt ", GameState.dirt.sample(game.player.global_position))
	if game and _args.has("holo") and _frames == 20:
		if _args["holo"] == "point":
			game.hologram.say("That hexagon's 72% done - finish it off! 85 m that way.", 30.0, game.player.global_position + game.player.global_basis.x * 60.0)
		else:
			game.supervisor_talk()
	if game and _args.has("hexflash") and _frames == 40:
		# Clear a hexagon a little ahead of the player to show the effect.
		var pl: Node3D = game.player
		game.complete_hex(HexGrid.cell_of(pl.global_position))
	if game and _args.has("ending"):
		if _frames == 10:
			GameState.missions_done.append("m_clean_moon")
			game._lander_action()
		if _frames == _target - 30 and game.ending:
			game.ending._t = float(_args["ending"])
		if game.ending and _frames > _target - 30 and _frames % 5 == 0 and _args.has("debug"):
			print("t ", game.ending._t, " alt ", TerrainGen.altitude(game.base.lander.global_position), " lander ", game.base.lander.global_position, " same ", game.base.lander == game.ending._lander)
	if game and _args.has("skin") and _frames == 8:
		for id in _args["skin"].split(","):
			Cosmetics.unlock(id)
			Cosmetics.equip(id)
	if game and _args.has("menu") and _frames == _target - 20:
		game.open_menu(_args["menu"])
	if game and _args.has("machines") and _frames == 12:
		GameState.credits = 1e7
		game.automation.add_machine("hex_station", TerrainGen.map_ground(20, 30), 0.3)
		game.automation.add_machine("drone_hangar", TerrainGen.map_ground(30, 18), 0.6)
		game.automation.add_machine("dust_collector", TerrainGen.map_ground(14, 18), 0.0)
	if game and _args.has("vehicle") and _args["vehicle"] == "lunar_ufo" and _frames > 30 and _frames < 60:
		game.vehicles[0].braking = true
	if game and _args.has("helpdialog") and _frames == _target - 10:
		game.menu.show_dialog("HOW AUTOMATION WORKS", GameMenu.AUTOMATION_HELP)
	if _frames >= _target:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.get("out", "user://shot.png"))
		print("saved ", _args.get("out", "user://shot.png"))
		get_tree().quit()
