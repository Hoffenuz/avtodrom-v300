class_name TrafficCars
extends Node3D
## "Other participants" (Settings → traffic): a few other learner cars in
## bright colours driving the exam route round the avtodrom while the player
## drives. They keep to the rules — stop at the crosswalk, on the estakada
## and at the railway line, wait for the green at the intersection, keep
## their distance — and stay out of the player's way: a car stops and waits
## as long as the player's car is on the stretch it is about to drive over,
## never appears near the player, and leaves the route out of sight at the
## finish to start again at the beginning.
##
## Kinematic: each car is moved along the path (its axles on the line, so it
## cuts the bends like a real car), set on the ground by two rays (the
## estakada), with its wheels turning, its stop lamps lit when it brakes and
## its indicator blinking before each turn. The cars are the game's own
## models (Car.MODELS, without the cabin; the engine's automatic mesh LODs
## thin them out with distance); on Low quality light single-mesh versions
## (pipeline/blender/build_parked_car.py --npc). It is an obstacle on the physics layer
## the player's car collides with. The box's dead-end lane (entered forwards,
## left after reversing into a bay) is replaced by the straight road past it.

const MODELS := [
	["res://assets/cars/lod/nexia2_npc.glb", 0.41, 0.82],
	["res://assets/cars/lod/cobalt_npc.glb", 0.44, 0.46],
	["res://assets/cars/lod/gentra_npc.glb", 0.5, 0.78],
] # [model, front plate height, rear plate height]
## Bright, easy to tell from the player's white / black cars.
const COLOURS := [Color(0.78, 0.07, 0.06), Color(0.96, 0.74, 0.05), Color(0.95, 0.42, 0.05),
		Color(0.1, 0.55, 0.22), Color(0.18, 0.55, 0.9), Color(0.5, 0.2, 0.62), Color(0.55, 0.78, 0.12),
		Color(0.05, 0.62, 0.62)]
const CRUISE := 3.3 # m/s ≈ 12 km/h
const ACCEL := 1.1
const DECEL := 2.2
const LENGTH := 4.4
const HALF_WIDTH := 0.85
const GAP := 4.0 # m between bumpers when queueing
const WAIT_LINE := 3.4 # s at the crosswalk, estakada and railway lines
const SPAWN_S := 36.0 # m along the path where cars (re)appear
const LAYER_OBSTACLE := 4
const PLAYER_HALF := Vector2(1.0, 2.4) # player's footprint half size (+margin)
## Car.MODELS ids, the same order as MODELS.
const FULL_IDS := ["nexia2", "cobalt_at", "gentra"]
const SIGNAL_BEFORE := 22.0 # m before a turn the indicator comes on
const SIGNAL_AFTER := 4.0
const FADE_TIME := 1.2 # s to appear / dissolve

var data: CourseData
var traffic: TrafficController
var player: Car
var camera: Camera3D
var cars: Array[Dictionary] = []
var _pts := PackedVector2Array()
var _ps := PackedFloat32Array()
var _len := 0.0
## Where the participants leave the route: short of the finish exercise, so
## they never take the player's parking place there.
var _end_s := 0.0
var _stops: Array = [] # [{s, kind, approach}] sorted by s
var _rng := RandomNumberGenerator.new()
var _plate_mat: StandardMaterial3D
var _meshes := {} # model path -> [body mesh, wheel mesh, wheel positions, plates]
var _full := true # the game's car models (else the light single-mesh ones)
var _turns: Array = [] # [{s, dir}] on the path: where to signal
var _blink_t := 0.0
var _log := false # "--traffic-log": print where the cars are every 5 s
var _log_t := 0.0


