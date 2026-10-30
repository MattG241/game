class_name World
extends Node3D
## Runs a day in the pub: time, customers, glasses, serving, upgrades, lighting and ambience.

signal served(result: Dictionary)
signal order_taken(c: Customer)

const MAX_DIRTY_CARRY := 6

var main: Node
var info: Dictionary
var player: Player
var hud: Node
var pour: Node
var drink_scene: DrinkScene
var darts: DartsGame
var live: LiveMusic
var voices: VoiceDirector
var match_day: MatchDay
var stories := Stories.new()
var session: SessionGame
var _cam_tween: Tween
var _vignette: CanvasLayer
var _chatter_t := 20.0
var dispatcher := OrderDispatcher.new()
var _spawn_gap := 0.0
var max_active_seen := 0
var run_time := 0.0          # seconds of play in this session (game time)
var _award_t := 2.0
var _celebration_pending: Array = []
var env: Environment
var close_cam: Camera3D
var nav_region: NavigationRegion3D

var customers: Array[Customer] = []
var staff_npcs: Array[StaffMember] = []
var bar_spots: Array = []         # Customer or null
var queue_slots: Array = []
var seats_taken: Dictionary = {}  # seat index -> Customer
var settle_slots: Array = []      # PintGlass or null
var loose_glasses: Array[PintGlass] = []  # glasses out in the room (dirty on tables etc.)
var rack_clean := 0
var spills: Array[Node3D] = []
var fast_forward := false
var tutorial_step := 0
var _spawn_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _regulars_today: Dictionary = {}
var _rack_visuals: Array[Node3D] = []
var _autosave_t := 0.0
var _first_customer_timer := -1.0
var _day_summary_pending := false
var _door_anim := 0.0
var _church_rung := -1
var _fire_audio: AudioStreamPlayer3D
var _nav_ready := false
var streak := 0                   # good pints in a row from the player (tips grow with it)
var _restoring := false
var guide_marker: MeshInstance3D  # floats over whatever to do next
var _guide_t := 0.0
var _guide: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_setup_env()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.28
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nav_region.navigation_mesh = nm
	var builder := PubBuilder.new()
	info = builder.build(nav_region)
	nav_region.bake_navigation_mesh(false)
	close_cam = Camera3D.new()
	close_cam.fov = 50.0
	close_cam.near = 0.02
	add_child(close_cam)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = PubLayout.PLAYER_START
	player.rotation.y = PI
	bar_spots.resize(PubLayout.BAR_SPOT_X.size())
	queue_slots.resize(PubLayout.QUEUE_POS.size())
	settle_slots.resize(PubLayout.SETTLE_SLOTS.size())
	rack_clean = GameState.glasses_total() - int(GameState.tutorial.get("dirty_overnight", 0))
	rack_clean = clampi(rack_clean, 0, GameState.glasses_total())
	_restoring = true      # last night's glasses shouldn't skip the tutorial ahead
	_restore_overnight_dirty()
	_restoring = false
	_make_interactables()
	_build_guide_marker()
	apply_upgrades()
	_refresh_rack()
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	_fire_audio = AudioStreamPlayer3D.new()
	_fire_audio.stream = Sfx.get_stream("fire_loop")
	_fire_audio.bus = "Ambience"
	_fire_audio.unit_size = 3.0
	_fire_audio.position = PubLayout.FIREPLACE + Vector3(0.5, 0.5, 0)
	add_child(_fire_audio)
	_update_lighting(true)
	voices = VoiceDirector.new()
	voices.name = "Voices"
	voices.world = self
	add_child(voices)
	live = LiveMusic.new()
	live.name = "LiveMusic"
	live.world = self
	add_child(live)
	stories.world = self
	session = SessionGame.new()
	session.name = "Session"
	session.world = self
	add_child(session)
	match_day = MatchDay.new()
	match_day.name = "MatchDay"
	match_day.world = self
	add_child(match_day)
	GameState.upgrade_bought.connect(_on_upgrade_bought)
	GameState.award_earned.connect(func(_id): voices.speak(null, "landlord", "milestone", true))
	GameState.goal_done.connect(_on_goal_done)
	MusicDirector.set_screen("world")
	MusicDirector.context["milestone"] = false
	await get_tree().physics_frame
	_nav_ready = true
	GameState.staff_changed.connect(refresh_staff)
	refresh_staff(true)


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.45, 0.36)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.22, 0.26)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	# brass, chrome, glass and polished wood reflect the pub itself: a panorama rendered from
	# inside the room (tools/bake) is used as the sky for reflections only
	var pano: Texture2D = load("res://assets/env/pub_reflection.png")
	if pano:
		var sky := Sky.new()
		var sm := PanoramaSkyMaterial.new()
		sm.panorama = pano
		sm.energy_multiplier = 1.6
		sky.sky_material = sm
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		env.sky = sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	we.environment = env
	add_child(we)
	_add_vignette()
	apply_graphics()


## A gentle darkening towards the screen edges, like a warm, dim room seen through the eye.
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	layer.name = "Vignette"
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.02, 0.01, 0.0, 0.5))
	g.add_point(0.55, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	add_child(layer)
	_vignette = layer


## Graphics presets. All run on the Compatibility (OpenGL ES 3) renderer used on Android.
##  Performance: 75% render scale, no shadows, glow or fog, light rain, fewer people.
##  Balanced:    full resolution, glow and fog, no real-time shadows.
##  High:        + shadowed key light over the taps, 2x MSAA, more rain and people.
##  Ultra:       + flickering shadows from the fire, 4x MSAA, the most people.
func apply_graphics() -> void:
	var preset := GameState.graphics_preset()
	var tier: int = GameState.GRAPHICS_PRESETS.find(preset)
	var scale := float(GameState.settings.get("render_scale", 1.0))
	if preset == "performance":
		scale = minf(scale, 0.75)
	get_viewport().scaling_3d_scale = clampf(scale, 0.5, 1.0)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][tier]
	if env:
		env.glow_enabled = tier >= 1 and not GameState.settings.get("reduced_effects", false)
		env.fog_enabled = tier >= 1
	Engine.max_fps = int(GameState.settings.get("fps_limit", 60))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if info.has("key_light") and info["key_light"]:
		(info["key_light"] as SpotLight3D).shadow_enabled = tier >= 2
	# point-light shadows re-render the scene six times each, so on Ultra only the fire casts them
	for l in info.get("lamps", []):
		(l as Light3D).shadow_enabled = false
	var fl: OmniLight3D = info.get("fire_light")
	if fl:
		fl.shadow_enabled = tier >= 3
	if _vignette:
		_vignette.visible = tier >= 1 and not GameState.settings.get("reduced_effects", false)
	for r in info.get("rain", []):
		(r as CPUParticles3D).amount = [120, 300, 500, 700][tier]
	# drifting dust in the lamplight from High up; the faint light cones from Balanced up
	for d in info.get("dust", []):
		(d as CPUParticles3D).visible = tier >= 2
	for cn in info.get("light_cones", []):
		(cn as Node3D).visible = tier >= 1


# ------------------------------------------------------------------ interactables
func _make_interactables() -> void:
	var I := Interactable
	var rack := I.make(self, PubLayout.RACK_POS + Vector3(0, 0.1, 0), "rack", _rack_prompt, _rack_action)
	rack.alt_prompt_fn = _tumbler_prompt
	rack.alt_action_fn = func(): _rack_action("tumbler")
	for id in info["taps"].keys():
		var t: Dictionary = info["taps"][id]
		var tap_id: String = id
		I.make(self, t["glass"] + Vector3(0, 0.25, 0), "tap_" + id, func(): return _tap_prompt(tap_id), func(): _tap_action(tap_id))
	for i in PubLayout.SETTLE_SLOTS.size():
		var idx := i
		I.make(self, PubLayout.SETTLE_SLOTS[i] + Vector3(0, 0.08, 0), "settle", func(): return _settle_prompt(idx), func(): _settle_action(idx), 0.0, 1.5)
	var sink := I.make(self, PubLayout.SINK_POS + Vector3(0, 0.1, 0), "sink", _sink_prompt, _sink_action)
	var sign := I.make(self, PubLayout.DOOR_SIGN_POS, "door_sign", _sign_prompt, _sign_action, 0.0, 2.2)
	sign.alt_prompt_fn = _lockin_prompt
	sign.alt_action_fn = _lockin
	I.make(self, PubLayout.TILL_POS + Vector3(0, 0.15, 0), "till", func(): return "Check the till & ledger", func(): hud.open_menu("ledger"))
	for id in PubLayout.KEG_POS.keys():
		var kid: String = id
		I.make(self, PubLayout.KEG_POS[id] + Vector3(0, 0.6, 0), "keg_" + id, func(): return _keg_prompt(kid), func(): _keg_action(kid), 1.2)
	I.make(self, PubLayout.STOCK_PILE + Vector3(0, 0.6, 0), "stock", func(): return "Order stock (phone)", func(): hud.open_menu("stock"))
	I.make(self, LINE_CLEAN_POS, "lines", _lines_prompt, _lines_action, 2.5)
	I.make(self, Vector3(PubLayout.OCHE_X + 0.4, 1.3, PubLayout.DARTBOARD.z), "darts", _darts_prompt, func(): start_darts(), 0.0, 2.4)
	I.make(self, DrinkScene.SPLIT_POS + Vector3(0, 0.2, 0.25), "split", _split_prompt, func(): start_split(), 0.0, 1.8)
	I.make(self, Vector3(-6.0, 0.9, 0.9), "fireside", _fireside_prompt, func(): start_relax(), 0.0, 2.0)
	I.make(self, PubLayout.JUKEBOX_POS + Vector3(0.3, 1.0, 0), "jukebox", func(): return "Choose the music (jukebox)" if player.has_hands_free() else "", func(): hud.open_menu("music"), 0.0, 2.2)
	I.make(self, PubLayout.STAGE_POS + Vector3(-1.4, 1.2, 0), "championship", _champ_prompt, func(): start_split(true), 0.0, 2.4)
	for spot in [PubLayout.STAGE_POS + Vector3(-1.2, 1.0, -0.8), LiveMusic.FIRESIDE_SPOT + Vector3(1.0, 1.0, 0.6)]:
		I.make(self, spot, "session", _session_prompt, func(): session.begin(), 0.0, 2.6)


