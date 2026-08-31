extends Camera3D
## Free-fly demo camera. WASD to move, hold right mouse to look, wheel sets
## speed, Shift boosts.

@export var move_speed := 8.0
@export var boost_mult := 4.0
@export var mouse_sens := 0.002

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sens)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		move_speed = clampf(move_speed * 1.15, 0.5, 200.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		move_speed = clampf(move_speed / 1.15, 0.5, 200.0)

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir += Vector3.FORWARD
	if Input.is_physical_key_pressed(KEY_S): dir += Vector3.BACK
	if Input.is_physical_key_pressed(KEY_A): dir += Vector3.LEFT
	if Input.is_physical_key_pressed(KEY_D): dir += Vector3.RIGHT
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir += Vector3.DOWN
	var speed := move_speed * (boost_mult if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	translate(dir.normalized() * speed * delta)
