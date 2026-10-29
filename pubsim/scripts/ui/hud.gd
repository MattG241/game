class_name HUD
extends CanvasLayer
## In-game heads-up display, pour-mode controls, toasts, and entry point for the menus.

var world: World
var frame: Control
var touch: TouchControls
var cash_label: Label
var time_label: Label
var rep_label: Label
var orders_box: VBoxContainer
var prompt_label: Label
var crosshair: Control
var ctx_btn: TouchButton
var alt_btn: TouchButton
var menu_btn: TouchButton
var ff_btn: TouchButton
var toast_box: VBoxContainer
var tip_panel: PanelContainer
var tip_label: Label
var tip_close: TouchButton
var subtitle_label: Label
var fps_label: Label
var held_label: Label
# pour mode
var pour_root: Control
var tilt_slider: TouchSlider
var lever_slider: TouchSlider
var gauge: Control
var pour_status: Label
var pour_feedback: Label
var settle_btn: TouchButton
var done_btn: TouchButton
var pour_ctrl: PourController
# overlays
var result_card: PanelContainer
var result_label: RichTextLabel
var menu: MenuPanel
# mini-games
var drink_root: Control
var drink_btn: TouchButton
var drink_leave: TouchButton
var drink_retry: TouchButton
var drink_label: Label
var drink_result: Label
var drink_ctrl: DrinkScene
var darts_root: Control
var darts_pad: TouchPad
var darts_score: Label
var darts_status: Label
var darts_leave: TouchButton
var darts_again: TouchButton
var darts_ctrl: DartsGame
var _result_t := 0.0
var _order_t := 0.0
var _subtitle_t := 0.0
var _tip_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	frame = Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = UITheme.theme()
	add_child(frame)
	touch = TouchControls.new()
	frame.add_child(touch)
	touch.look_delta.connect(func(d): world.player.look(d))
	_build_status()
	_build_actions()
	_build_pour_ui()
	_build_overlays()
	_build_minigame_ui()
	menu = MenuPanel.new()
	menu.hud = self
	frame.add_child(menu)
	menu.visible = false
	GameState.message.connect(toast)
	GameState.settings_changed.connect(apply_settings)
	get_viewport().size_changed.connect(_apply_safe_area)
	apply_settings()
	_apply_safe_area()


func _apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var vp := frame.get_viewport_rect().size
	var m := Vector4(16, 12, 16, 12)
	if win.x > 0 and win.y > 0 and safe.size.x > 0 and OS.has_feature("mobile"):
		var sx := vp.x / win.x
		var sy := vp.y / win.y
		m.x = maxf(m.x, safe.position.x * sx)
		m.y = maxf(m.y, safe.position.y * sy)
		m.z = maxf(m.z, (win.x - safe.end.x) * sx)
		m.w = maxf(m.w, (win.y - safe.end.y) * sy)
	frame.offset_left = m.x
	frame.offset_top = m.y
	frame.offset_right = -m.z
	frame.offset_bottom = -m.w


func apply_settings() -> void:
	var a := float(GameState.settings.get("button_opacity", 0.85))
	for b in [ctx_btn, alt_btn, menu_btn, ff_btn, settle_btn, done_btn]:
		if b:
			b.modulate.a = clampf(a + 0.1, 0.3, 1.0)
	get_tree().root.content_scale_factor = clampf(float(GameState.settings.get("hud_scale", 1.0)), 0.8, 1.4)
	if fps_label:
		fps_label.visible = bool(GameState.settings.get("show_fps", false))
	var contrast := bool(GameState.settings.get("high_contrast", false))
	if prompt_label:
		prompt_label.add_theme_constant_override("outline_size", 12 if contrast else 6)