func _hint(text: String) -> String:
	return "~" + text


func _rack_prompt() -> String:
	if player.held != null:
		if player.held.contents.is_empty() and player.held.dirt < 0.1:
			return "Put the glass back"
		return ""
	if not player.dirty_stack.is_empty():
		return _hint("Wash the dirty glasses at the sink first")
	if rack_clean <= 0:
		return _hint("No clean glasses! Collect and wash some")
	return "Take a clean pint glass (%d)" % rack_clean


## Whiskey and lemonade go in a tumbler (the second button at the rack, once either is sold).
func _tumbler_prompt() -> String:
	if player.held != null or not player.dirty_stack.is_empty() or rack_clean <= 0:
		return ""
	if GameState.drink_available("whiskey") or GameState.drink_available("soft"):
		return "Take a tumbler"
	return ""


func _rack_action(kind := "pint") -> void:
	if player.held != null:
		if player.held.contents.is_empty() and player.held.dirt < 0.1:
			var g := player.release_glass()
			g.queue_free()
			rack_clean += 1
			_refresh_rack()
		return
	if not player.dirty_stack.is_empty() or rack_clean <= 0:
		return
	rack_clean -= 1
	var g := PintGlass.new(kind)
	player.take_glass(g)
	_refresh_rack()
	Sfx.play("clink", -8.0)
	_tutorial_event("glass")


func _tap_prompt(id: String) -> String:
	if not GameState.drink_available(id):
		return ""
	var name: String = GameData.drink(id).get("short", id)
	if player.held == null:
		return _hint("Grab a clean glass to pour %s" % name)
	var c := player.held.contents
	if c.drink_id != "" and c.drink_id != id and not c.is_empty():
		return _hint("That glass already has %s in it" % GameData.drink(c.drink_id).get("short", ""))
	var want := str(GameData.drink(id).get("glass", "pint"))
	if c.is_empty() and player.held.kind != want:
		return _hint("%s goes in a %s glass" % [name, want])
	if GameState.serves_left(id) <= 0.02 and int(GameState.stock.get(id, 0)) <= 0:
		return _hint("Out of %s. Order more from the stock pile" % name)
	if GameState.serves_left(id) <= 0.02 and str(GameData.drink(id).get("stock_unit", "keg")) in ["keg", "cask"]:
		return _hint("%s keg is empty. Change it in the cellar" % name)
	if id == "stout" and c.stage >= 2:
		return "Top up the stout"
	return "Pour %s" % name


func _tap_action(id: String) -> void:
	if _tap_prompt(id).begins_with("~") or player.held == null:
		return
	pour.begin(id, info["taps"][id])


func _settle_prompt(i: int) -> String:
	var g: PintGlass = settle_slots[i]
	if g != null:
		if player.has_hands_free():
			var pct := int(g.contents.settled_fraction() * 100.0)
			if pct >= 99:
				return "Pick up the settled %s" % GameData.drink(g.contents.drink_id).get("short", "pint")
			return "Pick up the pint (settling %d%%)" % pct
		return ""
	if player.held != null and not player.held.contents.is_empty():
		return "Leave it here to settle"
	return ""


func _settle_action(i: int) -> void:
	var g: PintGlass = settle_slots[i]
	if g != null and player.has_hands_free():
		settle_slots[i] = null
		player.take_glass(g)
		return
	if g == null and player.held != null and not player.held.contents.is_empty():
		place_on_settle(i, player.release_glass())


func place_on_settle(i: int, g: PintGlass) -> void:
	settle_slots[i] = g
	add_child(g)
	g.global_position = PubLayout.SETTLE_SLOTS[i]
	g.rotation = Vector3.ZERO
	Sfx.play("glass_place", -6.0)
	_tutorial_event("settle")


func free_settle_slot() -> int:
	for i in settle_slots.size():
		if settle_slots[i] == null:
			return i
	return -1


func _sink_prompt() -> String:
	if not player.dirty_stack.is_empty():
		return "Wash a glass (%d dirty)" % player.dirty_stack.size()
	if player.held != null and not player.held.contents.is_empty():
		return "Pour it away"
	if player.held != null and player.held.dirt >= 0.1:
		return "Wash this glass"
	return ""


func _sink_action() -> void:
	if player.held != null and not player.held.contents.is_empty():
		var c := player.held.contents
		GameState.waste_units(c.drink_id, c.total())
		c.reset()
		player.held.set_dirty(0.5)
		Sfx.play("spill", -6.0)
		var g := player.release_glass()
		player.add_dirty(g)
		notify("Poured away. Wash the glass before reusing it.")
		return
	if player.held != null and player.held.dirt >= 0.1:
		player.add_dirty(player.release_glass())
	var batch := 1 + int(GameState.get_mod("wash_batch"))    # the glass washer takes more than one
	var g: PintGlass = null
	for i in batch:
		var gi := player.pop_dirty()
		if gi == null:
			break
		g = gi
		gi.queue_free()
		rack_clean += 1
		GameState.stats["glasses_washed"] = int(GameState.stats["glasses_washed"]) + 1
		GameState.bump_today("washed")
	if g == null:
		return
	_refresh_rack()
	Sfx.play("squeak", -6.0)
	Sfx.play("clink", -10.0)
	_tutorial_event("washed")


func _sign_prompt() -> String:
	match GameState.phase:
		"prep":
			return "Open the pub (flip the sign)"
		"open":
			return "Call last orders early"
		"last_orders", "closing":
			if customers.is_empty():
				return "Close up and cash up"
			return _hint("Waiting for the last customers to leave (%d)" % customers.size())
	return ""


func _sign_action() -> void:
	match GameState.phase:
		"prep":
			GameState.open_pub()
			Sfx.play("door_bell", -4.0)
			_set_sign(true)
			voices.speak(null, "landlord", "welcome", true)
			_tutorial_event("opened")
			if int(GameState.stats["served"]) == 0:
				_first_customer_timer = 3.0
		"open":
			_last_orders()
		"last_orders", "closing":
			if customers.is_empty():
				close_day()


# ------------------------------------------------------------------ the lock-in
## The regulars who'd stay behind the drawn blinds: the closest friends of the house.
func lockin_guests() -> Array:
	var ids := []
	for id in GameState.relationships.keys():
		if int(GameState.relationships[id]) >= 4 and GameData.regulars_by_id.has(id):
			ids.append(id)
	ids.sort_custom(func(a, b): return int(GameState.relationships[a]) > int(GameState.relationships[b]))
	return ids.slice(0, 5)


func _lockin_prompt() -> String:
	if GameState.phase not in ["last_orders", "closing"] or not customers.is_empty() or GameState.today.get("lockin", false):
		return ""
	if lockin_guests().size() < 2:
		return ""
	return "Hold a lock-in with the regulars"


## After hours, blinds down, the regulars stay on. Good money and better stories, unless the
## Gardaí come knocking.
func _lockin() -> void:
	if _lockin_prompt() == "":
		return
	var guests := lockin_guests()
	GameState.today["lockin"] = true
	var names := []
	for id in guests:
		names.append(str(GameData.regulars_by_id[id]["name"]).split(" ")[0])
		_relationship(id, 2)
	var rounds := 2 + _rng.randi() % 2
	var takings := 0.0
	for id in guests:
		takings += GameState.price_of(str(GameData.regulars_by_id[id].get("drink", "stout"))) * rounds
	var raided := _rng.randf() < 0.1 + 0.03 * guests.size()
	var who: String = ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])
	var body := ""
	if raided:
		var fine := float(GameData.econ("lockin_fine", 60))
		GameState.earn(takings * 0.5, "sales")
		GameState.spend(fine, "other", true)
		GameState.reputation = maxf(0.0, GameState.reputation - 2.0)
		Sfx.play("knock", -2.0)
		body = "%s stayed on with the blinds down. Half an hour in there's a knock at the door: the Gardaí.\nA €%d fine and a warning. Takings €%.2f." % [who, int(fine), takings * 0.5]
		celebrate("Garda at the door!", body, "t06")
	else:
		GameState.earn(takings, "sales")
		GameState.reputation = minf(100.0, GameState.reputation + 0.5)
		body = "%s stayed on with the blinds down. %d rounds, a few songs and the story about the bishop's bicycle.\nTakings €%.2f, and friends for life." % [who, rounds, takings]
		celebrate("A lock-in", body, "t17")
	GameState.stats["lockins"] = int(GameState.stats.get("lockins", 0)) + 1


func _set_sign(open: bool) -> void:
	var lbl: Label3D = info.get("door_sign_label")
	if lbl:
		lbl.text = "OPEN" if open else "CLOSED"
		lbl.modulate = Color(0.4, 0.95, 0.5) if open else Color(0.9, 0.3, 0.2)


const LINE_CLEAN_POS := Vector3(-5.6, 1.0, -6.0)


func _lines_prompt() -> String:
	var days := GameState.day - int(GameState.progress.get("lines_cleaned_day", GameState.day))
	if days < 3:
		return _hint("Beer lines are clean (done %s)" % ("today" if days == 0 else "%d days ago" % days))
	var cost := int(GameData.econ("line_clean_cost", 8))
	return "Hold to clean the beer lines (€%d)%s" % [cost, "  · overdue!" if GameState.line_penalty() > 0.0 else ""]


func _lines_action() -> void:
	if _lines_prompt().begins_with("~"):
		return
	if GameState.clean_lines():
		Sfx.play("squeak", -4.0)
		notify("Lines cleaned. Every draught pint tastes the way it should.", "good")
	else:
		notify("Not enough cash for the line cleaner.", "bad")


