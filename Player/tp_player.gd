extends CharacterBody3D

@export_group("Movement")
@export var walk_speed := 1.8
@export var jog_speed := 4.6
@export var sprint_speed := 7.6
@export var crouch_speed := 1.9
@export var ground_acceleration := 14.0
@export var ground_deceleration := 20.0
@export var air_acceleration := 4.0
@export var turn_speed := 13.0

@export_group("Jump")
@export var jump_height := 1.15
@export var gravity_scale := 1.8
@export var fall_gravity_scale := 2.4
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15
@export var land_air_time := 0.32
@export var fall_air_time := 0.16
@export var land_speed_threshold := 1.6
@export var jump_grace := 0.18

@export_group("Roll")
@export var roll_speed := 6.0
@export var roll_duration := 0.7
@export var roll_cooldown := 0.4
@export var match_roll_to_animation := true

@export_group("Swim")
@export var swim_speed := 3.2
@export var swim_sprint_speed := 4.6
@export var swim_vertical_speed := 2.4
@export var swim_acceleration := 6.0
@export var swim_turn_speed := 7.0
@export var swim_enter_depth := 1.35
@export var swim_exit_depth := 1.0
@export var swim_float_depth_idle := 1.25
@export var swim_float_depth_moving := 1.08
@export var swim_buoyancy := 5.0
@export var swim_exit_hop := 4.4
@export var swim_exit_reach := 0.45
@export var swim_probe := 3.0
@export var wade_depth := 0.35
@export var wade_speed_scale := 0.6

@export_group("Body")
@export var crouch_height := 1.15

@onready var _shape: CollisionShape3D = $Collision
@onready var _rig: Node3D = $CameraRig
@onready var _animator: Node3D = $Model
@onready var _water_sensor: Area3D = $WaterSensor

var _capsule: CapsuleShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stand_height := 1.8
var _coyote := 0.0
var _buffer := 0.0
var _air_time := 0.0
var _roll_time := 0.0
var _roll_cd := 0.0
var _roll_dir := Vector3.ZERO
var _crouching := false
var _crouch_dirty := false
var _jump_grace := 0.0
var _waters: Array[Area3D] = []
var _surface := -INF
var _swimming := false
var _probe := KinematicCollision3D.new()

func _ready() -> void:
	_capsule = (_shape.shape as CapsuleShape3D).duplicate()
	_shape.shape = _capsule
	_stand_height = _capsule.height
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	_apply_height(_stand_height)
	if match_roll_to_animation:
		var clip: float = _animator.clip_length("roll")
		if clip > 0.0:
			roll_duration = clip
	_water_sensor.area_entered.connect(_on_water_entered)
	_water_sensor.area_exited.connect(_on_water_exited)

func _physics_process(delta: float) -> void:
	_buffer = maxf(_buffer - delta, 0.0)
	_roll_cd = maxf(_roll_cd - delta, 0.0)
	_roll_time = maxf(_roll_time - delta, 0.0)
	_jump_grace = maxf(_jump_grace - delta, 0.0)
	_update_water()

	var was_grounded := is_on_floor()
	if was_grounded:
		_coyote = coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	_read_actions()

	if _swimming:
		_swim_step(delta)
	elif _roll_time > 0.0:
		_roll_step(delta)
	else:
		_move_step(delta)

	if not _swimming:
		_gravity_step(delta)
	move_and_slide()

	var grounded := is_on_floor()
	if not grounded:
		_air_time += delta

	_animate(grounded, was_grounded)

	if grounded:
		_air_time = 0.0

func _read_actions() -> void:
	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer_time
	if _swimming:
		return
	if Input.is_action_just_pressed("crouch") and _roll_time <= 0.0 and is_on_floor():
		_set_crouch(not _crouching)
	if Input.is_action_just_pressed("roll") and is_on_floor() and _roll_cd <= 0.0:
		_start_roll()

func _wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length_squared() < 0.0004:
		return Vector3.ZERO
	var basis := _rig.global_transform.basis
	var forward := -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (right * input.x - forward * input.y).limit_length(1.0)

func _has_move_input() -> bool:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.01

func _target_speed(magnitude: float) -> float:
	if _crouching and is_on_floor():
		return crouch_speed * magnitude
	if Input.is_action_pressed("walk"):
		return walk_speed * magnitude * _wade_scale()
	if Input.is_action_pressed("sprint"):
		return sprint_speed * magnitude * _wade_scale()
	return jog_speed * magnitude * _wade_scale()

func _move_step(delta: float) -> void:
	var wish := _wish_direction()
	var magnitude := wish.length()
	var goal := Vector3.ZERO
	if magnitude > 0.0:
		goal = wish.normalized() * _target_speed(magnitude)
	var planar := Vector3(velocity.x, 0.0, velocity.z)

	var rate := ground_acceleration if is_on_floor() else air_acceleration
	if magnitude < 0.05:
		rate = ground_deceleration if is_on_floor() else air_acceleration * 0.5
	planar = planar.lerp(goal, 1.0 - exp(-rate * delta))

	velocity.x = planar.x
	velocity.z = planar.z

	if magnitude > 0.05:
		_face(wish, delta, turn_speed)

	if _buffer > 0.0 and _coyote > 0.0:
		_buffer = 0.0
		_coyote = 0.0
		if _crouching:
			_set_crouch(false)
		velocity.y = sqrt(2.0 * _gravity * gravity_scale * jump_height)
		_jump_grace = jump_grace
		_animator.request("Jump")

