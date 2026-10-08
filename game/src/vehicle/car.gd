class_name Car
extends AvtoVehicle
## The candidate's car: AvtoVehicle physics (C++) + model, lamps, cabin
## controls (indicators, hazards, seat belt, headlights) and sounds.
##
## Physics state lives in the native class; everything a learner sees or
## hears about the car is handled here.

signal obstacle_hit(body: Node, speed: float)
signal indicator_changed

enum Indicator { OFF, LEFT, RIGHT }

## Per-model data from the Blender builds (pipeline/blender/build_*.py):
## body origin midway between the axles on the ground; front/rear = distance
## to the bumpers, half_width = body side (without mirrors), mirror = right
## door-mirror eye point (the left one is mirrored). speed_max/rpm_max: the
## dashboard dials' full scale (km/h, rpm). paint: body colour (default white).
const MODELS := {
	"nexia2": {"turn_glow": [0.15, 0.07, 0.16], "path": "res://assets/cars/nexia2/nexia2.glb", "lod": "res://assets/cars/lod/nexia2_lod.glb", "front": 2.18, "rear": 2.31, "half_width": 0.83,
			"mirror": Vector3(0.88, 0.93, -0.37), "speed_max": 220.0, "rpm_max": 8000.0,
			# No plate surfaces in this model: [centre, outward normal] on the
			# flat of the bumper and in the boot-lid recess.
			"plates": [[Vector3(0.0, 0.41, -2.176), Vector3(0.0, 0.0, -1.0)],
					[Vector3(0.0, 0.82, 2.171), Vector3(0.0, 0.23, 0.973)]]},
	"cobalt_at": {"path": "res://assets/cars/cobalt/cobalt.glb", "lod": "res://assets/cars/lod/cobalt_lod.glb", "front": 2.22, "rear": 2.26, "half_width": 0.86,
			"mirror": Vector3(0.936, 1.043, -0.53), "speed_max": 220.0, "rpm_max": 7000.0,
			"smooth_lamps": ["Lamp_Head", "Lamp_TurnFL", "Lamp_TurnFR"], "lamp_shader": true},
	"gentra": {"path": "res://assets/cars/gentra/gentra.glb", "lod": "res://assets/cars/lod/gentra_lod.glb", "front": 2.22, "rear": 2.31, "half_width": 0.87,
			"mirror": Vector3(0.905, 1.019, -0.45), "speed_max": 240.0, "rpm_max": 8000.0,
			"paint": Color(0.012, 0.012, 0.014)},
	# Chevrolet Onix sedan (pipeline/blender/build_onix.py); "onix_at" is the
	# same car with the automatic gearbox (settings "onix_gearbox").
	"onix": {"path": "res://assets/cars/onix/onix.glb", "lod": "res://assets/cars/lod/onix_lod.glb", "front": 2.163, "rear": 2.322, "half_width": 0.877,
			"mirror": Vector3(0.946, 1.033, -0.572), "speed_max": 220.0, "rpm_max": 7000.0, "height": 1.49,
			# One-skin body: its inside (seen through the windows and the panel
			# gaps, and from the seats) is drawn as trim and headliner.
			"inner_shell": true,
			# Its 2.5k-triangle shadow proxy bulges out of the rear quarters:
			# kept inside, and the paint takes no shadow (no grey patches).
			"shadow_inset": 0.05},
	# GAZelle NEXT van (pipeline/blender/build_gazelle.py): the model's own
	# front plate, the rear one low on the back doors.
	"gazelle": {"path": "res://assets/cars/gazelle/gazelle.glb", "lod": "res://assets/cars/lod/gazelle_lod.glb", "front": 2.716, "rear": 3.352, "half_width": 1.03,
			"mirror": Vector3(1.157, 1.323, -1.626), "speed_max": 160.0, "rpm_max": 5000.0,
			"eye_offset": Vector3(-0.01, 0.42, 0.55), "paint": Color(0.95, 0.95, 0.96), "height": 2.65,
			"shadow_inset": 0.12, "shadow_van": true, "cockpit_shell": true, "turn_glow": [0.1, 0.06, 0.12],
			"plates": [[Vector3(0.012, 0.62, -2.712), Vector3(0.0, 0.0, -1.0)],
					[Vector3(0.0, 0.66, 3.356), Vector3(0.0, 0.0, 1.0)]]},
}
const WHITE_PAINT := Color(0.93, 0.94, 0.95)
## The cars on offer, in the order the menu shows them ("onix" stands for
## both Onix gearboxes, see Session.car_id()).
const IDS := ["nexia2", "cobalt_at", "gentra", "onix", "gazelle"]
## Vehicles of the truck categories (BC): the exam sends them through the
## trucks' lanes (the first 90° corridor, the wide box P1).
const TRUCKS := CourseData.TRUCKS
const GAUGE_SHADER := preload("res://assets/shaders/gauge.gdshader")
const HEADLAMP_SHADER := preload("res://assets/shaders/headlamp.gdshader")
const CAR_SHADOW_SHADER := preload("res://assets/shaders/car_shadow.gdshader")
## The brand's number plate (pipeline/make_car_plate.py), 520 x 112 mm.
const PLATE_TEX := preload("res://assets/cars/plate_avtosmart.png")
const PLATE_SIZE := Vector2(0.52, 0.112)
const BLINK_HZ := 1.5 # 90 flashes per minute (UNECE R48)
const LAYER_CAR := 2
## Render layer of the body shell the driver cannot see from the seat
## (BodyOuter, split off in pipeline/blender/refine_car.py): the cockpit
## camera leaves it out, mirrors and outside views draw it.
const LAYER_EXTERIOR := 1 << 17 # layer 18
const MASK_WORLD := 1 | 4
## Render layer of what only the driver's seat shows (the inside of the body
## shell, the glass seen from inside): the mirrors leave it out.
const LAYER_INTERIOR := 1 << 16 # layer 17
const LAMP_GLOW_SHADER := preload("res://assets/shaders/lamp_glow.gdshader")
const CABIN_SHELL_SHADER := preload("res://assets/shaders/cabin_shell.gdshader")

