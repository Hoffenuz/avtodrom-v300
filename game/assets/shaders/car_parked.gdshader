// Parked cars in the car park and the other participants' cars on the
// avtodrom (pipeline/blender/build_parked_car.py): one surface per car model,
// the look baked into the vertex colour.
//   COLOR.rgb = surface colour (linear), COLOR.a = kind: 1 paint, 0.5 glass, 0 trim
//   INSTANCE_CUSTOM.rgb = this car's paint colour (linear) for MultiMeshes;
//   `paint_color` for single cars (use_instance = false). The instance colour
//   must be white (it multiplies COLOR).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool use_instance = true;
uniform vec3 paint_color : source_color = vec3(0.9);
// 1 = solid; below 1 the car dissolves in a screen-space dither (the other
// participants appearing and leaving the route) without alpha blending.
uniform float fade = 1.0;

varying vec3 paint;

void vertex() {
	paint = use_instance ? INSTANCE_CUSTOM.rgb : paint_color;
}

void fragment() {
	if (fade < 0.999) {
		float d = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (d > fade) {
			discard;
		}
	}
	float is_paint = smoothstep(0.7, 0.9, COLOR.a);
	float is_glass = smoothstep(0.25, 0.4, COLOR.a) * (1.0 - is_paint);
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * paint, is_paint);
	// Glossy paint under a clear coat, dark glass that mirrors the sky.
	ROUGHNESS = mix(mix(0.62, 0.03, is_glass), 0.26, is_paint);
	METALLIC = 0.18 * is_paint + 0.25 * is_glass;
	SPECULAR = mix(0.4, 0.85, max(is_glass, is_paint));
	CLEARCOAT = is_paint;
	CLEARCOAT_ROUGHNESS = 0.08;
}
