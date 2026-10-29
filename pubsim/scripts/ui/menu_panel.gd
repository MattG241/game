class_name MenuPanel
extends Control
## Pause menu with management tabs. Built from code; every button performs a real action.

var hud: HUD
var tab := "upgrades"
var content: VBoxContainer
var scroll: ScrollContainer
var title: Label
var tab_bar: HBoxContainer
var _summary_mode := false

const TABS := [["upgrades", "Upgrades"], ["stock", "Stock"], ["prices", "Prices"], ["ledger", "Ledger"], ["events", "Live music"], ["music", "Jukebox"], ["activities", "Pub games"], ["settings", "Settings"], ["game", "Game"]]

var _event_day := -1
var _now_label: Label
var _now_bar: ProgressBar
var _refresh_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 10
	panel.offset_bottom = -10
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	title = UITheme.label(GameState.pub_name, 34, UITheme.GOLD, MeshKit.font_title())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UITheme.button("Back to the bar", _close, 24)
	close.custom_minimum_size = Vector2(240, 60)
	head.add_child(close)
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	vb.add_child(tab_bar)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)


func _close() -> void:
	if _summary_mode:
		return
	hud.close_menu()


func open(t: String) -> void:
	_summary_mode = false
	visible = true
	tab_bar.visible = true
	title.text = GameState.pub_name
	_build_tabs()
	show_tab(t)


func _build_tabs() -> void:
	for ch in tab_bar.get_children():
		ch.queue_free()
	for t in TABS:
		var id: String = t[0]
		var b := UITheme.button(t[1], func(): show_tab(id), 19)
		b.custom_minimum_size = Vector2(118, 54)
		b.toggle_mode = true
		b.button_pressed = id == tab
		b.set_meta("tab", id)
		tab_bar.add_child(b)


func show_tab(t: String) -> void:
	tab = t
	for b in tab_bar.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.get_meta("tab", "") == t)
	for ch in content.get_children():
		ch.queue_free()
	scroll.scroll_vertical = 0
	match t:
		"upgrades":
			_upgrades()
		"stock":
			_stock()
		"prices":
			_prices()
		"ledger":
			_ledger()
		"settings":
			_settings()
		"activities":
			_activities()
		"events":
			_events()
		"music":
			_jukebox()
		"game":
			_game()


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	content.add_child(h)
	return h


func _card(bg := Color(0.18, 0.11, 0.06, 0.95)) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_box(bg, Color(0.45, 0.32, 0.15), 14, 2))
	content.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _text(parent: Node, t: String, size := 22, color := UITheme.CREAM) -> Label:
	var l := UITheme.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ upgrades
func _upgrades() -> void:
	_text(content, "Cash: €%.2f   ·   Upgrades change the pub you can see and how it runs." % GameState.cash, 22, UITheme.GOLD)
	var list := GameData.upgrades.duplicate()
	list.sort_custom(func(a, b): return [int(GameState.has_upgrade(a["id"])), float(a["cost"])] < [int(GameState.has_upgrade(b["id"])), float(b["cost"])])
	for u in list:
		var owned := GameState.has_upgrade(u["id"])
		var v := _card(Color(0.1, 0.22, 0.13, 0.95) if owned else Color(0.18, 0.11, 0.06, 0.95))
		var h := HBoxContainer.new()
		v.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		_text(info, "%s   [%s]" % [u["name"], u.get("category", "")], 26, UITheme.GOLD)
		_text(info, u.get("desc", ""), 20)
		var eff := _effects_text(u.get("effects", {}))
		if eff != "":
			_text(info, eff, 18, Color(0.6, 0.9, 0.65))
		var req: String = u.get("requires", "")
		if req != "" and not GameState.has_upgrade(req):
			_text(info, "Requires: %s" % GameData.upgrade(req).get("name", req), 18, Color(1, 0.6, 0.5))
		var id: String = u["id"]
		if owned:
			var l := UITheme.label("Owned", 24, Color(0.6, 0.95, 0.6))
			l.custom_minimum_size = Vector2(170, 0)
			h.add_child(l)
		else:
			var b := UITheme.button("Buy €%d" % int(u["cost"]), func():
				if GameState.buy_upgrade(id):
					Sfx.play("ui_buy", -2.0)
					show_tab("upgrades"), 24)
			b.custom_minimum_size = Vector2(190, 70)
			b.disabled = not GameState.can_buy_upgrade(id)
			h.add_child(b)