var indicator: Indicator = Indicator.OFF
var hazard := false
var seatbelt := false
var headlights := false
## True while the indicator/hazard lamps are lit in the blink cycle.
var blink_lit := false

var model: Node3D
var cockpit_eye := Vector3(-0.35, 1.13, 0.2)
var body_front := 2.18
var body_rear := 2.31
var body_half_width := 0.83
## Roof height (m); the chase camera rises and backs off for a taller vehicle.
var body_height := 1.45
var mirror_eye := Vector3(0.88, 0.93, -0.37)
var _wheel_pivots: Array[Node3D] = []
var _wheel_spins: Array[Node3D] = []
## A car on display (the menu): frozen, no suspension runs, so the wheels keep
## the model's own resting place instead of the physics' full-droop reset
## (which leaves them hanging ~9 cm into the floor).
var rest_pose := false
var _wheel_rest: Array[Transform3D] = []
var _steering: Node3D
var _gauge_speed: ShaderMaterial
var _gauge_rpm: ShaderMaterial
var _speed_max := 220.0
var _rpm_max := 8000.0
var _lamps := {}
## Every lamp lit, while the loading page still covers the screen: their
## materials get compiled then, not at the first brake or indicator.
var lamp_prewarm := false
var _lamp_on := {}
var _lamp_off := {}
## Red tail-lamp lenses that are part of the body shell ([mesh, surface]):
## on the Nexia they sit in front of Lamp_Tail, so they light with it.
var _tail_lenses: Array = []
var _tail_lens_off: Material
var _blink_t := 0.0
var _engine_sound: EngineSound
var _click: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _scrub: AudioStreamPlayer
## Smoothed 0..1 levels of the two tyre layers and the effects volume.
var _squeal_lvl := 0.0
var _scrub_lvl := 0.0
var _fx_gain := 1.0
var _interior := false
var _thump: AudioStreamPlayer3D
var _chime: AudioStreamPlayer
var _chime_t := 0.0
var _last_hit_time := -10.0
var _model_preset := ""
## Headlamp interiors drawn by headlamp.gdshader (the Cobalt's lens hulls).
var _lamp_shader := false
## Lit patches over the indicator lenses, by lamp name (MODELS[...]["turn_glow"]).
var _glows := {}
## Drawn only while the camera is in the driver's seat.
var _cockpit_only: Array[Node3D] = []
## The shadow drawn on the ground (car_shadow.gdshader), see _make_ground_shadow.
var _ground_shadow: MeshInstance3D
var _ground_mat: ShaderMaterial
## OpenGL: the ground shadow always, no shadow-map caster for the car.
var _simple_shadow := false
var _sun: DirectionalLight3D
var _sun_check := 0
## The body paint (one material per car): a new colour only changes it.
var _paint: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER_CAR
	collision_mask = MASK_WORLD
	wheel_collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)
	_load_model()
	_setup_audio()


func configure(preset_id: String) -> void:
	preset = preset_id
	auto_clutch = bool(Settings.get_value("auto_clutch"))
	# _ready() already built the default model when the car entered the tree;
	# a preset on the same model (the Onix's two gearboxes) keeps it.
	if model and Car.spec_for(_model_preset)["path"] != Car.spec_for(preset_id)["path"]:
		_clear_model()
		_load_model()
	else:
		refresh_paint()


# --------------------------------------------------------------------------- model
func _clear_model() -> void:
	for n in [model, get_node_or_null("Hull")]:
		if n:
			remove_child(n)
			n.free()
	model = null
	_wheel_pivots.clear()
	_wheel_rest.clear()
	_wheel_spins.clear()
	_steering = null
	_gauge_speed = null
	_gauge_rpm = null
	_lamps.clear()
	_tail_lenses.clear()
	_lamp_on.clear()
	_lamp_off.clear()
	_glows.clear()
	_cockpit_only.clear()
	if _ground_shadow:
		_ground_shadow.free()
		_ground_shadow = null


