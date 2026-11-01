extends Node
## Prints the world's node tree summary: top-level children, mesh counts, triangles, material kinds.

func _ready() -> void:
	GameState.delete_save()
	var main: Node = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	main.start_new("career", "The Crooked Shamrock")
	await get_tree().create_timer(1.0).timeout
	for u in ["lamps", "fireplace", "chalkboard", "drip_tray", "paint", "booths", "jukebox", "snug_stage"]:
		GameState.upgrades[u] = 1
	GameState.upgrades_changed.emit()
	await get_tree().create_timer(1.0).timeout
	var w: Node = main.world
	for ch in w.get_children():
		var st := {"mi": 0, "tri": 0, "shader": 0, "std": 0, "mm": 0}
		_count(ch, st)
		print("%-28s %-22s mi=%d tri=%d std=%d shader=%d multimesh=%d" % [ch.name, ch.get_class(), st.mi, st.tri, st.std, st.shader, st.mm])
	get_tree().quit()


func _count(n: Node, st: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh:
		st.mi += 1
		var m: Mesh = n.mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			st.tri += (idx.size() if idx else arr[Mesh.ARRAY_VERTEX].size()) / 3
			var mat: Material = n.get_active_material(s)
			if mat is ShaderMaterial:
				st.shader += 1
			else:
				st.std += 1
	elif n is MultiMeshInstance3D:
		st.mm += 1
	for c in n.get_children():
		_count(c, st)
