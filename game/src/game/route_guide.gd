class_name RouteGuide
extends MeshInstance3D
## A soft blue ribbon painted on the road along the next ~35 m of the exam
## route, plus glowing strips over the lines that matter in the current
## exercise (stop / fixation / start / end lines).

const AHEAD := 36.0
const WIDTH := 0.55

var data: CourseData
var director: ExamDirector
var course: CourseBuilder
var _mesh := ImmediateMesh.new()
var _t := 0.0
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


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.1
	_mesh.clear_surfaces()
	if director == null or director.state != ExamDirector.State.RUNNING:
		return
	var show_route := Session.route_visible()
	var s0 := director.tracker.s + 2.0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var wrote := false
	# A parking exercise (current, or coming up within the ribbon's reach)
	# shows its own way in: the ribbon stops where the manoeuvre leaves the
	# route, a bar marks the stop, and the guide takes over from there.
	var guided := _guided_exercise(s0)
	var s_end := s0 + AHEAD
	if guided:
		s_end = minf(s_end, _guide_start_s(guided))
	if show_route:
		var step := 1.0
		var s := s0
		while s < s_end - 0.01:
			step = minf(1.0, s_end - s)
			var a := data.route_point(s)
			var b := data.route_point(s + step)
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * WIDTH * 0.5
			var fade_a := 1.0 - (s - s0) / AHEAD
			var fade_b := 1.0 - (s + step - s0) / AHEAD
			var ca := Color(0.3, 0.62, 1.0, 0.33 * fade_a)
			var cb := Color(0.3, 0.62, 1.0, 0.33 * fade_b)
			_quad(a + n, a - n, b + n, b - n, ca, ca, cb, cb)
			wrote = true
			s += step
	if show_route and guided:
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
	if Session.hints_enabled():
		var ex := director.current_exercise()
		if ex:
			for line in ex.highlight:
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
