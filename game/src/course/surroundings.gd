class_name Surroundings
extends Node3D
## Everything outside the avtodrom fence, built once and baked with the
## course: the ring road, the AvtoSmart exam centre with its forecourt, flags
## and car park, a hedge, groves of six kinds of tree, and a far ring of city
## blocks with a few Tashkent landmarks on the horizon.
## Kept cheap for phones: a handful of meshes and MultiMeshes, no collision
## (the fence keeps the candidate's car inside), shadows only near the field.

const ROAD_OFFSET := 14.0 # m from the fence to the ring-road centre line
const ROAD_WIDTH := 7.0
# Everything out here is seen from 50-300 m: the layers over the lawn need a
# few centimetres between them to stay apart in a phone's depth buffer.
const RING_Y := 0.04
const PAINT_LIFT := 0.04
const HEDGE_OFFSET := 6.0
# Tree scatters are split into this many sectors around the field so the ones
# behind the camera are culled.
const TREE_SECTORS := 4
const FOLIAGE_SHADER := preload("res://assets/shaders/foliage.gdshader")
const BLOB_SHADER := preload("res://assets/shaders/blob_shadow.gdshader")
const FLAG_SHADER := preload("res://assets/shaders/flag.gdshader")
const BRAND_FONT := preload("res://assets/fonts/Montserrat-ExtraBold.ttf")
const BRAND_MARK := preload("res://assets/ui/brand_mark.png")
# Brand colours (brand/README.md).
const INK := Color(0.075, 0.1, 0.27)
const BRAND_GREEN := Color(0.08, 0.5, 0.24)

var fence: Rect2
var quality := 1
var mat: Dictionary
var _rng := RandomNumberGenerator.new()
var _facade: ShaderMaterial
var _keep_out: Array[Rect2] = [] # areas trees must avoid (road, building, car park)
## Trees and bushes placed by the exam centre (forecourt, planters), planted
## together with the park's.
var _extra_small: Array[Vector2] = []
var _extra_bush: Array[Vector2] = []


func build(p_fence: Rect2, p_quality: int, p_mat: Dictionary) -> void:
	name = "Surroundings"
	fence = p_fence
	quality = p_quality
	mat = p_mat
	_rng.seed = 7202609
	_facade = ShaderMaterial.new()
	_facade.shader = load("res://assets/shaders/facade.gdshader")
	_build_ring_road()
	_build_exam_centre()
	_build_hedge()
	_build_trees()
	_build_city()
	_set_draw_distances()


## Small things are not drawn from far away: at 150-250 m across the site a
## bench, a flag or a sign's letters are a few pixels, yet each costs a draw.
const DRAW_DISTANCE := {"ForecourtProps": 150.0, "Bush": 130.0, "ParkedCarShadows": 160.0, "Flag": 220.0,
		"BrandMark": 260.0, "Monolith": 260.0}


func _set_draw_distances() -> void:
	# Low quality: everything small goes sooner.
	var k := 1.0 if quality >= 1 else 0.6
	for child in get_children():
		var gi := child as GeometryInstance3D
		if gi == null:
			continue
		if gi is Label3D:
			gi.visibility_range_end = 220.0 * k
			continue
		for prefix in DRAW_DISTANCE:
			if String(gi.name).begins_with(prefix):
				gi.visibility_range_end = DRAW_DISTANCE[prefix] * k
				break


# --------------------------------------------------------------------------- helpers
func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _instance(mesh: Mesh, node_name: String, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Axis-aligned box as part of a SurfaceTool mesh (vertex colour = `color`;
## for the facade shader its alpha picks the wall style).
func _box(st: SurfaceTool, c: Vector3, size: Vector3, color := Color.WHITE) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)],
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var q := [c + f[1], c + f[2], c + f[3], c + f[4]]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(n)
				st.set_color(color)
				st.set_uv(Vector2(q[k].x + q[k].z, q[k].y))
				st.add_vertex(q[k])


func _clear_of(p: Vector2, margin: float) -> bool:
	if fence.grow(margin + 3.0).has_point(p):
		return false
	for r in _keep_out:
		if r.grow(margin).has_point(p):
			return false
	return true


func _text(text: String, size: int, color: Color, pos: Vector3, align := HORIZONTAL_ALIGNMENT_CENTER,
		pixel := 0.012) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = BRAND_FONT
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.horizontal_alignment = align
	l.position = pos
	add_child(l)
	return l


func _brand_mark(pos: Vector3, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_texture = BRAND_MARK
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "BrandMark"
	mi.mesh = q
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --------------------------------------------------------------------------- ring road
func _build_ring_road() -> void:
	var outer := fence.grow(ROAD_OFFSET + ROAD_WIDTH * 0.5)
	var inner := fence.grow(ROAD_OFFSET - ROAD_WIDTH * 0.5)
	var st := _st()
	# Four strips (a frame), so nothing overlaps.
	for q in [
		Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y - outer.position.y),
		Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
		Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
		Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y),
	]:
		MeshUtil.add_polygon(st, _rect_poly(q), RING_Y, 4.0)
	st.index()
	st.generate_tangents()
	st.set_material(mat["asphalt"])
	_instance(st.commit(), "RingRoad", false)
	_keep_out.append(outer)
	var paint := _st()
	var mid := fence.grow(ROAD_OFFSET)
	MeshUtil.add_dashed(paint, _densify_rect(mid), 0.12, RING_Y + PAINT_LIFT, 3.0, 6.0)
	for r in [outer.grow(-0.4), inner.grow(0.4)]:
		MeshUtil.add_ribbon(paint, _rect_poly(r), 0.12, RING_Y + PAINT_LIFT, true)
	paint.index()
	paint.set_material(mat["paint"])
	_instance(paint.commit(), "RingRoadPaint", false)