func setup(p_data: CourseData, p_traffic: TrafficController, p_player: Car, p_camera: Camera3D, count: int,
		seed_: int = -1) -> void:
	name = "TrafficCars"
	data = p_data
	traffic = p_traffic
	player = p_player
	camera = p_camera
	if seed_ >= 0:
		_rng.seed = seed_
	else:
		_rng.randomize()
	_log = "--traffic-log" in OS.get_cmdline_user_args()
	_full = int(Settings.get_value("quality")) >= 1
	_build_path()
	_plan_stops()
	_plan_turns()
	_end_s = _len - LENGTH
	var fin := data.exercise("finish")
	if not fin.is_empty():
		_end_s = _nearest_s(data.route_point(float(fin["s0"])), _len * 0.5, _len) - 4.0
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_texture = Car.PLATE_TEX
	_plate_mat.roughness = 0.45
	_plate_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var colours := COLOURS.duplicate()
	colours.shuffle()
	for i in count:
		var k := _rng.randi() % MODELS.size()
		var colour: Color = colours[i % colours.size()]
		var car := _make_car_full(FULL_IDS[k], colour, MODELS[k]) if _full else _make_car(MODELS[k], colour)
		cars.append(car)
	# Spread along the route, away from the player.
	for i in count:
		var s := _len * (i + 0.6) / (count + 0.4)
		for _t in 12:
			if _spawn_clear(s, 30.0, i):
				break
			s = fposmod(s + 47.0, _len - 60.0) + 20.0
		# "--traffic-near": the first car just ahead of the player (checks).
		var near := i == 0 and "--traffic-near" in OS.get_cmdline_user_args()
		if near:
			s = _nearest_s(Vector2(player.global_position.x, player.global_position.z), 0.0, _len) + 14.0
		_place(cars[i], s)
		cars[i]["active"] = near or _spawn_clear(s, 18.0, i)
		_show(cars[i], cars[i]["active"])
		_set_fade(cars[i], 1.0)


# ------------------------------------------------------------------ path
func _build_path() -> void:
	var route := data.route
	var rs := data.route_s
	var n := route.size()
	# The one dead end on the route (the box lane): find where the heading
	# turns right round, then the longest straight hop along the road that
	# joins the route before it turns in to the route after it comes out.
	var cut := Vector2i(-1, -1)
	var turn_i := -1
	for i in range(4, n - 5):
		var d0 := (route[i] - route[i - 4]).normalized()
		var d1 := (route[i + 4] - route[i]).normalized()
		if d0.dot(d1) < -0.8:
			turn_i = i
			break
	if turn_i > 0:
		var best := 0.0
		var lo := maxi(1, data.route_index(rs[turn_i] - 60.0))
		var hi := mini(n - 2, data.route_index(rs[turn_i] + 60.0))
		for a in range(lo, turn_i):
			var da := (route[a + 1] - route[a]).normalized()
			for b in range(turn_i, hi):
				var db := (route[b + 1] - route[b]).normalized()
				if da.dot(db) < 0.97:
					continue
				var v := route[b] - route[a]
				var L := v.length()
				if L < 2.0 or L > 30.0 or v.dot(da) <= 0.0 or absf(v.cross(da)) > 0.5:
					continue
				if rs[b] - rs[a] > best:
					best = rs[b] - rs[a]
					cut = Vector2i(a, b)
	for i in n:
		if cut.x >= 0 and i > cut.x and i < cut.y:
			if i == cut.x + 1:
				var a := route[cut.x]
				var b := route[cut.y]
				var steps := int(a.distance_to(b) / 0.5)
				for k in range(1, steps):
					_pts.append(a.lerp(b, float(k) / steps))
			continue
		_pts.append(route[i])
	_ps.resize(_pts.size())
	_ps[0] = 0.0
	for i in range(1, _pts.size()):
		_ps[i] = _ps[i - 1] + _pts[i].distance_to(_pts[i - 1])
	_len = _ps[_ps.size() - 1]


func _index(s: float) -> int:
	var lo := 0
	var hi := _ps.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _ps[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _at(s: float) -> Vector2:
	s = clampf(s, 0.0, _len)
	var i := _index(s)
	if i >= _pts.size() - 1:
		return _pts[_pts.size() - 1]
	var seg := _ps[i + 1] - _ps[i]
	return _pts[i].lerp(_pts[i + 1], 0.0 if seg <= 0.0 else (s - _ps[i]) / seg)


## Path distance of the point nearest `p` between s0 and s1.
func _nearest_s(p: Vector2, s0: float, s1: float) -> float:
	var best := INF
	var best_s := s0
	for i in range(_index(maxf(s0, 0.0)), mini(_index(minf(s1, _len)) + 1, _pts.size())):
		var d := _pts[i].distance_squared_to(p)
		if d < best:
			best = d
			best_s = _ps[i]
	return best_s


func _plan_stops() -> void:
	for def in data.exercises:
		var type := str(def["type"])
		if not type in ["stop_line", "hill", "intersection"]:
			continue
		var line: Dictionary = def["stop_line"]
		var mid := (Geo.line_a(line) + Geo.line_b(line)) * 0.5
		# The exercise's stretch of the original route, give or take the box cut.
		var s0 := _nearest_s(data.route_point(float(def["s0"])), 0.0, _len)
		var s := _nearest_s(mid, s0 - 5.0, s0 + 70.0)
		var stop := {"s": s - LENGTH * 0.5 - 0.5, "kind": "light" if type == "intersection" else "line"}
		if type == "intersection":
			stop["approach"] = str(def["approach"])
		_stops.append(stop)
	_stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])