func _keg_prompt(id: String) -> String:
	if not GameState.drink_available(id):
		return ""
	var d := GameData.drink(id)
	var left := GameState.serves_left(id)
	var spare := int(GameState.stock.get(id, 0))
	if left < 6.0 and spare > 0:
		return "Hold to change the %s %s (%d spare)" % [d["short"], d["stock_unit"], spare]
	if left < 6.0:
		return _hint("No spare %s %s. Order more from the stock menu" % [d["short"], d["stock_unit"]])
	return _hint("%s: about %d serves left, %d spare" % [d["short"], int(left), spare])


func _keg_action(id: String) -> void:
	if GameState.serves_left(id) >= 6.0:
		return
	if GameState.change_keg(id):
		Sfx.play("keg", -2.0)
		notify("Fresh %s connected." % GameData.drink(id)["stock_unit"], "info")
		_refresh_stock_pile()


## All close-up camera moves (pouring, darts, Split the G, the fireside) share one tween, so a
## move that is still finishing can never fight the next one.
func new_cam_tween() -> Tween:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween()
	return _cam_tween


## Hands the view back to the player, unless another close-up has started in the meantime.
func back_to_player_camera() -> void:
	if in_minigame():
		return
	player.camera.current = true
	player.input_enabled = true


func in_minigame() -> bool:
	return (pour and pour.active) or (drink_scene and drink_scene.active) or (darts and darts.active) or (session and session.active)


func _darts_prompt() -> String:
	if not GameState.has_upgrade("dartboard") or not player.has_hands_free():
		return ""
	return "Play darts against %s" % darts_opponent_name()


func darts_opponent() -> String:
	for c in customers:
		if c.regular_id != "" and c.state in ["drinking", "stand_drink"]:
			return c.regular_id
	return "packie"


func darts_opponent_name() -> String:
	return str(GameData.regulars_by_id.get(darts_opponent(), {}).get("name", "Packie Walsh")).split(" ")[0]


func _session_prompt() -> String:
	if not player.has_hands_free() or live == null or not live.playing:
		return ""
	if not GameState.has_upgrade("house_bodhran"):
		return _hint("Buy the house bodhrán to sit in on the session")
	if not session.can_play():
		return ""
	return "Sit in on the bodhrán"


func start_darts() -> void:
	if not in_minigame() and GameState.has_upgrade("dartboard"):
		darts.begin(darts_opponent())


func _split_prompt() -> String:
	if not player.has_hands_free():
		return ""
	return "Try the Split the G challenge"


func start_split(championship := false) -> void:
	if not in_minigame():
		drink_scene.championship = championship and live and live.championship_open and not live.championship_done
		drink_scene.begin("split", "stout")


func _champ_prompt() -> String:
	if live and live.championship_open and not live.championship_done and player.has_hands_free():
		return "Enter the Split the G championship (€50 prize)"
	return ""


func _fireside_prompt() -> String:
	if not player.has_hands_free():
		return ""
	if pub_closed_for_you():
		return "Sit by the fire with your own pint"
	return "Sit by the fire with a Galagers Zero"


func pub_closed_for_you() -> bool:
	return GameState.phase == "prep" or (GameState.phase in ["closing", "last_orders"] and customers.is_empty())


func start_relax() -> void:
	if not in_minigame():
		drink_scene.begin("relax", "stout" if pub_closed_for_you() else "zero")


# ------------------------------------------------------------------ glasses
func _refresh_rack() -> void:
	for n in _rack_visuals:
		n.queue_free()
	_rack_visuals.clear()
	var rack: Node3D = info["rack_glasses"]
	var slots: Array = info["rack_slots"]
	for i in mini(rack_clean, slots.size()):
		var g := PintGlass.new()
		rack.add_child(g)
		g.position = slots[i] + Vector3(0, 0.16, 0)
		g.rotation = Vector3(PI, 0, 0)  # stored upside down
		g.set_process(false)
		_rack_visuals.append(g)
	if hud:
		hud.refresh()


func glass_count_check() -> int:
	## Counts every glass in the game so tests can prove none are created or lost.
	var n := rack_clean
	if player.held:
		n += 1
	n += player.dirty_stack.size()
	for g in settle_slots:
		if g != null:
			n += 1
	n += loose_glasses.size()
	for c in customers:
		if c.glass != null:
			n += 1
	for st in staff_npcs:
		n += st.glass_count()
	if pour and pour.active and pour.glass and player.held != pour.glass:
		n += 1
	return n


func leave_dirty_glass(g: PintGlass, pos: Vector3) -> void:
	add_child(g)
	g.global_position = pos
	g.rotation = Vector3.ZERO
	loose_glasses.append(g)
	var it := Interactable.make(g, pos + Vector3(0, 0.08, 0), "dirty_glass",
		func(): return _collect_prompt(g), func(): _collect_glass(g), 0.0, 1.6)
	_tutorial_event("dirty")


func _collect_prompt(g: PintGlass) -> String:
	if player.held != null:
		return ""
	if player.dirty_stack.size() >= MAX_DIRTY_CARRY:
		return _hint("Hands full. Wash these first")
	return "Collect the empty glass"


func _collect_glass(g: PintGlass) -> void:
	if player.held != null or player.dirty_stack.size() >= MAX_DIRTY_CARRY:
		return
	loose_glasses.erase(g)
	for ch in g.get_children():
		if ch is Interactable:
			ch.queue_free()
	player.add_dirty(g)
	Sfx.play("clink", -8.0)


func _restore_overnight_dirty() -> void:
	var n := int(GameState.tutorial.get("dirty_overnight", 0))
	GameState.tutorial.erase("dirty_overnight")
	for i in n:
		var g := PintGlass.new()
		g.set_dirty(0.7)
		g.lace_top = 0.7
		leave_dirty_glass(g, PubLayout.SINK_POS + Vector3(-0.3 - (i % 4) * 0.09, 0, 0.12 - (i / 4) * 0.1))


# ------------------------------------------------------------------ staff
## Brings the hired staff in to match GameState.staff (at their posts when the world loads,
## through the front door when hired mid-day) and sends anyone let go home.
func refresh_staff(at_start := false) -> void:
	var want := {}
	for e in GameState.staff:
		want[str(e.get("id", ""))] = e
	for st in staff_npcs.duplicate():
		if not want.has(st.staff_id):
			staff_npcs.erase(st)
			st.clock_off()
			st.walk_to(PubLayout.OUTSIDE_DOOR, "exit")
	var models: Array = []
	for e in GameState.staff:
		models.append(str(e.get("model", "")))
	Customer.reserved_models = models
	for e in GameState.staff:
		var id := str(e.get("id", ""))
		var have := false
		for st in staff_npcs:
			if st.staff_id == id:
				have = true
		if have:
			continue
		var st := StaffMember.new()
		st.setup_staff(self, e, hash(id))
		add_child(st)
		staff_npcs.append(st)
		if at_start:
			st.global_position = st.home()
			st.rotation.y = PI
			st.state = "st_idle"
		else:
			st.global_position = PubLayout.INSIDE_DOOR
			st.walk_to(reach_point(st.home()), "st_idle")
			_door_anim = 2.0
			Sfx.play("door_bell", -10.0)
			st.say("Grand, I'll get stuck in.", 3.0)


const STAFF_OVERFLOW_WAIT := 15.0


func staff_serving(c: Customer) -> StaffMember:
	var st: Variant = c.get_meta("served_by") if c.has_meta("served_by") else null
	if st != null and is_instance_valid(st) and staff_npcs.has(st):
		return st
	return null


## The nearest point people can walk to (glasses and spills sit on tables and the bar).
func reach_point(pos: Vector3) -> Vector3:
	if not _nav_ready:
		return Vector3(pos.x, 0, pos.z)
	var p := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, Vector3(pos.x, 0, pos.z))
	return Vector3(p.x, 0, p.z)


## The waiting customer a bartender should see to next: whoever has waited longest, leaving the
## ones right in front of the player to the player.
func staff_next_customer(st: StaffMember) -> Customer:
	var best: Customer = null
	var best_score := INF
	var behind := player.global_position.z < PubLayout.BAR_BACK_Z + 0.3
	for c in customers:
		if c.state != "wait_order" or c.bar_spot < 0 or staff_serving(c) != null:
			continue
		# you're the first port of call: staff pick up orders that have been left waiting
		if not c.has_meta("at_bar_t"):
			c.set_meta("at_bar_t", run_time)
		if run_time - float(c.get_meta("at_bar_t")) < STAFF_OVERFLOW_WAIT:
			continue
		var d := absf(player.global_position.x - bar_spot_pos(c.bar_spot).x)
		if behind and d < 1.0 and c.patience_frac() > 0.5:
			continue
		var score := c.patience_frac() - minf(d, 6.0) * 0.05 + st.global_position.distance_to(c.global_position) * 0.02
		if score < best_score:
			best_score = score
			best = c
	return best


func staff_take_order(_st: StaffMember, c: Customer) -> void:
	c.take_order()
	order_taken.emit(c)
	if hud:
		hud.refresh_orders()


func staff_take_glass(st: StaffMember, kind: String) -> PintGlass:
	rack_clean -= 1
	var g := PintGlass.new(kind)
	add_child(g)
	g.global_position = PubLayout.RACK_POS
	_refresh_rack()
	Sfx.play_at("clink", PubLayout.RACK_POS, self, -10.0)
	return g


## Anyone else at the bar already waiting on this drink (their bartender may be busy).
func staff_other_taker(_st: StaffMember, drink_id: String) -> Customer:
	for c in customers:
		if c.state == "wait_drink" and c.drink_id == drink_id and c.bar_spot >= 0:
			var h := staff_serving(c)
			if h == null or h == _st:
				return c
	return null