func _build_status() -> void:
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.1, 0.06, 0.04, 0.82), Color(0.55, 0.38, 0.18), 16, 2))
	status.position = Vector2(0, 0)
	frame.add_child(status)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	status.add_child(vb)
	cash_label = UITheme.label("€0.00", 36, UITheme.GOLD)
	vb.add_child(cash_label)
	time_label = UITheme.label("", 22)
	vb.add_child(time_label)
	rep_label = UITheme.label("", 20, UITheme.MUTED)
	vb.add_child(rep_label)
	orders_box = VBoxContainer.new()
	orders_box.position = Vector2(0, 150)
	orders_box.add_theme_constant_override("separation", 6)
	frame.add_child(orders_box)
	menu_btn = TouchButton.new("Menu")
	_place(menu_btn, Control.PRESET_TOP_RIGHT, Vector2(-150, 0), Vector2(150, 76))
	menu_btn.pressed.connect(func(): open_menu("upgrades"))
	frame.add_child(menu_btn)
	ff_btn = TouchButton.new(">>", Color(0.2, 0.15, 0.1, 0.9))
	_place(ff_btn, Control.PRESET_TOP_RIGHT, Vector2(-260, 0), Vector2(96, 76))
	ff_btn.font_size = 30
	ff_btn.pressed.connect(func(): world.set_fast_forward(not world.fast_forward))
	frame.add_child(ff_btn)
	fps_label = UITheme.label("", 18, Color(0.6, 1, 0.6))
	_place(fps_label, Control.PRESET_TOP_RIGHT, Vector2(-520, 84), Vector2(520, 30))
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame.add_child(fps_label)


func _build_actions() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func(): crosshair.draw_circle(Vector2.ZERO, 4, Color(1, 0.95, 0.8, 0.8)))
	frame.add_child(crosshair)
	prompt_label = UITheme.label("", 28)
	_place(prompt_label, Control.PRESET_CENTER, Vector2(-380, 34), Vector2(760, 40))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(prompt_label)
	held_label = UITheme.label("", 20, UITheme.MUTED)
	_place(held_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-500, -300), Vector2(500, 30))
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame.add_child(held_label)
	ctx_btn = TouchButton.new("")
	_place(ctx_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-250, -140), Vector2(250, 140))
	ctx_btn.font_size = 26
	ctx_btn.pressed.connect(_on_ctx_pressed)
	ctx_btn.held_complete.connect(_on_ctx_held)
	frame.add_child(ctx_btn)
	alt_btn = TouchButton.new("", Color(0.3, 0.18, 0.08, 0.92))
	_place(alt_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-250, -236), Vector2(250, 84))
	alt_btn.font_size = 22
	alt_btn.pressed.connect(func():
		if world.player.focus:
			world.player.focus.activate_alt())
	frame.add_child(alt_btn)
	toast_box = VBoxContainer.new()
	_place(toast_box, Control.PRESET_CENTER_TOP, Vector2(-330, 92), Vector2(660, 10))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(toast_box)
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.06, 0.2, 0.12, 0.9), UITheme.GOLD, 16, 2))
	_place(tip_panel, Control.PRESET_CENTER_TOP, Vector2(-330, 0), Vector2(660, 60))
	tip_panel.custom_minimum_size = Vector2(660, 0)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	frame.add_child(tip_panel)
	tip_label = UITheme.label("", 22)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(600, 0)
	tip_panel.add_child(tip_label)
	tip_close = TouchButton.new("×", Color(0.3, 0.12, 0.08, 0.9))
	tip_close.size = Vector2(54, 54)
	tip_close.round_btn = true
	tip_close.font_size = 30
	_place(tip_close, Control.PRESET_CENTER_TOP, Vector2(340, 0), Vector2(54, 54))
	tip_close.visible = false
	tip_close.pressed.connect(func():
		tip_label.text = ""
		tip_panel.visible = false
		tip_close.visible = false)
	frame.add_child(tip_close)
	subtitle_label = UITheme.label("", 24)
	_place(subtitle_label, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -96), Vector2(620, 70))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(subtitle_label)


