extends Node
## Walks the astronaut for real (joystick input + physics) toward a series of targets,
## including locked-region borders, steep ridges and the world edge, and reports any
## shaking at borders, getting stuck, falling through the ground or invalid positions.
##   godot --headless --path . res://tests/stress_walk.tscn -- --frames=6000
var f := 0
var game
var target := 6000
var goals := [Vector3(0, 0, -200), Vector3(200, 0, 0), Vector3(120, 0, -110), Vector3(-200, 0, 30), Vector3(0, 0, 220), Vector3(60, 0, -60)]
var gi := 0
var stuck_frames := 0
var max_stuck := 0
var jitter := 0
var falls := 0
var bad := 0
var last := Vector3.ZERO
var last_dir := Vector3.ZERO
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="): target = int(a.substr(9))
	var boot = load("res://scripts/boot.gd").new()
	add_child(boot)
	boot.start_game(-3)
func _physics_process(_dt: float) -> void:
	f += 1
	if f == 3:
		game = get_tree().get_first_node_in_group("world")
		game.menu.close()
		GameState.regions[1] = true   # Crater Fields open, the others locked
		game.player.sprint_toggle = true
	if game == null or f < 10: return
	var pl: Player = game.player
	var p := pl.global_position
	var goal: Vector3 = goals[gi % goals.size()]
	var to := Vector3(goal.x - p.x, 0, goal.z - p.z)
	if to.length() < 6.0 or f % 900 == 0:
		gi += 1
	# Steer the camera toward the goal and push the stick forward (like a thumb).
	var want := atan2(-to.x, -to.z)
	pl.yaw = lerp_angle(pl.yaw, want, 0.08)
	game.controls.move_vector = Vector2(0, -1)
	if f % 240 == 0:
		pl.jump()
	if not p.is_finite():
		bad += 1
	elif p.y < TerrainGen.height(p.x, p.z) - 1.0:
		falls += 1
	var step := p - last
	step.y = 0
	if step.length() < 0.01:
		stuck_frames += 1
		max_stuck = maxi(max_stuck, stuck_frames)
	else:
		stuck_frames = 0
	# Shaking: direction of motion flips back and forth frame to frame.
	if step.length() > 0.05 and last_dir.length() > 0.05 and step.normalized().dot(last_dir.normalized()) < -0.5:
		jitter += 1
	last_dir = step
	last = p
	if f % 1000 == 0:
		print("frame ", f, " pos ", p.snapped(Vector3.ONE * 0.1), " goal ", gi % goals.size(), " jitter ", jitter, " max_stuck ", max_stuck)
	if f >= target:
		print("WALK DONE bad=%d below_ground=%d jitter=%d max_stuck_frames=%d" % [bad, falls, jitter, max_stuck])
		get_tree().quit()
