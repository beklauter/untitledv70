@tool
class_name PARiverSpline
extends Path3D
## River builder. Edit this node's curve in the editor and the water ribbon
## follows live. U runs across the width, V counts metres along the curve, so
## a flow shader panning along V follows every bend.
## The mesh is rebuilt on load.

## River width in metres. See also [member width_profile].
@export var width := 4.0:
	set(v):
		width = v
		_regen()

## Optional width multiplier along the river, start to end.
@export var width_profile: Curve:
	set(v):
		width_profile = v
		_regen()

## Metres between mesh rows. Smaller follows tight bends closer.
@export_range(0.25, 8.0, 0.05) var step := 1.0:
	set(v):
		step = v
		_regen()

## Subdivisions across the river. The surface bob needs these to shape the
## middle of the channel.
@export_range(1, 16) var width_segments := 4:
	set(v):
		width_segments = v
		_regen()

## Metres of river per V unit. Sets how far the texture stretches.
@export var uv_length_scale := 4.0:
	set(v):
		uv_length_scale = v
		_regen()

## Water flows from the first curve point to the last. Tick to reverse.
@export var reverse_flow := false:
	set(v):
		reverse_flow = v
		_regen()

## Water material. Defaults to the pack's river water.
@export var material: Material:
	set(v):
		material = v
		_regen()

## Rounds off clicked path points. Turn it off to hand-tune the handles.
@export var auto_smooth := true:
	set(v):
		auto_smooth = v
		_regen()

## How far the smoothing reaches, as a fraction of the gap to the neighbour.
@export_range(0.05, 0.5, 0.01) var smooth_strength := 0.25:
	set(v):
		smooth_strength = v
		_regen()

var _mesh_child: MeshInstance3D
var _updating := false

func _ready() -> void:
	if material == null:
		material = load("res://Polyart/Meadows/materials/Water/M_Dreamscape_WaterRiver.tres")
	if not curve_changed.is_connected(_regen):
		curve_changed.connect(_regen)
	_regen()

func _regen() -> void:
	if _updating or not is_inside_tree():
		return
	if auto_smooth and curve != null and curve.point_count >= 2:
		# Tangents from each point's neighbours. Guarded: writing the handles
		# fires curve_changed again.
		_updating = true
		for i in curve.point_count:
			var prev := curve.get_point_position(maxi(i - 1, 0))
			var next := curve.get_point_position(mini(i + 1, curve.point_count - 1))
			var tangent := (next - prev) * smooth_strength
			curve.set_point_in(i, -tangent)
			curve.set_point_out(i, tangent)
		_updating = false
	if _mesh_child == null or not is_instance_valid(_mesh_child):
		_mesh_child = get_node_or_null("RiverMesh")
	if _mesh_child == null:
		_mesh_child = MeshInstance3D.new()
		_mesh_child.name = "RiverMesh"
		add_child(_mesh_child)
	if curve == null or curve.get_baked_length() < step * 2.0:
		_mesh_child.mesh = null
		return

	var length := curve.get_baked_length()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rows := int(ceil(length / step)) + 1
	for r in rows:
		var s := minf(float(r) * step, length)
		var center := curve.sample_baked(s, true)
		var ahead := curve.sample_baked(minf(s + 0.1, length), true)
		var behind := curve.sample_baked(maxf(s - 0.1, 0.0), true)
		var tangent := (ahead - behind)
		tangent.y = 0.0
		if tangent.length_squared() < 1e-8:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var side := Vector3.UP.cross(tangent).normalized()
		var half := width * 0.5
		if width_profile:
			half *= maxf(width_profile.sample_baked(s / length), 0.01)
		# V runs along the draw direction, first point to last.
		# reverse_flow flips it.
		var v_dist := s if reverse_flow else (length - s)
		var v := v_dist / maxf(uv_length_scale, 0.001)
		for c in width_segments + 1:
			var u := float(c) / float(width_segments)
			verts.append(center + side * half * (1.0 - 2.0 * u))
			norms.append(Vector3.UP)
			uvs.append(Vector2(u, v))
	var cols := width_segments + 1
	for r in rows - 1:
		for c in width_segments:
			var a := r * cols + c
			# Clockwise from above, so the quads face up under cull_back.
			idx.append_array([a, a + cols, a + 1, a + 1, a + cols, a + cols + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Tangents, so the flow normal maps line up along the ribbon.
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_tangents()
	st.set_material(material)
	_mesh_child.mesh = st.commit()
