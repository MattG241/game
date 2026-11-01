extends Node3D
## Loads the exported .glb files into an empty scene (plain lights only) and renders a few views,
## to check the bake before it goes to Roblox. IN = export folder, SHOTS = output folder.

func _ready() -> void:
	var src := OS.get_environment("IN")
	var shots := OS.get_environment("SHOTS")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src.path_join("manifest.json")))
	for f in m["files"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(src.path_join(f["file"]), st) == OK:
			var scene := doc.generate_scene(st)
			add_child(scene)
	# hide one look of each upgrade (show the bought look)
	var hide_tags := {}
	for c in m["chunks"]:
		if str(c["tag"]).begins_with("hide:"):
			hide_tags[c["name"]] = true
	_hide(self, hide_tags)
	if OS.get_environment("FLIP") != "":
		_flip(self)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.3, 0.25)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	for l in m["lights"]:
		if str(l["tag"]).begins_with("hide:"):
			continue
		var lt: Light3D = SpotLight3D.new() if l["kind"] == "spot" else OmniLight3D.new()
		lt.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		lt.light_energy = l["energy"]
		lt.shadow_enabled = l["shadow"]
		add_child(lt)
		lt.global_position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		if lt is SpotLight3D:
			lt.spot_range = l["range"]
			lt.spot_angle = l["angle"]
			var d := Vector3(l["dir"][0], l["dir"][1], l["dir"][2])
			lt.look_at(lt.global_position + d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
		else:
			lt.omni_range = l["range"]
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	var views := {"room": [Vector3(-0.8, 1.6, -3.2), Vector3(0.0, 1.0, 4.0)], "backbar": [Vector3(-1.0, 1.55, 0.2), Vector3(-1.4, 1.6, -5.0)],
		"hud": [Vector3(1.6, 1.65, -3.4), Vector3(-6.0, 1.0, 1.5)]}
	for k in views.keys():
		cam.global_position = views[k][0]
		cam.look_at(views[k][1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots.path_join("x_%s.png" % k))
	get_tree().quit()


func _flip(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for s in n.mesh.get_surface_count():
			var m = n.mesh.surface_get_material(s)
			if m is BaseMaterial3D and m.albedo_texture:
				var img: Image = m.albedo_texture.get_image()
				img.decompress()
				img.flip_y()
				m.albedo_texture = ImageTexture.create_from_image(img)
	for c in n.get_children():
		_flip(c)


func _hide(n: Node, tags: Dictionary) -> void:
	if tags.has(str(n.name)) and n is Node3D:
		(n as Node3D).visible = false
	for c in n.get_children():
		_hide(c, tags)
