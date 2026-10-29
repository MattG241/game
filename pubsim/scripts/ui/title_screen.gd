class_name TitleScreen
extends Node
## Title screen over a slowly drifting view of the finished pub.

var main: Node
var _cam: Camera3D
var _t := 0.0
var _ui: Control
var _new_dialog: PanelContainer
var _name_edit: LineEdit
var _mode := "career"


func _ready() -> void:
	var scene := Node3D.new()
	add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.38, 0.28)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.1
	we.environment = env
	scene.add_child(we)
	var info := PubBuilder.new().build(scene)
	# show the fully renovated pub as a promise of what's to come
	for id in info["upgrade_show"].keys():
		for n in info["upgrade_show"][id]:
			n.visible = true
	for id in info["upgrade_hide"].keys():
		for n in info["upgrade_hide"][id]:
			n.visible = false
	for l in info["lamps"]:
		l.light_energy = 1.3
	for sl in info["street_lights"]:
		sl.visible = true
	_cam = Camera3D.new()
	_cam.fov = 62
	scene.add_child(_cam)
	_cam.current = true
	# a perfect pint on the bar for the hero shot
	var g := PintGlass.new()
	scene.add_child(g)
	g.global_position = Vector3(-0.2, PubLayout.BAR_TOP, -1.95)
	g.contents.drink_id = "stout"
	g.contents.serve = "stout"
	g.contents.body = 0.88
	g.contents.foam = 0.14
	_build_ui()
	Sfx.set_loop("rain", "rain_loop", 0.35)
	# Welcome to The Local plays on the title screen and fades when a game starts
	MusicDirector.clear_override()
	MusicDirector.set_screen("menu")


func _process(delta: float) -> void:
	_t += delta
	var a := sin(_t * 0.07) * 0.5
	var p := Vector3(-0.2 + sin(a) * 2.6, 1.55 + sin(_t * 0.13) * 0.08, 1.4 + cos(a) * 1.2)
	_cam.global_position = p
	_cam.look_at(Vector3(-0.6 + sin(_t * 0.05) * 0.6, 1.25, -2.2))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.theme()
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 560
	shade.color = Color(0.03, 0.02, 0.01, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(56, 48)
	vb.custom_minimum_size = Vector2(460, 0)
	vb.add_theme_constant_override("separation", 14)
	_ui.add_child(vb)
	var t1 := UITheme.label("The Irish Pub", 58, UITheme.GOLD, MeshKit.font_title())
	vb.add_child(t1)
	var t2 := UITheme.label("Simulator", 46, UITheme.CREAM, MeshKit.font_title())
	vb.add_child(t2)
	var t3 := UITheme.label("Pour the perfect pint. Build a legendary local.", 22, UITheme.MUTED)
	vb.add_child(t3)
	vb.add_child(Control.new())
	if GameState.has_save():
		var cb := UITheme.button("Continue", _continue, 30)
		cb.custom_minimum_size = Vector2(440, 76)
		vb.add_child(cb)
		var sum := UITheme.label(GameState.save_summary(), 20, UITheme.MUTED)
		vb.add_child(sum)
	var nb := UITheme.button("New career", func(): _ask_name("career"), 28)
	nb.custom_minimum_size = Vector2(440, 70)
	vb.add_child(nb)
	var sb := UITheme.button("Relaxed sandbox (€5,000, no rent)", func(): _ask_name("sandbox"), 22)
	sb.custom_minimum_size = Vector2(440, 64)
	vb.add_child(sb)
	var ver := UITheme.label("v%s · offline · no ads" % ProjectSettings.get_setting("application/config/version", "0.1"), 18, UITheme.MUTED)
	vb.add_child(ver)
	_new_dialog = PanelContainer.new()
	_new_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_new_dialog.offset_left = -320
	_new_dialog.offset_right = 320
	_new_dialog.offset_top = -150
	_new_dialog.offset_bottom = 150
	_new_dialog.visible = false
	_ui.add_child(_new_dialog)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 14)
	_new_dialog.add_child(dv)
	dv.add_child(UITheme.label("Name your pub", 32, UITheme.GOLD, MeshKit.font_title()))
	_name_edit = LineEdit.new()
	_name_edit.text = "The Crooked Shamrock"
	_name_edit.max_length = 28
	_name_edit.custom_minimum_size = Vector2(0, 64)
	_name_edit.add_theme_font_size_override("font_size", 26)
	dv.add_child(_name_edit)
	var warn := UITheme.label("", 18, Color(1, 0.7, 0.5))
	dv.add_child(warn)
	if GameState.has_save():
		warn.text = "Starting a new game replaces your current save."
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	dv.add_child(h)
	var go := UITheme.button("Open the doors", _start_new, 26)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(go)
	var cancel := UITheme.button("Back", func(): _new_dialog.visible = false, 24)
	h.add_child(cancel)


func _ask_name(mode: String) -> void:
	_mode = mode
	_new_dialog.visible = true


func _start_new() -> void:
	var n := _name_edit.text.strip_edges()
	if n.length() < 2:
		n = "The Crooked Shamrock"
	main.start_new(_mode, n)


func _continue() -> void:
	main.continue_game()
