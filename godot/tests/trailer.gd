extends Node
## Trailer shots: real gameplay, staged. Each clip sets up the world, drives the
## controls frame by frame and (for cinematic shots) flies its own camera.
## godot --write-movie clip.avi --fixed-fps 30 --path . res://tests/trailer.tscn -- --clip=brush --frames=180

var _args := {}
var _f := 0
var _target := 180
var _boot: Node
var game: Node
var cam: Camera3D
var _v: LunarVehicle
var _p0 := Vector3.ZERO      # anchor point of the shot
var _m := {}                 # scratch for clips


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_target = int(_args.get("frames", "180"))
	get_tree().root.theme = UIKit.theme()
	_boot = load("res://scripts/boot.gd").new()
	SaveManager.current_slot = 3
	_boot.set("current", null)
	add_child(_boot)
	_boot.start_game(-3)


func _process(delta: float) -> void:
	_f += 1
	if game == null:
		game = get_tree().get_first_node_in_group("world")
		if game == null:
			return
	if _f == 3:
		_setup_common()
	if _f == 6:
		for c in game.hud._toasts.get_children():
			c.queue_free()
	if _f >= 4:
		call("_clip_" + _args.get("clip", "brush"), _f - 4, delta)
	if _f >= _target:
		get_tree().quit()


# ------------------------------------------------------------------ helpers

func _setup_common() -> void:
	game.menu.close()
	GameState.credits = 2.5e6
	# Mid-game state: early contracts and achievements already done (no pop-up storm).
	for a in GameData.achievements:
		GameState.achievements_done.append(a["id"])
	for m in GameData.missions:
		if m["id"] != "m_clean_moon" and m["id"] != "m_go_home":
			GameState.missions_done.append(m["id"])
	for i in GameState.regions.size():
		GameState.regions[i] = true
	# A quiet world for filming: no surprise pop-ups, hints or nuggets.
	game.hologram.quiet = true
	game.nuggets._next = 1e9
	game.env._shower_in = 1e9
	var hud: bool = _args.has("hud")
	game.hud.visible = hud
	game.controls.visible = hud
	if hud:
		GameState.notify.connect(func(_t, _k): pass)


func _free_cam() -> Camera3D:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 60.0
		cam.near = 0.1
		cam.far = 2600.0
		game.add_child(cam)
	cam.current = true
	return cam


## Point the free camera from pos at target, keeping "up" away from the Moon's centre.
func _look(pos: Vector3, target: Vector3) -> void:
	var c := _free_cam()
	c.global_position = pos
	c.look_at(target, pos.normalized())


func _place_player(x: float, z: float, yaw: float, pitch: float) -> void:
	var pl: Player = game.player
	pl.global_position = TerrainGen.map_ground(x, z, 0.2)
	pl.yaw = yaw
	pl.pitch = pitch
	game.terrain.prewarm(pl.global_position)


func _vehicle(id: String, x: float, z: float, yaw: float) -> LunarVehicle:
	GameState.buy_vehicle(id)
	var v: LunarVehicle = game.vehicles[game.vehicles.size() - 1]
	var p := TerrainGen.map_ground(x, z, 1.2)
	v.global_transform = Transform3D(TerrainGen.heading_basis(p, yaw), p)
	game.terrain.prewarm(p)
	return v


func _frame(p: Vector3) -> Basis:
	return TerrainGen.frame(p.normalized())


# ------------------------------------------------------------------ clips

## First person with the toothbrush: one long sweep through thick dust (HUD on).
func _clip_brush(t: int, _d: float) -> void:
	if t == 0:
		_place_player(70, 40, 1.0, -0.62)
		GameState.tools["big_toothbrush"] = 3
		GameState.equip("big_toothbrush")
	if t > 8:
		game.controls.held["clean"] = true
		game.player.yaw += 0.006 * sin(t * 0.035)
		game.controls.move_vector = Vector2(0.0, -0.25) if t > 60 else Vector2.ZERO


