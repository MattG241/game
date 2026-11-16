extends Node
## Google AdMob integration (Poing Studios plugin): EU consent, rewarded ads and
## occasional interstitials. Everything degrades to "no ads" when the plugin is not
## present (desktop, tests) or when the device is offline, so the game always plays.
##
## Policy for this game (data/ads.json):
## - Rewarded ads are always optional: "double this sale", "instant recharge".
## - Interstitials only after a sale at the Dust Exchange, never in the first
##   10 minutes, at most every 5 minutes, and never right after a rewarded ad.
## - Buying "Remove ads" (IAP autoload) disables interstitials. Rewarded stay optional.

signal rewarded_ready_changed(ready: bool)

const CONFIG_PATH := "res://data/ads.json"
const START_DELAY := 10.0

var config := {}
var available := false         # plugin present and running on Android
var sdk_ready := false
var _sdk_starting := false
var simulate := false          # tests: pretend ads exist and complete instantly
var interstitials_shown := 0
var rewarded_shown := 0

var _rewarded = null           # RewardedAd
var _interstitial = null       # InterstitialAd
var _loading_rewarded := false
var _loading_interstitial := false
var _last_interstitial_s := -1e9
var _last_rewarded_s := -1e9
var _retry_t := 0.0
var _showing := false
# What the ads pipeline is doing, for Settings > Ad status and the copied log.
var stage := "not started"
var last_error := ""
var requests := 0
const ADS_LOG := "user://logs/ads.txt"
const CONSENT_TIMEOUT := 12.0   # start ads anyway if Google's consent check never answers
const INIT_TIMEOUT := 20.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			config = parsed
	available = bool(config.get("enabled", true)) and OS.get_name() == "Android" \
		and Engine.has_singleton("PoingGodotAdMob")
	if OS.get_name() == "Android":
		_note("app start: %s, plugin %s, units %s / %s" % [
			"Play Store build" if OS.has_feature("play_store") else "sideloaded build (Google TEST ads)",
			"found" if Engine.has_singleton("PoingGodotAdMob") else "NOT FOUND",
			_unit("interstitial"), _unit("rewarded")])
	if available:
		# Start a little after the menu so a startup problem can't stop the player
		# from reaching Settings > Copy crash log.
		get_tree().create_timer(START_DELAY, true, false, true).timeout.connect(_gather_consent)


## Real ad units only in the Play Store bundle ("play_store" export feature). The
## sideloaded APK always shows Google test ads, so playing it can never count as
## invalid clicks on the developer's own ads.
func _unit(kind: String) -> String:
	var key := "%s_unit_android" % kind
	if not OS.has_feature("play_store"):
		key = "test_" + key
	return str(config.get(key, ""))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------- consent

## Google's User Messaging Platform: shows the GDPR/US-states consent form when the
## player's region requires it, then starts the ads SDK.
func _gather_consent() -> void:
	_note("consent check")
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(params,
		func():
			_note("consent info ok (status %d, form %s)" % [UserMessagingPlatform.consent_information.get_consent_status(),
				UserMessagingPlatform.consent_information.get_is_consent_form_available()])
			if UserMessagingPlatform.consent_information.get_is_consent_form_available():
				_load_and_show_form()
			else:
				_start_sdk(),
		func(err):
			# Offline or form unavailable: still start (non-personalised ads only).
			_error("consent check failed", err)
			_start_sdk())
	# If Google's consent check never answers, don't let that block every ad.
	get_tree().create_timer(CONSENT_TIMEOUT, true, false, true).timeout.connect(func():
		if not sdk_ready and not _sdk_starting:
			_note("consent check gave no answer in %d s - starting ads anyway" % int(CONSENT_TIMEOUT))
			_start_sdk())


