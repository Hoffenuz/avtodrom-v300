class_name RouteGuide
extends MeshInstance3D
## A soft blue ribbon painted on the road along the next ~35 m of the exam
## route, plus glowing strips over the lines that matter in the current
## exercise (stop / fixation / start / end lines).
##
## Nothing is rebuilt per frame: the ribbon is the whole route as one static
## mesh whose shader (route_ribbon.gdshader) shows the stretch ahead of the
## car, and the overlay (parking guides, highlighted lines) is redrawn only
## when what it shows changes. Rebuilding a mesh ten times a second made a
## new GPU buffer each time, which phone drivers map and release lazily: a
## long drive ran a phone out of memory maps (Scudo "Out of memory").

const AHEAD := 36.0
const WIDTH := 0.55
const STEP := 1.0

var data: CourseData
var director: ExamDirector
var course: CourseBuilder
var _mesh := ImmediateMesh.new()
var _ribbon: MeshInstance3D
var _ribbon_mat: ShaderMaterial
## What the overlay shows now; it is redrawn only when this changes.
var _overlay_key := ""
## Exercise id -> route s where its parking guide leaves the route.
var _guide_s := {}


func setup(p_data: CourseData, p_director: ExamDirector, p_course: CourseBuilder) -> void:
	data = p_data
	director = p_director
	course = p_course
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	m.render_priority = 2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	_build_ribbon()


## The whole route as one strip, UV.x = route length s.
func _build_ribbon() -> void:
	var length := data.route_length()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var s := 0.0
	while s <= length + 0.001:
		var p := data.route_point(minf(s, length))
		var d := data.route_point(minf(s + 0.5, length)) - data.route_point(maxf(minf(s, length) - 0.5, 0.0))
		d = d.normalized() if d.length() > 1e-6 else Vector2(1, 0)
		var n := Vector2(-d.y, d.x) * WIDTH * 0.5
		for q in [p + n, p - n]:
			verts.append(Vector3(q.x, _y(q), q.y))
			uvs.append(Vector2(s, 0.0))
		s += STEP
	var idx := PackedInt32Array()
	for i in range(0, verts.size() - 2, 2):
		idx.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = preload("res://assets/shaders/route_ribbon.gdshader")
	_ribbon_mat.render_priority = 2
	_ribbon_mat.set_shader_parameter("ahead", AHEAD)
	_ribbon = MeshInstance3D.new()
	_ribbon.name = "Ribbon"
	_ribbon.mesh = am
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The route's box is the whole site: never culled by distance.
	_ribbon.extra_cull_margin = 4.0
	_ribbon.visible = false
	add_child(_ribbon)


func _process(_delta: float) -> void:
	var running := director != null and director.state == ExamDirector.State.RUNNING
	var show_route := running and Session.route_visible()
	var s0 := director.tracker.s + 2.0 if running else 0.0
	var guided := _guided_exercise(s0) if running else null
	# The ribbon: only its window moves.
	_ribbon.visible = show_route
	if show_route:
		var s_end := s0 + AHEAD
		if guided:
			s_end = minf(s_end, _guide_start_s(guided))
		_ribbon_mat.set_shader_parameter("s0", s0)
		_ribbon_mat.set_shader_parameter("s_end", s_end)
	# The overlay: redrawn when the exercise, the guide or the hints change.
	var cur := director.current_exercise() if running else null
	var key := "%s|%s|%s|%s" % [guided.id if guided and show_route else "",
			cur.id if cur and Session.hints_enabled() else "", show_route, running]
	if key != _overlay_key:
		_overlay_key = key
		_draw_overlay(guided if show_route else null, cur if Session.hints_enabled() else null)


