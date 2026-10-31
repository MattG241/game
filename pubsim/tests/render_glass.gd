extends Node3D
# Visual check: renders glasses at different pour stages and saves a screenshot.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.08, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.5, 0.4)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-40, 30, 0)
	add_child(l)
	var o := OmniLight3D.new()
	o.position = Vector3(0.2, 0.4, 0.5)
	o.light_color = Color(1, 0.75, 0.45)
	o.light_energy = 2.0
	add_child(o)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.12, 0.62)
	cam.fov = 40
	add_child(cam)
	cam.look_at(Vector3(0, 0.08, 0))
	var states := [
		{"body": 0.0, "cascade": 0.55, "foam": 0.0, "tilt": 40.0},
		{"body": 0.35, "cascade": 0.3, "foam": 0.08, "tilt": 0.0},
		{"body": 0.86, "cascade": 0.0, "foam": 0.155, "tilt": 0.0},
		{"body": 0.6, "cascade": 0.0, "foam": 0.1, "tilt": 0.0, "lace": 0.95},
	]
	for i in states.size():
		var g := PintGlass.new()
		add_child(g)
		g.position = Vector3(-0.27 + i * 0.18, 0, 0)
		g.contents.drink_id = "stout"
		g.contents.serve = "stout"
		g.contents.body = states[i]["body"]
		g.contents.cascade = states[i]["cascade"]
		g.contents.foam = states[i]["foam"]
		g.lace_top = states[i].get("lace", 0.0)
		g.rotation_degrees.z = -states[i]["tilt"]
	var floor_m := MeshKit.box(self, Vector3(2, 0.02, 1), Vector3(0, -0.01, 0), MeshKit.mat("bar_top"))
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT") if OS.get_environment("SHOT") != "" else "user://glass.png")
	get_tree().quit()
