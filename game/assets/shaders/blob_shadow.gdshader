// Soft contact shadow under the parked and the other participants' cars
// (a quad on the ground): cheap stand-in for a shadow map out of its range.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float strength = 0.55;

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	d = abs(d);
	// Rounded rectangle falloff: dense under the body, fading at the edges.
	float r = length(max(d - vec2(0.55, 0.72), 0.0) / vec2(0.45, 0.28));
	float a = (1.0 - smoothstep(0.0, 1.0, r)) * (0.75 + 0.25 * (1.0 - max(d.x, d.y)));
	ALBEDO = vec3(0.0);
	ALPHA = a * strength;
}
