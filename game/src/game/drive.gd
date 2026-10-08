extends Node3D
## The driving session (exam, practice or free drive): builds the world,
## spawns the car, wires the controls to it and runs the exam director.

const RESULTS_DELAY := 1.8

var data: CourseData
var course: CourseBuilder
var car: Car
var rig: CameraRig
var controls: DriverControls
var director: ExamDirector
var hud: Hud
var guide: RouteGuide
var mirrors: MirrorViews
var pause_menu: PauseMenu
var _layout_editor: HudLayoutEditor
var results: ResultsPanel
var quality := 1
var autopilot: Autopilot
var traffic_cars: TrafficCars
var _indicator_peak := 0.0
var _last_indicator := Car.Indicator.OFF
## Seconds the starter has turned after a key tap (-1: not cranking).
var _crank_t := -1.0
const CRANK_MAX_S := 2.5


func _ready() -> void:
	data = CourseData.for_vehicle(Session.car_id())
	quality = int(Settings.get_value("quality"))
	_apply_graphics()
	Settings.changed.connect(func(_k: String) -> void: _apply_graphics())
	Loading.stage("environment")
	var sun := EnvironmentSetup.create(self, quality)
	Loading.stage("course")
	course = CourseBuilder.load_or_build(data, quality, bool(Settings.get_value("lite_scenery")))
	add_child(course)
	var rng := RandomNumberGenerator.new()
	var seed_arg := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_arg = int(arg.substr(7)) # reproducible light phases / emergency point
			rng.seed = seed_arg
	course.traffic.randomize_phase(rng)

	Loading.stage("car")
	if not ClassDB.class_exists("AvtoVehicle"):
		# The physics module (game/bin/libavtodrom.*) did not load on this
		# device: there is no car to drive. Said plainly on the loading page.
		push_error("native module not loaded: AvtoVehicle missing")
		return
	car = Car.new()
	car.name = "Car"
	add_child(car)
	car.configure(Session.car_id())

	controls = DriverControls.new()
	controls.name = "Controls"
	add_child(controls)
	controls.steering_lock = car.get_steering_lock()
	controls.automatic = car.is_automatic()
	_connect_controls()

	Loading.stage("exam")
	var spawn := {}
	if Session.mode != Session.Mode.FREE:
		director = ExamDirector.new()
		director.name = "Director"
		add_child(director)
		director.setup(data, car, course.traffic, Session.practice_exercise if Session.mode == Session.Mode.PRACTICE else "")
		if seed_arg >= 0:
			director.rng.seed = seed_arg + 1
		director.finished.connect(_on_finished)
		spawn = director.spawn_point()
	else:
		var sp: Dictionary = data.exercise("start")["spawn"]
		spawn = {"pos": CourseData.v2(sp["pos"]), "yaw": float(sp["yaw"]), "running": false}
	car.teleport(course.spawn_transform(spawn["pos"], spawn["yaw"]), spawn["running"])
	car.ignition = spawn["running"]
	car.seatbelt = spawn["running"]
	car.handbrake = 0.0 if spawn["running"] else 1.0
	car.request_gear(AvtoGear.selector_neutral(car.is_automatic()) if not car.is_automatic() else AvtoGear.PARK)
	if spawn["running"]:
		# Practice spawns straight into the exercise, ready to drive off.
		if car.is_automatic():
			car.brake = 1.0
			car.request_gear(AvtoGear.DRIVE)
		elif car.auto_clutch:
			car.request_gear(1)

	rig = CameraRig.new(car)
	# Keeps the view on the car also while paused (a pause at the very first
	# frame would otherwise leave the camera at the world origin).
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(rig)
	var cam_mode := {"cockpit": CameraRig.Mode.COCKPIT, "chase": CameraRig.Mode.CHASE, "top": CameraRig.Mode.TOP}
	rig.set_mode(cam_mode.get(str(Settings.get_value("camera")), CameraRig.Mode.COCKPIT))

	guide = RouteGuide.new()
	add_child(guide)
	guide.setup(data, director, course)

	if "--stall-test" in OS.get_cmdline_user_args():
		return # checks: the load stops here, the stall message must appear
	if "--hang-test" in OS.get_cmdline_user_args() and not Loading.opengl_mode():
		OS.delay_msec(120000) # checks: a frozen driver; the watchdog must restart on OpenGL
	Loading.stage("hud")
	hud = Hud.new()
	add_child(hud)
	hud.setup(car, controls, director, data)
	hud.pause_requested.connect(_pause)
	hud.camera_requested.connect(_cycle_camera)
	hud.look_drag.connect(func(d: Vector2, w: float) -> void: rig.drag(d, w))
	hud.look_end.connect(func() -> void: rig.drag_end())
	hud.look_zoom.connect(func(f: float) -> void: rig.zoom_by(f))

	Loading.stage("mirrors")
	mirrors = MirrorViews.new()
	add_child(mirrors)
	mirrors.setup(car, hud.root, quality, sun, rig.camera)
	mirrors.hide_exterior_in_cockpit(rig)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume.connect(_resume)
	pause_menu.restart.connect(_restart)
	pause_menu.quit_to_menu.connect(_quit_to_menu)
	pause_menu.edit_layout.connect(_edit_layout)

	results = ResultsPanel.new()
	add_child(results)
	results.retry.connect(_restart)
	results.menu.connect(func() -> void: Session.back_to_menu())
	if Session.demo and director:
		# Demonstration: the autopilot performs the exercise; the player watches.
		start_autopilot()
		controls.view_only = true
		hud.set_demo(true)
		rig.set_mode(CameraRig.Mode.CHASE)
	_debug_options()
	Loading.stage("traffic")
	_setup_traffic(seed_arg)
	Loading.stage("first frame")
	# Lamp materials compile behind the loading page, not at the first brake.
	car.lamp_prewarm = true
	Loading.finish(func() -> void: car.lamp_prewarm = false)


