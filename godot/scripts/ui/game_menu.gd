class_name GameMenu
extends Control
## Full-screen tabbed menu: shop, suit, vehicles, permits, build, research, missions,
## operations (management + stats + achievements), inventory, map, settings, pause.
## Also hosts small modal panels (machine info, dialogs).

signal closed

const TABS := [
	["shop", "TOOLS"], ["suit", "SUIT"], ["vehicles", "VEHICLES"], ["permits", "PERMITS"],
	["build", "BUILD"], ["research", "RESEARCH"], ["missions", "MISSIONS"], ["ops", "OPERATIONS"],
	["inventory", "INVENTORY"], ["map", "MAP"], ["style", "STYLE"], ["settings", "SETTINGS"], ["pause", "GAME"],
]

var world: Node
var current := "shop"
var _tab_buttons := {}
var _content: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _credits: Label
var _modal: Control
var _dirty := false
var _refresh_t := 0.0


func _ready() -> void:
	UIKit.fill_viewport(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ins := UIKit.safe_insets(get_viewport())
	margin.add_theme_constant_override("margin_left", int(ins.x) + 18)
	margin.add_theme_constant_override("margin_right", int(ins.z) + 18)
	margin.add_theme_constant_override("margin_top", int(ins.y) + 14)
	margin.add_theme_constant_override("margin_bottom", int(ins.w) + 14)
	add_child(margin)
	var frame := UIKit.panel(UIKit.BG, UIKit.LINE, 20, 16)
	margin.add_child(frame)
	var outer := UIKit.vbox(12)
	frame.add_child(outer)
	var header := UIKit.hbox(16)
	outer.add_child(header)
	_title = UIKit.title("SHOP", 46, UIKit.TEXT)
	header.add_child(_title)
	header.add_child(UIKit.spacer())
	_credits = UIKit.title("", 38, UIKit.ACCENT)
	header.add_child(_credits)
	header.add_child(UIKit.accent_button("CLOSE", close, Vector2(160, 64)))
	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var tab_scroll := ScrollContainer.new()
	tab_scroll.custom_minimum_size = Vector2(230, 0)
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(tab_scroll)
	var tabs := UIKit.vbox(8)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.add_child(tabs)
	for t in TABS:
		var id: String = t[0]
		var b := UIKit.button(t[1], func(): show_tab(id), Vector2(210, 62), 21)
		b.toggle_mode = true
		tabs.add_child(b)
		_tab_buttons[id] = b
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_content = UIKit.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	GameState.inventory_changed.connect(_mark_dirty)
	GameState.credits_changed.connect(_mark_dirty.unbind(1))
	IAP.changed.connect(_mark_dirty)


func _mark_dirty() -> void:
	_dirty = true


func open(tab := "shop") -> void:
	close_modal_only()
	_hide_frame(false)
	visible = true
	Audio.play("ui_open")
	show_tab(tab)


func close() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null
	visible = false
	_hide_frame(false)
	closed.emit()


func show_tab(id: String) -> void:
	current = id
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == id
	for t in TABS:
		if t[0] == id:
			_title.text = t[1]
	_rebuild()
	_scroll.scroll_vertical = 0


func _process(delta: float) -> void:
	if not visible:
		return
	_credits.text = "%s CR   %d RP" % [GameState.fmt(GameState.credits), int(GameState.rp)]
	_refresh_t += delta
	if _refresh_t > 1.0 and current == "ops":
		_dirty = true
	if _dirty and _refresh_t > 0.25:
		_dirty = false
		_refresh_t = 0.0
		var sv := _scroll.scroll_vertical
		_rebuild()
		_scroll.set_deferred("scroll_vertical", sv)


func _rebuild() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	match current:
		"shop": _tab_tools()
		"suit": _tab_suit()
		"vehicles": _tab_vehicles()
		"permits": _tab_permits()
		"build": _tab_build()
		"research": _tab_research()
		"missions": _tab_missions()
		"ops": _tab_ops()
		"inventory": _tab_inventory()
		"map": _tab_map()
		"style": _tab_style()
		"settings": _tab_settings()
		"pause": _tab_pause()


# ------------------------------------------------------------------- helpers

func _card(title: String, desc: String, info: String, accent: Color, buttons: Array, owned := false) -> PanelContainer:
	var p := UIKit.panel(UIKit.PANEL_LIGHT if not owned else Color(0.08, 0.16, 0.14, 0.95), accent * Color(1, 1, 1, 0.6), 14, 14)
	var h := UIKit.hbox(14)
	p.add_child(h)
	var sw := ColorRect.new()
	sw.color = accent
	sw.custom_minimum_size = Vector2(8, 0)
	h.add_child(sw)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(title, 25, UIKit.TEXT, true))
	if desc != "":
		var d := UIKit.label(desc, 18, UIKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	if info != "":
		var i := UIKit.label(info, 17, UIKit.CYAN)
		i.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(i)
	var bv := UIKit.vbox(8)
	h.add_child(bv)
	for b in buttons:
		bv.add_child(b)
	_content.add_child(p)
	return p


func _buy_button(text: String, cost: float, cb: Callable, enabled := true) -> Button:
	var label := text if cost <= 0 else "%s\n%s CR" % [text, GameState.fmt(cost)]
	var b: Button
	if enabled and GameState.can_afford(cost):
		b = UIKit.accent_button(label, cb, Vector2(210, 70), 20)
	else:
		b = UIKit.button(label, cb, Vector2(210, 70), 20)
		b.disabled = not enabled or not GameState.can_afford(cost)
	return b


func _header(text: String) -> void:
	_content.add_child(UIKit.label(text, 18, UIKit.ACCENT, true))


func _note(text: String) -> void:
	var l := UIKit.label(text, 18, UIKit.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)


# ---------------------------------------------------------------------- tabs

func _tab_tools() -> void:
	var up: Dictionary = GameData.economy["tool_upgrade"]
	_note("Bigger tools clean wider strips, faster. Powered tools draw suit battery; it recharges at the base and near any of your machines. Upgrades add +%d%% strength and +%d%% width per level." % [roundi(float(up["strength_per_level"]) * 100.0), roundi(float(up["radius_per_level"]) * 100.0)])
	var max_level := int(GameData.economy["tool_upgrade"]["max_level"])
	for t in GameData.tools:
		var id: String = t["id"]
		var owned := GameState.tools.has(id)
		var s := GameState.tool_stats(id)
		var width: float = s["radius"] * 2.0 if s["shape"] == "round" else s["half_width"] * 2.0
		if s["shape"] == "swarm":
			width = s["radius"] * 2.0
		var info := "Width %.2f m   Strength %.1f   Reach %.0f m" % [width, s["strength"], s["reach"]]
		if float(s["power"]) > 0.0:
			info += "   Power %.1f/s" % s["power"]
		if owned:
			info += "   Level %d/%d" % [s["level"], max_level]
		var buttons := []
		if not owned:
			buttons.append(_buy_button("BUY", float(t["price"]), func(): GameState.buy_tool(id)))
		else:
			if GameState.equipped == id:
				var eb := UIKit.button("EQUIPPED", func(): pass, Vector2(210, 60), 20)
				eb.disabled = true
				buttons.append(eb)
			else:
				buttons.append(UIKit.button("EQUIP", func(): GameState.equip(id); _dirty = true, Vector2(210, 60), 20))
			if int(s["level"]) < max_level:
				buttons.append(_buy_button("UPGRADE", GameState.tool_upgrade_cost(id), func(): GameState.upgrade_tool(id)))
		_card(t["name"], t["desc"], info, Color.html(t["color"]), buttons, owned)


func _tab_suit() -> void:
	var tank: Array = GameData.economy["tank_levels"]
	var bat: Array = GameData.economy["battery_levels"]
	var boots: Array = GameData.economy["boots_levels"]
	var tc := GameState.next_tank_cost()
	_card("Dust Tank  (Level %d/%d)" % [GameState.tank_level, tank.size() - 1], "Holds the dust you collect. Bigger tank = fewer trips.",
		"Capacity %s" % GameState.fmt(GameState.tank_capacity()) + ("" if tc < 0 else "  ->  %s" % GameState.fmt(float(tank[GameState.tank_level + 1]["capacity"]) * (1.0 + GameState.research_bonus("capacity")))),
		Color(0.85, 0.78, 0.6), [_buy_button("MAXED" if tc < 0 else "UPGRADE", maxf(tc, 0), func(): GameState.buy_tank_upgrade(), tc >= 0)])
	var bc := GameState.next_battery_cost()
	_card("Suit Battery  (Level %d/%d)" % [GameState.battery_level, bat.size() - 1], "Powers electric tools.", "Capacity %d" % int(GameState.battery_capacity()),
		UIKit.GOOD, [_buy_button("MAXED" if bc < 0 else "UPGRADE", maxf(bc, 0), func(): GameState.buy_battery_upgrade(), bc >= 0)])
	var mc := GameState.next_boots_cost()
	var mv := GameState.move_stats()
	_card("Moon Boots  (Level %d/%d)" % [GameState.boots_level, boots.size() - 1], "Faster walking, sprinting and higher jumps.",
		"Walk %.1f m/s   Sprint %.1f m/s" % [mv["walk"], mv["sprint"]], UIKit.CYAN,
		[_buy_button("MAXED" if mc < 0 else "UPGRADE", maxf(mc, 0), func(): GameState.buy_boots_upgrade(), mc >= 0)])
	var hp := GameState.has_hover_pack()
	_card("Hover Pack", "Hold JUMP in the air to hover as long as your suit battery lasts. Tools clean from up to 6 m above the ground. Bigger batteries fly longer.",
		"Fitted" if hp else "Needs the Jump Jets research", Color(0.55, 0.8, 1.0),
		[_buy_button("OWNED" if hp else "BUY", GameState.HOVER_PACK_COST, func(): GameState.buy_hover_pack(), not hp and GameState.research_bonus("jetpack") > 0.0)], hp)


func _tab_vehicles() -> void:
	_note("Vehicles appear at the Vehicle Bay next to base. Walk up and press USE to drive. Your dust tank empties into the vehicle hopper when you get in. Cleaning vehicles toggle their vacuum with the CLEAN button.")
	for v in GameData.vehicles:
		var id: String = v["id"]
		var idx := -1
		for i in GameState.vehicles.size():
			if GameState.vehicles[i]["id"] == id:
				idx = i
		var owned := idx >= 0
		var stats: Dictionary = GameState.vehicle_stats(idx) if owned else v
		var info := "Top speed %d km/h   Hopper %s" % [int(float(stats["max_speed"]) * 3.6), GameState.fmt(stats["storage"])]
		if float(v["clean_width"]) > 0.0:
			info += "   Cleans %.1f m strip" % v["clean_width"]
		var buttons := []
		if not owned:
			buttons.append(_buy_button("BUY", float(v["price"]), func(): GameState.buy_vehicle(id)))
		else:
			var vi := idx
			for kind in [["engine", "ENGINE"], ["storage_lvl", "HOPPER"], ["clean_lvl", "CLEANER"]]:
				if kind[0] == "clean_lvl" and float(v["clean_width"]) <= 0.0:
					continue
				var c := GameState.vehicle_upgrade_cost(vi, kind[0])
				var k: String = kind[0]
				buttons.append(_buy_button("%s %d" % [kind[1], int(GameState.vehicles[vi].get(k, 0))] if c >= 0 else kind[1] + " MAX", maxf(c, 0), func(): GameState.upgrade_vehicle(vi, k), c >= 0))
			buttons.append(UIKit.button("CALL TO BAY", func(): world.recall_vehicle(vi), Vector2(210, 60), 20))
		_card(v["name"], v["desc"], info, Color.html(v["color"]), buttons, owned)


func _tab_permits() -> void:
	_note("Permits unlock new regions. Every region has more valuable dust than the last.")
	for i in range(1, GameData.regions.size()):
		var r := GameData.region(i)
		var unlocked := GameState.region_unlocked(i)
		var req_ok := GameState.permit_requirement_met(i)
		var req_text := ""
		if not req_ok:
			for m in GameData.missions:
				if m["id"] == r["requires"]:
					req_text = "Requires mission: " + m["title"]
		var idx := i
		var b: Button
		if unlocked:
			b = UIKit.button("UNLOCKED", func(): pass, Vector2(210, 60), 20)
			b.disabled = true
		else:
			b = _buy_button("BUY PERMIT", float(r["permit"]), func(): GameState.buy_permit(idx), req_ok)
		_card(r["name"], r["desc"], "Dust value x%s   Dust density x%s   %s" % [str(r["dust_mult"]), str(r["thickness"]), req_text], Color.html(r["tint"]), [b], unlocked)


const AUTOMATION_HELP := """Machines work wherever you build them - no power, cables or storage. Everything they clean is sold straight away, and every machine upgrades from Mk I to Mk V (each tier almost doubles its output).

DUST COLLECTOR - keeps a circle of ground around itself clean and extracts a steady trickle of deep regolith. Cheap; great early on.

HEXAGON CLEANING STATION - build it inside a hexagon. It clears that whole hexagon, then moves on to the nearest unfinished one by itself. Mk I takes about 10 minutes per hexagon, Mk V about one.

DRONE HANGAR - its drone squad clears any hexagon on the Moon. Tap the hangar and press CHOOSE ON MAP, then tap a hexagon on the globe. Left alone it picks the nearest unfinished hexagon.

Every hexagon cleared by a machine pays the same hexagon bonus as clearing it yourself."""


func _tab_build() -> void:
	var sim: AutomationSim = world.automation.sim
	_note("Automation revenue %s CR/min. Machines are placed 8 m in front of you. Tap a machine to upgrade it (Mk I-V)." % GameState.fmt(sim.revenue_rate))
	_content.add_child(UIKit.accent_button("HOW AUTOMATION WORKS", func(): show_dialog("HOW AUTOMATION WORKS", AUTOMATION_HELP), Vector2(420, 64), 22))
	for m in GameData.machines:
		var id: String = m["id"]
		var count := 0
		for mc in GameState.machines:
			if mc["id"] == id:
				count += 1
		var info := "Owned %d" % count
		match id:
			"dust_collector":
				info = "Cleans a %d m circle (Mk I)   Owned %d" % [int(sim.collector_radius({"id": id, "tier": 1})), count]
			"hex_station", "drone_hangar":
				var mins := AutomationSim.hex_area() / sim.hex_rate({"id": id, "tier": 1}) / 60.0
				info = "About %d min per hexagon at Mk I, %d s at Mk V   Owned %d" % [int(round(mins)), int(mins * 60.0 / pow(AutomationSim.TIER_MULT, 4)), count]
		_card(m["name"], m["desc"], info, Color.html(m["color"]), [_buy_button("PLACE", float(m["price"]), func(): world.begin_placement(id))])


func _tab_research() -> void:
	_note("Research points (RP) come from cleaning, missions, salvage and the crashed probe. You have %d RP." % int(GameState.rp))
	for r in GameData.research:
		var id: String = r["id"]
		var done := GameState.research_done.has(id)
		var avail := GameState.research_available(id)
		var reqs := []
		for q in r["requires"]:
			reqs.append(GameData.research_item(q)["name"])
		var info := "%d RP + %s CR" % [int(r["rp"]), GameState.fmt(r["credits"])]
		if not reqs.is_empty():
			info += "   Needs: " + ", ".join(reqs)
		var b: Button
		if done:
			b = UIKit.button("DONE", func(): pass, Vector2(210, 60), 20)
			b.disabled = true
		else:
			var can := avail and GameState.rp + 0.001 >= float(r["rp"])
			b = _buy_button("RESEARCH", float(r["credits"]), func(): GameState.do_research(id), can)
		_card(r["name"], r["desc"], info, Color(0.7, 0.6, 1.0), [b], done)


func _tab_missions() -> void:
	var cur := GameState.current_mission()
	_header("CONTRACTS  (%d / %d complete)" % [GameState.missions_done.size(), GameData.missions.size()])
	for m in GameData.missions:
		var done := GameState.missions_done.has(m["id"])
		var p := GameState.mission_progress(m)
		var prog := "COMPLETE" if done else "%s / %s" % [GameState.fmt_short(minf(p.x, p.y)), GameState.fmt_short(p.y)]
		if m["type"] == "landmark" and not done:
			prog = "%d%% / %d%%" % [roundi(p.x * 100.0), roundi(p.y * 100.0)]
		var accent := UIKit.GOOD if done else (UIKit.ACCENT if m == cur else UIKit.LINE)
		_card(m["title"], m["hint"], "Reward %s CR + %d RP   -   %s" % [GameState.fmt(m["reward"]), int(m["rp"]), prog], accent, [], done)
	_header("ACHIEVEMENTS  (%d / %d)" % [GameState.achievements_done.size(), GameData.achievements.size()])
	for a in GameData.achievements:
		var done := GameState.achievements_done.has(a["id"])
		_card(a["title"], a["desc"], "UNLOCKED" if done else "", Color(0.8, 0.6, 1.0) if done else UIKit.LINE, [], done)


func _tab_ops() -> void:
	var sim: AutomationSim = world.automation.sim
	_header("LUNAR CLEANUP CO. - OPERATIONS")
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	_content.add_child(g)
	var tiles := [
		["Automation revenue", "%s CR/min" % GameState.fmt(sim.revenue_rate)],
		["Automation output", "%s dust/min" % GameState.fmt(sim.production_rate)],
		["Machines", "%d" % GameState.machines.size()],
		["Hexagons cleared", "%d / %d" % [GameState.hexes_done.size(), HexGrid.count()]],
		["Total earned", "%s CR" % GameState.fmt(GameState.stat("credits_earned"))],
		["Auto dust produced", GameState.fmt(GameState.stat("auto_dust"))],
		["Area cleaned", "%s m2" % GameState.fmt(GameState.stat("m2_cleaned"))],
		["Dust collected by hand", GameState.fmt(GameState.stat("dust_collected"))],
		["Dust sold", GameState.fmt(GameState.stat("dust_sold"))],
		["Salvage recovered", GameState.fmt(GameState.stat("salvage"))],
		["Walked / driven", "%.1f km / %.1f km" % [GameState.stat("distance_walked") / 1000.0, GameState.stat("distance_driven") / 1000.0]],
		["Play time", "%d h %02d m" % [int(GameState.stat("play_time") / 3600.0), int(fmod(GameState.stat("play_time") / 60.0, 60.0))]],
	]
	for t in tiles:
		var p := UIKit.panel(UIKit.PANEL_LIGHT, UIKit.LINE, 12, 12)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UIKit.vbox(2)
		p.add_child(v)
		v.add_child(UIKit.label(t[0], 15, UIKit.MUTED, true))
		v.add_child(UIKit.label(t[1], 22, UIKit.TEXT, true))
		g.add_child(p)
	_header("EQUIPMENT STATUS")
	if GameState.machines.is_empty():
		_note("No machines yet. Open BUILD to place a Dust Collector, a Hexagon Cleaning Station or a Drone Hangar.")
	for m in GameState.machines:
		var info := GameData.machine(m["id"])
		var txt := "%s   |   %s   |   %s dust/min   |   earned %s CR" % [AutomationSim.tier_name(AutomationSim.tier(m)), m.get("status", ""), GameState.fmt(m.get("rate", 0.0)), GameState.fmt_short(m.get("earned", 0.0))]
		_card(info["name"], "", txt, Color.html(info["color"]), [])


func _tab_inventory() -> void:
	_header("TOOLS OWNED")
	for t in GameData.tools:
		if GameState.tools.has(t["id"]):
			var id: String = t["id"]
			var lv := GameState.tool_level(id)
			_card(t["name"], "", "Level %d%s" % [lv, "   (equipped)" if GameState.equipped == id else ""], Color.html(t["color"]),
				[UIKit.button("EQUIP", func(): GameState.equip(id); _dirty = true, Vector2(180, 58), 20)], GameState.equipped == id)
	_header("CARGO")
	_card("Dust tank", "", "%s / %s units   (worth ~%s CR)" % [GameState.fmt(GameState.tank_dust), GameState.fmt(GameState.tank_capacity()), GameState.fmt(GameState.tank_value * GameState.dust_price())], Color(0.85, 0.78, 0.6), [])
	for i in GameState.vehicles.size():
		var v: Dictionary = GameState.vehicles[i]
		var info := GameData.vehicle(v["id"])
		_card(info["name"], "", "Hopper %s / %s" % [GameState.fmt(v.get("dust", 0.0)), GameState.fmt(GameState.vehicle_stats(i)["storage"])], Color.html(info["color"]), [])
	_header("RESEARCH COMPLETED")
	var names := []
	for r in GameState.research_done:
		names.append(GameData.research_item(r)["name"])
	_note(", ".join(names) if not names.is_empty() else "None yet.")


## A Drone Hangar waiting for its target hexagon to be tapped on the map (-1 = none).
var map_assign_uid := -1


func _tab_map() -> void:
	var mv := MapView.new()
	mv.world = world
	mv.assign_uid = map_assign_uid
	map_assign_uid = -1
	mv.custom_minimum_size = Vector2(0, 620)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(mv)
	_note("Drag the Moon to spin it, pinch (or +/-) to zoom, ME to find yourself. Green patches are spotless, amber ones are started. In the final mission red shows dust still left and DUST marks the nearest. Orange marker: base. White arrow: you. Squares: machines. Purple dots: vehicles. Dark areas are locked regions.")


func _tab_style() -> void:
	var total := 0
	for cat in Cosmetics.CATS:
		total += Cosmetics.items(cat).size()
	_note("Make it yours: suit colours, tool skins and vehicle paint. Most unlock by watching one short ad%s; a few are achievement rewards. Unlocks carry over to every save.  (%d / %d unlocked)" % [
		" (all free with Remove Ads)" if not IAP.ads_removed else " - Remove Ads unlocked them all", Cosmetics.count_unlocked(), total])
	var titles := {"suit": "SUIT COLOURS", "tool": "TOOL SKINS (all tools)", "vehicle": "VEHICLE PAINT (all vehicles)"}
	for cat in Cosmetics.CATS:
		_header(titles[cat])
		var on := Cosmetics.equipped_id(cat)
		for it in Cosmetics.items(cat):
			var id: String = it["id"]
			var col := Color.html(it.get("color", it.get("suit", "#c0c0c0")))
			if it.get("rainbow", false):
				col = Color(1.0, 0.4, 0.8)
			var buttons := []
			var info := ""
			if id == on:
				info = "Wearing"
			elif Cosmetics.is_unlocked(id):
				buttons.append(UIKit.button("WEAR", func():
					Cosmetics.equip(id)
					Audio.play("ui_click")
					_mark_dirty(), Vector2(200, 60), 20))
			else:
				info = Cosmetics.lock_text(id)
				if it.get("unlock", "") == "ad":
					buttons.append(UIKit.accent_button("WATCH AD", func():
						Cosmetics.unlock_with_ad(id, func(_ok): _mark_dirty()), Vector2(200, 60), 20))
			_card(it["name"], "", info, col, buttons, id == on)


func _tab_settings() -> void:
	_content.add_child(SettingsPanel.build(func(): world.edit_layout()))


func _tab_pause() -> void:
	var box := UIKit.vbox(14)
	_content.add_child(box)
	box.add_child(UIKit.label("Slot %d   -   autosaves every %d s" % [SaveManager.current_slot, int(GameData.economy["autosave_seconds"])], 20, UIKit.MUTED))
	box.add_child(UIKit.accent_button("RESUME", close, Vector2(420, 76), 26))
	box.add_child(UIKit.button("SAVE GAME", func():
		SaveManager.save_game()
		GameState.notify.emit("Game saved", "purchase"), Vector2(420, 76), 26))
	box.add_child(UIKit.button("SAVE & MAIN MENU", func(): world.quit_to_menu(), Vector2(420, 76), 26))
	box.add_child(UIKit.button("SAVE & QUIT", func():
		SaveManager.save_game(-1, false)
		get_tree().quit(), Vector2(420, 76), 26))
	_tab_support(box)
	_note("Lunar Cleanup v%s - made with Godot Engine (MIT). Fonts: Exo 2 and Rajdhani (SIL Open Font License). All models, sounds and music are procedurally generated originals." % ProjectSettings.get_setting("application/config/version"))


## Remove ads (one-off Google Play purchase), restore, and the GDPR privacy form.
func _tab_support(box: VBoxContainer) -> void:
	box.add_child(UIKit.label("SUPPORT THE GAME", 18, UIKit.ACCENT, true))
	if IAP.ads_removed:
		box.add_child(UIKit.label("Ads removed - thank you! Rewarded bonuses stay available if you want them.", 18, UIKit.GOOD))
	else:
		var price := (" (%s)" % IAP.price_text) if IAP.price_text != "" else ""
		box.add_child(UIKit.accent_button("REMOVE ADS" + price, func(): IAP.buy(), Vector2(420, 76), 26))
		box.add_child(UIKit.label("One purchase stops the occasional full-screen ads for good.", 16, UIKit.MUTED))
	box.add_child(UIKit.button("RESTORE PURCHASES", func(): IAP.restore(), Vector2(420, 64), 22))
	if Ads.privacy_options_required():
		box.add_child(UIKit.button("AD PRIVACY OPTIONS", func(): Ads.show_privacy_options(), Vector2(420, 64), 22))


# -------------------------------------------------------------------- modals

func show_modal(title: String, body: Control, buttons: Array) -> void:
	if _modal:
		_modal.queue_free()
	visible = true
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var p := UIKit.panel(UIKit.BG, UIKit.ACCENT, 20, 22)
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var v := UIKit.vbox(14)
	p.add_child(v)
	v.add_child(UIKit.title(title, 40, UIKit.ACCENT))
	# Long text scrolls inside the dialog so its buttons always stay on screen.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var limit := maxf(get_viewport_rect().size.y - 300.0, 160.0)
	sc.custom_minimum_size = Vector2(0, limit)
	sc.add_child(body)
	v.add_child(sc)
	# Shrink to the text once it has been laid out (short dialogs stay compact).
	var fit := func():
		if is_instance_valid(sc) and is_instance_valid(body):
			sc.custom_minimum_size.y = minf(body.size.y, limit)
	fit.call_deferred()
	var h := UIKit.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	for b in buttons:
		h.add_child(b)


func close_modal_only() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func show_dialog(title: String, text: String) -> void:
	var l := UIKit.label(text, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	_hide_frame(true)
	show_modal(title, l, [UIKit.accent_button("OK", func(): close(); _hide_frame(false), Vector2(180, 68))])


func _hide_frame(hidden: bool) -> void:
	for c in get_children():
		if c != _modal and c is CanvasItem:
			(c as CanvasItem).visible = not hidden


func show_machine(uid: int) -> void:
	var sim: AutomationSim = world.automation.sim
	var m := sim.get_machine(uid)
	if m.is_empty():
		return
	var info := GameData.machine(m["id"])
	var t := AutomationSim.tier(m)
	var v := UIKit.vbox(8)
	var lines := [info["desc"], "Tier: %s   Status: %s" % [AutomationSim.tier_name(t), str(m.get("status", ""))],
		"Output: %s dust/min   Earned: %s CR" % [GameState.fmt(m.get("rate", 0.0)), GameState.fmt(m.get("earned", 0.0))]]
	match m["id"]:
		"dust_collector":
			lines.append("Keeps a %d m circle clean" % int(sim.collector_radius(m)))
		"hex_station", "drone_hangar":
			lines.append("Clears %d m2 per second - about %d s per hexagon" % [int(sim.hex_rate(m)), int(AutomationSim.hex_area() / sim.hex_rate(m))])
			if m["id"] == "drone_hangar":
				lines.append("Target: " + ("hexagon %d (chosen on the map)" % (int(m["target"]) + 1) if m.get("manual", false) else "nearest unfinished hexagon"))
	for line in lines:
		var l := UIKit.label(line, 20, UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
		v.add_child(l)
	var buttons := []
	var cost := sim.upgrade_cost(m)
	if cost >= 0.0:
		var up := UIKit.accent_button("UPGRADE TO %s  %s CR" % [AutomationSim.tier_name(t + 1), GameState.fmt(cost)], func():
			if sim.upgrade(m):
				close(); _hide_frame(false)
				show_machine(uid), Vector2(360, 68), 18)
		up.disabled = not GameState.can_afford(cost)
		buttons.append(up)
	if m["id"] == "drone_hangar":
		buttons.append(UIKit.button("CHOOSE ON MAP", func():
			close(); _hide_frame(false)
			map_assign_uid = uid
			world.open_menu("map"), Vector2(240, 68), 18))
	buttons.append(UIKit.button("REMOVE (50% BACK)", func():
		world.automation.remove_machine(uid)
		close(); _hide_frame(false), Vector2(260, 68), 18))
	buttons.append(UIKit.button("CLOSE", func(): close(); _hide_frame(false), Vector2(160, 68)))
	_hide_frame(true)
	show_modal(info["name"], v, buttons)
