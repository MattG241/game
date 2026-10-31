extends Node
## Renders the pub interior from the middle of the room into six cube faces (run under a display,
## e.g. xvfb-run). tools/bake/cube_to_panorama.py turns them into assets/env/pub_reflection.png,
## which the game uses as the sky that brass, chrome, glass and polished wood reflect.

const FACES := {"px": Vector3(1, 0, 0), "nx": Vector3(-1, 0, 0), "py": Vector3(0, 1, 0),
	"ny": Vector3(0, -1, 0), "pz": Vector3(0, 0, 1), "nz": Vector3(0, 0, -1)}


func _ready() -> void:
	var out := OS.get_environment("BAKE_OUT")
	GameState.delete_save()
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main.start_new("career", "Bake")
	for u in ["lamps", "fireplace", "chalkboard", "drip_tray", "paint", "booths"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	GameState.hour = 21.0
	await get_tree().create_timer(1.0).timeout
	var w: World = main.world
	main.hud.visible = false
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.05
	cam.far = 40.0
	vp.add_child(cam)
	cam.current = true
	var origin := Vector3(-0.6, 1.55, -1.0)
	for k in FACES.keys():
		var dir: Vector3 = FACES[k]
		var up := Vector3.UP if absf(dir.y) < 0.5 else (Vector3(0, 0, -1) if dir.y > 0 else Vector3(0, 0, 1))
		cam.global_transform = Transform3D(Basis(), origin).looking_at(origin + dir, up)
		for i in 4:
			await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.path_join("face_%s.png" % k))
		print("face ", k)
	get_tree().quit()