# ------------------------------------------------------------------ cars
func _model_parts(path: String) -> Array:
	if _meshes.has(path):
		return _meshes[path]
	var root: Node = (load(path) as PackedScene).instantiate()
	var body: Mesh = null
	var wheel: Mesh = null
	var wheels := {}
	for c in root.find_children("*", "Node3D", true, false):
		var n := c as Node3D
		if n is MeshInstance3D:
			if String(n.name).begins_with("NpcWheel"):
				wheel = (n as MeshInstance3D).mesh
			else:
				body = (n as MeshInstance3D).mesh
		elif String(n.name).begins_with("Wheel_"):
			wheels[String(n.name).substr(6, 2)] = n.position
	root.free()
	# Plates: where rays at the plate heights meet the body, front and back.
	var plates := []
	if body:
		var tm := TriangleMesh.new()
		tm.create_from_faces(body.get_faces())
		var model_row: Array = []
		for m in MODELS:
			if m[0] == path:
				model_row = m
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			var y: float = model_row[1 + k] if not model_row.is_empty() else 0.45
			var hit := tm.intersect_ray(Vector3(0, y, side * 4.0), Vector3(0, 0, -side))
			if not hit.is_empty():
				plates.append(hit["position"] + Vector3(0, 0, side * 0.01))
	var parts := [body, wheel, wheels, plates]
	_meshes[path] = parts
	return parts


func _make_car(model: Array, colour: Color) -> Dictionary:
	var parts := _model_parts(model[0])
	var root := AnimatableBody3D.new()
	root.name = "Participant"
	root.sync_to_physics = true
	root.collision_layer = LAYER_OBSTACLE
	root.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, 1.3, LENGTH)
	shape.shape = box
	shape.position = Vector3(0, 0.8, 0)
	root.add_child(shape)
	var paint := ShaderMaterial.new()
	paint.resource_local_to_scene = true
	paint.shader = load("res://assets/shaders/car_parked.gdshader")
	paint.set_shader_parameter("use_instance", false)
	paint.set_shader_parameter("paint_color", colour)
	var body := MeshInstance3D.new()
	body.mesh = parts[0]
	body.material_override = paint
	root.add_child(body)
	var wheels: Array[Node3D] = []
	var wpos: Dictionary = parts[2]
	for corner in ["FL", "FR", "RL", "RR"]:
		var w := MeshInstance3D.new()
		w.mesh = parts[1]
		w.material_override = paint
		w.position = wpos.get(corner, Vector3.ZERO)
		root.add_child(w)
		wheels.append(w)
	for i in (parts[3] as Array).size():
		var q := QuadMesh.new()
		q.size = Vector2(0.52, 0.112)
		q.material = _plate_mat
		var pm := MeshInstance3D.new()
		pm.mesh = q
		pm.position = parts[3][i]
		if i == 0:
			pm.rotation.y = PI # the front plate faces -z
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pm)
	var blob := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2, 4.9)
	var sm := ShaderMaterial.new()
	sm.shader = Surroundings.BLOB_SHADER
	plane.material = sm
	blob.mesh = plane
	blob.position.y = 0.03
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blob)
	add_child(root)
	var wb := 2.55
	if wpos.has("FL") and wpos.has("RL"):
		wb = absf((wpos["RL"] as Vector3).z - (wpos["FL"] as Vector3).z)
	var radius := 0.29
	if wpos.has("FL"):
		radius = maxf((wpos["FL"] as Vector3).y, 0.25)
	return {"node": root, "wheels": wheels, "wpos": wpos, "wb": wb, "radius": radius, "s": 0.0, "v": 0.0,
			"spin": 0.0, "wait": 0.0, "stop_done": -1.0, "active": true, "blocked_by": -1, "paint": paint,
			"fade": 1.0, "leaving": false, "extras": [blob] + root.get_children().filter(
					func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh)}


