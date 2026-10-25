class_name Weather
extends Node3D
## What the evening, night and rain looks (Settings "weather") add to the
## drive beyond the sky and sun (EnvironmentSetup): the street lamps' light
## on the ground, the car's headlamps on and throwing light, falling rain
## around the camera with its sound, and the wet road's grip. Everything here
## is drawn cheaply: no real lights but the one headlamp beam.

const POOL_SHADER := preload("res://assets/shaders/lamp_pool.gdshader")
const RAIN_SHADER := preload("res://assets/shaders/rain.gdshader")
## Grip of wet asphalt against dry (1.0).
const WET_GRIP := 0.78
## The lamp heads, as CourseBuilder._build_lamp_posts() places them.
const HEAD_HEIGHT := 8.78
const HEAD_REACH := 2.1
const POOL_RADIUS := 11.0
## The rain's layer: not in the mirrors (another full-screen pass each) nor
## in the results' map.
const LAYER_RAIN := 1 << 15 # layer 16

var look := "day"
var _rain: Array[MeshInstance3D] = []
var _sound: AudioStreamPlayer


func setup(p_look: String, data: CourseData, car: Car, quality: int) -> void:
	look = p_look
	if look == "day":
		return
	car.headlights = true
	if look == "night":
		car.enable_beam(5.0)
		_build_lamps(data, 0.8)
	elif look == "evening":
		car.enable_beam(1.6)
		_build_lamps(data, 0.18)
	elif look == "rain":
		car.set_surface_map(PackedByteArray(), 0, 0, Vector2.ZERO, 1.0,
				PackedFloat32Array([WET_GRIP]), PackedFloat32Array([1.0]))
		_build_rain(quality)


func _build_lamps(data: CourseData, strength: float) -> void:
	var posts: Array = data.raw.get("lamp_posts", [])
	if posts.is_empty():
		return
	var area := Rect2(data.fence[0], Vector2.ZERO)
	for p in data.fence:
		area = area.expand(p)
	var centre := area.get_center()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in posts:
		var pos := CourseData.v2(p)
		var dir := (centre - pos).normalized()
		var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
		var head := Vector3(pos.x, 0.0, pos.y) + basis * Vector3(0, 0, -HEAD_REACH)
		# The pool on the ground, a little off the pole towards the course.
		_quad(st, head + Vector3(0, 0.07, 0), basis, Vector2(POOL_RADIUS, POOL_RADIUS), Color(1, 1, 1, 0))
		# The lamp's glass, facing down, bright.
		_quad(st, head + Vector3(0, HEAD_HEIGHT, 0), basis, Vector2(0.16, 0.32), Color(1, 1, 1, 1))
	var mat := ShaderMaterial.new()
	mat.shader = POOL_SHADER
	mat.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.name = "LampLight"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A flat square, half-size [param half], in the plane y = at.y, turned by [param basis].
func _quad(st: SurfaceTool, at: Vector3, basis: Basis, half: Vector2, color: Color) -> void:
	var c := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k: Vector2 in c:
		st.set_color(color)
		st.set_uv((k + Vector2.ONE) * 0.5)
		st.add_vertex(at + basis * Vector3(k.x * half.x, 0, k.y * half.y))


func _build_rain(quality: int) -> void:
	# A near layer of big, fast streaks and (above the lowest quality) a far,
	# finer one. Each is one transparent pass over the screen.
	var layers := [[2.8, 7.0, 160.0, 4.0, 2.2, 0.26]]
	if quality >= 1:
		layers.append([7.0, 14.0, 300.0, 5.0, 1.5, 0.2])
	for l: Array in layers:
		var cyl := CylinderMesh.new()
		cyl.top_radius = l[0]
		cyl.bottom_radius = l[0]
		cyl.height = l[1]
		cyl.radial_segments = 24
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var mat := ShaderMaterial.new()
		mat.shader = RAIN_SHADER
		mat.set_shader_parameter("columns", l[2])
		mat.set_shader_parameter("rows", l[3])
		mat.set_shader_parameter("speed", l[4])
		mat.set_shader_parameter("tint", Color(0.8, 0.84, 0.9, l[5]))
		var mi := MeshInstance3D.new()
		mi.name = "Rain"
		mi.mesh = cyl
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER_RAIN
		mi.top_level = true # follows the camera's position, not its turn
		mi.extra_cull_margin = 16.0
		add_child(mi)
		_rain.append(mi)
	_sound = AudioStreamPlayer.new()
	_sound.stream = AudioSynth.rain()
	_sound.bus = "Master"
	add_child(_sound)
	_apply_volume()
	Settings.changed.connect(func(k: String) -> void:
		if k.begins_with("vol_"):
			_apply_volume())
	_sound.play()


func _apply_volume() -> void:
	var v := float(Settings.get_value("vol_master")) * float(Settings.get_value("vol_effects"))
	_sound.volume_db = linear_to_db(maxf(0.001, v * 0.5))


func _process(_dt: float) -> void:
	if _rain.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		for mi in _rain:
			mi.global_position = cam.global_position
