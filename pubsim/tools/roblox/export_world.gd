extends Node
## Exports the APK's pub for the Roblox edition: every static surface, baked.
##
## Builds the pub exactly as the game does (with every upgrade, so each upgrade's furniture can
## be shown or hidden in Roblox), then:
##  1. gathers every static mesh surface (skipping people, the door and sign, loose glasses, light
##     cones, flames, sky and other moving or see-through effects),
##  2. groups them into chunks by upgrade and by a grid over the floor plan, at most ~14k
##     triangles each,
##  3. gives each chunk one shared UV layout (Godot's lightmap unwrapper),
##  4. renders every surface into that layout with its own material, unlit: the APK's procedural
##     shaders (tiles, plaster, oak, stone, brass...) and its textures paint the chunk's texture,
##     corner shading and stains included,
##  5. writes the chunks as .glb (one mesh and one baked texture each) and a manifest with each
##     chunk's bounds and upgrade, the see-through pieces and the pub's lights.
##
## OUT = output folder (default res://../pubsim-roblox/assets/world)

const GRID := 3.0              # metres per chunk cell on the floor plan
const MAX_TRIS := 14000
const DENSITY := 190.0         # baked pixels per metre (before the 1024 cap)
const SS := 2                  # supersampling of the bake
const SKIP_SHADERS := ["flame", "light_cone", "liquid", "night_sky", "stream", "glass", "glass_back", "limb", "wall_wash"]
const SEE_THROUGH := {"lace": [Color(0.9, 0.86, 0.77), 0.45], "window_rain": [Color(0.12, 0.16, 0.2), 0.55]}

var out := ""
var info: Dictionary
var skip_roots: Array = []
var tag_of: Dictionary = {}     # node -> "show:id" / "hide:id"
var surfaces: Array = []        # {mesh, surface, xform, mat, tag, inst_color, inst_custom}
var clear: Array = []           # see-through pieces
var lights: Array = []
var labels: Array = []


func _ready() -> void:
	out = OS.get_environment("OUT")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../pubsim-roblox/assets/world")
	DirAccess.make_dir_recursive_absolute(out)
	GameState.delete_save()
	var main: Node = load("res://scripts/main.gd").new()
	add_child(main)
	await _wait(0.6)
	main.start_new("career", "The Crooked Shamrock")
	await _wait(1.0)
	var w: Node = main.world
	info = w.info
	# both looks of every upgrade, shown, so both can be baked
	for key in ["upgrade_show", "upgrade_hide"]:
		for id in info[key].keys():
			for n in info[key][id]:
				if n is Node3D:
					tag_of[n] = ("show:" if key == "upgrade_show" else "hide:") + str(id)
					n.visible = true
	for k in ["door", "rack_glasses", "env", "tv_label", "fire", "fire_light", "facade_label", "chalkboard_label", "door_sign"]:
		if info.get(k) is Node:
			skip_roots.append(info[k])
	for k in ["festival", "rain", "dust", "light_cones", "photos", "door_sign_labels"]:
		for n in info.get(k, []):
			if n is Node and k != "photos":
				skip_roots.append(n)
	await _wait(0.5)
	var nav: Node = w.get_node("Nav")
	_gather(nav, "")
	print("surfaces: %d, see-through: %d, lights: %d" % [surfaces.size(), clear.size(), lights.size()])
	var chunks := _chunk()
	print("chunks: %d" % chunks.size())
	var manifest := {"units": "metres", "chunks": [], "clear": [], "lights": lights, "files": [], "labels": labels,
		"layout": _layout(w)}
	var file_i := 0
	var file_bytes := 0
	var file_root := Node3D.new()
	var file_names: Array = []
	for ci in chunks.size():
		var ch: Dictionary = chunks[ci]
		var name := "c%03d" % ci
		var res := await _bake_chunk(ch, name)
		if res.is_empty():
			continue
		file_root.add_child(res["node"])
		file_names.append(name)
		file_bytes += int(res["bytes"])
		manifest["chunks"].append({"name": name, "tag": ch["tag"], "tris": res["tris"], "min": _v(res["aabb"].position),
			"max": _v(res["aabb"].end), "file": file_i, "tex": res["res"]})
		if file_bytes > 12_000_000 or ci == chunks.size() - 1:
			_write_glb(file_root, file_i)
			manifest["files"].append({"file": "world_%02d.glb" % file_i, "chunks": file_names})
			file_root.free()
			file_root = Node3D.new()
			file_names = []
			file_bytes = 0
			file_i += 1
	if file_root.get_child_count() > 0:
		_write_glb(file_root, file_i)
		manifest["files"].append({"file": "world_%02d.glb" % file_i, "chunks": file_names})
	else:
		file_root.free()
	# see-through pieces (windows, lace): plain meshes with a colour and transparency
	var clear_root := Node3D.new()
	for i in clear.size():
		var c: Dictionary = clear[i]
		var mi := MeshInstance3D.new()
		mi.name = "g%03d" % i
		var am := ArrayMesh.new()
		var arr := _world_arrays(c)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := StandardMaterial3D.new()
		m.albedo_color = c["color"]
		am.surface_set_material(0, m)
		mi.mesh = am
		clear_root.add_child(mi)
		var aabb := am.get_aabb()
		manifest["clear"].append({"name": mi.name, "tag": c["tag"], "color": [c["color"].r, c["color"].g, c["color"].b],
			"transparency": c["alpha"], "min": _v(aabb.position), "max": _v(aabb.end)})
	if clear.size() > 0:
		var st := GLTFState.new()
		var doc := GLTFDocument.new()
		doc.append_from_scene(clear_root, st)
		doc.write_to_filesystem(st, out.path_join("world_clear.glb"))
		manifest["files"].append({"file": "world_clear.glb", "chunks": manifest["clear"].map(func(x): return x["name"])})
	clear_root.free()
	var f := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, " "))
	f.close()
	print("done: %d chunks in %d files" % [manifest["chunks"].size(), manifest["files"].size()])
	get_tree().quit()


