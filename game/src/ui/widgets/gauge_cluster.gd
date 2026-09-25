class_name GaugeCluster
extends Control
## Compact instrument strip: speed (amber above 20 km/h, red above 40 — the
## avtodrom limits), the selected gear and the indicator arrows. Warning lamps
## (belt, handbrake, engine, ABS) appear above it only while they are lit.

const W := 290.0
const H := 62.0

var car: Car


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)


func _process(_delta: float) -> void:
	if car and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if car == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(UITheme.box(Color(0.05, 0.06, 0.08, 0.8), int(size.y * 0.5), 1, UITheme.LINE, 0), rect)
	var f := UITheme.bold()
	var fr := UITheme.regular()
	var cy := size.y * 0.5
	# Indicator arrows at both ends.
	Icons.draw(self, "left", Vector2(26, cy), 10.0, UITheme.INDICATOR if car.left_lit() else Color(1, 1, 1, 0.14))
	Icons.draw(self, "right", Vector2(size.x - 26, cy), 10.0,
			UITheme.INDICATOR if car.right_lit() else Color(1, 1, 1, 0.14))
	# Speed.
	var kmh := absf(car.get_speed_kmh())
	var col := UITheme.TEXT
	if kmh > 40.5:
		col = UITheme.STOP
	elif kmh > 20.5:
		col = UITheme.CAUTION
	var st := "%d" % int(round(kmh))
	var fs := 34
	var sw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs).x
	var sx := 112.0 # right edge of the number
	draw_string(f, Vector2(sx - sw, cy + 12), st, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(fr, Vector2(sx + 5, cy + 11), Loc.t("hud.kmh"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT_DIM)
	# Gear.
	var gear := AvtoGear.label(car)
	var gbox := Rect2(size.x - 98, cy - 19, 48, 38)
	draw_style_box(UITheme.box(Color(1, 1, 1, 0.08), 10, 0, UITheme.LINE, 0), gbox)
	var gw := f.get_string_size(gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(f, gbox.get_center() + Vector2(-gw * 0.5, 9), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			UITheme.CAUTION if gear == "R" else UITheme.TEXT)
	# Lit warning lamps only, centred above the strip.
	var lamps := []
	if car.ignition and not car.seatbelt:
		lamps.append(["belt", UITheme.STOP])
	if car.ignition and car.handbrake > 0.5:
		lamps.append(["handbrake", UITheme.STOP])
	if car.ignition and not car.is_engine_running():
		lamps.append(["engine", UITheme.CAUTION])
	if car.is_abs_active():
		lamps.append(["abs", UITheme.CAUTION])
	if lamps.is_empty():
		return
	var step := 30.0
	var x := size.x * 0.5 - (lamps.size() - 1) * step * 0.5
	var bg := Rect2(x - 20, -34, (lamps.size() - 1) * step + 40, 28)
	draw_style_box(UITheme.box(Color(0.05, 0.06, 0.08, 0.8), 14, 0, UITheme.LINE, 0), bg)
	for l in lamps:
		Icons.draw(self, l[0], Vector2(x, -20), 9.0, l[1])
		x += step
