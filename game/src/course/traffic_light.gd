class_name TrafficLight
extends StaticBody3D
## One three-aspect traffic signal on a pole. The lamp face (local +Z) looks
## at the traffic it controls. State is set by TrafficController.
##
## Built once by CourseBuilder (setup()) and saved into the baked course
## scene; on load, _ready() re-links the lamp meshes by name.

enum Aspect { OFF, RED, RED_YELLOW, GREEN, GREEN_BLINK, YELLOW }

const HOUSING_COLOR := Color(0.09, 0.1, 0.11)
const LAMP_COLORS := [Color(1.0, 0.12, 0.08), Color(1.0, 0.7, 0.05), Color(0.1, 1.0, 0.45)]
const POLE_H := 2.6

@export var light_id := ""
@export var group := ""
var aspect: Aspect = Aspect.OFF
var _lamps: Array[MeshInstance3D] = []
var _on_mats: Array[StandardMaterial3D] = []
var _off_mats: Array[StandardMaterial3D] = []
var _blink_t := 0.0


func setup(p_id: String, p_group: String) -> void:
	light_id = p_id
	group = p_group
	name = "TrafficLight_" + p_id
	collision_layer = SignFactory.OBSTACLE_LAYER
	collision_mask = 0
	add_to_group("obstacle", true)
	_build()


func _ready() -> void:
	if _lamps.is_empty():
		for i in 3:
			var lamp := get_node_or_null("Lamp%d" % i) as MeshInstance3D
			if lamp:
				_lamps.append(lamp)
	_make_materials()
	set_aspect(aspect if aspect != Aspect.OFF else Aspect.RED)


func _build() -> void:
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = POLE_H
	cm.radial_segments = 10
	cm.material = SignFactory.pole_material()
	pole.mesh = cm
	pole.position = Vector3(0, POLE_H * 0.5, 0)
	add_child(pole)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.1
	cyl.height = POLE_H + 0.9
	shape.shape = cyl
	shape.position = Vector3(0, (POLE_H + 0.9) * 0.5, 0)
	add_child(shape)

	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.95, 0.24)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = HOUSING_COLOR
	hm.roughness = 0.6
	bm.material = hm
	housing.mesh = bm
	housing.position = Vector3(0, POLE_H + 0.45, 0.0)
	add_child(housing)

	# Yellow backboard, as in the scheme.
	var board := MeshInstance3D.new()
	board.name = "Board"
	var bb := BoxMesh.new()
	bb.size = Vector3(0.56, 1.12, 0.02)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.95, 0.82, 0.1)
	bmat.roughness = 0.5
	bb.material = bmat
	board.mesh = bb
	board.position = Vector3(0, POLE_H + 0.45, -0.13)
	add_child(board)

	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.1
	sm.radial_segments = 16
	sm.rings = 4
	for i in 3:
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp%d" % i
		lamp.mesh = sm
		lamp.position = Vector3(0, POLE_H + 0.75 - i * 0.3, 0.12)
		add_child(lamp)
		_lamps.append(lamp)


func _make_materials() -> void:
	_on_mats.clear()
	_off_mats.clear()
	for i in 3:
		var on := StandardMaterial3D.new()
		on.albedo_color = LAMP_COLORS[i]
		on.emission_enabled = true
		on.emission = LAMP_COLORS[i]
		on.emission_energy_multiplier = 3.2
		on.roughness = 0.2
		_on_mats.append(on)
		var off := StandardMaterial3D.new()
		off.albedo_color = LAMP_COLORS[i].darkened(0.82)
		off.roughness = 0.25
		off.metallic = 0.2
		_off_mats.append(off)


func set_aspect(a: Aspect) -> void:
	aspect = a
	_refresh(true)


func _refresh(blink_on: bool) -> void:
	if _lamps.size() < 3 or _on_mats.size() < 3:
		return
	var red := aspect == Aspect.RED or aspect == Aspect.RED_YELLOW
	var yellow := aspect == Aspect.YELLOW or aspect == Aspect.RED_YELLOW
	var green := aspect == Aspect.GREEN or (aspect == Aspect.GREEN_BLINK and blink_on)
	var states := [red, yellow, green]
	for i in 3:
		_lamps[i].material_override = _on_mats[i] if states[i] else _off_mats[i]


func _process(delta: float) -> void:
	if aspect == Aspect.GREEN_BLINK:
		_blink_t += delta
		_refresh(fmod(_blink_t, 1.0) < 0.5)


## True when a driver may enter the junction (green or blinking green).
func is_go() -> bool:
	return aspect == Aspect.GREEN or aspect == Aspect.GREEN_BLINK


func is_stop() -> bool:
	return aspect == Aspect.RED or aspect == Aspect.RED_YELLOW or aspect == Aspect.YELLOW
