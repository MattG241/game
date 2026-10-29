extends Node
## Fast look at individual views while polishing (xvfb). SHOTS = output folder,
## VIEWS = comma-separated list of: fireside, pour, backbar, room, street, facade, crowd, bottles.

var main: Node
var out := ""


func _ready() -> void:
	out = OS.get_environment("SHOTS")
	var views := OS.get_environment("VIEWS").split(",", false)
	GameState.delete_save()
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await _wait(0.6)
	main.start_new("career", "The Crooked Shamrock")
	await _wait(1.0)
	for u in ["lamps", "fireplace", "chalkboard", "drip_tray", "paint", "booths", "jukebox", "snug_stage"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	GameState.hour = 20.5
	var w: World = main.world
	w._sign_action()
	GameState.reputation = 45.0
	for i in 8:
		var c := w.spawn_customer()
		c.global_position = Vector3(randf_range(-4.0, 3.0), 0, randf_range(0.0, 4.0))
	await _wait(6.0)
	main.hud.dismiss_celebration()
	var cam: Camera3D = w.close_cam
	for v in views:
		match v:
			"fireside":
				w.start_relax()
				await _wait(1.2)
				await _shot(v)
				w.drink_scene.end()
				await _wait(0.6)
			"pour":
				w.player.global_position = Vector3(-1.6, 0, -2.9)
				w.player.rotation.y = PI
				w._rack_action()
				w._tap_action("stout")
				await _wait(0.8)
				w.pour.tilt_input = 0.5
				w.pour.lever = 1.0
				await _wait(4.0)
				await _shot(v)
				w.pour.end(false)
				await _wait(0.6)
				var g = w.player.release_glass()
				if g:
					g.queue_free()
			"band", "fiddler":
				GameState.cash = 3000.0
				w.live.event_id = "old_country_jig" if v == "band" else "fiddles_fire"
				w.live.finished_tonight = false
				w.live._start(GameData.events_by_id[w.live.event_id])
				await _wait(3.0)
				if v == "band":
					w.live._gather_audience("dance", 6)
				await _wait(3.5)
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 55.0
				if v == "band":
					cam.global_transform = Transform3D(Basis(), Vector3(2.2, 1.6, 0.6)).looking_at(Vector3(5.6, 1.0, 3.6), Vector3.UP)
				else:
					cam.global_transform = Transform3D(Basis(), Vector3(-3.4, 1.5, 1.6)).looking_at(Vector3(-5.6, 0.9, 2.2), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(0.6)
				await _shot(v)
				main.hud.visible = true
				w.live.stop_now()
				w.player.camera.current = true
			"barwait":
				var bc := w.spawn_customer()
				bc.global_position = w.bar_spot_pos(3)
				bc.state = "wait_order"
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 55.0
				cam.global_transform = Transform3D(Basis(), Vector3(-1.0, 1.6, -3.0)).looking_at(Vector3(-1.0, 1.4, -1.2), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(1.5)
				await _shot(v)
				main.hud.visible = true
				w.player.camera.current = true
			"split":
				w.start_split()
				await _wait(1.0)
				var ds: DrinkScene = w.drink_scene
				ds.press()
				await _wait(1.5)
				ds.release()
				for k in 8:
					await _wait(1.0)
					print("SPLIT t=%d state=%s reveal_t=%.2f settle=%.2f" % [k + 1, ds.state, ds._reveal_t, ds._settle_t])
				await _shot(v)
				ds.end()
				await _wait(0.6)
			"drinkers":
				# a standing drinker side-on and one facing the camera, frozen through a sip
				var dc: Array = []
				for i in 2:
					var c := w.spawn_customer()
					c.global_position = [Vector3(1.0, 0, 2.0), Vector3(1.9, 0, 2.0)][i]
					var g := PintGlass.new()
					g.contents.drink_id = "stout"
					g.contents.serve = "stout"
					g.contents.stage = 3
					g.contents.body = 0.88
					g.contents.foam = 0.1
					c.receive_drink(g)
					c.state = "stand_drink"
					c._react_t = 0.0
					c.rotation.y = [PI * 0.5, 0.0][i]
					c._sip_t = 999.0
					dc.append(c)
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 40.0
				cam.global_transform = Transform3D(Basis(), Vector3(1.45, 1.5, 0.2)).looking_at(Vector3(1.45, 1.25, 2.0), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(1.0)
				await _shot("drink_hold")
				for c in dc:
					c._sip_t = 0.0
				while dc[0]._sip_phase <= 0.0 or dc[0]._sip_phase > dc[0]._sip_dur * 0.85:
					await get_tree().process_frame
				await _shot("drink_lift")
				while dc[0]._sip_phase > dc[0]._sip_dur * 0.5:
					await get_tree().process_frame
				await _shot("drink_sip")
				for c in dc:
					var lips: Vector3 = c._head.global_transform * Vector3(0, -0.05, -0.105)
					var rim: Vector3 = c.glass.global_transform * Vector3(0, c.glass.height, 0.04)
					print("SIP phase=%.2f kind=%s w=%.2f rim-lips=%.3f goal=%s glass=%s" % [c._sip_phase, c._sip_kind, c._ik_w, rim.distance_to(lips), str(c._ik_goal), str(c._body.to_local(c.glass.global_position))])
				main.hud.visible = true
				w.player.camera.current = true
			"seated":
				# someone sits down with a pint, puts it on the table, then picks it up for a sip
				var si := 0
				var sd: Dictionary = w.seat_info(si)
				var sc := w.spawn_customer()
				var sg := PintGlass.new()
				sg.contents.drink_id = "stout"
				sg.contents.serve = "stout"
				sg.contents.stage = 3
				sg.contents.body = 0.88
				sg.contents.foam = 0.1
				sc.receive_drink(sg)
				sc._react_t = 99.0
				sc.global_position = sd["pos"]
				sc.seat = si
				sc._seat_yaw = sd["yaw"]
				sc._after_path = "seated"
				sc._arrive()
				sc._sip_t = 999.0
				var side: Vector3 = sc.global_transform.basis.x
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 42.0
				cam.global_transform = Transform3D(Basis(), sd["pos"] + side * 1.7 + Vector3(0, 1.25, 0) - sc.global_transform.basis.z * 0.25).looking_at(sd["pos"] + Vector3(0, 0.95, 0) - sc.global_transform.basis.z * 0.25, Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(0.5)
				await _shot("seat_put")
				while sc._sip_kind != "":
					await get_tree().process_frame
				await _wait(0.5)
				await _shot("seat_rest")
				sc._sip_t = 0.0
				while sc._sip_phase <= 0.0 or sc._sip_phase > sc._sip_dur * 0.88:
					await get_tree().process_frame
				await _shot("seat_reach")
				while sc._sip_phase > sc._sip_dur * 0.5:
					await get_tree().process_frame
				await _shot("seat_sip")
				print("SEAT glass parent=%s spot=%s glass=%s kind=%s phase=%.2f dur=%.2f state=%s seated=%s body=%s" % [sc.glass.get_parent().name, str(sc._glass_spot), str(sc.glass.global_position), sc._sip_kind, sc._sip_phase, sc._sip_dur, sc.state, sc._seated, str(sc._body.to_local(sc._glass_spot))])
				main.hud.visible = true
				w.player.camera.current = true
			"faces":
				# three people standing chatting, close up
				var spots := [Vector3(1.0, 0, 2.0), Vector3(1.6, 0, 2.15), Vector3(2.2, 0, 2.0)]
				for i in 3:
					var c := w.spawn_customer()
					c.global_position = spots[i]
					c.state = "idle"
					c.rotation.y = 0.0
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 45.0
				cam.global_transform = Transform3D(Basis(), Vector3(1.6, 1.55, 0.2)).looking_at(Vector3(1.6, 1.25, 2.1), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(1.0)
				await _shot(v)
				main.hud.visible = true
				w.player.camera.current = true
			_:
				var views_cam := {
					"backbar": [Vector3(-1.0, 1.55, 0.2), Vector3(-1.4, 1.6, -5.0)],
					"room": [Vector3(-0.8, 1.6, -3.2), Vector3(0.0, 1.0, 4.0)],
					"street": [Vector3(0.0, 1.6, 12.5), Vector3(0.0, 3.0, 5.0)],
					"facade": [Vector3(3.5, 1.7, 10.0), Vector3(0.0, 1.8, 5.0)],
					"crowd": [Vector3(1.5, 1.6, -0.5), Vector3(-3.0, 1.0, 3.0)],
					"bottles": [Vector3(-2.0, 1.75, -3.6), Vector3(-2.0, 1.7, -5.0)],
					"terrace": [Vector3(-2.0, 1.7, 6.6), Vector3(0.0, 3.0, 14.0)],
					"window": [Vector3(-4.0, 1.55, 3.7), Vector3(-4.2, 1.6, 5.2)],
				}
				if views_cam.has(v):
					var pr: Array = views_cam[v]
					if w._cam_tween:
						w._cam_tween.kill()
					cam.fov = 60.0
					cam.global_transform = Transform3D(Basis(), pr[0]).looking_at(pr[1], Vector3.UP)
					cam.current = true
					main.hud.visible = false
					await _wait(0.8)
					await _shot(v)
					main.hud.visible = true
					w.player.camera.current = true
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("q_" + name + ".png"))