## Third person, rainbow brush and hazard suit, walking and cleaning; the camera
## swings round in front of the astronaut.
func _clip_third(t: int, _d: float) -> void:
	if t == 0:
		_place_player(-60, -70, 2.2, -0.5)
		Cosmetics.unlock("suit_hazard")
		Cosmetics.unlock("tool_rainbow")
		Cosmetics.equip("suit_hazard")
		Cosmetics.equip("tool_rainbow")
		GameState.tools["hand_brush"] = 4
		GameState.equip("hand_brush")
		game.player.set_third_person(true, false)
	if t > 6:
		game.controls.held["clean"] = true
		game.controls.move_vector = Vector2(0.0, -0.5)
		game.player.yaw += 0.006
	if t > 8 and not _args.has("tp"):
		var pl: Player = game.player
		var pp := pl.global_position
		var b := pl.global_basis
		var k := t / float(_target)
		var a := 0.5 + k * 1.1
		var off := (-b.z * cos(a) + b.x * sin(a)) * 5.5 + pp.normalized() * (2.2 - 0.6 * k)
		_look(pp + off, pp + pp.normalized() * 0.9 - b.z * 1.2)


## The Wide-Area Cleaning Beam in first person: dust lifted from 20 m away (HUD on).
func _clip_beam(t: int, _d: float) -> void:
	if t == 0:
		_place_player(90, 50, 0.9, -0.22)
		GameState.tools["cleaning_beam"] = 4
		GameState.equip("cleaning_beam")
		GameState.tank_level = 6
		GameState.battery_level = 6
		GameState.battery = GameState.battery_capacity()
	if t > 6:
		game.controls.held["clean"] = true
		game.player.yaw += 0.01 * sin(t * 0.02)
		game.controls.move_vector = Vector2(0, -0.35)


## Slow crane over the base under the Milky Way.
func _clip_base(t: int, _d: float) -> void:
	if t == 0:
		_place_player(0, 60, 0.0, 0.0)
		game.player.visible = false
		_p0 = LunarBase.at(Vector3(4, 0, 10))
	var k := t / float(_target)
	var b := _frame(_p0)
	var a := 0.9 + k * 0.7
	var pos := _p0 + (b.x * cos(a) + b.z * sin(a)) * (55.0 - 12.0 * k) + b.y * (30.0 - 18.0 * k)
	_look(pos, _p0 + b.y * (6.0 - 2.0 * k))


## Looking up from the ground into the sky: Milky Way, planets, a meteor shower.
func _clip_sky(t: int, _d: float) -> void:
	if t == 0:
		_place_player(50, -80, 0.0, 0.0)
		game.player.visible = false
		game.env.start_shower()
		game.env._shower_t = 12.0
		_p0 = TerrainGen.map_ground(50, -80, 1.6)
	var k := t / float(_target)
	var b := _frame(_p0)
	var dir := (b.y * (1.1 - 0.75 * k) - b.z * 1.0 + b.x * (0.6 - 0.9 * k)).normalized()
	_look(_p0, _p0 + dir * 10.0)


## Cleaning Truck chase: a 14 m boom eating a stripe through the dust.
func _clip_truck(t: int, _d: float) -> void:
	if t == 0:
		_place_player(0, 215, 0.0, 0.0)
		_v = _vehicle("cleaning_truck", 0, 225, 0.2)
		game.enter_vehicle(_v)
	if t > 4:
		_v.cleaning = true
		game.controls.move_vector = Vector2(0.12 * sin(t * 0.02), -1.0)
	if t > 6:
		var vp := _v.global_position
		var b := _v.global_basis
		var k := t / float(_target)
		var side := b.x * (9.0 - 16.0 * k)
		_look(vp + b.z * 15.0 + side + vp.normalized() * (4.5 + 1.5 * k), vp - b.z * 3.0)


## The Lunar Saucer skimming the ground, beam on, camera flying alongside.
func _clip_saucer(t: int, _d: float) -> void:
	if t == 0:
		_place_player(-150, 180, 0.0, 0.0)
		_v = _vehicle("lunar_ufo", -150, 190, 2.4)
		game.enter_vehicle(_v)
	if t > 4:
		_v.cleaning = true
		game.controls.move_vector = Vector2(0.18, -1.0)
		_v.braking = t < 30
	if t > 8:
		var vp := _v.global_position
		var b := _v.global_basis
		var k := t / float(_target)
		var a := 0.6 + k * 1.4
		var off := (b.x * cos(a) + b.z * sin(a)) * 13.0 + vp.normalized() * (3.0 + 3.0 * k)
		_look(vp + off, vp - vp.normalized() * 2.0)


## A hexagon being finished: the golden sweep and the wall of light.
func _clip_hex(t: int, _d: float) -> void:
	if t == 0:
		_place_player(-60, 260, 0.0, 0.0)
		game.player.visible = false
		var cell := HexGrid.cell_of(game.player.global_position)
		_m["cell"] = cell
		_p0 = HexGrid.center_point(cell)
		game.terrain.prewarm(_p0)
	if t == 40:
		game.complete_hex(int(_m["cell"]))
	var b := _frame(_p0)
	var k := t / float(_target)
	var a := 0.4 + k * 0.5
	var pos := _p0 + (b.x * cos(a) + b.z * sin(a)) * (62.0 - 8.0 * k) + b.y * (34.0 - 6.0 * k)
	_look(pos, _p0 + b.y * 2.0)