## Command-line helpers for automated checks (after "--" on the command line;
## screenshots and time limits are handled by the DebugShots autoload):
##   --camera=<mode>     cockpit | chase | top
##   --autopilot         the autopilot drives
##   --autopilot-test    drive the whole exam, print the protocol, exit 0 if clean
##   --faults=<a,b>      autopilot with deliberate mistakes (see Autopilot.faults)
##   --seed=<n>          fixed traffic-light phases (reproducible runs)
##   --open-pause        open the pause menu at once (screenshots)
func _debug_options() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			var m := {"cockpit": CameraRig.Mode.COCKPIT, "chase": CameraRig.Mode.CHASE, "top": CameraRig.Mode.TOP}
			rig.set_mode(m.get(arg.substr(9), CameraRig.Mode.CHASE))
		elif arg == "--autopilot":
			start_autopilot()
		elif arg.begins_with("--no-process="):
			# Frame-time checks: stop the named nodes' per-frame work.
			for n in arg.substr(13).split(","):
				var node := find_child(n, true, false)
				if node:
					node.process_mode = Node.PROCESS_MODE_DISABLED
		elif arg == "--open-pause":
			_pause.call_deferred()
		elif arg.begins_with("--faults="):
			start_autopilot()
			autopilot.faults = arg.substr(9).split(",")
		elif arg == "--autopilot-test":
			# End-to-end check: drive the whole exam, report, exit(0) only if clean.
			start_autopilot()
			_test_mode = true
			director.penalty_added.connect(func(e: Dictionary) -> void:
				print("PENALTY №%d +%d (%s) at %.1f s: %s [%s]" % [e["no"], e["points"], e["exercise"], e["time"],
						PenaltyTable.text(int(e["no"])), e["detail"]]))
			director.milestone.connect(func(text: String) -> void:
				print("[%6.1f s] milestone: %s" % [director.exam_time, text]))
			director.exercise_changed.connect(func() -> void:
				var ex := director.current_exercise()
				if ex:
					print("[%6.1f s] exercise: %s" % [director.exam_time, ex.id]))


var _test_mode := false


## Other participants (Settings → traffic, or "--traffic=<n>" for checks).
## Not with the autopilot: the demonstrations and the automated exam drive
## an empty avtodrom.
func _setup_traffic(seed_arg: int) -> void:
	var count := int(Settings.get_value("traffic_count")) if bool(Settings.get_value("traffic")) else 0
	var forced := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--traffic="): # checks (also with the autopilot: frame-time runs)
			count = int(arg.substr(10))
			forced = true
	# The demonstrations drive among the other participants as the player
	# would (they wait while the car is on their way); the automated checks
	# stay alone unless they ask for traffic.
	if count <= 0 or (autopilot != null and not Session.demo and not forced) \
			or ("--autopilot-test" in OS.get_cmdline_user_args() and not forced):
		return
	traffic_cars = TrafficCars.new()
	add_child(traffic_cars)
	# The participants drive the cars' route, whatever the player drives.
	traffic_cars.setup(CourseData.get_default(), course.traffic, car, rig.camera, clampi(count, 1, 5), seed_arg)


