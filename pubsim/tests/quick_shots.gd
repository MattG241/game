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