## Where things are, for the Roblox scripts: the floor plan constants, every seat, the taps,
## the door and sign, the standing spots.
func _layout(w: Node) -> Dictionary:
	var d := {}
	var consts: Dictionary = (load("res://scripts/world/pub_layout.gd") as Script).get_script_constant_map()
	for k in consts.keys():
		d[k] = _json(consts[k])
	var seats: Array = []
	for st in info.get("seats", []):
		var e := {}
		for k in st.keys():
			e[k] = _json(st[k])
		seats.append(e)
	d["seats"] = seats
	var taps := {}
	for id in info.get("taps", {}).keys():
		var t: Dictionary = info["taps"][id]
		taps[id] = {"nozzle": _json(t.get("nozzle")), "glass": _json(t.get("glass")),
			"root": _json((t["root"] as Node3D).global_position) if t.get("root") is Node3D else null}
	d["taps"] = taps
	if info.get("door") is Node3D:
		var dn: Node3D = info["door"]
		d["door"] = {"pos": _v(dn.global_position), "yaw": dn.global_rotation.y}
	if info.get("door_sign") is Node3D:
		d["door_sign"] = _v((info["door_sign"] as Node3D).global_position)
	var ws: Script = w.get_script()
	var wc: Dictionary = ws.get_script_constant_map()
	if wc.has("STAND_SPOTS"):
		d["STAND_SPOTS"] = _json(wc["STAND_SPOTS"])
	d["rack_slots"] = _json(info.get("rack_slots", []))
	d["sink_slots"] = _json(info.get("sink_slots", []))
	return d


func _json(x):
	if x is Vector3:
		return _v(x)
	if x is Vector2:
		return [x.x, x.y]
	if x is Array:
		return x.map(func(y): return _json(y))
	if x is Dictionary:
		var o := {}
		for k in x.keys():
			o[str(k)] = _json(x[k])
		return o
	if x is Object:
		return null
	return x


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _skipped(n: Node) -> bool:
	for r in skip_roots:
		if r == n:
			return true
	var s = n.get_script()
	if s and s is Script:
		var p: String = s.resource_path
		for bad in ["customer", "staff_member", "pint_glass", "player", "musician"]:
			if p.find(bad) >= 0:
				return true
	return false


