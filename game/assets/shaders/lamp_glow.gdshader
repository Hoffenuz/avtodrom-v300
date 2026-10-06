shader_type spatial;
// The lit patch of an indicator lens (Car._make_turn_glows): a soft amber
// disc facing the camera, pulled a little towards it so the lens in front of
// the bulb does not hide it, and faded out when the lamp faces away.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.06, 1.0);
uniform float energy = 1.8;
// Metres towards the camera.
uniform float pull = 0.1;
// Direction the lamp shines, in the car's frame.
uniform vec3 facing = vec3(0.0, 0.0, -1.0);
// dot(facing, view) where the patch has faded out / is fully seen.
uniform vec2 fade_range = vec2(-0.15, 0.35);

varying float v_fade;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 face = normalize((MODEL_MATRIX * vec4(facing, 0.0)).xyz);
	v_fade = smoothstep(fade_range.x, fade_range.y, dot(face, to_cam));
	// Billboard round the lamp's centre, quad size in metres.
	vec4 p = VIEW_MATRIX * vec4(centre, 1.0);
	p.xy += VERTEX.xy;
	p.xyz += normalize(-p.xyz) * pull;
	POSITION = PROJECTION_MATRIX * p;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.25, 1.0, d);
	ALBEDO = color.rgb * energy * mix(1.0, 1.6, 1.0 - smoothstep(0.0, 0.45, d));
	ALPHA = core * core * v_fade;
}