## Dissolves (0) or shows (1) the car; plates and shadow only when solid.
func _set_fade(car: Dictionary, f: float) -> void:
	car["fade"] = f
	if car["paint"]:
		(car["paint"] as ShaderMaterial).set_shader_parameter("fade", f)
	else:
		# The full models have many materials: they appear and vanish at the
		# middle of the fade (out of the camera's view anyway).
		(car["model"] as Node3D).visible = f > 0.5
	for e in car["extras"]:
		(e as Node3D).visible = f >= 0.999


## Route turns (indicator checks) as path distances for the participants.
func _plan_turns() -> void:
	for t in data.raw["route"]["turns"]:
		var p := data.route_point(float(t["s"]))
		_turns.append({"s": _nearest_s(p, 0.0, _len), "dir": str(t["dir"])})
	_turns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])


## A participant built from the game's own car model: materials, plates and
## (Cobalt) headlamps as on the player's car; no cabin behind the windows,
## which are tinted dark instead; the shadow from the light proxy.
func _make_car_full(cid: String, colour: Color, light: Array) -> Dictionary:
	var spec: Dictionary = Car.MODELS[cid]
	var root := AnimatableBody3D.new()
	root.name = "Participant"
	root.sync_to_physics = true
	root.collision_layer = LAYER_OBSTACLE
	root.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var front: float = spec["front"]
	var rear: float = spec["rear"]
	box.size = Vector3(float(spec["half_width"]) * 2.0, 1.3, front + rear)
	shape.shape = box
	shape.position = Vector3(0, 0.8, (rear - front) * 0.5)
	root.add_child(shape)
	var model: Node3D = (load(spec["path"]) as PackedScene).instantiate()
	model.name = "Model"
	root.add_child(model)
	for n in ["Interior", "SteeringPivot", "GaugeSpeed", "GaugeRpm", "CollisionHull"]:
		var x := model.find_child(n, true, false)
		if x:
			x.get_parent().remove_child(x)
			x.free()
	Car._apply_materials(model, colour)
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(0.02, 0.028, 0.034)
	tint.metallic = 0.35
	tint.roughness = 0.04
	var lamps := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.begins_with("Lamp_"):
			lamps[String(m.name)] = m
		for sfc in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(sfc)
			if src and src.resource_name == "window":
				m.set_surface_override_material(sfc, tint)
	Car.smooth_lamps(lamps, spec.get("smooth_lamps", []))
	var drawn := Car.headlamp_materials(lamps, model) if spec.get("lamp_shader", false) else {}
	Car.add_plates(model, spec)
	# Lamps per group: [mesh, off material, on material].
	var groups := {"brake": [], "left": [], "right": []}
	var red := Car._emissive(Color(1.0, 0.06, 0.04), 6.0)
	var orange := Car._emissive(Color(1.0, 0.52, 0.05), 6.0)
	for n in lamps:
		var mi: MeshInstance3D = lamps[n]
		var off: Material = drawn[n][0] if drawn.has(n) else mi.get_active_material(0)
		if drawn.has(n):
			for sfc in mi.mesh.get_surface_count():
				mi.set_surface_override_material(sfc, off)
		var on_turn: Material = drawn[n][1] if drawn.has(n) else orange
		if n in ["Lamp_Brake", "Lamp_Tail"]:
			groups["brake"].append([mi, off, red])
		elif n in ["Lamp_TurnFL", "Lamp_TurnRL", "Lamp_TurnSL"]:
			groups["left"].append([mi, off, on_turn])
		elif n in ["Lamp_TurnFR", "Lamp_TurnRR", "Lamp_TurnSR"]:
			groups["right"].append([mi, off, on_turn])
	# Far away the light single-mesh version stands in (one draw instead of a
	# dozen): the full model up to HLOD_RANGE, the light one beyond.
	var hlod := 140.0 if int(Settings.get_value("quality")) >= 2 else 70.0
	for gi in model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = hlod
	var parts := _model_parts(light[0])
	var far_nodes: Array = []
	if parts[0] and parts[1]:
		var far := ShaderMaterial.new()
		far.shader = load("res://assets/shaders/car_parked.gdshader")
		far.set_shader_parameter("use_instance", false)
		far.set_shader_parameter("paint_color", colour)
		var body := MeshInstance3D.new()
		body.name = "FarBody"
		body.mesh = parts[0]
		body.material_override = far
		body.visibility_range_begin = hlod
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(body)
		far_nodes.append(body)
		var wpos: Dictionary = parts[2]
		for corner in wpos:
			var w := MeshInstance3D.new()
			w.mesh = parts[1]
			w.material_override = far
			w.position = wpos[corner]
			if String(corner).ends_with("R"):
				w.rotation.y = PI
			w.visibility_range_begin = hlod
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(w)
			far_nodes.append(w)
	# The shadow: the 2.5k-triangle proxy, as the player's car.
	if spec.has("lod") and ResourceLoader.exists(spec["lod"]):
		var src := (load(spec["lod"]) as PackedScene).instantiate()
		for lm in src.find_children("*", "MeshInstance3D", true, false):
			var proxy := MeshInstance3D.new()
			proxy.mesh = (lm as MeshInstance3D).mesh
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			proxy.transform = Car.chain_to(lm, src)
			model.add_child(proxy)
		src.free()
	add_child(root)
	var pivots: Array[Node3D] = []
	var spins: Array[Node3D] = []
	for corner in ["FL", "FR", "RL", "RR"]:
		pivots.append(model.find_child("Wheel_" + corner, true, false) as Node3D)
		spins.append(model.find_child("Spin_" + corner, true, false) as Node3D)
	var wb := 2.55
	var radius := 0.29
	if pivots[0] and pivots[2]:
		wb = absf(pivots[2].position.z - pivots[0].position.z)
		radius = maxf(pivots[0].position.y, 0.25)
	var wheels: Array[Node3D] = []
	return {"node": root, "wheels": wheels, "pivots": pivots, "spins": spins, "wpos": {}, "wb": wb,
			"radius": radius, "s": 0.0, "v": 0.0, "spin": 0.0, "wait": 0.0, "stop_done": -1.0, "active": true,
			"blocked_by": -1, "paint": null, "fade": 1.0, "leaving": false, "extras": far_nodes, "lamps": groups,
			"lamp_state": {}, "model": model}


