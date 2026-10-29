extends Node
## Loads the editable JSON data files (prices, drinks, upgrades, people, events).

var economy: Dictionary = {}
var drinks: Array = []
var drinks_by_id: Dictionary = {}
var upgrades: Array = []
var upgrades_by_id: Dictionary = {}
var regulars: Array = []
var regulars_by_id: Dictionary = {}
var events: Array = []
var events_by_id: Dictionary = {}
var objectives: Array = []
var staff_pool: Array = []
var furniture: Array = []
var furniture_by_id: Dictionary = {}
var customer_lines: Dictionary = {}
var quiz: Array = []
var awards: Array = []
var brand: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	economy = _load("res://data/economy.json", {})
	drinks = _load("res://data/drinks.json", [])
	upgrades = _load("res://data/upgrades.json", [])
	regulars = _load("res://data/regulars.json", [])
	events = _load("res://data/events.json", [])
	objectives = _load("res://data/objectives.json", [])
	staff_pool = _load("res://data/staff.json", [])
	furniture = _load("res://data/furniture.json", [])
	customer_lines = _load("res://data/customer_lines.json", {})
	quiz = _load("res://data/quiz.json", [])
	awards = _load("res://data/awards.json", [])
	brand = _load("res://data/brand.json", {})
	drinks_by_id = _index(drinks)
	upgrades_by_id = _index(upgrades)
	regulars_by_id = _index(regulars)
	events_by_id = _index(events)
	furniture_by_id = _index(furniture)


func _index(arr: Array) -> Dictionary:
	var d := {}
	for item in arr:
		d[item["id"]] = item
	return d


func _load(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("Failed to parse %s" % path)
		return fallback
	return parsed


func econ(key: String, default: Variant = 0.0) -> Variant:
	return economy.get(key, default)


func drink(id: String) -> Dictionary:
	return drinks_by_id.get(id, {})


func drink_name(id: String) -> String:
	return drink(id).get("name", id)


func upgrade(id: String) -> Dictionary:
	return upgrades_by_id.get(id, {})