func _load_model() -> void:
	_model_preset = preset
	var spec: Dictionary = Car.spec_for(preset)
	body_front = spec["front"]
	body_rear = spec["rear"]
	body_half_width = spec["half_width"]
	body_height = spec.get("height", 1.45)
	mirror_eye = spec["mirror"]
	var scene: PackedScene = load(spec["path"])
	model = scene.instantiate()
	model.name = "Model"
	add_child(model)
	for corner in ["FL", "FR", "RL", "RR"]:
		var pivot := model.find_child("Wheel_" + corner, true, false) as Node3D
		var spin := model.find_child("Spin_" + corner, true, false) as Node3D
		_wheel_pivots.append(pivot)
		_wheel_rest.append(pivot.transform if pivot else Transform3D())
		_wheel_spins.append(spin)
	_steering = model.find_child("SteeringWheel", true, false) as Node3D
	var pivot_node := model.find_child("SteeringPivot", true, false) as Node3D
	if pivot_node:
		# Eye above and behind the steering wheel (a van's driver sits higher
		# over a flatter wheel: MODELS[...]["eye_offset"]).
		cockpit_eye = pivot_node.position + spec.get("eye_offset", Vector3(-0.01, 0.34, 0.52))
	for n in ["Lamp_Head", "Lamp_Fog", "Lamp_Tail", "Lamp_Brake", "Lamp_Reverse", "Lamp_TurnFL", "Lamp_TurnFR",
			"Lamp_TurnRL", "Lamp_TurnRR", "Lamp_TurnSL", "Lamp_TurnSR"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi:
			_lamps[n] = mi
	_paint = _apply_materials(model, spec.get("paint", WHITE_PAINT), not spec.has("shadow_inset"))
	refresh_paint()
	# The player's car stays near the camera: its automatic LODs (switched
	# early on phones, EnvironmentSetup.apply_viewport) fold the smooth body
	# into visible creases in the paint's highlights.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).lod_bias = 4.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.name.begins_with("Lamp_"):
			continue
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src and src.resource_name == "lamp_red":
				_tail_lenses.append([m, s])
				_tail_lens_off = m.get_surface_override_material(s)
	Car.smooth_lamps(_lamps, spec.get("smooth_lamps", []))
	_lamp_shader = spec.get("lamp_shader", false)
	Car.add_plates(model, spec)
	var outer := model.find_child("BodyOuter", true, false) as VisualInstance3D
	if outer and spec.get("cockpit_shell", false):
		_make_cockpit_shell(outer as MeshInstance3D)
	elif outer:
		outer.layers = LAYER_EXTERIOR
	if spec.get("inner_shell", false):
		_make_inner_shell()
	_make_gauges(spec)
	_make_collision()
	_simple_shadow = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if not _simple_shadow:
		_add_shadow_proxy(spec)
	_make_ground_shadow(spec)
	_make_lamp_materials()
	_make_turn_glows(spec)
	_update_lamps(0.0)
	set_interior_audio(_interior)


## A van's cab has no door cards or headliner of its own: from the seat the
## body shell stays in view (bonnet, mirrors) and its inside is drawn as trim
## panels, overhead as the headliner; the glass seen from inside is clearer
## than from outside (it would read as a milky sheet at a grazing angle).
func _make_cockpit_shell(outer: MeshInstance3D) -> void:
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = CABIN_SHELL_SHADER
	# Both parts of the shell: the doors are in the inner one.
	for part: MeshInstance3D in [outer, model.find_child("Body", true, false) as MeshInstance3D]:
		if part == null:
			continue
		var shell := MeshInstance3D.new()
		shell.name = "CabinShell"
		shell.mesh = part.mesh
		shell.material_override = shell_mat
		shell.transform = part.transform
		part.get_parent().add_child(shell)
		_cockpit_only.append(shell)
	var glass := model.find_child("Glass", true, false) as MeshInstance3D
	if glass:
		glass.layers = LAYER_EXTERIOR
		var clear := Car._pbr(Color(0.05, 0.07, 0.08, 0.14), 0.0, 0.05)
		clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		clear.cull_mode = BaseMaterial3D.CULL_DISABLED
		clear.metallic_specular = 0.25
		var inside := MeshInstance3D.new()
		inside.name = "GlassInside"
		inside.mesh = glass.mesh
		inside.material_override = clear
		inside.transform = glass.transform
		glass.get_parent().add_child(inside)
		_cockpit_only.append(inside)
	for n in _cockpit_only:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(n as VisualInstance3D).layers = LAYER_INTERIOR


## A body made of one skin (its source was drawn two-sided) shows nothing
## where the inside should be: the floor and the far doors through the
## windows, the inside of the panels through their gaps. Its back faces are
## drawn as the cabin trim (cabin_shell.gdshader), in every view: the same
## meshes once more, no new triangles, and only the back faces that show
## reach the fragment shader.
func _make_inner_shell() -> void:
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = CABIN_SHELL_SHADER
	for part_name in ["BodyOuter", "Body"]:
		var part := model.find_child(part_name, true, false) as MeshInstance3D
		if part == null:
			continue
		var shell := MeshInstance3D.new()
		shell.name = part_name + "Inner"
		shell.mesh = part.mesh
		shell.material_override = shell_mat
		shell.transform = part.transform
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.lod_bias = part.lod_bias
		part.get_parent().add_child(shell)


## The indicator bulbs sit deep behind their lenses and show as a dot when
## lit: a soft amber patch over each lens (lamp_glow.gdshader) makes it read
## as a lit indicator, seen from the directions the lamp shines.
## MODELS[...]["turn_glow"] = [front, side, rear] patch sizes in metres.
func _make_turn_glows(spec: Dictionary) -> void:
	var sizes: Array = spec.get("turn_glow", [])
	if sizes.is_empty():
		return
	for n in _lamps:
		if not n.begins_with("Lamp_Turn"):
			continue
		var kind := String(n).substr(9, 1) # F, R or S
		var side := -1.0 if String(n).ends_with("L") else 1.0
		var mi: MeshInstance3D = _lamps[n]
		var centre := Car.chain_to(mi, model) * mi.mesh.get_aabb().get_center()
		var facing := Vector3(side, 0.0, 0.0)
		var size: float = sizes[1]
		if kind == "F":
			facing = Vector3(side * 0.6, 0.0, -1.0).normalized()
			size = sizes[0]
		elif kind == "R":
			facing = Vector3(side * 0.5, 0.0, 1.0).normalized()
			size = sizes[2]
		var mat := ShaderMaterial.new()
		mat.shader = LAMP_GLOW_SHADER
		mat.set_shader_parameter("facing", facing)
		mat.set_shader_parameter("pull", 0.06 if kind == "S" else 0.1)
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			# No 2x ceiling on OpenGL (see _make_lamp_materials): amber, not yellow-white.
			mat.set_shader_parameter("color", Color(1.0, 0.45, 0.02))
			mat.set_shader_parameter("energy", 0.75)
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		var glow := MeshInstance3D.new()
		glow.name = n + "_Glow"
		glow.mesh = quad
		glow.material_override = mat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.layers = LAYER_EXTERIOR
		glow.position = centre
		glow.visible = false
		# Billboarded in the shader: the culling box must cover any turn.
		glow.custom_aabb = AABB(Vector3.ONE * -size, Vector3.ONE * size * 2.0)
		model.add_child(glow)
		_glows[n] = glow


## The Cobalt's headlamp lenses are the flat-shaded front of a convex hull
## (pipeline/blender/refine_car.py), split into the lamp and its indicator
## end: each long facet (and each piece) caught the light on its own, a grey
## patchwork. Per side, all the pieces get one smooth, gently domed normal
## field (the area-weighted average normal, bent outwards from the lamp's
## centre), so the lamp reads as one curved clear lens over a chrome
## reflector; the projector disc becomes a dark glass lens.
const LAMP_DOME := 2.2 # how strongly the normals fan out, per metre from the centre


static func smooth_lamps(lamps: Dictionary, names: Array) -> void:
	var mis: Array[MeshInstance3D] = []
	for n in names:
		if lamps.has(n):
			mis.append(lamps[n])
	# Per side (-1 / +1): vertex sum and count, area-weighted normal sum.
	var stats := {-1: [Vector3.ZERO, 0, Vector3.ZERO], 1: [Vector3.ZERO, 0, Vector3.ZERO]}
	for mi in mis:
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := idx.size() if not idx.is_empty() else verts.size()
		for t in range(0, count - 2, 3):
			var a := verts[idx[t] if not idx.is_empty() else t]
			var b := verts[idx[t + 1] if not idx.is_empty() else t + 1]
			var c := verts[idx[t + 2] if not idx.is_empty() else t + 2]
			var side := 1 if (a + b + c).x > 0.0 else -1
			stats[side][2] -= (b - a).cross(c - a) # clockwise front faces: the cross points inward
		for v in verts:
			var side := 1 if v.x > 0.0 else -1
			stats[side][0] += v
			stats[side][1] += 1
	for mi in mis:
		var src := mi.mesh
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			if s == 0:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals := PackedVector3Array()
				normals.resize(verts.size())
				for i in verts.size():
					var st: Array = stats[1 if verts[i].x > 0.0 else -1]
					var centre: Vector3 = st[0] / maxf(float(st[1]), 1.0)
					var avg: Vector3 = (st[2] as Vector3).normalized()
					normals[i] = (avg + (verts[i] - centre) * LAMP_DOME).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, src.surface_get_material(s))
		var overrides: Array[Material] = []
		for s in src.get_surface_count():
			overrides.append(mi.get_surface_override_material(s))
		mi.mesh = out
		for s in overrides.size():
			mi.set_surface_override_material(s, overrides[s])
		if out.get_surface_count() > 1:
			mi.set_surface_override_material(1, _pbr(Color(0.1, 0.11, 0.13), 0.85, 0.05))