func _densify_rect(r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := _rect_poly(r)
	for i in 4:
		var a := c[i]
		var b := c[(i + 1) % 4]
		var n := int(ceil(a.distance_to(b) / 2.0))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(c[0])
	return out


# --------------------------------------------------------------------------- exam centre
func _build_exam_centre() -> void:
	# North of the field, opposite the start: building, forecourt, car park.
	var road_outer := fence.position.y - ROAD_OFFSET - ROAD_WIDTH * 0.5
	var park := Rect2(-6.0, road_outer - 22.0, 62.0, 22.0)
	var bld := Rect2(0.0, park.position.y - 26.0, 48.0, 16.0)
	_keep_out.append(park)
	_keep_out.append(Rect2(bld.position.x - 4.0, bld.position.y - 4.0, bld.size.x + 8.0, park.position.y - bld.position.y + 4.0))

	# Car park surface, bay lines and a driveway to the ring road.
	var st := _st()
	MeshUtil.add_polygon(st, _rect_poly(park), RING_Y, 4.0)
	MeshUtil.add_polygon(st, _rect_poly(Rect2(park.end.x - 8.0, park.end.y, 7.0, 0.5)), RING_Y, 4.0)
	st.index()
	st.generate_tangents()
	st.set_material(mat["asphalt"])
	_instance(st.commit(), "CarPark", false)
	var paint := _st()
	var bays := []
	var bay_w := 2.6
	var n := int((park.size.x - 12.0) / bay_w)
	for row in 2:
		var z0 := park.position.y + 1.0 if row == 0 else park.end.y - 6.0
		for k in n + 1:
			var x := park.position.x + 2.0 + k * bay_w
			MeshUtil.add_ribbon(paint, PackedVector2Array([Vector2(x, z0), Vector2(x, z0 + 5.0)]), 0.1, RING_Y + PAINT_LIFT, false)
			if k < n:
				bays.append([Vector2(x + bay_w * 0.5, z0 + 2.5), 0.0 if row == 0 else PI])
	paint.index()
	paint.set_material(mat["paint"])
	_instance(paint.commit(), "CarParkPaint", false)
	_park_cars(bays)

	# Forecourt: paving from the building to the car park, planters either
	# side of the steps with bushes, a few small trees in front of the wings.
	var fz0 := bld.end.y
	var fz1 := park.position.y
	var fc := _st()
	MeshUtil.add_polygon(fc, _rect_poly(Rect2(bld.position.x - 3.0, fz0, bld.size.x + 6.0, fz1 - fz0)), RING_Y + PAINT_LIFT, 3.0)
	fc.index()
	fc.generate_tangents()
	fc.set_material(mat["concrete"])
	_instance(fc.commit(), "Forecourt", false)
	var cx := bld.get_center().x
	for x in [3.5, 11.0, 37.0, 44.5]:
		_extra_small.append(Vector2(bld.position.x + x, fz1 - 1.6))
	for sx in [-1.0, 1.0]:
		for k in 5:
			_extra_bush.append(Vector2(cx + sx * (8.2 + k * 0.9), fz0 + 4.2 + (k % 2) * 0.5))

	_build_forecourt_props(bld, fz0, fz1)
	_build_centre_building(bld)
	if quality >= 1:
		_build_flags(Vector2(bld.position.x + 1.5, fz0 + 5.5))
	_build_monolith(Vector2(park.end.x + 2.2, park.end.y - 1.2))


## The exam centre, built like a real three-storey public building: a
## steel-and-glass entrance block a storey taller than the rest, with the
## AvtoSmart sign on the solid band across its top; wings in white composite
## panels with ribbon windows set back between the floor spandrels and split by
## aluminium mullions, a ground floor clad in light stone with tall shop
## windows between its piers, a parapet with a brand-green line, plant on the
## roof, a cantilevered canopy over the entrance steps. Everything is real
## geometry (the recesses catch the shadows): one vertex-coloured mesh and one
## reflective glass mesh, two draw calls.
func _build_centre_building(bld: Rect2) -> void:
	var b := _st() # panels, stone, frames
	var g := _st() # glass
	var cx := bld.get_center().x
	var front := bld.end.y
	var back := bld.position.y
	var white := Color(0.9, 0.91, 0.92)
	var panel := Color(0.84, 0.86, 0.88)
	var stone := Color(0.8, 0.75, 0.66)
	var alu := Color(0.36, 0.38, 0.41)
	var dark := Color(0.16, 0.17, 0.19)
	var roof := Color(0.42, 0.43, 0.45)
	var green := BRAND_GREEN
	var glass := Color.WHITE
	var gf := 4.2 # ground floor height (the lobby)
	var fh := 3.5 # upper floors
	var top := gf + 2.0 * fh # roof slab at 11.2
	var en_w := 14.0 # entrance block
	var en_front := front + 2.0
	var en_h := top + 3.6 # a storey taller, the sign band on top
	var wing_w := (bld.size.x - en_w) * 0.5
	var recess := 0.32 # glass set back from the panel face

	# Core volume (the wings' front face is the recessed glass plane).
	var depth := front - back
	_box(b, Vector3(cx, top * 0.5, back + (depth - recess) * 0.5), Vector3(bld.size.x, top, depth - recess), white)
	_box(b, Vector3(cx, top + 0.06, back + depth * 0.5), Vector3(bld.size.x - 0.4, 0.12, depth - 0.4), roof)

	for side in [-1.0, 1.0]:
		var x0: float = cx + side * en_w * 0.5 # inner edge of the wing
		var x1: float = cx + side * (en_w * 0.5 + wing_w) # outer edge
		var wx: float = (x0 + x1) * 0.5
		# Ground floor: stone piers every ~4.2 m, tall glass between them.
		_box(g, Vector3(wx, gf * 0.5, front - recess + 0.02), Vector3(wing_w, gf, 0.04), glass)
		var piers := 5
		for k in piers:
			var px: float = lerpf(x0, x1, float(k) / (piers - 1))
			_box(b, Vector3(px, gf * 0.5, front - 0.12), Vector3(0.7, gf, 0.5), stone)
		_box(b, Vector3(wx, gf - 0.25, front - 0.1), Vector3(wing_w + 0.35, 0.5, 0.55), stone) # lintel band
		# Upper floors: a white spandrel under each ribbon window, mullions.
		for f in 2:
			var y0 := gf + f * fh
			_box(b, Vector3(wx, y0 + 0.55, front - 0.05), Vector3(wing_w + 0.35, 1.1, 0.4), panel)
			_box(g, Vector3(wx, y0 + 1.1 + (fh - 1.1) * 0.5, front - recess + 0.02), Vector3(wing_w, fh - 1.1, 0.04), glass)
			var n := int(wing_w / 1.4)
			for k in n + 1:
				var mx: float = lerpf(x0, x1, float(k) / n)
				_box(b, Vector3(mx, y0 + 1.1 + (fh - 1.1) * 0.5, front - recess + 0.06), Vector3(0.08, fh - 1.1, 0.1), alu)
			# Sill line along the ribbon.
			_box(b, Vector3(wx, y0 + 1.12, front - recess + 0.08), Vector3(wing_w, 0.06, 0.16), alu)
		# Parapet: white panel, a brand-green line, a dark coping.
		_box(b, Vector3(wx, top + 0.45, front - 0.05), Vector3(wing_w + 0.35, 0.9, 0.4), panel)
		_box(b, Vector3(wx, top + 0.25, front + 0.16), Vector3(wing_w + 0.36, 0.14, 0.02), green)
		_box(b, Vector3(wx, top + 0.95, front - depth * 0.5), Vector3(wing_w + 0.45, 0.1, depth + 0.1), dark)
		# End wall: plain panels with a vertical strip of windows (the stairs).
		var ex: float = x1 + side * 0.01
		_box(g, Vector3(ex, top * 0.5 + 0.4, front - 3.5), Vector3(0.04, top - 2.0, 1.6), glass)
		for f in 3:
			var ly := gf + f * fh - 0.05 if f > 0 else 1.4
			_box(b, Vector3(ex + side * 0.03, ly, front - 3.5), Vector3(0.06, 0.12, 1.7), alu)
		_box(b, Vector3(x1, 0.3, back + depth * 0.5), Vector3(0.3, 0.6, depth), stone) # plinth line
		# Plant on the roof, set back from the edge.
		_box(b, Vector3(wx - side * 2.5, top + 0.85, back + 4.0), Vector3(3.4, 1.6, 2.6), roof)
		_box(b, Vector3(wx + side * 2.8, top + 0.6, back + 6.5), Vector3(1.8, 1.1, 1.8), roof)
		_box(b, Vector3(wx + side * 0.4, top + 0.6, back + 6.5), Vector3(1.8, 1.1, 1.8), roof)

	# Entrance block: curtain wall in front of a dark core, a storey taller.
	var ez := (back + en_front) * 0.5
	_box(b, Vector3(cx, en_h * 0.5, ez), Vector3(en_w, en_h, en_front - back - 0.1), dark)
	var band_y0 := top + 0.8 # the solid sign band starts here
	_box(g, Vector3(cx, band_y0 * 0.5, en_front - 0.03), Vector3(en_w - 0.6, band_y0, 0.04), glass)
	_box(g, Vector3(cx + en_w * 0.5 - 0.03, band_y0 * 0.5, ez + 1.0), Vector3(0.04, band_y0, en_front - back - 2.0), glass)
	_box(g, Vector3(cx - en_w * 0.5 + 0.03, band_y0 * 0.5, ez + 1.0), Vector3(0.04, band_y0, en_front - back - 2.0), glass)
	# The curtain wall's frame: mullions every 1.7 m, transoms at the floors.
	var cols := 8
	for k in cols + 1:
		var mx: float = lerpf(cx - en_w * 0.5 + 0.3, cx + en_w * 0.5 - 0.3, float(k) / cols)
		_box(b, Vector3(mx, band_y0 * 0.5, en_front + 0.02), Vector3(0.1, band_y0, 0.12), alu)
	for ty in [gf, gf + fh, gf + 2.0 * fh]:
		_box(b, Vector3(cx, ty, en_front + 0.02), Vector3(en_w - 0.6, 0.14, 0.14), alu)
	# Sign band: white, the green line under it, a dark coping.
	_box(b, Vector3(cx, (band_y0 + en_h) * 0.5, en_front + 0.05), Vector3(en_w + 0.3, en_h - band_y0, 0.3), white)
	_box(b, Vector3(cx, band_y0 - 0.05, en_front + 0.1), Vector3(en_w + 0.32, 0.18, 0.32), green)
	_box(b, Vector3(cx, en_h + 0.06, ez), Vector3(en_w + 0.5, 0.12, en_front - back + 0.3), dark)
	# Corner piers of the entrance block.
	for sx in [-1.0, 1.0]:
		_box(b, Vector3(cx + sx * (en_w * 0.5 + 0.05), en_h * 0.5, en_front - 0.1), Vector3(0.5, en_h, 0.5), white)

	# Canopy: a thin white slab on two slender columns, doors under it.
	var cz := en_front + 2.3
	_box(b, Vector3(cx, gf + 0.15, cz), Vector3(12.5, 0.3, 4.6), white)
	_box(b, Vector3(cx, gf - 0.02, cz), Vector3(12.3, 0.04, 4.4), Color(0.7, 0.72, 0.74)) # soffit
	for sx in [-1.0, 1.0]:
		ProcGeo.cylinder(b, Transform3D(), Vector3(cx + sx * 5.6, 0.0, cz + 1.8), 0.13, 0.13, gf, 12, white)
	_box(g, Vector3(cx, 1.9, en_front + 0.06), Vector3(6.0, 2.9, 0.06), glass)
	for dx in [-3.0, -1.0, 1.0, 3.0]:
		_box(b, Vector3(cx + dx, 1.9, en_front + 0.1), Vector3(0.08, 2.9, 0.1), dark)
	_box(b, Vector3(cx, 3.38, en_front + 0.1), Vector3(6.1, 0.1, 0.12), dark)
	# Steps and planters.
	for i in 3:
		var d := 3.6 - i * 1.2
		_box(b, Vector3(cx, 0.075 + i * 0.15, en_front + d * 0.5), Vector3(11.0 - i * 0.8, 0.15, d), stone * 0.92)
	for sx in [-1.0, 1.0]:
		_box(b, Vector3(cx + sx * 9.9, 0.3, front + 4.4), Vector3(5.2, 0.6, 1.8), stone * 0.85)

	b.index()
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.62
	b.set_material(bm)
	_instance(b.commit(), "ExamCentre", true)
	g.index()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.3, 0.36)
	gm.metallic = 0.6
	gm.roughness = 0.06
	gm.metallic_specular = 0.8
	g.set_material(gm)
	_instance(g.commit(), "ExamCentreGlass", false)

	# The sign on the band: logo, "AvtoSmart" in the brand's ink, the green line.
	var sz := en_front + 0.21
	var sy := (band_y0 + en_h) * 0.5
	_brand_mark(Vector3(cx - 5.0, sy, sz), 2.3)
	_text("AvtoSmart", 120, INK, Vector3(cx - 3.55, sy + 0.45, sz), HORIZONTAL_ALIGNMENT_LEFT, 0.011)
	_text("AVTODROM · IMTIHON MARKAZI", 50, BRAND_GREEN, Vector3(cx - 3.5, sy - 0.72, sz), HORIZONTAL_ALIGNMENT_LEFT, 0.011)
	# Name on the canopy's front edge.
	_text("IMTIHON MARKAZI", 40, Color(0.2, 0.22, 0.25), Vector3(cx, gf + 0.15, cz + 2.31), HORIZONTAL_ALIGNMENT_CENTER, 0.008)