func _apply_graphics() -> void:
	quality = int(Settings.get_value("quality"))
	EnvironmentSetup.apply_viewport(get_viewport(), quality)
	if not DebugShots.perf:
		Engine.max_fps = Settings.frame_limit()
	# The "shadows" toggle (and a quality change) must reach the sun even
	# after the scene has already loaded, not just at EnvironmentSetup.create().
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = quality >= 1 and bool(Settings.get_value("shadows"))


func _on_setting_changed(key: String) -> void:
	if key == "auto_clutch" and car:
		car.auto_clutch = bool(Settings.get_value("auto_clutch"))
	if key == "steering_mode" and controls:
		controls.touch_steer_active = false # let tilt / keys take over again
	if key in ["auto_clutch", "left_handed", "steering_mode"] and hud:
		hud.relayout()


func _connect_controls() -> void:
	Settings.changed.connect(_on_setting_changed)
	controls.indicator_pressed.connect(func(dir: int) -> void: car.toggle_indicator(dir))
	controls.hazard_pressed.connect(func() -> void: car.set_hazard(not car.hazard))
	controls.seatbelt_pressed.connect(func() -> void: car.seatbelt = not car.seatbelt)
	controls.headlights_pressed.connect(func() -> void: car.headlights = not car.headlights)
	controls.handbrake_pressed.connect(func() -> void: car.handbrake = 0.0 if car.handbrake > 0.5 else 1.0)
	controls.camera_pressed.connect(_cycle_camera)
	controls.pause_pressed.connect(_pause)
	controls.ignition_pressed.connect(_on_key_tap)
	controls.starter_changed.connect(_on_starter)
	controls.gear_requested.connect(_on_gear)
	controls.gear_step.connect(func(d: int) -> void:
		var cur := car.get_selector() if car.is_automatic() else car.get_gear()
		# The automatic selector runs P(0) R(1) N(2) D(3); "up" means towards P.
		var delta := -d if car.is_automatic() else d
		_on_gear(AvtoGear.step(cur, delta, car.is_automatic(), car.get_forward_gear_count())))


## Next camera view; the choice is remembered for the next drive.
func _cycle_camera() -> void:
	rig.cycle()
	Settings.set_value("camera", ["cockpit", "chase", "top"][rig.mode])


## One tap on the key starts the engine (the starter turns until it catches,
## like a start button); a tap with the engine running switches it off.
func _on_key_tap() -> void:
	if car.is_engine_running():
		car.ignition = false
		car.starter = false
		_crank_t = -1.0
		return
	_on_starter(true)
	if car.starter:
		_crank_t = 0.0


func _on_starter(held: bool) -> void:
	if not held:
		car.starter = false
		return
	if car.is_engine_running():
		return
	car.ignition = true
	var clutch_ok := car.is_automatic() or car.auto_clutch or car.clutch > 0.7 or AvtoGear.in_neutral_or_park(car)
	var selector_ok := not car.is_automatic() or AvtoGear.in_neutral_or_park(car)
	if not clutch_ok or not selector_ok:
		hud.show_center(Loc.t("hud.clutch_to_start"), UITheme.CAUTION, 2.2)
		return
	car.starter = true


func _on_gear(g: int) -> void:
	# The real Cobalt wants the brake pedal to leave P; on a phone that needs a
	# second finger for no benefit, so the selector moves freely.
	if not car.request_gear(g):
		hud.gears.reject()
		if not car.is_automatic():
			hud.show_center(Loc.t("hud.clutch_needed"), UITheme.CAUTION, 1.8)


## Hands the car to the autopilot (demonstration mode / automated test).
func start_autopilot() -> void:
	if director == null or autopilot != null:
		return
	autopilot = Autopilot.new()
	autopilot.name = "Autopilot"
	add_child(autopilot)
	autopilot.setup(car, director, data)
	autopilot.active = true


## The first seconds of the drive (after the loading page): if the frame rate
## stays under FPS_FLOOR and the player has not picked a quality, one level
## lower is saved and applied at once (resolution, shadows, anti-aliasing;
## the scenery itself follows on the next load). Checked again afterwards, so
## a weak device can step down twice.
const FPS_FLOOR := 22.0
const FPS_SETTLE := 1.5 # s ignored after the loading page (pipelines compiling)
const FPS_WINDOW := 6.0
var _fps_t := 0.0
var _fps_frames := 0
var _fps_time := 0.0


func _process(delta: float) -> void:
	_watch_frame_rate(delta)