func staff_serve(st: StaffMember, c: Customer) -> bool:
	var g := st.glass
	if g == null:
		return false
	var res := serve_customer(c, g, st)
	if not res.get("ok", false):
		return false
	st.glass = null
	var score := int(res.get("score", 0))
	if hud and (score < 60 or score >= 92):
		# only the pints worth knowing about: a poor one (have a word) or a perfect one
		notify("%s served %s a %s (%d)" % [st.display_name, c.display_name.split(" ")[0], str(res.get("verdict", "")).to_lower(), score], "good" if score >= 92 else "warn")
	return true


## A pint nobody wants goes down the sink and the glass is washed.
func staff_tip_away(st: StaffMember) -> void:
	var g := st.glass
	st.glass = null
	if g == null:
		return
	if not g.contents.is_empty():
		GameState.waste_units(g.contents.drink_id, g.contents.total())
		Sfx.play_at("spill", PubLayout.SINK_POS, self, -10.0)
	g.queue_free()
	rack_clean += 1
	_refresh_rack()


func staff_next_spill(st: StaffMember) -> Node3D:
	var best: Node3D = null
	for s in spills:
		var who: Variant = s.get_meta("staff") if s.has_meta("staff") else null
		if who != null and who != st and is_instance_valid(who):
			continue
		if best == null or st.global_position.distance_to(s.global_position) < st.global_position.distance_to(best.global_position):
			best = s
	return best


func staff_wipe(_st: StaffMember, s: Node3D) -> void:
	spills.erase(s)
	s.queue_free()
	Sfx.play_at("squeak", s.global_position, self, -8.0)
	GameState.stats["spills_cleaned"] = int(GameState.stats["spills_cleaned"]) + 1


func staff_next_glass(st: StaffMember) -> PintGlass:
	var best: PintGlass = null
	for g in loose_glasses:
		var who: Variant = g.get_meta("staff") if g.has_meta("staff") else null
		if who != null and who != st and is_instance_valid(who):
			continue
		if best == null or st.global_position.distance_to(g.global_position) < st.global_position.distance_to(best.global_position):
			best = g
	return best


func staff_pick_up(_st: StaffMember, g: PintGlass) -> void:
	loose_glasses.erase(g)
	for ch in g.get_children():
		if ch is Interactable:
			ch.queue_free()


func staff_wash(_st: StaffMember, g: PintGlass) -> void:
	g.queue_free()
	rack_clean += 1
	GameState.stats["glasses_washed"] = int(GameState.stats["glasses_washed"]) + 1
	GameState.bump_today("washed")
	_refresh_rack()
	Sfx.play_at("squeak", PubLayout.SINK_POS, self, -10.0)
	Sfx.play_at("clink", PubLayout.SINK_POS, self, -12.0)


## Someone clocking off puts down what they hold: a pint goes down the sink, empties stay out.
func staff_drop_all(st: StaffMember) -> void:
	if st.role == "bartender":
		staff_tip_away(st)
		return
	var gs := st.carried.duplicate()
	st.carried.clear()
	st.glass = null
	gs.reverse()
	var i := 0
	for g in gs:
		if g.get_parent():
			g.get_parent().remove_child(g)
		# left by the sink for whoever washes up next
		leave_dirty_glass(g, PubLayout.SINK_POS + Vector3(-0.3 - (i % 4) * 0.09, 0, 0.12 - (i / 4) * 0.1))
		i += 1


# ------------------------------------------------------------------ customers
func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _nav_ready:
		return PackedVector3Array([to])
	var map := get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.size() > 0:
		p.append(to)
	return p


func patience_drain() -> float:
	# good atmosphere and music make waiting easier
	var a := GameState.atmosphere()
	return clampf(1.15 - a / 200.0, 0.6, 1.2)


func drink_speed_mult() -> float:
	return 1.0 / (1.0 + GameState.get_mod("stay_mult") + GameState.live_stay)


func line(kind: String) -> String:
	var arr: Array = GameData.customer_lines.get(kind, ["..."])
	return arr[_rng.randi() % arr.size()]


func order_line(c: Customer) -> String:
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		var lines: Array = r.get("greet", [])
		if not lines.is_empty():
			return lines[_rng.randi() % lines.size()]
	if c.visitor == "tourist" and _rng.randf() < 0.5:
		var tl: Array = GameData.customer_lines.get("tourist_order", [])
		return tl[_rng.randi() % tl.size()] + " (%s it is!)" % GameData.drink(c.drink_id).get("short", "")
	var ol: Dictionary = GameData.customer_lines.get("order", {})
	var arr: Array = ol.get(c.drink_id, ["A drink, please."])
	return arr[_rng.randi() % arr.size()]


func pick_drink(c: Customer) -> String:
	var avail := GameState.available_drinks()
	var stocked := avail.filter(func(id): return GameState.serves_left(id) > 0.5 or int(GameState.stock.get(id, 0)) > 0)
	if stocked.is_empty():
		stocked = avail
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		if r["drink"] in stocked:
			return r["drink"]
		if r.has("alt") and r["alt"] in stocked:
			return r["alt"]
	# stout is the house speciality
	var weights := {"stout": 5.0, "lager": 3.0, "ale": 1.5, "cider": 1.5, "zero": 0.8, "whiskey": 1.0, "soft": 1.0}
	var total := 0.0
	for id in stocked:
		total += float(weights.get(id, 1.0))
	var r2 := _rng.randf() * total
	for id in stocked:
		r2 -= float(weights.get(id, 1.0))
		if r2 <= 0.0:
			return id
	return stocked[0]


func max_customers() -> int:
	var preset: String = GameState.graphics_preset()
	var cap := int(GameData.econ("max_customers_" + preset, 14))
	var seats := 0
	for s in info["seats"]:
		if not s.has("upgrade") or GameState.has_upgrade(s["upgrade"]):
			seats += 1
	return mini(cap, seats + bar_spots.size() + 2)


func arrival_rate_per_hour() -> float:
	if GameState.phase != "open":
		return 0.0
	var h := GameState.hour
	var curve := 0.6
	if h >= 18.0:
		curve = 1.0
	if h >= 20.0:
		curve = 1.35
	if h >= 22.0:
		curve = 1.05
	var wd: Array = GameData.econ("weekday_mult", [1, 1, 1, 1, 1, 1, 1])
	var weather_m: Dictionary = GameData.econ("weather_mult", {})
	var wm := float(weather_m.get(GameState.weather, 1.0))
	if GameState.weather in ["rain", "storm"]:
		wm += GameState.get_mod("rain_bonus")
	var rep := 0.55 + GameState.reputation / 45.0
	var arr := 1.0 + GameState.get_mod("arrival_mult")
	var music := (live.arrival_mult() if live else 1.0) * (match_day.arrival_mult() if match_day else 1.0)
	return float(GameData.econ("base_arrivals_per_hour", 7.0)) * curve * float(wd[GameState.weekday()]) * wm * rep * arr * music


func _maybe_spawn(dt: float) -> void:
	if _first_customer_timer > 0.0:
		_first_customer_timer -= dt
		if _first_customer_timer <= 0.0:
			dispatcher.force_next = true
			spawn_customer()
		return
	_spawn_gap -= dt
	if GameState.phase != "open" or _spawn_gap > 0.0:
		return
	# keep the room as lively as the hour and reputation suggest, without flooding the bar:
	# arrivals mostly sit and chat; the dispatcher decides when each of them orders
	var music := (live.arrival_mult() if live else 1.0) * (match_day.arrival_mult() if match_day else 1.0)
	var target := dispatcher.target_population(GameState.hour, music, max_customers())
	if customers.size() >= target or dispatcher.pending.size() >= 4:
		return
	_spawn_gap = _rng.randf_range(10.0, 22.0)
	spawn_customer()


## Orders currently being dealt with at the bar (walking up, waiting to order, waiting for a drink).
func active_orders() -> int:
	var n := 0
	for c in customers:
		if c.ordering and c.state in ["walk", "wait_order", "wait_drink", "queue"]:
			n += 1
	return n


func _dispatch(dt: float) -> void:
	if GameState.phase == "closing":
		dispatcher.pending.clear()      # the bar's shut: nobody else is called up
		return
	var a := active_orders()
	max_active_seen = maxi(max_active_seen, a)
	var c = dispatcher.tick(dt, a, live != null and live.playing)
	if c != null:
		send_to_bar(c)


func send_to_bar(c: Customer) -> void:
	var spot := request_bar_spot(c)
	if spot < 0:
		dispatcher.add_pending(c)
		return
	if c.seat >= 0:
		release_seat(c.seat)
		c.seat = -1
	c.go_to_bar(spot, bar_spot_pos(spot))


func customer_wants_order(c: Customer) -> void:
	c.state = "mingle"
	c.mingle_t = 0.0
	dispatcher.add_pending(c)


