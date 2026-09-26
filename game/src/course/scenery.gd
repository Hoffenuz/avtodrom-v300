class_name Scenery
extends Node3D
## The world outside the avtodrom fence: a street around the site with
## sidewalks and poplar rows, apartment blocks, shops and warehouses, parks,
## a far city skyline, hills on the horizon and ground out to the far plane.
##
## Built at load time (a few ms) next to the course, so it never touches the
## baked course scene. Everything is static and merged: buildings, trees and
## hills share one material and are split into four meshes (one per side of
## the site) so the side behind the camera is culled; road surfaces reuse the
## course's own ground materials. No collision (the car cannot leave the
## fence) and no shadows (the shadow pass would draw every tree once more per
## split).
## Budget (Medium): ~30k triangles, 12 draw calls for the whole ring, of
## which the camera sees about half.

const FENCE_MARGIN := 1.6 # CourseBuilder._build_fence grows the fence rect by this
const ROAD_OFFSET := 18.0 # street centre line, measured from the fence
const ROAD_W := 7.5
const WALK_W := 2.5
const ROAD_CORNER_R := 16.0
const GROUND_REACH := 1000.0
const LAWN_REACH := 160.0 # CourseBuilder._build_ground lawn frame
const TILE_ASPHALT := 4.0
const TILE_CONCRETE := 3.0
const TILE_GRASS := 5.0
const CELL := 3.2 # window spacing along a wall (facade.gdshader)
const FLOOR_H := 3.0

const WALL_COLORS := [Color(0.88, 0.84, 0.76), Color(0.92, 0.87, 0.78), Color(0.8, 0.8, 0.78),
		Color(0.9, 0.8, 0.64), Color(0.84, 0.76, 0.68), Color(0.94, 0.91, 0.85), Color(0.8, 0.72, 0.62),
		Color(0.86, 0.74, 0.6), Color(0.78, 0.82, 0.84)]
const SHOP_COLORS := [Color(0.85, 0.62, 0.45), Color(0.62, 0.72, 0.8), Color(0.9, 0.84, 0.62),
		Color(0.7, 0.78, 0.66), Color(0.92, 0.9, 0.86)]
const ROOF_COLOR := Color(0.36, 0.36, 0.37)

var quality := 1
var _rng := RandomNumberGenerator.new()
var _half := Vector2.ZERO # fence half extents (grown)
var _centre := Vector2.ZERO
var _sides: Array[SurfaceTool] = [] # N, E, S, W
var _tree_sides: Array[SurfaceTool] = []
var _blocked: Array[Rect2] = [] # footprints already used (buildings, road)
var _radial: Array[Rect2] = [] # the two roads leading away (no trees on them)
var _asphalt: SurfaceTool
var _walk: SurfaceTool
var _paint: SurfaceTool
var _ground: SurfaceTool


## Builds the scenery around `course` and adds it as a child of `parent`.
static func create(parent: Node, course: CourseBuilder, p_quality: int) -> Scenery:
	var s := Scenery.new()
	s.name = "Scenery"
	s.build(course, p_quality)
	parent.add_child(s)
	return s


func build(course: CourseBuilder, p_quality: int) -> void:
	quality = p_quality
	_rng.seed = 7_2026_0926
	# The course used to plant a ring of ball-shaped trees; the scenery has its
	# own, so drop them if an older baked course still carries them.
	for n in ["TreeCrowns", "TreeTrunks"]:
		var old := course.get_node_or_null(n)
		if old:
			course.remove_child(old)
			old.free()
	var r := Rect2(course.data.fence[0], Vector2.ZERO)
	for p in course.data.fence:
		r = r.expand(p)
	r = r.grow(FENCE_MARGIN)
	_centre = r.get_center()
	_half = r.size * 0.5
	for i in 4:
		_sides.append(_begin())
		_tree_sides.append(_begin())
	_asphalt = _begin()
	_walk = _begin()
	_paint = _begin()
	_ground = _begin()

	_build_ground()
	_build_street()
	_build_radial_roads()
	_place_buildings()
	_place_trees()
	_build_skyline()
	_build_hills()
	_commit(course)


# --------------------------------------------------------------------------- helpers
func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Which side of the site a point belongs to: 0 = N (-z), 1 = E, 2 = S, 3 = W.
func _side_of(p: Vector2) -> int:
	var d := p - _centre
	if absf(d.x) / _half.x > absf(d.y) / _half.y:
		return 1 if d.x > 0.0 else 3
	return 2 if d.y > 0.0 else 0


