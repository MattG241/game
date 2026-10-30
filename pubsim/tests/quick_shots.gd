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
			"staff", "staff_side", "staff_close":
				# a hired bartender pouring for someone at the bar
				GameState.cash = 500.0
				GameState.hire("ciaran")
				await _wait(0.2)
				var st: StaffMember = w.staff_npcs[0]
				st.global_position = Vector3(-1.0, 0, -2.62)
				st.state = "st_idle"
				var bc := w.spawn_customer()
				bc.global_position = w.bar_spot_pos(3)
				bc.bar_spot = 3
				w.bar_spots[3] = bc
				bc.state = "wait_order"
				bc.rotation.y = 0.0
				var phase := OS.get_environment("POUR_PHASE") if OS.get_environment("POUR_PHASE") != "" else "first"
				for k in 600:
					await _wait(0.1)
					if st.state == "st_pour" and st._pour_phase == phase and st._pour_t > float(OS.get_environment("POUR_T") if OS.get_environment("POUR_T") != "" else "2.0"):
						break
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 50.0
				var tx := st.global_position.x
				if v == "staff":
					cam.global_transform = Transform3D(Basis(), Vector3(tx + 0.3, 1.55, -0.9)).looking_at(Vector3(tx, 1.2, -2.5), Vector3.UP)
				elif v == "staff_side":
					cam.global_transform = Transform3D(Basis(), Vector3(tx + 1.6, 1.5, -2.6)).looking_at(Vector3(tx, 1.2, -2.4), Vector3.UP)
				else:
					cam.global_transform = Transform3D(Basis(), Vector3(tx + 0.75, 1.42, -2.2)).looking_at(Vector3(tx, 1.25, -2.35), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(0.3)
				print("STAFF state=%s phase=%s t=%.1f" % [st.state, st._pour_phase, st._pour_t])
				await _shot(v)
				main.hud.visible = true
				w.player.camera.current = true
			"hud":
				# normal play: the Next line, today's goals and the marker over a waiting customer
				var hc := w.spawn_customer()
				hc.global_position = w.bar_spot_pos(1)
				hc.bar_spot = 1
				w.bar_spots[1] = hc
				hc.state = "wait_order"
				hc.rotation.y = 0.0
				w.player.global_position = Vector3(1.6, 0, -3.6)
				w.player.rotation.y = PI * 0.8
				w.player.camera.current = true
				await _wait(1.5)
				await _shot(v)
			"summary":
				# the end of day 1, as the player sees it after flipping the sign
				GameState.hour = 24.9
				GameState.phase = "closing"
				for sc in w.customers.duplicate():
					sc.queue_free()
				w.customers.clear()
				w.close_day()
				await _wait(1.0)
				await _shot(v)
				var m: MenuPanel = main.hud.menu
				print("SUMMARY scroll max=%d page=%d" % [int(m.scroll.get_v_scroll_bar().max_value), int(m.scroll.size.y)])
				for b in m.find_children("*", "Button", true, false):
					if not (b as Button).is_visible_in_tree():
						continue
					print("SUMMARY button '%s' at %s size %s visible_in_window=%s" % [(b as Button).text, b.global_position, b.size, get_viewport().get_visible_rect().has_point(b.global_position + b.size / 2)])
			"stations", "stations_front":
				for u in ["lager_tap", "ale_pump", "drinks_fridge", "whiskey_optics", "soda_gun"]:
					GameState.upgrades[u] = 1
				GameState.upgrades_changed.emit()
				await _wait(0.5)
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 60.0
				if v == "stations":
					cam.global_transform = Transform3D(Basis(), Vector3(-3.6, 1.65, -3.6)).looking_at(Vector3(-3.6, 1.2, -2.1), Vector3.UP)
				else:
					cam.global_transform = Transform3D(Basis(), Vector3(-3.4, 1.6, -0.3)).looking_at(Vector3(-3.8, 1.2, -2.1), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(0.4)
				await _shot(v)
				main.hud.visible = true
				w.player.camera.current = true
			"matchtv":
				GameState.day = 4
				GameState.upgrades["big_screen"] = 1
				GameState.upgrades_changed.emit()
				GameState.hour = 17.3
				await _wait(3.0)
				for k in 3:
					w.match_day._score()
				if w._cam_tween:
					w._cam_tween.kill()
				cam.fov = 60.0
				cam.global_transform = Transform3D(Basis(), Vector3(-3.6, 1.65, 2.6)).looking_at(Vector3(-6.6, 1.8, 2.2), Vector3.UP)
				cam.current = true
				await _wait(1.0)
				await _shot(v)
				w.player.camera.current = true
			"story":
				GameState.relationships["nora"] = 3
				var sc := w.spawn_customer("nora")
				sc.state = "drinking"
				w._customer_action(sc)
				await _wait(0.6)
				await _shot(v)
				main.hud.dismiss_celebration()
			"session":
				GameState.cash = 3000.0
				GameState.upgrades["house_bodhran"] = 1
				w.live.event_id = "fiddles_fire"
				w.live.finished_tonight = false
				w.live._start(GameData.events_by_id[w.live.event_id])
				await _wait(3.0)
				w.player.global_position = Vector3(-3.6, 0, 2.4)
				w.player.rotation.y = PI * 0.5
				w.session.begin(true)
				await _wait(3.0)
				w.session.tap()
				await _shot(v)
				w.session.stop()
			"menu_upgrades", "menu_staff", "menu_settings":
				main.hud.open_menu(v.substr(5))
				await _wait(0.5)
				await _shot(v)
				main.hud.close_menu()
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
				var dk: Skeleton3D = dc[0]._skel
				for bn in ["upperarm_r", "lowerarm_r", "hand_r", "clavicle_r"]:
					var bi := dk.find_bone(bn)
					var gp := dk.get_bone_global_pose(bi)
					var gr := dk.get_bone_global_rest(bi)
					print("BONE %s pose_o=%s rest_o=%s y=%s" % [bn, str(gp.origin), str(gr.origin), str(gp.basis.y)])
				print("WRIST ", str(dc[0]._body.global_transform.affine_inverse() * dc[0]._elbows[1].get_child(0).global_transform))
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
				var sc: Customer
				if OS.get_environment("SEAT_MODEL") != "":
					var sm := OS.get_environment("SEAT_MODEL")
					sc = Customer.new()
					sc.setup(w, {"model": sm, "gender": sm.substr(0, 1)}, 5)
					w.add_child(sc)
				else:
					sc = w.spawn_customer()
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
			"inst":
				# each instrument close up, seated musician facing the camera
				if w._cam_tween:
					w._cam_tween.kill()
				main.hud.visible = false
				var ang := float(OS.get_environment("INST_ANGLE")) if OS.get_environment("INST_ANGLE") != "" else 0.5
				for kind in ["fiddle", "whistle", "accordion", "bodhran", "guitar", "banjo"]:
					var m := Customer.new()
					m.setup(w, {"gender": "m"}, 4242)
					w.add_child(m)
					m.global_position = Vector3(0.5, 0, 2.6)
					m.rotation.y = PI
					m.make_musician(kind, 0.5)
					m.add_stool()
					var focus := m.global_position + Vector3(0, 0.95, 0)
					cam.fov = 40.0
					cam.global_transform = Transform3D(Basis(), focus + Vector3(sin(ang) * 1.5, 0.3, cos(ang) * 1.5)).looking_at(focus, Vector3.UP)
					cam.current = true
					await _wait(0.7)
					await _shot("inst_" + kind)
					m.queue_free()
					await _wait(0.1)
				main.hud.visible = true
				w.player.camera.current = true
			"mh":
				# the Blender-built MakeHuman characters, standing in the pub
				var names := OS.get_environment("MH_NAMES").split(",", false)
				var x := 0.0
				for n in names:
					var sc: PackedScene = load("res://assets/people_mh/%s.gltf" % n)
					var inst: Node3D = sc.instantiate()
					w.add_child(inst)
					inst.global_position = Vector3(0.2 + x, 0, 2.6)
					x += 0.75
				if w._cam_tween:
					w._cam_tween.kill()
				var cx := 0.2 + (names.size() - 1) * 0.375
				cam.fov = 40.0 if names.size() > 1 else 22.0
				var cy := 1.2 if names.size() > 1 else 1.55
				cam.global_transform = Transform3D(Basis(), Vector3(cx, cy + 0.1, 2.6 - (3.4 if names.size() > 1 else 1.6))).looking_at(Vector3(cx, cy, 2.6), Vector3.UP)
				cam.current = true
				main.hud.visible = false
				await _wait(0.8)
				await _shot("mh")
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
				cam.fov = 45.0 if OS.get_environment("FACE_CLOSE") == "" else 18.0
				cam.global_transform = Transform3D(Basis(), Vector3(1.6, 1.55, 0.2)).looking_at(Vector3(1.6, 1.25 if OS.get_environment("FACE_CLOSE") == "" else 1.6, 2.1), Vector3.UP)
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