func spawn_customer(force_regular := "") -> Customer:
	var c := Customer.new()
	var look := {}
	var reg := force_regular
	if reg == "" and _rng.randf() < 0.35:
		var options := []
		for r in GameData.regulars:
			if not _regulars_today.has(r["id"]):
				options.append(r["id"])
		if not options.is_empty():
			reg = options[_rng.randi() % options.size()]
	if reg != "":
		var r: Dictionary = GameData.regulars_by_id[reg]
		look = r.get("look", {})
		c.regular_id = reg
		c.display_name = r["name"]
		c.patience_max = dispatcher.patience_for(float(r.get("patience", 1.0)))
		c.tip_mult = float(r.get("tip", 1.0))
		_regulars_today[reg] = true
	else:
		var names: Array = GameData.customer_lines.get("first_names", ["Pat"])
		c.display_name = names[_rng.randi() % names.size()]
		var types: Array = GameData.customer_lines.get("visitor_types", ["local"])
		c.visitor = types[_rng.randi() % types.size()]
		c.patience_max = dispatcher.patience_for(_rng.randf_range(0.9, 1.1) * (1.2 if c.visitor == "tourist" else 1.0))
		c.tip_mult = _rng.randf_range(0.7, 1.3) * (1.3 if c.visitor == "tourist" else 1.0)
	c.patience = c.patience_max
	c.budget = 1 + int(_rng.randf() < 0.45) + int(_rng.randf() < 0.2)
	c.drink_rate = 1.0 / _rng.randf_range(75.0, 120.0)
	c.speed = _rng.randf_range(1.1, 1.4)
	c.setup(self, look, _rng.randi())
	var reg_voice := str(GameData.regulars_by_id[reg].get("voice", "")) if reg != "" else ""
	c.voice = VoiceDirector.voice_for(reg_voice, c.gender, c.visitor, _rng.randi())
	add_child(c)
	c.drink_id = pick_drink(c)
	var from_left := _rng.randf() < 0.5
	c.global_position = PubLayout.STREET_SPAWN_L if from_left else PubLayout.STREET_SPAWN_R
	c.left_pub.connect(_on_customer_left)
	customers.append(c)
	var name_text := c.display_name if c.regular_id != "" else ""
	c.set_name_tag(name_text)
	var it := Interactable.make(c, c.global_position + Vector3(0, 1.3, 0), "customer",
		func(): return _customer_prompt(c), func(): _customer_action(c), 0.0, 2.3)
	it.position = Vector3(0, 1.3, 0)
	c.walk_to(PubLayout.INSIDE_DOOR, "choose")
	_door_anim = 2.0
	Sfx.play("door_bell", -10.0)
	# price check: very expensive drinks put people off
	return c


func customer_choose(c: Customer) -> void:
	var ratio := GameState.price_of(c.drink_id) / float(GameData.drink(c.drink_id).get("price", 5.0))
	if ratio > 1.0 + float(GameData.econ("price_tolerance", 0.18)) * 2.5 and _rng.randf() < (ratio - 1.3) * 2.0:
		c.say(line("too_dear"), 3.0, Color(1, 0.7, 0.4))
		GameState.today["walkouts"] = int(GameState.today["walkouts"]) + 1
		c.leave()
		return
	# find somewhere to sit (or stand) and wait to be called up to order
	var s := request_seat(c)
	if s >= 0:
		c.seat = s
		var sd: Dictionary = seat_info(s)
		c.start_mingling(sd["pos"], sd["yaw"])
	else:
		c.start_mingling(standing_spot(c), 0.0)
	dispatcher.add_pending(c)


func request_bar_spot(c: Customer) -> int:
	if c.bar_spot >= 0:
		return c.bar_spot
	# prefer spots nearest the stout tap
	var order := range(bar_spots.size())
	order.sort_custom(func(a, b): return absf(PubLayout.BAR_SPOT_X[a] - PubLayout.TAP_X["stout"]) < absf(PubLayout.BAR_SPOT_X[b] - PubLayout.TAP_X["stout"]))
	for i in order:
		if bar_spots[i] == null:
			bar_spots[i] = c
			return i
	return -1


func release_bar_spot(c: Customer) -> void:
	for i in bar_spots.size():
		if bar_spots[i] == c:
			bar_spots[i] = null


func release_queue_slot(c: Customer) -> void:
	if c.queue_slot >= 0 and c.queue_slot < queue_slots.size() and queue_slots[c.queue_slot] == c:
		queue_slots[c.queue_slot] = null
	c.queue_slot = -1


func bar_spot_pos(i: int) -> Vector3:
	return Vector3(PubLayout.BAR_SPOT_X[i], 0, PubLayout.BAR_SPOT_Z)


func request_seat(c: Customer) -> int:
	var seats: Array = info["seats"]
	var best := -1
	var best_score := INF
	for i in seats.size():
		if seats_taken.has(i):
			continue
		var s: Dictionary = seats[i]
		if s.has("upgrade") and not GameState.has_upgrade(s["upgrade"]):
			continue
		var score: float = (s["pos"] as Vector3).distance_to(c.global_position) + _rng.randf() * 3.0
		if s["kind"] == "armchair" and GameState.has_upgrade("fireplace"):
			score -= 3.0
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		seats_taken[best] = c
	return best


func release_seat(i: int) -> void:
	seats_taken.erase(i)


func seat_info(i: int) -> Dictionary:
	return info["seats"][i]


func standing_spot(c: Customer) -> Vector3:
	var spots := [Vector3(-1.5, 0, 4.3), Vector3(1.6, 0, 4.4), Vector3(-6.3, 0, -0.6), Vector3(4.3, 0, 0.2), Vector3(-2.0, 0, 0.0)]
	return spots[_rng.randi() % spots.size()] + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))


func nearest_ledge(p: Vector3) -> Vector3:
	# the bar top in front of the nearest service spot, or a window sill
	var best := Vector3(PubLayout.BAR_SPOT_X[0], PubLayout.BAR_TOP, PubLayout.SERVE_Z)
	var bd := INF
	for x in PubLayout.BAR_SPOT_X:
		var q := Vector3(x + _rng.randf_range(-0.2, 0.2), PubLayout.BAR_TOP, PubLayout.SERVE_Z)
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	for q in [Vector3(-4.2, 0.92, 4.8), Vector3(3.6, 0.92, 4.8)]:
		var d: float = q.distance_to(p)
		if d < bd:
			bd = d
			best = q + Vector3(_rng.randf_range(-0.5, 0.5), 0, 0)
	return best


func exit_point(_c: Customer) -> Vector3:
	return PubLayout.STREET_SPAWN_L if _rng.randf() < 0.5 else PubLayout.STREET_SPAWN_R


func can_reorder(c: Customer) -> bool:
	return GameState.phase == "open" and c.satisfaction_sum / maxf(1.0, c.served_count) > 45.0


func on_customer_at_bar(c: Customer) -> void:
	c.set_meta("at_bar_t", run_time)
	_tutorial_event("customer_at_bar")


func on_walkout(c: Customer) -> void:
	if c.served_count == 0:
		streak = 0
		GameState.today["walkouts"] = int(GameState.today["walkouts"]) + 1
		GameState.stats["walkouts"] = int(GameState.stats["walkouts"]) + 1
		notify("%s gave up waiting and left." % c.display_name, "bad")
		if c.regular_id != "":
			_relationship(c.regular_id, -2)


func _on_customer_left(c: Customer) -> void:
	customers.erase(c)
	release_bar_spot(c)
	release_queue_slot(c)
	if c.seat >= 0:
		release_seat(c.seat)


func _customer_prompt(c: Customer) -> String:
	if not is_instance_valid(c):
		return ""
	var helper := staff_serving(c)
	if helper != null and c.state in ["wait_order", "wait_drink"]:
		return _hint("%s is looking after %s" % [helper.display_name, c.display_name])
	match c.state:
		"wait_order":
			return "Take %s's order" % c.display_name
		"wait_drink":
			if player.held != null and not player.held.contents.is_empty():
				return "Serve %s" % c.display_name
			return _hint("%s is waiting for a %s" % [c.display_name, GameData.drink(c.drink_id).get("short", "")])
		"queue":
			return _hint("%s is queueing for the bar" % c.display_name)
		"drinking", "stand_drink", "mingle":
			if c.regular_id != "" and player.has_hands_free():
				if not stories.chapter_ready(c.regular_id).is_empty():
					return "Talk to %s (something on their mind)" % c.display_name
				if c.state != "mingle":
					return "Chat with %s" % c.display_name
	return ""


func _customer_action(c: Customer) -> void:
	if staff_serving(c) != null and c.state in ["wait_order", "wait_drink"]:
		return
	match c.state:
		"wait_order":
			c.take_order()
			order_taken.emit(c)
			_tutorial_event("order")
			if hud:
				hud.refresh_orders()
		"wait_drink":
			if player.held != null and not player.held.contents.is_empty():
				serve_customer(c, player.held)
		"drinking", "stand_drink", "mingle":
			if c.regular_id != "" and not stories.chapter_ready(c.regular_id).is_empty():
				stories.tell(c)
				return
			if c.regular_id != "" and c.state != "mingle":
				var r: Dictionary = GameData.regulars_by_id[c.regular_id]
				var chat: Array = r.get("chat", [])
				if not chat.is_empty():
					c.speak("chatter", chat[_rng.randi() % chat.size()], 5.0, Color(1, 0.97, 0.9), true)
					_relationship(c.regular_id, 1, true)
					var chatted: Array = GameState.today.get("chatted", [])
					if not chatted.has(c.regular_id):
						chatted.append(c.regular_id)
						GameState.today["chatted"] = chatted
						GameState.today["chats"] = chatted.size()


