class_name GaugeCluster
extends Control
## Compact instrument strip: speed (amber above 20 km/h, red above 40 — the
## avtodrom limits), the selected gear and the indicator arrows. Warning lamps
## (belt, handbrake, engine, ABS) light up inside the strip, left of the speed.

const W := 320.0
const H := 62.0

var car: Car
var _text: Control # numbers, drawn without the baked picture's blend mode


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	_text = Control.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.draw.connect(_draw_text)
	add_child(_text)


var _shown := ""


## Redraw only when something on the strip changes (not every frame).
func _process(_delta: float) -> void:
	if car == null or not is_visible_in_tree():
		return
	var state := "%d|%s|%s%s|%s%s%s%s" % [int(round(absf(car.get_speed_kmh()))), AvtoGear.label(car),
			car.left_lit(), car.right_lit(), car.ignition and not car.seatbelt, car.ignition and car.handbrake > 0.5,
			car.ignition and not car.is_engine_running(), car.is_abs_active()]
	if state != _shown:
		_shown = state
		queue_redraw()
		_text.queue_redraw()


func _draw() -> void:
	if car == null:
		return
	# Box, arrows and warning lamps change rarely: one baked picture per
	# combination (see CanvasBaker); the numbers are drawn on top.
	var lamps := _lamp_states()
	var tex := _picture(lamps)
	if tex:
		material = CanvasBaker.premultiplied()
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
	else:
		material = null
		_draw_still(self, lamps)


func _draw_text() -> void:
	if car == null:
		return
	var f := UITheme.bold()
	var fr := UITheme.regular()
	var cy := _text.size.y * 0.5
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
	var sx := 150.0 # right edge of the number
	_text.draw_string(f, Vector2(sx - sw, cy + 12), st, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	_text.draw_string(fr, Vector2(sx + 5, cy + 11), Loc.t("hud.kmh"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			UITheme.TEXT_DIM)
	# Gear.
	var gear := AvtoGear.label(car)
	var gbox := Rect2(_text.size.x - 98, cy - 19, 48, 38)
	var gw := f.get_string_size(gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_text.draw_string(f, gbox.get_center() + Vector2(-gw * 0.5, 9), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			UITheme.CAUTION if gear == "R" else UITheme.TEXT)


## Indicator arrows, then belt, handbrake, engine, ABS lamps.
func _lamp_states() -> Array:
	return [car.left_lit(), car.right_lit(), car.ignition and not car.seatbelt, car.ignition and car.handbrake > 0.5,
			car.ignition and not car.is_engine_running(), car.is_abs_active()]


var _baked := {} # lamp states -> SubViewport
var _baked_for := ""


func _picture(lamps: Array) -> Texture2D:
	if not CanvasBaker.available() or size.x < 1.0:
		return null
	var scale := CanvasBaker.pixel_scale(self)
	var sig := "%.0fx%.0f@%.2f" % [size.x, size.y, scale]
	if sig != _baked_for:
		_baked_for = sig
		for vp in _baked.values():
			vp.queue_free()
		_baked.clear()
	var key := str(lamps)
	if not _baked.has(key):
		_baked[key] = CanvasBaker.bake(self, size, scale, func(ci: CanvasItem) -> void: _draw_still(ci, lamps))
		_redraw_next_frame.call_deferred()
		return null
	return _baked[key].get_texture()


func _redraw_next_frame() -> void:
	await get_tree().process_frame
	queue_redraw()


func _draw_still(ci: CanvasItem, lamps: Array) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	ci.draw_style_box(UITheme.box(Color(0.05, 0.06, 0.08, 0.8), int(size.y * 0.5), 1, UITheme.LINE, 0), rect)
	var cy := size.y * 0.5
	# Indicator arrows at both ends.
	Icons.draw(ci, "left", Vector2(26, cy), 10.0, UITheme.INDICATOR if lamps[0] else Color(1, 1, 1, 0.14))
	Icons.draw(ci, "right", Vector2(size.x - 26, cy), 10.0, UITheme.INDICATOR if lamps[1] else Color(1, 1, 1, 0.14))
	# Gear box.
	ci.draw_style_box(UITheme.box(Color(1, 1, 1, 0.08), 10, 0, UITheme.LINE, 0), Rect2(size.x - 98, cy - 19, 48, 38))
	# Warning lamps: a 2 × 2 block between the left arrow and the speed.
	var icons := [["belt", UITheme.STOP], ["handbrake", UITheme.STOP], ["engine", UITheme.CAUTION],
			["abs", UITheme.CAUTION]]
	for i in icons.size():
		var c := Vector2(58.0 + (i % 2) * 22.0, cy - 11.0 + (i / 2) * 22.0)
		Icons.draw(ci, icons[i][0], c, 7.5, icons[i][1] if lamps[2 + i] else Color(1, 1, 1, 0.1))
