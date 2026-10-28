extends Node
## Screenshot harness: godot --path . res://tests/shot.tscn -- --mode=game --out=/tmp/a.png --frames=120
## Used during development and in CI to capture what the game actually renders.

var _args := {}
var _frames := 0
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
			var p: PackedStringArray = _args["pos"].split(",")
			pl.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
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
			game.automation.add_machine("solar_array", Vector3(40, TerrainGen.height(40, 4), 4), 0.0)
			game.automation.add_machine("charging_station", Vector3(46, TerrainGen.height(46, 10), 10), 0.0)
		game.begin_placement(_args["place"])
	if game and _args.has("ending"):
		if _frames == 10:
			GameState.missions_done.append("m_clean_moon")
			game._lander_action()
		if _frames == _target - 30 and game.ending:
			game.ending._t = float(_args["ending"])
	if game and _args.has("menu") and _frames == _target - 20:
		game.open_menu(_args["menu"])
	if _frames >= _target:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.get("out", "user://shot.png"))
		print("saved ", _args.get("out", "user://shot.png"))
		get_tree().quit()
