extends Node3D
## Title screen with a live 3D lunar backdrop (Earth-rise over the tutorial crater).

var boot: Node
var _cam: Camera3D
var _t := 0.0
var _ui: Control
var _panel: VBoxContainer
var _sub: Control
var _terrain: Terrain
var _focus: Node3D


func _ready() -> void:
	TerrainGen.setup()
	GameState.active = false
	GameState.dirt.clear()
	add_child(LunarEnv.new())
	_focus = Node3D.new()
	_focus.position = Vector3(40, 0, -30)
	add_child(_focus)
	_terrain = Terrain.new()
	add_child(_terrain)
	_terrain.focus = _focus
	_terrain.prewarm(_focus.position)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.far = 2600
	add_child(_cam)
	_cam.current = true
	# A giant toothbrush planted in the regolith like a flag, plus a clean stripe.
	var tc := TerrainGen.landmark("tutorial_crater")
	var e := Vector3(LunarEnv.EARTH_DIR.x, 0, LunarEnv.EARTH_DIR.z).normalized()
	var side := Vector3(-e.z, 0, e.x)
	var p := Vector3(tc[1], 0, tc[2]) - e * 13.0 + side * 9.0
	p.y = TerrainGen.height(p.x, p.z)
	var brush := Node3D.new()
	brush.position = p
	brush.rotation = Vector3(0.18, 0.6, 0.12)
	add_child(brush)
	Meshes.part(brush, Meshes.cyl(0.18, 6.0, 12), Meshes.hs(Color(0.3, 0.76, 0.97), 0.1, 0.35), Vector3(0, 3.0, 0))
	Meshes.part(brush, Meshes.box(Vector3(0.6, 1.6, 0.4)), Meshes.hs(Color(0.3, 0.76, 0.97), 0.1, 0.35), Vector3(0, 6.6, 0.1))
	Meshes.part(brush, Meshes.box(Vector3(0.5, 1.4, 0.5)), Meshes.hs(Color(0.97, 0.97, 0.95), 0.0, 0.8, Color(0, 0, 0), 0.0, 8.0, 0.1), Vector3(0, 6.6, 0.5))
	var astro := Meshes.astronaut(Color(1.0, 0.5, 0.1))
	astro.position = p + Vector3(1.6, 0, 0.8)
	astro.position.y = TerrainGen.height(astro.position.x, astro.position.z)
	astro.rotation.y = 2.2
	add_child(astro)
	for i in 60:
		var a := float(i) / 60.0
		var q := p.lerp(Vector3(tc[1], 0, tc[2]) - e * 26.0 + side * 2.0, a) + side * sin(a * 9.0) * 1.2
		GameState.dirt.stamp(DirtMap.Shape.ROUND, q.x, q.z, 0.9, 0.0, 0.0, 1.0, 1e9)
	_terrain.refresh_all_textures()
	_build_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UIKit.theme()
	layer.add_child(_ui)
	UIKit.fill_viewport(_ui)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.015, 0.03, 0.85))
	g.set_color(1, Color(0.01, 0.015, 0.03, 0.0))
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size = Vector2(760, 0)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.size = Vector2(760, 2000)
	_ui.add_child(grad)
	var ins := UIKit.safe_insets(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x) + 60)
	margin.add_theme_constant_override("margin_top", int(ins.y) + 40)
	margin.add_theme_constant_override("margin_bottom", int(ins.w) + 30)
	margin.add_theme_constant_override("margin_right", int(ins.z) + 40)
	_ui.add_child(margin)
	var row := UIKit.hbox(40)
	margin.add_child(row)
	_panel = UIKit.vbox(10)
	_panel.custom_minimum_size = Vector2(440, 0)
	row.add_child(_panel)
	_sub = Control.new()
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_sub)
	_show_main()


func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


func _show_main() -> void:
	_clear(_panel)
	_clear(_sub)
	var th := UIKit.hbox(18)
	th.add_child(UIKit.title("LUNAR", 92, UIKit.ACCENT))
	th.add_child(UIKit.title("CLEANUP", 92, UIKit.TEXT))
	_panel.add_child(th)
	var sub := UIKit.label("One toothbrush. One Moon. Zero budget.", 22, UIKit.MUTED)
	_panel.add_child(sub)
	_panel.add_child(UIKit.spacer(false))
	var latest := SaveManager.latest_slot()
	if latest > 0:
		_panel.add_child(UIKit.accent_button("CONTINUE", func(): boot.start_game(latest), Vector2(420, 64), 26))
		_panel.add_child(UIKit.button("NEW GAME", _show_new, Vector2(420, 58), 24))
	else:
		_panel.add_child(UIKit.accent_button("NEW GAME", func(): boot.start_game(-1), Vector2(420, 64), 26))
	_panel.add_child(UIKit.button("LOAD GAME", _show_load, Vector2(420, 58), 24))
	_panel.add_child(UIKit.button("SETTINGS", _show_settings, Vector2(420, 58), 24))
	_panel.add_child(UIKit.button("CREDITS", _show_credits, Vector2(420, 58), 24))
	_panel.add_child(UIKit.button("EXIT", func(): get_tree().quit(), Vector2(420, 58), 24))
	if Diagnostics.previous_crashed:
		var warn := UIKit.label("The game closed unexpectedly last time. Settings > Copy crash log, then paste it to the developer.", 17, UIKit.ACCENT)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(warn)
	_panel.add_child(UIKit.label("v%s   offline - no ads - no purchases" % ProjectSettings.get_setting("application/config/version"), 16, UIKit.MUTED))


