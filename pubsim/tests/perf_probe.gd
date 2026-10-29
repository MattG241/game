extends Node
## Renders a busy evening (a full pub, a band, every upgrade) under each graphics preset and prints
## draw calls, objects and triangles per frame from the main view. Run under a display (xvfb).
## Frame times here come from a software rasteriser, so only the counts are meaningful.

func _ready() -> void:
	GameState.delete_save()
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	main.start_new("career", "Perf")
	await get_tree().create_timer(1.0).timeout
	for u in ["lamps", "fireplace", "chalkboard", "drip_tray", "paint", "booths", "jukebox", "snug_stage", "sound_system", "dartboard"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	var w: World = main.world
	w._sign_action()
	GameState.hour = 20.5
	GameState.reputation = 70.0
	w.live.event_id = "old_country_jig"
	w.live._start(GameData.events_by_id["old_country_jig"])
	for i in 24:
		var c := w.spawn_customer()
		c.global_position = Vector3(randf_range(-4.5, 4.0), 0, randf_range(-0.5, 4.2))
	await get_tree().create_timer(6.0).timeout
	main.hud.dismiss_celebration()
	w.player.global_position = Vector3(-0.8, 0, -3.0)
	w.player.rotation.y = PI   # facing out over the bar into the room, crowd and band
	print("PERF people in pub: %d" % w.customers.size())
	for pr in ["performance", "balanced", "high", "ultra"]:
		GameState.settings["graphics"] = pr
		w.apply_graphics()
		var shown := mini(w.customers.size(), w.max_customers())
		await get_tree().create_timer(1.0).timeout
		var dc := 0
		var obj := 0
		var tri := 0
		for k in 10:
			await RenderingServer.frame_post_draw
			dc = maxi(dc, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			obj = maxi(obj, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			tri = maxi(tri, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		print("PERF %-11s crowd cap %2d  draw calls %4d  objects %4d  triangles %7d" % [pr, w.max_customers(), dc, obj, tri])
	get_tree().quit()
