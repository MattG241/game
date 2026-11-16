extends Node
## Drives a vehicle flat-out across the world, steering around, and reports anything
## physically broken: non-finite transforms, huge speeds, falling through the ground.
##   godot --headless --path . res://tests/stress_drive.tscn -- --frames=5000 --vehicle=scooter
var f := 0
var game
var v
var target := 5000
var vid := "scooter"
var bad := 0
var falls := 0
var max_speed := 0.0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="): target = int(a.substr(9))
		if a.begins_with("--vehicle="): vid = a.substr(10)
	var boot = load("res://scripts/boot.gd").new()
	add_child(boot)
	boot.start_game(-3)
func _physics_process(_dt: float) -> void:
	f += 1
	if f == 3:
		game = get_tree().get_first_node_in_group("world")
		game.menu.close()
		for i in 5: GameState.regions[i] = true
		GameState.credits = 1e8
		GameState.buy_vehicle(vid)
	if f == 6:
		v = game.vehicles[0]
		game.enter_vehicle(v)
	if v == null: return
	# Full throttle, slowly weaving, occasionally hard turns.
	var steer := sin(f * 0.004) * 0.6 + (0.8 if (f / 400) % 5 == 0 else 0.0)
	game.controls.move_vector = Vector2(steer, -1.0)
	var p: Vector3 = v.global_position
	var sp: float = v.linear_velocity.length()
	max_speed = maxf(max_speed, sp)
	if not p.is_finite() or not v.linear_velocity.is_finite() or sp > 80.0:
		bad += 1
		if bad < 5: print("BROKEN frame ", f, " pos ", p, " vel ", v.linear_velocity)
	if p.is_finite() and TerrainGen.altitude(p) < -1.0:
		falls += 1
		if falls < 5: print("BELOW GROUND frame ", f, " pos ", p, " altitude ", TerrainGen.altitude(p))
	if f % 500 == 0 and sp < 0.5:
		var cs := []
		for w in v._wheels: cs.append(w.is_in_contact())
		var up := p.normalized()
		var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + up * 3.0, p - up * 3.0, 1))
		print("  STUCK contacts ", cs, " upright ", snappedf(v.global_basis.y.dot(up), 0.01), " flatness ", snappedf(TerrainGen.flatness(p), 0.01), " ground_hit ", hit.get("collider"), " cam_in_ground ", TerrainGen.altitude(v.cam.global_position) < 0.2)
	if f % 500 == 0:
		print("frame ", f, " map ", TerrainGen.dir_to_map(p.normalized()).round(), " speed ", snappedf(sp, 0.1), " chunks ", game.terrain.active_chunks())
	if f >= target:
		print("DRIVE DONE bad=", bad, " below_ground=", falls, " max_speed=", snappedf(max_speed, 0.1))
		get_tree().quit()
