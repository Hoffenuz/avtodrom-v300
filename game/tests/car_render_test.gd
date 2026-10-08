extends Node
## Renders the exam car from outside and from the driver's seat and saves PNGs
## (needs a GPU, not --headless). Used to review the car model and cabin:
##   godot --path game res://tests/car_render_test.tscn -- <out_dir> [car preset] [brake|lamps]

var out_dir := "user://car_shots"
var world: Node3D
var car: Car
var cam: Camera3D
var shots: Array = []
var detail_mode := false
var idx := 0
var wait := 0
## "spin" mode: close-ups of the left and right wheels at several spin angles.
var spin_mode := false
var turn_mode := false
## "body" mode: the paint up close (rear quarters, the boot and plate) and
## views through the windows, where a one-sided body shows the far side.
var body_mode := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	world = Node3D.new()
	add_child(world)
	# Optional "q=N" anywhere in the arguments: the quality level (default 2).
	var q := 2
	for a in args:
		if a.begins_with("q="):
			q = int(a.substr(2))
	EnvironmentSetup.create(world, q)
	EnvironmentSetup.apply_viewport(get_viewport(), q)
	var builder := CourseBuilder.new()
	world.add_child(builder)
	builder.build(CourseData.get_default(), q)
	car = Car.new()
	world.add_child(car)
	car.configure(args[1] if args.size() > 1 else "nexia2")
	# Optional third argument "brake": ignition on, foot on the brake (the
	# stop lamps must light), headlights on.
	if args.size() > 2 and args[2] == "brake":
		car.ignition = true
		car.brake = 1.0
		car.headlights = true
	elif args.size() > 2 and args[2] == "lamps":
		car.lamp_prewarm = true # every lamp lit
	elif args.size() > 2 and args[2] == "turn":
		turn_mode = true # the left indicators held lit (no blinking)
		car.ignition = true
	elif args.size() > 2 and args[2] == "spin":
		spin_mode = true
	elif args.size() > 2 and args[2] == "body":
		body_mode = true
	elif args.size() > 2 and args[2] in ["detail", "detail_lit"]:
		detail_mode = true
		if args[2] == "detail_lit":
			car.ignition = true
			car.headlights = true
	var data := CourseData.get_default()
	var start: Dictionary = data.exercise("start")["spawn"]
	car.teleport(builder.spawn_transform(CourseData.v2(start["pos"]), float(start["yaw"])), true)
	Loading.finish() # the loading page covers the first frames otherwise
	cam = Camera3D.new()
	cam.current = true
	cam.far = 500
	world.add_child(cam)
	# Car-relative views (body frame: +x right, -z forward). fov, eye, target.
	shots = [
		["front34", 40, Vector3(-3.4, 1.5, -4.6), Vector3(0, 0.6, 0)],
		["rear34", 40, Vector3(3.4, 1.7, 4.8), Vector3(0, 0.6, 0)],
		["side", 35, Vector3(-7.5, 1.0, 0.0), Vector3(0, 0.7, 0)],
		["front", 35, Vector3(0, 1.2, -7.0), Vector3(0, 0.7, 0)],
		["top", 40, Vector3(0.01, 8.0, 0.0), Vector3(0, 0, 0)],
		["cockpit", -1, Vector3.ZERO, Vector3.ZERO],
		["cockpit_wide", -2, Vector3.ZERO, Vector3.ZERO],
		# The driver turning the head (the cockpit camera skips BodyOuter).
		["cockpit_left", -1, Vector3(0, 1.4, 0), Vector3.ZERO],
		["cockpit_right", -1, Vector3(0, -1.4, 0), Vector3.ZERO],
		["cockpit_back", -1, Vector3(0, PI, -0.15), Vector3.ZERO],
		["cockpit_down", -1, Vector3(0, 0.3, -0.8), Vector3.ZERO],
		["dash_centre", 60, Vector3(0.1, 1.15, 0.45), Vector3(0.0, 0.9, -0.55)],
		["headlight", 30, Vector3(-1.6, 0.95, -3.4), Vector3(-0.62, 0.66, -1.9)],
		["passenger", 70, Vector3(0.38, 1.12, 0.2), Vector3(-0.2, 0.85, -0.7)],
	]
	if detail_mode:
		# Close-ups of the lamps and the number plates.
		shots = [
			["d_front", 32, Vector3(0, 0.85, -4.6), Vector3(0, 0.62, -2.0)],
			["d_headlamp", 24, Vector3(-1.5, 0.9, -3.6), Vector3(-0.6, 0.72, -2.05)],
			["d_headlamp_front", 20, Vector3(-0.35, 0.8, -4.2), Vector3(-0.62, 0.72, -2.1)],
			["d_rear", 32, Vector3(0, 0.95, 4.8), Vector3(0, 0.7, 2.1)],
			["d_front34", 30, Vector3(-2.6, 1.2, -4.4), Vector3(0, 0.55, -1.2)],
		]
	if turn_mode:
		shots = [
			["t_front34", 30, Vector3(-2.6, 1.2, -4.4), Vector3(0, 0.55, -1.2)],
			["t_rear34", 30, Vector3(-2.6, 1.3, 4.6), Vector3(0, 0.6, 1.2)],
			["t_side", 30, Vector3(-4.5, 1.0, -0.6), Vector3(0, 0.6, -0.6)],
			["t_headlamp", 22, Vector3(-1.5, 0.9, -3.6), Vector3(-0.6, 0.72, -2.05)],
			["t_rear", 26, Vector3(-0.8, 1.0, 4.4), Vector3(-0.55, 0.8, 2.1)],
		]
	if body_mode:
		shots = [
			["b_quarter_left", 34, Vector3(-3.4, 1.3, 3.6), Vector3(-0.6, 0.75, 1.3)],
			["b_quarter_right", 34, Vector3(3.4, 1.3, 3.6), Vector3(0.6, 0.75, 1.3)],
			["b_rear", 30, Vector3(0, 1.1, 5.4), Vector3(0, 0.7, 2.0)],
			["b_rear_low", 26, Vector3(0.6, 0.6, 4.2), Vector3(0, 0.55, 2.2)],
			["b_through_left", 40, Vector3(-4.2, 1.15, 0.4), Vector3(0, 1.0, 0.2)],
			["b_through_right", 40, Vector3(4.2, 1.15, -0.2), Vector3(0, 1.0, 0.0)],
			["b_through_rear", 40, Vector3(1.2, 1.7, 5.2), Vector3(0, 1.05, 0.5)],
			["b_chase", 55, Vector3(0, 2.2, 6.2), Vector3(0, 0.9, -1.0)],
			["b_above", 40, Vector3(-3.2, 3.8, 2.4), Vector3(0, 0.6, 0.0)],
		]
	if spin_mode:
		shots = []
		for k in 6:
			var a := k * TAU / 6.0
			shots.append(["spin_left_%d" % k, 30, Vector3(-3.2, 0.45, -1.3), Vector3(-0.75, 0.3, -1.3), a])
			shots.append(["spin_right_%d" % k, 30, Vector3(3.2, 0.45, -1.3), Vector3(0.75, 0.3, -1.3), a])


