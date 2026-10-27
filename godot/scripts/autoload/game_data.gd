extends Node
## Read-only balancing data loaded from res://data/*.json.

var economy: Dictionary = {}
var tools: Array = []
var vehicles: Array = []
var vehicle_upgrade: Dictionary = {}
var machines: Array = []
var regions: Array = []
var missions: Array = []
var achievements: Array = []
var research: Array = []

var _tool_index := {}
var _vehicle_index := {}
var _machine_index := {}
var _research_index := {}
var _region_index := {}


func _ready() -> void:
	reload()


func reload() -> void:
	economy = _load("res://data/economy.json")
	var t := _load("res://data/tools.json")
	tools = t.get("tools", [])
	var v := _load("res://data/vehicles.json")
	vehicles = v.get("vehicles", [])
	vehicle_upgrade = v.get("upgrade", {})
	machines = _load("res://data/machines.json").get("machines", [])
	regions = _load("res://data/regions.json").get("regions", [])
	var m := _load("res://data/missions.json")
	missions = m.get("missions", [])
	achievements = m.get("achievements", [])
	research = _load("res://data/research.json").get("research", [])
	_tool_index = _index(tools)
	_vehicle_index = _index(vehicles)
	_machine_index = _index(machines)
	_research_index = _index(research)
	_region_index = _index(regions)


func _index(arr: Array) -> Dictionary:
	var d := {}
	for i in arr.size():
		d[arr[i]["id"]] = i
	return d


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing data file " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Bad JSON in " + path)
		return {}
	return parsed


func tool(id: String) -> Dictionary:
	return tools[_tool_index[id]] if _tool_index.has(id) else {}


func tool_index(id: String) -> int:
	return _tool_index.get(id, -1)


func vehicle(id: String) -> Dictionary:
	return vehicles[_vehicle_index[id]] if _vehicle_index.has(id) else {}


func machine(id: String) -> Dictionary:
	return machines[_machine_index[id]] if _machine_index.has(id) else {}


func research_item(id: String) -> Dictionary:
	return research[_research_index[id]] if _research_index.has(id) else {}


func region(index: int) -> Dictionary:
	return regions[clampi(index, 0, regions.size() - 1)]


func region_index(id: String) -> int:
	return _region_index.get(id, -1)


static func color(hex: String) -> Color:
	return Color.html(hex)