func _gather(n: Node, tag: String) -> void:
	if _skipped(n):
		return
	if n is Node3D and not (n as Node3D).visible:
		return
	if tag_of.has(n):
		tag = tag_of[n]
	if n is Label3D and (n as Label3D).billboard == BaseMaterial3D.BILLBOARD_DISABLED and (n as Label3D).text != "":
		var lb: Label3D = n
		var b := lb.global_transform.basis
		labels.append({"text": lb.text, "pos": _v(lb.global_position), "x": _v(b.x), "y": _v(b.y), "z": _v(b.z),
			"pixel": lb.pixel_size, "font_size": lb.font_size, "color": [lb.modulate.r, lb.modulate.g, lb.modulate.b, lb.modulate.a],
			"outline": lb.outline_size, "width": lb.width, "align": lb.horizontal_alignment, "tag": tag,
			"font": lb.font.resource_path if lb.font else ""})
	if n is OmniLight3D or n is SpotLight3D:
		var l: Light3D = n
		var e := {"kind": "spot" if n is SpotLight3D else "omni", "pos": _v(l.global_position), "color": [l.light_color.r, l.light_color.g, l.light_color.b],
			"energy": l.light_energy, "shadow": l.shadow_enabled, "tag": tag}
		if n is SpotLight3D:
			e["range"] = (n as SpotLight3D).spot_range
			e["angle"] = (n as SpotLight3D).spot_angle
			e["dir"] = _v(-l.global_transform.basis.z)
		else:
			e["range"] = (n as OmniLight3D).omni_range
		lights.append(e)
	elif n is MeshInstance3D and n.mesh:
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count():
			_add_surface(mi.mesh, s, mi.global_transform, mi.get_active_material(s), tag, null, null)
	elif n is MultiMeshInstance3D and n.multimesh:
		var mm: MultiMesh = n.multimesh
		for i in mm.instance_count:
			var xf: Transform3D = n.global_transform * mm.get_instance_transform(i)
			var col = mm.get_instance_color(i) if mm.use_colors else null
			var cu = mm.get_instance_custom_data(i) if mm.use_custom_data else null
			for s in mm.mesh.get_surface_count():
				var mat: Material = n.material_override if n.material_override else mm.mesh.surface_get_material(s)
				_add_surface(mm.mesh, s, xf, mat, tag, col, cu)
	for c in n.get_children():
		_gather(c, tag)


func _add_surface(mesh: Mesh, s: int, xf: Transform3D, mat: Material, tag: String, icol, icu) -> void:
	if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
		return
	var e := {"mesh": mesh, "surface": s, "xform": xf, "mat": mat, "tag": tag, "inst_color": icol, "inst_custom": icu}
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		var sp: String = (mat as ShaderMaterial).shader.resource_path.get_file().get_basename()
		if sp in SKIP_SHADERS:
			return
		if SEE_THROUGH.has(sp):
			e["color"] = SEE_THROUGH[sp][0]
			e["alpha"] = SEE_THROUGH[sp][1]
			clear.append(e)
			return
	elif mat is BaseMaterial3D:
		var bm: BaseMaterial3D = mat
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bm.albedo_color.a < 0.97:
			e["color"] = Color(bm.albedo_color.r, bm.albedo_color.g, bm.albedo_color.b)
			e["alpha"] = clampf(1.0 - bm.albedo_color.a, 0.0, 0.95)
			clear.append(e)
			return
	surfaces.append(e)


func _tris(e: Dictionary) -> int:
	var arr: Array = e["mesh"].surface_get_arrays(e["surface"])
	var idx = arr[Mesh.ARRAY_INDEX]
	return (idx.size() if idx else arr[Mesh.ARRAY_VERTEX].size()) / 3


func _chunk() -> Array:
	var cells := {}
	for e in surfaces:
		var aabb: AABB = e["xform"] * e["mesh"].get_aabb()
		var c := aabb.get_center()
		var key := "%s|%d|%d" % [e["tag"], floori(c.x / GRID), floori(c.z / GRID)]
		if not cells.has(key):
			cells[key] = []
		cells[key].append(e)
	var chunks: Array = []
	var keys := cells.keys()
	keys.sort()
	for key in keys:
		var cur: Array = []
		var tris := 0
		for e in cells[key]:
			var t := _tris(e)
			if tris + t > MAX_TRIS and not cur.is_empty():
				chunks.append({"tag": key.split("|")[0], "surfaces": cur})
				cur = []
				tris = 0
			cur.append(e)
			tris += t
		if not cur.is_empty():
			chunks.append({"tag": key.split("|")[0], "surfaces": cur})
	return chunks


## The surface's arrays in world space (positions, normals, uv, colour), unindexed.
func _world_arrays(e: Dictionary) -> Array:
	var src: Array = e["mesh"].surface_get_arrays(e["surface"])
	var xf: Transform3D = e["xform"]
	var nb := xf.basis.inverse().transposed()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var norms = src[Mesh.ARRAY_NORMAL]
	var uvs = src[Mesh.ARRAY_TEX_UV]
	var cols = src[Mesh.ARRAY_COLOR]
	var idx = src[Mesh.ARRAY_INDEX]
	var order: PackedInt32Array = idx if idx else PackedInt32Array(range(verts.size()))
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	v.resize(order.size())
	nrm.resize(order.size())
	uv.resize(order.size())
	col.resize(order.size())
	for i in order.size():
		var k := order[i]
		v[i] = xf * verts[k]
		nrm[i] = (nb * norms[k]).normalized() if norms and norms.size() > k else Vector3.UP
		uv[i] = uvs[k] if uvs and uvs.size() > k else Vector2.ZERO
		col[i] = cols[k] if cols and cols.size() > k else Color.WHITE
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	return arr