## Stop lamps while braking or standing, the indicator before the route's turns.
func _update_lamps(car: Dictionary, braking: bool) -> void:
	if not car.has("lamps"):
		return
	var s: float = car["s"]
	var sig := ""
	for t in _turns:
		var ds: float = float(t["s"]) - s
		if ds < -SIGNAL_AFTER:
			continue
		if ds < SIGNAL_BEFORE:
			sig = t["dir"]
		break
	var lit := fmod(_blink_t, 0.667) < 0.333
	var want := {"brake": braking, "left": sig == "left" and lit, "right": sig == "right" and lit}
	var state: Dictionary = car["lamp_state"]
	for g in want:
		if state.get(g, null) == want[g]:
			continue
		state[g] = want[g]
		for entry in car["lamps"][g]:
			var mi: MeshInstance3D = entry[0]
			mi.set_surface_override_material(0, entry[2] if want[g] else entry[1])


func _show(car: Dictionary, on: bool) -> void:
	var node: AnimatableBody3D = car["node"]
	node.visible = on
	node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	(node.get_child(0) as CollisionShape3D).disabled = not on


## Whether a car may appear at `s`: the player and the other cars are
## `radius` away, and (after the start) the spot is out of the camera's view.
func _spawn_clear(s: float, radius: float, self_i: int) -> bool:
	var p := _at(s)
	var pp := Vector2(player.global_position.x, player.global_position.z)
	if p.distance_to(pp) < radius:
		return false
	for i in cars.size():
		if i != self_i and cars[i]["active"] and absf(float(cars[i]["s"]) - s) < LENGTH + GAP * 2.0:
			return false
	return true


func _in_view(p: Vector2, y := 0.8) -> bool:
	if camera == null:
		return false
	var w := Vector3(p.x, y, p.y)
	return camera.is_position_in_frustum(w) and camera.global_position.distance_to(w) < 140.0