func _effects_text(e: Dictionary) -> String:
	var names := {
		"atmosphere": "Atmosphere +%d", "tips_mult": "Tips +%d%%", "glasses": "+%d glasses", "arrival_mult": "Footfall +%d%%",
		"beer_quality": "Pint quality +%d", "rain_bonus": "Rainy-night trade +%d%%", "stay_mult": "Customers linger +%d%%",
		"dirt_rate_mult": "Stays cleaner", "spill_mess_mult": "Spills drain away", "capacity": "+%d seats",
		"freshness_decay_mult": "Kegs stay fresh longer", "event_draw": "Event crowds +%d%%", "rep_gain": "Reputation +%d/day",
	}
	var parts := []
	for k in e.keys():
		if not names.has(k):
			continue
		var fmt: String = names[k]
		var v := float(e[k])
		if fmt.contains("%%"):
			v *= 100.0
		parts.append(fmt % int(round(v)) if fmt.contains("%d") else fmt)
	return " · ".join(parts)


# ------------------------------------------------------------------ stock
func _stock() -> void:
	_text(content, "Stock arrives tomorrow morning. Delivery fee €%d per order. Change empty kegs in the cellar." % int(GameData.econ("delivery_fee", 6)), 20, UITheme.MUTED)
	for d in GameData.drinks:
		var id: String = d["id"]
		if not GameState.drink_available(id):
			continue
		var v := _card()
		var h := HBoxContainer.new()
		v.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		_text(info, d["name"], 26, UITheme.GOLD)
		var left := GameState.serves_left(id)
		var fresh := int(GameState.freshness(id) * 100)
		_text(info, "On tap: %d serves (%d%% fresh)  ·  Spare: %d %s  ·  Arriving: %d" % [int(left), fresh, int(GameState.stock.get(id, 0)), d["stock_unit"], GameState.pending_delivery(id)], 20)
		_text(info, "€%d per %s (%d serves, €%.2f each)" % [int(d["stock_cost"]), d["stock_unit"], int(d["units_per_stock"]), GameState.unit_cost(id)], 18, UITheme.MUTED)
		for n in [1, 3]:
			var packs: int = n
			var cost := float(d["stock_cost"]) * packs + float(GameData.econ("delivery_fee", 6))
			var b := UITheme.button("Order %d (€%d)" % [packs, int(cost)], func():
				if GameState.order_stock(id, packs):
					Sfx.play("ui_buy", -4.0)
					GameState.notify("Ordered %d × %s for tomorrow." % [packs, d["stock_unit"]], "good")
				show_tab("stock"), 20)
			b.custom_minimum_size = Vector2(190, 64)
			b.disabled = not GameState.can_afford(cost)
			h.add_child(b)


# ------------------------------------------------------------------ prices
func _prices() -> void:
	_text(content, "Higher prices mean more profit per drink but lower satisfaction and tips. Very high prices turn people away.", 20, UITheme.MUTED)
	for d in GameData.drinks:
		var id: String = d["id"]
		if not GameState.drink_available(id):
			continue
		var v := _card()
		var h := HBoxContainer.new()
		v.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var price := GameState.price_of(id)
		var cost := GameState.unit_cost(id)
		var margin := (price - cost) / price * 100.0
		_text(info, "%s   €%.2f" % [d["name"], price], 26, UITheme.GOLD)
		_text(info, "Cost €%.2f  ·  Margin %d%%  ·  Usual price €%.2f" % [cost, int(margin), float(d["price"])], 20)
		for step in [-0.5, -0.1, 0.1, 0.5]:
			var st: float = step
			var b := UITheme.button(("%+.1f" % st), func():
				GameState.set_price(id, GameState.price_of(id) + st)
				show_tab("prices"), 22)
			b.custom_minimum_size = Vector2(96, 60)
			h.add_child(b)


