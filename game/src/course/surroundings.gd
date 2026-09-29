class_name Surroundings
extends Node3D
## Everything outside the avtodrom fence, built once and baked with the
## course: the ring road, the exam centre with its car park and parked cars,
## a hedge, poplar rows and park trees, and a far ring of city blocks.
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
const TREE_SECTORS := 6

var fence: Rect2
var quality := 1
var mat: Dictionary
var _rng := RandomNumberGenerator.new()
var _facade: ShaderMaterial
var _keep_out: Array[Rect2] = [] # areas trees must avoid (road, building, car park)


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
	_build_poplars()
	_build_park_trees()
	_build_city()


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


## Axis-aligned box as part of a SurfaceTool mesh (vertex colour = `color`).
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
	var bld := Rect2(0.0, park.position.y - 20.0, 48.0, 16.0)
	_keep_out.append(park)
	_keep_out.append(bld.grow(4.0))

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

	# Forecourt paving in front of the building.
	var fc := _st()
	MeshUtil.add_polygon(fc, _rect_poly(Rect2(bld.position.x - 3.0, bld.end.y, bld.size.x + 6.0, 4.0)), RING_Y + PAINT_LIFT, 3.0)
	fc.index()
	fc.generate_tangents()
	fc.set_material(mat["concrete"])
	_instance(fc.commit(), "Forecourt", false)

	# Building: two storeys, a taller entrance block, parapet and canopy.
	var b := _st()
	var h := 7.6
	var cx := bld.get_center().x
	var cz := bld.get_center().y
	var wall := Color(0.93, 0.9, 0.84)
	_box(b, Vector3(cx, h * 0.5, cz), Vector3(bld.size.x, h, bld.size.y), wall)
	_box(b, Vector3(cx, h + 0.35, cz), Vector3(bld.size.x + 0.4, 0.7, bld.size.y + 0.4), wall * 0.92)
	_box(b, Vector3(cx, 5.2, bld.end.y + 1.0), Vector3(12.0, 10.4, 2.4), Color(0.8, 0.84, 0.9))
	_box(b, Vector3(cx, 3.2, bld.end.y + 3.4), Vector3(14.0, 0.3, 3.2), Color(0.35, 0.37, 0.4))
	for sx in [-6.4, 6.4]:
		_box(b, Vector3(cx + sx, 1.6, bld.end.y + 4.6), Vector3(0.3, 3.2, 0.3), Color(0.35, 0.37, 0.4))
	b.index()
	var bm := _facade.duplicate() as ShaderMaterial
	b.set_material(bm)
	_instance(b.commit(), "ExamCentre", true)
	# Glass doors under the canopy.
	var doors := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(6.0, 2.6, 0.1)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.17, 0.22)
	glass.roughness = 0.1
	glass.metallic = 0.3
	dm.material = glass
	doors.mesh = dm
	doors.position = Vector3(cx, 1.3, bld.end.y + 2.25)
	add_child(doors)
	# Name on the entrance block, facing the field.
	var sign := Label3D.new()
	sign.text = "IMTIHON MARKAZI"
	sign.font_size = 96
	sign.pixel_size = 0.0125
	sign.modulate = Color(0.1, 0.24, 0.5)
	sign.outline_size = 0
	sign.shaded = true
	sign.double_sided = false
	sign.position = Vector3(cx, 8.6, bld.end.y + 2.25)
	var font: Font = load("res://assets/fonts/Inter.ttf")
	if font:
		var fv := FontVariation.new()
		fv.base_font = font
		fv.variation_opentype = {"wght": 750}
		sign.font = fv
	add_child(sign)


