class_name SphereLayout
extends RefCounted
## Stands authored content on the round Moon. Base and landmark builders still lay
## things out on the old flat map (x, z = map coordinates, y = height above the mean
## radius, as TerrainGen.height returns). wrap() then gives every compact piece its own
## anchor on the sphere, so each building stands upright on its own patch of ground.
## Spread-out groups (a ring of barrier posts, a debris field) are split into their
## pieces first; the pieces stay inside their group, so hiding the group still works.

## Pieces bigger than this (metres from their origin) are split into their children.
const MAX_EXTENT := 26.0


## Anchors the children of root on the sphere. root must sit at the map origin with an
## identity transform, its children laid out in map coordinates.
static func wrap(root: Node3D) -> void:
	_wrap_children(root, Vector3.ZERO)


static func _wrap_children(node: Node3D, offset: Vector3) -> void:
	for c in node.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		var flat := offset + n.position
		if n.get_child_count() == 0 or _extent(n) <= MAX_EXTENT:
			_anchor(node, n, flat)
		else:
			# A spread-out group: its children are laid out relative to it.
			_wrap_children(n, flat)
			n.transform = Transform3D.IDENTITY


static func _anchor(parent: Node3D, n: Node3D, flat: Vector3) -> void:
	var anchor := Node3D.new()
	anchor.name = "At_" + n.name
	anchor.transform = TerrainGen.map_xform(flat.x, flat.z, 0.0)
	parent.remove_child(n)
	n.position = Vector3(0, flat.y, 0)
	anchor.add_child(n)
	parent.add_child(anchor)


## Rough size of a node: furthest mesh bound or child origin from its own origin,
## measured across the ground (height doesn't matter for curvature).
static func _extent(n: Node3D) -> float:
	var r := 0.0
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		for c in node.get_children():
			if not (c is Node3D):
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			r = maxf(r, Vector2(cx.origin.x, cx.origin.z).length())
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var b: AABB = cx * (c as MeshInstance3D).mesh.get_aabb()
				for k in 8:
					var p := b.get_endpoint(k)
					r = maxf(r, Vector2(p.x, p.z).length())
			stack.append([c, cx])
	return r
