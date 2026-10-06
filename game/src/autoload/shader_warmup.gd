class_name ShaderWarmup
## Compiles a scene's material shaders one per frame behind the loading page.
##
## On OpenGL a shader compiles the first time something draws with it. A new
## scene's first frame used to build every one at once: tens of seconds in
## one frame in a browser (WebGL runs through Direct3D on Windows, about a
## second per shader), long enough for the browser to call the page frozen,
## and seconds on a phone's first start. Here the scene stays hidden and a
## small quad per distinct material is drawn in front of its camera, one more
## each frame, under the same sun and sky, so the frame where the scene shows
## has nothing left to build. Once the shaders are cached (the browser and
## Godot keep them), each step takes a frame.

const LAYER := 1 << 19


## Whether this renderer compiles shaders on first draw (OpenGL).
static func enabled() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Hidden from the 3D camera until warm() shows it (the loading page covers it).
static func hide_3d(tree: SceneTree) -> void:
	if enabled():
		tree.root.disable_3d = true


## progress(done, total) runs before each step.
static func warm(scene: Node, progress: Callable) -> void:
	var tree := scene.get_tree()
	var cam := tree.root.get_camera_3d()
	tree.root.disable_3d = false
	if cam == null:
		return
	var t0 := Time.get_ticks_msec()
	var found := {}
	# Two frames: the car's lamps alternate between their lit looks (lamp_prewarm).
	_collect(scene, found)
	await tree.process_frame
	if not is_instance_valid(cam):
		return
	_collect(scene, found)
	var subviews: Array[SubViewport] = []
	_find_subviews(scene, subviews)
	subviews = subviews.filter(func(vp: SubViewport) -> bool: return not vp.disable_3d)
	for vp in subviews:
		vp.disable_3d = true # mirrors: they show the same materials
	var mask := cam.cull_mask
	cam.cull_mask = LAYER
	var holder := Node3D.new()
	holder.name = "ShaderWarmup"
	cam.add_child(holder)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var keys := found.keys()
	for i in keys.size():
		progress.call(i, keys.size())
		var e: Array = found[keys[i]]
		var gi: GeometryInstance3D
		if e[1]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = quad
			mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			gi = mmi
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			gi = mi
		gi.material_override = e[0]
		gi.layers = LAYER
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.position = Vector3((i % 5 - 2) * 0.25, (i / 5 % 3 - 1) * 0.25, -2.0)
		holder.add_child(gi)
		await RenderingServer.frame_post_draw
		if not is_instance_valid(cam):
			return # the scene went away meanwhile
	progress.call(keys.size(), keys.size())
	holder.queue_free()
	cam.cull_mask = mask
	for vp in subviews:
		if is_instance_valid(vp):
			vp.disable_3d = false
	print("WARM %d shaders in %d ms" % [keys.size(), Time.get_ticks_msec() - t0])


## Distinct shaders: key -> [material, drawn through a MultiMesh].
static func _collect(n: Node, found: Dictionary) -> void:
	if n is GeometryInstance3D and n.visible:
		var multi := n is MultiMeshInstance3D
		var mats: Array[Material] = []
		if n.material_override:
			mats.append(n.material_override)
		else:
			var mesh: Mesh = null
			if n is MeshInstance3D:
				mesh = n.mesh
			elif multi and n.multimesh:
				mesh = n.multimesh.mesh
			if mesh:
				for i in mesh.get_surface_count():
					var m: Material = n.get_surface_override_material(i) if n is MeshInstance3D else null
					if m == null:
						m = mesh.surface_get_material(i)
					if m:
						mats.append(m)
		for m in mats:
			var k := _key(m) + ("|mm" if multi else "")
			if k != "" and not found.has(k):
				found[k] = [m, multi]
	for c in n.get_children():
		_collect(c, found)


static func _find_subviews(n: Node, out: Array[SubViewport]) -> void:
	if n is SubViewport:
		out.append(n)
	for c in n.get_children():
		_find_subviews(c, out)


## What tells two materials' shaders apart: the shader itself, or for the
## built-in material the settings it generates its shader from.
static func _key(m: Material) -> String:
	if m is ShaderMaterial:
		return "s%d" % m.shader.get_rid().get_id() if m.shader else ""
	if m is BaseMaterial3D:
		var s := "b%d.%d.%d.%d.%d.%d.%d.%d.%d" % [m.transparency, m.shading_mode, m.cull_mode, m.depth_draw_mode,
				m.diffuse_mode, m.specular_mode, m.blend_mode, m.texture_filter, m.billboard_mode]
		for i in BaseMaterial3D.FLAG_MAX:
			s += "1" if m.get_flag(i) else "0"
		for i in BaseMaterial3D.FEATURE_MAX:
			s += "1" if m.get_feature(i) else "0"
		return s
	return ""
