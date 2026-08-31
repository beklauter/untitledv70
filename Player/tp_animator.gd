extends Node3D

@export_group("Animations")
@export var idle_anim := "Idle"
@export var walk_anim := "Walk"
@export var jog_anim := "Jog_Fwd"
@export var sprint_anim := "Sprint"
@export var crouch_idle_anim := "Crouch_Idle"
@export var crouch_move_anim := "Crouch_Fwd"
@export var jump_anim := "Jump_Start"
@export var fall_anim := "Jump"
@export var land_anim := "Jump_Land"
@export var roll_anim := "Roll"
@export var swim_idle_anim := "Swim_Idle"
@export var swim_move_anim := "Swim_Fwd"

@export_group("Blending")
@export var walk_speed := 1.8
@export var jog_speed := 4.6
@export var sprint_speed := 7.6
@export var crouch_speed := 1.9
@export var swim_speed := 3.2
@export var blend_sharpness := 14.0
@export var inherit_controller_speeds := true

const HARD_LOCK := ["Roll"]
const SOFT_LOCK := ["Jump", "Land"]

var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _speed := 0.0
var _blended := 0.0
var _crouching := false
var _clips := {}

func _ready() -> void:
	_player = _find_player(self)
	if _player == null:
		set_process(false)
		return
	_player.active = false
	if inherit_controller_speeds:
		_pull_speeds()
	_build_tree()

func _process(delta: float) -> void:
	if _playback == null:
		return
	_blended = lerpf(_blended, _speed, 1.0 - exp(-blend_sharpness * delta))
	_tree.set("parameters/Move/blend_position", _blended)
	_tree.set("parameters/Crouch/blend_position", _blended)
	_tree.set("parameters/Swim/blend_position", _blended)

func set_locomotion(speed: float, crouching: bool) -> void:
	_speed = speed
	_crouching = crouching

func request(state: String, force := false) -> void:
	if _playback == null:
		return
	var current := _playback.get_current_node()
	if state == "Fall" and current == "Jump":
		return
	if state == "Ground":
		if current in HARD_LOCK:
			return
		if not force and current in SOFT_LOCK:
			return
		state = "Crouch" if _crouching else "Move"
	if current == state:
		return
	_playback.travel(state)

func current_state() -> String:
	return String(_playback.get_current_node()) if _playback != null else ""

func locomotion_blend() -> float:
	return _blended

func clip_length(key: String) -> float:
	if _player == null or not _clips.has(key):
		return 0.0
	var anim := _player.get_animation(_clips[key])
	return anim.length if anim != null else 0.0

func _pull_speeds() -> void:
	var body := get_parent()
	if body == null:
		return
	walk_speed = _pull(body, "walk_speed", walk_speed)
	jog_speed = _pull(body, "jog_speed", jog_speed)
	sprint_speed = _pull(body, "sprint_speed", sprint_speed)
	crouch_speed = _pull(body, "crouch_speed", crouch_speed)
	swim_speed = _pull(body, "swim_speed", swim_speed)

func _pull(body: Node, property: String, fallback: float) -> float:
	var value: Variant = body.get(property)
	return float(value) if value != null else fallback

func _find_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_player(child)
		if found != null:
			return found
	return null

func _resolve(anim_name: String) -> String:
	if anim_name == "":
		return ""
	if _player.has_animation(anim_name):
		return anim_name
	if _player.has_animation(anim_name + "_Loop"):
		return anim_name + "_Loop"
	if anim_name.ends_with("_Loop") and _player.has_animation(anim_name.trim_suffix("_Loop")):
		return anim_name.trim_suffix("_Loop")
	return ""

func _pick(anim_name: String, fallback: String) -> String:
	var resolved := _resolve(anim_name)
	return resolved if resolved != "" else _resolve(fallback)

func _set_loop(anim_name: String, looping: bool) -> void:
	if anim_name == "":
		return
	var anim := _player.get_animation(anim_name)
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

