class_name Nuggets
extends Node3D
## Gold dust nuggets: now and then, while you clean, a nugget hides in dusty ground
## nearby, glinting. Brush the dust off it (or walk / drive onto it) to dig it out:
## a jackpot worth more than a full tank.

const MAX := 2                    # nuggets waiting at once
const EVERY := Vector2(150.0, 300.0)   # seconds of actual cleaning between nuggets
const NEAR := Vector2(8.0, 22.0)  # spawn this far in front of you
const LOSE_AT := 160.0            # forgotten when you go this far away

var world: Node
var _next := 0.0
var _last_m2 := -1.0
var _list: Array[Dictionary] = []    # {node, pos, glint, light, t}
var _sparkle: Shader


func _ready() -> void:
	_sparkle = load("res://shaders/sparkle.gdshader")
	_next = randf_range(EVERY.x, EVERY.y) * 0.5     # the first one comes a little sooner


func _process(delta: float) -> void:
	if world == null:
		return
	var m2 := GameState.stat("m2_cleaned")
	if _last_m2 >= 0.0 and m2 > _last_m2 + 0.0001:
		_next -= delta
	_last_m2 = m2
	if _next <= 0.0 and _list.size() < MAX and spawn():
		_next = randf_range(EVERY.x, EVERY.y)
	var focus: Node3D = world.focus_node()
	var fp := focus.global_position
	var grab := 3.2 if world.current_vehicle else 1.7
	for i in range(_list.size() - 1, -1, -1):
		var n: Dictionary = _list[i]
		n["t"] = float(n["t"]) + delta
		var t: float = n["t"]
		var pos: Vector3 = n["pos"]
		var gm := (n["glint"] as MeshInstance3D).material_override as ShaderMaterial
		var tw := 0.55 + 0.45 * pow(absf(sin(t * 2.3 + i)), 6.0)
		gm.set_shader_parameter("strength", tw * 1.6)
		gm.set_shader_parameter("spin", t * 0.4)
		(n["light"] as OmniLight3D).light_energy = 0.6 + 0.8 * tw
		var d := pos.distance_to(fp)
		if d > LOSE_AT:
			(n["node"] as Node3D).queue_free()
			_list.remove_at(i)
		elif d < grab or GameState.dirt.sample(pos) < 0.12:
			_collect(i)


## Hides a nugget in dusty ground in front of the player. False if no spot found.
func spawn() -> bool:
	var focus: Node3D = world.focus_node()
	var fp := focus.global_position
	var up := fp.normalized()
	var cam := get_viewport().get_camera_3d()
	var fwd := -(cam.global_basis.z if cam else focus.global_basis.z)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	if fwd.length() < 0.5:
		fwd = TerrainGen.frame(up).z
	for attempt in 16:
		var a := randf_range(-0.7, 0.7)
		var dir := fwd.rotated(up, a)
		var p := TerrainGen.surface((fp + dir * randf_range(NEAR.x, NEAR.y)).normalized(), 0.0)
		if GameState.dirt.sample(p) < 0.55 or p.distance_to(AutomationSim.BASE_CENTER) < 40.0:
			continue
		_add(p)
		return true
	return false


func _add(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(TerrainGen.upright(p, TerrainGen.frame(p.normalized()).z), p)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 7
	sm.rings = 4
	rock.mesh = sm
	rock.scale = Vector3(0.34, 0.22, 0.27)
	rock.position = Vector3(0, 0.03, 0)
	rock.rotation = Vector3(randf() * 0.5, randf() * TAU, randf() * 0.5)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.22
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.6, 0.15)
	gold.emission_energy_multiplier = 0.6
	rock.material_override = gold
	root.add_child(rock)
	var glint := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	glint.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = _sparkle
	glint.material_override = gm
	glint.position = Vector3(0, 0.22, 0)
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glint)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.omni_range = 3.0
	light.position = Vector3(0, 0.4, 0)
	root.add_child(light)
	_list.append({"node": root, "pos": p, "glint": glint, "light": light, "t": randf() * 3.0})


## What a nugget is worth: more than a full tank here, and it keeps up late in the game.
func value_at(p: Vector3) -> float:
	var mult := float(GameData.region(TerrainGen.region_of(p))["dust_mult"])
	var tank := GameState.tank_capacity() * GameState.dust_price() * mult
	return maxf(tank * 1.5, GameState.stat("credits_earned") * 0.003)


func _collect(i: int) -> void:
	var n: Dictionary = _list[i]
	_list.remove_at(i)
	var root: Node3D = n["node"]
	var v := value_at(n["pos"])
	GameState.add_credits(v)
	GameState.add_stat("nuggets", 1.0)
	Audio.play("nugget")
	Settings.vibrate(80, 0.7)
	GameState.notify.emit("GOLD NUGGET!  +%s CR" % GameState.fmt(v), "purchase")
	GameState.check_missions()
	# Pops out of the dust, spins up and vanishes in a flash
	var up := root.global_basis.y
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "global_position", root.global_position + up * 1.6, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "rotation:y", root.rotation.y + TAU * 2.0, 0.9)
	tw.tween_property(n["light"], "light_energy", 5.0, 0.4)
	tw.chain().tween_property(root, "scale", Vector3.ONE * 0.01, 0.25)
	tw.chain().tween_callback(root.queue_free)


func count() -> int:
	return _list.size()