## Hands a glass to a waiting customer: scores it, takes payment and tips.
func serve_customer(c: Customer, g: PintGlass, by: StaffMember = null) -> Dictionary:
	var con := g.contents
	if con.drink_id != c.drink_id:
		c.refuse_drink(line("wrong_drink") + " (%s)" % GameData.drink(c.drink_id).get("short", ""))
		return {"ok": false, "reason": "wrong_drink"}
	var draught := str(GameData.drink(c.drink_id).get("stock_unit", "keg")) in ["keg", "cask"]
	var lines := GameState.line_penalty() if draught else 0.0
	var res := con.evaluate(g.dirt, GameState.get_mod("beer_quality") * 0.6 - lines)
	if lines > 0.0:
		(res["notes"] as Array).append("The beer lines need cleaning (in the cellar)")
	var q: int = res["score"]
	if q < 30:
		c.refuse_drink(line("refuse"))
		GameState.today["complaints"] = int(GameState.today["complaints"]) + 1
		c.patience = maxf(c.patience, c.patience_max * 0.4)
		res["ok"] = false
		res["reason"] = "refused"
		notify("%s: %s" % [res["verdict"], ", ".join(res["notes"])], "bad")
		return res
	if player.held == g:
		player.release_glass()
	# payment
	var price := GameState.price_of(c.drink_id)
	var base := float(GameData.drink(c.drink_id).get("price", 5.0))
	var fair := clampf(1.0 - maxf(0.0, price / base - 1.0) * 2.0, 0.0, 1.0)
	var wait_score := clampf(c.patience / c.patience_max, 0.0, 1.0)
	var atmos := GameState.atmosphere() / 100.0
	var sat := q * 0.5 + wait_score * 25.0 + fair * 10.0 + atmos * 10.0 + cleanliness() / 100.0 * 5.0
	sat = clampf(sat, 0.0, 100.0)
	var tip_rate := 0.0
	if q >= 90:
		tip_rate = 0.22
	elif q >= 75:
		tip_rate = 0.12
	elif q >= 60:
		tip_rate = 0.05
	tip_rate *= c.tip_mult * (1.0 + GameState.get_mod("tips_mult") + GameState.live_tips) * (0.6 + wait_score * 0.4) * (0.5 + fair * 0.5)
	if by == null:
		# a run of good pints gets the bar talking: tips grow with the streak
		streak = streak + 1 if q >= 75 else 0
		GameState.today["best_streak"] = maxi(int(GameState.today.get("best_streak", 0)), streak)
		tip_rate *= 1.0 + minf(streak, 10) * 0.03
		if q >= 90:
			GameState.bump_today("perfect")
	var tip := snappedf(price * tip_rate, 0.1)
	GameState.earn(price, "sales")
	GameState.earn(tip, "tips")
	if c.order_time >= 0.0 and by == null:
		OrderDispatcher.record_service(run_time - c.order_time)   # the pacing follows the player's own speed
	GameState.today["served"] = int(GameState.today["served"]) + 1
	GameState.today["satisfaction_sum"] = float(GameState.today["satisfaction_sum"]) + sat
	GameState.today["quality_sum"] = float(GameState.today["quality_sum"]) + q
	GameState.today["pours"] = int(GameState.today["pours"]) + 1
	GameState.stats["served"] = int(GameState.stats["served"]) + 1
	if c.drink_id in ["stout", "lager", "ale"]:
		GameState.stats["pints_poured"] = int(GameState.stats["pints_poured"]) + 1
	if q >= 90:
		GameState.stats["perfect_pints"] = int(GameState.stats["perfect_pints"]) + 1
	GameState.stats["best_pour"] = maxi(int(GameState.stats["best_pour"]), q)
	c.satisfaction_sum += sat
	if c.regular_id != "":
		stories.note_pint(c.regular_id, q)
	c.receive_drink(g)
	var reaction := ""
	if c.regular_id != "":
		var r: Dictionary = GameData.regulars_by_id[c.regular_id]
		var arr: Array = r.get("praise" if q >= 70 else "complain", [])
		reaction = arr[_rng.randi() % arr.size()] if not arr.is_empty() else ""
		_relationship(c.regular_id, 3 if q >= 85 else (1 if q >= 60 else -1))
	else:
		reaction = line("praise" if q >= 80 else ("ok" if q >= 55 else "complain"))
	c.speak("praise" if q >= 70 else "complain", reaction, 3.5, Color(0.7, 1.0, 0.7) if q >= 70 else Color(1.0, 0.85, 0.6))
	Sfx.play("glass_place", -4.0)
	Sfx.play("till", -8.0)
	if tip > 0.0:
		Sfx.play("coins", -6.0)
	GameState.vibrate(25)
	if q >= 92:
		_perfect_pint_reaction(c)
	res["ok"] = true
	res["price"] = price
	res["tip"] = tip
	res["satisfaction"] = sat
	res["customer"] = c.display_name
	res["by"] = by.display_name if by else ""
	res["streak"] = streak if by == null else 0
	if by == null and streak in [3, 5, 10, 15, 20]:
		notify("On a roll! %d good pints in a row. Tips +%d%%" % [streak, int(minf(streak, 10) * 3)], "good")
	served.emit(res)
	if by:
		GameState.today["staff_served"] = int(GameState.today.get("staff_served", 0)) + 1
		if hud:
			hud.refresh_orders()
		return res
	if hud:
		hud.show_pour_result(res)
		hud.refresh_orders()
	_tutorial_event("served")
	return res


func _perfect_pint_reaction(served_to: Customer) -> void:
	# the Perfect Pint excerpt plays over the music (not more than once every so often), and the bar cheers
	var played := MusicDirector.play_stinger("t14")
	Sfx.play("cheer", -6.0 if played else -3.0)
	for c in customers:
		if c != served_to and c.global_position.distance_to(served_to.global_position) < 7.0 and randf() < 0.7:
			c.cheer()
	notify("A perfect pint! The bar raises a glass.", "good")


## Now and then someone near you passes a remark (recorded chatter lines only; no bubble spam).
func _ambient_chatter(delta: float) -> void:
	_chatter_t -= delta
	if _chatter_t > 0.0:
		return
	_chatter_t = _rng.randf_range(28.0, 55.0)
	var near: Array = []
	for c in customers:
		if c.state in ["mingle", "drinking", "stand_drink"] and c.global_position.distance_to(player.global_position) < 8.0:
			near.append(c)
	if not near.is_empty():
		var c: Customer = near[_rng.randi() % near.size()]
		c.speak("chatter", "", 4.0)


## A reaction from the room (used by Split the G).
func crowd_voice(tag: String) -> void:
	voices.crowd(tag)


func _on_upgrade_bought(id: String) -> void:
	var u := GameData.upgrade(id)
	voices.speak(null, "landlord", "upgrade", true)
	# substantial renovations get a proper moment with The Pub Gets Bigger
	if float(u.get("cost", 0)) >= 200.0:
		celebrate("The pub gets bigger!", "%s\n%s" % [u["name"], u.get("desc", "")], "t15")


func celebrate(title: String, body: String, track: String) -> void:
	if hud == null:
		return
	MusicDirector.start_override(track, "feature")
	hud.show_celebration(title, body, track)


func _check_awards() -> void:
	for a in GameData.awards:
		var id: String = a["id"]
		if id in GameState.objectives_done:
			continue
		var met := false
		if a.has("rep"):
			met = GameState.reputation >= float(a["rep"])
		elif a.has("stat"):
			met = float(GameState.stats.get(a["stat"], 0)) >= float(a["at"])
		if met:
			GameState.objectives_done.append(id)
			GameState.earn(float(a.get("cash", 0)), "prizes")
			GameState.award_earned.emit(id)
			celebrate("Award: %s" % a["name"], "%s\nPrize: €%d" % [a["desc"], int(a.get("cash", 0))], "t16")
			return


func _update_music_context() -> void:
	var ctx := MusicDirector.context
	ctx["screen"] = "summary" if hud and hud.menu.visible and hud.menu._summary_mode else "world"
	ctx["phase"] = GameState.phase
	ctx["hour"] = GameState.hour
	ctx["weekday"] = GameState.weekday()
	ctx["weather"] = GameState.weather
	ctx["customers"] = customers.size()
	ctx["capacity_frac"] = float(customers.size()) / maxf(1.0, max_customers())
	ctx["atmosphere"] = GameState.atmosphere()
	var served := int(GameState.today.get("served", 0))
	ctx["satisfaction"] = float(GameState.today.get("satisfaction_sum", 0.0)) / maxf(1.0, served) if served > 0 else 60.0
	# keep the chatter down while a vocal song is being sung so the words carry
	var vocal: bool = live != null and live.playing and MusicDirector.tracks.get(live.now_playing, {}).get("vocal", false)
	# a quiet murmur for a few people, the busy room fading in as the pub fills
	var fill := clampf(customers.size() / 10.0, 0.0, 1.0) * (0.35 if vocal else 0.8)
	var busy := clampf((customers.size() - 3) / 6.0, 0.0, 1.0)
	# the room's murmur sits under the words, on the ambience bus (it ducks when someone speaks)
	Sfx.set_loop("crowd_quiet", "quiet_crowd_loop", minf(fill * 2.0, 0.6) * (1.0 - busy) * 0.6, "Ambience")
	Sfx.set_loop("crowd", "crowd_loop", fill * busy * 0.5, "Ambience")


func _relationship(id: String, delta: int, chat := false) -> void:
	var r := int(GameState.relationships.get(id, 0))
	if chat:
		var key := "chat_%s_%d" % [id, GameState.day]
		if GameState.tutorial.has(key):
			return
		GameState.tutorial[key] = true
	GameState.relationships[id] = clampi(r + delta, -10, 100)


func cleanliness() -> float:
	var dirty := 0
	for g in loose_glasses:
		dirty += 1
	# fresh paint and tiles show the mess less (dirt_rate_mult is negative)
	var k := maxf(0.2, 1.0 + GameState.get_mod("dirt_rate_mult"))
	return clampf(100.0 - (spills.size() * 9.0 + dirty * 3.0) * k, 0.0, 100.0)


# ------------------------------------------------------------------ spills
func add_spill(pos: Vector3, size := 0.12) -> void:
	if randf() < -GameState.get_mod("spill_mess_mult"):
		return
	var s := MeshKit.cyl(self, size, size, 0.004, pos + Vector3(0, 0.003, 0), MeshKit.mat("spill"), 16)
	s.scale = Vector3(1.0, 1.0, randf_range(0.6, 1.0))
	spills.append(s)
	Interactable.make(s, pos + Vector3(0, 0.05, 0), "spill", func(): return "Hold to wipe the spill", func(): _wipe(s), 0.9, 1.8)


func _wipe(s: Node3D) -> void:
	spills.erase(s)
	s.queue_free()
	Sfx.play("squeak", -4.0)
	GameState.stats["spills_cleaned"] = int(GameState.stats["spills_cleaned"]) + 1