func _face(direction: Vector3, delta: float, speed: float) -> void:
	var target := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-speed * delta))

func _on_water_entered(area: Area3D) -> void:
	if not _waters.has(area):
		_waters.append(area)

func _on_water_exited(area: Area3D) -> void:
	_waters.erase(area)

func _water_depth() -> float:
	return _surface - global_position.y

func _bottom_water_depth() -> float:
	var drop := swim_probe
	if test_move(global_transform, Vector3.DOWN * swim_probe, _probe):
		drop = _probe.get_travel().length()
	return _surface - (global_position.y - drop)

func _wade_scale() -> float:
	var depth := _water_depth()
	if depth < wade_depth:
		return 1.0
	return lerpf(1.0, wade_speed_scale, clampf(depth / maxf(swim_enter_depth, 0.01), 0.0, 1.0))

func _update_water() -> void:
	var best := -INF
	for area in _waters:
		if not is_instance_valid(area):
			continue
		var level: float = area.surface_level() if area.has_method("surface_level") else area.global_position.y
		best = maxf(best, level)
	_surface = best

	var depth := _bottom_water_depth()
	if _swimming:
		if depth < swim_exit_depth:
			_swimming = false
	elif depth > swim_enter_depth:
		_swimming = true
		_roll_time = 0.0
		_set_crouch(false)
		velocity.y *= 0.25
	motion_mode = MOTION_MODE_FLOATING if _swimming else MOTION_MODE_GROUNDED

func _swim_step(delta: float) -> void:
	_air_time = 0.0
	var wish := _wish_direction()
	var magnitude := wish.length()
	var top := swim_sprint_speed if Input.is_action_pressed("sprint") else swim_speed
	var goal := Vector3.ZERO
	if magnitude > 0.0:
		goal = wish.normalized() * top * magnitude
	var planar := Vector3(velocity.x, 0.0, velocity.z).lerp(goal, 1.0 - exp(-swim_acceleration * delta))
	velocity.x = planar.x
	velocity.z = planar.z

	var blend := clampf(_animator.locomotion_blend() / maxf(swim_speed, 0.01), 0.0, 1.0)
	var float_line := _surface - lerpf(swim_float_depth_idle, swim_float_depth_moving, blend)
	var rise := clampf((float_line - global_position.y) * swim_buoyancy, -swim_vertical_speed, swim_vertical_speed)
	if Input.is_action_pressed("jump") and global_position.y < float_line:
		rise = swim_vertical_speed
	elif Input.is_action_pressed("crouch"):
		rise = -swim_vertical_speed
	velocity.y = lerpf(velocity.y, rise, 1.0 - exp(-swim_acceleration * delta))

	if Input.is_action_just_pressed("jump") and test_move(global_transform, Vector3.DOWN * swim_exit_reach):
		velocity.y = swim_exit_hop

	if magnitude > 0.05:
		_face(wish, delta, swim_turn_speed)

func _start_roll() -> void:
	var wish := _wish_direction()
	if wish.length_squared() < 0.01:
		wish = -global_transform.basis.z
	_roll_dir = Vector3(wish.x, 0.0, wish.z).normalized()
	_roll_time = roll_duration
	_roll_cd = roll_duration + roll_cooldown
	_set_crouch(false)
	rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
	_animator.request("Roll")

func _roll_step(delta: float) -> void:
	var t := 1.0 - (_roll_time / roll_duration)
	var speed := roll_speed * (1.0 - smoothstep(0.35, 0.85, t))
	var planar := Vector3(velocity.x, 0.0, velocity.z).lerp(_roll_dir * speed, 1.0 - exp(-18.0 * delta))
	velocity.x = planar.x
	velocity.z = planar.z

func _gravity_step(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
		return
	var pull := fall_gravity_scale if velocity.y < 0.0 else gravity_scale
	velocity.y -= _gravity * pull * delta
	velocity.y = maxf(velocity.y, -60.0)

func _set_crouch(value: bool) -> void:
	if value == _crouching:
		return
	if not value and not _can_stand():
		return
	_crouching = value
	_crouch_dirty = true
	_apply_height(crouch_height if value else _stand_height)

func _apply_height(height: float) -> void:
	_capsule.height = height
	_shape.position.y = height * 0.5

func _can_stand() -> bool:
	var previous := _capsule.height
	var offset := _shape.position.y
	_apply_height(_stand_height)
	var blocked := test_move(global_transform, Vector3.UP * 0.02)
	_capsule.height = previous
	_shape.position.y = offset
	return not blocked

func _animate(grounded: bool, was_grounded: bool) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	_animator.set_locomotion(planar, _crouching)

	if _swimming:
		_animator.request("Swim")
		return

	if _roll_time > 0.0 or _jump_grace > 0.0:
		return

	var wants_move := _has_move_input()
	var force := wants_move or _crouch_dirty
	_crouch_dirty = false

	if grounded:
		var stopping := not wants_move and planar < land_speed_threshold
		if not was_grounded and _air_time > land_air_time and stopping:
			_animator.request("Land")
		else:
			_animator.request("Ground", force)
	elif _air_time > fall_air_time:
		_animator.request("Fall")
