class_name Cosmetics
extends RefCounted
## Customisation: suit colours, tool skins and vehicle paint. Unlocks are kept with the
## player's settings (not a save slot), so they carry over to every game. Most are
## unlocked by watching one rewarded ad (all of those are free with Remove Ads); a few
## are achievement rewards.

const CATS := ["suit", "tool", "vehicle"]
const DEFAULTS := {"suit": "suit_classic", "tool": "tool_factory", "vehicle": "veh_factory"}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/cosmetics.json", FileAccess.READ)
		if f:
			_data = JSON.parse_string(f.get_as_text())
	return _data


static func items(cat: String) -> Array:
	return data().get(cat, [])


static func item(id: String) -> Dictionary:
	for cat in CATS:
		for it in items(cat):
			if it["id"] == id:
				return it
	return {}


static func _store() -> Dictionary:
	var s = Settings.get_value("cosmetics", {})
	return s if s is Dictionary else {}


static func is_unlocked(id: String) -> bool:
	var it := item(id)
	if it.is_empty():
		return false
	var how: String = it.get("unlock", "ad")
	if how == "free":
		return true
	if how == "ad":
		return IAP.ads_removed or (_store().get("unlocked", []) as Array).has(id)
	return GameState.achievements_done.has(how) or (_store().get("unlocked", []) as Array).has(id)


## How to get it, for the menu ("" if already yours).
static func lock_text(id: String) -> String:
	if is_unlocked(id):
		return ""
	var how: String = item(id).get("unlock", "ad")
	if how == "ad":
		return "Watch one ad to unlock"
	for a in GameData.achievements:
		if a["id"] == how:
			return "Achievement: %s - %s" % [a["title"], a["desc"]]
	return "Locked"


static func unlock(id: String) -> void:
	var s := _store()
	var list: Array = s.get("unlocked", [])
	if not list.has(id):
		list.append(id)
	s["unlocked"] = list
	Settings.set_value("cosmetics", s)


## Watch a rewarded ad, then unlock and wear it. on_done(true) once unlocked.
static func unlock_with_ad(id: String, on_done: Callable) -> void:
	if is_unlocked(id):
		on_done.call(true)
		return
	var shown := Ads.show_rewarded(func():
		unlock(id)
		equip(id)
		GameState.notify.emit("Unlocked: %s" % item(id).get("name", id), "purchase")
		on_done.call(true))
	if not shown:
		on_done.call(false)


static func equip(id: String) -> void:
	if not is_unlocked(id):
		return
	var s := _store()
	var eq: Dictionary = s.get("equipped", {})
	for cat in CATS:
		for it in items(cat):
			if it["id"] == id:
				eq[cat] = id
	s["equipped"] = eq
	Settings.set_value("cosmetics", s)


static func equipped_id(cat: String) -> String:
	var id: String = (_store().get("equipped", {}) as Dictionary).get(cat, DEFAULTS[cat])
	return id if is_unlocked(id) else DEFAULTS[cat]


static func equipped(cat: String) -> Dictionary:
	return item(equipped_id(cat))


static func count_unlocked() -> int:
	var n := 0
	for cat in CATS:
		for it in items(cat):
			if is_unlocked(it["id"]):
				n += 1
	return n


## Material for a tool or vehicle skin (null = keep the factory look).
static func skin_material(it: Dictionary) -> Material:
	if it.get("rainbow", false):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/rainbow.gdshader")
		return m
	if not it.has("color"):
		return null
	var c := Color.html(it["color"])
	var e := float(it.get("emit", 0.0))
	return Meshes.hs(c, float(it.get("metallic", 0.3)), float(it.get("rough", 0.4)), c if e > 0.0 else Color(0, 0, 0), e, 3.0, 0.05)


## Repaints a freshly built tool: its handle and every part in the tool's own colour.
static func skin_tool(head: Node3D, shaft: MeshInstance3D, tool_color: Color) -> void:
	var m := skin_material(equipped("tool"))
	if m == null:
		return
	shaft.material_override = m
	for mi in head.find_children("*", "MeshInstance3D", true, false):
		var cur = (mi as MeshInstance3D).material_override
		if cur is ShaderMaterial and (cur as ShaderMaterial).get_shader_parameter("paint") is Color:
			var p: Color = (cur as ShaderMaterial).get_shader_parameter("paint")
			if absf(p.r - tool_color.r) + absf(p.g - tool_color.g) + absf(p.b - tool_color.b) < 0.05:
				(mi as MeshInstance3D).material_override = m
