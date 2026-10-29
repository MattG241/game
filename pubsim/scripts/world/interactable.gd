class_name Interactable
extends Node3D
## Something the player can use. The prompt callable returns "" when unavailable.

var prompt_fn: Callable
var action_fn: Callable
var alt_prompt_fn: Callable
var alt_action_fn: Callable
var hold_seconds := 0.0       # >0: the button must be held (wiping, scrubbing)
var reach := 1.9
var tag := ""


static func make(parent: Node, pos: Vector3, tag_name: String, prompt: Callable, action: Callable, hold := 0.0, reach_m := 1.9) -> Interactable:
	var it := Interactable.new()
	it.tag = tag_name
	it.prompt_fn = prompt
	it.action_fn = action
	it.hold_seconds = hold
	it.reach = reach_m
	parent.add_child(it)
	it.global_position = pos
	it.add_to_group("interactable")
	return it


func prompt() -> String:
	if not is_visible_in_tree() or not prompt_fn.is_valid():
		return ""
	return str(prompt_fn.call())


func alt_prompt() -> String:
	if not is_visible_in_tree() or not alt_prompt_fn.is_valid():
		return ""
	return str(alt_prompt_fn.call())


func activate() -> void:
	if action_fn.is_valid():
		action_fn.call()


func activate_alt() -> void:
	if alt_action_fn.is_valid():
		alt_action_fn.call()