# ------------------------------------------------------------------ day flow
func _process(delta: float) -> void:
	run_time += delta
	if GameState.phase != "prep":
		var gh := delta / GameState.seconds_per_game_hour()
		GameState.hour += gh
		var close_h := float(GameData.econ("close_hour", 24.0))
		var last_h := float(GameData.econ("last_orders_hour", 23.5))
		if GameState.phase == "open" and GameState.hour >= last_h:
			_last_orders()
		if GameState.phase == "last_orders" and GameState.hour >= close_h:
			GameState.phase = "closing"
			voices.speak(null, "landlord", "closing", true)
			for c in customers.duplicate():
				if c.state in ["queue", "wait_order"]:
					c.say("Ah, closing time. Night!", 2.0)
					c.leave()
		if GameState.hour >= close_h + 0.75:
			# nobody stays past a quarter to one
			for c in customers.duplicate():
				if c.state != "walk":
					c.leave()
		_maybe_spawn(delta)
		_dispatch(delta)
		_ambient_chatter(delta)
	# settle every pint in the building
	var settle_s := float(GameData.econ("settle_seconds", 12.0))
	for g in settle_slots:
		if g != null:
			g.contents.settle(delta, settle_s)
	if player.held:
		player.held.contents.settle(delta, settle_s)
	for c in customers:
		if c.glass:
			c.glass.contents.settle(delta, settle_s)
	player.update_focus()
	_update_lighting(false)
	_update_audio()
	_update_door(delta)
	if fast_forward and not can_fast_forward():
		set_fast_forward(false)
	_autosave_t += delta
	if _autosave_t > 45.0:
		_autosave_t = 0.0
		autosave()
	_check_church_bell()
	_update_music_context()
	_award_t -= delta
	if _award_t <= 0.0:
		_award_t = 2.0
		if not in_minigame():
			_check_awards()
			GameState.check_goals()
			stories.check()
			stories.refresh_markers()
	_update_guide(delta)


func _last_orders() -> void:
	if GameState.phase != "open":
		return
	GameState.phase = "last_orders"
	Sfx.play("till", -2.0)
	voices.speak(null, "landlord", "last_orders", true)
	notify("Last orders, please! No new customers tonight.", "info")


func can_fast_forward() -> bool:
	if in_minigame():
		return false
	for c in customers:
		if c.state in ["wait_order", "wait_drink", "queue"]:
			return false
	return true


func set_fast_forward(on: bool) -> void:
	fast_forward = on and can_fast_forward()
	Engine.time_scale = 3.0 if fast_forward else 1.0


func close_day() -> void:
	if not customers.is_empty():
		return
	set_fast_forward(false)
	# glasses that weren't washed stay dirty overnight
	var dirty := loose_glasses.size() + player.dirty_stack.size()
	for g in settle_slots:
		if g != null:
			dirty += 1
	if player.held:
		dirty += 1
	for st in staff_npcs:
		dirty += st.glass_count()
	GameState.tutorial["dirty_overnight"] = dirty
	if live:
		live.stop_now()
	var finished_day := GameState.day
	GameState.check_goals(true)
	var goals: Array = GameState.daily_goals().duplicate(true)
	var best_streak := int(GameState.today.get("best_streak", 0))
	var staff_served := int(GameState.today.get("staff_served", 0))
	var sang := bool(GameState.today.get("singalong", false))
	var summary := GameState.end_day()
	summary["milestone"] = finished_day in [1, 3, 7, 14, 21, 30, 50, 75, 100] or sang
	summary["goals"] = goals
	summary["best_streak"] = best_streak
	summary["staff_served"] = staff_served
	MusicDirector.context["milestone"] = summary["milestone"]
	if hud:
		hud.show_day_summary(summary)


func autosave() -> void:
	# mid-day saves keep the clock, cash and stock; the room resets to opening state on load
	GameState.save_game()


func _update_door(delta: float) -> void:
	var door: Node3D = info.get("door")
	if door == null:
		return
	_door_anim = maxf(0.0, _door_anim - delta)
	var target := -1.2 if _door_anim > 0.0 else 0.0
	door.rotation.y = lerp(door.rotation.y, target, minf(1.0, delta * 4.0))


func _check_church_bell() -> void:
	var h := int(GameState.hour)
	if GameState.phase != "prep" and h != _church_rung and GameState.hour - h < 0.02 and h in [18, 21, 24]:
		_church_rung = h
		Sfx.play("church_bell", -14.0, 0.0, "Ambience")


func _update_audio() -> void:
	var rain := 0.0
	if GameState.weather == "rain":
		rain = 0.5
	elif GameState.weather == "storm":
		rain = 0.85
	Sfx.set_loop("rain", "rain_loop", rain, "Weather")
	var lit := GameState.has_upgrade("fireplace")
	if lit and not _fire_audio.playing:
		_fire_audio.play()
	elif not lit and _fire_audio.playing:
		_fire_audio.stop()


func _update_lighting(force: bool) -> void:
	var h := GameState.hour
	var dusk := clampf((h - 17.5) / 2.5, 0.0, 1.0)  # 0 = late afternoon, 1 = night
	env.background_color = Color(0.36, 0.4, 0.46).lerp(Color(0.02, 0.025, 0.045), dusk)
	env.fog_light_color = env.background_color
	var lamps_restored := GameState.has_upgrade("lamps")
	var lamp_e := (1.3 if lamps_restored else 0.7) * (0.8 + 0.2 * dusk)
	for l in info["lamps"]:
		(l as OmniLight3D).light_energy = lamp_e
		(l as OmniLight3D).omni_range = 4.8 if lamps_restored else 3.2
	env.ambient_light_energy = lerpf(0.6, 0.42, dusk) + (0.08 if lamps_restored else 0.0)
	env.ambient_light_color = Color(0.55, 0.5, 0.45).lerp(Color(0.5, 0.38, 0.28), dusk)
	var wet := 1.0 if GameState.weather in ["rain", "storm"] else 0.0
	for m in info["window_mats"]:
		(m as ShaderMaterial).set_shader_parameter("glow", Color(0.45, 0.5, 0.55).lerp(Color(0.02, 0.03, 0.05), dusk))
		(m as ShaderMaterial).set_shader_parameter("rain", wet)
	for sl in info["street_lights"]:
		(sl as OmniLight3D).visible = dusk > 0.3
	for r in info["rain"]:
		(r as CPUParticles3D).emitting = GameState.weather in ["rain", "storm"]
	var fl: OmniLight3D = info.get("fire_light")
	if fl and fl.is_visible_in_tree():
		fl.light_energy = 1.4 + 0.35 * sin(Time.get_ticks_msec() * 0.011) + 0.2 * sin(Time.get_ticks_msec() * 0.027)
	var hands: Array = info.get("clock_hands", [])
	if hands.size() == 2:
		(hands[0] as Node3D).rotation.z = -fmod(h, 12.0) / 12.0 * TAU
		(hands[1] as Node3D).rotation.z = -fmod(h, 1.0) * TAU


# ------------------------------------------------------------------ upgrades
func _on_upgrades_changed() -> void:
	var before := rack_clean + _glasses_out()
	var total := GameState.glasses_total()
	if total > before:
		rack_clean += total - before
	apply_upgrades()
	_refresh_rack()


func _glasses_out() -> int:
	return glass_count_check() - rack_clean


func apply_upgrades() -> void:
	for id in info["upgrade_show"].keys():
		var owned := GameState.has_upgrade(id)
		for n in info["upgrade_show"][id]:
			(n as Node3D).visible = owned
	for id in info["upgrade_hide"].keys():
		var owned2 := GameState.has_upgrade(id)
		for n in info["upgrade_hide"][id]:
			(n as Node3D).visible = not owned2
	var fl: OmniLight3D = info.get("fire_light")
	if fl:
		fl.visible = GameState.has_upgrade("fireplace")
	var name_l: Label3D = info.get("facade_label")
	if name_l:
		name_l.text = GameState.pub_name
	_refresh_stock_pile()
	_update_lighting(true)


func _refresh_stock_pile() -> void:
	var pile: Node3D = info.get("stock_pile")
	if pile == null:
		return
	for ch in pile.get_children():
		ch.queue_free()
	var i := 0
	for id in GameState.stock.keys():
		if not GameState.drink_available(id):
			continue
		for k in mini(int(GameState.stock[id]), 4):
			var p := Vector3((i % 3) * 0.45 - 0.45, 0, -(i / 3) * 0.45)
			if GameData.drink(id).get("stock_unit", "keg") in ["keg", "cask"]:
				MeshKit.cyl(pile, 0.2, 0.2, 0.6, p + Vector3(0, 0.3, 0), MeshKit.mat("steel_keg"), 16)
			else:
				MeshKit.box(pile, Vector3(0.4, 0.3, 0.3), p + Vector3(0, 0.15, 0), MeshKit.mat("cardboard"))
			i += 1


# ------------------------------------------------------------------ what to do next
func _on_goal_done(g: Dictionary) -> void:
	notify("Goal complete: %s  +€%d" % [g["text"], int(g["reward"])], "good")
	Sfx.play("coins", -4.0)
	if hud and hud.has_method("refresh_goals"):
		hud.refresh_goals()


func _build_guide_marker() -> void:
	guide_marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.0
	cone.height = 0.22
	cone.radial_segments = 12
	cone.rings = 1
	guide_marker.mesh = cone
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.78, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true          # seen through the bar and the crowd
	m.render_priority = 10
	guide_marker.material_override = m
	guide_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	guide_marker.visible = false
	add_child(guide_marker)


func _update_guide(delta: float) -> void:
	_guide_t -= delta
	if _guide_t <= 0.0:
		_guide_t = 0.4
		_guide = next_step()
	if guide_marker == null:
		return
	var on: bool = bool(GameState.settings.get("show_guide", true)) and _guide.has("pos") and not in_minigame() \
		and not (pour and pour.active)
	if on:
		var at: Vector3 = _guide["pos"]
		on = Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length() > 1.3
		var bob := sin(run_time * 3.0) * 0.05
		guide_marker.global_position = at + Vector3(0, 0.32 + bob, 0)
		guide_marker.rotation.y += delta * 1.5
		var mat := guide_marker.material_override as StandardMaterial3D
		mat.albedo_color.a = 0.65 + sin(run_time * 3.0) * 0.25
	guide_marker.visible = on