## "AVTOSMART" number plates over the model's own ones (the "plate"
## surfaces: their outline, facing and the embossed characters, which the
## new plate covers), or at the spots listed in the model spec.
static func add_plates(model: Node3D, spec: Dictionary) -> void:
	var plates: Array = [] # [centre, normal, size]
	if spec.has("plates"):
		for pl in spec["plates"]:
			plates.append([pl[0], (pl[1] as Vector3).normalized(), PLATE_SIZE])
	else:
		# Per end of the car (-z front, +z rear): bounds, normal, points.
		var acc := {-1: [Vector3.INF, -Vector3.INF, Vector3.ZERO, []], 1: [Vector3.INF, -Vector3.INF, Vector3.ZERO, []]}
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var xf := Car.chain_to(m, model)
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s)
				if src == null or src.resource_name != "plate":
					continue
				var arrays := m.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in verts.size():
					var v := xf * verts[i]
					var a: Array = acc[1 if v.z > 0.0 else -1]
					a[0] = (a[0] as Vector3).min(v)
					a[1] = (a[1] as Vector3).max(v)
					if i < normals.size():
						a[2] += xf.basis * normals[i]
					(a[3] as Array).append(v)
		for side in [-1, 1]:
			var a: Array = acc[side]
			if (a[3] as Array).size() < 4:
				continue
			var n := (a[2] as Vector3)
			n = Vector3(0.0, n.y, n.z).normalized() if n.length() > 0.01 else Vector3(0, 0, side)
			if signf(n.z) != side:
				n = Vector3(0, 0, side)
			var lo: Vector3 = a[0]
			var hi: Vector3 = a[1]
			var centre := (lo + hi) * 0.5
			# In front of the frontmost point (the characters stand proud).
			var front := -INF
			for v in a[3]:
				front = maxf(front, (v - centre).dot(n))
			var tilt := absf(n.y)
			var height := (hi.y - lo.y) / maxf(sqrt(1.0 - tilt * tilt), 0.3)
			plates.append([centre + n * front, n, Vector2(hi.x - lo.x, height)])
	if plates.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PLATE_TEX
	mat.roughness = 0.42
	mat.metallic_specular = 0.6
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for pl in plates:
		var n: Vector3 = pl[1]
		var qm := QuadMesh.new()
		qm.size = pl[2]
		qm.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Plate"
		mi.mesh = qm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# QuadMesh faces +z: turn +z onto the plate's outward normal.
		var z := n
		var x := Vector3.UP.cross(z).normalized()
		var y := z.cross(x)
		mi.transform = Transform3D(Basis(x, y, z), (pl[0] as Vector3) + n * 0.004)
		model.add_child(mi)


func _chain_to_model(n: Node) -> Transform3D:
	return Car.chain_to(n, model)


