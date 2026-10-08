shader_type spatial;
// The inside of a body shell (Car, models with "cockpit_shell" from the
// driver's seat, "inner_shell" from everywhere): only the back faces are
// drawn (culled in hardware, so the depth test still runs early), as trim
// panels, and the faces overhead as the headliner.
render_mode cull_front;

uniform vec3 trim : source_color = vec3(0.19, 0.195, 0.2);
uniform vec3 headliner : source_color = vec3(0.62, 0.61, 0.58);

void fragment() {
	// Back faces: the normal turned to the viewer (into the cabin).
	vec3 n = dot(NORMAL, VIEW) < 0.0 ? -NORMAL : NORMAL;
	NORMAL = n;
	vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ALBEDO = mix(trim, headliner, smoothstep(0.55, 0.85, -wn.y));
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