func _draw_overlay(guided: Exercise, cur: Exercise) -> void:
	_mesh.clear_surfaces()
	var wrote := false
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if guided:
		# Parking exercises: the way into the bay or pocket and the spot to stop in.
		var g: Dictionary = guided.def["guide"]
		var c := Color(0.3, 0.62, 1.0, 0.3)
		var paths: Array = g.get("paths", [])
		for pi in paths.size():
			var pts := CourseData.poly(paths[pi])
			for i in pts.size() - 1:
				_segment(pts[i], pts[i + 1], WIDTH * 0.8, c)
			# Chevrons show which way each leg is driven (forward, then back in).
			var along := 0.0
			for i in pts.size() - 1:
				var L := pts[i].distance_to(pts[i + 1])
				var d := (pts[i + 1] - pts[i]) / maxf(L, 0.001)
				var at := 1.2 - along
				while at < L:
					_chevron(pts[i] + d * at, d, Color(1, 1, 1, 0.7))
					at += 2.4
				along = fmod(along + L, 2.4)
			if pi == 0 and pts.size() > 1:
				# Stop bar where the manoeuvre starts, across the direction of travel.
				var d0 := data.route_dir(_guide_start_s(guided))
				var n0 := Vector2(-d0.y, d0.x)
				_segment(pts[0] - n0 * 1.0, pts[0] + n0 * 1.0, 0.3, Color(1.0, 1.0, 1.0, 0.6))
		var spot := CourseData.poly(g.get("spot", []))
		for i in spot.size():
			_segment(spot[i], spot[(i + 1) % spot.size()], 0.14, Color(0.3, 0.62, 1.0, 0.55))
		wrote = true
	if cur:
		for line in cur.highlight:
			var a := CourseData.v2(line["a"])
			var b := CourseData.v2(line["b"])
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * 0.22
			# Green "put the wheels here": yellow would read as the box's limit line.
			var c := Color(0.25, 0.9, 0.45, 0.5)
			_quad(a + n, a - n, b + n, b - n, c, c, c, c)
			wrote = true
	if wrote:
		_mesh.surface_end()
	else:
		_mesh.clear_surfaces()


## The parking exercise whose guide is shown: the current one, or the next
## one once its start is within the ribbon's reach.
func _guided_exercise(s0: float) -> Exercise:
	var cur := director.current_exercise()
	if cur:
		return cur if cur.def.has("guide") else null
	var up := director.upcoming_exercise()
	if up and up.def.has("guide") and up.s0 - s0 < AHEAD:
		return up
	return null


## Route s nearest to where the exercise's guide begins (cached).
func _guide_start_s(ex: Exercise) -> float:
	if _guide_s.has(ex.id):
		return _guide_s[ex.id]
	var p0 := CourseData.v2(ex.def["guide"]["paths"][0][0])
	var best_s := ex.s0
	var best_d := INF
	var s := ex.s0 - 10.0
	while s <= ex.s1 + 10.0:
		var d := data.route_point(s).distance_squared_to(p0)
		if d < best_d:
			best_d = d
			best_s = s
		s += 0.25
	_guide_s[ex.id] = best_s
	return best_s


## A small painted ">" pointing along d.
func _chevron(p: Vector2, d: Vector2, c: Color) -> void:
	var n := Vector2(-d.y, d.x)
	var tip := p + d * 0.35
	_segment(tip, p - d * 0.25 + n * 0.3, 0.1, c)
	_segment(tip, p - d * 0.25 - n * 0.3, 0.1, c)


func _segment(a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * width * 0.5
	_quad(a + n, a - n, b + n, b - n, c, c, c, c)


func _y(p: Vector2) -> float:
	return (course.estakada_height(p.x, p.y) if course else 0.0) + CourseBuilder.PAINT_Y + 0.015


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var va := Vector3(a.x, _y(a), a.y)
	var vb := Vector3(b.x, _y(b), b.y)
	var vc := Vector3(c.x, _y(c), c.y)
	var vd := Vector3(d.x, _y(d), d.y)
	for pair in [[va, ca], [vb, cb], [vc, cc], [vb, cb], [vd, cd], [vc, cc]]:
		_mesh.surface_set_color(pair[1])
		_mesh.surface_add_vertex(pair[0])