func _area(arr: Array) -> float:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var a := 0.0
	for i in range(0, v.size() - 2, 3):
		a += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
	return a


func _bake_chunk(ch: Dictionary, name: String) -> Dictionary:
	# one surface per source surface, in world space, so the unwrapper packs them into one layout
	var am := ArrayMesh.new()
	var area := 0.0
	var srcs: Array = []
	for e in ch["surfaces"]:
		var arr := _world_arrays(e)
		if (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < 3:
			continue
		area += _area(arr)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		srcs.append(e)
	if srcs.is_empty() or area < 0.0005:
		return {}
	var res := clampi(int(nearest_po2(int(sqrt(area) * DENSITY))), 128, 1024)
	var texel := sqrt(area) / float(res) * 1.15
	if am.lightmap_unwrap(Transform3D.IDENTITY, texel) != OK:
		push_warning("%s: unwrap failed" % name)
		return {}
	# render every surface into the layout, unlit, with its own material
	var vp := SubViewport.new()
	vp.size = Vector2i(res * SS, res * SS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 0, 10)
	vp.add_child(cam)
	var count := am.get_surface_count()
	for s in count:
		var e: Dictionary = srcs[s]
		var arr := am.surface_get_arrays(s)
		# back into the source's own space so object-space shaders see what they always see
		var inv: Transform3D = e["xform"].affine_inverse()
		var nb: Basis = e["xform"].basis.transposed()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = inv * v[i]
			if nrm.size() > i:
				nrm[i] = (nb * nrm[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		var local := ArrayMesh.new()
		local.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		local.surface_set_material(0, _bake_material(e))
		var mi := MeshInstance3D.new()
		mi.mesh = local
		mi.extra_cull_margin = 16384.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(mi)
		mi.global_transform = e["xform"]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGBA8)
	var png := out.path_join("_bake_%s.png" % name)
	img.save_png(png)
	# finish the texture in Python (dilate the islands, downsample): it is much faster there
	var outp := out.path_join("_tex_%s.png" % name)
	var py := ProjectSettings.globalize_path("res://tools/roblox/finish_bake.py")
	var code := OS.execute("python3", [py, png, outp, str(res)])
	if code != 0:
		push_warning("%s: finish_bake failed" % name)
		return {}
	var tex_img := Image.load_from_file(outp)
	# one mesh, positions in world space, the bake layout as its only UVs
	var v_all := PackedVector3Array()
	var n_all := PackedVector3Array()
	var uv_all := PackedVector2Array()
	for s in count:
		var arr := am.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var order: PackedInt32Array = idx if idx else PackedInt32Array(range(v.size()))
		for k in order:
			v_all.append(v[k])
			n_all.append(nrm[k] if nrm.size() > k else Vector3.UP)
			uv_all.append(uv2[k])
	var final := []
	final.resize(Mesh.ARRAY_MAX)
	final[Mesh.ARRAY_VERTEX] = v_all
	final[Mesh.ARRAY_NORMAL] = n_all
	final[Mesh.ARRAY_TEX_UV] = uv_all
	var fm := ArrayMesh.new()
	fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(tex_img)
	mat.roughness = 0.8
	fm.surface_set_material(0, mat)
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = fm
	return {"node": node, "tris": v_all.size() / 3, "aabb": fm.get_aabb(), "res": res,
		"bytes": FileAccess.get_file_as_bytes(outp).size() + v_all.size() * 32}


func _write_glb(root: Node3D, i: int) -> void:
	var st := GLTFState.new()
	var doc := GLTFDocument.new()
	doc.image_format = "PNG"
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, out.path_join("world_%02d.glb" % i))
	print("world_%02d.glb: %d chunks (%s)" % [i, root.get_child_count(), error_string(err)])


# ------------------------------------------------------------------ bake materials
var _shader_cache := {}


func _bake_material(e: Dictionary) -> Material:
	var mat: Material = e["mat"]
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		var sm: ShaderMaterial = mat
		var sh := _bake_shader(sm.shader, e["inst_color"] != null or e["inst_custom"] != null)
		var bm := ShaderMaterial.new()
		bm.shader = sh
		for p in sm.shader.get_shader_uniform_list():
			var pn: String = p["name"]
			bm.set_shader_parameter(pn, sm.get_shader_parameter(pn))
		if e["inst_color"] != null:
			bm.set_shader_parameter("_ic", e["inst_color"])
		if e["inst_custom"] != null:
			bm.set_shader_parameter("_icu", e["inst_custom"])
		return bm
	# a standard material: colour x texture x vertex colour, plus its glow
	var m := ShaderMaterial.new()
	m.shader = _std_shader()
	var col := Color.WHITE
	if mat is BaseMaterial3D:
		var b: BaseMaterial3D = mat
		col = b.albedo_color
		if e["inst_color"] != null:
			col *= e["inst_color"]
		m.set_shader_parameter("albedo", col)
		m.set_shader_parameter("has_tex", b.albedo_texture != null)
		if b.albedo_texture:
			m.set_shader_parameter("tex", b.albedo_texture)
		m.set_shader_parameter("uv_scale", Vector2(b.uv1_scale.x, b.uv1_scale.y))
		m.set_shader_parameter("uv_offset", Vector2(b.uv1_offset.x, b.uv1_offset.y))
		m.set_shader_parameter("use_vcol", b.vertex_color_use_as_albedo)
		m.set_shader_parameter("triplanar", b.uv1_triplanar)
		m.set_shader_parameter("tri_sharp", b.uv1_triplanar_sharpness)
		if b.emission_enabled:
			m.set_shader_parameter("emission", b.emission * b.emission_energy_multiplier)
	else:
		m.set_shader_parameter("albedo", Color(0.5, 0.5, 0.5))
	return m


var _std: Shader


func _std_shader() -> Shader:
	if _std:
		return _std
	_std = Shader.new()
	_std.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool use_vcol = false;
uniform bool triplanar = false;
uniform float tri_sharp = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
varying vec3 tp;
varying vec3 tn;
void vertex() {
	tp = VERTEX * vec3(uv_scale, 1.0);
	tn = NORMAL;
	POSITION = vec4(UV2.x * 2.0 - 1.0, 1.0 - UV2.y * 2.0, 0.0, 1.0);
}
void fragment() {
	vec4 c = albedo;
	if (has_tex) {
		if (triplanar) {
			vec3 w = pow(abs(tn), vec3(tri_sharp));
			w /= max(w.x + w.y + w.z, 1e-4);
			c *= texture(tex, tp.zy) * w.x + texture(tex, tp.xz) * w.y + texture(tex, tp.xy) * w.z;
		} else {
			c *= texture(tex, UV * uv_scale + uv_offset);
		}
	}
	if (use_vcol) { c *= COLOR; }
	ALBEDO = min(c.rgb + emission * 0.6, vec3(1.0));
}
"""
	return _std


## The material's own shader, made to paint into the bake layout: unlit, double-sided, every
## triangle placed at its spot in the layout; instance colour/custom data become uniforms.
func _bake_shader(src: Shader, instanced: bool) -> Shader:
	var key := src.resource_path + ("#i" if instanced else "")
	if _shader_cache.has(key):
		return _shader_cache[key]
	var code := src.code
	var lines := code.split("\n")
	var outl: PackedStringArray = []
	var had_mode := false
	for l in lines:
		var t := l.strip_edges()
		if t.begins_with("render_mode"):
			outl.append("render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;")
			had_mode = true
		else:
			outl.append(l)
	code = "\n".join(outl)
	if not had_mode:
		code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;")
	code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform vec4 _ic = vec4(1.0);\nuniform vec4 _icu = vec4(0.0);")
	code = code.replace("INSTANCE_CUSTOM", "_icu")
	var place := "POSITION = vec4(UV2.x * 2.0 - 1.0, 1.0 - UV2.y * 2.0, 0.0, 1.0);"
	var vi := code.find("void vertex()")
	if vi < 0:
		code += "\nvoid vertex() { " + place + " }\n"
	else:
		var open := code.find("{", vi)
		var depth := 0
		var i := open
		while i < code.length():
			var ch := code[i]
			if ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					break
			i += 1
		var body := code.substr(open, i - open)
		if instanced:
			body = body.replace("COLOR", "_ic")
		code = code.substr(0, open) + body + "\n\t" + place + "\n" + code.substr(i)
	var sh := Shader.new()
	sh.code = code
	_shader_cache[key] = sh
	return sh
