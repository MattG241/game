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
var celebration: PanelContainer
var celebration_title: Label
var celebration_body: Label
var celebration_ok: TouchButton
var _celebration_track := ""
var _result_t := 0.0
var _order_t := 0.0
var _subtitle_t := 0.0
var _tip_t := 0.0
var goal_card: PanelContainer
var goal_chip: TouchButton
var next_pill: PanelContainer
var next_label: Label
var goals_box: VBoxContainer
var _goals_t := 0.0
var _goals_open_t := 0.0         # the goal list opens for a moment when one is met (or on a tap)
var _goals_done := -1


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
	_build_celebration()
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


## The largest text scale that still leaves room for the menus and the pour sliders on this screen.
func _max_scale() -> float:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return 1.25
	var s := minf(win.x / 1280.0, win.y / 720.0)
	return clampf(minf(win.x / (s * 1060.0), win.y / (s * 620.0)), 0.8, 1.25)


func apply_settings() -> void:
	var a := float(GameState.settings.get("button_opacity", 0.85))
	for b in [ctx_btn, alt_btn, menu_btn, ff_btn, settle_btn, done_btn]:
		if b:
			b.modulate.a = clampf(a + 0.1, 0.3, 1.0)
	get_tree().root.content_scale_factor = clampf(float(GameState.settings.get("hud_scale", 1.0)), 0.8, _max_scale())
	if fps_label:
		fps_label.visible = bool(GameState.settings.get("show_fps", false))
	var contrast := bool(GameState.settings.get("high_contrast", false))
	if prompt_label:
		prompt_label.add_theme_constant_override("outline_size", 8 if contrast else 0)


func _build_status() -> void:
	# top left: cash, then day, time, weather and state in one quiet line
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UITheme.glass_box(0.62, 14, Color(0, 0, 0, 0), 16, 8))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.position = Vector2(0, 0)
	frame.add_child(status)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	status.add_child(vb)
	cash_label = UITheme.hud_label("€0.00", 30, UITheme.GOLD, 800)
	vb.add_child(cash_label)
	time_label = UITheme.hud_label("", 17, Color(1, 0.97, 0.9, 0.85))
	vb.add_child(time_label)
	rep_label = UITheme.hud_label("", 16, Color(1.0, 0.72, 0.4))    # only shown when something needs attention
	rep_label.visible = false
	vb.add_child(rep_label)
	orders_box = VBoxContainer.new()
	orders_box.position = Vector2(0, 104)
	orders_box.add_theme_constant_override("separation", 6)
	orders_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(orders_box)
	# top right: fast-forward and menu
	menu_btn = TouchButton.new("Menu")
	menu_btn.style = "glass"
	menu_btn.font_size = 21
	_place(menu_btn, Control.PRESET_TOP_RIGHT, Vector2(-112, 0), Vector2(112, 54))
	menu_btn.pressed.connect(func(): open_menu("upgrades"))
	frame.add_child(menu_btn)
	ff_btn = TouchButton.new(">>")
	ff_btn.style = "glass"
	ff_btn.font_size = 22
	_place(ff_btn, Control.PRESET_TOP_RIGHT, Vector2(-190, 0), Vector2(68, 54))
	ff_btn.pressed.connect(func(): world.set_fast_forward(not world.fast_forward))
	frame.add_child(ff_btn)
	# top centre: the one thing to do next
	next_pill = PanelContainer.new()
	next_pill.add_theme_stylebox_override("panel", UITheme.glass_box(0.62, 14, UITheme.GOLD, 16, 7))
	next_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(next_pill, Control.PRESET_CENTER_TOP, Vector2(-140, 0), Vector2(280, 10))
	next_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH     # sized to the text, kept centred
	frame.add_child(next_pill)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -3)
	next_pill.add_child(nv)
	nv.add_child(UITheme.hud_label("NEXT", 13, UITheme.GOLD, 800))
	next_label = UITheme.hud_label("", 20)
	nv.add_child(next_label)
	# goals: a small chip that opens the list (it also opens by itself when one is met)
	goal_chip = TouchButton.new("Goals 0/3")
	goal_chip.style = "glass"
	goal_chip.font_size = 18
	_place(goal_chip, Control.PRESET_TOP_RIGHT, Vector2(-190, 62), Vector2(190, 44))
	goal_chip.pressed.connect(func(): _goals_open_t = 0.0 if _goals_open_t > 0.0 else 9999.0)
	frame.add_child(goal_chip)
	goal_card = PanelContainer.new()
	goal_card.add_theme_stylebox_override("panel", UITheme.glass_box(0.62, 14, Color(0, 0, 0, 0), 14, 8))
	goal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(goal_card, Control.PRESET_TOP_RIGHT, Vector2(-360, 114), Vector2(360, 10))
	goal_card.custom_minimum_size = Vector2(360, 0)
	frame.add_child(goal_card)
	goals_box = VBoxContainer.new()
	goals_box.add_theme_constant_override("separation", 2)
	goal_card.add_child(goals_box)
	fps_label = UITheme.hud_label("", 16, Color(0.6, 1, 0.6))
	_place(fps_label, Control.PRESET_BOTTOM_LEFT, Vector2(0, -24), Vector2(520, 24))
	frame.add_child(fps_label)

