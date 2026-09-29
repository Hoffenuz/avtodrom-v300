shader_type spatial;
// Menu showroom floor: a plain satin floor that fades into the horizon haze,
// so the car stands in open space without a visible edge.

uniform vec3 near_color : source_color = vec3(0.31, 0.325, 0.35);
uniform vec3 far_color : source_color = vec3(0.70, 0.77, 0.86);
uniform float fade_start = 9.0;
uniform float fade_end = 80.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = smoothstep(fade_start, fade_end, length(world_pos.xz));
	ALBEDO = mix(near_color, far_color, t);
	ROUGHNESS = mix(0.55, 1.0, t);
	SPECULAR = mix(0.4, 0.0, t);
}