## Automation: cleaning stations beaming at their hexagons, a drone squad at work.
func _clip_machines(t: int, _d: float) -> void:
	if t == 0:
		_place_player(200, 120, 0.0, 0.0)
		game.player.visible = false
		var auto: Automation = game.automation
		_p0 = TerrainGen.map_ground(200, 120)
		auto.add_machine("hex_station", TerrainGen.map_ground(200, 120), 0.3)
		auto.add_machine("hex_station", TerrainGen.map_ground(214, 104), 1.1)
		auto.add_machine("drone_hangar", TerrainGen.map_ground(186, 106), 0.6)
		auto.add_machine("dust_collector", TerrainGen.map_ground(192, 134), 0.0)
		for m in GameState.machines:
			while auto.sim.upgrade_cost(m) > 0.0 and AutomationSim.tier(m) < 4:
				auto.sim.upgrade(m)
		var hg: Dictionary = GameState.machines[2]
		auto.sim.assign(hg, HexGrid.cell_of(TerrainGen.map_ground(200, 150)))
		game.terrain.prewarm(_p0)
	var b := _frame(_p0)
	var k := t / float(_target)
	var a := 2.2 + k * 0.9
	var pos := _p0 + (b.x * cos(a) + b.z * sin(a)) * (30.0 - 6.0 * k) + b.y * (9.0 + 4.0 * k)
	_look(pos, _p0 + b.y * 4.0)


## A gold nugget glinting in the dust, then brushed out (HUD on).
func _clip_nugget(t: int, _d: float) -> void:
	if t == 0:
		_place_player(90, 120, 0.2, -0.5)
		GameState.tools["broom"] = 2
		GameState.equip("broom")
	if t == 6:
		game.nuggets._list.clear()
		var pl: Player = game.player
		var ahead := TerrainGen.surface((pl.global_position - pl.global_basis.z * 4.0).normalized(), 0.0)
		game.nuggets._add(ahead)
		_m["n"] = ahead
	if t > 40:
		game.controls.held["clean"] = true
		game.controls.move_vector = Vector2(0, -0.3)


## Supervisor Gleam's hologram pointing the way (HUD on).
func _clip_gleam(t: int, _d: float) -> void:
	if t == 0:
		_place_player(-30, 90, 1.4, -0.12)
	if t == 10:
		game.hologram.quiet = false
		game.hologram.say("That hexagon's 87% done - finish it off! 60 m that way.", 30.0, game.player.global_position - game.player.global_basis.x * 50.0 - game.player.global_basis.z * 30.0)
		game.hologram.quiet = true


## The globe map spinning, cleared hexagons in green (HUD on).
func _clip_map(t: int, _d: float) -> void:
	if t == 0:
		for c in HexGrid.count():
			if randf() < 0.45:
				GameState.hexes_done.append(c)
		game.open_menu("map")
	var mv: Node = game.menu.find_children("*", "MapView", true, false)[0] if not game.menu.find_children("*", "MapView", true, false).is_empty() else null
	if mv:
		mv._rot = Basis(Vector3.UP, t * 0.012) * Basis(Vector3.RIGHT, 0.35)


## The finale: lift-off and the climb away from the spotless Moon.
func _clip_finale(t: int, _d: float) -> void:
	if t == 0:
		for c in HexGrid.count():
			GameState.hexes_done.append(c)
			GameState.dirt.swept_cells[c] = true
		for key in GameState.dirt.chunks.keys():
			for c in HexGrid.candidates(key):
				GameState.dirt.sweep_cell(key, c)
		GameState.missions_done.append("m_clean_moon")
		GameState.stats["play_time"] = 5 * 3600 + 12 * 60
		GameState.stats["m2_cleaned"] = 1130000.0
		GameState.stats["credits_earned"] = 48250000.0
		game._lander_action()
	if t == 2 and game.ending:
		game.ending._t = float(_args.get("from", "13.0"))
	# The trailer has its own titles: hide the film's captions and letterbox.
	if game.ending:
		var e: Ending = game.ending
		for l in [e._title, e._subtitle, e._count, e._stats]:
			if l:
				l.visible = false
		for bar in e._bars:
			bar.visible = false