func _tap_spot(id: String) -> Vector3:
	var t: Dictionary = info["taps"].get(id, {})
	return (t["glass"] as Vector3) + Vector3(0, 0.25, 0) if not t.is_empty() else Vector3(PubLayout.TAP_X.get(id, -1.0), PubLayout.BAR_TOP, PubLayout.TAP_Z)


func _above(c: Node3D) -> Vector3:
	return c.global_position + Vector3(0, 1.85, 0)


## The single most useful thing for the player to do now: {"text": ..., "pos": where (optional)}.
func next_step() -> Dictionary:
	var phase := GameState.phase
	var sign_pos := PubLayout.DOOR_SIGN_POS
	if phase == "prep":
		for id in PubLayout.KEG_POS.keys():
			if GameState.drink_available(id) and GameState.serves_left(id) < 4.0 and int(GameState.stock.get(id, 0)) > 0:
				return {"text": "Change the %s keg in the cellar before opening" % GameData.drink(id).get("short", id), "pos": PubLayout.KEG_POS[id] + Vector3(0, 0.7, 0)}
		if GameState.line_penalty() > 0.0 and GameState.can_afford(float(GameData.econ("line_clean_cost", 8))):
			return {"text": "The beer lines need cleaning (cellar) before you open", "pos": LINE_CLEAN_POS}
		return {"text": "Flip the sign by the front door to open up", "pos": sign_pos}
	if phase in ["last_orders", "closing"] and customers.is_empty():
		return {"text": "Everyone's gone home: flip the sign to cash up", "pos": sign_pos}
	var held := player.held
	var mine: Array = []          # customers waiting on a drink from the player
	for c in customers:
		if c.state == "wait_drink" and staff_serving(c) == null:
			mine.append(c)
	mine.sort_custom(func(a, b): return a.patience_frac() < b.patience_frac())
	var needs := func(drink: String) -> Customer:
		for c in mine:
			if c.drink_id == drink:
				return c
		return null
	if held != null and not held.contents.is_empty():
		var hc := held.contents
		if hc.serve == "stout" and hc.stage == 2:
			if hc.settled_fraction() < 0.97 and free_settle_slot() >= 0:
				return {"text": "Leave the stout on the drip tray to settle", "pos": PubLayout.SETTLE_SLOTS[free_settle_slot()]}
			return {"text": "Top up the stout at the tap", "pos": _tap_spot(hc.drink_id)}
		var who: Customer = needs.call(hc.drink_id)
		if who != null:
			return {"text": "Serve %s their %s" % [who.display_name, GameData.drink(hc.drink_id).get("short", "")], "pos": _above(who)}
		return {"text": "Nobody's waiting on that one: pour it away at the sink", "pos": PubLayout.SINK_POS}
	# pints on the drip tray
	var settling: PintGlass = null
	var settling_i := -1
	for i in settle_slots.size():
		var g: PintGlass = settle_slots[i]
		if g != null:
			if g.contents.settled_fraction() >= 0.99 and player.has_hands_free():
				return {"text": "Pick up the settled stout and top it up", "pos": PubLayout.SETTLE_SLOTS[i]}
			settling = g
			settling_i = i
	if not player.dirty_stack.is_empty():
		return {"text": "Wash the empties at the sink (%d)" % player.dirty_stack.size(), "pos": PubLayout.SINK_POS}
	var covered := {}
	for g in settle_slots:
		if g != null:
			covered[g.contents.drink_id] = int(covered.get(g.contents.drink_id, 0)) + 1
	var unpoured: Customer = null
	for c in mine:
		if int(covered.get(c.drink_id, 0)) > 0:
			covered[c.drink_id] = int(covered[c.drink_id]) - 1
		elif unpoured == null:
			unpoured = c
	if held != null:
		if unpoured != null:
			return {"text": "Pour %s's %s at the tap" % [unpoured.display_name, GameData.drink(unpoured.drink_id).get("short", "")], "pos": _tap_spot(unpoured.drink_id)}
		if mine.is_empty():
			return {"text": "Take an order, or put the glass back on the rack", "pos": PubLayout.RACK_POS}
	for c in customers:
		if c.state == "wait_order" and staff_serving(c) == null:
			return {"text": "Take %s's order" % c.display_name, "pos": _above(c)}
	if unpoured != null:
		if rack_clean > 0:
			var gk := str(GameData.drink(unpoured.drink_id).get("glass", "pint"))
			return {"text": "Grab a clean %s for %s's %s" % ["tumbler" if gk == "tumbler" else "glass", unpoured.display_name, GameData.drink(unpoured.drink_id).get("short", "")], "pos": PubLayout.RACK_POS}
		if not loose_glasses.is_empty():
			return {"text": "Out of clean glasses! Collect empties to wash", "pos": loose_glasses[0].global_position}
	if settling != null:
		return {"text": "The stout is settling (%d%%). Top it up when it's dark" % int(settling.contents.settled_fraction() * 100.0), "pos": PubLayout.SETTLE_SLOTS[settling_i]}
	for id in GameState.available_drinks():
		if GameState.serves_left(id) < 4.0:
			var spare := int(GameState.stock.get(id, 0))
			if spare > 0 and PubLayout.KEG_POS.has(id):
				return {"text": "The %s keg's nearly out: change it in the cellar" % GameData.drink(id).get("short", id), "pos": PubLayout.KEG_POS[id] + Vector3(0, 0.7, 0)}
			if spare <= 0:
				return {"text": "Running low on %s: order more at the stock pile" % GameData.drink(id).get("short", id), "pos": PubLayout.STOCK_PILE + Vector3(0, 0.7, 0)}
	var collector := GameState.staff_count("collector") > 0
	if not collector and (loose_glasses.size() >= 2 or (rack_clean <= 2 and not loose_glasses.is_empty())):
		var near := loose_glasses[0]
		for g in loose_glasses:
			if g.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
				near = g
		return {"text": "Collect the empty glasses (%d out)" % loose_glasses.size(), "pos": near.global_position}
	if not collector and not spills.is_empty():
		return {"text": "Wipe up the spill", "pos": spills[0].global_position}
	if phase == "open" and customers.is_empty():
		return {"text": "Quiet for now: customers will be in soon", "idle": true}
	if phase != "open":
		return {"text": "Last orders: see the last few out the door", "idle": true}
	for c in customers:
		if c.regular_id != "" and c.state in ["drinking", "stand_drink", "mingle"] and not stories.chapter_ready(c.regular_id).is_empty():
			return {"text": "%s has something to tell you" % c.display_name.split(" ")[0], "pos": _above(c)}
	if match_day and match_day.on:
		return {"text": "Match on: %s" % match_day.score_text(), "idle": true}
	var favours := stories.open_favours()
	if not favours.is_empty():
		return {"text": "A favour for %s: %s" % [favours[0]["name"], favours[0]["text"]], "idle": true}
	for c in customers:
		if c.regular_id != "" and c.state in ["drinking", "stand_drink"] and not GameState.today.get("chatted", []).has(c.regular_id):
			return {"text": "All in hand. Have a chat with %s" % c.display_name, "pos": _above(c)}
	return {"text": "All in hand. Throw some darts or have a pint by the fire", "idle": true}


# ------------------------------------------------------------------ tutorial & messages
func notify(text: String, kind := "info") -> void:
	GameState.notify(text, kind)


func subtitle(who: String, text: String, c: Node3D) -> void:
	if hud and player and c.global_position.distance_to(player.global_position) < 7.0:
		hud.subtitle(who, text)


func _tutorial_event(ev: String) -> void:
	if GameState.tutorial.get("done", false) or _restoring:
		return
	var steps := {
		"start": "Welcome to The Crooked Shamrock! Walk round the end of the bar to the front door and flip the sign to OPEN.",
		"opened": "You're open. Your first customer is on the way. Head back behind the bar.",
		"customer_at_bar": "A customer is waiting at the bar (look for the !). Walk up behind the bar and take their order.",
		"order": "Grab a clean pint glass from the rack on the back counter behind you.",
		"glass": "Take the glass to the brass stout tap on the bar and start pouring.",
		"settle": "While it settles you can serve, wash glasses or wait. Pick it up when it's dark, then top it up at the tap.",
		"served": "Paid! Earnings go in the till. Open the menu (top right) to buy your first upgrade when you can afford it.",
		"dirty": "Customers leave empty glasses behind. Collect them and wash them at the sink beside the rack.",
		"washed": "Clean glass back on the rack. That's the loop! The gold marker always shows what to do next. At midnight everyone heads home: then flip the sign again to cash up.",
	}
	var order := ["start", "opened", "customer_at_bar", "order", "glass", "settle", "served", "dirty", "washed"]
	var idx := order.find(ev)
	if idx < 0 or idx < tutorial_step:
		return
	if ev == "washed" and tutorial_step < order.find("served") + 1:
		return      # pouring a bad first pint away and washing it isn't the end of the lesson
	tutorial_step = idx + 1
	if hud:
		hud.set_tip(steps[ev])
	if ev == "washed":
		GameState.tutorial["done"] = true


## Bunting and shamrock go up on festival days.
func _set_festival_look() -> void:
	var on := not GameState.festival_today().is_empty()
	for n in info.get("festival", []):
		(n as Node3D).visible = on


func on_ready_with_hud() -> void:
	_set_sign(GameState.phase != "prep")
	if GameState.phase == "prep":
		notify("Day %d · %s · %s" % [GameState.day, GameState.weekday_name(), GameState.weather.capitalize()])
		var fest := GameState.festival_today()
		if not fest.is_empty():
			celebrate(str(fest["name"]), str(fest["desc"]), "t05")
		var m := GameState.match_today()
		if not m.is_empty():
			notify("Match day! The game's on the big screen from %d:00." % int(m[0]), "good")
	_set_festival_look()
	start_tutorial()


func start_tutorial() -> void:
	if GameState.tutorial.get("done", false):
		return
	if GameState.phase == "prep":
		_tutorial_event("start")
