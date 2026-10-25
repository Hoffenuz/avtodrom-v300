class_name EnvironmentSetup
extends RefCounted
## Sky, sun and post-processing, scaled to the quality level.
##   0 = low (phones from ~2018, OpenGL fallback), 1 = medium, 2 = high.

## Late-morning sun from the south-east, as in the scheme's shading.
const SUN_ROTATION := Vector3(deg_to_rad(-52.0), deg_to_rad(150.0), 0.0)


## One sky per look for the whole session: its lighting (radiance) is
## filtered once, not again for the menu and every drive (seconds on a
## phone's GPU). Key: "<quality>:<weather>".
static var _skies := {}

## The drive's look (Settings "weather"): sky colours (top, horizon, ground
## horizon, ground bottom) for the procedural skies, and the sun (or moon).
const LOOKS := {
	"evening": {
		"sky": [Color(0.16, 0.22, 0.4), Color(0.98, 0.6, 0.36), Color(0.5, 0.38, 0.3), Color(0.06, 0.06, 0.07)],
		"sun_rot": Vector3(-9.0, 235.0, 0.0), "sun_energy": 1.0, "sun_color": Color(1.0, 0.64, 0.4),
		"fog": Color(0.86, 0.62, 0.48), "fog_density": 0.0022, "exposure": 1.05, "saturation": 1.08,
	},
	"night": {
		"sky": [Color(0.012, 0.018, 0.045), Color(0.1, 0.08, 0.075), Color(0.05, 0.045, 0.045), Color(0.01, 0.01, 0.012)],
		"sun_rot": Vector3(-38.0, 120.0, 0.0), "sun_energy": 0.12, "sun_color": Color(0.6, 0.7, 1.0),
		"fog": Color(0.06, 0.06, 0.08), "fog_density": 0.004, "exposure": 1.35, "saturation": 0.95,
		"ambient": Color(0.18, 0.19, 0.25),
	},
	"rain": {
		"sky": [Color(0.36, 0.39, 0.44), Color(0.56, 0.58, 0.61), Color(0.4, 0.41, 0.42), Color(0.2, 0.2, 0.21)],
		"sun_rot": Vector3(-52.0, 150.0, 0.0), "sun_energy": 0.45, "sun_color": Color(0.86, 0.89, 0.95),
		"fog": Color(0.6, 0.62, 0.66), "fog_density": 0.0045, "exposure": 1.0, "saturation": 0.85,
	},
}


## Settings "weather", or "day" for anything unknown.
static func weather() -> String:
	var w := str(Settings.get_value("weather"))
	return w if LOOKS.has(w) else "day"


## Whether the sun casts shadows in this look (an overcast sky or the moon:
## none, which also spares the phone a shadow pass).
static func sun_shadows(look: String) -> bool:
	return look == "day" or look == "evening"


static func create(parent: Node, quality: int, look := "day") -> DirectionalLight3D:
	var env := Environment.new()
	var q := clampi(quality, 0, 2)
	var spec: Dictionary = LOOKS.get(look, {})
	var key := "%d:%s" % [q, look]
	if not _skies.has(key):
		var new_sky := Sky.new()
		if spec.is_empty():
			var sky_mat := PanoramaSkyMaterial.new()
			sky_mat.panorama = load("res://assets/sky/sky_1k.hdr")
			sky_mat.energy_multiplier = 1.0
			new_sky.sky_material = sky_mat
		else:
			var c: Array = spec["sky"]
			var pm := ProceduralSkyMaterial.new()
			pm.sky_top_color = c[0]
			pm.sky_horizon_color = c[1]
			pm.ground_horizon_color = c[2]
			pm.ground_bottom_color = c[3]
			pm.sky_curve = 0.12
			pm.ground_curve = 0.05
			pm.sun_angle_max = 8.0 if look == "night" else 30.0
			new_sky.sky_material = pm
		new_sky.radiance_size = [Sky.RADIANCE_SIZE_64, Sky.RADIANCE_SIZE_128, Sky.RADIANCE_SIZE_256][q]
		if q == 0 and Settings.is_mobile():
			new_sky.radiance_size = Sky.RADIANCE_SIZE_32 # a quarter of the filtering
		# The sky never changes: its lighting is computed once, fully, before the
		# first frame (incremental mode spreads it over frames, and the ground and
		# the background visibly change brightness while it converges).
		new_sky.process_mode = Sky.PROCESS_MODE_QUALITY
		_skies[key] = new_sky
	env.background_mode = Environment.BG_SKY
	env.sky = _skies[key]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var mobile := Settings.is_mobile() # phone browsers too
	# Glow is a full-screen blur chain: on phones only at the top level.
	env.glow_enabled = quality >= 2 or (quality >= 1 and not mobile)
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	if not spec.is_empty():
		env.fog_light_color = spec["fog"]
		env.fog_density = spec["fog_density"]
		env.tonemap_exposure = spec["exposure"]
		env.adjustment_saturation = spec["saturation"]
		if spec.has("ambient"):
			# The night sky is too dark to light anything: a moonlit fill.
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = spec["ambient"]
	# The wet road (ground.gdshader); every drive and the menu set it.
	RenderingServer.global_shader_parameter_set("wetness", 1.0 if look == "rain" else 0.0)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = SUN_ROTATION
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.92)
	if not spec.is_empty():
		var rot: Vector3 = spec["sun_rot"]
		sun.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), 0.0)
		sun.light_energy = spec["sun_energy"]
		sun.light_color = spec["sun_color"]
	# Low: no shadows. Medium: one cascade to 35 m on phones. High: more.
	sun.shadow_enabled = quality >= 1 and bool(Settings.get_value("shadows")) and sun_shadows(look)
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	if quality >= 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if mobile 				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 55.0 if mobile else 80.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if mobile 				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 35.0 if mobile else 45.0
	sun.directional_shadow_blend_splits = quality >= 2 and not mobile
	parent.add_child(sun)
	return sun


## Resolution, anti-aliasing and level of detail for a viewport.
static func apply_viewport(vp: Viewport, quality: int) -> void:
	var mobile := Settings.is_mobile() # phone browsers too
	var scale := Settings.render_scale()
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (scale < 0.99 and quality >= 1) 			else Viewport.SCALING_3D_MODE_BILINEAR
	var q := clampi(quality, 0, 2)
	var msaa := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X] if mobile 			else [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	vp.msaa_3d = msaa[q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Switch meshes to their lighter automatic LODs earlier on phones.
	# Higher thresholds make the car body visibly pop between its LODs.
	var lod := [4.0, 2.0, 1.5] if mobile else [3.0, 1.0, 1.0]
	vp.mesh_lod_threshold = lod[q]
