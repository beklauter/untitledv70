extends Area3D

@export var surface_offset := 0.0
@export var flow := Vector3.ZERO

@onready var _shape: CollisionShape3D = $CollisionShape3D

func surface_level() -> float:
	if _shape == null:
		return global_position.y + surface_offset
	var box := _shape.shape as BoxShape3D
	if box == null:
		return _shape.global_position.y + surface_offset
	return _shape.global_position.y + box.size.y * 0.5 * _shape.global_basis.get_scale().y + surface_offset

func flow_velocity() -> Vector3:
	return global_basis * flow
