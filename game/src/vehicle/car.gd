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
## door-mirror eye point (the left one is mirrored).
const MODELS := {
	"nexia2": {"path": "res://assets/cars/nexia2/nexia2.glb", "front": 2.18, "rear": 2.31, "half_width": 0.83,
			"mirror": Vector3(0.88, 0.93, -0.37)},
	"cobalt_at": {"path": "res://assets/cars/cobalt/cobalt.glb", "front": 2.22, "rear": 2.26, "half_width": 0.86,
			"mirror": Vector3(0.936, 1.043, -0.53)},
}
const BLINK_HZ := 1.5 # 90 flashes per minute (UNECE R48)
const LAYER_CAR := 2
const MASK_WORLD := 1 | 4

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
var mirror_eye := Vector3(0.88, 0.93, -0.37)
var _wheel_pivots: Array[Node3D] = []
var _wheel_spins: Array[Node3D] = []
var _steering: Node3D
var _lamps := {}
var _lamp_on := {}
var _lamp_off := {}
var _blink_t := 0.0
var _engine_sound: EngineSound
var _click: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _thump: AudioStreamPlayer3D
var _chime: AudioStreamPlayer
var _chime_t := 0.0
var _last_hit_time := -10.0
var _model_preset := ""


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
	# _ready() already built the default model when the car entered the tree.
	if model and _model_preset != preset_id:
		_clear_model()
		_load_model()


# --------------------------------------------------------------------------- model
func _clear_model() -> void:
	for n in [model, get_node_or_null("Hull")]:
		if n:
			remove_child(n)
			n.free()
	model = null
	_wheel_pivots.clear()
	_wheel_spins.clear()
	_steering = null
	_lamps.clear()
	_lamp_on.clear()
	_lamp_off.clear()


