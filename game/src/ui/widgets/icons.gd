class_name Icons
extends RefCounted
## Vector pictograms drawn straight into a CanvasItem (no image assets, crisp
## at every screen density). `c` is the centre, `s` the half-size.


static func draw(ci: CanvasItem, icon: String, c: Vector2, s: float, color: Color) -> void:
	match icon:
		"left":
			_arrow(ci, c, s, color, -1.0)
		"right":
			_arrow(ci, c, s, color, 1.0)
		"hazard":
			var pts := PackedVector2Array()
			for k in 3:
				var a := -PI * 0.5 + k * TAU / 3.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.95 + Vector2(0, s * 0.18))
			pts.append(pts[0])
			ci.draw_polyline(pts, color, s * 0.16, true)
			var inner := PackedVector2Array()
			for k in 3:
				var a := -PI * 0.5 + k * TAU / 3.0
				inner.append(c + Vector2(cos(a), sin(a)) * s * 0.42 + Vector2(0, s * 0.1))
			inner.append(inner[0])
			ci.draw_polyline(inner, color, s * 0.1, true)
		"belt":
			ci.draw_circle(c + Vector2(0, -s * 0.62), s * 0.22, color)
			var body := PackedVector2Array([c + Vector2(-s * 0.45, s * 0.85), c + Vector2(-s * 0.4, -s * 0.18),
					c + Vector2(0, -s * 0.34), c + Vector2(s * 0.4, -s * 0.18), c + Vector2(s * 0.45, s * 0.85)])
			ci.draw_colored_polygon(body, color.darkened(0.35))
			ci.draw_line(c + Vector2(-s * 0.55, -s * 0.2), c + Vector2(s * 0.5, s * 0.75), color, s * 0.18, true)
		"key":
			ci.draw_arc(c + Vector2(-s * 0.45, 0), s * 0.38, 0, TAU, 24, color, s * 0.16, true)
			ci.draw_line(c + Vector2(-s * 0.08, 0), c + Vector2(s * 0.9, 0), color, s * 0.18, true)
			ci.draw_line(c + Vector2(s * 0.55, 0), c + Vector2(s * 0.55, s * 0.32), color, s * 0.16, true)
			ci.draw_line(c + Vector2(s * 0.85, 0), c + Vector2(s * 0.85, s * 0.4), color, s * 0.16, true)
		"handbrake":
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, color, s * 0.14, true)
			ci.draw_arc(c, s * 0.92, PI * 0.72, PI * 1.28, 10, color, s * 0.12, true)
			ci.draw_arc(c, s * 0.92, -PI * 0.28, PI * 0.28, 10, color, s * 0.12, true)
			_letter(ci, "P", c, s * 0.9, color)
		"lights":
			var d := PackedVector2Array()
			for k in 13:
				var a := -PI * 0.5 + k * PI / 12.0
				d.append(c + Vector2(-s * 0.1 + cos(a) * s * 0.55, sin(a) * s * 0.6))
			d.append(c + Vector2(-s * 0.1, -s * 0.6))
			ci.draw_polyline(d, color, s * 0.14, true)
			for k in 4:
				var y := -s * 0.45 + k * s * 0.3
				ci.draw_line(c + Vector2(-s * 0.3, y), c + Vector2(-s * 0.95, y + s * 0.12), color, s * 0.12, true)
		"camera":
			ci.draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.5), Vector2(s * 1.3, s * 1.0)), color, false, s * 0.14)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.5, -s * 0.2), c + Vector2(s * 0.95, -s * 0.5),
					c + Vector2(s * 0.95, s * 0.5), c + Vector2(s * 0.5, s * 0.2)]), color)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.6), Vector2(s * 0.32, s * 1.2)), color)
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.6), Vector2(s * 0.32, s * 1.2)), color)
		"engine":
			var e := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.2), c + Vector2(-s * 0.45, -s * 0.2),
					c + Vector2(-s * 0.3, -s * 0.5), c + Vector2(s * 0.35, -s * 0.5), c + Vector2(s * 0.5, -s * 0.25),
					c + Vector2(s * 0.85, -s * 0.25), c + Vector2(s * 0.85, s * 0.45), c + Vector2(-s * 0.3, s * 0.45),
					c + Vector2(-s * 0.5, s * 0.2), c + Vector2(-s * 0.8, s * 0.2)])
			e.append(e[0])
			ci.draw_polyline(e, color, s * 0.13, true)
		"abs":
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, color, s * 0.12, true)
			var f := UITheme.bold()
			var fs := int(s * 0.62)
			var w := f.get_string_size("ABS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), "ABS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		"map":
			var m := PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.55), c + Vector2(-s * 0.3, -s * 0.8),
					c + Vector2(s * 0.3, -s * 0.55), c + Vector2(s * 0.85, -s * 0.8), c + Vector2(s * 0.85, s * 0.55),
					c + Vector2(s * 0.3, s * 0.8), c + Vector2(-s * 0.3, s * 0.55), c + Vector2(-s * 0.85, s * 0.8)])
			m.append(m[0])
			ci.draw_polyline(m, color, s * 0.12, true)
		"restart":
			ci.draw_arc(c, s * 0.62, -PI * 0.1, PI * 1.5, 24, color, s * 0.16, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.62, -s * 0.5), c + Vector2(s * 0.95, 0.0),
					c + Vector2(s * 0.3, s * 0.02)]), color)
		_:
			_letter(ci, icon, c, s, color)


static func _arrow(ci: CanvasItem, c: Vector2, s: float, color: Color, dir: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(dir * s * 0.95, 0), c + Vector2(dir * s * 0.05, -s * 0.8), c + Vector2(dir * s * 0.05, -s * 0.35),
		c + Vector2(-dir * s * 0.9, -s * 0.35), c + Vector2(-dir * s * 0.9, s * 0.35), c + Vector2(dir * s * 0.05, s * 0.35),
		c + Vector2(dir * s * 0.05, s * 0.8),
	])
	ci.draw_colored_polygon(pts, color)


static func _letter(ci: CanvasItem, text: String, c: Vector2, s: float, color: Color) -> void:
	var f := UITheme.bold()
	var fs := int(s * 1.1)
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(f, c + Vector2(-sz.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