func _close_side() -> void:
	Audio.play("ui_back")
	_clear(_sub)
	_panel.visible = true


## Side panels take the whole screen width (the title column hides) so long
## pages such as Settings never run off the right edge on phones.
func _side_panel(title: String) -> VBoxContainer:
	_clear(_sub)
	_panel.visible = false
	var p := UIKit.panel(UIKit.BG, UIKit.LINE, 20, 20)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub.add_child(p)
	var v := UIKit.vbox(12)
	p.add_child(v)
	var h := UIKit.hbox(12)
	v.add_child(h)
	h.add_child(UIKit.title(title, 44))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.button("BACK", _close_side, Vector2(150, 62)))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var inner := UIKit.vbox(12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	return inner


func _slot_text(slot: int) -> String:
	var info := SaveManager.slot_info(slot)
	if info.is_empty():
		return "SLOT %d  -  empty" % slot
	var when := Time.get_datetime_string_from_unix_time(int(info["saved_at"]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
	return "SLOT %d  -  %s CR  -  %s m2 cleaned  -  %d missions\n%s  -  played %d min" % [slot, GameState.fmt_short(info["credits"]), GameState.fmt_short(info["m2"]), info["missions"], when, int(info["play_time"] / 60.0)]


func _show_new() -> void:
	var v := _side_panel("NEW GAME")
	v.add_child(UIKit.label("Choose a save slot. Starting over in a used slot replaces it.", 20, UIKit.MUTED))
	for s in range(1, SaveManager.SLOTS + 1):
		var slot := s
		var b := UIKit.button(_slot_text(slot), func(): _confirm_new(slot), Vector2(0, 90), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)


func _confirm_new(slot: int) -> void:
	if not SaveManager.has_save(slot):
		boot.start_game(-slot)
		return
	var v := _side_panel("OVERWRITE?")
	v.add_child(UIKit.label("Slot %d already has a save. Start a new game there anyway?" % slot, 22))
	v.add_child(UIKit.accent_button("YES, START FRESH", func():
		SaveManager.delete_slot(slot)
		boot.start_game(-slot), Vector2(360, 72)))
	v.add_child(UIKit.button("NO", _show_new, Vector2(360, 72)))


func _show_load() -> void:
	var v := _side_panel("LOAD GAME")
	var any := false
	for s in range(1, SaveManager.SLOTS + 1):
		var slot := s
		var has := SaveManager.has_save(slot)
		any = any or has
		var b := UIKit.button(_slot_text(slot), func(): boot.start_game(slot), Vector2(0, 90), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not has
		v.add_child(b)
	if not any:
		v.add_child(UIKit.label("No saves yet - start a New Game.", 20, UIKit.MUTED))


func _show_settings() -> void:
	var v := _side_panel("SETTINGS")
	v.add_child(SettingsPanel.build())


func _show_credits() -> void:
	var v := _side_panel("CREDITS")
	var text := """LUNAR CLEANUP
Design, code, models, sound and music: generated for this project (original work).

Built with Godot Engine 4.3 (MIT licence) - godotengine.org
Fonts: Exo 2 and Rajdhani - SIL Open Font License 1.1 (see assets/fonts)
All 3D models are procedural meshes built in GDScript.
All sound effects and music are synthesised by tools/gen_audio.py.

No ads. No microtransactions. No internet required.
Thank you for cleaning the Moon."""
	var l := UIKit.label(text, 21)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)


func _process(delta: float) -> void:
	_t += delta
	var tc := TerrainGen.landmark("tutorial_crater")
	var center := Vector3(tc[1], 0, tc[2])
	# Slow dolly toward the crater with the Earth hanging above the horizon.
	var e := Vector3(LunarEnv.EARTH_DIR.x, 0, LunarEnv.EARTH_DIR.z).normalized()
	var side := Vector3(-e.z, 0, e.x)
	var pos := center - e * (30.0 - sin(_t * 0.07) * 6.0) + side * (8.0 + sin(_t * 0.05) * 10.0)
	pos.y = TerrainGen.height(pos.x, pos.z) + 3.2
	_cam.global_position = pos
	_cam.look_at(pos + e * 40.0 + Vector3(0, 9.5, 0), Vector3.UP)
	_focus.global_position = pos
