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
	# GALAGERS branding: back bar sign and taps from the customer side, and a fresh pint close up
	w.player.global_position = Vector3(-1.2, 0, -0.6)
	w.player.rotation.y = 0.0
	w.player.camera.rotation.x = 0.12
	await _shot("20_brand_backbar")
	var hero := PintGlass.new()
	w.add_child(hero)
	hero.global_position = Vector3(-0.3, PubLayout.BAR_TOP, -1.95)
	hero.rotation.y = DrinkScene.g_yaw()
	hero.contents.drink_id = "stout"
	hero.contents.body = 0.86
	hero.contents.foam = 0.16
	var cam: Camera3D = w.close_cam
	cam.global_transform = Transform3D(Basis(), Vector3(-0.3, PubLayout.BAR_TOP + 0.11, -1.62)).looking_at(Vector3(-0.42, PubLayout.BAR_TOP + 0.085, -1.95), Vector3.UP)
	cam.current = true
	await _wait(0.6)
	await _shot("21_galagers_pint")
	cam.global_transform = Transform3D(Basis(), Vector3(-1.6, PubLayout.BAR_TOP + 0.55, -1.55)).looking_at(Vector3(-1.6, PubLayout.BAR_TOP + 0.5, -2.06), Vector3.UP)
	await _wait(0.3)
	await _shot("22_tap_badge")
	hero.queue_free()
	w.player.camera.current = true
	GameState.upgrades["dartboard"] = 1
	GameState.upgrades_changed.emit()
	w.start_darts()
	await _wait(1.0)
	w.darts.aim = Vector2(0.02, 0.09)
	w.darts.aiming = true
	w.darts.release_throw()
	await _wait(1.0)
	w.darts.aim = Vector2(-0.03, 0.0)
	await _shot("10_darts")
	w.darts.end()
	await _wait(0.6)
	w.start_split()
	await _wait(1.0)
	await _shot("11_split_ready")
	w.drink_scene.press()
	await _wait(1.0)
	await _shot("12_split_drinking")
	await _wait(1.9)
	w.drink_scene.release()
	await _wait(2.6)
	await _shot("13a_split_slowmo")
	for k in 40:
		if w.drink_scene.state == "replay":
			break
		await _wait(0.25)
	await _wait(0.5)
	await _shot("13_split_result")
	w.drink_scene.end()
	await _wait(0.6)
	w.start_relax()
	await _wait(1.0)
	w.drink_scene.press()
	await _wait(1.2)
	await _shot("14_fireside_sip")
	w.drink_scene.release()
	w.drink_scene.end()
	await _wait(0.6)
	# live music: fiddler by the fire
	GameState.cash = 3000.0
	GameState.hour = 19.0
	w.live.book(GameState.day, "fiddles_fire")
	GameState.hour = 20.1
	await _wait(2.0)
	w.player.global_position = Vector3(-2.6, 0, 2.0)
	w.player.rotation.y = deg_to_rad(80)
	w.player.camera.rotation.x = -0.15
	await _shot("15_fiddler_by_fire")
	w.live.stop_now()
	# a band on the stage with dancers
	for u in ["snug_stage", "sound_system", "jukebox", "booths"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	await _wait(0.3)
	main.hud.dismiss_celebration()
	GameState.bookings.erase(str(GameState.day))
	w.live.event_id = "old_country_jig"
	w.live.finished_tonight = false
	for a in GameData.awards:
		GameState.objectives_done.append(a["id"])
	GameState.reputation = 40.0
	for c in w.customers:
		if c.state == "wait_drink" or c.state == "wait_order":
			c.leave()
	for i in 6:
		w.spawn_customer()
	await _wait(1.0)
	w.live._start(GameData.events_by_id["old_country_jig"])
	await _wait(4.0)
	# hand drinks out so a crowd can gather
	for c in w.customers:
		if c.glass == null and c.state in ["wait_order", "wait_drink", "queue", "walk"]:
			var pg := PintGlass.new()
			pg.contents.drink_id = "stout"
			pg.contents.body = 0.8
			pg.contents.foam = 0.1
			c.glass = pg
			c._right_hand.add_child(pg)
			c.state = "stand_drink"
			c.global_position = Vector3(randf_range(1.0, 3.0), 0, randf_range(1.5, 4.0))
	w.live._gather_audience("dance", 6)
	await _wait(4.0)
	main.hud.dismiss_celebration()
	w.player.global_position = Vector3(0.6, 0, 1.2)
	w.player.rotation.y = deg_to_rad(-62)
	w.player.camera.rotation.x = -0.1
	await _shot("16_stage_band_dancers")
	w.live.stop_now()
	w.celebrate("The pub gets bigger!", "Snug Corner Stage\nA low stage for musicians.", "t15")
	await _wait(0.5)
	await _shot("17_celebration")
	main.hud.dismiss_celebration()
	main.hud.open_menu("music")
	await _wait(0.5)
	await _shot("18_jukebox")
	main.hud.menu.show_tab("events")
	await _wait(0.3)
	await _shot("19_events")
	main.hud.close_menu()
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