## Flat ground quad a-b-c-d at height y, UV in world metres / tile.
func _flat(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, tile: float,
		col := Color.WHITE) -> void:
	var uv := PackedVector2Array([a / tile, b / tile, c / tile, d / tile])
	ProcGeo.quad(st, _v3(a, y), _v3(b, y), _v3(c, y), _v3(d, y), Vector3.UP, col, uv)


## Closed rounded-rectangle loop around the site at `offset` from the fence.
func _loop(offset: float, corner_r: float, seg := 8) -> PackedVector2Array:
	var hx := _half.x + offset
	var hz := _half.y + offset
	var rr := minf(corner_r, minf(hx, hz))
	var pts := PackedVector2Array()
	var centres := [Vector2(hx - rr, hz - rr), Vector2(-hx + rr, hz - rr), Vector2(-hx + rr, -hz + rr),
			Vector2(hx - rr, -hz + rr)]
	for c in 4:
		for k in seg + 1:
			var a := PI * 0.5 * (c + float(k) / seg)
			pts.append(_centre + centres[c] + Vector2(cos(a), sin(a)) * rr)
	return pts


## Band between two parallel closed loops (same point count).
func _band(st: SurfaceTool, inner: PackedVector2Array, outer: PackedVector2Array, y: float, tile: float) -> void:
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		_flat(st, inner[i], inner[j], outer[j], outer[i], y, tile)


# --------------------------------------------------------------------------- ground
func _build_ground() -> void:
	# Frame from the edge of the course lawn out to the far plane, split into
	# rings so no triangle is huge (keeps the vertex fog smooth).
	var steps := [LAWN_REACH, 320.0, 560.0, GROUND_REACH]
	for k in steps.size() - 1:
		var r0 := Rect2(_centre - _half, _half * 2.0).grow(steps[k])
		var r1 := Rect2(_centre - _half, _half * 2.0).grow(steps[k + 1])
		var a := [r0.position, Vector2(r0.end.x, r0.position.y), r0.end, Vector2(r0.position.x, r0.end.y)]
		var b := [r1.position, Vector2(r1.end.x, r1.position.y), r1.end, Vector2(r1.position.x, r1.end.y)]
		for i in 4:
			var j := (i + 1) % 4
			_flat(_ground, a[i], a[j], b[j], b[i], -0.002, TILE_GRASS)


# --------------------------------------------------------------------------- roads
## A two-lane street around the whole site with sidewalks on both sides.
func _build_street() -> void:
	var half_w := ROAD_W * 0.5
	var road_in := _loop(ROAD_OFFSET - half_w, ROAD_CORNER_R - half_w)
	var road_out := _loop(ROAD_OFFSET + half_w, ROAD_CORNER_R + half_w)
	_band(_asphalt, road_in, road_out, 0.012, TILE_ASPHALT)
	_band(_walk, _loop(ROAD_OFFSET - half_w - WALK_W, ROAD_CORNER_R - half_w - WALK_W), road_in, 0.016,
			TILE_CONCRETE)
	_band(_walk, road_out, _loop(ROAD_OFFSET + half_w + WALK_W, ROAD_CORNER_R + half_w + WALK_W), 0.016,
			TILE_CONCRETE)
	# Edge lines and a dashed centre line.
	_line_loop(_loop(ROAD_OFFSET - half_w + 0.35, ROAD_CORNER_R - half_w + 0.35), 0.12, 0.0)
	_line_loop(_loop(ROAD_OFFSET + half_w - 0.35, ROAD_CORNER_R + half_w - 0.35), 0.12, 0.0)
	_line_loop(_loop(ROAD_OFFSET, ROAD_CORNER_R, 12), 0.12, 3.0)
	var street := Rect2(_centre - _half, _half * 2.0).grow(ROAD_OFFSET + half_w + WALK_W + 1.0)
	_blocked.append(street)