func _park_cars(bays: Array) -> void:
	var paints := [Color(0.95, 0.95, 0.96), Color(0.93, 0.93, 0.94), Color(0.1, 0.1, 0.11), Color(0.62, 0.64, 0.66),
			Color(0.55, 0.08, 0.08), Color(0.12, 0.2, 0.42), Color(0.75, 0.73, 0.68), Color(0.2, 0.22, 0.24)]
	var models := ["res://assets/cars/lod/nexia2_parked.glb", "res://assets/cars/lod/cobalt_parked.glb",
			"res://assets/cars/lod/gentra_parked.glb"]
	var picks := []
	for m in models.size():
		picks.append([])
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = load("res://assets/shaders/car_parked.gdshader")
	for bay in bays:
		if _rng.randf() < 0.62:
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
			var p: Vector2 = bay[0]
			var yaw: float = bay[1] + _rng.randf_range(-0.04, 0.04)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, RING_Y, p.y)) * local)
			var c: Color = paints[_rng.randi() % paints.size()]
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, c.srgb_to_linear())
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "ParkedCars%d" % m
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _chain(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != top and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# --------------------------------------------------------------------------- green
func _build_hedge() -> void:
	# A trimmed hedge outside the fence, with gaps behind the lamp posts'
	# side of the road. One mesh.
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
			var size := Vector3(seg, 1.1, 1.1) if along else Vector3(1.1, 1.1, seg)
			_box(st, Vector3(mid.x, 0.55, mid.y), size, Color(0.2, 0.34, 0.14).lerp(Color(0.26, 0.4, 0.16), _rng.randf()))
			k += seg + _rng.randf_range(1.5, 4.0)
	st.index()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	st.set_material(m)
	_instance(st.commit(), "Hedge", quality >= 2)


func _crown_mesh() -> ArrayMesh:
	# Overlapping blobs: reads as a tree crown from every side. Medium and
	# low get two coarser blobs (72 tris instead of 180): ~110 of these fill
	# every view out of the car.
	var blobs := [[Vector3(0, 0, 0), 1.0, 6, 4], [Vector3(0.7, -0.25, 0.3), 0.75, 6, 4],
			[Vector3(-0.55, -0.2, -0.45), 0.8, 6, 4]]
	if quality <= 1:
		blobs = [[Vector3(0.08, 0, 0.05), 1.0, 6, 3], [Vector3(-0.55, -0.22, -0.35), 0.8, 4, 2]]
	var st := _st()
	for b in blobs:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = b[2]
		sphere.rings = b[3]
		st.append_from(sphere, 0, Transform3D(Basis().scaled(Vector3.ONE * float(b[1])), b[0]))
	return st.commit()


func _build_poplars() -> void:
	# Poplar rows along the outer side of the ring road — the classic
	# Uzbek roadside tree: tall, narrow, dark green.
	var spacing := 6.5 if quality >= 1 else 11.0
	var r := fence.grow(ROAD_OFFSET + ROAD_WIDTH * 0.5 + 3.0)
	var pts: Array[Vector2] = []
	var c := _rect_poly(r)
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
			if not skip:
				pts.append(p + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)))
			k += spacing * _rng.randf_range(0.85, 1.15)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.1
	trunk.bottom_radius = 0.2
	trunk.height = 3.0
	trunk.radial_segments = 5
	trunk.rings = 0
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 6
	crown.rings = 5 if quality >= 2 else 4
	_scatter("Poplar", pts, trunk, crown, func(s: float) -> Array:
		# [trunk basis/offset, crown scale, crown centre height]
		var hgt := 10.0 * s * _rng.randf_range(0.85, 1.2)
		var wid := 1.25 * s * _rng.randf_range(0.8, 1.2)
		return [Vector3(1.0, 1.0, 1.0) * s, Vector3(wid, hgt * 0.5, wid), 2.0 * s + hgt * 0.5],
		Color(0.14, 0.28, 0.11), Color(0.27, 0.4, 0.15))


func _build_park_trees() -> void:
	var count := 110 if quality >= 1 else 55
	var pts: Array[Vector2] = []
	var tries := 0
	while pts.size() < count and tries < count * 20:
		tries += 1
		var side := _rng.randi() % 4
		var along := _rng.randf()
		var dist := _rng.randf_range(ROAD_OFFSET + 8.0, 70.0)
		var outer := fence.grow(20.0)
		var p: Vector2
		match side:
			0: p = Vector2(lerpf(outer.position.x - 40.0, outer.end.x + 40.0, along), fence.position.y - dist)
			1: p = Vector2(lerpf(outer.position.x - 40.0, outer.end.x + 40.0, along), fence.end.y + dist)
			2: p = Vector2(fence.position.x - dist, lerpf(outer.position.y, outer.end.y, along))
			_: p = Vector2(fence.end.x + dist, lerpf(outer.position.y, outer.end.y, along))
		if _clear_of(p, 3.0):
			pts.append(p)
	# Three kinds, so the park is not one tree copied a hundred times:
	# broad-leaved (plane, elm), conifers (archa / spruce) and small round
	# ornamental trees, each with its own spread of greens.
	var broad: Array[Vector2] = []
	var conifer: Array[Vector2] = []
	var small: Array[Vector2] = []
	for p in pts:
		var r := _rng.randf()
		if r < 0.5:
			broad.append(p)
		elif r < 0.75:
			conifer.append(p)
		else:
			small.append(p)
	_scatter("ParkTree", broad, _trunk(0.13, 0.22), _crown_mesh(), func(s: float) -> Array:
		var spread := _rng.randf_range(0.85, 1.2)
		return [Vector3(1.0, 1.0, 1.0) * s, Vector3(2.4 * spread, 2.1, 2.4 * spread) * s, 4.2 * s],
		Color(0.2, 0.36, 0.14), Color(0.38, 0.48, 0.17))
	_scatter("Conifer", conifer, _trunk(0.1, 0.18), _conifer_mesh(), func(s: float) -> Array:
		var tall := _rng.randf_range(0.9, 1.35)
		return [Vector3(1.0, 0.5, 1.0) * s, Vector3(1.9, 3.6 * tall, 1.9) * s, (0.8 + 3.6 * tall) * s],
		Color(0.07, 0.19, 0.09), Color(0.12, 0.26, 0.12))
	_scatter("SmallTree", small, _trunk(0.08, 0.13), _round_crown_mesh(), func(s: float) -> Array:
		return [Vector3(0.7, 0.7, 0.7) * s, Vector3(1.5, 1.3, 1.5) * s, 2.9 * s],
		Color(0.34, 0.5, 0.18), Color(0.52, 0.56, 0.2))