func _build_pour_ui() -> void:
	pour_root = Control.new()
	pour_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pour_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pour_root.visible = false
	frame.add_child(pour_root)
	tilt_slider = TouchSlider.new()
	tilt_slider.title = "TILT GLASS"
	_place(tilt_slider, Control.PRESET_TOP_LEFT, Vector2(20, 120), Vector2(170, 470))
	tilt_slider.target_band = Vector2(38.0 / 90.0, 52.0 / 90.0)
	tilt_slider.marker_text = "45°"
	tilt_slider.changed.connect(func(v): if pour_ctrl: pour_ctrl.tilt_input = v)
	pour_root.add_child(tilt_slider)
	lever_slider = TouchSlider.new()
	lever_slider.title = "PULL TAP"
	lever_slider.inverted = true
	lever_slider.spring_back = true
	lever_slider.accent = Color(0.5, 0.85, 0.55)
	_place(lever_slider, Control.PRESET_TOP_RIGHT, Vector2(-190, 120), Vector2(170, 470))
	lever_slider.changed.connect(func(v): if pour_ctrl: pour_ctrl.lever = v)
	pour_root.add_child(lever_slider)
	gauge = Control.new()
	_place(gauge, Control.PRESET_TOP_RIGHT, Vector2(-260, 160), Vector2(56, 400))
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	pour_root.add_child(gauge)
	pour_status = UITheme.label("", 26)
	_place(pour_status, Control.PRESET_CENTER_TOP, Vector2(-380, 8), Vector2(760, 70))
	pour_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pour_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pour_root.add_child(pour_status)
	pour_feedback = UITheme.label("", 24, UITheme.GOLD)
	_place(pour_feedback, Control.PRESET_CENTER_TOP, Vector2(-350, 84), Vector2(700, 70))
	pour_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pour_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pour_root.add_child(pour_feedback)
	settle_btn = TouchButton.new("Leave to settle")
	_place(settle_btn, Control.PRESET_CENTER_BOTTOM, Vector2(-262, -92), Vector2(250, 84))
	settle_btn.pressed.connect(func(): if pour_ctrl: pour_ctrl.end(true))
	pour_root.add_child(settle_btn)
	done_btn = TouchButton.new("Lower glass", Color(0.3, 0.18, 0.08, 0.92))
	_place(done_btn, Control.PRESET_CENTER_BOTTOM, Vector2(12, -92), Vector2(250, 84))
	done_btn.pressed.connect(func(): if pour_ctrl: pour_ctrl.end(false))
	pour_root.add_child(done_btn)


func _draw_gauge() -> void:
	if pour_ctrl == null or pour_ctrl.glass == null:
		return
	var c := pour_ctrl.glass.contents
	var h := gauge.size.y
	var w := gauge.size.x
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.95, 1.0, 0.12)
	sb.border_color = Color(0.9, 0.9, 0.85, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	gauge.draw_style_box(sb, Rect2(0, 0, w, h))
	var scale := h / 1.05
	var y_of := func(v: float) -> float: return h - v * scale
	var dark := clampf(c.body, 0.0, 1.05)
	var liq := clampf(c.liquid_level(), 0.0, 1.05)
	var tot := clampf(c.total(), 0.0, 1.05)
	gauge.draw_rect(Rect2(4, y_of.call(dark), w - 8, dark * scale), Color(0.08, 0.03, 0.02))
	gauge.draw_rect(Rect2(4, y_of.call(liq), w - 8, (liq - dark) * scale), Color(0.5, 0.32, 0.18))
	gauge.draw_rect(Rect2(4, y_of.call(tot), w - 8, (tot - liq) * scale), Color(0.95, 0.88, 0.72))
	var font := MeshKit.font_ui(800)
	for mark in [[0.75, "¾"], [1.0, "top"]]:
		var y: float = y_of.call(mark[0])
		gauge.draw_line(Vector2(-8, y), Vector2(w + 8, y), UITheme.GOLD, 2.0)
		gauge.draw_string(font, Vector2(-62, y + 8), mark[1], HORIZONTAL_ALIGNMENT_RIGHT, 50, 20, UITheme.GOLD)


func _build_overlays() -> void:
	result_card = PanelContainer.new()
	result_card.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.1, 0.06, 0.04, 0.95), UITheme.GOLD, 20, 3))
	_place(result_card, Control.PRESET_CENTER, Vector2(-260, -220), Vector2(520, 10))
	result_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_card.custom_minimum_size = Vector2(520, 0)
	result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_card.visible = false
	frame.add_child(result_card)
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(480, 0)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.add_theme_font_size_override("normal_font_size", 24)
	result_label.add_theme_font_size_override("bold_font_size", 34)
	result_label.add_theme_font_override("normal_font", MeshKit.font_ui(700))
	result_label.add_theme_font_override("bold_font", MeshKit.font_title())
	result_card.add_child(result_label)