# ------------------------------------------------------------------ driving
func _physics_process(dt: float) -> void:
	if player == null:
		return
	_blink_t += dt
	if _log:
		_log_t += dt
		if _log_t >= 5.0:
			_log_t = 0.0
			var parts := []
			for c in cars:
				parts.append("%s s=%.0f v=%.1f%s" % ["on" if c["active"] else "off", c["s"], c["v"],
						" blocked" if int(c["blocked_by"]) != -1 else ""])
			print("TRAFFIC player=(%.1f, %.1f) %.1f km/h engine=%s | %s" % [player.global_position.x,
					player.global_position.z, player.get_speed_kmh(), player.is_engine_running(), " | ".join(parts)])
	for i in cars.size():
		var car: Dictionary = cars[i]
		if not car["active"]:
			if _spawn_clear(SPAWN_S, 25.0, i) and not _in_view(_at(SPAWN_S)):
				car["active"] = true
				car["leaving"] = false
				car["v"] = 0.0
				car["stop_done"] = -1.0
				_place(car, SPAWN_S)
				_show(car, true)
				_set_fade(car, 0.0)
			continue
		if float(car["fade"]) < 1.0 and not car["leaving"]:
			_set_fade(car, minf(float(car["fade"]) + dt / FADE_TIME, 1.0))
		_drive(i, car, dt)


func _drive(i: int, car: Dictionary, dt: float) -> void:
	var s: float = car["s"]
	var v: float = car["v"]
	# Done with the route: slow to a stop and dissolve.
	if s >= _end_s:
		if not car["leaving"]:
			car["leaving"] = true
			(car["node"].get_child(0) as CollisionShape3D).set_deferred("disabled", true)
		v = maxf(v - DECEL * dt, 0.0)
		car["v"] = v
		_place(car, s + v * dt, dt)
		_set_fade(car, maxf(float(car["fade"]) - dt / FADE_TIME, 0.0))
		if float(car["fade"]) <= 0.0:
			car["active"] = false
			_show(car, false)
		return
	var target := CRUISE * _curve_factor(s)
	# Stops on the way.
	for st in _stops:
		var ds: float = float(st["s"]) - s
		if ds < -0.5 or float(car["stop_done"]) >= float(st["s"]):
			continue
		if ds > 25.0:
			break
		var go := false
		if st["kind"] == "light":
			var group := "NS" if st["approach"] in ["N", "S"] else "EW"
			var left := traffic.time_to_stop(group) if traffic else INF
			var t_to_line := ds / maxf(v, 0.8)
			go = left > t_to_line + 1.5 or (ds < v * v / (2.0 * DECEL) and left > 0.0)
			if go:
				if ds < 0.5:
					car["stop_done"] = st["s"]
				break
		elif ds < 0.4 and v < 0.05:
			car["wait"] = float(car["wait"]) + dt
			if float(car["wait"]) >= WAIT_LINE:
				car["wait"] = 0.0
				car["stop_done"] = st["s"]
				break
		target = minf(target, sqrt(maxf(2.0 * DECEL * 0.6 * maxf(ds - 0.1, 0.0), 0.0)))
		break
	# The car ahead on the path.
	for j in cars.size():
		if j == i or not cars[j]["active"]:
			continue
		var gap: float = float(cars[j]["s"]) - s - LENGTH
		if gap > -LENGTH * 0.5 and gap < 30.0:
			target = minf(target, sqrt(maxf(2.0 * DECEL * 0.6 * maxf(gap - GAP, 0.0), 0.0)))
	# The player (and cars crossing at the intersection) on the stretch ahead.
	var look := v * v / (2.0 * DECEL) + 9.0
	var block := _blocked_ahead(i, s, look)
	if block < INF:
		target = minf(target, sqrt(maxf(2.0 * DECEL * 0.6 * maxf(block - 3.2, 0.0), 0.0)))
	var dv := target - v
	v += clampf(dv, -DECEL * 1.6 * dt, ACCEL * dt)
	v = maxf(v, 0.0)
	car["v"] = v
	_update_lamps(car, dv < -0.25 or v < 0.2)
	_place(car, s + v * dt, dt)


