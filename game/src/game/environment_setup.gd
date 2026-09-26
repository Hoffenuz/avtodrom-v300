class_name EnvironmentSetup
extends RefCounted
## Sky, sun and post-processing, scaled to the quality level.
##   0 = low (phones from ~2018, OpenGL fallback), 1 = medium, 2 = high.

static func create(parent: Node, quality: int) -> DirectionalLight3D:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky/sky_1k.hdr")
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if quality < 2 else Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if quality >= 2 else Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
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
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Late-morning sun from the south-east, as in the scheme's shading.
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(150.0), 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = quality >= 1 and bool(Settings.get_value("shadows"))
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality < 2 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 45.0 if quality < 2 else 80.0
	sun.directional_shadow_blend_splits = quality >= 2
	parent.add_child(sun)
	return sun