func _trunk(top: float, bottom: float) -> CylinderMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = top
	trunk.bottom_radius = bottom
	trunk.height = 3.0
	trunk.radial_segments = 5
	trunk.rings = 0
	return trunk


## A spruce/archa: three stacked cones, the crown's y from -1 to +1.
func _conifer_mesh() -> ArrayMesh:
	var st := _st()
	var tiers := [[1.0, -1.0, 0.95], [0.78, -0.45, 0.85], [0.52, 0.12, 0.88]] # radius, base y, height
	var segs := 7 if quality >= 1 else 5
	for t in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(t[0])
		cone.height = float(t[2])
		cone.radial_segments = segs
		cone.rings = 0
		cone.cap_bottom = true
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, float(t[1]) + float(t[2]) * 0.5, 0)))
	return st.commit()


## A small ornamental tree: one slightly flattened ball.
func _round_crown_mesh() -> ArrayMesh:
	var st := _st()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 7 if quality >= 1 else 5
	sphere.rings = 4 if quality >= 1 else 3
	st.append_from(sphere, 0, Transform3D())
	return st.commit()


## Trunks and crowns as MultiMeshes, one pair per sector around the field
## (nodes `<label>Trunks<k>` / `<label>Crowns<k>`): a single MultiMesh would
## have one AABB around the whole site and never be frustum-culled, so the
## trees behind the camera would still be drawn. `shape(scale)` returns
## [trunk scale, crown scale, crown centre height].
func _scatter(label: String, pts: Array[Vector2], trunk: Mesh, crown: Mesh, shape: Callable, c0: Color,
		c1: Color) -> void:
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.3, 0.23, 0.16)
	tm.roughness = 0.9
	(trunk as PrimitiveMesh).material = tm
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	if crown is ArrayMesh:
		(crown as ArrayMesh).surface_set_material(0, cm)
	else:
		(crown as PrimitiveMesh).material = cm
	# Same draw order and rng use as one big scatter: only the grouping differs.
	var trunks: Array = []
	var crowns: Array = []
	for k in TREE_SECTORS:
		trunks.append([])
		crowns.append([])
	var centre := fence.get_center()
	for p in pts:
		var s := _rng.randf_range(0.8, 1.25)
		var sh: Array = shape.call(s)
		var ts: Vector3 = sh[0]
		var cs: Vector3 = sh[1]
		var cb := Basis(Vector3.UP, _rng.randf() * TAU).scaled(cs)
		var k := _sector(p - centre)
		trunks[k].append(Transform3D(Basis().scaled(ts), Vector3(p.x, 1.5 * ts.y, p.y)))
		crowns[k].append([Transform3D(cb, Vector3(p.x, float(sh[2]), p.y)), c0.lerp(c1, _rng.randf())])
	for k in TREE_SECTORS:
		if trunks[k].is_empty():
			continue
		var tmm := MultiMesh.new()
		tmm.transform_format = MultiMesh.TRANSFORM_3D
		tmm.mesh = trunk
		tmm.instance_count = trunks[k].size()
		var cmm := MultiMesh.new()
		cmm.transform_format = MultiMesh.TRANSFORM_3D
		cmm.use_colors = true
		cmm.mesh = crown
		cmm.instance_count = crowns[k].size()
		for i in trunks[k].size():
			tmm.set_instance_transform(i, trunks[k][i])
			cmm.set_instance_transform(i, crowns[k][i][0])
			cmm.set_instance_color(i, crowns[k][i][1])
		for pair in [[tmm, label + "Trunks%d" % k], [cmm, label + "Crowns%d" % k]]:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = pair[1]
			mmi.multimesh = pair[0]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 1 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


## Sector (0 .. TREE_SECTORS-1) of a direction from the field centre.
static func _sector(d: Vector2) -> int:
	var a := fposmod(d.angle() + PI / TREE_SECTORS, TAU)
	return mini(int(a / TAU * TREE_SECTORS), TREE_SECTORS - 1)