## Slower through tight bends (lateral acceleration ≈ 1.2 m/s²).
func _curve_factor(s: float) -> float:
	var worst := 1.0
	for k in [2.0, 5.0, 8.0]:
		var d0 := (_at(s + k) - _at(s + k - 2.0)).normalized()
		var d1 := (_at(s + k + 2.0) - _at(s + k)).normalized()
		var turn := absf(d0.angle_to(d1))
		if turn > 0.02:
			var radius := 2.0 / turn
			worst = minf(worst, sqrt(1.2 * radius) / CRUISE)
	return clampf(worst, 0.45, 1.0)


## Path distance to the first point ahead (up to `look` m) that the player's
## car, or another participant crossing the path, stands on; INF if clear.
func _blocked_ahead(self_i: int, s: float, look: float) -> float:
	var obstacles: Array = [] # [centre, forward, half size, car index]
	var pf := -player.global_transform.basis.z
	obstacles.append([Vector2(player.global_position.x, player.global_position.z), Vector2(pf.x, pf.z).normalized(),
			PLAYER_HALF, -1])
	for j in cars.size():
		if j == self_i or not cars[j]["active"]:
			continue
		# Cars on the same stretch are handled by the queueing gap.
		if absf(float(cars[j]["s"]) - s) < 30.0:
			continue
		# Never both waiting for each other.
		if int(cars[j]["blocked_by"]) == self_i and j > self_i:
			continue
		var n: Node3D = cars[j]["node"]
		var f := -n.global_transform.basis.z
		obstacles.append([Vector2(n.global_position.x, n.global_position.z), Vector2(f.x, f.z).normalized(),
				Vector2(HALF_WIDTH + 0.3, LENGTH * 0.5 + 0.3), j])
	cars[self_i]["blocked_by"] = -1
	var d := 0.0
	while d <= look:
		var p := _at(s + LENGTH * 0.5 + d)
		for o in obstacles:
			var rel: Vector2 = p - (o[0] as Vector2)
			var fwd: Vector2 = o[1]
			var along := absf(rel.dot(fwd))
			var side := absf(rel.dot(Vector2(-fwd.y, fwd.x)))
			var half: Vector2 = o[2]
			if along < half.y + 0.4 and side < half.x + HALF_WIDTH + 0.4:
				cars[self_i]["blocked_by"] = o[3]
				return d
		d += 0.8
	return INF


## Puts the car at path distance `s` (its body centre), axles on the line,
## on the ground, wheels turned and rolled.
func _place(car: Dictionary, s: float, dt := 0.0) -> void:
	var old_s: float = car["s"]
	car["s"] = s
	var wb: float = car["wb"]
	var front := _at(s + wb * 0.5)
	var rear := _at(s - wb * 0.5)
	var fwd := (front - rear).normalized()
	if fwd == Vector2.ZERO:
		fwd = Vector2(0, -1)
	var mid := (front + rear) * 0.5
	var yf := _ground(front)
	var yr := _ground(rear)
	var y := (yf + yr) * 0.5
	var pitch := atan2(yf - yr, wb)
	var yaw := atan2(-fwd.x, -fwd.y)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var node: AnimatableBody3D = car["node"]
	node.global_transform = Transform3D(basis, Vector3(mid.x, y, mid.y))
	# Wheels: roll by the distance travelled, fronts steered along the path.
	var ahead := (_at(s + wb * 0.5 + 2.0) - front).normalized()
	var steer := fwd.angle_to(ahead) * 1.4 if ahead != Vector2.ZERO else 0.0
	car["spin"] = float(car["spin"]) + (s - old_s) / float(car["radius"])
	if car.has("spins"):
		for k in 4:
			var pv: Node3D = car["pivots"][k]
			var sp: Node3D = car["spins"][k]
			if pv and k < 2:
				pv.basis = Basis(Vector3.UP, -steer)
			if sp:
				sp.rotation.x = -float(car["spin"])
		return
	var wheels: Array[Node3D] = car["wheels"]
	for k in 4:
		var flip := Basis(Vector3.UP, PI) if k % 2 == 1 else Basis()
		var st := Basis(Vector3.UP, -steer) if k < 2 else Basis()
		wheels[k].basis = st * Basis(Vector3.RIGHT, -float(car["spin"])) * flip


func _ground(p: Vector2) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 6.0, p.y), Vector3(p.x, -2.0, p.y), 1)
	var hit := space.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0
