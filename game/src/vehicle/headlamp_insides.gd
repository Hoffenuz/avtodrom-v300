class_name HeadlampInsides
extends RefCounted
## The Cobalt's headlamp, built in depth behind its lens hull: the hull keeps
## its shape and its painted housing (headlamp.gdshader, `recessed`), but the
## two round optics are holes in it with real geometry behind, as the other
## cars' modelled lamps have: the projector (a chrome cone into a black bezel
## and a domed dark glass lens) towards the grille, the high-beam reflector
## (a chrome paraboloid bowl with its bulb) towards the wing. They catch the
## light and shift with the view like the real thing instead of reading as a
## picture on the glass. Circle centres and radii are the shader's (bounds).

const SEGMENTS := 40
## Recess depths behind the hull at the optic's rim, metres.
const PROJECTOR_DEPTH := 0.045
const BOWL_DEPTH := 0.04

var lit: Array = [] # [MeshInstance3D, off material, on material]


## `lamps`: the car's lamp meshes by name; the hull is Lamp_Head with the
## indicator end pieces (the high-beam bowl sits partly under those).
## Everything is built in `model`'s space, the space `bounds` was measured in
## (Car.headlamp_bounds).
static func build(lamps: Dictionary, model: Node3D, bounds: Vector4) -> HeadlampInsides:
	var out := HeadlampInsides.new()
	var lamp: MeshInstance3D = lamps["Lamp_Head"]
	# The model's old projector disc (the lens mesh's second surface) would
	# float in front of the new optics: the lens keeps its hull only.
	if lamp.mesh.get_surface_count() > 1:
		var hull := ArrayMesh.new()
		hull.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lamp.mesh.surface_get_arrays(0))
		hull.surface_set_material(0, lamp.mesh.surface_get_material(0))
		var keep := lamp.get_surface_override_material(0)
		lamp.mesh = hull
		lamp.set_surface_override_material(0, keep)
	var tris := PackedVector3Array()
	for name in ["Lamp_Head", "Lamp_TurnFL", "Lamp_TurnFR"]:
		if not lamps.has(name):
			continue
		var mi: MeshInstance3D = lamps[name]
		var xf := Car.chain_to(mi, model)
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var n := idx.size() if not idx.is_empty() else verts.size()
		for i in n:
			tris.append(xf * verts[idx[i] if not idx.is_empty() else i])
	var normal_sum := Vector3.ZERO
	for t in range(0, tris.size() - 2, 3):
		normal_sum -= (tris[t + 1] - tris[t]).cross(tris[t + 2] - tris[t])
	# Out of the lens along the car's length (the shader's circles are drawn
	# along z too).
	var fwd := Vector3(0, 0, -1.0 if normal_sum.z < 0.0 else 1.0)
	var w := bounds.y - bounds.x
	var h := bounds.w - bounds.z

	# Vacuum-plated, not a mirror: a mirror striped the sky across it.
	var chrome := Car._pbr(Color(0.8, 0.81, 0.83), 1.0, 0.22)
	chrome.cull_mode = BaseMaterial3D.CULL_DISABLED
	var satin := Car._pbr(Color(0.78, 0.79, 0.81), 1.0, 0.2)
	satin.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bezel := Car._pbr(Color(0.03, 0.03, 0.035), 0.2, 0.5)
	bezel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_off := Car._pbr(Color(0.025, 0.028, 0.035), 0.0, 0.03)
	lens_off.clearcoat_enabled = true
	lens_off.clearcoat = 1.0
	lens_off.clearcoat_roughness = 0.02
	lens_off.metallic_specular = 0.9
	var lens_on := Car._emissive(Color(1.0, 0.98, 0.94), 3.0)
	var bulb_off := Car._pbr(Color(0.92, 0.92, 0.9), 0.0, 0.15)
	var bulb_on := Car._emissive(Color(1.0, 0.97, 0.9), 4.0)

	for side in [-1.0, 1.0]:
		# The projector.
		var ca := Vector2(side * (bounds.x + w * 0.36), bounds.z + h * 0.5)
		var ra := h * 0.28
		var base := _rim_base(tris, ca, ra, fwd)
		var bottom := base - PROJECTOR_DEPTH
		out._add(model, _cone(tris, ca, ra, ra * 0.8, fwd, bottom), chrome)
		out._add(model, _disc(ca, ra * 0.8, ra * 0.66, bottom, fwd), bezel)
		var lens := out._add(model, _dome(ca, ra * 0.68, bottom, 0.022, fwd), lens_off)
		out.lit.append([lens, lens_off, lens_on])
		# The high-beam bowl.
		var cb := Vector2(side * (bounds.x + w * 0.79), bounds.z + h * 0.56)
		var rb := h * 0.14
		var bbase := _rim_base(tris, cb, rb, fwd)
		out._add(model, _bowl(tris, cb, rb, fwd, bbase - BOWL_DEPTH), satin)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rb * 0.2
		sm.height = rb * 0.4
		sm.radial_segments = 16
		sm.rings = 8
		bulb.mesh = sm
		bulb.material_override = bulb_off
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = Vector3(cb.x, cb.y, 0.0) + fwd * (bbase - BOWL_DEPTH * 0.45)
		model.add_child(bulb)
		out.lit.append([bulb, bulb_off, bulb_on])
	return out


