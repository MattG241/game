extends Node
## Player preferences. Stored separately from save slots so they survive new games.

signal changed

const PATH := "user://settings.cfg"

const PRESETS := {
	"low": {"render_scale": 0.6, "shadows": false, "view_distance": 140.0, "particles": 0.4, "msaa": 0, "detail": 0},
	"medium": {"render_scale": 0.8, "shadows": true, "view_distance": 190.0, "particles": 0.7, "msaa": 0, "detail": 1},
	"high": {"render_scale": 1.0, "shadows": true, "view_distance": 250.0, "particles": 1.0, "msaa": 1, "detail": 2},
}

var values := {
	"preset": "medium",
	"fps": 60,
	"render_scale": 0.8,
	"shadows": true,
	"view_distance": 190.0,
	"particles": 0.7,
	"msaa": 0,
	"detail": 1,
	"sensitivity": 1.0,
	"invert_y": false,
	"aim_assist": true,
	"clean_toggle": false,
	"controls_opacity": 0.85,
	"controls_scale": 1.0,
	"layout": {},
	"vibration": true,
	"music_volume": 0.6,
	"sfx_volume": 0.9,
	"perf_overlay": false,
}


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String, default = null):
	return values.get(key, default)


func set_value(key: String, value, save := true) -> void:
	values[key] = value
	apply()
	if save:
		save_settings()
	changed.emit()


func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	values["preset"] = name
	for k in PRESETS[name]:
		values[k] = PRESETS[name][k]
	apply()
	save_settings()
	changed.emit()


func apply() -> void:
	Engine.max_fps = int(values["fps"])
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(values["render_scale"]), 0.4, 1.0)
		vp.msaa_3d = Viewport.MSAA_2X if int(values["msaa"]) > 0 else Viewport.MSAA_DISABLED
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(float(values["music_volume"]), 0.0001)))
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(float(values["sfx_volume"]), 0.0001)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_detect_defaults()
		return
	for k in values.keys():
		if cfg.has_section_key("settings", k):
			values[k] = cfg.get_value("settings", k)


func _detect_defaults() -> void:
	# First launch: high-end phones (e.g. Galaxy S25 Ultra) get the high preset.
	var cores := OS.get_processor_count()
	if OS.has_feature("mobile") and cores < 8:
		apply_preset("low")
	elif cores >= 8:
		apply_preset("high")
	else:
		apply_preset("medium")


func vibrate(ms: int = 15, amplitude: float = 0.4) -> void:
	if not values["vibration"]:
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)
