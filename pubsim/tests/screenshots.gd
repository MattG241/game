extends Node
## Renders real screenshots of the running game (needs a display: use xvfb-run).
## Output folder is taken from the SHOTS environment variable.

var main: Node
var out := ""


func _ready() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	GameState.delete_save()
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await _wait(1.5)
	await _shot("01_title")
	main.start_new("career", "The Crooked Shamrock")
	await _wait(1.0)
	var w: World = main.world
	GameState.hour = 19.0
	await _shot("02_behind_bar_shabby")
	w._sign_action()
	for i in 4:
		w.spawn_customer()
	await _wait(14.0)
	w.player.global_position = Vector3(-1.4, 0, -3.0)
	w.player.rotation.y = PI
	w.player._pitch = -0.12
	w.player.camera.rotation.x = -0.12
	await _shot("03_customers_at_bar")
	w.player.global_position = Vector3(0.5, 0, 3.8)
	w.player.rotation.y = 0.0
	w.player.camera.rotation.x = -0.05
	await _shot("04_room_view")
	w.player.global_position = Vector3(-1.6, 0, -2.9)
	w.player.rotation.y = PI
	w._rack_action()
	w._tap_action("stout")
	await _wait(0.8)
	var pc: PourController = w.pour
	pc.tilt_input = 0.5
	pc.lever = 1.0
	await _wait(5.0)
	await _shot("05_pouring_cascade")
	var g: PintGlass = w.player.held
	g.contents.body = 0.62
	g.contents.cascade = 0.0
	g.contents.foam = 0.08
	g.contents.stage = 2
	pc.lever = 0.0
	pc.tilt_input = 0.0
	await _wait(1.0)
	pc.lever = 0.35
	await _wait(2.5)
	pc.lever = 0.0
	await _wait(0.5)
	await _shot("06_topping_up")
	pc.end(false)
	await _wait(0.6)
	for u in ["lamps", "fireplace", "chalkboard", "drip_tray", "paint"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	w.player.global_position = Vector3(-2.0, 0, 1.6)
	w.player.rotation.y = deg_to_rad(110)
	w.player.camera.rotation.x = -0.1
	await _shot("07_upgraded_fireplace")
	w.player.global_position = Vector3(0, 0, 9.5)
	w.player.rotation.y = PI
	w.player.camera.rotation.x = 0.05
	await _shot("08_street")
	main.hud.open_menu("upgrades")
	await _wait(0.3)
	await _shot("09_menu")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
