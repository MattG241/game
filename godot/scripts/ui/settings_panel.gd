class_name SettingsPanel
extends RefCounted
## Builds the settings UI (used from the main menu and the in-game pause menu).

static func build(on_edit_layout: Callable = Callable()) -> Control:
	var root := UIKit.vbox(14)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_section("GRAPHICS"))
	var presets := UIKit.hbox(10)
	for p in ["low", "medium", "high"]:
		var name: String = p
		var b := UIKit.button(name.to_upper(), func(): Settings.apply_preset(name), Vector2(150, 64))
		b.toggle_mode = true
		b.button_pressed = Settings.get_value("preset", "") == name
		presets.add_child(b)
	root.add_child(_row("Quality preset", presets))
	var fps := UIKit.hbox(10)
	for f in [30, 60]:
		var val: int = f
		var b := UIKit.button("%d FPS" % val, func(): Settings.set_value("fps", val), Vector2(150, 64))
		b.toggle_mode = true
		b.button_pressed = int(Settings.get_value("fps", 60)) == val
		fps.add_child(b)
	root.add_child(_row("Frame rate", fps))
	root.add_child(_slider("Render scale", "render_scale", 0.5, 1.0, 0.05))
	root.add_child(_slider("View distance", "view_distance", 110.0, 280.0, 10.0))
	root.add_child(_slider("Particle amount", "particles", 0.2, 1.0, 0.1))
	root.add_child(_toggle("Shadows", "shadows"))
	root.add_child(_toggle("Anti-aliasing (MSAA 2x)", "msaa", true))
	root.add_child(_toggle("Performance overlay", "perf_overlay"))
	root.add_child(_section("CONTROLS"))
	root.add_child(_slider("Look sensitivity", "sensitivity", 0.3, 2.5, 0.05))
	root.add_child(_toggle("Invert look Y", "invert_y"))
	root.add_child(_toggle("Aim assist for cleaning", "aim_assist"))
	root.add_child(_toggle("CLEAN button toggles (tap on / tap off)", "clean_toggle"))
	root.add_child(_slider("Control opacity", "controls_opacity", 0.25, 1.0, 0.05))
	root.add_child(_slider("Control size", "controls_scale", 0.75, 1.35, 0.05))
	if on_edit_layout.is_valid():
		var lay := UIKit.hbox(10)
		lay.add_child(UIKit.button("CUSTOMISE LAYOUT", on_edit_layout, Vector2(260, 64)))
		lay.add_child(UIKit.button("RESET LAYOUT", func(): Settings.set_value("layout", {}), Vector2(220, 64)))
		root.add_child(_row("Button layout", lay))
	root.add_child(_toggle("Vibration", "vibration"))
	root.add_child(_section("AUDIO"))
	root.add_child(_slider("Music volume", "music_volume", 0.0, 1.0, 0.05))
	root.add_child(_slider("Effects volume", "sfx_volume", 0.0, 1.0, 0.05))
	root.add_child(_section("TROUBLESHOOTING"))
	var status := UIKit.label("If the game closed unexpectedly, reopen it and tap this, then paste the text to the developer.", 18, UIKit.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	root.add_child(UIKit.button("COPY CRASH LOG", func():
		var n := copy_crash_log()
		status.text = "Copied %d lines to the clipboard." % n if n > 0 else "No log found yet.", Vector2(320, 64)))
	return root


## Copies the most useful log to the clipboard: the previous session's log (the one
## that ended in a crash) if there is one, otherwise the current session's.
static func copy_crash_log() -> int:
	var dir := "user://logs"
	var files := DirAccess.get_files_at(dir)
	var older := []
	for f in files:
		if f.ends_with(".log") and f != "godot.log":
			older.append(f)
	older.sort()
	var pick: String = dir + "/" + (older[older.size() - 1] if not older.is_empty() else "godot.log")
	if not FileAccess.file_exists(pick):
		return 0
	var text := FileAccess.get_file_as_string(pick)
	var lines := text.split("\n")
	# Keep the end of the log (where the crash is) within clipboard-friendly size.
	var start := maxi(lines.size() - 400, 0)
	var header := "Lunar Cleanup %s | %s | %s | %d cores\n%s\n" % [ProjectSettings.get_setting("application/config/version"),
		OS.get_model_name(), OS.get_name(), OS.get_processor_count(), pick.get_file()]
	DisplayServer.clipboard_set(header + "\n".join(lines.slice(start)))
	return lines.size() - start


static func _section(t: String) -> Control:
	var l := UIKit.label(t, 18, UIKit.ACCENT, true)
	return l


static func _row(text: String, ctrl: Control) -> Control:
	var h := UIKit.hbox(16)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	return h


static func _slider(text: String, key: String, lo: float, hi: float, step: float) -> Control:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key, lo))
	s.custom_minimum_size = Vector2(320, 48)
	var val := UIKit.label("%.2f" % s.value, 20, UIKit.MUTED)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v):
		val.text = "%.2f" % v if hi <= 3.0 else "%d" % int(v)
		Settings.set_value(key, v))
	if hi > 3.0:
		val.text = "%d" % int(s.value)
	var h := UIKit.hbox(10)
	h.add_child(s)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(val)
	return _row(text, h)


static func _toggle(text: String, key: String, as_int := false) -> Control:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key, false))
	c.custom_minimum_size = Vector2(90, 52)
	c.toggled.connect(func(on):
		Audio.play("ui_click")
		Settings.set_value(key, (1 if on else 0) if as_int else on))
	return _row(text, c)
