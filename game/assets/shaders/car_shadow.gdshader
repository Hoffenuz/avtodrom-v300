// The player's car shadow where shadow maps fall short (OpenGL, low quality):
// a quad on the ground under the car. The body is two boxes, the lower body
// up to the belt line and the narrower cabin over it, and the shadow is
// where the sun ray through a ground point meets either box: the box is
// stepped along the sun's direction by height, plus a dense contact shade
// right under the car. Same for every sedan, soft and without speckles.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 body = vec4(0.0, 0.0, 0.85, 2.25); // centre x, z, half width, half length (car frame)
uniform vec4 cabin = vec4(0.0, 0.25, 0.68, 0.95); // the same for the cabin
uniform vec2 heights = vec2(0.92, 1.44); // belt line, roof
uniform vec2 sun_step = vec2(0.4, 0.6); // ground offset per metre of height (car frame)
uniform float strength = 0.62;

varying vec2 p;

void vertex() {
	p = VERTEX.xz;
	// Nudged towards the camera a little more than the road paint
	// (marking.gdshader), so the paint under the car is shaded too.
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 to_cam = cam - VERTEX;
	float dist = length(to_cam);
	VERTEX += to_cam / max(dist, 0.001) * 0.03 * clamp(dist * 0.08, 0.3, 4.0);
}

float rbox(vec2 q, vec2 b, float r) {
	vec2 d = abs(q) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	float cast = 0.0;
	for (int i = 0; i < 10; i++) {
		float h = mix(0.25, heights.y, (float(i) + 0.5) / 10.0);
		vec4 b = h < heights.x ? body : cabin;
		float d = rbox(p - sun_step * h - b.xy, b.zw, 0.22);
		float soft = 0.05 + 0.06 * h; // the penumbra widens with height
		cast = max(cast, 1.0 - smoothstep(-soft, soft, d));
	}
	float dc = rbox(p - body.xy, body.zw * vec2(0.9, 0.95), 0.35);
	float contact = 1.0 - smoothstep(-0.45, 0.2, dc);
	ALBEDO = vec3(0.0);
	ALPHA = max(cast * strength, contact * min(strength + 0.16, 0.85));
}
