// The exam route's blue ribbon (RouteGuide): the whole route is one static
// mesh built once, UV.x the route length s at each vertex; only the stretch
// from s0 to s_end is drawn, fading out over `ahead` metres. Moving the
// window is a uniform change: no mesh is rebuilt while driving (rebuilding
// it ten times a second made a new GPU buffer each time, which phones'
// drivers map and release lazily).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float s0 = 0.0;
uniform float s_end = 0.0;
uniform float ahead = 36.0;
uniform vec4 colour : source_color = vec4(0.3, 0.62, 1.0, 0.33);

varying float s;

void vertex() {
	s = UV.x;
}

void fragment() {
	if (s < s0 || s > s_end) {
		discard;
	}
	ALBEDO = colour.rgb;
	ALPHA = colour.a * clamp(1.0 - (s - s0) / ahead, 0.0, 1.0);
}