## Transform of `n` relative to its ancestor `top`.
static func chain_to(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != top and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## The car's shadow drawn on the ground by car_shadow.gdshader: on OpenGL
## the shadow maps drew it speckled with light and stair-stepped at the
## edges, so there it replaces the shadow proxy; elsewhere it shows while the
## sun casts no shadows (low quality, shadows off), so the car never floats.
## The boxes come from the model's size: every sedan's shadow is alike.
func _make_ground_shadow(spec: Dictionary) -> void:
	var hw: float = spec["half_width"]
	var front: float = spec["front"]
	var rear: float = spec["rear"]
	var roof: float = spec.get("height", 0.0)
	if roof <= 0.0:
		roof = 1.44
		for n in ["BodyOuter", "Body"]:
			var mi := model.find_child(n, true, false) as MeshInstance3D
			if mi and mi.mesh:
				roof = (Car.chain_to(mi, self) * mi.mesh.get_aabb()).end.y
				break
	var cz := (rear - front) * 0.5
	var hl := (front + rear) * 0.5
	var body := Vector4(0.0, cz, hw, hl)
	# A sedan's cabin: narrower, about two fifths of the length, set back;
	# a van is one tall box.
	var cabin := Vector4(0.0, cz + 0.25, hw * 0.8, hl * 0.42)
	var belt := roof * 0.63
	if spec.get("shadow_van", false):
		cabin = Vector4(0.0, cz + 0.15, hw * 0.96, hl * 0.93)
		belt = 0.0
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = CAR_SHADOW_SHADER
	# Over the road paint (CourseBuilder.PAINT_Y on the pads) and drawn after
	# the painted guides (RouteGuide, priority 2).
	_ground_mat.render_priority = 3
	_ground_mat.set_shader_parameter("body", body)
	_ground_mat.set_shader_parameter("cabin", cabin)
	_ground_mat.set_shader_parameter("heights", Vector2(belt, roof))
	var plane := PlaneMesh.new()
	# Room for the shadow cast sideways and lengthwise by the sun.
	plane.size = Vector2(hw * 2.0 + roof * 2.4, hl * 2.0 + roof * 2.4)
	plane.material = _ground_mat
	_ground_shadow = MeshInstance3D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.mesh = plane
	_ground_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_shadow.top_level = true
	_ground_shadow.visible = _simple_shadow
	add_child(_ground_shadow)
	_sun_check = 0


## The ground shadow follows the road under the wheels (suspension, slopes)
## and turns with the car; the sun's offset is passed in the car's frame.
func _update_ground_shadow() -> void:
	if _ground_shadow == null:
		return
	_sun_check -= 1
	if _sun_check <= 0:
		_sun_check = 30
		if _sun == null or not is_instance_valid(_sun):
			_sun = get_tree().current_scene.find_child("Sun", true, false) as DirectionalLight3D 					if get_tree().current_scene else null
		_ground_shadow.visible = _simple_shadow or _sun == null or not _sun.shadow_enabled
	if not _ground_shadow.visible:
		return
	var xf := global_transform
	var up := xf.basis.y
	var origin := xf.origin
	if not rest_pose and not freeze:
		var pts: Array[Vector3] = []
		for i in 4:
			if get_wheel_contact(i):
				pts.append(get_wheel_ground_point(i))
		if pts.size() == 4:
			# Wheels 0/1 front, 2/3 rear: the diagonals span the road plane.
			var n := (pts[3] - pts[0]).cross(pts[2] - pts[1]).normalized()
			if n.dot(up) < 0.0:
				n = -n
			var mid := (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
			up = n
			origin = xf.origin - n * n.dot(xf.origin - mid)
	var fwd := (xf.basis.z - up * up.dot(xf.basis.z)).normalized()
	var b := Basis(up.cross(fwd), up, fwd)
	_ground_shadow.global_transform = Transform3D(b, origin + up * 0.07)
	var l := -Basis.from_euler(EnvironmentSetup.SUN_ROTATION).z
	if _sun and is_instance_valid(_sun):
		l = -_sun.global_basis.z
	var ll := b.inverse() * l
	if ll.y < -0.05:
		_ground_mat.set_shader_parameter("sun_step", Vector2(ll.x, ll.z) / -ll.y)


## Invisible 2.5k-triangle copy of the car that only casts the shadow.
func _add_shadow_proxy(spec: Dictionary) -> void:
	if not spec.has("lod") or not ResourceLoader.exists(spec["lod"]):
		return
	var src := (load(spec["lod"]) as PackedScene).instantiate()
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var proxy := MeshInstance3D.new()
		proxy.name = "ShadowProxy"
		proxy.mesh = m.mesh
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var t := Transform3D()
		var n: Node = m
		while n != src and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		# A little inside the real body: where the two surfaces crossed, the
		# body shadowed itself in speckles (bonnet, doors).
		# A van's long flat sides need more: its simplified hull bulges out of
		# them by several centimetres (MODELS[...]["shadow_inset"], metres).
		var box := m.mesh.get_aabb()
		var c := box.get_center()
		var k := Vector3.ONE * 0.96
		if spec.has("shadow_inset"):
			var half := box.size * 0.5
			var d: float = spec["shadow_inset"]
			k = Vector3((half.x - d) / half.x, (half.y - d) / half.y, (half.z - d) / half.z)
		proxy.transform = t * Transform3D(Basis().scaled(k), c * (Vector3.ONE - k))
		model.add_child(proxy)
	src.free()


func _make_collision() -> void:
	var hull := model.find_child("CollisionHull", true, false) as MeshInstance3D
	var cs := CollisionShape3D.new()
	cs.name = "Hull"
	if hull and hull.mesh:
		var shape := hull.mesh.create_convex_shape(true, true)
		cs.shape = shape
		cs.transform = hull.transform
		hull.queue_free()
	else:
		var b := BoxShape3D.new()
		b.size = Vector3(1.65, 0.9, 4.4)
		cs.shape = b
		cs.position = Vector3(0, 0.75, 0)
	add_child(cs)


static func _pbr(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Cabin surfaces skip the sun's shadow maps: seen from the driver's seat the
## roof shadow falls on them as big jagged steps. Their dark albedo stands in
## for the shade under the roof instead.
static func _cabin(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := _pbr(color, metallic, roughness)
	m.disable_receive_shadows = true
	return m


## The game's PBR set on the model's semantic materials (also for the other
## participants' cars, TrafficCars).
## `paint_shadows` false: the paint takes no shadows (a van's long flat
## sides caught its own simplified shadow caster in patches).
## The model spec of a preset (the automatic Onix uses the Onix's).
static func spec_for(preset_id: String) -> Dictionary:
	return MODELS.get(CarPaint.base_id(preset_id), MODELS["nexia2"])


## Puts the colour chosen for this car (CarPaint) on the body paint.
func refresh_paint() -> void:
	var e := CarPaint.entry(CarPaint.key_for(preset))
	if _paint == null or e.is_empty():
		return
	Car.set_paint(_paint, e[2], e[3], e[4])


static func set_paint(paint: StandardMaterial3D, colour: Color, metallic: float, roughness: float) -> void:
	paint.albedo_color = colour
	paint.metallic = metallic
	paint.roughness = roughness


## Returns the body paint material.
static func _apply_materials(root: Node, paint_color: Color, paint_shadows := true) -> StandardMaterial3D:
	# A dark paint needs a smoother top coat to read as paint, not plastic.
	var dark := paint_color.get_luminance() < 0.2
	var paint := _pbr(paint_color, 0.05, 0.2 if dark else 0.28)
	paint.disable_receive_shadows = not paint_shadows
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.9
	paint.clearcoat_roughness = 0.08
	var window := _pbr(Color(0.03, 0.05, 0.06, 0.42), 0.2, 0.04)
	window.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	window.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp_glass := _pbr(Color(0.9, 0.92, 0.95, 0.22), 0.0, 0.03)
	lamp_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var table := {
		"paint": paint,
		"trim_black": _pbr(Color(0.035, 0.035, 0.038), 0.0, 0.55),
		"rim": _pbr(Color(0.78, 0.79, 0.8), 0.85, 0.28),
		"rubber": _pbr(Color(0.045, 0.045, 0.048), 0.0, 0.88),
		"metal": _pbr(Color(0.6, 0.61, 0.62), 0.7, 0.4),
		"brake_disc": _pbr(Color(0.42, 0.4, 0.38), 0.8, 0.45),
		"chrome": _pbr(Color(0.86, 0.87, 0.88), 1.0, 0.12),
		"window": window,
		"lamp_glass": lamp_glass,
		"lamp_orange": _pbr(Color(0.75, 0.33, 0.02), 0.0, 0.25),
		"lamp_red": _pbr(Color(0.42, 0.03, 0.03), 0.0, 0.2),
		"interior": _cabin(Color(0.13, 0.13, 0.135), 0.85),
		"interior_light": _cabin(Color(0.22, 0.22, 0.225), 0.8),
		"interior_black": _cabin(Color(0.03, 0.03, 0.032), 0.6),
		"dash": _cabin(Color(0.06, 0.06, 0.065), 0.8),
		"dash_panel": _cabin(Color(0.012, 0.012, 0.014), 0.3),
		"dash_trim": _cabin(Color(0.1, 0.1, 0.11), 0.5),
		"mirror": _pbr(Color(0.9, 0.92, 0.94), 1.0, 0.02),
		"lamp_white": _pbr(Color(0.82, 0.84, 0.86), 0.3, 0.12),
		"headlamp": _pbr(Color(0.09, 0.095, 0.1), 0.3, 0.4),
		"headlamp_lens": _pbr(Color(0.8, 0.82, 0.86), 1.0, 0.15),
		"plate": _pbr(Color(0.92, 0.93, 0.94), 0.0, 0.45),
		"headliner": _cabin(Color(0.46, 0.45, 0.43), 0.9),
	}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			var key := src.resource_name if src else ""
			if table.has(key):
				m.set_surface_override_material(s, table[key])
		# The shadow comes from the light proxy (see _add_shadow_proxy): the
		# full model would cost ~100k triangles again in the shadow pass.
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return paint


func _make_gauges(spec: Dictionary) -> void:
	_speed_max = spec.get("speed_max", 220.0)
	_rpm_max = spec.get("rpm_max", 8000.0)
	_gauge_speed = _gauge("GaugeSpeed", int(_speed_max / 20.0) + 1, 2.0)
	var red := get_redline_rpm()
	_gauge_rpm = _gauge("GaugeRpm", int(_rpm_max / 1000.0) + 1, red / _rpm_max if red > 0.0 else 1.0)


func _gauge(node_name: String, majors: int, red_from: float) -> ShaderMaterial:
	var mi := model.find_child(node_name, true, false) as MeshInstance3D
	if mi == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = GAUGE_SHADER
	m.set_shader_parameter("majors", majors)
	m.set_shader_parameter("red_from", red_from)
	mi.set_surface_override_material(0, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m


func _make_lamp_materials() -> void:
	var orange := Color(1.0, 0.52, 0.05)
	var red := Color(1.0, 0.06, 0.04)
	var white := Color(1.0, 0.97, 0.9)
	# Energies for the Mobile renderer, whose colour buffer tops out near 2:
	# a 7x red reads as deep red there. OpenGL keeps the full value and the
	# tone mapper lifts its green and blue into a pale pinkish white, so there
	# the colours are purer and the energies about a third.
	var k := 1.0
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		k = 0.36
		orange = Color(1.0, 0.42, 0.02)
		red = Color(1.0, 0.012, 0.008)
	var drawn := Car.headlamp_materials(_lamps, model) if _lamp_shader else {}
	for n in _lamps:
		if drawn.has(n):
			_lamp_off[n] = drawn[n][0]
			_lamp_on[n] = drawn[n][1]
			continue
		var off: Material = _lamps[n].get_active_material(0)
		_lamp_off[n] = off
		if n.begins_with("Lamp_Turn"):
			_lamp_on[n] = _emissive(orange, 6.0 * k)
		elif n == "Lamp_Tail":
			_lamp_on[n] = _emissive(red, 2.2 * maxf(k, 0.6))
		elif n == "Lamp_Brake":
			_lamp_on[n] = _emissive(red, 7.0 * k)
		elif n == "Lamp_Reverse":
			_lamp_on[n] = _emissive(white, 4.0 * maxf(k, 0.5))
		else:
			_lamp_on[n] = _emissive(white, 5.0 * maxf(k, 0.5))
	# Brighter tail variant used while braking (the Nexia's tail and stop
	# lamps share one lens).
	if _lamps.has("Lamp_Tail"):
		_lamp_on["Lamp_Tail_brake"] = _emissive(red, 7.0 * k)


## Off / on materials of the front lamps painted by headlamp.gdshader, with
## the lamp's extent (inner edge to the end of the indicator piece) measured
## from the right-hand meshes; the shader mirrors it for the left.
static func headlamp_materials(lamps: Dictionary, model: Node3D) -> Dictionary:
	var b := Vector4(INF, -INF, INF, -INF)
	for n in ["Lamp_Head", "Lamp_TurnFR"]:
		if not lamps.has(n):
			continue
		var mi: MeshInstance3D = lamps[n]
		var xf := Car.chain_to(mi, model)
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v0 in verts:
			var v := xf * v0
			if v.x <= 0.0:
				continue
			b = Vector4(minf(b.x, v.x), maxf(b.y, v.x), minf(b.z, v.y), maxf(b.w, v.y))
	if b.x == INF:
		return {}
	var out := {}
	for n in ["Lamp_Head", "Lamp_TurnFL", "Lamp_TurnFR"]:
		if not lamps.has(n):
			continue
		var pair := []
		for on in [0.0, 1.0]:
			var m := ShaderMaterial.new()
			m.shader = HEADLAMP_SHADER
			m.set_shader_parameter("bounds", b)
			m.set_shader_parameter("part", 0 if n == "Lamp_Head" else 1)
			m.set_shader_parameter("lit", on)
			pair.append(m)
		out[n] = pair
	return out


func _set_lamp(n: String, on: bool, variant := "") -> void:
	if not _lamps.has(n):
		return
	var mi: MeshInstance3D = _lamps[n]
	if _glows.has(n):
		(_glows[n] as Node3D).visible = on
	var mat: Material = _lamp_on.get(n + variant, _lamp_on.get(n)) if on else _lamp_off[n]
	if mi.get_surface_override_material(0) != mat:
		mi.set_surface_override_material(0, mat)
		# The painted lamps: the old projector disc inside takes the same
		# material (it would show as a black spot through the lens).
		if _lamp_shader and mat is ShaderMaterial:
			for s in range(1, mi.mesh.get_surface_count()):
				mi.set_surface_override_material(s, mat)
		if _lamp_shader and n == "Lamp_Head":
			# The indicator end pieces carry part of the beam's reflectors.
			for tn in ["Lamp_TurnFL", "Lamp_TurnFR"]:
				for key in [tn, tn + "_on"]:
					var tm: Variant = _lamp_off.get(tn) if key == tn else _lamp_on.get(tn)
					if tm is ShaderMaterial:
						(tm as ShaderMaterial).set_shader_parameter("beam", 1.0 if on else 0.0)
	if n == "Lamp_Tail":
		for lens in _tail_lenses:
			(lens[0] as MeshInstance3D).set_surface_override_material(lens[1], mat if on else _tail_lens_off)


# --------------------------------------------------------------------------- audio
func _setup_audio() -> void:
	_engine_sound = EngineSound.new()
	_engine_sound.name = "EngineSound"
	_engine_sound.bus = "Master"
	if OS.has_feature("web"):
		# Mixed on the game's thread there: enough sound ready for a slow frame.
		_engine_sound.buffer_length = 0.25
	add_child(_engine_sound)
	_click = AudioStreamPlayer.new()
	_click.volume_db = -6.0
	add_child(_click)
	# Tyre layers loop for the whole drive and are faded in and out by volume
	# (see _set_loop): starting and stopping a player several times a second
	# as the slip flickers churns playbacks under the audio thread, and a
	# phone's audio thread crashed on it (SIGSEGV in AudioTrack).
	_squeal = AudioStreamPlayer.new()
	_squeal.stream = AudioSynth.squeal()
	_squeal.volume_db = -80.0
	add_child(_squeal)
	_squeal.play(randf() * _squeal.stream.get_length())
	_scrub = AudioStreamPlayer.new()
	_scrub.stream = AudioSynth.scrub()
	_scrub.volume_db = -80.0
	add_child(_scrub)
	_scrub.play(randf() * _scrub.stream.get_length())
	_thump = AudioStreamPlayer3D.new()
	_thump.stream = AudioSynth.thump()
	add_child(_thump)
	_chime = AudioStreamPlayer.new()
	_chime.stream = AudioSynth.chime(1046.0, 784.0)
	AudioSynth.relay_click(0.8) # the indicator's "off" click, made now, not at the first blink
	_chime.volume_db = -8.0
	add_child(_chime)
	_apply_volumes()
	Settings.changed.connect(func(_k: String) -> void: _apply_volumes())


func _apply_volumes() -> void:
	var master := float(Settings.get_value("vol_master"))
	_engine_sound.volume_db = linear_to_db(maxf(master * float(Settings.get_value("vol_engine")), 0.0001))
	_fx_gain = master * float(Settings.get_value("vol_effects"))
	var fx := linear_to_db(maxf(_fx_gain, 0.0001))
	_click.volume_db = fx - 6.0
	_thump.volume_db = fx
	_chime.volume_db = fx - 8.0


func set_interior_audio(inside: bool) -> void:
	if _engine_sound:
		_engine_sound.interior = 1.0 if inside else 0.0
	_interior = inside
	for n in _cockpit_only:
		n.visible = inside


# --------------------------------------------------------------------------- cabin controls
func set_indicator(dir: Indicator) -> void:
	if indicator == dir:
		return
	indicator = dir
	if indicator != Indicator.OFF or hazard:
		_blink_t = 0.0 # a fresh flash starts immediately
	indicator_changed.emit()
	_click.stream = AudioSynth.relay_click(1.0)
	_click.play()


func toggle_indicator(dir: Indicator) -> void:
	set_indicator(Indicator.OFF if indicator == dir else dir)


func set_hazard(on: bool) -> void:
	if hazard == on:
		return
	hazard = on
	_blink_t = 0.0
	indicator_changed.emit()
	_click.stream = AudioSynth.relay_click(1.0)
	_click.play()


func left_lit() -> bool:
	return blink_lit and (hazard or indicator == Indicator.LEFT)


func right_lit() -> bool:
	return blink_lit and (hazard or indicator == Indicator.RIGHT)


## Indicator lever position as the exam sees it (hazards count as both).
func signalling_left() -> bool:
	return hazard or indicator == Indicator.LEFT


func signalling_right() -> bool:
	return hazard or indicator == Indicator.RIGHT


# --------------------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_update_wheels()
	_update_ground_shadow()
	_update_lamps(delta)
	_update_audio(delta)


func _update_wheels() -> void:
	for i in 4:
		var pivot := _wheel_pivots[i]
		if pivot == null:
			continue
		if rest_pose:
			pivot.transform = _wheel_rest[i]
			continue
		pivot.transform = Transform3D(Basis(Vector3.UP, -get_wheel_steer(i)), get_wheel_position(i))
		if _wheel_spins[i]:
			_wheel_spins[i].rotation.x = -fmod(get_wheel_rotation(i), TAU)
	if _steering:
		_steering.rotation.y = -deg_to_rad(steering_wheel)
	if _gauge_speed:
		var kmh := absf(get_forward_speed()) * 3.6
		_gauge_speed.set_shader_parameter("value", clampf(kmh / _speed_max, 0.0, 1.0))
	if _gauge_rpm:
		_gauge_rpm.set_shader_parameter("value", clampf(get_rpm() / _rpm_max, 0.0, 1.0))


func _update_lamps(delta: float) -> void:
	var blinking := hazard or indicator != Indicator.OFF
	var was := blink_lit
	if blinking and (ignition or hazard):
		_blink_t += delta
		blink_lit = fmod(_blink_t * BLINK_HZ, 1.0) < 0.5
	else:
		_blink_t = 0.0
		blink_lit = false
	if blink_lit != was and blinking:
		_click.stream = AudioSynth.relay_click(1.0 if blink_lit else 0.8)
		_click.play()
	var l := left_lit()
	var r := right_lit()
	for n in ["Lamp_TurnFL", "Lamp_TurnRL", "Lamp_TurnSL"]:
		_set_lamp(n, l)
	for n in ["Lamp_TurnFR", "Lamp_TurnRR", "Lamp_TurnSR"]:
		_set_lamp(n, r)
	var braking := brake > 0.05 and ignition
	_set_lamp("Lamp_Brake", braking)
	_set_lamp("Lamp_Tail", braking or (headlights and ignition), "_brake" if braking else "")
	_set_lamp("Lamp_Head", headlights and ignition)
	var reversing := ignition and (get_gear() == -1)
	_set_lamp("Lamp_Reverse", reversing)
	if lamp_prewarm:
		for n in _lamps:
			_set_lamp(n, true, "_brake" if Engine.get_process_frames() % 2 == 0 else "")


func _update_audio(delta: float) -> void:
	_engine_sound.rpm = get_rpm()
	_engine_sound.load = get_throttle_opening()
	_engine_sound.running = is_engine_running()
	_engine_sound.cranking = is_engine_cranking()
	var speed := absf(get_forward_speed())
	_update_tyre_audio(delta, speed)
	# Seat-belt reminder chime while moving unbelted, like the real car.
	if not seatbelt and ignition and speed > 2.0:
		_chime_t -= delta
		if _chime_t <= 0.0:
			_chime.play()
			_chime_t = 2.0
	else:
		_chime_t = 0.0


## Tyre noise from how fast each contact patch rubs over the road. Two
## layers, like a real car:
## - squeal: the tonal scream of tyres sliding past their grip limit at speed
##   (a fast corner, a skid from 40 km/h);
## - scrub: the dull rasp of a locked or sliding tyre (a skid, the handbrake),
##   much quieter, and silent at parking speed.
## The normalised slip saturates at 3 as soon as a tyre lets go, so it cannot
## tell a slight slide from a locked wheel: the slide speed decides.
func _update_tyre_audio(delta: float, speed: float) -> void:
	var squeal := 0.0
	var scrub := 0.0
	var nominal_load := mass * 9.81 * 0.25
	for i in 4:
		if not get_wheel_contact(i):
			continue
		var s := get_wheel_slip(i)
		if s < 0.9:
			continue
		var slide := get_wheel_slide_speed(i)
		var load := clampf(get_wheel_load(i) / nominal_load, 0.0, 1.5)
		squeal += smoothstep(0.9, 1.5, s) * smoothstep(0.8, 4.0, slide) * load
		scrub += smoothstep(1.0, 2.5, s) * smoothstep(0.2, 5.0, slide) * load
	# Two wheels sliding is "full"; the scream needs real speed (fades in
	# from ~10 km/h, full above ~45 km/h).
	squeal = clampf(squeal * 0.5, 0.0, 1.0) * smoothstep(3.0, 12.0, speed)
	# Scrub is a real slide only (a skid, a locked wheel): at parking speed a
	# tyre on full lock is silent.
	scrub = clampf(scrub * 0.5, 0.0, 1.0) * smoothstep(1.5, 5.0, speed)
	# Fast attack, slower release: no clicks or stutter when slip flickers.
	# A non-finite level would stick forever (it feeds back through _follow).
	_squeal_lvl = _follow(_squeal_lvl, squeal if is_finite(squeal) else 0.0, delta)
	_scrub_lvl = _follow(_scrub_lvl, scrub if is_finite(scrub) else 0.0, delta)
	if not is_finite(_squeal_lvl):
		_squeal_lvl = 0.0
	if not is_finite(_scrub_lvl):
		_scrub_lvl = 0.0
	if not is_finite(speed):
		speed = 0.0
	var muffle := 0.5 if _interior else 1.0
	_set_loop(_squeal, _squeal_lvl * 0.32 * muffle, 0.94 + 0.1 * _squeal_lvl)
	_set_loop(_scrub, _scrub_lvl * 0.25 * muffle, 0.75 + clampf(speed / 20.0, 0.0, 0.45))


static func _follow(current: float, target: float, delta: float) -> float:
	var tau := 0.05 if target > current else 0.2
	return lerpf(current, target, 1.0 - exp(-delta / tau))


## The audio thread trusts these values: pitch_scale rejects <= 0 but lets a
## NaN through, and a NaN pitch sends the WAV mixer's read position off the
## end of the sample data (the SIGSEGV in AudioTrack seen on phones). Slip and
## load come straight from the tyre model, so anything non-finite is silence.
func _set_loop(p: AudioStreamPlayer, gain: float, pitch: float) -> void:
	var g := gain * _fx_gain
	if not (is_finite(g) and is_finite(pitch)):
		g = 0.0
		pitch = 1.0
	p.volume_db = linear_to_db(g) if g >= 0.003 else -80.0
	p.pitch_scale = clampf(pitch, 0.5, 2.0)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("obstacle"):
		return
	# Game time, not wall time: the debounce must not depend on the frame rate.
	var now := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	if now - _last_hit_time < 0.6:
		return
	_last_hit_time = now
	var speed := linear_velocity.length()
	_thump.volume_db = linear_to_db(clampf(speed / 6.0, 0.05, 1.0))
	_thump.play()
	obstacle_hit.emit(body, speed)
