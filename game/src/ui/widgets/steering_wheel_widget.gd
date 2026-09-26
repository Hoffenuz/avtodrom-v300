class_name SteeringWheelWidget
extends Control
## On-screen steering wheel. Grab it anywhere and turn: the finger's angle
## around the centre drives the wheel 1:1, over as many turns as the car's
## lock allows (the Nexia has 1.5 turns each way). Letting go leaves the
## wheel where it is when stationary and lets it self-centre when moving,
## like a real car's caster does.

signal steered(deg: float)

var lock_deg := 540.0
var angle_deg := 0.0
var sensitivity := 1.0
var autocenter := true
## Set every frame by the drive scene: car speed in m/s (self-centring grows with it).
var car_speed := 0.0
var _touch := -1
var _last_ang := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var c := size * 0.5
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_touch = event.index
			_last_ang = (event.position - c).angle()
		elif not event.pressed and event.index == _touch:
			_touch = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		var v: Vector2 = event.position - c
		if v.length() > 12.0:
			var ang := v.angle()
			var d := wrapf(ang - _last_ang, -PI, PI)
			_last_ang = ang
			angle_deg = clampf(angle_deg + rad_to_deg(d) * sensitivity, -lock_deg, lock_deg)
			steered.emit(angle_deg)
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()


## The app lost focus mid-touch: no finger-up will arrive.
func release_touch() -> void:
	_touch = -1


func is_held() -> bool:
	return _touch >= 0


func _process(delta: float) -> void:
	if _touch < 0 and autocenter and absf(angle_deg) > 0.01:
		var rate := clampf(absf(car_speed) * 70.0, 0.0, 480.0)
		if rate > 0.0:
			angle_deg = move_toward(angle_deg, 0.0, rate * delta)
			steered.emit(angle_deg)
			queue_redraw()


func set_angle(deg: float) -> void:
	angle_deg = clampf(deg, -lock_deg, lock_deg)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var rot := deg_to_rad(angle_deg)
	# Rim.
	draw_arc(c, r * 0.86, 0, TAU, 64, Color(0.07, 0.08, 0.09, 0.9), r * 0.2, true)
	draw_arc(c, r * 0.86, 0, TAU, 64, Color(1, 1, 1, 0.09), 2.0, true)
	draw_arc(c, r * 0.96, 0, TAU, 64, Color(1, 1, 1, 0.12), 1.5, true)
	# Spokes at 3, 6 and 9 o'clock (screen angles grow clockwise), then the hub.
	for base in [0.0, PI * 0.5, PI]:
		var dir := Vector2(cos(rot + base), sin(rot + base))
		draw_line(c + dir * r * 0.26, c + dir * r * 0.76, Color(0.1, 0.11, 0.12, 0.95), r * 0.14, true)
	draw_circle(c, r * 0.3, Color(0.12, 0.13, 0.15, 0.95))
	draw_arc(c, r * 0.3, 0, TAU, 32, Color(1, 1, 1, 0.12), 2.0, true)
	# Top-centre marker shows how far round the wheel is.
	var top := Vector2(cos(rot - PI * 0.5), sin(rot - PI * 0.5))
	draw_line(c + top * r * 0.76, c + top * r * 0.96, UITheme.CAUTION, r * 0.08, true)
	# Turns read-out (e.g. 1.2 ↻).
	var turns := angle_deg / 360.0
	if absf(turns) > 0.02:
		var f := UITheme.bold()
		var txt := "%s%.1f" % ["→ " if turns > 0 else "← ", absf(turns)]
		var fs := 18
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_DIM)