func _build_actions() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func(): crosshair.draw_circle(Vector2.ZERO, 3, Color(1, 1, 1, 0.7)))
	frame.add_child(crosshair)
	prompt_label = UITheme.hud_label("", 19, Color(1, 0.97, 0.9, 0.8))
	_place(prompt_label, Control.PRESET_CENTER, Vector2(-380, 26), Vector2(760, 30))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(prompt_label)
	held_label = UITheme.hud_label("", 16, Color(1, 0.97, 0.9, 0.65))
	_place(held_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-500, -232), Vector2(500, 24))
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame.add_child(held_label)
	ctx_btn = TouchButton.new("", Color(0.12, 0.45, 0.29, 0.94))
	ctx_btn.style = "accent"
	_place(ctx_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-230, -116), Vector2(230, 116))
	ctx_btn.font_size = 23
	ctx_btn.pressed.connect(_on_ctx_pressed)
	ctx_btn.held_complete.connect(_on_ctx_held)
	frame.add_child(ctx_btn)
	alt_btn = TouchButton.new("")
	alt_btn.style = "glass"
	_place(alt_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-230, -196), Vector2(230, 70))
	alt_btn.font_size = 19
	alt_btn.pressed.connect(func():
		if world.player.focus:
			world.player.focus.activate_alt())
	frame.add_child(alt_btn)
	toast_box = VBoxContainer.new()
	_place(toast_box, Control.PRESET_CENTER_TOP, Vector2(-260, 76), Vector2(520, 10))
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(toast_box)
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", UITheme.glass_box(0.7, 14, UITheme.GOLD, 16, 10))
	# tutorial tips sit low in the middle, clear of the status, the goals and the buttons
	_place(tip_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-290, -150), Vector2(580, 60))
	tip_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip_panel.custom_minimum_size = Vector2(580, 0)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	frame.add_child(tip_panel)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 12)
	tip_panel.add_child(tip_row)
	tip_label = UITheme.hud_label("", 19)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(480, 0)
	tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip_label)
	tip_close = TouchButton.new("×")
	tip_close.style = "glass"
	tip_close.custom_minimum_size = Vector2(44, 44)
	tip_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tip_close.round_btn = true
	tip_close.font_size = 24
	tip_close.visible = false
	tip_close.pressed.connect(func():
		tip_label.text = ""
		tip_panel.visible = false
		tip_close.visible = false)
	tip_row.add_child(tip_close)
	subtitle_label = UITheme.hud_label("", 21)
	_place(subtitle_label, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -84), Vector2(620, 64))
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
	pour_status = UITheme.hud_label("", 22)
	_place(pour_status, Control.PRESET_CENTER_TOP, Vector2(-380, 8), Vector2(760, 70))
	pour_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pour_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pour_root.add_child(pour_status)
	pour_feedback = UITheme.hud_label("", 20, UITheme.GOLD)
	_place(pour_feedback, Control.PRESET_CENTER_TOP, Vector2(-350, 84), Vector2(700, 70))
	pour_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pour_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pour_root.add_child(pour_feedback)
	settle_btn = TouchButton.new("Leave to settle", Color(0.12, 0.45, 0.29, 0.94))
	settle_btn.style = "accent"
	settle_btn.font_size = 21
	_place(settle_btn, Control.PRESET_CENTER_BOTTOM, Vector2(-242, -80), Vector2(230, 72))
	settle_btn.pressed.connect(func(): if pour_ctrl: pour_ctrl.end(true))
	pour_root.add_child(settle_btn)
	done_btn = TouchButton.new("Lower glass")
	done_btn.style = "glass"
	done_btn.font_size = 21
	_place(done_btn, Control.PRESET_CENTER_BOTTOM, Vector2(12, -80), Vector2(230, 72))
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
	result_card.add_theme_stylebox_override("panel", UITheme.glass_box(0.72, 18, Color(0, 0, 0, 0), 22, 14))
	_place(result_card, Control.PRESET_CENTER, Vector2(-220, -210), Vector2(440, 10))
	result_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_card.custom_minimum_size = Vector2(440, 0)
	result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_card.visible = false
	frame.add_child(result_card)
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(396, 0)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.add_theme_font_size_override("normal_font_size", 20)
	result_label.add_theme_font_size_override("bold_font_size", 30)
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
			var dg := darts_ctrl         # end() clears darts_ctrl, so keep hold of the game
			var opp := dg.opponent
			dg.end()
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(dg) and not dg.active:
				dg.begin(opp))
	darts_root.add_child(darts_again)


