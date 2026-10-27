class_name HUD
extends Control
## In-game heads-up display: credits, dust tank, battery, tool, objective tracker,
## region, interaction prompt, toasts, sale pop-ups and the optional perf overlay.

var world: Node
var _credits_label: Label
var _rp_label: Label
var _tank_bar: ProgressBar
var _tank_label: Label
var _bat_bar: ProgressBar
var _bat_row: Control
var _tool_label: Label
var _clean_label: Label
var _obj_title: Label
var _obj_hint: Label
var _obj_bar: ProgressBar
var _obj_panel: PanelContainer
var _region_label: Label
var _prompt: Label
var _toasts: VBoxContainer
var _popup: Label
var _perf: Label
var _vehicle_panel: PanelContainer
var _vehicle_label: Label
var _hopper_bar: ProgressBar
var _place_panel: PanelContainer
var _place_label: Label
var _left: PanelContainer
var _shown_credits := 0.0
var _insets := Vector4.ZERO
var _tank_flash := 0.0
var _t := 0.0


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build()
	GameState.notify.connect(toast)
	GameState.sold.connect(_on_sold)
	# Bound methods (not lambdas) so the connections are dropped when the HUD is freed.
	GameState.tank_changed.connect(_update_tank.unbind(2))
	GameState.battery_changed.connect(_update_battery.unbind(2))
	GameState.tool_changed.connect(_update_tool.unbind(1))
	GameState.inventory_changed.connect(_update_tool)
	get_viewport().size_changed.connect(_layout)
	_shown_credits = GameState.credits
	_update_tank()
	_update_battery()
	_update_tool()
	_layout()
	call_deferred("_layout")


func _build() -> void:
	# Left status panel
	_left = UIKit.panel(Color(0.04, 0.06, 0.1, 0.72), Color(0.25, 0.35, 0.5, 0.6), 16, 14)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	var v := UIKit.vbox(6)
	v.custom_minimum_size = Vector2(300, 0)
	_left.add_child(v)
	var cr := UIKit.hbox(8)
	v.add_child(cr)
	var coin := UIKit.label("CR", 20, UIKit.ACCENT, true)
	cr.add_child(coin)
	_credits_label = UIKit.title("0", 44, UIKit.ACCENT)
	cr.add_child(_credits_label)
	cr.add_child(UIKit.spacer())
	_rp_label = UIKit.label("0 RP", 18, Color(0.75, 0.65, 1.0))
	cr.add_child(_rp_label)
	var tr := UIKit.hbox(8)
	v.add_child(tr)
	tr.add_child(UIKit.label("DUST", 16, UIKit.MUTED, true))
	_tank_label = UIKit.label("0 / 40", 18)
	tr.add_child(UIKit.spacer())
	tr.add_child(_tank_label)
	_tank_bar = UIKit.bar(Color(0.85, 0.78, 0.6), 18)
	v.add_child(_tank_bar)
	_bat_row = UIKit.vbox(4)
	v.add_child(_bat_row)
	var br := UIKit.hbox(8)
	_bat_row.add_child(br)
	br.add_child(UIKit.label("BATTERY", 16, UIKit.MUTED, true))
	_bat_bar = UIKit.bar(UIKit.GOOD, 12)
	_bat_row.add_child(_bat_bar)
	_tool_label = UIKit.label("", 18, UIKit.CYAN, true)
	v.add_child(_tool_label)
	_clean_label = UIKit.label("", 15, UIKit.MUTED)
	v.add_child(_clean_label)
	# Objective tracker
	_obj_panel = UIKit.panel(Color(0.04, 0.06, 0.1, 0.65), Color(1.0, 0.62, 0.11, 0.5), 14, 12)
	_obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_obj_panel)
	var ov := UIKit.vbox(4)
	ov.custom_minimum_size = Vector2(420, 0)
	_obj_panel.add_child(ov)
	var oh := UIKit.hbox(8)
	ov.add_child(oh)
	oh.add_child(UIKit.label("OBJECTIVE", 14, UIKit.ACCENT, true))
	_region_label = UIKit.label("", 14, UIKit.MUTED, true)
	oh.add_child(UIKit.spacer())
	oh.add_child(_region_label)
	_obj_title = UIKit.label("", 21, UIKit.TEXT, true)
	_obj_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(_obj_title)
	_obj_bar = UIKit.bar(UIKit.ACCENT, 8)
	ov.add_child(_obj_bar)
	_obj_hint = UIKit.label("", 15, UIKit.MUTED)
	_obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(_obj_hint)
	# Toasts
	_toasts = UIKit.vbox(6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	# Prompt
	_prompt = UIKit.label("", 24, Color.WHITE, true)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)
	# Sale popup
	_popup = UIKit.title("", 64, UIKit.ACCENT)
	_popup.add_theme_constant_override("outline_size", 10)
	_popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.modulate.a = 0.0
	add_child(_popup)
	# Vehicle panel
	_vehicle_panel = UIKit.panel(Color(0.04, 0.06, 0.1, 0.72), Color(0.6, 0.5, 1.0, 0.6), 14, 12)
	_vehicle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vehicle_panel)
	var vv := UIKit.vbox(4)
	vv.custom_minimum_size = Vector2(300, 0)
	_vehicle_panel.add_child(vv)
	_vehicle_label = UIKit.label("", 18, UIKit.TEXT, true)
	vv.add_child(_vehicle_label)
	_hopper_bar = UIKit.bar(Color(0.7, 0.55, 1.0), 14)
	vv.add_child(_hopper_bar)
	_vehicle_panel.visible = false
	# Placement panel
	_place_panel = UIKit.panel(Color(0.04, 0.06, 0.1, 0.8), UIKit.GOOD, 14, 12)
	_place_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_place_panel)
	_place_label = UIKit.label("", 20, UIKit.TEXT, true)
	_place_panel.add_child(_place_label)
	_place_panel.visible = false
	# Perf overlay
	_perf = UIKit.label("", 15, Color(0.6, 1.0, 0.6))
	_perf.add_theme_constant_override("outline_size", 6)
	_perf.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_perf)