## Painted line along a closed loop; `dash` > 0 makes it dashed (dash = gap).
func _line_loop(loop: PackedVector2Array, width: float, dash: float) -> void:
	var n := loop.size()
	var along := 0.0
	for i in n:
		var a := loop[i]
		var b := loop[(i + 1) % n]
		var seg_len := a.distance_to(b)
		if seg_len < 0.001:
			continue
		var d := (b - a) / seg_len
		var side := d.orthogonal() * width * 0.5
		if dash <= 0.0:
			_flat(_paint, a - side, b - side, b + side, a + side, 0.02, 1.0)
			continue
		var t := 0.0
		while t < seg_len:
			var phase := fmod(along + t, dash * 2.0)
			var run := (dash - phase) if phase < dash else (dash * 2.0 - phase)
			var t1 := minf(t + run, seg_len)
			if phase < dash:
				var p0 := a + d * t
				var p1 := a + d * t1
				_flat(_paint, p0 - side, p1 - side, p1 + side, p0 + side, 0.02, 1.0)
			t = t1 + 0.0001
		along += seg_len


## Two long roads leading away from the street towards the city.
func _build_radial_roads() -> void:
	var half_w := ROAD_W * 0.5
	var start_n := _centre + Vector2(-38.0, -_half.y - ROAD_OFFSET - half_w)
	var start_e := _centre + Vector2(_half.x + ROAD_OFFSET + half_w, 14.0)
	for road in [[start_n, Vector2(0, -1)], [start_e, Vector2(1, 0)]]:
		var p0: Vector2 = road[0]
		var dir: Vector2 = road[1]
		var side := dir.orthogonal() * half_w
		var p1 := p0 + dir * (GROUND_REACH - 60.0)
		_flat(_asphalt, p0 - side, p1 - side, p1 + side, p0 + side, 0.012, TILE_ASPHALT)
		var ws := dir.orthogonal() * (half_w + WALK_W)
		_flat(_walk, p0 + side, p1 + side, p1 + ws, p0 + ws, 0.016, TILE_CONCRETE)
		_flat(_walk, p0 - ws, p1 - ws, p1 - side, p0 - side, 0.016, TILE_CONCRETE)
		var t := 1.5
		var ls := dir.orthogonal() * 0.06
		while t < p0.distance_to(p1) - 3.0:
			var a := p0 + dir * t
			var b := a + dir * 3.0
			_flat(_paint, a - ls, b - ls, b + ls, a + ls, 0.02, 1.0)
			t += 6.0
		var lo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)) - Vector2.ONE * (half_w + WALK_W + 2.0)
		var hi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y)) + Vector2.ONE * (half_w + WALK_W + 2.0)
		_blocked.append(Rect2(lo, hi - lo))
		_radial.append(Rect2(lo, hi - lo))


# --------------------------------------------------------------------------- buildings
## Tries to place a building footprint of `size` (x, z) centred at `c`;
## returns false if it would overlap something already there.
func _free(rect: Rect2) -> bool:
	for b in _blocked:
		if b.intersects(rect):
			return false
	return true


## A block of flats: `cells` window cells long, `floors` high, rotated so its
## long side runs along `along_x`. Adds a paved apron and roof details.
func _add_block(c: Vector2, cells_long: int, cells_deep: int, floors: int, along_x: bool, col: Color,
		windows := true, roof_col := ROOF_COLOR) -> bool:
	var L := cells_long * CELL
	var D := cells_deep * CELL
	var size := Vector2(L, D) if along_x else Vector2(D, L)
	var rect := Rect2(c - size * 0.5, size)
	if not _free(rect.grow(4.0)):
		return false
	_blocked.append(rect.grow(4.0))
	var side := _side_of(c)
	var st := _sides[side]
	var h := floors * FLOOR_H + 0.6
	var wall := Color(col.r, col.g, col.b, 1.0 if windows else 0.0)
	var roof := Color(roof_col.r, roof_col.g, roof_col.b, 0.0)
	var xf := Transform3D(Basis(), _v3(c))
	var lo := Vector3(-size.x * 0.5, 0.0, -size.y * 0.5)
	var hi := Vector3(size.x * 0.5, h, size.y * 0.5)
	ProcGeo.box(st, xf, lo, hi, wall, true, roof)
	# Parapet cap and lift machine rooms on tall blocks.
	if floors >= 5:
		var cap := Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.0)
		ProcGeo.box(st, xf, Vector3(lo.x - 0.15, h, lo.z - 0.15), Vector3(hi.x + 0.15, h + 0.35, hi.z + 0.15), cap,
				true, roof)
		var rooms := maxi(1, cells_long / 7)
		for k in rooms:
			var t := (k + 0.5) / rooms - 0.5
			var o := Vector3(t * L, 0, 0) if along_x else Vector3(0, 0, t * L)
			ProcGeo.box(st, xf, o + Vector3(-1.8, h + 0.35, -1.8), o + Vector3(1.8, h + 2.8, 1.8), cap, true, roof)
	# Paved apron around the building.
	var ap := rect.grow(3.0)
	_flat(_walk, ap.position, Vector2(ap.end.x, ap.position.y), ap.end, Vector2(ap.position.x, ap.end.y), 0.01,
			TILE_CONCRETE)
	return true


