class_name CameraRig
extends Node3D
## Three views of the car:
##   COCKPIT — driver's eye, free look by dragging (turn the head to check
##             the kerb or look over the shoulder when reversing);
##   CHASE   — behind and above, smoothed, swings behind when reversing;
##   TOP     — bird's-eye view for learning the manoeuvres.

signal mode_changed(mode: int)

enum Mode { COCKPIT, CHASE, TOP }

var car: Car
var mode: Mode = Mode.COCKPIT
var camera: Camera3D
var look_yaw := 0.0 # radians, head turn in the cockpit (+ = left)
var look_pitch := 0.0
var _chase_pos := Vector3.ZERO
var _chase_look := Vector3.ZERO
var _initialised := false
var _auto_look := true


func _init(p_car: Car) -> void:
	car = p_car
	name = "CameraRig"
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.near = 0.05
	camera.far = 900.0
	# Placed every frame from the car's interpolated transform already.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)


func set_mode(m: Mode) -> void:
	mode = m
	look_yaw = 0.0
	look_pitch = 0.0
	_initialised = false
	car.set_interior_audio(mode == Mode.COCKPIT)
	mode_changed.emit(mode)


func cycle() -> void:
	set_mode(((mode + 1) % 3) as Mode)


## Drag-to-look (pixels -> radians).
func look(delta_px: Vector2) -> void:
	_auto_look = false
	look_yaw = clampf(look_yaw - delta_px.x * 0.005, -2.4, 2.4)
	look_pitch = clampf(look_pitch - delta_px.y * 0.004, -0.6, 0.5)


func release_look() -> void:
	_auto_look = true


func _physics_process(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	if car == null:
		return
	var xf := car.get_global_transform_interpolated()
	match mode:
		Mode.COCKPIT:
			camera.fov = 72.0
			if _auto_look:
				# Glance towards where the car is going when reversing.
				var target_yaw := PI * 0.82 if car.get_gear() == -1 and car.get_forward_speed() < -0.2 else 0.0
				look_yaw = lerpf(look_yaw, target_yaw * 0.0, 1.0 - exp(-delta * 3.0))
				look_pitch = lerpf(look_pitch, 0.0, 1.0 - exp(-delta * 3.0))
			var head := Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch - 0.07)
			camera.global_transform = Transform3D(xf.basis * head, xf * car.cockpit_eye)
		Mode.CHASE:
			camera.fov = 65.0
			var back := xf.basis.z.normalized()
			var reversing := car.get_forward_speed() < -0.5
			var dir := -back if reversing else back
			var desired := xf.origin + dir * 7.2 + Vector3.UP * 2.9
			var look_at_pt := xf.origin + Vector3.UP * 0.9 - dir * 2.0
			if not _initialised:
				_chase_pos = desired
				_chase_look = look_at_pt
				_initialised = true
			var k := 1.0 - exp(-delta * 4.0)
			_chase_pos = _chase_pos.lerp(desired, k)
			_chase_look = _chase_look.lerp(look_at_pt, 1.0 - exp(-delta * 8.0))
			camera.global_position = _chase_pos
			camera.look_at(_chase_look, Vector3.UP)
		Mode.TOP:
			camera.fov = 55.0
			var fwd := -xf.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var pos := xf.origin + Vector3.UP * 17.0 - fwd * 4.0
			camera.global_position = pos
			camera.look_at(xf.origin + fwd * 1.5, fwd)