## Benches and lamp posts along the forecourt, bollards at the car park's edge.
func _build_forecourt_props(bld: Rect2, fz0: float, fz1: float) -> void:
	var st := _st()
	var cx := bld.get_center().x
	var wood := Color(0.45, 0.3, 0.18)
	var steel := Color(0.2, 0.21, 0.23)
	for sx in [-1.0, 1.0]:
		for k in 2:
			var bx: float = cx + sx * (14.5 + k * 6.0)
			var bz := fz0 + 2.2
			_box(st, Vector3(bx, 0.45, bz), Vector3(1.8, 0.06, 0.45), wood)
			_box(st, Vector3(bx, 0.72, bz - 0.2), Vector3(1.8, 0.35, 0.06), wood)
			for lx in [-0.75, 0.75]:
				_box(st, Vector3(bx + lx, 0.22, bz), Vector3(0.06, 0.44, 0.4), steel)
	# Slim lamp posts with a flat head.
	for k in 6:
		var lx: float = bld.position.x + 2.0 + k * (bld.size.x - 4.0) / 5.0
		var lz := fz1 - 0.6
		_box(st, Vector3(lx, 2.2, lz), Vector3(0.1, 4.4, 0.1), steel)
		_box(st, Vector3(lx, 4.45, lz + 0.2), Vector3(0.18, 0.08, 0.6), steel)
	# Bollards between the forecourt and the car park.
	var n := 16
	for k in n:
		var bx2: float = bld.position.x - 2.0 + k * (bld.size.x + 4.0) / (n - 1)
		if absf(bx2 - cx) < 6.5:
			continue
		_box(st, Vector3(bx2, 0.45, fz1 - 0.2), Vector3(0.16, 0.9, 0.16), steel)
	st.index()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	st.set_material(m)
	_instance(st.commit(), "ForecourtProps", false)


## Three flagpoles on the forecourt: the national flag either side of the
## AvtoSmart one.
func _build_flags(at: Vector2) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.07
	pole.height = 10.0
	pole.radial_segments = 8
	pole.rings = 0
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.82, 0.83, 0.85)
	pm.metallic = 0.8
	pm.roughness = 0.3
	pole.material = pm
	var textures := ["res://assets/ui/flag_uz.png", "res://assets/ui/flag_avtosmart.png", "res://assets/ui/flag_uz.png"]
	for i in 3:
		var p := at + Vector2(i * 2.4, 0.0)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pole
		pmi.name = "FlagPole"
		pmi.position = Vector3(p.x, 5.0, p.y)
		add_child(pmi)
		var flag := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.2, 1.1)
		q.subdivide_width = 10
		q.subdivide_depth = 2
		var fm := ShaderMaterial.new()
		fm.shader = FLAG_SHADER
		fm.set_shader_parameter("tex", load(textures[i]))
		q.material = fm
		flag.mesh = q
		# Flying towards +x from the pole, the quad's face towards the field.
		flag.position = Vector3(p.x + 1.15, 9.2, p.y)
		flag.name = "Flag"
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flag)