func _watch_frame_rate(delta: float) -> void:
	if Loading.is_covering() or get_tree().paused or bool(Settings.get_value("quality_user")):
		return
	if int(Settings.get_value("quality")) <= 0 and Settings.render_scale() <= 0.6 \
			and (bool(Settings.get_value("lite_scenery")) or not Settings.is_mobile()):
		set_process(false)
		return
	_fps_t += delta
	if _fps_t < FPS_SETTLE:
		return
	_fps_frames += 1
	_fps_time += delta
	if _fps_time < FPS_WINDOW:
		return
	var fps := _fps_frames / _fps_time
	_fps_frames = 0
	_fps_time = 0.0
	_fps_t = 0.0
	if fps >= FPS_FLOOR:
		set_process(false) # fine on this device
		return
	var q := int(Settings.get_value("quality"))
	print("frame rate %.1f fps at quality %d: stepping down" % [fps, q])
	if q > 0:
		Settings.set_value("quality", q - 1)
	elif Settings.is_mobile() and Settings.render_scale() > 0.6:
		Settings.set_value("render_scale", 0.6)
	elif Settings.is_mobile() and not bool(Settings.get_value("lite_scenery")):
		Settings.set_value("lite_scenery", true) # lighter scenery from the next drive
	else:
		set_process(false) # nothing left to lower
		return
	if hud:
		hud.show_center(Loc.t("hud.quality_lowered"), UITheme.INFO, 3.0)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	if _crank_t >= 0.0:
		_crank_t += delta
		if car.is_engine_running() or _crank_t > CRANK_MAX_S:
			car.starter = false
			_crank_t = -1.0
	controls.car_speed = car.get_forward_speed()
	if autopilot and autopilot.active:
		return
	car.throttle = controls.throttle
	car.brake = controls.brake
	car.clutch = controls.clutch
	car.steering_wheel = controls.steer_deg
	_indicator_self_cancel()


## Real indicator stalks cancel when the wheel comes back after a turn.
func _indicator_self_cancel() -> void:
	if car.indicator != _last_indicator:
		_last_indicator = car.indicator
		_indicator_peak = 0.0
	if car.indicator == Car.Indicator.OFF:
		return
	var sign := -1.0 if car.indicator == Car.Indicator.LEFT else 1.0
	var turned := car.steering_wheel * sign
	_indicator_peak = maxf(_indicator_peak, turned)
	if _indicator_peak > 150.0 and turned < 45.0:
		car.set_indicator(Car.Indicator.OFF)


## Android "back": close whatever is open on top, otherwise pause. It never
## leaves a running exam by itself (the pause menu warns about rule №26).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if results == null or results.visible:
				return
			if _layout_editor:
				_layout_editor.finish()
			elif pause_menu.visible:
				if not pause_menu.back():
					_resume()
			else:
				_pause()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# A call or the home button: no finger-up events will arrive, so let
			# go of every on-screen control and stop the clock.
			if controls:
				controls.release_touch()
			if hud:
				hud.release_touch()
			if results and not results.visible and Settings.is_mobile():
				_pause()


func _pause() -> void:
	if results.visible:
		return
	get_tree().paused = true
	pause_menu.open(_exam_running(), hud.touch_mode and not hud.demo)


func _exam_running() -> bool:
	return director != null and not director.practice and not Session.demo \
			and director.state == ExamDirector.State.RUNNING


## Touch-control layout, over the paused drive; back to the pause menu after.
func _edit_layout() -> void:
	pause_menu.visible = false
	_layout_editor = HudLayoutEditor.new(hud)
	_layout_editor.finished.connect(func() -> void:
		_layout_editor.queue_free()
		_layout_editor = null
		pause_menu.open(_exam_running(), true))
	hud.root.add_child(_layout_editor)


func _resume() -> void:
	get_tree().paused = false
	pause_menu.close()


func _restart() -> void:
	Session.restart_drive()


func _quit_to_menu() -> void:
	if director and not director.practice and director.state == ExamDirector.State.RUNNING:
		director.abandon()
	Session.back_to_menu()


func _on_finished(result: Dictionary) -> void:
	if _test_mode:
		print("RESULT passed=%s completed=%s penalty=%d time=%.1f distance=%d" % [result["passed"],
				result["completed"], result["penalty"], result["time"], result["distance"]])
		for ex in result["exercises"]:
			print("  %-14s performed=%s penalties=%d" % [ex["id"], ex["performed"], ex["penalties"]])
		get_tree().quit(0 if int(result["penalty"]) == 0 and result["completed"] else 1)
		return
	Session.record_result(result)
	await get_tree().create_timer(RESULTS_DELAY).timeout
	if is_inside_tree():
		results.show_result(result)
