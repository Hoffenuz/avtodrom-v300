// Parked cars in the car park (Surroundings, pipeline/blender/build_parked_car.py):
// one surface per car model, the look baked into the vertex colour.
//   COLOR.rgb = surface colour (linear), COLOR.a = kind: 1 paint, 0.5 glass, 0 trim
//   INSTANCE_CUSTOM.rgb = this car's paint colour (linear); the instance colour
//   must be white (it multiplies COLOR)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 paint;

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float is_paint = smoothstep(0.7, 0.9, COLOR.a);
	float is_glass = smoothstep(0.25, 0.4, COLOR.a) * (1.0 - is_paint);
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * paint, is_paint);
	ROUGHNESS = mix(mix(0.7, 0.06, is_glass), 0.32, is_paint);
	METALLIC = 0.12 * is_paint;
	SPECULAR = mix(0.4, 0.7, max(is_glass, is_paint));
}