func _load_and_show_form() -> void:
	UserMessagingPlatform.load_consent_form(
		func(form):
			var status := UserMessagingPlatform.consent_information.get_consent_status()
			if status == ConsentInformation.ConsentStatus.REQUIRED:
				_note("showing consent form")
				form.show(func(_e):
					_note("consent form closed")
					_start_sdk())
			else:
				_start_sdk(),
		func(err):
			_error("consent form failed to load", err)
			_start_sdk())


## True when the player must be able to revisit their ad privacy choices (GDPR).
func privacy_options_required() -> bool:
	if not available:
		return false
	return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	if available:
		UserMessagingPlatform.show_privacy_options_form(func(_e): pass)


## Ads may only be loaded once the SDK reports it has finished initialising: the
## plugin loads on Android's UI thread, where an early load throws and closes the app.
func _start_sdk() -> void:
	if sdk_ready or _sdk_starting:
		return
	_sdk_starting = true
	_note("sdk start (MobileAds.initialize)")
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status):
		sdk_ready = true
		_note("sdk ready")
		_load_rewarded()
		_load_interstitial()
	MobileAds.initialize(listener)
	get_tree().create_timer(INIT_TIMEOUT, true, false, true).timeout.connect(func():
		if not sdk_ready:
			_note("sdk gave no 'initialised' answer in %d s" % int(INIT_TIMEOUT)))


# ------------------------------------------------------------------- loading

func _load_rewarded() -> void:
	if not sdk_ready or _loading_rewarded or _rewarded != null:
		return
	_loading_rewarded = true
	requests += 1
	_note("load rewarded " + _unit("rewarded"))
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading_rewarded = false
		_rewarded = ad
		_note("rewarded loaded")
		rewarded_ready_changed.emit(true)
	cb.on_ad_failed_to_load = func(err):
		_loading_rewarded = false
		_error("rewarded failed to load", err)
		_retry_t = 30.0
	RewardedAdLoader.new().load(_unit("rewarded"), AdRequest.new(), cb)


func _load_interstitial() -> void:
	if not sdk_ready or _loading_interstitial or _interstitial != null or IAP.ads_removed:
		return
	_loading_interstitial = true
	requests += 1
	_note("load interstitial " + _unit("interstitial"))
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading_interstitial = false
		_interstitial = ad
		_note("interstitial loaded")
	cb.on_ad_failed_to_load = func(err):
		_loading_interstitial = false
		_error("interstitial failed to load", err)
		_retry_t = 30.0
	InterstitialAdLoader.new().load(_unit("interstitial"), AdRequest.new(), cb)


func _process(delta: float) -> void:
	if _retry_t > 0.0:
		_retry_t -= delta
		if _retry_t <= 0.0:
			_load_rewarded()
			_load_interstitial()


# ------------------------------------------------------------------ rewarded

func rewarded_ready() -> bool:
	if simulate:
		return true
	return _rewarded != null and not _showing


## Shows a rewarded ad. on_reward is called only if the player watched it to the end.
func show_rewarded(on_reward: Callable) -> bool:
	if simulate:
		rewarded_shown += 1
		_last_rewarded_s = _now()
		on_reward.call()
		return true
	if not rewarded_ready():
		GameState.notify.emit("No ad available right now - try again in a moment", "info")
		return false
	var ad = _rewarded
	_rewarded = null
	rewarded_ready_changed.emit(false)
	var earned := [false]
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item): earned[0] = true
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = func():
		_ad_finished()
		if earned[0]:
			on_reward.call()
		ad.destroy()
		_load_rewarded()
	fs.on_ad_failed_to_show_full_screen_content = func(_e):
		_ad_finished()
		ad.destroy()
		_load_rewarded()
	ad.full_screen_content_callback = fs
	_ad_started()
	rewarded_shown += 1
	_last_rewarded_s = _now()
	ad.show(listener)
	return true


# -------------------------------------------------------------- interstitial

