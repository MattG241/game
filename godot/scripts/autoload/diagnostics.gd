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

var previous_crashed := false
var _t := 0.0
var _last_event := "start"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(SESSION):
		var old := FileAccess.get_file_as_string(SESSION)
		var lines := old.strip_edges().split("\n")
		var last := lines[lines.size() - 1] if lines.size() > 0 else ""
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


## Record a notable moment (menu opened, vehicle entered...) in the next breadcrumb.
func event(what: String) -> void:
	_last_event = what


func _append(line: String) -> void:
	var f := FileAccess.open(SESSION, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()


func _process(delta: float) -> void:
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
	_append("%s | %s | fps %d | mem %d MB | vram %d MB | %s" % [Time.get_time_string_from_system(), where,
		Engine.get_frames_per_second(), int(OS.get_static_memory_usage() / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), _last_event])
	_last_event = ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_append("PAUSED " + Time.get_time_string_from_system())
		NOTIFICATION_APPLICATION_RESUMED:
			_append("RESUMED " + Time.get_time_string_from_system())
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			_append("END " + Time.get_time_string_from_system())


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
