extends Node
## Entry point. Shows the main menu and swaps between menu and game world.

const MainMenu := preload("res://scripts/ui/main_menu.gd")
const Game := preload("res://scripts/game.gd")

var current: Node


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().root.theme = UIKit.theme()
	Diagnostics.mark("boot")
	if Diagnostics.previous_crashed:
		_show_recovery()
	else:
		show_menu()


## After a crash: a plain 2D screen (nothing 3D is loaded yet) so the crash log can
## always be copied, even when the game closes again a moment after opening.
func _show_recovery() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	UIKit.fill_viewport(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.045)
	root.add_child(bg)
	UIKit.fill_viewport(bg)
	var center := CenterContainer.new()
	root.add_child(center)
	UIKit.fill_viewport(center)
	var v := UIKit.vbox(16)
	center.add_child(v)
	var t := UIKit.title("LUNAR CLEANUP CLOSED UNEXPECTEDLY", 40, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var msg := UIKit.label("Sorry about that. Tap COPY CRASH LOG and paste it to the developer - it says exactly what went wrong.", 20)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(760, 0)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)
	var row := UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var copy := UIKit.accent_button("COPY CRASH LOG", func(): pass, Vector2(320, 80), 24)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(Diagnostics.report())
		copy.text = "COPIED - PASTE IT TO THE DEVELOPER")
	row.add_child(copy)
	row.add_child(UIKit.button("CONTINUE", func():
		layer.queue_free()
		show_menu(), Vector2(240, 80), 24))


func show_menu() -> void:
	Diagnostics.mark("menu start")
	_swap(MainMenu.new())
	Audio.play_music(true)


func start_game(load_slot: int) -> void:
	# load_slot <= 0 means new game in slot -load_slot
	if load_slot > 0 and SaveManager.is_complete(load_slot):
		# A finished game is over: it can't be continued.
		show_menu()
		return
	if load_slot > 0:
		if not SaveManager.load_game(load_slot):
			GameState.new_game()
			SaveManager.current_slot = load_slot
	else:
		GameState.new_game()
		SaveManager.current_slot = maxi(-load_slot, 1)
	Diagnostics.mark("game start (slot %d)" % load_slot)
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