func _build_celebration() -> void:
	celebration = PanelContainer.new()
	celebration.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.07, 0.2, 0.12, 0.96), UITheme.GOLD, 22, 4))
	celebration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(celebration, Control.PRESET_CENTER, Vector2(-330, -190), Vector2(660, 330))
	celebration.visible = false
	frame.add_child(celebration)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	celebration.add_child(vb)
	celebration_title = UITheme.label("", 40, UITheme.GOLD, MeshKit.font_title())
	celebration_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	celebration_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(celebration_title)
	celebration_body = UITheme.label("", 24)
	celebration_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	celebration_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(celebration_body)
	celebration_ok = TouchButton.new("Sláinte!")
	_place(celebration_ok, Control.PRESET_CENTER, Vector2(-120, 170), Vector2(240, 80))
	celebration_ok.visible = false
	celebration_ok.pressed.connect(dismiss_celebration)
	frame.add_child(celebration_ok)


## Big moments (renovations, awards) get a card and their own music until dismissed.
func show_celebration(title: String, body: String, track: String) -> void:
	celebration_title.text = title
	var now := MusicDirector.title_of(track)
	celebration_body.text = body + ("\n\nNow playing: %s" % now if now != "" else "")
	celebration.visible = true
	celebration_ok.visible = true
	celebration_ok.set_label("Sláinte!")
	_celebration_track = track
	Sfx.play("cheer", -6.0)


## A regular's story: the same card as a celebration, without the music or the cheering.
func show_story(title: String, body: String) -> void:
	celebration_title.text = title
	celebration_body.text = body
	celebration.visible = true
	celebration_ok.visible = true
	celebration_ok.set_label("Go on")
	_celebration_track = ""


func dismiss_celebration() -> void:
	celebration.visible = false
	celebration_ok.visible = false
	if _celebration_track != "":
		MusicDirector.clear_override(_celebration_track)
	_celebration_track = ""


func _hide_gameplay(on: bool) -> void:
	touch.reset()
	touch.gameplay = not on
	for n in [ctx_btn, alt_btn, crosshair, prompt_label, held_label, orders_box, menu_btn, ff_btn, tip_panel, tip_close, next_pill, goal_chip, goal_card]:
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
		drink_label.text = "Split the G: hold to take ONE gulp. Let go when you think the line between the stout and the head will sit exactly halfway through the G.%s" % best
	else:
		drink_label.text = "Your own pint by the fire. Hold to sip, at your own pace."


func update_drink_ui(ds: DrinkScene) -> void:
	drink_btn.visible = ds.state in ["ready", "drinking", "between"]
	drink_btn.set_label("Drinking..." if ds.state == "drinking" else ("Hold to sip" if ds.mode == "relax" else "Hold to drink"))


func set_drink_text(t: String) -> void:
	drink_label.text = t