func _leaf(anim_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	return node

func _add_point(points: Array, position: float, anim_name: String) -> void:
	if anim_name == "":
		return
	for point in points:
		if point[1] == anim_name:
			return
	points.append([position, anim_name])

func _blend_space(points: Array) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = maxf(points[points.size() - 1][0], 1.0)
	space.snap = 0.05
	for point in points:
		space.add_blend_point(_leaf(point[1]), point[0])
	return space

func _link(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float, sync := false) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC if sync else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	sm.add_transition(from, to, transition)

func _link_at_end(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(from, to, transition)

func _build_tree() -> void:
	var idle := _pick(idle_anim, "Idle")
	if idle == "":
		var available := _player.get_animation_list()
		if available.is_empty():
			set_process(false)
			return
		idle = String(available[0])

	var walk := _pick(walk_anim, idle)
	var jog := _pick(jog_anim, walk)
	var sprint := _pick(sprint_anim, jog)
	var crouch_idle := _pick(crouch_idle_anim, idle)
	var crouch_move := _pick(crouch_move_anim, walk)
	var jump := _pick(jump_anim, idle)
	var fall := _pick(fall_anim, jump)
	var land := _pick(land_anim, idle)
	var roll := _pick(roll_anim, idle)
	var swim_idle := _pick(swim_idle_anim, idle)
	var swim_move := _pick(swim_move_anim, swim_idle)

	for looping in [idle, walk, jog, sprint, crouch_idle, crouch_move, fall, swim_idle, swim_move]:
		_set_loop(looping, true)
	for once in [jump, land, roll]:
		_set_loop(once, false)

	_clips = {
		"idle": idle, "walk": walk, "jog": jog, "sprint": sprint,
		"crouch_idle": crouch_idle, "crouch_move": crouch_move,
		"jump": jump, "fall": fall, "land": land, "roll": roll,
		"swim_idle": swim_idle, "swim_move": swim_move,
	}

	var move_points := []
	_add_point(move_points, 0.0, idle)
	_add_point(move_points, walk_speed, walk)
	_add_point(move_points, jog_speed, jog)
	_add_point(move_points, sprint_speed, sprint)

	var crouch_points := []
	_add_point(crouch_points, 0.0, crouch_idle)
	_add_point(crouch_points, crouch_speed, crouch_move)

	var swim_points := []
	_add_point(swim_points, 0.0, swim_idle)
	_add_point(swim_points, swim_speed, swim_move)

	var sm := AnimationNodeStateMachine.new()
	sm.add_node("Move", _blend_space(move_points), Vector2(320, 100))
	sm.add_node("Crouch", _blend_space(crouch_points), Vector2(320, 260))
	sm.add_node("Jump", _leaf(jump), Vector2(560, 40))
	sm.add_node("Fall", _leaf(fall), Vector2(760, 100))
	sm.add_node("Land", _leaf(land), Vector2(560, 180))
	sm.add_node("Roll", _leaf(roll), Vector2(100, 260))
	sm.add_node("Swim", _blend_space(swim_points), Vector2(320, 420))

	_link(sm, "Start", "Move", 0.0)
	_link(sm, "Move", "Crouch", 0.2, true)
	_link(sm, "Crouch", "Move", 0.2, true)
	_link(sm, "Move", "Jump", 0.08)
	_link(sm, "Crouch", "Jump", 0.08)
	_link_at_end(sm, "Jump", "Fall", 0.15)
	_link(sm, "Jump", "Land", 0.1)
	_link(sm, "Jump", "Move", 0.15)
	_link(sm, "Jump", "Crouch", 0.15)
	_link(sm, "Move", "Fall", 0.2)
	_link(sm, "Crouch", "Fall", 0.2)
	_link(sm, "Fall", "Land", 0.1)
	_link(sm, "Fall", "Move", 0.15)
	_link(sm, "Fall", "Crouch", 0.15)
	_link_at_end(sm, "Land", "Move", 0.18)
	_link(sm, "Land", "Jump", 0.08)
	_link(sm, "Land", "Fall", 0.15)
	_link(sm, "Land", "Crouch", 0.18)
	_link(sm, "Move", "Roll", 0.1)
	_link(sm, "Crouch", "Roll", 0.1)
	_link_at_end(sm, "Roll", "Move", 0.2)
	_link(sm, "Roll", "Fall", 0.15)
	_link(sm, "Move", "Swim", 0.25)
	_link(sm, "Crouch", "Swim", 0.25)
	_link(sm, "Fall", "Swim", 0.15)
	_link(sm, "Jump", "Swim", 0.15)
	_link(sm, "Land", "Swim", 0.2)
	_link(sm, "Roll", "Swim", 0.2)
	_link(sm, "Swim", "Move", 0.25)
	_link(sm, "Swim", "Crouch", 0.25)
	_link(sm, "Swim", "Fall", 0.2)
	_link(sm, "Swim", "Jump", 0.1)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	add_child(_tree)
	var anim_root := _player.get_node_or_null(_player.root_node)
	if anim_root == null:
		anim_root = _player.get_parent()
	_tree.root_node = _tree.get_path_to(anim_root)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.tree_root = sm
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_tree.active = true
	_playback = _tree.get("parameters/playback")