# ------------------------------------------------------------------ ledger
func _ledger() -> void:
	var t := GameState.today
	var v := _card()
	_text(v, "Today so far (Day %d, %s)" % [GameState.day, GameState.weekday_name()], 26, UITheme.GOLD)
	var lines := [
		["Drink sales", t["sales"]], ["Tips", t["tips"]], ["Cost of drinks sold", -float(t["cogs"])],
		["Stock ordered", -float(t["stock_spend"])], ["Upgrades", -float(t["upgrade_spend"])],
	]
	for ln in lines:
		_text(v, "%-24s €%.2f" % [ln[0], float(ln[1])], 22)
	_text(v, "Served %d · Walk-outs %d · Complaints %d · Wasted %.1f serves" % [int(t["served"]), int(t["walkouts"]), int(t.get("complaints", 0)), float(t["wasted_units"])], 20, UITheme.MUTED)
	var avg_q := float(t["quality_sum"]) / maxi(1, int(t["pours"]))
	_text(v, "Average pint quality %d · Rent €%d and utilities €%d are paid at closing" % [int(avg_q), int(GameData.econ("rent_per_day", 30)), int(GameData.econ("utilities_per_day", 8) + GameState.get_mod("utilities"))], 20, UITheme.MUTED)
	if not GameState.history.is_empty():
		var hv := _card()
		_text(hv, "Previous days", 26, UITheme.GOLD)
		for i in range(GameState.history.size() - 1, maxi(-1, GameState.history.size() - 8), -1):
			var s: Dictionary = GameState.history[i]
			_text(hv, "Day %d (%s): income €%.2f · expenses €%.2f · profit €%.2f · served %d · rep %+.1f" % [int(s["day"]), str(s["weekday"]).substr(0, 3), float(s["income"]), float(s["expenses"]), float(s["profit"]), int(s["served"]), float(s["rep_change"])], 20)
	var st := _card()
	_text(st, "Career", 26, UITheme.GOLD)
	var gs := GameState.stats
	_text(st, "Pints poured %d · Perfect pints %d · Best pour %d · Customers served %d · Glasses washed %d · Days run %d" % [int(gs["pints_poured"]), int(gs["perfect_pints"]), int(gs["best_pour"]), int(gs["served"]), int(gs["glasses_washed"]), int(gs["days"])], 20)


# ------------------------------------------------------------------ live music bookings
func _events() -> void:
	var live: LiveMusic = hud.world.live
	if _event_day < GameState.day:
		_event_day = GameState.day
	_text(content, "Book musicians for tonight or the coming week. They play from 8pm to 11pm, draw a crowd, lift the atmosphere and make people stay longer. Acts suit some nights better than others. Cancelling before the night refunds the fee.", 20, UITheme.MUTED)
	var days := HBoxContainer.new()
	days.add_theme_constant_override("separation", 8)
	content.add_child(days)
	var names: Array = GameData.econ("weekday_names", [])
	for d in range(GameState.day, GameState.day + 7):
		var wd := (d + 2) % 7
		var booked: String = GameState.bookings.get(str(d), "")
		var label := "%s\nDay %d%s" % [str(names[wd]).substr(0, 3), d, "\nbooked" if booked != "" else ""]
		var dd := d
		var b := UITheme.button(label, func():
			_event_day = dd
			show_tab("events"), 18)
		b.custom_minimum_size = Vector2(118, 86)
		b.toggle_mode = true
		b.set_pressed_no_signal(d == _event_day)
		days.add_child(b)
	var day := _event_day
	var wd2 := (day + 2) % 7
	var booked_id: String = GameState.bookings.get(str(day), "")
	if booked_id != "":
		var ev: Dictionary = GameData.events_by_id.get(booked_id, {})
		var v := _card(Color(0.1, 0.22, 0.13, 0.95))
		_text(v, "Booked for %s (day %d): %s" % [names[wd2], day, ev.get("name", "")], 26, UITheme.GOLD)
		_text(v, "%s · plays %s" % [ev.get("kind", ""), MusicDirector.title_of(str(ev.get("track", "")))], 20)
		var c := UITheme.button("Cancel booking (refund €%d)" % int(ev.get("fee", 0)), func():
			if live.cancel(day):
				GameState.notify("Booking cancelled.", "info")
			show_tab("events"), 20)
		c.disabled = day == GameState.day and (live.playing or GameState.hour >= LiveMusic.EVENT_START - 0.5)
		v.add_child(c)
		return
	for ev in GameData.events:
		var id: String = ev["id"]
		var why := live.can_book(day, id)
		var eff := LiveMusic.effectiveness(ev, wd2)
		var v := _card()
		var h := HBoxContainer.new()
		v.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		_text(info, "%s   [%s]" % [ev["name"], ev["kind"]], 24, UITheme.GOLD)
		_text(info, ev["desc"], 19)
		var best: Array = ev.get("best_days", [])
		var best_txt := "any night" if best.is_empty() else ", ".join(best.map(func(x): return str(names[int(x)]).substr(0, 3)))
		_text(info, "Plays %s · Crowd x%.2f · Atmosphere +%d · Best: %s%s" % [MusicDirector.title_of(str(ev["track"])), float(ev["draw"]), int(ev["atmosphere"]), best_txt,
			"" if eff >= 1.0 else " (a %s is a quieter night for it)" % names[wd2]], 18, Color(0.6, 0.9, 0.65))
		if why != "":
			_text(info, why, 18, Color(1, 0.65, 0.5))
		var b := UITheme.button("Book €%d" % int(ev["fee"]), func():
			if live.book(day, id):
				Sfx.play("ui_buy", -4.0)
				GameState.notify("%s booked for day %d." % [ev["name"], day], "good")
			show_tab("events"), 22)
		b.custom_minimum_size = Vector2(170, 66)
		b.disabled = why != ""
		h.add_child(b)