func show_split_result(res: Dictionary) -> void:
	drink_result.text = "%s\n%s" % [res["verdict"], res["where"]]
	drink_label.text = "Score %d / 100%s   (best %d)\n%s" % [res["score"], "  ·  New personal best!" if res["best"] else "", int(res.get("best_score", res["score"])), res["reaction"]]
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
	time_label.text = "%s %s  ·  Day %d  ·  %s  ·  %s" % [gs.weekday_name().substr(0, 3), gs.clock_text(), gs.day, weather_txt, phase_txt]
	# reputation, cleanliness and atmosphere live in the menu; only a problem earns a line here
	var warn := ""
	if world.cleanliness() < 70.0:
		warn = "The pub needs a tidy (%d%% clean)" % int(world.cleanliness())
	rep_label.text = warn
	rep_label.visible = warn != ""
	if fps_label.visible:
		fps_label.text = "%d fps  %.1f ms  %d npc  %d draws  %d MB" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			world.customers.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)]
	world.player.move_input = touch.move
	var pouring := pour_root.visible
	if not pouring and not menu.visible and not drink_root.visible and not darts_root.visible and not (world.session and world.session.active):
		_update_context()
	if pouring and pour_ctrl:
		_update_pour_ui()
	ff_btn.style = "accent" if world.fast_forward else "glass"
	ff_btn.color = Color(0.72, 0.5, 0.16, 0.95)
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
		if _tip_t <= 0.0 and tip_panel.visible:
			tip_panel.visible = false
			tip_close.visible = false
	var playing := not pour_root.visible and not drink_root.visible and not darts_root.visible and not menu.visible \
		and not celebration.visible and not world.in_minigame()
	if celebration.visible and tip_panel.visible:
		tip_panel.visible = false      # a card has the floor; the tip comes back with the next step
		tip_close.visible = false
	var nt := str(world._guide.get("text", ""))
	if nt != next_label.text:
		next_label.text = nt
		# long steps wrap inside a fixed width so the pill never reaches the cash or the buttons
		var long := nt.length() > 46
		next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if long else TextServer.AUTOWRAP_OFF
		next_label.custom_minimum_size = Vector2(540 if long else 0, 0)
		next_pill.reset_size()
	next_pill.visible = playing and next_label.text != "" and bool(GameState.settings.get("show_guide", true)) \
		and not bool(world._guide.get("idle", false)) and not tip_panel.visible
	_goals_t -= delta
	if _goals_t <= 0.0:
		_goals_t = 1.0
		refresh_goals()
	_goals_open_t -= delta
	goal_chip.visible = playing
	goal_card.visible = playing and _goals_open_t > 0.0


## Today's goals with their progress (ticked off as they're met).
func refresh_goals() -> void:
	if goals_box == null:
		return
	var goals := GameState.daily_goals()
	while goals_box.get_child_count() < goals.size() + 1:
		goals_box.add_child(UITheme.hud_label("", 17))
	(goals_box.get_child(0) as Label).text = "TODAY'S GOALS"
	(goals_box.get_child(0) as Label).add_theme_font_size_override("font_size", 13)
	(goals_box.get_child(0) as Label).add_theme_color_override("font_color", UITheme.GOLD)
	var done := goals.filter(func(g): return g["done"]).size()
	goal_chip.set_label("Goals %d/%d" % [done, goals.size()])
	if _goals_done >= 0 and done > _goals_done:
		_goals_open_t = 5.0      # show the list for a moment when one is met
	_goals_done = done
	for i in goals.size():
		var g: Dictionary = goals[i]
		var l := goals_box.get_child(i + 1) as Label
		var prog := ""
		if g["done"]:
			prog = "done  +€%d" % int(g["reward"])
		elif str(g["kind"]) == "count":
			prog = "%d/%d" % [int(GameState.goal_value(g)), int(g["target"])]
		elif str(g["kind"]) == "zero":
			prog = "so far, so good" if GameState.goal_value(g) <= 0.0 else "missed"
		else:
			prog = "now %d" % int(GameState.goal_value(g)) if int(GameState.today["pours"]) > 0 else ""
		l.text = "%s    %s" % [g["text"], prog]
		l.add_theme_color_override("font_color", Color(0.62, 0.95, 0.62) if g["done"] else (Color(1, 0.62, 0.5) if prog == "missed" else Color(1, 0.97, 0.9, 0.9)))