## Walks along one side of the site, placing rows of buildings.
## `axis` 0 = rows run along x (north / south), 1 = along z (east / west).
func _building_row(side_sign: float, axis: int, dist: float, span: float, kinds: Array) -> void:
	var t := -span
	while t < span:
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var cells := 10
		var deep := 4
		var floors := 9
		var col: Color = WALL_COLORS[_rng.randi() % WALL_COLORS.size()]
		var windows := true
		var roof := ROOF_COLOR
		match kind:
			"panel9":
				cells = _rng.randi_range(14, 22)
				floors = 9
			"panel5":
				cells = _rng.randi_range(12, 20)
				floors = 5
			"tower":
				cells = 7
				deep = 7
				floors = _rng.randi_range(12, 16)
			"shop":
				cells = _rng.randi_range(6, 11)
				deep = 3
				floors = _rng.randi_range(1, 2)
				col = SHOP_COLORS[_rng.randi() % SHOP_COLORS.size()]
			"warehouse":
				cells = _rng.randi_range(10, 15)
				deep = 6
				floors = 2
				col = Color(0.72, 0.72, 0.7)
				windows = false
				roof = Color(0.55, 0.57, 0.6)
		var L := cells * CELL
		var D := deep * CELL
		var along_x := axis == 0
		# Towers and shops sometimes turn end-on to the street.
		if kind == "panel5" and _rng.randf() < 0.3:
			along_x = not along_x
		var depth_extent := D if along_x == (axis == 0) else L
		var len_extent := L if along_x == (axis == 0) else D
		var d := dist + depth_extent * 0.5 + _rng.randf_range(0.0, 8.0)
		var mid := t + len_extent * 0.5
		var c: Vector2
		if axis == 0:
			c = _centre + Vector2(mid, side_sign * (_half.y + d))
		else:
			c = _centre + Vector2(side_sign * (_half.x + d), mid)
		_add_block(c, cells, deep, floors, along_x, col, windows, roof)
		t += len_extent + _rng.randf_range(10.0, 26.0)


func _place_buildings() -> void:
	var near := ROAD_OFFSET + ROAD_W * 0.5 + WALK_W + 14.0
	var wide_x := _half.x + 150.0
	var wide_z := _half.y + 90.0
	# North: nine-storey panel blocks behind a row of shops, towers behind.
	_building_row(-1.0, 0, near, wide_x, ["shop", "shop", "panel5"])
	_building_row(-1.0, 0, near + 38.0, wide_x, ["panel9", "panel9", "panel5"])
	_building_row(-1.0, 0, near + 95.0, wide_x, ["tower", "panel9"])
	# South: warehouses and garages first, then housing.
	_building_row(1.0, 0, near, wide_x, ["warehouse", "shop", "warehouse"])
	_building_row(1.0, 0, near + 45.0, wide_x, ["panel5", "panel9", "panel5"])
	_building_row(1.0, 0, near + 100.0, wide_x, ["tower", "panel9"])
	# East and west ends.
	for s in [-1.0, 1.0]:
		_building_row(s, 1, near + 6.0, wide_z, ["panel5", "shop"])
		_building_row(s, 1, near + 50.0, wide_z, ["panel9", "tower"])


# --------------------------------------------------------------------------- trees
## Lombardy poplar (the roadside tree of Uzbekistan): tall and narrow.
func _poplar(p: Vector2, s: float) -> void:
	var st := _tree_sides[_side_of(p)]
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _v3(p))
	var bark := Color(0.36, 0.3, 0.24, 0.0)
	ProcGeo.cylinder(st, xf, Vector3.ZERO, 0.2, 0.12, 3.2, 5, bark, false)
	var g := Color(0.2, 0.34, 0.13).lerp(Color(0.3, 0.42, 0.16), _rng.randf())
	ProcGeo.blob(st, xf, Vector3(0, 7.6, 0), Vector3(1.45, 5.8, 1.45), 7, 5, Color(g.r, g.g, g.b, 0.0), _rng, 0.14,
			Color(g.r * 0.6, g.g * 0.6, g.b * 0.6, 0.0))