## A dark stone monolith at the car park's driveway with the brand's name.
func _build_monolith(at: Vector2) -> void:
	var st := _st()
	_box(st, Vector3(at.x, 1.7, at.y), Vector3(2.6, 3.4, 0.55), Color(0.16, 0.17, 0.19))
	_box(st, Vector3(at.x, 0.12, at.y), Vector3(3.2, 0.24, 1.1), Color(0.55, 0.56, 0.57))
	_box(st, Vector3(at.x, 0.5, at.y + 0.28), Vector3(2.6, 0.12, 0.02), BRAND_GREEN)
	st.index()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	st.set_material(m)
	_instance(st.commit(), "Monolith", true)
	_keep_out.append(Rect2(at.x - 3.0, at.y - 2.0, 6.0, 4.0))
	var z := at.y + 0.29
	_brand_mark(Vector3(at.x, 2.55, z), 1.1)
	_text("AvtoSmart", 64, Color(0.97, 0.97, 0.98), Vector3(at.x, 1.68, z), HORIZONTAL_ALIGNMENT_CENTER, 0.0085)
	_text("AVTODROM", 40, Color(0.29, 0.87, 0.5), Vector3(at.x, 1.2, z), HORIZONTAL_ALIGNMENT_CENTER, 0.0085)
	_text("avtotestu.uz", 30, Color(0.75, 0.78, 0.82), Vector3(at.x, 0.82, z), HORIZONTAL_ALIGNMENT_CENTER, 0.0085)


## Parked cars (pipeline/blender/build_parked_car.py), mostly the white,
## silver and black of Tashkent's streets, each on a soft contact shadow.
func _park_cars(bays: Array) -> void:
	var paints := [[Color(0.95, 0.95, 0.96), 30], [Color(0.9, 0.91, 0.92), 12], [Color(0.66, 0.68, 0.7), 12],
			[Color(0.42, 0.44, 0.46), 7], [Color(0.06, 0.06, 0.07), 11], [Color(0.1, 0.16, 0.34), 7],
			[Color(0.5, 0.06, 0.07), 6], [Color(0.74, 0.7, 0.62), 6], [Color(0.3, 0.36, 0.42), 5],
			[Color(0.2, 0.3, 0.22), 3], [Color(0.55, 0.42, 0.3), 3]]
	var total := 0
	for p in paints:
		total += int(p[1])
	var models := ["res://assets/cars/lod/nexia2_parked.glb", "res://assets/cars/lod/cobalt_parked.glb",
			"res://assets/cars/lod/gentra_parked.glb"]
	var picks := []
	for m in models.size():
		picks.append([])
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = load("res://assets/shaders/car_parked.gdshader")
	var shadows: Array[Transform3D] = []
	var occupied := 0.7 if quality >= 1 else 0.4
	for bay in bays:
		if _rng.randf() < occupied:
			picks[_rng.randi() % models.size()].append(bay)
	for m in models.size():
		if picks[m].is_empty():
			continue
		var scene: PackedScene = load(models[m])
		var src := scene.instantiate()
		var meshes := src.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			src.free()
			continue
		var mi: MeshInstance3D = meshes[0]
		var mesh := mi.mesh.duplicate() as ArrayMesh
		var local := _chain(mi, src)
		src.free()
		# One surface; the look is in the vertex colours, the paint per instance.
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, paint_mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true # white; without it Compatibility reads COLOR as zero
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = picks[m].size()
		for i in picks[m].size():
			var bay: Array = picks[m][i]
			var p: Vector2 = bay[0] + Vector2(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.3, 0.3))
			var yaw: float = bay[1] + _rng.randf_range(-0.05, 0.05)
			var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, RING_Y, p.y))
			mm.set_instance_transform(i, base * local)
			var roll := _rng.randi() % total
			var c: Color = paints[0][0]
			for pc in paints:
				roll -= int(pc[1])
				if roll < 0:
					c = pc[0]
					break
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, c.srgb_to_linear())
			shadows.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, RING_Y + PAINT_LIFT + 0.01, p.y)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "ParkedCars%d" % m
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	if not shadows.is_empty():
		add_child(blob_shadows("ParkedCarShadows", shadows))