func _update_context() -> void:
	var p := world.player
	var f := p.focus
	var text := ""
	var enabled := false
	if f:
		text = f.prompt()
		enabled = not text.begins_with("~")
		text = text.trim_prefix("~")
	# the action button already says what it does; the centre line is only for "can't yet" hints
	prompt_label.text = "" if enabled else text
	ctx_btn.visible = f != null and enabled
	if ctx_btn.visible:
		ctx_btn.hold_seconds = f.hold_seconds
		var short := text
		if short.length() > 17:
			short = _wrap(short, 16)    # two lines (the button shrinks anything still too wide)
		ctx_btn.set_label(short, "hold" if f.hold_seconds > 0.0 else "")
		ctx_btn.queue_redraw()
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
	var caps: Array = world.dispatcher.caps()
	var active := world.active_orders()
	var waiting: Array = []
	for c in world.customers:
		if c.state in ["wait_order", "wait_drink"]:
			waiting.append(c)
	if waiting.size() < 2:
		return      # one order is already in the Next line and over their head: keep the screen clear
	# longest-waiting first: that's who to serve next
	waiting.sort_custom(func(a, b): return a.patience_frac() < b.patience_frac())
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.glass_box(0.62, 14, Color(0, 0, 0, 0), 14, 8))
	card.custom_minimum_size = Vector2(250, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orders_box.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var full := active >= int(caps[1])
	vb.add_child(UITheme.hud_label("AT THE BAR  %d%s" % [waiting.size(), "  ·  FULL" if full else ""], 13, Color(1.0, 0.72, 0.4) if full else UITheme.GOLD, 800))
	var shown := 0
	for c in waiting:
		if shown >= 4:
			break
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var who := UITheme.hud_label(c.display_name.split(" ")[0], 18)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var helper := world.staff_serving(c)
		var what: String = GameData.drink(c.drink_id).get("short", "?") if c.order_taken else "to order"
		if helper != null:
			what += " · " + helper.display_name
		row.add_child(UITheme.hud_label(what, 16, UITheme.GOLD if c.order_taken else Color(1, 1, 1, 0.6)))
		# patience as a slim line under the name
		var track := ColorRect.new()
		track.custom_minimum_size = Vector2(222, 3)
		track.color = Color(1, 1, 1, 0.12)
		vb.add_child(track)
		var fill := ColorRect.new()
		fill.size = Vector2(222.0 * c.patience_frac(), 3)
		fill.color = UITheme.patience_color(c.patience_frac())
		track.add_child(fill)
		shown += 1

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
		if int(res.get("streak", 0)) >= 2:
			t += "[color=#f2c25c]Streak %d · tips +%d%%[/color]\n" % [int(res["streak"]), int(minf(int(res["streak"]), 10) * 3)]
	var notes: Array = res.get("notes", [])
	if not notes.is_empty():
		t += "[color=#d8c9a8]" + "\n".join(notes) + "[/color]"
	t += "[/center]"
	result_label.text = t
	result_card.visible = true
	_result_t = 4.5


# ------------------------------------------------------------------ messages
func toast(text: String, kind := "info") -> void:
	for ch in toast_box.get_children():
		if ch.has_meta("text") and ch.get_meta("text") == text:
			return       # already showing
	if kind == "info" and toast_box.get_child_count() >= 1:
		return       # routine news doesn't stack on top of something that matters
	var accents := {"good": Color(0.4, 0.85, 0.5), "bad": Color(0.95, 0.4, 0.3), "warn": Color(0.95, 0.7, 0.25), "info": Color(1, 1, 1, 0.0)}
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.glass_box(0.66, 12, accents.get(kind, accents["info"]), 14, 7))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.hud_label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(480, 0)
	p.add_child(l)
	p.set_meta("text", text)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 2:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)

func set_tip(text: String) -> void:
	if tip_label == null:
		return   # a tutorial step can fire while a reloaded HUD is still being built
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
	MusicDirector.context["menu_open"] = tab != "music"
	menu.open(tab)


func close_menu() -> void:
	MusicDirector.context["menu_open"] = false
	menu.visible = false
	touch.enabled = true
	get_tree().paused = false


func show_day_summary(s: Dictionary) -> void:
	touch.reset()
	touch.enabled = false
	get_tree().paused = true
	# the world stops while the accounts are up, so tell the music ourselves
	MusicDirector.context["screen"] = "summary"
	MusicDirector.context["phase"] = "closing"
	menu.show_summary(s)
