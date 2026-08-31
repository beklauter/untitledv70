@tool
class_name PALodGroup
extends Node3D
## Detail level control for the wrapper prefabs.
## Set [member lod_switch_distances] in metres, or move them all at once with
## [member distance_scale]. It drives the model's LOD0 to LODN children through
## their visibility ranges.

@export var lod_switch_distances: PackedFloat32Array = PackedFloat32Array():
	set(v):
		lod_switch_distances = v
		_apply()

## Multiplies every switch distance. 2.0 holds detail twice as far out.
@export_range(0.1, 8.0, 0.05) var distance_scale: float = 1.0:
	set(v):
		distance_scale = v
		_apply()

var _lod_re := RegEx.create_from_string("_LOD(\\d+)$")

func _ready() -> void:
	set_notify_transform(true)
	_apply()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	var model := get_node_or_null("Model")
	if model == null:
		return
	_walk(model, _world_scale())

## Switch distances scale with the instance's world scale, largest axis.
func _world_scale() -> float:
	var s := global_transform.basis.get_scale()
	return maxf(maxf(absf(s.x), absf(s.y)), absf(s.z))

func _walk(n: Node, ws: float) -> void:
	if n is MeshInstance3D:
		var m := _lod_re.search(n.name)
		if m:
			var i := int(m.get_string(1))
			var begin := 0.0
			var end := 0.0
			if i > 0 and i - 1 < lod_switch_distances.size():
				begin = lod_switch_distances[i - 1] * distance_scale * ws
			if i < lod_switch_distances.size():
				end = lod_switch_distances[i] * distance_scale * ws
			(n as MeshInstance3D).visibility_range_begin = begin
			(n as MeshInstance3D).visibility_range_end = end
	for c in n.get_children():
		_walk(c, ws)
