extends Node
## Prints navigation paths between key spots, to check they go round furniture (dev tool).
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	main.start_new("career", "Nav")
	for i in 20:
		await get_tree().physics_frame
	var w: World = main.world
	for pair in [[Vector3(-2, 0, -3.3), Vector3(-1, 0, 1.0)], [Vector3(-2, 0, -3.3), Vector3(3.15, 0, -0.9)], [Vector3(3.15, 0, -0.9), Vector3(1.2, 0, -4.18)], [Vector3(0, 0, 4.2), Vector3(-2, 0, -3.3)]]:
		var p: PackedVector3Array = w.nav_path(pair[0], pair[1])
		var cut := false
		for k in p.size() - 1:
			for s in 10:
				var q: Vector3 = p[k].lerp(p[k + 1], s / 10.0)
				if q.x > PubLayout.BAR_X.x and q.x < PubLayout.BAR_X.y and q.z < PubLayout.BAR_FRONT_Z and q.z > PubLayout.BAR_BACK_Z:
					cut = true
		print("NAV ", pair, " -> ", p, " through bar: ", cut)
	get_tree().quit()
