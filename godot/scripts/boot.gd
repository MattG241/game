extends Node
## Entry point. Shows the main menu and swaps between menu and game world.

const MainMenu := preload("res://scripts/ui/main_menu.gd")
const Game := preload("res://scripts/game.gd")

var current: Node


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().root.theme = UIKit.theme()
	show_menu()


func show_menu() -> void:
	_swap(MainMenu.new())
	Audio.play_music(true)


func start_game(load_slot: int) -> void:
	# load_slot <= 0 means new game in slot -load_slot
	if load_slot > 0:
		if not SaveManager.load_game(load_slot):
			GameState.new_game()
			SaveManager.current_slot = load_slot
	else:
		GameState.new_game()
		SaveManager.current_slot = maxi(-load_slot, 1)
	var g := Game.new()
	g.boot = self
	_swap(g)


func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	if n.has_method("set") and "boot" in n:
		n.set("boot", self)
	add_child(n)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameState.active:
			SaveManager.save_game(-1, false)
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if GameState.active:
			SaveManager.save_game(-1, false)