static func _place(c: Control, preset: int, pos: Vector2, sz: Vector2) -> void:
	## Anchors the control, then sets offsets relative to that anchor point.
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func _build_minigame_ui() -> void:
	drink_root = Control.new()
	drink_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drink_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drink_root.visible = false
	frame.add_child(drink_root)
	drink_label = UITheme.label("", 26)
	drink_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drink_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(drink_label, Control.PRESET_CENTER_TOP, Vector2(-420, 6), Vector2(840, 90))
	drink_root.add_child(drink_label)
	drink_result = UITheme.label("", 34, UITheme.GOLD, MeshKit.font_title())
	drink_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drink_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(drink_result, Control.PRESET_CENTER, Vector2(-420, 120), Vector2(840, 140))
	drink_root.add_child(drink_result)
	drink_btn = TouchButton.new("Hold to drink")
	drink_btn.font_size = 30
	_place(drink_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-300, -170), Vector2(300, 170))
	drink_btn.pressed.connect(func(): if drink_ctrl: drink_ctrl.press())
	drink_btn.released.connect(func(): if drink_ctrl: drink_ctrl.release())
	drink_root.add_child(drink_btn)
	drink_leave = TouchButton.new("Leave", Color(0.3, 0.18, 0.08, 0.92))
	_place(drink_leave, Control.PRESET_BOTTOM_LEFT, Vector2(0, -90), Vector2(200, 84))
	drink_leave.pressed.connect(func(): if drink_ctrl: drink_ctrl.end())
	drink_root.add_child(drink_leave)
	drink_retry = TouchButton.new("Try again")
	_place(drink_retry, Control.PRESET_BOTTOM_LEFT, Vector2(216, -90), Vector2(220, 84))
	drink_retry.pressed.connect(func(): if drink_ctrl: drink_ctrl.retry())
	drink_root.add_child(drink_retry)
	darts_root = Control.new()
	darts_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	darts_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	darts_root.visible = false
	frame.add_child(darts_root)
	darts_pad = TouchPad.new()
	darts_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	darts_pad.dragged.connect(func(rel): if darts_ctrl: darts_ctrl.drag(rel))
	darts_pad.released.connect(func(): if darts_ctrl: darts_ctrl.release_throw())
	darts_root.add_child(darts_pad)
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.06, 0.08, 0.07, 0.9), Color(0.6, 0.5, 0.3), 14, 2))
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(sp, Control.PRESET_CENTER_TOP, Vector2(-330, 0), Vector2(660, 60))
	darts_root.add_child(sp)
	darts_score = UITheme.label("", 30, UITheme.CREAM, MeshKit.font_title())
	darts_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp.add_child(darts_score)
	darts_status = UITheme.label("", 24)
	darts_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	darts_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(darts_status, Control.PRESET_CENTER_BOTTOM, Vector2(-420, -190), Vector2(840, 80))
	darts_root.add_child(darts_status)
	darts_leave = TouchButton.new("Leave the oche", Color(0.3, 0.18, 0.08, 0.92))
	_place(darts_leave, Control.PRESET_BOTTOM_LEFT, Vector2(0, -90), Vector2(240, 84))
	darts_leave.pressed.connect(func(): if darts_ctrl: darts_ctrl.end())
	darts_root.add_child(darts_leave)
	darts_again = TouchButton.new("Rematch")
	_place(darts_again, Control.PRESET_BOTTOM_LEFT, Vector2(256, -90), Vector2(200, 84))
	darts_again.pressed.connect(func():
		if darts_ctrl:
			var opp := darts_ctrl.opponent
			darts_ctrl.end()
			await get_tree().create_timer(0.5).timeout
			darts_ctrl.begin(opp))
	darts_root.add_child(darts_again)