# ------------------------------------------------------------------ jukebox
func _jukebox() -> void:
	var md := MusicDirector
	var now := _card(Color(0.08, 0.2, 0.12, 0.96))
	_text(now, "Now playing", 20, UITheme.MUTED)
	_now_label = _text(now, "", 28, UITheme.GOLD)
	_now_bar = ProgressBar.new()
	_now_bar.show_percentage = false
	_now_bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.GOLD
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.03, 0.02)
	bg.set_corner_radius_all(6)
	_now_bar.add_theme_stylebox_override("fill", fill)
	_now_bar.add_theme_stylebox_override("background", bg)
	now.add_child(_now_bar)
	_refresh_now()
	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 10)
	now.add_child(ctl)
	var auto_b := UITheme.button("Automatic", func():
		md.set_mode("auto")
		show_tab("music"), 20)
	auto_b.toggle_mode = true
	auto_b.set_pressed_no_signal(md.mode == "auto")
	ctl.add_child(auto_b)
	var man_b := UITheme.button("My choice", func():
		var id: String = md.manual_id if md.manual_id != "" else (md.current_id if md.current_id != "" else "t03")
		md.play_track(id)
		show_tab("music"), 20)
	man_b.toggle_mode = true
	man_b.set_pressed_no_signal(md.mode == "manual")
	ctl.add_child(man_b)
	var pause_b := UITheme.button("Resume" if md.paused else "Pause", func():
		md.toggle_pause()
		show_tab("music"), 20)
	pause_b.disabled = md.mode != "manual"
	ctl.add_child(pause_b)
	ctl.add_child(UITheme.button("Skip", func():
		md.skip()
		show_tab("music"), 20))
	var vh := HBoxContainer.new()
	now.add_child(vh)
	vh.add_child(UITheme.label("Music volume", 20))
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = float(GameState.settings.get("vol_music", 0.8))
	vs.custom_minimum_size = Vector2(380, 44)
	vs.value_changed.connect(func(x): GameState.set_setting("vol_music", x))
	vh.add_child(vs)
	var note := "Automatic picks music to suit the time, weather and how busy you are. Live musicians always take over while they play." if md.mode == "auto" else "Your playlist plays in order. Live musicians still take over while they perform."
	_text(now, note, 18, UITheme.MUTED)
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 8)
	content.add_child(cats)
	var cat_list := [["all", "All 20"]]
	for k in md.categories.keys():
		cat_list.append([k, md.categories[k]])
	for c in cat_list:
		var cid: String = c[0]
		var b := UITheme.button(str(c[1]), func():
			md.set_playlist(cid)
			show_tab("music"), 18)
		b.toggle_mode = true
		b.set_pressed_no_signal(md.playlist == cid)
		cats.add_child(b)
	for t in md.track_list:
		if md.playlist != "all" and t["category"] != md.playlist:
			continue
		var playing_now: bool = md.current_id == t["id"] and md.situation.begins_with("manual")
		var v := _card(Color(0.12, 0.25, 0.15, 0.95) if md.current_id == t["id"] else Color(0.18, 0.11, 0.06, 0.95))
		var h := HBoxContainer.new()
		v.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		_text(info, md.title_of(t["id"]), 24, UITheme.GOLD if md.current_id == t["id"] else UITheme.CREAM)
		var dur := float(t.get("duration", 0))
		_text(info, "%s · %d:%02d%s" % [md.categories.get(t["category"], ""), int(dur) / 60, int(dur) % 60, " · vocal" if t.get("vocal", false) else ""], 18, UITheme.MUTED)
		var tid: String = t["id"]
		var pb := UITheme.button("Playing" if playing_now else "Play", func():
			md.play_track(tid)
			show_tab("music"), 20)
		pb.custom_minimum_size = Vector2(150, 60)
		h.add_child(pb)


