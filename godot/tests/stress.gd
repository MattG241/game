extends Node
## Stress harness: walks the player across the world for many frames to shake out
## streaming crashes.  godot --headless --path . res://tests/stress.tscn -- --frames=6000
var f := 0
var game
var target := 6000
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="): target = int(a.substr(9))
	var boot = load("res://scripts/boot.gd").new()
	add_child(boot)
	boot.start_game(-3)
	for i in 5: GameState.regions[i] = true
func _physics_process(dt: float) -> void:
	f += 1
	if f == 3:
		game = get_tree().get_first_node_in_group("world")
		game.menu.close()
	if game == null: return
	var t: float = f * dt
	# Large figure-eight through every region and over the far pole (map coordinates)
	var p := TerrainGen.map_ground(sin(t * 0.05) * 930.0, sin(t * 0.1) * 600.0, 1.0)
	game.player.global_position = p
	# Every tool gets a turn, the swarm controller (four drones) most of all.
	if f % 300 == 1:
		var ids := ["swarm_controller", "cleaning_beam", "heavy_cleaner", "swarm_controller", "toothbrush"]
		var id: String = ids[(f / 300) % ids.size()]
		GameState.tools[id] = 0
		GameState.equip(id)
	game.player.yaw += 0.02
	if (f / 120) % 2 == 0:
		game.controls.held["clean"] = true
	else:
		game.controls.held.erase("clean")
	GameState.tank_dust = 0
	if f % 500 == 0:
		print("frame ", f, " pos ", p, " chunks ", game.terrain.active_chunks(), " dirt ", GameState.dirt.chunks.size(), " mem MB ", int(OS.get_static_memory_usage() / 1048576))
	if f % 1500 == 0:
		SaveManager.save_game(3, true)
	if f >= target:
		print("STRESS OK")
		get_tree().quit()