func _hide_gameplay(on: bool) -> void:
	touch.reset()
	touch.gameplay = not on
	for n in [ctx_btn, alt_btn, crosshair, prompt_label, held_label, orders_box, menu_btn, ff_btn, tip_panel, tip_close]:
		n.visible = not on
	if not on:
		tip_panel.visible = tip_label.text != ""
		tip_close.visible = tip_panel.visible
		ctx_btn.visible = false
		alt_btn.visible = false


func enter_drink_mode(ds: DrinkScene) -> void:
	drink_ctrl = ds
	_hide_gameplay(true)
	drink_root.visible = true
	drink_result.text = ""
	drink_retry.visible = false
	drink_btn.visible = true
	if ds.mode == "split":
		var best := "" if GameState.best_split_mm < 0.0 else "  Your best: %.1f mm." % GameState.best_split_mm
		drink_label.text = "Split the Knot: hold to take ONE gulp. Let go when you think the line between the stout and the head will sit exactly on the bar through the knot.%s" % best
	else:
		drink_label.text = "Your own pint by the fire. Hold to sip, at your own pace."


func update_drink_ui(ds: DrinkScene) -> void:
	drink_btn.visible = ds.state in ["ready", "drinking", "between"]
	drink_btn.set_label("Drinking..." if ds.state == "drinking" else ("Hold to sip" if ds.mode == "relax" else "Hold to drink"))


func set_drink_text(t: String) -> void:
	drink_label.text = t


func show_split_result(res: Dictionary) -> void:
	drink_result.text = "%s\n%s" % [res["verdict"], res["where"]]
	drink_label.text = "Score %d%s\n%s" % [res["score"], "  ·  New personal best!" if res["best"] else "", res["reaction"]]
	drink_retry.visible = true
	drink_btn.visible = false


func exit_drink_mode() -> void:
	drink_ctrl = null
	drink_root.visible = false
	_hide_gameplay(false)


func enter_darts_mode(dg: DartsGame) -> void:
	darts_ctrl = dg
	_hide_gameplay(true)
	darts_root.visible = true
	darts_again.visible = false
	update_darts_ui(dg, "")


func update_darts_ui(dg: DartsGame, status: String) -> void:
	darts_score.text = "You  %d     %s  %d     Darts left %d" % [dg.scores[0], dg.opponent_name, dg.scores[1], dg.darts_left]
	if status != "":
		darts_status.text = status
	darts_again.visible = dg.winner >= 0


