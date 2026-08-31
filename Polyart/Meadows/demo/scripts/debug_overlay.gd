extends CanvasLayer
## F3 shows an in-game stats overlay: rendering, memory and scene counters.
## F4 tints every Terrain3D scatter batch by detail level, green for LOD0 then
## yellow, orange and red.

const LOD_COLORS := [Color(0.2, 1.0, 0.2), Color(1.0, 0.9, 0.2),
	Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.2)]

var _label: Label
var _accum := 0.0
var _lod_view := false
var _grass_hidden := false
var _saved_overrides := {}   # instance_id to original material
var _lod_counts := [0, 0, 0, 0]

func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.self_modulate = Color(1, 1, 1, 0.85)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	panel.add_child(_label)
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
		elif event.physical_keycode == KEY_F4:
			_toggle_lod_view()
		elif event.physical_keycode == KEY_F6:
			_toggle_group("Trees")
		elif event.physical_keycode == KEY_F7:
			_toggle_group("Statics")
		elif event.physical_keycode == KEY_8:
			_grass_hidden = not _grass_hidden
			_walk_toggle_grass(get_tree().root)
		elif event.physical_keycode == KEY_9:
			var t := _find_terrain()
			if t:
				t.visible = not t.visible

func _find_terrain() -> Terrain3D:
	var demo := get_tree().current_scene
	return demo.get_node_or_null(^"Terrain3D") as Terrain3D if demo else null

func _walk_toggle_grass(n: Node) -> void:
	if n is MultiMeshInstance3D and n.name.begins_with("MMI3D"):
		n.visible = not _grass_hidden
	for c in n.get_children():
		_walk_toggle_grass(c)

func _toggle_group(group_name: String) -> void:
	var demo := get_tree().current_scene
	if demo == null:
		return
	var n: Node3D = demo.get_node_or_null(NodePath(group_name))
	if n:
		n.visible = not n.visible

func _toggle_lod_view() -> void:
	_lod_view = not _lod_view
	_lod_counts = [0, 0, 0, 0]
	var mats: Array[StandardMaterial3D] = []
	for c in LOD_COLORS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		mats.append(m)
	_walk_mmis(get_tree().root, mats)
	if not _lod_view:
		_saved_overrides.clear()

func _walk_mmis(n: Node, mats: Array[StandardMaterial3D]) -> void:
	if n is MultiMeshInstance3D and n.name.begins_with("MMI3D"):
		var lstr := String(n.name).get_slice("_L", 1)
		if lstr != "" and lstr != "S":
			var lod := clampi(int(lstr), 0, 3)
			if _lod_view:
				_saved_overrides[n.get_instance_id()] = n.material_override
				n.material_override = mats[lod]
				_lod_counts[lod] += n.multimesh.instance_count if n.multimesh else 0
			else:
				n.material_override = _saved_overrides.get(n.get_instance_id(), null)
	for c in n.get_children():
		_walk_mmis(c, mats)

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	var fps := Engine.get_frames_per_second()
	_label.text = "\n".join([
		" FPS: %d  (%.2f ms)" % [fps, 1000.0 / maxf(fps, 1.0)],
		" Draw calls: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" Objects drawn: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		" Triangles: %s" % _fmt(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		" Video RAM: %.0f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		" Texture RAM: %.0f MB" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		" Buffer RAM: %.0f MB" % (Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		" Static RAM: %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		" Process: %.2f ms   Physics: %.2f ms" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		" Nodes: %d   Orphans: %d" % [
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)],
		" Physics active: %d" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		" Res: %s   VSync: %s" % [
			str(get_viewport().get_visible_rect().size),
			"on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off"],
		" LOD view (F4): %s" % ("ON  L0:%d L1:%d L2:%d L3:%d placed" % [
			_lod_counts[0], _lod_counts[1], _lod_counts[2], _lod_counts[3]] if _lod_view else "off"),
		" Keys: F4 lod colors | F6 trees | F7 props | 8 grass | 9 terrain",
	])

func _fmt(v: float) -> String:
	if v >= 1e6:
		return "%.1fM" % (v / 1e6)
	if v >= 1e3:
		return "%.1fK" % (v / 1e3)
	return str(int(v))
