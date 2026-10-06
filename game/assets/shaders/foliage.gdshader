// Tree crowns, bushes and hedges (Surroundings). The colour is the vertex
// colour (a baked light-to-shade gradient: darker low in the crown and in its
// hollows) times the instance colour (the tree's own green), broken up by a
// world-space noise so neighbouring leaves are not one flat tint.
// No shadow maps are sampled: the crowns are round, low-poly shapes that
// shadowed themselves in dithered speckles; the gradient and a wrapped
// diffuse do their shading. `sway` moves the crown gently in the wind
// (0 for hedges), phase taken from the instance position.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform float sway = 0.06; // metres at the top of a 10 m crown
uniform float noise_scale = 0.9;
uniform float noise_strength = 0.22;

varying vec3 wp;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = max(wp.y - origin.y + 1.0, 0.0) * 0.1; // more sway higher up
	float ph = origin.x * 0.37 + origin.z * 0.23;
	vec3 wind = vec3(sin(TIME * 1.3 + ph), 0.0, cos(TIME * 0.9 + ph * 1.7)) * sway * up;
	wind += vec3(sin(TIME * 3.1 + wp.y * 1.7 + ph), 0.0, 0.0) * sway * 0.25 * up;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * wind;
}

void fragment() {
	float n = vnoise(wp * noise_scale) * 0.65 + vnoise(wp * noise_scale * 3.1) * 0.35;
	vec3 c = COLOR.rgb * mix(1.0 - noise_strength, 1.0 + noise_strength * 0.6, n);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	BACKLIGHT = c * 0.25; // light through the leaves at the edges
}
