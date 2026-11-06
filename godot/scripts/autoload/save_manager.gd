extends Node
## Versioned save slots in user:// (Android app-private storage, kept across APK updates).
## Each slot: state.json (progress) + dirt.bin (compressed cleaning masks).
## Writes are atomic (tmp -> rename) with a .bak of the previous save for recovery.
## Heavy work (encoding/compressing/writing) happens on a worker thread.

signal saved(slot: int)

const SLOTS := 3
const ROOT := "user://saves"

var current_slot := 1
var _task := -1
var _mutex := Mutex.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [ROOT, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_dir(slot) + "/state.json") or FileAccess.file_exists(slot_dir(slot) + "/state.json.bak")


func has_any_save() -> bool:
	for s in range(1, SLOTS + 1):
		if has_save(s):
			return true
	return false


func latest_slot() -> int:
	var best := -1
	var best_t := -1
	for s in range(1, SLOTS + 1):
		var info := slot_info(s)
		if not info.is_empty() and not info.get("complete", false) and int(info.get("saved_at", 0)) > best_t:
			best_t = int(info.get("saved_at", 0))
			best = s
	return best


## Lightweight summary for the load screen.
func slot_info(slot: int) -> Dictionary:
	var d := _read_json(slot_dir(slot) + "/state.json")
	if d.is_empty():
		d = _read_json(slot_dir(slot) + "/state.json.bak")
	if d.is_empty():
		return {}
	var st: Dictionary = d.get("stats", {})
	return {"saved_at": int(d.get("saved_at", 0)), "credits": float(d.get("credits", 0)),
		"m2": float(st.get("m2_cleaned", 0)), "play_time": float(st.get("play_time", 0)),
		"missions": (d.get("missions_done", []) as Array).size(),
		"complete": bool((d.get("flags", {}) as Dictionary).get("went_home", false)),
		"earned": float(st.get("credits_earned", 0))}


## True when the game in a slot has been finished (flown home): it can't be continued.
func is_complete(slot: int) -> bool:
	return bool(slot_info(slot).get("complete", false))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func is_saving() -> bool:
	return _task != -1


func _process(_delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		saved.emit(current_slot)


## Save the running game. threaded=false is used when the app is being paused/closed.
func save_game(slot := -1, threaded := true) -> void:
	if slot < 0:
		slot = current_slot
	current_slot = slot
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	Diagnostics.event("save slot %d" % slot)
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("write_state"):
		world.write_state()
	var json := JSON.stringify(GameState.to_dict())
	var snap := GameState.dirt.snapshot()
	if threaded:
		_task = WorkerThreadPool.add_task(_write.bind(slot, json, snap), false, "save")
	else:
		_write(slot, json, snap)
		saved.emit(slot)


func _write(slot: int, json: String, snap: Array) -> void:
	_mutex.lock()
	var dir := slot_dir(slot)
	DirAccess.make_dir_recursive_absolute(dir)
	var dirt_bytes := DirtMap.encode_snapshot(snap)
	_atomic_write(dir + "/dirt.bin", dirt_bytes)
	_atomic_write(dir + "/state.json", json.to_utf8_buffer())
	_mutex.unlock()


func _atomic_write(path: String, bytes: PackedByteArray) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write " + tmp)
		return
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	DirAccess.rename_absolute(tmp, path)


## Loads a slot into GameState. Falls back to the backup if the main file is damaged.
func load_game(slot: int) -> bool:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	var dir := slot_dir(slot)
	for suffix in ["", ".bak"]:
		var d := _read_json(dir + "/state.json" + suffix)
		if d.is_empty():
			continue
		var dirt_ok := true
		var dirt_path: String = dir + "/dirt.bin" + suffix
		var dirt_bytes := PackedByteArray()
		if FileAccess.file_exists(dirt_path):
			dirt_bytes = FileAccess.get_file_as_bytes(dirt_path)
		GameState.from_dict(d)
		if not GameState.dirt.decode(dirt_bytes):
			dirt_ok = false
			# Try the other dirt file before giving up on cleaning progress.
			var alt: String = dir + "/dirt.bin" + (".bak" if suffix == "" else "")
			if FileAccess.file_exists(alt):
				dirt_ok = GameState.dirt.decode(FileAccess.get_file_as_bytes(alt))
			if not dirt_ok:
				GameState.dirt.clear()
				push_warning("Cleaning data was damaged; world dust was reset.")
		current_slot = slot
		if suffix != "":
			GameState.notify.emit("Save was damaged - restored from backup", "info")
		return true
	return false


func delete_slot(slot: int) -> void:
	var dir := slot_dir(slot)
	for f in ["state.json", "state.json.bak", "dirt.bin", "dirt.bin.bak"]:
		if FileAccess.file_exists(dir + "/" + f):
			DirAccess.remove_absolute(dir + "/" + f)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
