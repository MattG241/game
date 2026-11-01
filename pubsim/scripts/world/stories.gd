class_name Stories
extends RefCounted
## The regulars' story arcs (data/stories.json). When a regular with a chapter waiting is in the
## pub, a gold "..." hangs over them; talking to them tells the chapter. Some chapters ask a
## favour (a perfect pint, a game of darts, an upgrade, a booked night, a session, clean lines),
## which is checked as you play and rewarded when done. One chapter per regular per day.

var world: Node


func _state(arc_id: String) -> Dictionary:
	var all: Dictionary = GameState.progress.get("stories", {})
	if not all.has(arc_id):
		all[arc_id] = {"ch": 0, "active": false, "day": 0, "base": 0}
	GameState.progress["stories"] = all
	return all[arc_id]


func _arc_for(regular_id: String) -> Dictionary:
	for a in GameData.stories:
		if str(a["regular"]) == regular_id:
			return a
	return {}


## The chapter this regular would tell now, or {}.
func chapter_ready(regular_id: String) -> Dictionary:
	var arc := _arc_for(regular_id)
	if arc.is_empty():
		return {}
	var st := _state(arc["id"])
	var chs: Array = arc["chapters"]
	if bool(st["active"]) or int(st["ch"]) >= chs.size() or GameState.day < int(st["day"]):
		return {}
	var ch: Dictionary = chs[int(st["ch"])]
	if int(GameState.relationships.get(regular_id, 0)) < int(ch.get("min_rel", 0)):
		return {}
	return ch


## Favours asked and not yet done: [{regular, name, text}].
func open_favours() -> Array:
	var out := []
	for a in GameData.stories:
		var st := _state(a["id"])
		if bool(st["active"]):
			var ch: Dictionary = a["chapters"][int(st["ch"])]
			out.append({"regular": a["regular"], "name": str(GameData.regulars_by_id[a["regular"]]["name"]).split(" ")[0], "text": ch.get("ask_text", "")})
	return out


## Talking to a regular with a chapter waiting.
func tell(c: Customer) -> void:
	var arc := _arc_for(c.regular_id)
	var ch := chapter_ready(c.regular_id)
	if ch.is_empty():
		return
	var st := _state(arc["id"])
	var body := str(ch["text"])
	if ch.has("ask"):
		st["active"] = true
		st["base"] = _baseline(str(ch["ask"]))
		body += "\n\nFavour: " + str(ch["ask_text"])
		world.hud.show_story(str(arc["title"]), body)
		check()          # an upgrade they ask for may already be in
	else:
		world.hud.show_story(str(arc["title"]), body + _reward(c.regular_id, ch.get("reward", {})))
		_advance(st)
	c.hide_bubble()
	GameState.stats["story_chapters"] = int(GameState.stats.get("story_chapters", 0)) + 1


func _baseline(ask: String) -> int:
	match ask:
		"darts":
			return int(GameState.stats.get("darts_games", 0))
		"session":
			return int(GameState.stats.get("sessions", 0))
		"lines":
			return int(GameState.progress.get("lines_cleaned_day", 0))
	return 0


func _advance(st: Dictionary) -> void:
	st["active"] = false
	st["ch"] = int(st["ch"]) + 1
	st["day"] = GameState.day + 1      # the next chapter comes another day


## A perfect pint for a regular (called by the world when one is served).
func note_pint(regular_id: String, score: int) -> void:
	var arc := _arc_for(regular_id)
	if arc.is_empty():
		return
	var st := _state(arc["id"])
	if bool(st["active"]) and str(arc["chapters"][int(st["ch"])].get("ask", "")) == "perfect_pint" and score >= 90:
		st["base"] = -1        # done
		check()


## Checks every favour in progress and rewards the ones that are done.
func check() -> void:
	for a in GameData.stories:
		var st := _state(a["id"])
		if not bool(st["active"]):
			continue
		var ch: Dictionary = a["chapters"][int(st["ch"])]
		var ask := str(ch.get("ask", ""))
		var done := false
		if ask.begins_with("upgrade:"):
			done = GameState.has_upgrade(ask.substr(8))
		else:
			match ask:
				"perfect_pint":
					done = int(st["base"]) == -1
				"darts", "session":
					done = _baseline(ask) > int(st["base"])
				"lines":
					done = GameState.line_penalty() <= 0.0 and int(GameState.progress.get("lines_cleaned_day", 0)) > int(st["base"])
				"book_event":
					for d in GameState.bookings.keys():
						if int(d) >= GameState.day:
							done = true
		if done:
			var name := str(GameData.regulars_by_id[a["regular"]]["name"]).split(" ")[0]
			world.notify("%s's favour done: %s%s" % [name, str(ch.get("ask_text", "")), _reward(a["regular"], ch.get("reward", {}))], "good")
			Sfx.play("coins", -4.0)
			_advance(st)


func _reward(regular_id: String, r: Dictionary) -> String:
	var parts := []
	if r.has("rel"):
		GameState.relationships[regular_id] = clampi(int(GameState.relationships.get(regular_id, 0)) + int(r["rel"]), -10, 100)
	if r.has("cash"):
		GameState.earn(float(r["cash"]), "prizes")
		parts.append("+€%d" % int(r["cash"]))
	if r.has("rep"):
		GameState.reputation = minf(100.0, GameState.reputation + float(r["rep"]))
		parts.append("reputation +%s" % str(r["rep"]))
	if r.has("upgrade") and not GameState.has_upgrade(str(r["upgrade"])):
		GameState.upgrades[str(r["upgrade"])] = 1
		GameState.upgrades_changed.emit()
		parts.append("%s added to the pub" % GameData.upgrade(str(r["upgrade"])).get("name", ""))
	return ("  (" + ", ".join(parts) + ")") if not parts.is_empty() else ""


## Gold dots over regulars who have something to tell you.
func refresh_markers() -> void:
	for c in world.customers:
		if c.regular_id == "" or c.state not in ["drinking", "stand_drink", "mingle"]:
			continue
		if not chapter_ready(c.regular_id).is_empty():
			c.show_bubble("...", Color(1.0, 0.8, 0.3))
