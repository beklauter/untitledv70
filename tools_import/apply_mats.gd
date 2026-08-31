@tool
# Post-import hook driven by tools_import/mat_overrides.json.
# Entry formats per source fbx:
#   ["res://...tres", null, ...]                      old form, materials by order
#   {"mats": [...], "fix_normals": ["_LOD1", ...]}    materials, normal rebuild, or both
# fix_normals: meshes whose node name ends with a listed suffix get their normals
# regenerated FLAT from geometry (some source LODs ship broken vertex normals).
extends EditorScenePostImport

const MAP_PATH := "res://tools_import/mat_overrides.json"

func _post_import(scene: Node) -> Node:
	var text := FileAccess.get_file_as_string(MAP_PATH)
	var map: Dictionary = JSON.parse_string(text) if text else {}
	var entry: Variant = map.get(get_source_file())
	var mats: Array = []
	var fix_suffixes: Array = []
	if entry is Array:
		mats = entry
	elif entry is Dictionary:
		mats = entry.get("mats", [])
		fix_suffixes = entry.get("fix_normals", [])
	if not mats.is_empty():
		_apply(scene, mats, {"i": 0})
	if not fix_suffixes.is_empty():
		_fix_normals(scene, fix_suffixes)
	return scene

func _apply(node: Node, mats: Array, state: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		for s in node.mesh.get_surface_count():
			if state.i < mats.size():
				var p = mats[state.i]
				if p != null and String(p) != "":
					node.mesh.surface_set_material(s, load(String(p)))
				state.i += 1
	for c in node.get_children():
		_apply(c, mats, state)

func _fix_normals(node: Node, suffixes: Array) -> void:
	if node is MeshInstance3D and node.mesh:
		for suf in suffixes:
			if String(node.name).ends_with(String(suf)):
				node.mesh = _rebuilt_flat(node.mesh)
				break
	for c in node.get_children():
		_fix_normals(c, suffixes)

func _rebuilt_flat(mesh: Mesh) -> ArrayMesh:
	# Per-face normals computed from geometry, oriented by the ORIGINAL vertex
	# normals' hemisphere (they are skewed, not reversed, so they point the way).
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx_v = a[Mesh.ARRAY_INDEX]
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nu := PackedVector2Array()
		var tri_count: int = ((idx_v as PackedInt32Array).size() if idx_v != null else verts.size()) / 3
		for t in tri_count:
			var i := [0, 0, 0]
			for k in 3:
				i[k] = (idx_v as PackedInt32Array)[t * 3 + k] if idx_v != null else t * 3 + k
			var p0 := verts[i[0]]
			var p1 := verts[i[1]]
			var p2 := verts[i[2]]
			var fn := (p1 - p0).cross(p2 - p0)
			if fn.length_squared() < 1e-12:
				continue
			fn = fn.normalized()
			var ref := (norms[i[0]] + norms[i[1]] + norms[i[2]])
			if fn.dot(ref) < 0.0:
				fn = -fn
			for k in 3:
				nv.append(verts[i[k]])
				nn.append(fn)
				if uvs.size() > i[k]:
					nu.append(uvs[i[k]])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = nv
		arrays[Mesh.ARRAY_NORMAL] = nn
		if nu.size() == nv.size():
			arrays[Mesh.ARRAY_TEX_UV] = nu
		var tmp := ArrayMesh.new()
		tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# tangents for the normal-mapped material
		var st := SurfaceTool.new()
		st.create_from(tmp, 0)
		if nu.size() == nv.size():
			st.generate_tangents()
		st.set_material(mesh.surface_get_material(s))
		st.commit(out)
	return out
