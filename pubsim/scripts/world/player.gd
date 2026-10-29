class_name Player
extends CharacterBody3D
## First-person bartender. Moved by the virtual joystick, looked around by swiping.

const SPEED := 2.7
const EYE := 1.62

var camera: Camera3D
var hand: Node3D
var move_input := Vector2.ZERO
var input_enabled := true
var held: PintGlass = null
var fp_hand: Node3D   # the bartender's own right hand, shown wrapped round whatever glass is held
var dirty_stack: Array[PintGlass] = []
var focus: Interactable = null
var _pitch := -0.08
var _bob := 0.0
var _step_acc := 0.0
var _step_i := 0


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	camera = Camera3D.new()
	camera.position.y = EYE
	camera.fov = 70.0
	camera.near = 0.03
	camera.far = 80.0
	add_child(camera)
	camera.current = true
	hand = Node3D.new()
	hand.position = Vector3(0.2, -0.3, -0.45)
	camera.add_child(hand)
	fp_hand = _build_hand()
	hand.add_child(fp_hand)
	fp_hand.visible = false
	floor_snap_length = 0.3


func look(delta_px: Vector2) -> void:
	if not input_enabled:
		return
	var sens := 0.0042 * float(GameState.settings.get("look_sensitivity", 1.0))
	var inv := -1.0 if GameState.settings.get("invert_look", false) else 1.0
	rotation.y -= delta_px.x * sens
	_pitch = clampf(_pitch - delta_px.y * sens * inv, -1.25, 1.2)
	camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	_update_hand()
	var dir := Vector3.ZERO
	if input_enabled:
		var mi := move_input
		# desktop testing convenience; the game never requires a keyboard
		var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if kb.length() > 0.1:
			mi = kb
		dir = (transform.basis * Vector3(mi.x, 0, mi.y))
		dir.y = 0
	var target := dir * SPEED
	velocity.x = move_toward(velocity.x, target.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 18.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.3:
		_step_acc += speed * delta
		if _step_acc > 0.62:
			_step_acc = 0.0
			_step_i = (_step_i + 1) % 3
			Sfx.play("step%d" % _step_i, -10.0, 0.08)
		if not GameState.settings.get("reduced_motion", false):
			_bob += delta * speed * 4.2
	camera.position.y = EYE + sin(_bob) * 0.018 * clampf(speed / SPEED, 0, 1)


func has_hands_free() -> bool:
	return held == null and dirty_stack.is_empty()


## A right hand gripping a pint (palm on the right, fingers round the far side, thumb across the
## front) with a rolled shirt sleeve. Merged into a few meshes; only shown while holding a glass.
func _build_hand() -> Node3D:
	return build_hand()


static func build_hand() -> Node3D:
	# the sculpted gripping hand (tools/gen_people.py), skin down to the wrist then a rolled
	# white shirt sleeve
	var h := Node3D.new()
	h.name = "FirstPersonHand"
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/people/hand_grip.obj")
	mi.material_override = MeshKit.shader_mat("res://assets/shaders/limb.gdshader", {
		"cloth": Color(0.9, 0.71, 0.58), "pattern": 0, "end_color": Color(0.93, 0.92, 0.88),
		"end_rough": 0.85, "split_y": -0.11, "cuff": 1.0, "cuff_color": Color(0.85, 0.84, 0.8)})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(mi)
	return h


func _update_hand() -> void:
	fp_hand.visible = held != null and held.get_parent() == hand


func take_glass(g: PintGlass) -> void:
	held = g
	if g.get_parent():
		g.get_parent().remove_child(g)
	hand.add_child(g)
	g.position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	g.scale = Vector3.ONE
	_update_hand()


func release_glass() -> PintGlass:
	var g := held
	held = null
	if g and g.get_parent() == hand:
		hand.remove_child(g)
	_update_hand()
	return g


func add_dirty(g: PintGlass) -> void:
	if g.get_parent():
		g.get_parent().remove_child(g)
	hand.add_child(g)
	dirty_stack.append(g)
	_layout_stack()


func pop_dirty() -> PintGlass:
	if dirty_stack.is_empty():
		return null
	var g: PintGlass = dirty_stack.pop_back()
	hand.remove_child(g)
	_layout_stack()
	return g


func _layout_stack() -> void:
	for i in dirty_stack.size():
		var g: PintGlass = dirty_stack[i]
		g.position = Vector3(-0.05 + (i % 2) * 0.09, -0.02, -(i / 2) * 0.09)
		g.rotation = Vector3.ZERO


## Picks the interactable the player is looking at (or nearest to the view centre).
func update_focus() -> void:
	var best: Interactable = null
	var best_score := INF
	var cam_pos := camera.global_position
	var fwd := -camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null:
			continue
		var to := it.global_position - cam_pos
		var dist := to.length()
		if dist > it.reach + 0.6:
			continue
		var flat := Vector2(to.x, to.z).length()
		if flat > it.reach:
			continue
		var ang := fwd.angle_to(to.normalized())
		if ang > 0.62:
			continue
		var p := it.prompt()
		if p == "":
			continue
		var score := ang * 2.0 + dist * 0.35
		if score < best_score:
			best_score = score
			best = it
	focus = best