## Soft contact shadows (blob_shadow.gdshader) under cars at `xforms`.
static func blob_shadows(node_name: String, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2, 4.9)
	var sm := ShaderMaterial.new()
	sm.shader = BLOB_SHADER
	plane.material = sm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _chain(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != top and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# --------------------------------------------------------------------------- green
func _foliage_material(sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("sway", sway)
	return m


func _build_hedge() -> void:
	# A trimmed hedge outside the fence, in stretches with gaps. One mesh: a
	# body and a slightly narrower top, the colour darker at the foot.
	var r := fence.grow(HEDGE_OFFSET)
	var st := _st()
	var c := _rect_poly(r)
	for i in 4:
		var a := c[i]
		var b := c[(i + 1) % 4]
		var L := a.distance_to(b)
		var k := 0.0
		while k < L - 1.0:
			var seg := minf(_rng.randf_range(10.0, 18.0), L - k)
			var p0 := a.lerp(b, k / L)
			var p1 := a.lerp(b, (k + seg) / L)
			var mid := (p0 + p1) * 0.5
			var along := absf(p1.x - p0.x) > absf(p1.y - p0.y)
			var tone := Color(0.15, 0.29, 0.09).lerp(Color(0.2, 0.35, 0.11), _rng.randf())
			var hgt := _rng.randf_range(1.0, 1.25)
			var body := Vector3(seg, hgt - 0.2, 1.1) if along else Vector3(1.1, hgt - 0.2, seg)
			var top := Vector3(seg - 0.2, 0.2, 0.9) if along else Vector3(0.9, 0.2, seg - 0.2)
			_box(st, Vector3(mid.x, (hgt - 0.2) * 0.5, mid.y), body, tone * 0.8)
			_box(st, Vector3(mid.x, hgt - 0.1, mid.y), top, tone)
			if _rng.randf() < 0.35:
				_extra_bush.append(mid + (Vector2(0, 1.6) if along else Vector2(1.6, 0)) * (1.0 if _rng.randf() < 0.5 else -1.0))
			k += seg + _rng.randf_range(1.5, 4.0)
	st.index()
	st.set_material(_foliage_material(0.0))
	_instance(st.commit(), "Hedge", quality >= 2)


## Icosahedron (subdiv 0) or its once-split sphere: [vertices, indices].
static func _icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = []
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
			[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		v.append(Vector3(p[0], p[1], p[2]).normalized())
	var f := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
			3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for _s in subdiv:
		var mids := {}
		var nf := []
		for i in range(0, f.size(), 3):
			var m := []
			for e in [[f[i], f[i + 1]], [f[i + 1], f[i + 2]], [f[i + 2], f[i]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not mids.has(key):
					mids[key] = v.size()
					v.append(((v[e[0]] + v[e[1]]) * 0.5).normalized())
				m.append(mids[key])
			nf.append_array([f[i], m[0], m[2], f[i + 1], m[1], m[0], f[i + 2], m[2], m[1], m[0], m[1], m[2]])
		f = nf
	return [v, f]


## A crown of overlapping jittered balls ([centre, radius, y squash] each, in
## a unit crown of y -1..1). Vertex colour = baked shade: dark low in the
## crown and inside it, light on its upper outer skin; the instance colour
## gives the green. Normals blend the ball's sphere and the facet, so the
## crown reads soft but not plastic.
func _crown(clumps: Array, subdiv: int, jitter: float, seed_: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var ico := _icosphere(subdiv)
	var iv: Array[Vector3] = ico[0]
	var idx: Array = ico[1]
	var st := _st()
	var centroid := Vector3.ZERO
	var extent := 0.01
	for c in clumps:
		centroid += c[0]
	centroid /= clumps.size()
	for c in clumps:
		extent = maxf(extent, (c[0] - centroid).length() + float(c[1]))
	for c in clumps:
		var centre: Vector3 = c[0]
		var rad: float = c[1]
		var squash: float = c[2] if c.size() > 2 else 1.0
		var pts: Array[Vector3] = []
		for p in iv:
			var k := 1.0 + r.randf_range(-jitter, jitter)
			pts.append(centre + Vector3(p.x, p.y * squash, p.z) * rad * k)
		for i in range(0, idx.size(), 3):
			var a := pts[idx[i]]
			var b := pts[idx[i + 1]]
			var d := pts[idx[i + 2]]
			var fn := (b - a).cross(d - a)
			var out := ((a + b + d) / 3.0 - centre)
			var order := [a, d, b] if fn.dot(out) > 0.0 else [a, b, d] # clockwise from outside
			var facet := fn.normalized() * (1.0 if fn.dot(out) > 0.0 else -1.0)
			for q: Vector3 in order:
				var sn: Vector3 = ((q as Vector3) - centre).normalized()
				var h := clampf((q.y + 1.0) * 0.5, 0.0, 1.0)
				var outer := clampf((q - centroid).length() / extent, 0.0, 1.0)
				var shade := clampf(0.34 + 0.36 * h + 0.34 * outer * outer, 0.3, 1.0)
				st.set_normal((sn * 0.97 + facet * 0.03).normalized())
				st.set_color(Color(shade, shade, shade))
				st.add_vertex(q)
	return st.commit()


## A spruce / archa: jittered stacked cones, the crown's y from -1 to +1.
func _conifer_crown(seed_: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var st := _st()
	var segs := 8 if quality >= 1 else 6
	var tiers := 4
	for t in tiers:
		var f := float(t) / tiers
		var base_y := -1.0 + f * 1.55
		var height := 0.75 - f * 0.12
		var rad := (1.0 - f * 0.72) * r.randf_range(0.92, 1.08)
		var apex := Vector3(r.randf_range(-0.04, 0.04), base_y + height, r.randf_range(-0.04, 0.04))
		var rim: Array[Vector3] = []
		for s in segs:
			var ang := TAU * (s + r.randf_range(-0.15, 0.15)) / segs
			var rr := rad * r.randf_range(0.85, 1.1)
			rim.append(Vector3(cos(ang) * rr, base_y + r.randf_range(-0.05, 0.05), sin(ang) * rr))
		for s in segs:
			var a := rim[s]
			var b := rim[(s + 1) % segs]
			# Outside face (clockwise seen from outside), then the underside.
			var n := (b - a).cross(apex - a).normalized()
			if n.dot((a + b) * 0.5 - Vector3(0, base_y, 0)) < 0.0:
				n = -n
			for q in [a, apex, b]:
				var shade := clampf(0.5 + 0.35 * (q.y + 1.0) * 0.5 + (0.2 if q == apex else 0.0), 0.35, 1.0)
				st.set_normal((n + Vector3(0, 0.35, 0)).normalized())
				st.set_color(Color(shade, shade, shade))
				st.add_vertex(q)
			for q in [a, b, Vector3(0, base_y + 0.12, 0)]:
				st.set_normal(Vector3.DOWN)
				st.set_color(Color(0.3, 0.3, 0.3))
				st.add_vertex(q)
	return st.commit()


## Random clumps for a broad crown: one core, `n` round it, one on top.
func _broad_clumps(r: RandomNumberGenerator, n: int, spread: float, size: float) -> Array:
	var out := [[Vector3(0, -0.05, 0), 0.62 * size, 0.95]]
	for k in n:
		var ang := TAU * (k + r.randf_range(-0.3, 0.3)) / n
		var d := spread * r.randf_range(0.75, 1.05)
		out.append([Vector3(cos(ang) * d, r.randf_range(-0.35, 0.3), sin(ang) * d), size * r.randf_range(0.4, 0.55),
				r.randf_range(0.8, 1.0)])
	out.append([Vector3(r.randf_range(-0.15, 0.15), 0.5, r.randf_range(-0.15, 0.15)), size * 0.45, 0.9])
	return out


## A poplar's narrow column of stacked clumps.
func _column_clumps(r: RandomNumberGenerator) -> Array:
	var out := []
	var n := r.randi_range(4, 6)
	var bulge := r.randf_range(0.3, 0.6) # where the column is widest
	for k in n:
		var f := float(k) / (n - 1)
		var wide := 1.0 - absf(f - bulge) * 1.2
		out.append([Vector3(r.randf_range(-0.1, 0.1), -0.8 + f * 1.6, r.randf_range(-0.1, 0.1)),
				clampf(0.26 + 0.14 * wide, 0.16, 0.42) * r.randf_range(0.92, 1.08), 1.9])
	return out


func _trunk(top: float, bottom: float) -> CylinderMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = top
	trunk.bottom_radius = bottom
	trunk.height = 3.0
	trunk.radial_segments = 5
	trunk.rings = 0
	return trunk


## Six kinds of tree in natural groves, rows of poplars mixed with plane
## trees and elms along the ring road, and bushes by the hedge and the exam
## centre. Every kind has three crown shapes (soft round clumps) and its own
## spread of colour and proportions; about one broad-leaved tree in ten has
## started to turn (late September).
func _build_trees() -> void:
	var sub := 1 if quality >= 2 else 0
	var r := RandomNumberGenerator.new()
	r.seed = 424242

	# Tree rows along the outer side of the ring road: mostly poplars, every
	# third or so a plane tree or an elm, as along Tashkent's streets.
	var spacing := 8.0 if quality >= 1 else 16.0
	var row_broad: Array[Vector2] = []
	var row_elm: Array[Vector2] = []
	var ring := fence.grow(ROAD_OFFSET + ROAD_WIDTH * 0.5 + 3.0)
	var poplars: Array[Vector2] = []
	var c := _rect_poly(ring)
	for i in 4:
		var a := c[i]
		var b := c[(i + 1) % 4]
		var L := a.distance_to(b)
		var k := 0.0
		while k < L:
			var p := a.lerp(b, k / L)
			var skip := false
			for ko in _keep_out.slice(1):
				if (ko as Rect2).grow(2.0).has_point(p):
					skip = true
			var roll := _rng.randf()
			var q := p + Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5))
			if skip or roll < 0.05: # the odd gap
				pass
			elif roll < 0.2:
				row_broad.append(q)
			elif roll < 0.33:
				row_elm.append(q)
			else:
				poplars.append(q)
			k += spacing * _rng.randf_range(0.85, 1.15)

	# Groves in the park round the site.
	var count := 120 if quality >= 1 else 36
	var kinds := ["chinor", "elm", "conifer", "small"]
	var groups := {"chinor": [] as Array[Vector2], "elm": [] as Array[Vector2], "conifer": [] as Array[Vector2],
			"small": [] as Array[Vector2]}
	var placed := 0
	var tries := 0
	while placed < count and tries < 400:
		tries += 1
		var side := _rng.randi() % 4
		var along := _rng.randf()
		var dist := _rng.randf_range(ROAD_OFFSET + 10.0, 72.0)
		var outer := fence.grow(20.0)
		var centre: Vector2
		match side:
			0: centre = Vector2(lerpf(outer.position.x - 40.0, outer.end.x + 40.0, along), fence.position.y - dist)
			1: centre = Vector2(lerpf(outer.position.x - 40.0, outer.end.x + 40.0, along), fence.end.y + dist)
			2: centre = Vector2(fence.position.x - dist, lerpf(outer.position.y, outer.end.y, along))
			_: centre = Vector2(fence.end.x + dist, lerpf(outer.position.y, outer.end.y, along))
		var main_kind: String = kinds[[0, 0, 1, 1, 2, 3][_rng.randi() % 6]]
		var n := _rng.randi_range(1, 7)
		for j in n:
			var p := centre + Vector2(_rng.randfn(0.0, 5.5), _rng.randfn(0.0, 5.5))
			if not _clear_of(p, 3.0):
				continue
			var kind: String = main_kind if _rng.randf() < 0.7 else kinds[_rng.randi() % kinds.size()]
			(groups[kind] as Array[Vector2]).append(p)
			placed += 1
	(groups["small"] as Array[Vector2]).append_array(_extra_small)
	(groups["chinor"] as Array[Vector2]).append_array(row_broad)
	(groups["elm"] as Array[Vector2]).append_array(row_elm)

	var green_broad := [Color(0.27, 0.47, 0.13), Color(0.4, 0.56, 0.16)]
	var autumn := [Color(0.72, 0.58, 0.14), Color(0.78, 0.44, 0.12)]
	_scatter("ParkTreeChinor", groups["chinor"], _trunk(0.16, 0.3),
			[_crown(_broad_clumps(r, 6, 0.55, 1.0), sub, 0.07, 11), _crown(_broad_clumps(r, 7, 0.6, 0.95), sub, 0.08, 12),
					_crown(_broad_clumps(r, 5, 0.5, 1.1), sub, 0.07, 13)],
			func(s: float) -> Array:
				var spread := _rng.randf_range(0.9, 1.2)
				return [Vector3(1.2, 1.25, 1.2) * s, Vector3(3.4 * spread, 2.7, 3.4 * spread) * s, 5.9 * s],
			green_broad, autumn)
	_scatter("ParkTreeElm", groups["elm"], _trunk(0.12, 0.22),
			[_crown(_broad_clumps(r, 5, 0.5, 1.0), sub, 0.08, 21), _crown(_broad_clumps(r, 4, 0.45, 1.05), sub, 0.08, 22),
					_crown(_broad_clumps(r, 6, 0.4, 0.9), sub, 0.07, 23)],
			func(s: float) -> Array:
				var spread := _rng.randf_range(0.85, 1.15)
				return [Vector3(1.0, 1.0, 1.0) * s, Vector3(2.5 * spread, 2.3, 2.5 * spread) * s, 4.6 * s],
			[Color(0.2, 0.38, 0.12), Color(0.3, 0.47, 0.14)], autumn)
	_scatter("ParkTreeConifer", groups["conifer"], _trunk(0.09, 0.17),
			[_conifer_crown(31), _conifer_crown(32), _conifer_crown(33)],
			func(s: float) -> Array:
				var tall := _rng.randf_range(0.85, 1.4)
				return [Vector3(1.0, 0.5, 1.0) * s, Vector3(1.9, 3.8 * tall, 1.9) * s, (0.9 + 3.8 * tall) * s],
			[Color(0.09, 0.22, 0.12), Color(0.15, 0.3, 0.16)], [])
	_scatter("ParkTreeSmall", groups["small"], _trunk(0.07, 0.12),
			[_crown(_broad_clumps(r, 3, 0.4, 1.1), sub, 0.07, 41), _crown(_broad_clumps(r, 4, 0.35, 1.0), sub, 0.07, 42)],
			func(s: float) -> Array:
				return [Vector3(0.7, 0.7, 0.7) * s, Vector3(1.5, 1.35, 1.5) * s, 2.9 * s],
			[Color(0.38, 0.56, 0.15), Color(0.52, 0.62, 0.18)], [Color(0.7, 0.36, 0.14)])
	_scatter("Poplar", poplars, _trunk(0.1, 0.2),
			[_crown(_column_clumps(r), sub, 0.06, 51), _crown(_column_clumps(r), sub, 0.07, 52),
					_crown(_column_clumps(r), sub, 0.06, 53)],
			func(s: float) -> Array:
				var hgt := 10.0 * s * _rng.randf_range(0.85, 1.25)
				var wid := 3.2 * s * _rng.randf_range(0.8, 1.15)
				return [Vector3(1.0, 1.0, 1.0) * s, Vector3(wid, hgt * 0.5, wid), 2.0 * s + hgt * 0.5],
			[Color(0.18, 0.36, 0.11), Color(0.28, 0.45, 0.14)], autumn)
	var bushes: Array[Vector2] = []
	if quality >= 1:
		for p in _extra_bush:
			bushes.append(p)
	_scatter("Bush", bushes, null,
			[_crown([[Vector3(0, 0, 0), 0.6, 0.8], [Vector3(0.45, -0.1, 0.2), 0.45, 0.8], [Vector3(-0.4, -0.1, -0.25), 0.5, 0.8]], sub, 0.18, 61)],
			func(s: float) -> Array:
				return [Vector3.ZERO, Vector3(1.1, 0.8, 1.1) * s, 0.55 * s],
			[Color(0.2, 0.36, 0.11), Color(0.28, 0.44, 0.13)], [])


## Trunks and crowns as MultiMeshes, one per crown shape and sector around
## the field (nodes `<label>Trunks<k>` / `<label>Crowns<v>_<k>`): a single
## MultiMesh would have one AABB round the whole site and never be culled.
## `shape(scale)` returns [trunk scale, crown scale, crown centre height].
## `turned` (may be empty): the autumn colours one tree in ten takes.
func _scatter(label: String, pts: Array[Vector2], trunk: Mesh, crowns: Array, shape: Callable, greens: Array,
		turned: Array) -> void:
	if pts.is_empty():
		return
	if quality == 0:
		# One crown shape per kind: a third of the draws (the colours and
		# sizes still vary per tree).
		crowns = crowns.slice(0, 1)
	if trunk:
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.32, 0.25, 0.18)
		tm.roughness = 0.95
		(trunk as PrimitiveMesh).material = tm
	var sway := 0.03 if label == "Bush" else (0.09 if label == "Poplar" else 0.06)
	var cm := _foliage_material(sway)
	for crown in crowns:
		(crown as ArrayMesh).surface_set_material(0, cm)
	var trunks: Array = []
	var crown_sets: Array = [] # [variant][sector] -> [[xform, colour]]
	for k in TREE_SECTORS:
		trunks.append([])
	for v in crowns.size():
		var per := []
		for k in TREE_SECTORS:
			per.append([])
		crown_sets.append(per)
	var centre := fence.get_center()
	for p in pts:
		var s := _rng.randf_range(0.8, 1.25)
		var sh: Array = shape.call(s)
		var ts: Vector3 = sh[0]
		var cs: Vector3 = sh[1]
		var lean := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.05))
		var cb := lean * Basis(Vector3.UP, _rng.randf() * TAU).scaled(cs)
		var k := _sector(p - centre)
		if trunk:
			trunks[k].append(Transform3D(lean * Basis().scaled(ts), Vector3(p.x, 1.5 * ts.y, p.y)))
		var col: Color = (greens[0] as Color).lerp(greens[1], _rng.randf())
		if not turned.is_empty() and _rng.randf() < 0.1:
			col = col.lerp(turned[_rng.randi() % turned.size()], _rng.randf_range(0.55, 0.9))
		var crown_pos := Vector3(p.x, float(sh[2]), p.y) + lean * Vector3(0, float(sh[2]), 0) - Vector3(0, float(sh[2]), 0)
		crown_sets[_rng.randi() % crowns.size()][k].append([Transform3D(cb, crown_pos), col])
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 1 \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in TREE_SECTORS:
		if trunk and not trunks[k].is_empty():
			var tmm := MultiMesh.new()
			tmm.transform_format = MultiMesh.TRANSFORM_3D
			tmm.mesh = trunk
			tmm.instance_count = trunks[k].size()
			for i in trunks[k].size():
				tmm.set_instance_transform(i, trunks[k][i])
			_add_mm(label + "Trunks%d" % k, tmm, shadow)
		for v in crowns.size():
			var items: Array = crown_sets[v][k]
			if items.is_empty():
				continue
			var cmm := MultiMesh.new()
			cmm.transform_format = MultiMesh.TRANSFORM_3D
			cmm.use_colors = true
			cmm.mesh = crowns[v]
			cmm.instance_count = items.size()
			for i in items.size():
				cmm.set_instance_transform(i, items[i][0])
				cmm.set_instance_color(i, items[i][1])
			_add_mm(label + "Crowns%d_%d" % [v, k], cmm, shadow if label != "Bush" else \
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _add_mm(node_name: String, mm: MultiMesh, shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = shadow
	add_child(mmi)


## Sector (0 .. TREE_SECTORS-1) of a direction from the field centre.
static func _sector(d: Vector2) -> int:
	var a := fposmod(d.angle() + PI / TREE_SECTORS, TAU)
	return mini(int(a / TAU * TREE_SECTORS), TREE_SECTORS - 1)


# --------------------------------------------------------------------------- city
## A ring of blocks 230–420 m away, softened by the fog: Tashkent's mix of
## 9- and 16-storey panel blocks (balconies, panel seams, stair columns) in
## their pastel paints, new towers on podiums, glass towers in blue, green
## and bronze glass, round towers, low houses under pitched roofs, two domed
## complexes with minarets and, far out, the TV tower.
func _build_city() -> void:
	var count := 96 if quality >= 1 else 36
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _facade
	var blocks: Array = [] # [transform, colour]
	var roof_boxes: Array = []
	var roofs: Array = [] # pitched
	var rounds: Array = [] # round towers
	var panel_colours := [Color(0.9, 0.87, 0.8), Color(0.85, 0.85, 0.83), Color(0.78, 0.82, 0.86),
			Color(0.92, 0.84, 0.72), Color(0.8, 0.76, 0.7), Color(0.93, 0.9, 0.84), Color(0.86, 0.8, 0.74),
			Color(0.76, 0.8, 0.78), Color(0.9, 0.78, 0.66), Color(0.82, 0.88, 0.84), Color(0.94, 0.88, 0.78),
			Color(0.86, 0.74, 0.7)]
	var glass_colours := [Color(0.62, 0.74, 0.86), Color(0.64, 0.8, 0.74), Color(0.78, 0.7, 0.58),
			Color(0.8, 0.82, 0.84), Color(0.56, 0.66, 0.8)]
	var roof_colours := [Color(0.45, 0.2, 0.16), Color(0.36, 0.38, 0.4), Color(0.5, 0.3, 0.22), Color(0.3, 0.42, 0.36),
			Color(0.24, 0.36, 0.5)]
	for i in count:
		var ang := TAU * (i + _rng.randf_range(-0.35, 0.35)) / count
		var rad := _rng.randf_range(230.0, 420.0)
		var kind := _rng.randf()
		var yaw := -ang + PI * 0.5 + _rng.randf_range(-0.2, 0.2)
		var rot := Basis(Vector3.UP, yaw)
		var pos := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad * 0.8)
		var col: Color = panel_colours[_rng.randi() % panel_colours.size()]
		if kind < 0.08:
			# Glass tower with a set-back crown.
			var h := _rng.randf_range(50.0, 90.0)
			var w := _rng.randf_range(16.0, 28.0)
			var d := _rng.randf_range(16.0, 24.0)
			col = glass_colours[_rng.randi() % glass_colours.size()]
			col.a = 0.68
			blocks.append([Transform3D(rot.scaled(Vector3(w, h, d)), pos + Vector3(0, h * 0.5, 0)), col])
			var ch := _rng.randf_range(5.0, 10.0)
			blocks.append([Transform3D(rot.scaled(Vector3(w * 0.7, ch, d * 0.7)), pos + Vector3(0, h + ch * 0.5, 0)), col])
			continue
		if kind < 0.16:
			# A new tower on a wide podium.
			var ph := 3 * 3.3 + 1.0
			var pw := _rng.randf_range(34.0, 50.0)
			var pd := _rng.randf_range(20.0, 28.0)
			var th := _rng.randi_range(14, 22) * 3.2
			var tw := _rng.randf_range(16.0, 22.0)
			var pod := Color(col.r, col.g, col.b, 0.95)
			blocks.append([Transform3D(rot.scaled(Vector3(pw, ph, pd)), pos + Vector3(0, ph * 0.5, 0)), pod])
			var tc: Color = panel_colours[_rng.randi() % panel_colours.size()]
			tc.a = [0.3, 0.5, 0.95][_rng.randi() % 3]
			var off := rot * Vector3(_rng.randf_range(-pw * 0.2, pw * 0.2), 0, 0)
			blocks.append([Transform3D(rot.scaled(Vector3(tw, th, tw * 0.9)), pos + off + Vector3(0, ph + th * 0.5, 0)), tc])
			roof_boxes.append([Transform3D(rot.scaled(Vector3(tw * 0.4, 3.0, tw * 0.4)), pos + off + Vector3(0, ph + th + 1.5, 0)),
					Color(tc.r * 0.9, tc.g * 0.9, tc.b * 0.9, 0.8)])
			continue
		if kind < 0.2:
			# Round tower.
			var rh := _rng.randf_range(40.0, 70.0)
			var rr := _rng.randf_range(9.0, 13.0)
			var rc: Color = glass_colours[_rng.randi() % glass_colours.size()] if _rng.randf() < 0.5 else col
			rc.a = 0.68 if _rng.randf() < 0.5 else 0.95
			rounds.append([Transform3D(Basis().scaled(Vector3(rr * 2.0, rh, rr * 2.0)), pos + Vector3(0, rh * 0.5, 0)), rc])
			continue
		var h: float
		var style: float
		if kind < 0.38:
			h = 16 * 3.0 + 1.5 # 16 storeys
			style = [0.1, 0.3, 0.5][_rng.randi() % 3]
		elif kind < 0.78:
			h = 9 * 3.0 + 1.5 # 9 storeys
			style = [0.1, 0.1, 0.3, 0.5][_rng.randi() % 4]
		else:
			h = _rng.randi_range(3, 5) * 3.0 + 1.0 # low houses, pitched roofs
			style = 0.95
		var w := _rng.randf_range(24.0, 60.0) if kind < 0.78 else _rng.randf_range(14.0, 30.0)
		var d := _rng.randf_range(12.0, 15.0) if kind < 0.78 else _rng.randf_range(16.0, 26.0)
		col.a = style
		blocks.append([Transform3D(rot.scaled(Vector3(w, h, d)), pos + Vector3(0, h * 0.5, 0)), col])
		if kind < 0.78:
			# Lift / stair housing on the roof.
			var rb := Vector3(minf(w * 0.18, 7.0), 2.8, d * 0.45)
			var off := rot * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), h + rb.y * 0.5, 0.0)
			roof_boxes.append([Transform3D(rot.scaled(rb), pos + off), Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.8)])
			if _rng.randf() < 0.3:
				# A second wing at right angles: an L-shaped block.
				var w2 := _rng.randf_range(18.0, 30.0)
				var wing := rot * Basis(Vector3.UP, PI * 0.5)
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				var off2 := rot * Vector3(side * (w * 0.5 - d * 0.5), 0.0, w2 * 0.5 + d * 0.5)
				blocks.append([Transform3D(wing.scaled(Vector3(w2, h, d)), pos + off2 + Vector3(0, h * 0.5, 0)), col])
		else:
			var rh := d * 0.28
			roofs.append([Transform3D(rot * Basis(Vector3.UP, PI * 0.5).scaled(Vector3(d * 1.04, rh, w * 1.02)),
					pos + Vector3(0, h + rh * 0.5, 0)), roof_colours[_rng.randi() % roof_colours.size()]])
	_multimesh("City", box, blocks)
	var rbox := BoxMesh.new()
	rbox.size = Vector3.ONE
	rbox.material = _facade
	if quality >= 1:
		_multimesh("CityRoofBoxes", rbox, roof_boxes)
	if not rounds.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 1.0
		cyl.radial_segments = 16
		cyl.rings = 0
		cyl.material = _facade
		_multimesh("CityRound", cyl, rounds)
	if not roofs.is_empty():
		var prism := PrismMesh.new()
		prism.size = Vector3.ONE
		var rm := StandardMaterial3D.new()
		rm.vertex_color_use_as_albedo = true
		rm.roughness = 0.85
		prism.material = rm
		_multimesh("CityRoofs", prism, roofs)
	_build_landmarks()