func _refresh_now() -> void:
	if _now_label == null or not is_instance_valid(_now_label):
		return
	var md := MusicDirector
	var t := ""
	var live: LiveMusic = hud.world.live if hud.world else null
	if live and live.playing and live.now_playing != "":
		t = "Live in the pub: %s" % md.title_of(live.now_playing)
	elif md.current_id != "":
		t = md.title_of(md.current_id) + ("  (paused)" if md.paused else "")
	else:
		t = "Nothing playing"
	_now_label.text = t
	var len := 1.0
	var pos := 0.0
	if live and live.playing and live.now_playing != "":
		len = maxf(1.0, live.player3d.stream.get_length())
		pos = live.player3d.get_playback_position()
	elif md.current_id != "":
		len = maxf(1.0, float(md.tracks[md.current_id].get("duration", 1.0)))
		pos = md.position()
	_now_bar.max_value = len
	_now_bar.value = pos


func _process(delta: float) -> void:
	if not visible or tab != "music":
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_refresh_now()


# ------------------------------------------------------------------ activities
func _activity(title_t: String, desc: String, btn: String, cb: Callable, enabled := true, why := "") -> void:
	var v := _card()
	var h := HBoxContainer.new()
	v.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	_text(info, title_t, 26, UITheme.GOLD)
	_text(info, desc, 20)
	if not enabled and why != "":
		_text(info, why, 18, Color(1, 0.65, 0.5))
	var b := UITheme.button(btn, func():
		hud.close_menu()
		cb.call(), 22)
	b.custom_minimum_size = Vector2(200, 70)
	b.disabled = not enabled
	h.add_child(b)


func _activities() -> void:
	var w: World = hud.world
	var best := "No attempts yet." if GameState.best_split_mm < 0.0 else "Best: %.1f mm from the line in %d attempts." % [GameState.best_split_mm, int(GameState.stats["split_attempts"])]
	_activity("Split the Knot", "One gulp from a full pint: stop with the line between the stout and the head exactly on the bar through the Kilbrack Knot on the glass. Purely virtual practice. " + best, "Play", w.start_split)
	var has_board := GameState.has_upgrade("dartboard")
	_activity("Darts: 301", "A friendly game against %s. Drag to aim, let go to throw; the aim drifts, so time it. Wins %d of %d." % [w.darts_opponent_name(), int(GameState.stats["darts_wins"]), int(GameState.stats["darts_games"])],
		"Play", w.start_darts, has_board, "Buy the Dartboard & Oche upgrade first.")
	var closed := w.pub_closed_for_you()
	_activity("A pint by the fire", "Sit in the armchair and enjoy a pint at your own pace. %s" % ("The pub's closed, so it's a Kilbrack Stout." if closed else "You're working, so it's an alcohol-free Kilbrack Zero."), "Sit down", w.start_relax)


