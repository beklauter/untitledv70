extends Camera3D

# -------------------------
# Maus-Parallax
# -------------------------
@export var max_rotation_x := 2.0
@export var max_rotation_y := 4.0
@export var move_amount := 0.15
@export var smooth_speed := 3.0

# -------------------------
# Idle-Kamerafahrt
# -------------------------
@export var idle_rotation_x := 3.0
@export var idle_rotation_y := 18.0
@export var idle_speed := 0.18

# Optionale seitliche Bewegung
@export var idle_move_x := 0.4

var start_rotation: Vector3
var start_position: Vector3
var time := 0.0


func _ready():
	start_rotation = rotation_degrees
	start_position = position


func _process(delta):
	time += delta

	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = get_viewport().get_mouse_position()

	# Mausposition auf Bereich -1 bis +1 umrechnen
	var mouse := Vector2(
		(mouse_pos.x / viewport_size.x) * 2.0 - 1.0,
		(mouse_pos.y / viewport_size.y) * 2.0 - 1.0
	)

	# -------------------------
	# Idle-Bewegung
	# -------------------------

	var idle_y = sin(time * idle_speed) * idle_rotation_y
	var idle_x = sin(time * idle_speed * 0.63) * idle_rotation_x

	# -------------------------
	# Zielrotation
	# -------------------------

	var target_rotation := start_rotation

	# Starker Idle-Schwenk
	target_rotation.y += idle_y
	target_rotation.x += idle_x

	# Maus-Parallax zusätzlich
	target_rotation.y -= mouse.x * max_rotation_y
	target_rotation.x -= mouse.y * max_rotation_x

	# Kamera weich drehen
	rotation_degrees = rotation_degrees.lerp(
		target_rotation,
		clamp(smooth_speed * delta, 0.0, 1.0)
	)

	# -------------------------
	# Zielposition
	# -------------------------

	var target_position := start_position

	# Automatische seitliche Kamerafahrt
	target_position.x += sin(time * idle_speed) * idle_move_x

	# Maus-Parallax
	target_position.x += mouse.x * move_amount
	target_position.y -= mouse.y * move_amount

	# Kamera weich bewegen
	position = position.lerp(
		target_position,
		clamp(smooth_speed * delta, 0.0, 1.0)
	)
