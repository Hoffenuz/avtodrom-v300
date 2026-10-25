class_name ExamMap
extends Control
## The results' map: the course seen from straight above (rendered once, from
## the drive's own world, so it is the course the candidate drove), the way
## the car went (reversing in another colour) and a numbered mark where each
## penalty came. A mark tapped is "picked": the results panel explains it.

signal picked(index: int)

const HEIGHT := 160.0
const ASPECT := 2.0 # width / height of what is shown
const MARGIN := 4.0 # metres around the course
const PRACTICE_MARGIN := 12.0
const FWD := Color(0.35, 0.72, 1.0)
const REV := Color(1.0, 0.62, 0.25)

var _track := PackedVector2Array()
var _rev := PackedByteArray()
var _marks: Array[Vector2] = [] # world positions of the penalties, by entry index
var _colors: Array[Color] = []
var _origin := Vector2.ZERO # world x, z at the map's top-left corner
var _span := Vector2.ONE # metres shown
var _selected := -1
var _view: SubViewport


## [param r] is the result sheet (ExamDirector.result()); [param course] the
## course it was driven on.
func setup(r: Dictionary, course: CourseData) -> void:
	_track = r.get("track", PackedVector2Array())
	_rev = r.get("track_rev", PackedByteArray())
	for e: Dictionary in r.get("entries", []):
		var p: Array = e.get("pos", [])
		_marks.append(Vector2(p[0], p[1]) if p.size() == 2 else Vector2.INF)
		var pts := int(e["points"])
		_colors.append(UITheme.CAUTION if pts < 20 else (UITheme.STOP if pts >= 50 else Color(1.0, 0.55, 0.2)))
	var area := Rect2()
	if r.get("practice", false) and not _track.is_empty():
		# One exercise: close in on where it was driven.
		area = Rect2(_track[0], Vector2.ZERO)
		for p in _track:
			area = area.expand(p)
		area = area.grow(PRACTICE_MARGIN)
	elif course and not course.fence.is_empty():
		area = Rect2(course.fence[0], Vector2.ZERO)
		for p in course.fence:
			area = area.expand(p)
		area = area.grow(MARGIN)
	else:
		area = Rect2(-90, -45, 180, 90)
	# Widen the short side so the shape is always ASPECT: the panel's box.
	var c := area.get_center()
	_span = area.size
	_span.x = maxf(_span.x, _span.y * ASPECT)
	_span.y = _span.x / ASPECT
	_origin = c - _span * 0.5
	custom_minimum_size = Vector2(320.0 * ASPECT, 320.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_view = SubViewport.new()
	var w := 900 if Settings.is_mobile() else 1280
	_view.size = Vector2i(w, int(w / ASPECT))
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_view)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = _span.y
	cam.near = 1.0
	cam.far = HEIGHT + 40.0
	cam.rotation_degrees = Vector3(-90, 0, 0) # screen up = -z, right = +x
	var c := _origin + _span * 0.5
	cam.position = Vector3(c.x, HEIGHT, c.y)
	var main := get_viewport().get_camera_3d()
	if main:
		cam.cull_mask = (main.cull_mask | Car.LAYER_EXTERIOR) & ~(Car.LAYER_INTERIOR | Weather.LAYER_RAIN)
	var world := get_viewport().find_world_3d()
	if world and world.environment:
		# No haze from 160 m up: the drive's fog is tuned for eye level.
		var env: Environment = world.environment.duplicate()
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		if EnvironmentSetup.weather() == "night":
			# Moonlight is too dark to read a map by.
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.55, 0.57, 0.62)
			env.tonemap_exposure = 1.6
		cam.environment = env
	_view.add_child(cam)
	cam.current = true


func select(index: int) -> void:
	_selected = index
	queue_redraw()


func _map_rect() -> Rect2:
	var s := size
	var w := minf(s.x, s.y * ASPECT)
	var h := w / ASPECT
	return Rect2((s.x - w) * 0.5, (s.y - h) * 0.5, w, h)


func _to_map(p: Vector2, rect: Rect2) -> Vector2:
	return rect.position + (p - _origin) / _span * rect.size


func _draw() -> void:
	var rect := _map_rect()
	draw_texture_rect(_view.get_texture(), rect, false)
	draw_rect(rect, Color(1, 1, 1, 0.18), false, 1.0)
	_draw_track(rect)
	var shown: Array[Vector2] = []
	for i in _marks.size():
		if _marks[i] == Vector2.INF or i == _selected:
			continue
		shown.append(_draw_mark(i, rect, shown))
	if _selected >= 0 and _selected < _marks.size() and _marks[_selected] != Vector2.INF:
		_draw_mark(_selected, rect, shown)


func _draw_track(rect: Rect2) -> void:
	if _track.size() < 2:
		return
	# Runs of one direction, each a polyline over a dark edge.
	var run := PackedVector2Array([_to_map(_track[0], rect)])
	var rev := _rev.size() > 0 and _rev[0] == 1
	for i in range(1, _track.size()):
		var r := i < _rev.size() and _rev[i] == 1
		run.append(_to_map(_track[i], rect))
		if r != rev or i == _track.size() - 1:
			if run.size() >= 2:
				draw_polyline(run, Color(0, 0, 0, 0.55), 5.0, true)
				draw_polyline(run, REV if rev else FWD, 2.5, true)
			run = PackedVector2Array([run[run.size() - 1]])
			rev = r
	draw_circle(_to_map(_track[0], rect), 6.0, UITheme.GO)
	draw_circle(_to_map(_track[_track.size() - 1], rect), 6.0, Color.WHITE)


## Draws mark [param i]; one landing on an earlier one moves aside so both
## numbers can be read. Returns where it was drawn.
func _draw_mark(i: int, rect: Rect2, shown: Array[Vector2]) -> Vector2:
	var at := _to_map(_marks[i], rect)
	for other in shown:
		if at.distance_to(other) < 20.0:
			at = other + Vector2(20, -8)
	var big := i == _selected
	var r := 15.0 if big else 11.0
	draw_circle(at, r + 2.0, Color.WHITE if big else Color(0, 0, 0, 0.7))
	draw_circle(at, r, _colors[i])
	var f := UITheme.bold()
	var fs := 17 if big else 13
	var label := str(i + 1)
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, at + Vector2(-tw.x * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.06, 0.06, 0.07))
	return at


func _gui_input(event: InputEvent) -> void:
	var at := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		at = event.position
	if at == Vector2.INF:
		return
	var rect := _map_rect()
	var best := -1
	var best_d := 30.0
	for i in _marks.size():
		if _marks[i] == Vector2.INF:
			continue
		var d := _to_map(_marks[i], rect).distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		select(best)
		picked.emit(best)
		accept_event()
