// A flag on its pole, waving (the quad's UV.x runs from the pole outwards).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float amp = 0.12;

void vertex() {
	float x = UV.x;
	float ph = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x * 0.7;
	VERTEX.z += sin(x * 7.0 - TIME * 4.2 + ph) * amp * x;
	VERTEX.y -= x * x * 0.06;
	NORMAL = normalize(vec3(0.0, 0.0, 1.0) + vec3(-cos(x * 7.0 - TIME * 4.2 + ph) * amp * 1.5, 0.0, 0.0));
}

void fragment() {
	vec4 t = texture(tex, UV);
	float fold = 0.88 + 0.12 * sin(UV.x * 7.0 - TIME * 4.2);
	ALBEDO = t.rgb * fold;
	ROUGHNESS = 0.8;
	BACKLIGHT = t.rgb * 0.3;
}