## Broad deciduous tree (plane / elm): two overlapping lumpy crowns.
func _broadleaf(p: Vector2, s: float) -> void:
	var st := _tree_sides[_side_of(p)]
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _v3(p))
	var bark := Color(0.4, 0.34, 0.27, 0.0)
	ProcGeo.cylinder(st, xf, Vector3.ZERO, 0.3, 0.2, 3.4, 6, bark, false)
	var g := Color(0.24, 0.4, 0.14).lerp(Color(0.36, 0.48, 0.18), _rng.randf())
	var gc := Color(g.r, g.g, g.b, 0.0)
	var dark := Color(g.r * 0.55, g.g * 0.55, g.b * 0.55, 0.0)
	ProcGeo.blob(st, xf, Vector3(0, 5.4, 0), Vector3(3.0, 2.5, 3.0), 8, 5, gc, _rng, 0.16, dark)
	var off := Vector3(_rng.randf_range(-1.2, 1.2), 6.6, _rng.randf_range(-1.2, 1.2))
	ProcGeo.blob(st, xf, off, Vector3(2.0, 1.7, 2.0), 6, 4, gc.lightened(0.06), _rng, 0.16, dark)


func _tree_row(loop: PackedVector2Array, spacing: float, poplar_share: float, keep: float) -> void:
	var n := loop.size()
	var carry := 0.0
	for i in n:
		var a := loop[i]
		var b := loop[(i + 1) % n]
		var L := a.distance_to(b)
		var t := carry
		while t < L:
			var p := a.lerp(b, t / L) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
			if _rng.randf() < keep and not _on_radial_road(p):
				if _rng.randf() < poplar_share:
					_poplar(p, _rng.randf_range(0.85, 1.15))
				else:
					_broadleaf(p, _rng.randf_range(0.75, 1.1))
			t += spacing
		carry = t - L


func _on_radial_road(p: Vector2) -> bool:
	for b in _radial:
		if b.has_point(p):
			return true
	return false


func _place_trees() -> void:
	var keep := 1.0 if quality >= 1 else 0.55
	var half_w := ROAD_W * 0.5
	# Between the fence and the street, and along the far sidewalk.
	_tree_row(_loop(ROAD_OFFSET - half_w - WALK_W - 2.2, ROAD_CORNER_R - 6.0), 9.0, 0.5, 0.85 * keep)
	_tree_row(_loop(ROAD_OFFSET + half_w + WALK_W + 2.0, ROAD_CORNER_R + 6.0), 7.5, 0.8, 0.9 * keep)
	# Park clumps in the gaps between buildings.
	var clumps := int(50 * keep)
	var placed := 0
	var tries := 0
	var r := Rect2(_centre - _half, _half * 2.0)
	while placed < clumps and tries < clumps * 20:
		tries += 1
		var p := Vector2(_rng.randf_range(r.position.x - 170.0, r.end.x + 170.0),
				_rng.randf_range(r.position.y - 150.0, r.end.y + 150.0))
		var probe := Rect2(p - Vector2(4, 4), Vector2(8, 8))
		if not _free(probe):
			continue
		var count := _rng.randi_range(2, 5)
		for k in count:
			var q := p + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-7, 7))
			if _free(Rect2(q - Vector2(2, 2), Vector2(4, 4))):
				if _rng.randf() < 0.25:
					_poplar(q, _rng.randf_range(0.8, 1.1))
				else:
					_broadleaf(q, _rng.randf_range(0.8, 1.25))
		_blocked.append(probe.grow(3.0))
		placed += 1