func _layout() -> void:
	_insets = UIKit.safe_insets(get_viewport())
	var s := get_viewport_rect().size
	_left.position = Vector2(_insets.x + 6, _insets.y + 6)
	# Objective sits between the status panel and the menu buttons.
	_obj_panel.position = Vector2(maxf(s.x * 0.5 - 250, _insets.x + 340), _insets.y + 6)
	_obj_panel.size.x = 440
	_toasts.position = Vector2(s.x * 0.5 - 300, _insets.y + 150)
	_toasts.size = Vector2(600, 300)
	_prompt.position = Vector2(s.x * 0.5 - 300, s.y - _insets.w - 150)
	_prompt.size = Vector2(600, 40)
	_popup.position = Vector2(s.x * 0.5 - 300, s.y * 0.36)
	_popup.size = Vector2(600, 80)
	_vehicle_panel.position = Vector2(_insets.x + 6, _insets.y + 250)
	_place_panel.position = Vector2(s.x * 0.5 - 260, s.y - _insets.w - 90)
	_perf.position = Vector2(_insets.x + 8, s.y * 0.5)


func _update_tank() -> void:
	var cap := GameState.tank_capacity()
	_tank_bar.max_value = cap
	_tank_bar.value = GameState.tank_dust
	_tank_label.text = "%s / %s" % [GameState.fmt(GameState.tank_dust), GameState.fmt(cap)]
	var full := GameState.tank_dust >= cap - 0.01
	_tank_label.add_theme_color_override("font_color", UIKit.BAD if full else UIKit.TEXT)


func _update_battery() -> void:
	_bat_bar.max_value = GameState.battery_capacity()
	_bat_bar.value = GameState.battery
	var low := GameState.battery < GameState.battery_capacity() * 0.2
	_bat_bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.BAD if low else UIKit.GOOD, Color(0, 0, 0, 0), 0, 8, 0))


func _update_tool() -> void:
	var s := GameState.tool_stats(GameState.equipped)
	if s.is_empty():
		return
	_tool_label.text = "%s  Lv %d" % [s["name"], int(s["level"])]
	var powered := float(s.get("power", 0.0)) > 0.0
	_bat_row.visible = powered or GameState.battery < GameState.battery_capacity() - 0.5


func toast(text: String, kind := "info") -> void:
	var p := UIKit.panel(Color(0.04, 0.06, 0.1, 0.85), _kind_color(kind), 12, 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 20, Color.WHITE, kind == "mission" or kind == "achievement")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(560, 0)
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.2 if kind != "mission" else 5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
	if kind == "error":
		Audio.play("error", -6.0)


func _kind_color(kind: String) -> Color:
	match kind:
		"mission":
			return UIKit.ACCENT
		"achievement":
			return Color(0.8, 0.6, 1.0)
		"purchase", "upgrade":
			return UIKit.GOOD
		"error":
			return UIKit.BAD
	return UIKit.CYAN


