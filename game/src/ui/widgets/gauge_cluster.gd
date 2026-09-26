class_name GaugeCluster
extends Control
## Instrument cluster: speedometer with the avtodrom limits marked (20 km/h
## amber, 40 km/h red), tachometer with the stall zone and redline, the
## selected gear, and the warning lamps a learner must watch.

var car: Car
var speed_kmh := 0.0
var rpm := 0.0
var gear_text := "N"
var _blink := false
var _drawn := [] # what the last _draw showed; redraw only when it changes
var _bg_box := UITheme.box(Color(0.05, 0.06, 0.08, 0.82), 28, 1, UITheme.LINE, 0)
var _gear_box := UITheme.box(Color(1, 1, 1, 0.07), 12, 0, UITheme.LINE, 0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(430, 190)
	Loc.language_changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if car == null:
		return
	speed_kmh = absf(car.get_speed_kmh())
	rpm = car.get_rpm() if car.ignition else 0.0
	gear_text = AvtoGear.label(car)
	_blink = car.blink_lit
	# The dials move in visible steps of ~0.1 km/h and 20 rpm; below that a
	# redraw would repaint the same picture.
	var shown := [roundi(speed_kmh * 10.0), roundi(rpm / 20.0), gear_text, car.left_lit(), car.right_lit(),
			car.ignition, car.seatbelt, car.handbrake > 0.5, car.is_engine_running(), car.is_abs_active()]
	if shown != _drawn:
		_drawn = shown
		queue_redraw()


func _dial(c: Vector2, r: float, a0: float, a1: float, value: float, vmax: float, color: Color, width: float) -> void:
	draw_arc(c, r, a0, a1, 48, Color(1, 1, 1, 0.1), width, true)
	var t := clampf(value / vmax, 0.0, 1.0)
	if t > 0.001:
		draw_arc(c, r, a0, lerpf(a0, a1, t), 48, color, width, true)


func _tick_mark(c: Vector2, r: float, a: float, len_: float, color: Color, w: float) -> void:
	var d := Vector2(cos(a), sin(a))
	draw_line(c + d * (r - len_), c + d * r, color, w, true)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_bg_box, rect)
	var f := UITheme.bold()
	var fr := UITheme.regular()

	# Speedometer 0–60 km/h (the avtodrom never needs more).
	var sc := Vector2(size.x * 0.34, size.y * 0.6)
	var sr := size.y * 0.46
	var a0 := PI * 0.8
	var a1 := PI * 2.2
	var vmax := 60.0
	var col := UITheme.GO
	if speed_kmh > 40.5:
		col = UITheme.STOP
	elif speed_kmh > 20.5:
		col = UITheme.CAUTION
	_dial(sc, sr, a0, a1, speed_kmh, vmax, col, 12.0)
	for v in [0, 10, 20, 30, 40, 50, 60]:
		var a := lerpf(a0, a1, v / vmax)
		var tc := UITheme.CAUTION if v == 20 else (UITheme.STOP if v == 40 else Color(1, 1, 1, 0.45))
		_tick_mark(sc, sr - 10.0, a, 14.0 if v % 20 == 0 else 8.0, tc, 3.0 if v % 20 == 0 else 2.0)
	var st := "%d" % int(round(speed_kmh))
	var fs := 58
	var sw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, sc + Vector2(-sw * 0.5, 14), st, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT)
	var unit := Loc.t("hud.kmh")
	var uw := fr.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(fr, sc + Vector2(-uw * 0.5, 38), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.TEXT_DIM)

	# Tachometer.
	var tc2 := Vector2(size.x * 0.76, size.y * 0.47)
	var tr := size.y * 0.3
	var rmax := 7000.0
	var idle := car.get_idle_rpm() if car else 850.0
	var red := car.get_redline_rpm() if car else 6000.0
	var rcol := UITheme.INFO
	if rpm > red:
		rcol = UITheme.STOP
	elif car and car.ignition and car.is_engine_running() and rpm < idle - 200.0:
		rcol = UITheme.CAUTION
	_dial(tc2, tr, a0, a1, rpm, rmax, rcol, 8.0)
	draw_arc(tc2, tr + 7.0, lerpf(a0, a1, red / rmax), a1, 16, UITheme.STOP, 3.0, true)
	var rt := "%.1f" % (rpm / 1000.0)
	var rw := f.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(f, tc2 + Vector2(-rw * 0.5, 8), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UITheme.TEXT)
	var rl := Loc.t("hud.rpm")
	var rlw := fr.get_string_size(rl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(fr, tc2 + Vector2(-rlw * 0.5, 26), rl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_FAINT)

	# Gear.
	var gbox := Rect2(tc2.x - 34, size.y - 58, 68, 46)
	draw_style_box(_gear_box, gbox)
	var gw := f.get_string_size(gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	draw_string(f, gbox.get_center() + Vector2(-gw * 0.5, 12), gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32,
			UITheme.CAUTION if gear_text == "R" else UITheme.TEXT)

	# Warning lamps row (top).
	if car == null:
		return
	var y := 24.0
	var x := 26.0
	var s := 11.0
	var lamps := []
	lamps.append(["left", UITheme.INDICATOR, car.left_lit()])
	lamps.append(["right", UITheme.INDICATOR, car.right_lit()])
	lamps.append(["belt", UITheme.STOP, car.ignition and not car.seatbelt])
	lamps.append(["handbrake", UITheme.STOP, car.ignition and car.handbrake > 0.5])
	lamps.append(["engine", UITheme.CAUTION, car.ignition and not car.is_engine_running()])
	lamps.append(["abs", UITheme.CAUTION, car.is_abs_active()])
	for l in lamps:
		var on: bool = l[2]
		Icons.draw(self, l[0], Vector2(x, y), s, l[1] if on else Color(1, 1, 1, 0.12))
		x += 30.0