# --------------------------------------------------------------------------- city
## A ring of blocks 230–420 m away, softened by the fog: Tashkent's mix of
## 9- and 16-storey panel blocks (balconies, panel seams, stair columns),
## low 4–5 storey houses under pitched roofs and a few glass towers. Some
## blocks have a second wing (L plan) and every flat roof its lift housing.
## Three MultiMeshes: walls, roof boxes, pitched roofs.
func _build_city() -> void:
	var count := 90 if quality >= 1 else 50
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _facade
	var blocks: Array = [] # [transform, colour]
	var roof_boxes: Array = []
	var roofs: Array = [] # pitched
	var panel_colours := [Color(0.9, 0.87, 0.8), Color(0.85, 0.85, 0.83), Color(0.78, 0.82, 0.86),
			Color(0.92, 0.84, 0.72), Color(0.8, 0.76, 0.7), Color(0.93, 0.9, 0.84), Color(0.86, 0.8, 0.74),
			Color(0.76, 0.8, 0.78)]
	var roof_colours := [Color(0.45, 0.2, 0.16), Color(0.36, 0.38, 0.4), Color(0.5, 0.3, 0.22), Color(0.3, 0.42, 0.36)]
	for i in count:
		var ang := TAU * (i + _rng.randf_range(-0.35, 0.35)) / count
		var rad := _rng.randf_range(230.0, 420.0)
		var kind := _rng.randf()
		var h: float
		var style: float
		var col: Color = panel_colours[_rng.randi() % panel_colours.size()]
		if kind < 0.1:
			h = _rng.randf_range(45.0, 80.0) # glass tower
			style = 0.68
			col = [Color(0.72, 0.8, 0.86), Color(0.8, 0.82, 0.84), Color(0.66, 0.74, 0.78)][_rng.randi() % 3]
		elif kind < 0.3:
			h = 16 * 3.0 + 1.5 # 16 storeys
			style = [0.1, 0.3, 0.5][_rng.randi() % 3]
		elif kind < 0.72:
			h = 9 * 3.0 + 1.5 # 9 storeys
			style = [0.1, 0.1, 0.3, 0.5][_rng.randi() % 4]
		else:
			h = _rng.randi_range(4, 5) * 3.0 + 1.0 # low houses, pitched roofs
			style = 0.95
		var w := _rng.randf_range(24.0, 60.0) if kind >= 0.1 and kind < 0.72 else _rng.randf_range(14.0, 30.0)
		var d := _rng.randf_range(12.0, 15.0) if kind >= 0.1 else _rng.randf_range(20.0, 30.0)
		var yaw := -ang + PI * 0.5 + _rng.randf_range(-0.2, 0.2)
		var rot := Basis(Vector3.UP, yaw)
		var pos := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad * 0.8)
		col.a = style
		blocks.append([Transform3D(rot.scaled(Vector3(w, h, d)), pos + Vector3(0, h * 0.5, 0)), col])
		var flat := kind < 0.72
		if flat:
			# Lift / stair housing on the roof.
			var rb := Vector3(minf(w * 0.18, 7.0), 2.8, d * 0.45)
			var off := rot * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), h + rb.y * 0.5, 0.0)
			roof_boxes.append([Transform3D(rot.scaled(rb), pos + off), Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.8)])
		else:
			var rh := d * 0.28
			roofs.append([Transform3D(rot * Basis(Vector3.UP, PI * 0.5).scaled(Vector3(d * 1.04, rh, w * 1.02)),
					pos + Vector3(0, h + rh * 0.5, 0)), roof_colours[_rng.randi() % roof_colours.size()]])
		if kind >= 0.1 and kind < 0.72 and _rng.randf() < 0.3:
			# A second wing at right angles: an L-shaped block.
			var w2 := _rng.randf_range(18.0, 30.0)
			var wing := rot * Basis(Vector3.UP, PI * 0.5)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var off2 := rot * Vector3(side * (w * 0.5 - d * 0.5), 0.0, w2 * 0.5 + d * 0.5)
			blocks.append([Transform3D(wing.scaled(Vector3(w2, h, d)), pos + off2 + Vector3(0, h * 0.5, 0)), col])
	_multimesh("City", box, blocks)
	var rbox := BoxMesh.new()
	rbox.size = Vector3.ONE
	rbox.material = _facade
	_multimesh("CityRoofBoxes", rbox, roof_boxes)
	if not roofs.is_empty():
		var prism := PrismMesh.new()
		prism.size = Vector3.ONE
		var rm := StandardMaterial3D.new()
		rm.vertex_color_use_as_albedo = true
		rm.roughness = 0.85
		prism.material = rm
		_multimesh("CityRoofs", prism, roofs)


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
