// Headlamp behind a clear lens, drawn on the lens mesh itself (car.gd,
// MODELS[...]["lamp_shader"]): the Cobalt's lamps are the smooth-shaded front
// of a convex hull with nothing modelled inside, so the inside is painted here
// from the object-space position, after the real T250 lamp: a dark smoked
// chrome housing; towards the grille a large projector (a dark glass lens in
// a bright chrome ring); towards the wing a smaller round high-beam reflector
// with its bulb; under it, at the outer corner, the amber indicator; a thin
// chrome strip along the lower edge. Everything has soft edges: no lines.
//   bounds = (inner |x|, outer |x|, lowest y, highest y) of one lamp, metres
//   part   = 0 the lamp, 1 its outer end pieces (the indicator)
//   lit    = 0 off .. 1 on (headlamp beams, or the indicator flash)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 bounds = vec4(0.45, 0.8, 0.5, 0.83);
uniform int part = 0;
uniform float lit = 0.0;
// The headlamps' state, for the end pieces (their own `lit` is the indicator).
uniform float beam = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// 1 inside a circle of radius r, with a soft edge of width e.
float disc(float d, float r, float e) {
	return 1.0 - smoothstep(r - e, r + e, d);
}

void fragment() {
	float s = abs(lp.x);
	float y = lp.y;
	float w = max(bounds.y - bounds.x, 0.01);
	float h = max(bounds.w - bounds.z, 0.01);
	float u = clamp((s - bounds.x) / w, 0.0, 1.0); // 0 at the grille, 1 at the wing
	float v = clamp((y - bounds.z) / h, 0.0, 1.0);
	float e = 0.0015; // edge softness, metres

	// Housing: dark smoked chrome, a little lighter at the top (the sky).
	vec3 albedo = vec3(0.15, 0.155, 0.165) * mix(0.8, 1.15, v);
	float metal = 0.85;
	float rough = 0.3;

	// The projector: chrome ring, a dark bezel, the glass lens.
	vec2 ca = vec2(bounds.x + w * 0.4, bounds.z + h * 0.5);
	float ra = h * 0.3;
	float da = length(vec2(s, y) - ca);
	float ring = disc(da, ra, e);
	float bezel = disc(da, ra * 0.8, e);
	float lens = disc(da, ra * 0.66, e);
	// The ring is a shallow cone: brighter towards its outer edge.
	vec3 ring_col = vec3(0.8, 0.81, 0.83) * mix(0.75, 1.0, smoothstep(ra * 0.8, ra, da));
	albedo = mix(albedo, ring_col, ring);
	metal = mix(metal, 0.9, ring);
	rough = mix(rough, 0.24, ring);
	albedo = mix(albedo, vec3(0.05, 0.05, 0.055), bezel);
	rough = mix(rough, 0.4, bezel * (1.0 - lens));
	// The lens: dark glass, a soft lighter crescent at the top.
	vec2 dl = (vec2(s, y) - ca) / (ra * 0.66);
	float crescent = smoothstep(0.2, 0.9, dl.y) * (1.0 - smoothstep(0.6, 1.0, length(dl)));
	vec3 lens_col = mix(vec3(0.07, 0.075, 0.085), vec3(0.32, 0.34, 0.37), crescent * 0.6);
	albedo = mix(albedo, lens_col, lens);
	metal = mix(metal, 0.1, lens);
	rough = mix(rough, 0.04, lens);

	// The high-beam reflector: a smooth chrome bowl, its bulb in the middle.
	vec2 cb = vec2(bounds.x + w * 0.76, bounds.z + h * 0.56);
	float rb = h * 0.15;
	float db = length(vec2(s, y) - cb);
	float bowl = disc(db, rb, e);
	// Satin, not a mirror: polished it showed the sky as a bright blue disc.
	vec3 bowl_col = vec3(0.62, 0.63, 0.65) * mix(0.5, 1.0, smoothstep(0.0, rb, db));
	albedo = mix(albedo, bowl_col, bowl);
	metal = mix(metal, 0.75, bowl);
	rough = mix(rough, 0.32, bowl);
	float bulb = disc(db, rb * 0.22, e);
	albedo = mix(albedo, vec3(0.95, 0.95, 0.93), bulb);

	// The indicator: an amber lens at the outer lower corner.
	vec2 ct = vec2(bounds.x + w * 0.88, bounds.z + h * 0.24);
	vec2 dt = (vec2(s, y) - ct) / vec2(w * 0.045, h * 0.075);
	float amber = disc(length(dt), 1.0, 0.1);
	albedo = mix(albedo, vec3(0.62, 0.34, 0.07), amber);
	metal = mix(metal, 0.2, amber);
	rough = mix(rough, 0.15, amber);

	// The chrome strip along the lower edge.
	float strip = smoothstep(0.06, 0.08, v) * (1.0 - smoothstep(0.12, 0.14, v)) * (1.0 - max(ring, amber));
	albedo = mix(albedo, vec3(0.82, 0.83, 0.85), strip);
	metal = mix(metal, 1.0, strip);
	rough = mix(rough, 0.14, strip);

	vec3 glow = vec3(0.0);
	float head_on = part == 0 ? lit : beam;
	// Low beam: the projector lens glows, its ring catches the light.
	glow += vec3(1.0, 0.98, 0.94) * head_on * (lens * 3.0 + (ring - bezel) * 0.5 + bowl * 0.25);
	float turn_on = part == 1 ? lit : 0.0;
	float halo = disc(length(dt), 1.8, 0.6);
	glow += vec3(1.0, 0.5, 0.04) * turn_on * (amber * 5.0 + halo * 1.2);

	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	// The clear polycarbonate lens over it all.
	CLEARCOAT = 0.8;
	CLEARCOAT_ROUGHNESS = 0.05;
	EMISSION = glow;
}
