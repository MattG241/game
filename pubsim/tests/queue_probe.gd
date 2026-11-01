extends Node
## Measures how the customer queue builds when nobody is served (balance probe).
## Prints the number of waiting/queued/arriving customers at intervals.

func _ready() -> void:
	GameState.delete_save()
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	main.start_new("career", "Probe")
	for i in 10:
		await get_tree().process_frame
	var w: World = main.world
	GameState.tutorial["done"] = true
	w._sign_action()
	var t := 0.0
	var marks := [30, 60, 90, 120, 180, 240, 300, 450, 600]
	var mi := 0
	while mi < marks.size():
		await get_tree().process_frame
		t += 1.0 / 60.0
		if t >= marks[mi]:
			var waiting := 0
			var walking := 0
			for c in w.customers:
				if c.state in ["wait_order", "wait_drink", "queue"]:
					waiting += 1
				elif c.state == "walk":
					walking += 1
			var orders := 0
			if w.has_method("active_orders"):
				orders = w.active_orders()
			print("PROBE t=%3ds  hour=%s  customers=%d  waiting_at_bar=%d  walking=%d  active_orders=%d" % [marks[mi], GameState.clock_text(), w.customers.size(), waiting, walking, orders])
			mi += 1
	get_tree().quit()