# --------------------------------------------------------------------------- far away
## City blocks between the lawn edge and the hills; the fog turns them into
## a hazy skyline.
func _build_skyline() -> void:
	var count := 150 if quality >= 1 else 90
	var inner := Rect2(_centre - _half, _half * 2.0).grow(LAWN_REACH + 40.0)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var a := _rng.randf() * TAU
		var dist := _rng.randf_range(300.0, 760.0)
		var c := _centre + Vector2(cos(a), sin(a)) * dist
		if inner.has_point(c):
			continue
		var tall := _rng.randf() < 0.3
		var floors := _rng.randi_range(9, 16) if tall else _rng.randi_range(3, 9)
		var cells := _rng.randi_range(5, 7) if tall else _rng.randi_range(8, 20)
		var deep := _rng.randi_range(4, 7) if tall else 4
		var col: Color = WALL_COLORS[_rng.randi() % WALL_COLORS.size()].darkened(_rng.randf_range(0.0, 0.15))
		if _add_block(c, cells, deep, floors, _rng.randf() < 0.5, col):
			placed += 1


## Low hills on the north-east horizon (towards the Chimgan range), then a
## lower ridge all around so the ground never ends in a hard line.
func _build_hills() -> void:
	var seg := 160
	for ring in 2:
		var dist := 880.0 if ring == 0 else 940.0
		var prev_top := Vector3.ZERO
		var prev_base := Vector3.ZERO
		var prev_n := Vector3.ZERO
		var phase := _rng.randf() * TAU
		for i in seg + 1:
			var a := TAU * i / seg
			var dir := Vector2(sin(a), -cos(a)) # a = 0 north, PI/2 east
			var ne := maxf(0.0, cos(a - PI * 0.3)) # strongest to the north-east
			var hgt := 12.0 + 8.0 * sin(a * 5.0 + phase) + 5.0 * sin(a * 13.0 + phase * 2.0)
			if ring == 1:
				# Jagged peaks: a sum of sharpened sines.
				var peaks := 0.0
				for f in [9.0, 17.0, 31.0]:
					peaks += (1.0 - absf(sin(a * f + phase * f))) / f * 9.0
				hgt += ne * ne * (45.0 + 60.0 * peaks + 25.0 * sin(a * 3.0 + phase))
			hgt = maxf(hgt, 4.0)
			var base := _v3(_centre + dir * dist, -2.0)
			var top := _v3(_centre + dir * (dist + hgt * 0.8), hgt)
			var n := (Vector3(-dir.x, 0.0, -dir.y) * 0.6 + Vector3.UP).normalized()
			if i > 0:
				var col := Color(0.42, 0.47, 0.4).lerp(Color(0.5, 0.54, 0.6), float(ring))
				var side := _side_of(_centre + dir * 50.0)
				var st := _sides[side]
				ProcGeo.tri(st, prev_base, base, top, prev_n, n, n, Color(col.r, col.g, col.b, 0.0),
						PackedVector2Array([Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1)]))
				ProcGeo.tri(st, prev_base, top, prev_top, prev_n, n, prev_n, Color(col.r, col.g, col.b, 0.0),
						PackedVector2Array([Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1)]))
			prev_top = top
			prev_base = base
			prev_n = n


# --------------------------------------------------------------------------- output
func _material_of(course: CourseBuilder, node_name: String, fallback: Color) -> Material:
	var mi := course.get_node_or_null(node_name) as MeshInstance3D
	if mi and mi.mesh and mi.mesh.get_surface_count() > 0:
		var m := mi.mesh.surface_get_material(0)
		if mi.material_override:
			m = mi.material_override
		if m:
			return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = fallback
	sm.roughness = 0.9
	return sm


func _add(st: SurfaceTool, material: Material, node_name: String, tangents: bool, shadows := false) -> void:
	st.index()
	if tangents:
		st.generate_tangents()
	st.set_material(material)
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _commit(course: CourseBuilder) -> void:
	var facade := ShaderMaterial.new()
	facade.shader = load("res://assets/shaders/facade.gdshader")
	_add(_ground, _material_of(course, "Lawn", Color(0.3, 0.45, 0.2)), "OuterGround", true)
	_add(_asphalt, _material_of(course, "Asphalt", Color(0.3, 0.3, 0.32)), "Street", true)
	_add(_walk, _material_of(course, "Pads", Color(0.7, 0.7, 0.68)), "Sidewalks", true)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.88, 0.88, 0.86)
	paint.roughness = 0.7
	_add(_paint, paint, "StreetLines", false)
	var names := ["North", "East", "South", "West"]
	for i in 4:
		_add(_sides[i], facade, "Buildings" + names[i], false)
		_add(_tree_sides[i], facade, "Trees" + names[i], false)