func set_lit(on: bool) -> void:
	for e in lit:
		(e[0] as MeshInstance3D).material_override = e[2] if on else e[1]


func _add(model: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "HeadlampInside"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)
	return mi


## The lens hull's position along `fwd` at (x, y), or NAN off the hull.
static func _surface(tris: PackedVector3Array, p: Vector2, fwd: Vector3) -> float:
	var best := NAN
	for t in range(0, tris.size() - 2, 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var bc := Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
		if not bc:
			continue
		# Barycentric interpolation of z.
		var v0 := Vector2(b.x - a.x, b.y - a.y)
		var v1 := Vector2(c.x - a.x, c.y - a.y)
		var v2 := Vector2(p.x - a.x, p.y - a.y)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		var z := a.z + u * (b.z - a.z) + v * (c.z - a.z)
		var along := z * fwd.z
		if is_nan(best) or along > best:
			best = along
	return best


## The hull along `fwd` at the rim point of angle `ang`, falling back to the
## centre when the rim runs off the hull.
static func _rim(tris: PackedVector3Array, c: Vector2, r: float, ang: float, fwd: Vector3, fallback: float) -> float:
	var s := _surface(tris, c + Vector2(cos(ang), sin(ang)) * r, fwd)
	return fallback if is_nan(s) else s


## The deepest rim point (the recess bottom is measured from it).
static func _rim_base(tris: PackedVector3Array, c: Vector2, r: float, fwd: Vector3) -> float:
	var centre := _surface(tris, c, fwd)
	if is_nan(centre):
		centre = 0.0
	var base := centre
	for i in SEGMENTS:
		base = minf(base, _rim(tris, c, r, TAU * i / SEGMENTS, fwd, centre))
	return base


static func _pt(c: Vector2, r: float, ang: float, along: float, fwd: Vector3) -> Vector3:
	return Vector3(c.x + cos(ang) * r, c.y + sin(ang) * r, 0.0) + fwd * along


## From the hull's edge (r0, following the curved surface) back to r1 at
## `bottom`: the projector's polished cone.
static func _cone(tris: PackedVector3Array, c: Vector2, r0: float, r1: float, fwd: Vector3, bottom: float) -> ArrayMesh:
	var centre := _surface(tris, c, fwd)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 4
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var top0 := _rim(tris, c, r0, a0, fwd, centre)
		var top1 := _rim(tris, c, r0, a1, fwd, centre)
		for k in rings:
			var t0 := float(k) / rings
			var t1 := float(k + 1) / rings
			var p00 := _pt(c, lerpf(r0, r1, t0), a0, lerpf(top0, bottom, t0), fwd)
			var p01 := _pt(c, lerpf(r0, r1, t0), a1, lerpf(top1, bottom, t0), fwd)
			var p10 := _pt(c, lerpf(r0, r1, t1), a0, lerpf(top0, bottom, t1), fwd)
			var p11 := _pt(c, lerpf(r0, r1, t1), a1, lerpf(top1, bottom, t1), fwd)
			for p in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A flat ring at `along`: the black bezel round the projector lens.
static func _disc(c: Vector2, r0: float, r1: float, along: float, fwd: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(fwd)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		for p in [_pt(c, r0, a0, along, fwd), _pt(c, r1, a0, along, fwd), _pt(c, r1, a1, along, fwd),
				_pt(c, r0, a0, along, fwd), _pt(c, r1, a1, along, fwd), _pt(c, r0, a1, along, fwd)]:
			st.add_vertex(p)
	return st.commit()


## A shallow spherical cap of radius r standing `rise` out of `along`: the
## projector's glass lens.
static func _dome(c: Vector2, r: float, along: float, rise: float, fwd: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	for k in rings:
		var t0 := float(k) / rings
		var t1 := float(k + 1) / rings
		for i in SEGMENTS:
			var a0 := TAU * i / SEGMENTS
			var a1 := TAU * (i + 1) / SEGMENTS
			var q := func(t: float, a: float) -> Vector3:
				return _pt(c, r * t, a, along + rise * (1.0 - t * t), fwd)
			for p in [q.call(t0, a0), q.call(t1, a0), q.call(t1, a1), q.call(t0, a0), q.call(t1, a1), q.call(t0, a1)]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A paraboloid bowl from the hull's edge down to `bottom`: the reflector.
static func _bowl(tris: PackedVector3Array, c: Vector2, r: float, fwd: Vector3, bottom: float) -> ArrayMesh:
	var centre := _surface(tris, c, fwd)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var top0 := _rim(tris, c, r, a0, fwd, centre)
		var top1 := _rim(tris, c, r, a1, fwd, centre)
		for k in rings:
			# t: 0 at the rim, 1 at the bottom; the radius falls as sqrt.
			var t0 := float(k) / rings
			var t1 := float(k + 1) / rings
			var q := func(t: float, a: float, top: float) -> Vector3:
				return _pt(c, r * sqrt(1.0 - t), a, lerpf(top, bottom, t), fwd)
			for p in [q.call(t0, a0, top0), q.call(t1, a0, top0), q.call(t1, a1, top1),
					q.call(t0, a0, top0), q.call(t1, a1, top1), q.call(t0, a1, top1)]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()
