extends Node
## Walks straight into a locked region border for 600 frames and measures shaking.
var f := 0
var game
var jitter := 0
var teleports := 0
var last := Vector3.ZERO
var last_dir := Vector3.ZERO
var cam_jumps := 0
var last_cam := Vector3.ZERO
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var boot = load("res://scripts/boot.gd").new()
	add_child(boot)
	boot.start_game(-3)
func _physics_process(_dt: float) -> void:
	f += 1
	if f == 3:
		game = get_tree().get_first_node_in_group("world")
		game.menu.close()
		var p := Vector3(5, 0, -140)
		p.y = TerrainGen.height(p.x, p.z) + 0.3
		game.player.global_position = p
		game.player.yaw = 0.0   # facing -Z: into the locked Highlands
		game.terrain.prewarm(p)
	if game == null or f < 20: return
	game.controls.move_vector = Vector2(0.15, -1)
	var p: Vector3 = game.player.global_position
	var step := p - last
	step.y = 0
	if step.length() > 0.05 and last_dir.length() > 0.05 and step.normalized().dot(last_dir.normalized()) < -0.5:
		jitter += 1
	if step.length() > 1.0:
		teleports += 1
	last_dir = step
	last = p
	if f >= 620:
		print("BORDER jitter=%d teleports=%d final=%s in_locked=%s" % [jitter, teleports, str(p.snapped(Vector3.ONE * 0.1)), str(not GameState.region_unlocked(TerrainGen.region_at(p.x, p.z)))])
		get_tree().quit()