func exit_darts_mode() -> void:
	darts_ctrl = null
	darts_root.visible = false
	_hide_gameplay(false)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if world == null:
		return
	var gs := GameState
	cash_label.text = "€%.2f" % gs.cash
	var weather_txt: String = {"rain": "Rain", "storm": "Storm", "cloudy": "Cloudy", "clear": "Clear"}.get(gs.weather, "")
	var phase_txt: String = {"prep": "Closed", "open": "Open", "last_orders": "Last orders", "closing": "Closing"}.get(gs.phase, "")
	time_label.text = "%s · Day %d · %s · %s · %s" % [gs.weekday_name().substr(0, 3), gs.day, gs.clock_text(), weather_txt, phase_txt]
	rep_label.text = "Reputation %d · Clean %d%% · Atmos %d" % [int(gs.reputation), int(world.cleanliness()), int(gs.atmosphere())]
	if fps_label.visible:
		fps_label.text = "%d fps  %.1f ms  %d npc  %d draws  %d MB" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			world.customers.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)]
	world.player.move_input = touch.move
	var pouring := pour_root.visible
	if not pouring and not menu.visible and not drink_root.visible and not darts_root.visible:
		_update_context()
	if pouring and pour_ctrl:
		_update_pour_ui()
	ff_btn.color = Color(0.6, 0.4, 0.1, 0.95) if world.fast_forward else Color(0.2, 0.15, 0.1, 0.9)
	ff_btn.enabled = world.can_fast_forward() or world.fast_forward
	ff_btn.queue_redraw()
	_order_t -= delta
	if _order_t <= 0.0:
		_order_t = 0.25
		refresh_orders()
	if _result_t > 0.0:
		_result_t -= delta
		if _result_t <= 0.0:
			result_card.visible = false
	if _subtitle_t > 0.0:
		_subtitle_t -= delta
		if _subtitle_t <= 0.0:
			subtitle_label.text = ""
	if _tip_t > 0.0:
		_tip_t -= delta


func _update_context() -> void:
	var p := world.player
	var f := p.focus
	var text := ""
	var enabled := false
	if f:
		text = f.prompt()
		enabled = not text.begins_with("~")
		text = text.trim_prefix("~")
	prompt_label.text = text
	prompt_label.add_theme_color_override("font_color", UITheme.CREAM if enabled else UITheme.MUTED)
	ctx_btn.visible = f != null and enabled
	if ctx_btn.visible:
		ctx_btn.hold_seconds = f.hold_seconds
		var short := text
		if short.length() > 22:
			short = _wrap(short, 20)
		ctx_btn.set_label(short, "hold" if f.hold_seconds > 0.0 else "")
	var alt := f.alt_prompt() if f else ""
	alt_btn.visible = alt != ""
	if alt_btn.visible:
		alt_btn.set_label(_wrap(alt, 20))
	var held := ""
	if p.held:
		var c := p.held.contents
		if c.is_empty():
			held = "Holding: clean glass" if p.held.dirt < 0.1 else "Holding: dirty glass"
		else:
			held = "Holding: %s (%d%% full)" % [GameData.drink(c.drink_id).get("short", ""), int(c.total() * 100)]
	elif not p.dirty_stack.is_empty():
		held = "Carrying %d dirty glass%s" % [p.dirty_stack.size(), "" if p.dirty_stack.size() == 1 else "es"]
	held_label.text = held


func _wrap(t: String, n: int) -> String:
	var words := t.split(" ")
	var out := ""
	var line := ""
	for w in words:
		if (line + " " + w).strip_edges().length() > n and line != "":
			out += line.strip_edges() + "\n"
			line = w
		else:
			line += " " + w
	return (out + line.strip_edges()).strip_edges()


func _on_ctx_pressed() -> void:
	var f := world.player.focus
	if f and f.hold_seconds <= 0.0 and not f.prompt().begins_with("~"):
		Sfx.play("ui_click", -12.0, 0.0)
		f.activate()


func _on_ctx_held() -> void:
	var f := world.player.focus
	if f and f.hold_seconds > 0.0 and not f.prompt().begins_with("~"):
		f.activate()


func refresh() -> void:
	pass


func refresh_orders() -> void:
	for ch in orders_box.get_children():
		ch.queue_free()
	var shown := 0
	for c in world.customers:
		if c.state not in ["wait_order", "wait_drink"] or shown >= 5:
			continue
		shown += 1
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.92, 0.88, 0.76, 0.92), Color(0.4, 0.3, 0.15), 10, 2))
		p.custom_minimum_size = Vector2(250, 0)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		p.add_child(vb)
		var what: String = GameData.drink(c.drink_id).get("short", "?") if c.order_taken else "wants to order"
		var l := UITheme.label("%s: %s" % [c.display_name, what], 20, Color(0.15, 0.1, 0.05))
		l.add_theme_constant_override("outline_size", 0)
		vb.add_child(l)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(220.0 * c.patience_frac(), 8)
		bar.color = Color(0.85, 0.25, 0.2).lerp(Color(0.2, 0.6, 0.3), c.patience_frac())
		vb.add_child(bar)
		orders_box.add_child(p)