## Decides whether an interstitial may show now (pure rules; easy to test).
func interstitial_allowed(play_seconds: float, now_s: float) -> bool:
	if IAP.ads_removed or not bool(config.get("enabled", true)):
		return false
	if play_seconds < float(config.get("interstitial_first_after_seconds", 600)):
		return false
	if now_s - _last_interstitial_s < float(config.get("interstitial_interval_seconds", 300)):
		return false
	if now_s - _last_rewarded_s < float(config.get("interstitial_after_rewarded_gap_seconds", 90)):
		return false
	return true


## Called at natural breaks (after selling dust). Returns true if an ad was shown.
func maybe_show_interstitial() -> bool:
	var now := _now()
	if not interstitial_allowed(GameState.stat("play_time"), now):
		return false
	if simulate:
		interstitials_shown += 1
		_last_interstitial_s = now
		return true
	if _interstitial == null or _showing:
		_load_interstitial()
		return false
	var ad = _interstitial
	_interstitial = null
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = func():
		_ad_finished()
		ad.destroy()
		_load_interstitial()
	fs.on_ad_failed_to_show_full_screen_content = func(_e):
		_ad_finished()
		ad.destroy()
		_load_interstitial()
	ad.full_screen_content_callback = fs
	_ad_started()
	interstitials_shown += 1
	_last_interstitial_s = now
	ad.show()
	return true


func reset_pacing() -> void:
	_last_interstitial_s = -1e9
	_last_rewarded_s = -1e9


# ------------------------------------------------------------ while showing

func _ad_started() -> void:
	_showing = true
	Diagnostics.event("ad shown")
	AudioServer.set_bus_mute(0, true)
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("release_input"):
		world.release_input()


func _ad_finished() -> void:
	_showing = false
	AudioServer.set_bus_mute(0, false)


func ads_removed_changed() -> void:
	if IAP.ads_removed and _interstitial != null:
		_interstitial.destroy()
		_interstitial = null


# ------------------------------------------------------------- diagnostics

## Records a step: shown in Settings > Ad status and kept in user://logs/ads.txt.
func _note(what: String) -> void:
	stage = what
	Diagnostics.mark("ads " + what)
	var lines: PackedStringArray = []
	if FileAccess.file_exists(ADS_LOG):
		lines = FileAccess.get_file_as_string(ADS_LOG).strip_edges().split("\n")
	lines.append("%s %s" % [Time.get_datetime_string_from_system(), what])
	if lines.size() > 80:
		lines = lines.slice(lines.size() - 80)
	DirAccess.make_dir_recursive_absolute(ADS_LOG.get_base_dir())
	var f := FileAccess.open(ADS_LOG, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")


func _error(what: String, err) -> void:
	var detail := ""
	if err is Object:
		var code = err.get("code") if err.get("code") != null else err.get("error_code")
		var msg = err.get("message")
		detail = " (code %s: %s)" % [str(code), str(msg)]
	last_error = what + detail
	_note("ERROR " + last_error)


## One paragraph for Settings > Ad status.
func status_text() -> String:
	if OS.get_name() != "Android":
		return "Ads only run on Android."
	var lines := [
		"Build: " + ("Play Store (your real AdMob units)" if OS.has_feature("play_store") else "sideloaded APK (Google TEST ads - these never count in your AdMob account)"),
		"AdMob plugin: " + ("found" if Engine.has_singleton("PoingGodotAdMob") else "NOT FOUND"),
		"Ads SDK: " + ("ready" if sdk_ready else ("starting" if _sdk_starting else "not started")),
		"Requests this session: %d   Rewarded loaded: %s   Interstitial loaded: %s" % [requests, "yes" if _rewarded != null else "no", "yes" if _interstitial != null else "no"],
		"Last step: " + stage,
	]
	if last_error != "":
		lines.append("Last error: " + last_error)
	if IAP.ads_removed:
		lines.append("Remove Ads purchased: full-screen ads are off (rewarded ads stay optional).")
	return "\n".join(lines)


## The ads log, for the copied crash report.
func log_text() -> String:
	if FileAccess.file_exists(ADS_LOG):
		return FileAccess.get_file_as_string(ADS_LOG)
	return "(no ads log yet)"