func _load_model() -> void:
	_model_preset = preset
	var spec: Dictionary = MODELS.get(preset, MODELS["nexia2"])
	body_front = spec["front"]
	body_rear = spec["rear"]
	body_half_width = spec["half_width"]
	mirror_eye = spec["mirror"]
	var scene: PackedScene = load(spec["path"])
	model = scene.instantiate()
	model.name = "Model"
	add_child(model)
	for corner in ["FL", "FR", "RL", "RR"]:
		var pivot := model.find_child("Wheel_" + corner, true, false) as Node3D
		var spin := model.find_child("Spin_" + corner, true, false) as Node3D
		_wheel_pivots.append(pivot)
		_wheel_spins.append(spin)
	_steering = model.find_child("SteeringWheel", true, false) as Node3D
	var pivot_node := model.find_child("SteeringPivot", true, false) as Node3D
	if pivot_node:
		cockpit_eye = pivot_node.position + Vector3(-0.01, 0.34, 0.52)
	for n in ["Lamp_Head", "Lamp_Fog", "Lamp_Tail", "Lamp_Brake", "Lamp_Reverse", "Lamp_TurnFL", "Lamp_TurnFR",
			"Lamp_TurnRL", "Lamp_TurnRR", "Lamp_TurnSL", "Lamp_TurnSR"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi:
			_lamps[n] = mi
	_apply_materials(model)
	_make_collision()
	_make_lamp_materials()
	_update_lamps(0.0)


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


func _pbr(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _apply_materials(root: Node) -> void:
	var paint := _pbr(Color(0.93, 0.94, 0.95), 0.05, 0.28)
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
		"interior": _pbr(Color(0.3, 0.3, 0.31), 0.0, 0.85),
		"interior_light": _pbr(Color(0.46, 0.46, 0.47), 0.0, 0.8),
		"mirror": _pbr(Color(0.9, 0.92, 0.94), 1.0, 0.02),
		"lamp_white": _pbr(Color(0.82, 0.84, 0.86), 0.3, 0.12),
		"plate": _pbr(Color(0.92, 0.93, 0.94), 0.0, 0.45),
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
		# Only the body, wheels and cabin cast shadows. Glass would block the sun
		# as if it were opaque, and lamps, hubs and mirror glass sit inside the
		# body's silhouette: each extra caster is drawn again in every shadow
		# split, which on phones costs more than it adds.
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _casts_shadow(m) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _casts_shadow(m: MeshInstance3D) -> bool:
	var n := String(m.name)
	return not (n.begins_with("Lamp_") or n.begins_with("Hub_") or n in ["Glass", "MirrorGlass"])


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
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
	for n in _lamps:
		var off: Material = _lamps[n].get_active_material(0)
		_lamp_off[n] = off
		if n.begins_with("Lamp_Turn"):
			_lamp_on[n] = _emissive(orange, 6.0)
		elif n == "Lamp_Tail":
			_lamp_on[n] = _emissive(red, 2.2)
		elif n == "Lamp_Brake":
			_lamp_on[n] = _emissive(red, 7.0)
		elif n == "Lamp_Reverse":
			_lamp_on[n] = _emissive(white, 4.0)
		else:
			_lamp_on[n] = _emissive(white, 5.0)
	# Brighter tail variant used while braking (the Nexia's tail and stop
	# lamps share one lens).
	if _lamps.has("Lamp_Tail"):
		_lamp_on["Lamp_Tail_brake"] = _emissive(red, 7.0)


func _set_lamp(n: String, on: bool, variant := "") -> void:
	if not _lamps.has(n):
		return
	var mi: MeshInstance3D = _lamps[n]
	var mat: Material = _lamp_on.get(n + variant, _lamp_on.get(n)) if on else _lamp_off[n]
	if mi.get_surface_override_material(0) != mat:
		mi.set_surface_override_material(0, mat)


# --------------------------------------------------------------------------- audio
func _setup_audio() -> void:
	_engine_sound = EngineSound.new()
	_engine_sound.name = "EngineSound"
	_engine_sound.bus = "Master"
	add_child(_engine_sound)
	_click = AudioStreamPlayer.new()
	_click.volume_db = -6.0
	add_child(_click)
	_squeal = AudioStreamPlayer.new()
	_squeal.stream = AudioSynth.squeal()
	_squeal.volume_db = -60.0
	add_child(_squeal)
	_squeal.play()
	_thump = AudioStreamPlayer3D.new()
	_thump.stream = AudioSynth.thump()
	add_child(_thump)
	_chime = AudioStreamPlayer.new()
	_chime.stream = AudioSynth.chime(1046.0, 784.0)
	_chime.volume_db = -8.0
	add_child(_chime)
	_apply_volumes()
	Settings.changed.connect(func(_k: String) -> void: _apply_volumes())


func _apply_volumes() -> void:
	var master := float(Settings.get_value("vol_master"))
	_engine_sound.volume_db = linear_to_db(maxf(master * float(Settings.get_value("vol_engine")), 0.0001))
	var fx := linear_to_db(maxf(master * float(Settings.get_value("vol_effects")), 0.0001))
	_click.volume_db = fx - 6.0
	_thump.volume_db = fx
	_chime.volume_db = fx - 8.0


func set_interior_audio(inside: bool) -> void:
	_engine_sound.interior = 1.0 if inside else 0.0


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
	_update_lamps(delta)
	_update_audio(delta)


func _update_wheels() -> void:
	for i in 4:
		var pivot := _wheel_pivots[i]
		if pivot == null:
			continue
		pivot.transform = Transform3D(Basis(Vector3.UP, -get_wheel_steer(i)), get_wheel_position(i))
		if _wheel_spins[i]:
			_wheel_spins[i].rotation.x = -fmod(get_wheel_rotation(i), TAU)
	if _steering:
		_steering.rotation.y = -deg_to_rad(steering_wheel)


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


func _update_audio(delta: float) -> void:
	_engine_sound.rpm = get_rpm()
	_engine_sound.load = get_throttle_opening()
	_engine_sound.running = is_engine_running()
	_engine_sound.cranking = is_engine_cranking()
	var slip := 0.0
	for i in 4:
		if get_wheel_contact(i):
			slip = maxf(slip, get_wheel_slip(i))
	var speed := absf(get_forward_speed())
	var squeal := clampf((slip - 1.1) * 1.2, 0.0, 1.0) * clampf(speed / 4.0, 0.0, 1.0)
	_squeal.volume_db = linear_to_db(maxf(squeal * 0.5, 0.0001))
	_squeal.pitch_scale = 0.9 + squeal * 0.25
	# Seat-belt reminder chime while moving unbelted, like the real car.
	if not seatbelt and ignition and speed > 2.0:
		_chime_t -= delta
		if _chime_t <= 0.0:
			_chime.play()
			_chime_t = 2.0
	else:
		_chime_t = 0.0


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
