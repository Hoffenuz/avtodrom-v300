// A street lamp's light on the ground at night, and the lamp's glowing glass:
// added over what is there (Weather). The real lights would cost a pass per
// lamp on phones; this is one draw for all of them.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform float strength = 0.5; // the pools
uniform float glass = 4.0; // the lamps' glass

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	// COLOR.a: 1 for the glass (flat, bright), 0 for a pool (soft edge).
	float pool = pow(clamp(1.0 - d, 0.0, 1.0), 1.7) * strength;
	ALBEDO = color.rgb * mix(pool, glass * step(d, 1.2), COLOR.a);
}
