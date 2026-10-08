class_name CarPaint
## Body colours on offer and the per-car choice (settings "paint_<car>").
##
## The colours are the common ones on Uzbek roads (UzAuto paint codes), with
## the near-duplicates left out: one white (not white and cream), one grey of
## each shade, one red, champagne for the warm shades. A colour is only the
## paint material's albedo and sheen (Car._apply_materials), so it costs
## nothing to draw. The GAZelle keeps its white: nobody repaints a van.
##
## Reads the settings through the scene tree, not the Settings autoload by
## name: car.gd (and so this) also compiles in the course bake, which runs
## without autoloads.

## key, paint code, colour (sRGB), metallic, roughness.
const COLORS := [
	["white", "GAZ", Color(0.93, 0.94, 0.95), 0.05, 0.28],
	["silver", "GAN", Color(0.66, 0.68, 0.7), 0.55, 0.3],
	["grey", "GNJ", Color(0.27, 0.285, 0.3), 0.45, 0.28],
	["black", "GB0", Color(0.012, 0.012, 0.014), 0.05, 0.2],
	["red", "GL8", Color(0.36, 0.025, 0.04), 0.3, 0.24],
	["champagne", "GJT", Color(0.7, 0.62, 0.49), 0.5, 0.3],
]
## The car as the build delivers it, where no colour was chosen.
const DEFAULT := {"gentra": "black"}


## Whether the player may choose this car's colour.
static func paintable(car_id: String) -> bool:
	return car_id != "gazelle"


## The car as the menu offers it: the automatic Onix is the Onix.
static func base_id(car_id: String) -> String:
	return "onix" if car_id == "onix_at" else car_id


## Settings key of a car's colour.
static func setting_key(car_id: String) -> String:
	return "paint_" + base_id(car_id)


## The chosen colour's key ("" where the car is not paintable).
static func key_for(car_id: String) -> String:
	if not paintable(car_id):
		return ""
	var key := ""
	var s := _settings()
	if s:
		key = str(s.call("get_value", setting_key(car_id)))
	if find(key) < 0:
		key = DEFAULT.get(base_id(car_id), "white")
	return key


## Index of a colour key in COLORS, -1 if there is none.
static func find(key: String) -> int:
	for i in COLORS.size():
		if COLORS[i][0] == key:
			return i
	return -1


## The COLORS row of a key, [] if there is none.
static func entry(key: String) -> Array:
	var i := find(key)
	return COLORS[i] if i >= 0 else []


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree else null
