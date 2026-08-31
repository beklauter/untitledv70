@tool
class_name PAGradientFog
extends MeshInstance3D
## Feeds the scene's sun direction to the gradient fog material.
## The quad covers the screen from its shader, so its position does not matter.
## Only its cull margin does, which the scene sets large.

func _ready() -> void:
	set_notify_transform(false)
	_push_sun()

func _process(_delta: float) -> void:
	_push_sun()

func _push_sun() -> void:
	var mat := get_active_material(0) as ShaderMaterial
	if mat == null:
		return
	var sun := _find_sun(get_tree().current_scene if Engine.is_editor_hint() else get_tree().root)
	if sun == null:
		return
	mat.set_shader_parameter("sun_direction", -sun.global_transform.basis.z)

func _find_sun(n: Node) -> DirectionalLight3D:
	if n == null:
		return null
	if n is DirectionalLight3D and (n as DirectionalLight3D).visible:
		return n
	for c in n.get_children():
		var found := _find_sun(c)
		if found != null:
			return found
	return null