func _process(_delta: float) -> void:
	if turn_mode:
		car.indicator = Car.Indicator.LEFT
		car._blink_t = 0.0 # always the lit half of the cycle
	wait += 1
	if wait < 25:
		return
	if idx > 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(str(shots[idx - 1][0]) + ".png"))
		print("saved ", shots[idx - 1][0])
	if idx >= shots.size():
		get_tree().quit(0)
		return
	var s: Array = shots[idx]
	var xf := car.global_transform
	if spin_mode:
		# The wheels turned by hand (the car stands still): a wobbling or
		# off-centre part shows as it moves between the shots.
		car.rest_pose = true
		for sp in car._wheel_spins:
			if sp:
				sp.rotation.x = float(s[4])
	var fov: float = s[1]
	if fov < 0:
		var look: Vector3 = s[2] # (unused, yaw, pitch) of the head
		var head := Basis(Vector3.UP, look.y) * Basis(Vector3.RIGHT, look.z - 0.07)
		cam.global_transform = Transform3D(xf.basis * head, xf * car.cockpit_eye)
		cam.fov = 72 if fov == -1 else 95
		cam.cull_mask &= ~Car.LAYER_EXTERIOR
		car.set_interior_audio(true) # the cockpit-only parts
	else:
		cam.cull_mask |= Car.LAYER_EXTERIOR
		car.set_interior_audio(false)
		cam.fov = fov
		cam.global_position = xf * (s[2] as Vector3)
		cam.look_at(xf * (s[3] as Vector3), Vector3.UP)
	idx += 1
	wait = 0
