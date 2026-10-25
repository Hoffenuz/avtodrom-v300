// Falling rain: thin streaks on a cylinder around the camera (Weather), two
// layers at different distances. Cheap on phones: no particles, one draw each.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.78, 0.82, 0.9, 0.32);
uniform float columns = 140.0; // streaks around the cylinder
uniform float rows = 3.0; // drops above each other per column
uniform float speed = 1.6; // cylinder heights per second
uniform float density = 0.7; // share of the columns with rain

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float x = UV.x * columns;
	float col = floor(x);
	float r = hash(col);
	if (hash(col + 17.0) > density) {
		discard;
	}
	float fx = fract(x) - 0.5;
	float line = 1.0 - smoothstep(0.03, 0.09, abs(fx));
	// UV.y grows downwards: the pattern moves to larger UV.y with time.
	float v = fract(UV.y * rows - TIME * speed * (0.85 + 0.3 * r) + r * 5.0);
	float drop = smoothstep(0.0, 0.03, v) * (1.0 - smoothstep(0.03, 0.12, v));
	float a = tint.a * line * drop;
	if (a < 0.01) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = a;
}
