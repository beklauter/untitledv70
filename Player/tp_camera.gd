extends Node3D

@export var pivot_height := 1.5
@export var shoulder_offset := 0.5
@export var mouse_sensitivity := 0.0026
@export var stick_sensitivity := 3.2
@export var invert_y := false
@export var pitch_min := -1.15
@export var pitch_max := 0.62
@export var distance := 4.2
@export var distance_min := 1.4
@export var distance_max := 9.0
@export var zoom_step := 0.45
@export var follow_speed := 18.0
@export var zoom_speed := 10.0
@export var capture_on_start := true

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _yaw := 0.0
var _pitch := -0.22
var _distance := 4.2
var _target: Node3D

func _ready() -> void:
	_target = get_parent() as Node3D
	_distance = distance
	arm.spring_length = _distance
	arm.position.x = shoulder_offset
	var body := _target as CollisionObject3D
	if body != null:
		arm.add_excluded_object(body.get_rid())
	top_level = true
	_yaw = _target.rotation.y
	global_position = _pivot_point()
	global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	if capture_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch += event.relative.y * mouse_sensitivity * (1.0 if invert_y else -1.0)
		_pitch = clampf(_pitch, pitch_min, pitch_max)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - zoom_step, distance_min, distance_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + zoom_step, distance_min, distance_max)
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if look.length_squared() > 0.0004:
		_yaw -= look.x * stick_sensitivity * delta
		_pitch -= look.y * stick_sensitivity * delta * (-1.0 if invert_y else 1.0)
		_pitch = clampf(_pitch, pitch_min, pitch_max)
	global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))

func _physics_process(delta: float) -> void:
	_distance = lerpf(_distance, distance, 1.0 - exp(-zoom_speed * delta))
	arm.spring_length = _distance
	global_position = global_position.lerp(_pivot_point(), 1.0 - exp(-follow_speed * delta))

func _pivot_point() -> Vector3:
	return _target.global_position + Vector3.UP * pivot_height

func get_yaw() -> float:
	return _yaw
