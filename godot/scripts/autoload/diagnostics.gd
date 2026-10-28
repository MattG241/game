extends Node
## Crash breadcrumbs. Native crashes on Android never reach Godot's log file, so every
## few seconds a one-line status is appended (and flushed) to user://logs/session.txt.
## A clean exit writes END and going to the background writes PAUSED. If the previous
## session's last line is neither, it crashed: its breadcrumbs are kept for the
## "Copy crash log" button and the main menu mentions it.

const DIR := "user://logs"
const SESSION := DIR + "/session.txt"
const LAST_CRASH := DIR + "/last_crash_session.txt"
const INTERVAL := 4.0
const PREVIOUS := DIR + "/previous_session.txt"
const FREEZE_MS := 3000

var previous_crashed := false
var _t := 0.0
var _last_event := "start"
# Freeze watchdog: a background thread notices when the main thread stops ticking.
var _heartbeat_ms := 0
var _watchdog: Thread
var _stop := false
var _frozen := false
var _backgrounded := false
var _crumb_mutex := Mutex.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(SESSION):
		var old := FileAccess.get_file_as_string(SESSION)
		var lines := old.strip_edges().split("\n")
		var last := lines[lines.size() - 1] if lines.size() > 0 else ""
		var pf := FileAccess.open(PREVIOUS, FileAccess.WRITE)
		if pf:
			pf.store_string(old)
			pf.close()
		if not last.begins_with("END") and not last.begins_with("PAUSED") and lines.size() > 1:
			previous_crashed = true
			var f := FileAccess.open(LAST_CRASH, FileAccess.WRITE)
			if f:
				f.store_string(old)
				f.close()
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f:
		f.store_line("SESSION %s | %s | %s | %d cores | %s" % [ProjectSettings.get_setting("application/config/version"),
			OS.get_model_name(), OS.get_name(), OS.get_processor_count(), Time.get_datetime_string_from_system()])
		f.close()
	_heartbeat_ms = Time.get_ticks_msec()
	_watchdog = Thread.new()
	_watchdog.start(_watch)


func _watch() -> void:
	while not _stop:
		OS.delay_msec(500)
		var stalled := Time.get_ticks_msec() - _heartbeat_ms
		if _backgrounded:
			continue
		if stalled > FREEZE_MS and not _frozen:
			_frozen = true
			_append("FREEZE main thread stalled %d ms (last event: %s)" % [stalled, _last_event])
		elif stalled < FREEZE_MS and _frozen:
			_frozen = false
			_append("UNFROZE after stall")


## Record a notable moment (menu opened, vehicle entered...) in the next breadcrumb.
func event(what: String) -> void:
	_last_event = what


## Writes a line immediately (for steps right before a possible native crash).
func mark(what: String) -> void:
	_last_event = what
	_append("%s | %s" % [Time.get_time_string_from_system(), what])


func _append(line: String) -> void:
	_crumb_mutex.lock()
	var f := FileAccess.open(SESSION, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()
	_crumb_mutex.unlock()


func _process(delta: float) -> void:
	_heartbeat_ms = Time.get_ticks_msec()
	if delta > 1.0 and not _backgrounded:
		_append("HITCH frame took %d ms" % int(delta * 1000.0))
	_t += delta
	if _t < INTERVAL:
		return
	_t = 0.0
	var where := "menu"
	var world := get_tree().get_first_node_in_group("world")
	if world:
		var p: Vector3 = world.focus_node().global_position
		var reg := TerrainGen.region_at(p.x, p.z)
		where = "%s (%d,%d,%d) r%d %s" % ["vehicle" if world.current_vehicle else "foot", p.x, p.y, p.z, reg, world.mode]
		where += " chunks %d dirt %d" % [world.terrain.active_chunks(), GameState.dirt.chunks.size()]
		if world.current_vehicle:
			where += " speed %.1f up %.2f" % [world.current_vehicle.linear_velocity.length(), world.current_vehicle.global_basis.y.y]
	_append("%s | %s | fps %d | mem %d MB | vram %d MB | %s" % [Time.get_time_string_from_system(), where,
		Engine.get_frames_per_second(), int(OS.get_static_memory_usage() / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), _last_event])
	_last_event = ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_backgrounded = true
			_append("PAUSED " + Time.get_time_string_from_system())
		NOTIFICATION_APPLICATION_RESUMED:
			_heartbeat_ms = Time.get_ticks_msec()
			_backgrounded = false
			_append("RESUMED " + Time.get_time_string_from_system())
		NOTIFICATION_WM_CLOSE_REQUEST:
			_append("END " + Time.get_time_string_from_system())
		NOTIFICATION_EXIT_TREE:
			_append("END " + Time.get_time_string_from_system())
			_stop = true
			if _watchdog and _watchdog.is_started():
				_watchdog.wait_to_finish()


## Text for the clipboard: crashed session breadcrumbs (if any), then the log tails.
func report() -> String:
	var out := "Lunar Cleanup %s | %s | %s | %d cores\n" % [ProjectSettings.get_setting("application/config/version"),
		OS.get_model_name(), OS.get_name(), OS.get_processor_count()]
	if FileAccess.file_exists(LAST_CRASH):
		var crumbs := FileAccess.get_file_as_string(LAST_CRASH).strip_edges().split("\n")
		out += "\n== LAST CRASHED SESSION (last 60 breadcrumbs) ==\n"
		out += "\n".join(crumbs.slice(maxi(crumbs.size() - 60, 0))) + "\n"
	else:
		out += "\n(no crashed session recorded)\n"
	# Always include how the previous session ended (freezes show up here even when
	# Android later closed the app from the background).
	if FileAccess.file_exists(PREVIOUS):
		var prev := FileAccess.get_file_as_string(PREVIOUS).strip_edges().split("\n")
		var notable := []
		for l in prev:
			if l.begins_with("FREEZE") or l.begins_with("HITCH") or l.begins_with("UNFROZE") or l.contains("recover") or l.contains("reset"):
				notable.append(l)
		out += "\n== PREVIOUS SESSION: %d notable events, last 40 lines ==\n" % notable.size()
		out += "\n".join(notable.slice(maxi(notable.size() - 15, 0))) + ("\n...\n" if not notable.is_empty() else "")
		out += "\n".join(prev.slice(maxi(prev.size() - 40, 0))) + "\n"
	# Errors from all kept logs, newest first, plus the tail of the newest older log.
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(n): return n.ends_with(".log"))
	files.sort()
	files.reverse()
	for name in files:
		var lines := FileAccess.get_file_as_string(DIR + "/" + name).split("\n")
		var errs := []
		for i in lines.size():
			var l: String = lines[i]
			if l.contains("ERROR") or l.contains("SCRIPT") or l.contains("crash") or l.contains("signal"):
				errs.append(l + (" | " + lines[i + 1].strip_edges() if i + 1 < lines.size() else ""))
		out += "\n== %s (%d lines, %d errors) ==\n" % [name, lines.size(), errs.size()]
		out += "\n".join(errs.slice(maxi(errs.size() - 25, 0))) + "\n"
	return out