## Two domed complexes (turquoise dome on a sand-coloured drum, two
## minarets) and the Tashkent TV tower, far out on the horizon.
func _build_landmarks() -> void:
	var st := _st()
	var sand := Color(0.86, 0.77, 0.62)
	var tile := Color(0.1, 0.55, 0.62)
	var white := Color(0.9, 0.9, 0.9)
	var red := Color(0.75, 0.15, 0.12)
	for spot in [[deg_to_rad(205.0), 330.0], [deg_to_rad(40.0), 360.0]]:
		var ang: float = spot[0]
		var rad: float = spot[1]
		var c := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad * 0.8)
		_box(st, c + Vector3(0, 6.0, 0), Vector3(30.0, 12.0, 30.0), sand)
		ProcGeo.cylinder(st, Transform3D(), c + Vector3(0, 12.0, 0), 8.5, 8.5, 5.0, 16, sand)
		_dome(st, c + Vector3(0, 17.0, 0), 8.8, 11.0, tile)
		for sx in [-1.0, 1.0]:
			var m := c + Vector3(sx * 19.0, 0, 13.0)
			ProcGeo.cylinder(st, Transform3D(), m, 1.5, 1.2, 34.0, 10, sand)
			ProcGeo.cylinder(st, Transform3D(), m + Vector3(0, 30.0, 0), 1.9, 1.9, 1.2, 10, sand)
			_dome(st, m + Vector3(0, 34.0, 0), 1.3, 2.4, tile)
	# TV tower: three legs, the shaft, two pods, a red-and-white mast.
	var ang2 := deg_to_rad(-60.0)
	var t := Vector3(cos(ang2) * 560.0, 0.0, sin(ang2) * 560.0 * 0.8)
	for k in 3:
		var a := TAU * k / 3.0
		var foot := t + Vector3(cos(a), 0, sin(a)) * 14.0
		var up := (t + Vector3(0, 45.0, 0) - foot)
		var xf := Transform3D(Basis(Vector3.UP.cross(up.normalized()).normalized(), Vector3.UP.angle_to(up.normalized())), foot)
		ProcGeo.cylinder(st, xf, Vector3.ZERO, 1.6, 1.2, up.length(), 8, white)
	ProcGeo.cylinder(st, Transform3D(), t + Vector3(0, 40.0, 0), 3.2, 2.2, 150.0, 12, white)
	ProcGeo.cylinder(st, Transform3D(), t + Vector3(0, 95.0, 0), 9.0, 9.0, 8.0, 16, white)
	ProcGeo.cylinder(st, Transform3D(), t + Vector3(0, 150.0, 0), 7.0, 7.0, 6.0, 16, white)
	for k in 6:
		ProcGeo.cylinder(st, Transform3D(), t + Vector3(0, 190.0 + k * 10.0, 0), 1.0, 0.8, 10.0, 6, red if k % 2 == 0 else white)
	st.index()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	st.set_material(m)
	_instance(st.commit(), "Landmarks", false)


