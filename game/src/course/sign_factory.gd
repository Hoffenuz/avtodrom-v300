class_name SignFactory
extends RefCounted
## Road signs: galvanised pole + printed plate(s) from assets/signs/<code>.png.
## Plate faces are sampled from assets/signs/atlas.png (see
## pipeline/make_sign_atlas.py) so every plate shares one material and the
## merged course draws them all in one call; a code missing from the atlas
## falls back to its own texture.
##
## A sign is placed with the yaw of the traffic it addresses; the plate's
## printed face (local +Z) then looks at the oncoming driver.

const SIGN_DIR := "res://assets/signs/"
const ATLAS_JSON := "res://assets/signs/atlas.json"
const POLE_RADIUS := 0.035
const OBSTACLE_LAYER := 4

static var _shader: Shader
static var _pole_mat: StandardMaterial3D
static var _plate_mats := {}
static var _pole_mesh: CylinderMesh
static var _atlas_mat: ShaderMaterial
static var _atlas_rects: Dictionary
static var _quads := {}


static func _shader_material(tex: Texture2D) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://assets/shaders/sign.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("face_tex", tex)
	return m


## Atlas rect [u0, v0, u1, v1, aspect] of a sign face, or [] if it has none.
static func _atlas_rect(code: String) -> Array:
	if _atlas_rects.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
		_atlas_rects = parsed["rects"] if parsed is Dictionary else {"": []}
	return _atlas_rects.get(code, [])


static func _material_for(code: String) -> ShaderMaterial:
	if not _atlas_rect(code).is_empty():
		if _atlas_mat == null:
			_atlas_mat = _shader_material(load(SIGN_DIR + "atlas.png"))
		return _atlas_mat
	if not _plate_mats.has(code):
		_plate_mats[code] = _shader_material(load(SIGN_DIR + code + ".png"))
	return _plate_mats[code]


static func pole_material() -> StandardMaterial3D:
	if _pole_mat == null:
		_pole_mat = StandardMaterial3D.new()
		_pole_mat.albedo_color = Color(0.62, 0.64, 0.66)
		_pole_mat.metallic = 0.7
		_pole_mat.roughness = 0.45
	return _pole_mat


static func _aspect(code: String) -> float:
	var r := _atlas_rect(code)
	if not r.is_empty():
		return float(r[4])
	var tex: Texture2D = load(SIGN_DIR + code + ".png")
	if tex == null:
		return 1.0
	return float(tex.get_width()) / float(maxi(tex.get_height(), 1))


## Builds one sign. `size` is the plate's longer side in metres (0.7 = type II).
## `plates` lists the supplementary plates below it (7.x), and may go on with
## a second sign and its plates.
static func make(code: String, height: float, size: float, plates: Array) -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Sign_" + code.replace(".", "_")
	root.collision_layer = OBSTACLE_LAYER
	root.collision_mask = 0
	root.add_to_group("obstacle", true)

	var top := height + size * 0.5
	var pole := MeshInstance3D.new()
	if _pole_mesh == null:
		_pole_mesh = CylinderMesh.new()
		_pole_mesh.top_radius = POLE_RADIUS
		_pole_mesh.bottom_radius = POLE_RADIUS
		_pole_mesh.height = 1.0
		_pole_mesh.radial_segments = 8
		_pole_mesh.rings = 1
		_pole_mesh.material = pole_material()
	pole.mesh = _pole_mesh
	pole.scale = Vector3(1, top, 1)
	pole.position = Vector3(0, top * 0.5, 0)
	root.add_child(pole)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = POLE_RADIUS + 0.02
	cyl.height = top
	shape.shape = cyl
	shape.position = Vector3(0, top * 0.5, 0)
	root.add_child(shape)

	var y := height
	y = _add_plate(root, code, size, y) - 0.04
	# Supplementary plates (7.x) stack under the sign they belong to; another
	# code in the list is a second sign on the same pole, with its own plates.
	for p in plates:
		var c := str(p)
		if c.begins_with("7."):
			y = _add_plate(root, c, size, y - 0.02, true) - 0.04
		else:
			y = _add_plate(root, c, size, y - 0.06 - size * 0.5) - 0.04
	return root


## Adds a plate whose top edge sits at... centre at `y` for the main sign;
## returns the plate's bottom edge so supplementary plates stack below.
static func _add_plate(root: Node3D, code: String, size: float, y: float, below := false) -> float:
	var aspect := _aspect(code)
	var w := size if aspect >= 1.0 else size * aspect
	var h := size / aspect if aspect >= 1.0 else size
	if below:
		# Supplementary plates (7.x) are as wide as the main sign.
		w = size
		h = size / aspect
	var mi := MeshInstance3D.new()
	mi.mesh = _quad(code, w, h)
	mi.material_override = _material_for(code)
	var cy := y if not below else y - h * 0.5
	mi.position = Vector3(0, cy, POLE_RADIUS + 0.01)
	root.add_child(mi)
	return cy - h * 0.5


## A w x h plate facing +Z, with UVs on the code's atlas rect.
static func _quad(code: String, w: float, h: float) -> Mesh:
	var key := "%s|%.3f|%.3f" % [code, w, h]
	if _quads.has(key):
		return _quads[key]
	var r := _atlas_rect(code)
	var uv0 := Vector2(r[0], r[1]) if not r.is_empty() else Vector2.ZERO
	var uv1 := Vector2(r[2], r[3]) if not r.is_empty() else Vector2.ONE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	var corners := [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]
	for c: Vector2 in corners:
		st.set_uv(Vector2(lerpf(uv0.x, uv1.x, c.x + 0.5), lerpf(uv0.y, uv1.y, 0.5 - c.y)))
		st.add_vertex(Vector3(c.x * w, c.y * h, 0.0))
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(i)
	st.generate_tangents()
	var mesh := st.commit()
	_quads[key] = mesh
	return mesh
