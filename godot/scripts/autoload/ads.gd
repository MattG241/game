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

var config := {}
var available := false         # plugin present and running on Android
var sdk_ready := false
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			config = parsed
	available = bool(config.get("enabled", true)) and OS.get_name() == "Android" \
		and Engine.has_singleton("PoingGodotAdMob")
	if available:
		_gather_consent()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------- consent

## Google's User Messaging Platform: shows the GDPR/US-states consent form when the
## player's region requires it, then starts the ads SDK.
func _gather_consent() -> void:
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(params,
		func():
			if UserMessagingPlatform.consent_information.get_is_consent_form_available():
				_load_and_show_form()
			else:
				_start_sdk(),
		func(_err):
			# Offline or form unavailable: still start (non-personalised ads only).
			_start_sdk())


func _load_and_show_form() -> void:
	UserMessagingPlatform.load_consent_form(
		func(form):
			var status := UserMessagingPlatform.consent_information.get_consent_status()
			if status == ConsentInformation.ConsentStatus.REQUIRED:
				form.show(func(_e): _start_sdk())
			else:
				_start_sdk(),
		func(_err): _start_sdk())


## True when the player must be able to revisit their ad privacy choices (GDPR).
func privacy_options_required() -> bool:
	if not available:
		return false
	return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	if available:
		UserMessagingPlatform.show_privacy_options_form(func(_e): pass)


func _start_sdk() -> void:
	if sdk_ready:
		return
	MobileAds.initialize()
	sdk_ready = true
	_load_rewarded()
	if not IAP.ads_removed:
		_load_interstitial()


# ------------------------------------------------------------------- loading

func _load_rewarded() -> void:
	if not sdk_ready or _loading_rewarded or _rewarded != null:
		return
	_loading_rewarded = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading_rewarded = false
		_rewarded = ad
		rewarded_ready_changed.emit(true)
	cb.on_ad_failed_to_load = func(_err):
		_loading_rewarded = false
		_retry_t = 30.0
	RewardedAdLoader.new().load(str(config.get("rewarded_unit_android", "")), AdRequest.new(), cb)


func _load_interstitial() -> void:
	if not sdk_ready or _loading_interstitial or _interstitial != null or IAP.ads_removed:
		return
	_loading_interstitial = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading_interstitial = false
		_interstitial = ad
	cb.on_ad_failed_to_load = func(_err):
		_loading_interstitial = false
		_retry_t = 30.0
	InterstitialAdLoader.new().load(str(config.get("interstitial_unit_android", "")), AdRequest.new(), cb)


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