## A dome of radius `r` rising `h` above `base` (half a squashed sphere).
func _dome(st: SurfaceTool, base: Vector3, r: float, h: float, color: Color) -> void:
	var seg := 16
	var rings := 6
	for i in rings:
		var a0 := PI * 0.5 * i / rings
		var a1 := PI * 0.5 * (i + 1) / rings
		for s in seg:
			var b0 := TAU * s / seg
			var b1 := TAU * (s + 1) / seg
			var p := [
				base + Vector3(cos(b0) * cos(a0) * r, sin(a0) * h, sin(b0) * cos(a0) * r),
				base + Vector3(cos(b1) * cos(a0) * r, sin(a0) * h, sin(b1) * cos(a0) * r),
				base + Vector3(cos(b1) * cos(a1) * r, sin(a1) * h, sin(b1) * cos(a1) * r),
				base + Vector3(cos(b0) * cos(a1) * r, sin(a1) * h, sin(b0) * cos(a1) * r),
			]
			var n := []
			for q in p:
				n.append((((q as Vector3) - base) / Vector3(r, h, r)).normalized())
			ProcGeo.tri(st, p[0], p[1], p[2], n[0], n[1], n[2], color)
			ProcGeo.tri(st, p[0], p[2], p[3], n[0], n[2], n[3], color)


func _multimesh(node_name: String, mesh: Mesh, items: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