# ------------------------------------------------------------------ settings
func _slider(label: String, key: String, mn: float, mx: float, step: float, fmt := "%.2f") -> void:
	var h := _row()
	var l := UITheme.label(label, 22)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(GameState.settings.get(key, mn))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 50)
	h.add_child(s)
	var val := UITheme.label(fmt % s.value, 22, UITheme.GOLD)
	val.custom_minimum_size = Vector2(90, 0)
	h.add_child(val)
	s.value_changed.connect(func(x):
		val.text = fmt % x
		GameState.set_setting(key, x)
		if key == "render_scale" and hud.world:
			hud.world.apply_graphics())


func _toggle(label: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = bool(GameState.settings.get(key, false))
	c.add_theme_font_size_override("font_size", 22)
	c.custom_minimum_size = Vector2(0, 54)
	c.toggled.connect(func(on): GameState.set_setting(key, on))
	content.add_child(c)


func _choice(label: String, key: String, options: Array, on_change := Callable()) -> void:
	var h := _row()
	var l := UITheme.label(label, 22)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	for o in options:
		var val = o[0]
		var b := UITheme.button(str(o[1]), func():
			GameState.set_setting(key, val)
			if on_change.is_valid():
				on_change.call()
			show_tab("settings"), 20)
		b.custom_minimum_size = Vector2(120, 56)
		b.toggle_mode = true
		b.set_pressed_no_signal(str(GameState.settings.get(key)) == str(val))
		h.add_child(b)


func _settings() -> void:
	_text(content, "Controls", 26, UITheme.GOLD)
	_slider("Look sensitivity", "look_sensitivity", 0.3, 2.5, 0.05)
	_slider("Button opacity", "button_opacity", 0.3, 1.0, 0.05)
	_slider("Text & HUD scale", "hud_scale", 0.8, 1.4, 0.05)
	_toggle("Invert look up/down", "invert_look")
	_toggle("Vibration", "vibration")
	_toggle("Pour assist (auto-tilts the glass; you still control the tap)", "pour_assist")
	_text(content, "Audio", 26, UITheme.GOLD)
	_slider("Master", "vol_master", 0.0, 1.0, 0.05)
	_slider("Music", "vol_music", 0.0, 1.0, 0.05)
	_slider("Ambience (rain, fire)", "vol_ambience", 0.0, 1.0, 0.05)
	_slider("Crowd chatter", "vol_speech", 0.0, 1.0, 0.05)
	_slider("Effects", "vol_effects", 0.0, 1.0, 0.05)
	_toggle("Subtitles for customer speech", "subtitles")
	_text(content, "Graphics & accessibility", 26, UITheme.GOLD)
	var regfx := func(): if hud.world: hud.world.apply_graphics()
	_choice("Quality", "graphics", [["low", "Low"], ["medium", "Medium"], ["high", "High"]], regfx)
	_choice("Frame-rate limit", "fps_limit", [[30, "30"], [60, "60"], [120, "120"]], regfx)
	_slider("Render scale", "render_scale", 0.5, 1.0, 0.05)
	_toggle("Reduced camera motion", "reduced_motion")
	_toggle("Reduced visual effects", "reduced_effects")
	_toggle("High-contrast prompts", "high_contrast")
	_toggle("Show performance overlay", "show_fps")
	_text(content, "Game", 26, UITheme.GOLD)
	_choice("Real minutes per pub day", "day_length", [[6, "6"], [10, "10"], [15, "15"], [20, "20"]])


# ------------------------------------------------------------------ game
func _game() -> void:
	var v := _card()
	_text(v, "Save & exit", 26, UITheme.GOLD)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	h.add_child(UITheme.button("Save now", func():
		if GameState.save_game():
			GameState.notify("Game saved.", "good")
		else:
			GameState.notify("Save failed!", "bad")))
	h.add_child(UITheme.button("Save & quit to title", func():
		GameState.save_game()
		hud.close_menu()
		hud.world.main.quit_to_title()))
	var rn := _card()
	_text(rn, "Rename your pub", 26, UITheme.GOLD)
	var rh := HBoxContainer.new()
	rn.add_child(rh)
	var le := LineEdit.new()
	le.text = GameState.pub_name
	le.max_length = 28
	le.custom_minimum_size = Vector2(500, 60)
	le.add_theme_font_size_override("font_size", 24)
	rh.add_child(le)
	rh.add_child(UITheme.button("Rename", func():
		var n := le.text.strip_edges()
		if n.length() >= 2:
			GameState.pub_name = n
			title.text = n
			hud.world.apply_upgrades()
			GameState.notify("The pub is now called %s." % n, "good")))
	var help := _card()
	_text(help, "How to play", 26, UITheme.GOLD)
	_text(help, "Move with the left thumb (drag anywhere on the left side). Look by swiping on the right. The big button bottom-right does whatever the prompt says; some actions are held.\n\n" +
		"The perfect stout: take a clean glass from the rack, go to the stout tap, tilt the glass to 45°, pull the tap and fill to about three-quarters, straightening as it fills. Let it settle (leave it on the drip tray and do something else), then top it up upright with a gentle pull until the head domes just above the rim. Serve it to the customer who ordered it.\n\n" +
		"Collect empty glasses and wash them at the sink. Change empty kegs in the cellar (door at the back left behind the bar). Order stock from the Stock tab. Close up after midnight to see your day's accounts.", 20)
	var cr := _card()
	_text(cr, "Credits", 26, UITheme.GOLD)
	_text(cr, "An original game. All 3D models, textures, sound effects and music are generated procedurally by the game's own code; the tunes are original compositions. Fonts: Uncial Antiqua and Nunito (SIL Open Font License). Built with Godot Engine (MIT). Kilbrack, Lough Glas, Red Fox, Orchard Gate and Ballyfinn are fictional brands.", 18, UITheme.MUTED)


# ------------------------------------------------------------------ end of day
func show_summary(s: Dictionary) -> void:
	_summary_mode = true
	visible = true
	tab_bar.visible = false
	title.text = "Closing time: Day %d" % int(s["day"])
	for ch in content.get_children():
		ch.queue_free()
	var v := _card()
	_text(v, "%s at %s" % [str(s["weekday"]), GameState.pub_name], 24, UITheme.MUTED)
	var rows := [
		["Drink sales", s["sales"]], ["Tips", s["tips"]], ["Stock ordered", -float(s["stock_spend"])],
		["Upgrades bought", -float(s["upgrade_spend"])], ["Rent", -float(s["rent"])], ["Utilities", -float(s["utilities"])],
		["Wages", -float(s["wages"])],
	]
	for r in rows:
		if absf(float(r[1])) > 0.001:
			_text(v, "%-22s €%.2f" % [r[0], float(r[1])], 24)
	var profit := float(s["profit"])
	_text(v, "Profit today: €%.2f" % profit, 30, Color(0.6, 1, 0.6) if profit >= 0 else Color(1, 0.6, 0.5))
	_text(v, "Cost of drinks sold €%.2f · Gross margin €%.2f · Wasted %.1f serves" % [float(s["cogs"]), float(s["gross_margin"]), float(s["wasted"])], 20, UITheme.MUTED)
	_text(v, "Served %d · Walk-outs %d · Avg satisfaction %d%% · Avg quality %d" % [int(s["served"]), int(s["walkouts"]), int(s["avg_satisfaction"]), int(s["avg_quality"])], 22)
	_text(v, "Reputation %d (%+.1f) · Cash €%.2f" % [int(s["reputation"]), float(s["rep_change"]), float(s["cash"])], 22, UITheme.GOLD)
	_text(v, "Progress saved.", 20, Color(0.6, 0.9, 0.65))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	content.add_child(h)
	h.add_child(UITheme.button("Start the next day", func():
		_summary_mode = false
		hud.close_menu()
		hud.world.main.start_world()))
	h.add_child(UITheme.button("Quit to title", func():
		_summary_mode = false
		hud.close_menu()
		hud.world.main.quit_to_title()))