# ------------------------------------------------------------------ pour mode
func enter_pour_mode(ctrl: PourController) -> void:
	pour_ctrl = ctrl
	_hide_gameplay(true)
	pour_root.visible = true
	tilt_slider.set_value(0.0)
	lever_slider.set_value(0.0)
	pour_feedback.text = ""
	var assist := bool(GameState.settings.get("pour_assist", false))
	tilt_slider.visible = not assist
	var stout := ctrl.serve == "stout"
	settle_btn.visible = stout


func exit_pour_mode() -> void:
	pour_ctrl = null
	pour_root.visible = false
	_hide_gameplay(false)


func set_pour_feedback(t: String) -> void:
	pour_feedback.text = t


func _update_pour_ui() -> void:
	pour_status.text = pour_ctrl.status_text()
	tilt_slider.readout = "%d°" % int(pour_ctrl.tilt)
	tilt_slider.queue_redraw()
	lever_slider.readout = "%d%%" % int(pour_ctrl.lever * 100)
	lever_slider.queue_redraw()
	gauge.queue_redraw()
	var free: bool = pour_ctrl.world.free_settle_slot() >= 0
	settle_btn.enabled = free and not pour_ctrl.glass.contents.is_empty()
	settle_btn.queue_redraw()


func show_pour_result(res: Dictionary) -> void:
	var q: int = res.get("score", 0)
	var col := "#9be59b" if q >= 75 else ("#f2d27a" if q >= 55 else "#f08a70")
	var t := "[center][b][color=%s]%s[/color][/b]\n" % [col, res.get("verdict", "")]
	t += "Quality %d / 100\n" % q
	if res.get("ok", false):
		t += "[color=#f2c25c]+€%.2f[/color]" % res.get("price", 0.0)
		if res.get("tip", 0.0) > 0.0:
			t += "  ·  [color=#9be59b]tip €%.2f[/color]" % res["tip"]
		t += "\nSatisfaction %d%%\n" % int(res.get("satisfaction", 0))
	var notes: Array = res.get("notes", [])
	if not notes.is_empty():
		t += "[color=#d8c9a8]" + "\n".join(notes) + "[/color]"
	t += "[/center]"
	result_label.text = t
	result_card.visible = true
	_result_t = 4.5


# ------------------------------------------------------------------ messages
func toast(text: String, kind := "info") -> void:
	var colors := {"good": Color(0.12, 0.38, 0.2, 0.92), "bad": Color(0.45, 0.12, 0.08, 0.92), "warn": Color(0.45, 0.32, 0.05, 0.92), "info": Color(0.12, 0.08, 0.05, 0.9)}
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_box(colors.get(kind, colors["info"]), Color(0.75, 0.6, 0.3), 12, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(600, 0)
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func set_tip(text: String) -> void:
	tip_label.text = text
	var show := text != "" and not pour_root.visible
	tip_panel.visible = show
	tip_close.visible = show
	tip_panel.reset_size()
	_tip_t = 12.0


func subtitle(who: String, text: String) -> void:
	subtitle_label.text = "%s: %s" % [who, text]
	_subtitle_t = 4.0


# ------------------------------------------------------------------ menus
func open_menu(tab: String) -> void:
	if pour_root.visible or drink_root.visible or darts_root.visible:
		return
	touch.reset()
	touch.enabled = false
	world.set_fast_forward(false)
	get_tree().paused = true
	menu.open(tab)


func close_menu() -> void:
	menu.visible = false
	touch.enabled = true
	get_tree().paused = false


func show_day_summary(s: Dictionary) -> void:
	touch.reset()
	touch.enabled = false
	get_tree().paused = true
	menu.show_summary(s)
