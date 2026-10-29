extends Node
## Root controller: switches between the title screen and a pub day, and saves on suspend.

var world: World
var hud: HUD
var title: TitleScreen


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	show_title()


func _clear() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.stop_all_loops()
	for n in [world, hud, title]:
		if n and is_instance_valid(n):
			n.queue_free()
	world = null
	hud = null
	title = null


func show_title() -> void:
	_clear()
	title = TitleScreen.new()
	title.main = self
	add_child(title)


func quit_to_title() -> void:
	show_title()


func start_new(mode: String, pub_name: String) -> void:
	GameState.new_game(mode, pub_name)
	GameState.save_game()
	start_world()


func continue_game() -> void:
	if GameState.load_game():
		start_world()
	else:
		GameState.notify("Couldn't load the save.", "bad")


func start_world() -> void:
	_clear()
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	world.main = self
	hud = HUD.new()
	hud.world = world
	world.hud = hud
	add_child(world)
	var pour := PourController.new()
	pour.name = "Pour"
	pour.world = world
	world.pour = pour
	world.add_child(pour)
	add_child(hud)
	world.on_ready_with_hud()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if world and GameState.in_game:
				GameState.save_game()
				if OS.has_feature("mobile") and hud and not get_tree().paused and not (world.pour and world.pour.active):
					hud.open_menu("game")
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if hud and world:
				if hud.menu.visible:
					hud.menu._close()
				elif world.pour and world.pour.active:
					world.pour.end(false)
				else:
					hud.open_menu("game")
			elif title:
				get_tree().quit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if world and GameState.in_game:
				GameState.save_game()
			get_tree().quit()
