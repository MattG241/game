extends Node
## Google Play Billing: the one-off "Remove ads" purchase.
## The entitlement is cached in Settings (survives new games and offline play) and is
## re-checked against Google Play on every launch, so restores and refunds are honoured.

signal changed

var product_id := "remove_ads"
var ads_removed := false
var price_text := ""           # localized price from Play, e.g. "A$4.99"
var available := false         # billing plugin present and connected
var simulate := false          # tests: pretend purchases succeed
var _client: Node = null       # BillingClient
var _product_known := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ads_removed = bool(Settings.get_value("ads_removed", false))
	var cfg_path := "res://data/ads.json"
	if FileAccess.file_exists(cfg_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			product_id = str(parsed.get("remove_ads_product_id", product_id))
	if OS.get_name() == "Android" and Engine.has_singleton("GodotGooglePlayBilling"):
		get_tree().create_timer(6.0, true, false, true).timeout.connect(_start_billing)


func _start_billing() -> void:
	Diagnostics.mark("billing start")
	_client = BillingClient.new()
	add_child(_client)
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(func(): available = false)
	_client.query_product_details_response.connect(_on_product_details)
	_client.query_purchases_response.connect(_on_purchases)
	_client.on_purchase_updated.connect(_on_purchases)
	_client.acknowledge_purchase_response.connect(func(_r): pass)
	_client.start_connection()


func _on_connected() -> void:
	Diagnostics.mark("billing connected")
	available = true
	_client.query_product_details(PackedStringArray([product_id]), BillingClient.ProductType.INAPP)
	_client.query_purchases(BillingClient.ProductType.INAPP)


func _on_product_details(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		return
	for d in result.get("product_details", []):
		if d.get("product_id", "") == product_id:
			_product_known = true
			var offers = d.get("one_time_purchase_offer_details_list")
			if offers is Array and not offers.is_empty():
				price_text = str(offers[0].get("formatted_price", ""))
	changed.emit()


## Handles both "query existing purchases" and "purchase just completed".
func _on_purchases(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		return
	var owned := false
	for p in result.get("purchases", []):
		if product_id in Array(p.get("product_ids", [])):
			if int(p.get("purchase_state", 0)) == BillingClient.PurchaseState.PURCHASED:
				owned = true
				# One-off products must be acknowledged within 3 days or Google refunds them.
				if not bool(p.get("is_acknowledged", false)):
					_client.acknowledge_purchase(str(p.get("purchase_token", "")))
			elif int(p.get("purchase_state", 0)) == BillingClient.PurchaseState.PENDING:
				GameState.notify.emit("Purchase pending - it will unlock once payment completes", "info")
	if owned != ads_removed and (owned or result.has("purchases")):
		_set_removed(owned, owned)


func _set_removed(on: bool, announce := false) -> void:
	ads_removed = on
	Settings.set_value("ads_removed", on)
	Ads.ads_removed_changed()
	changed.emit()
	if announce:
		Audio.play("purchase")
		GameState.notify.emit("Ads removed - thank you for supporting Lunar Cleanup!", "purchase")


func can_buy() -> bool:
	return simulate or (available and _product_known)


func buy() -> void:
	if ads_removed:
		return
	if simulate:
		_set_removed(true, true)
		return
	if not available:
		GameState.notify.emit("Google Play isn't reachable right now - check your connection", "error")
		return
	if not _product_known:
		GameState.notify.emit("Store item not available yet - try again shortly", "error")
		_client.query_product_details(PackedStringArray([product_id]), BillingClient.ProductType.INAPP)
		return
	var r: Dictionary = _client.purchase(product_id)
	if int(r.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		GameState.notify.emit("Couldn't open the Google Play purchase screen", "error")


## "Restore purchases": asks Google Play again (also happens automatically on launch).
func restore() -> void:
	if simulate:
		return
	if available:
		_client.query_purchases(BillingClient.ProductType.INAPP)
		GameState.notify.emit("Checking your Google Play purchases...", "info")
	else:
		GameState.notify.emit("Google Play isn't reachable right now", "error")