func _on_sold(amount: float, credits: float) -> void:
	_popup.text = "+%s CR" % GameState.fmt(credits)
	_popup.modulate.a = 1.0
	_popup.scale = Vector2(0.6, 0.6)
	_popup.pivot_offset = _popup.size * 0.5
	var tw := create_tween()
	tw.tween_property(_popup, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(1.0)
	tw.tween_property(_popup, "modulate:a", 0.0, 0.6)
	Audio.play("sell")
	Settings.vibrate(35, 0.6)


func set_prompt(text: String) -> void:
	_prompt.text = text


func _process(delta: float) -> void:
	_t += delta
	# Smoothly count credits up/down for satisfying feedback.
	var target := GameState.credits
	if absf(target - _shown_credits) < 0.5:
		_shown_credits = target
	else:
		_shown_credits = lerpf(_shown_credits, target, minf(delta * 8.0, 1.0))
	_credits_label.text = GameState.fmt_short(_shown_credits)
	_rp_label.text = "%d RP" % int(GameState.rp)
	var m := GameState.current_mission()
	if m.is_empty():
		_obj_title.text = "All missions complete - you run the Moon!"
		_obj_bar.value = 1.0
		_obj_bar.max_value = 1.0
		_obj_hint.text = ""
	else:
		var p := GameState.mission_progress(m)
		_obj_title.text = m["title"]
		_obj_bar.max_value = maxf(p.y, 0.0001)
		_obj_bar.value = minf(p.x, p.y)
		var prog := ""
		if p.y > 1.0:
			prog = "  (%s / %s)" % [GameState.fmt_short(minf(p.x, p.y)), GameState.fmt_short(p.y)]
		elif m["type"] == "landmark":
			prog = "  (%d%% / %d%%)" % [roundi(p.x * 100.0), roundi(p.y * 100.0)]
		_obj_hint.text = m.get("hint", "") + prog
	if world:
		var fp: Vector3 = world.focus_node().global_position
		var reg := GameData.region(TerrainGen.region_at(fp.x, fp.z))
		_region_label.text = "%s  x%s" % [reg["name"].to_upper(), str(reg["dust_mult"])]
		var c: Cleaner = world.player.cleaner
		var rate_txt := ""
		if c and c.rate > 0.05:
			rate_txt = "   +%s dust/s" % GameState.fmt_short(c.rate)
		_clean_label.text = "Cleaned %s m2%s" % [GameState.fmt_short(GameState.stat("m2_cleaned")), rate_txt]
		var veh: LunarVehicle = world.current_vehicle
		_vehicle_panel.visible = veh != null
		if veh:
			var kmh := veh.linear_velocity.length() * 3.6
			_vehicle_label.text = "%s   %d km/h%s" % [veh.info["name"], int(kmh), "   VACUUM ON" if veh.cleaning else ""]
			_hopper_bar.max_value = float(veh.info["storage"])
			_hopper_bar.value = veh.hopper()
		var placing: String = world.automation.placing
		_place_panel.visible = placing != ""
		if placing != "":
			var info := GameData.machine(placing)
			var reason: String = world.automation.ghost_reason
			_place_label.text = "%s  -  %s CR   %s" % [info["name"], GameState.fmt(info["price"]), ("OK: tap BUILD" if reason == "" else reason)]
			_place_label.add_theme_color_override("font_color", UIKit.GOOD if reason == "" else UIKit.BAD)
	if GameState.tank_dust >= GameState.tank_capacity() - 0.01:
		_tank_flash += delta
		_tank_bar.modulate = Color(1, 1, 1, 0.6 + 0.4 * sin(_tank_flash * 8.0))
	else:
		_tank_bar.modulate = Color.WHITE
	_perf.visible = bool(Settings.get_value("perf_overlay", false))
	if _perf.visible:
		var fps := Engine.get_frames_per_second()
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		var vmem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var chunks: int = world.terrain.active_chunks() if world else 0
		_perf.text = "FPS %d  (%.1f ms)\nprocess %.1f ms  physics %.1f ms\nRAM %.0f MB  VRAM %.0f MB\ndraw calls %d  tris %dk\nchunks %d  dirt chunks %d\nscale %.2f" % [
			fps, 1000.0 / maxf(fps, 1), ms, phys, mem, vmem, draws, prims / 1000, chunks, GameState.dirt.chunks.size(), get_viewport().scaling_3d_scale]
