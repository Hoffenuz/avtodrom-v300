// Headlamp behind a clear lens, drawn on the lens mesh itself (car.gd,
// MODELS[...]["lamp_shader"]): the Cobalt's lamps are the smooth-shaded front
// of a convex hull with nothing modelled inside, so the inside is painted here
// from the object-space position, after the real T250 lamp: a bright chrome
// housing; a large multi-facet reflector bowl with its bulb shield in the
// middle and a smaller one towards the grille; a curved chrome strip along the
// lower edge over a dark lip; at the outer end, in the chrome, the amber
// indicator bulb. A clear-coat layer is the polycarbonate lens.
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

// A multi-facet reflector: smooth parabolic shading, a dozen wedge facets
// each catching the light a little differently, a bright rolled lip.
vec3 bowl(vec2 d, float radius) {
	float r = length(d) / radius;
	float ang = atan(d.y, d.x);
	float facet = fract(ang / 6.2832 * 12.0);
	float wedge = 0.9 + 0.1 * sin(floor(ang / 6.2832 * 12.0) * 2.7);
	float depth = mix(0.5, 1.0, smoothstep(0.15, 0.95, r)); // darker deep inside
	float seam = smoothstep(0.0, 0.04, facet) * smoothstep(1.0, 0.96, facet);
	// Lit from above: the upper half of the bowl brighter than the lower.
	float sky = 0.85 + 0.15 * clamp(d.y / radius, -1.0, 1.0);
	vec3 c = vec3(0.84, 0.85, 0.87) * depth * wedge * sky * mix(0.82, 1.0, seam);
	c = mix(c, vec3(0.97), smoothstep(0.88, 0.97, r)); // rolled lip
	return c;
}

void fragment() {
	float s = abs(lp.x);
	float y = lp.y;
	float w = max(bounds.y - bounds.x, 0.01);
	float h = max(bounds.w - bounds.z, 0.01);
	float u = clamp((s - bounds.x) / w, 0.0, 1.0); // 0 at the grille, 1 at the wing
	float v = clamp((y - bounds.z) / h, 0.0, 1.0);

	// Housing: satin chrome, darker towards the bottom (the inside of the
	// lamp is in its own shade). Not a mirror: polished, it reflected the
	// blue sky and the whole lamp read blue.
	vec3 albedo = vec3(0.7, 0.71, 0.73) * mix(0.62, 1.0, smoothstep(0.1, 0.8, v));
	float metal = 0.7;
	float rough = 0.34;

	// Large reflector (middle) and the smaller one towards the grille.
	float cy = bounds.z + h * 0.5;
	vec2 ca = vec2(bounds.x + w * 0.5, cy);
	vec2 cb = vec2(bounds.x + w * 0.2, cy + h * 0.02);
	float ra = h * 0.36;
	float rb = h * 0.24;
	vec2 da = vec2(s, y) - ca;
	vec2 db = vec2(s, y) - cb;
	float in_a = 1.0 - smoothstep(ra - 0.002, ra, length(da));
	float in_b = 1.0 - smoothstep(rb - 0.002, rb, length(db));
	// A thin dark gap round each bowl sets it into the housing.
	float gap = (1.0 - smoothstep(0.002, 0.005, abs(length(da) - ra))) + (1.0 - smoothstep(0.002, 0.005, abs(length(db) - rb)));
	albedo = mix(albedo, bowl(da, ra), in_a);
	albedo = mix(albedo, bowl(db, rb), in_b);
	metal = mix(metal, 0.8, max(in_a, in_b));
	rough = mix(rough, 0.26, max(in_a, in_b));
	albedo *= 1.0 - 0.45 * clamp(gap, 0.0, 1.0);
	// The projector in the large bowl: a dark glass lens in a bright ring;
	// a bare bulb in the small one.
	float pr = ra * 0.42;
	float proj = 1.0 - smoothstep(pr - 0.002, pr, length(da));
	float ring = (1.0 - smoothstep(pr, pr + 0.006, length(da))) * (1.0 - proj);
	float bulb = 1.0 - smoothstep(0.011, 0.014, length(db));
	albedo = mix(albedo, vec3(0.95), ring);
	vec3 lens = mix(vec3(0.16, 0.17, 0.19), vec3(0.04, 0.045, 0.05), smoothstep(0.0, pr, length(da - vec2(-0.25, 0.3) * pr)));
	albedo = mix(albedo, lens, proj);
	metal = mix(metal, 0.2, proj);
	rough = mix(rough, 0.06, proj);
	albedo = mix(albedo, vec3(0.98, 0.97, 0.94), bulb);
	rough = mix(rough, 0.12, bulb);

	// The chrome "smile" along the lower edge, the dark lip under it, and a
	// dark bezel along the top.
	float smile_v = 0.13 + 0.05 * (1.0 - u) * (1.0 - u);
	float smile = 1.0 - smoothstep(0.012, 0.028, abs(v - smile_v));
	float lip = 1.0 - smoothstep(smile_v - 0.03, smile_v - 0.01, v);
	albedo = mix(albedo, vec3(0.1, 0.105, 0.11), lip);
	metal = mix(metal, 0.3, lip);
	rough = mix(rough, 0.4, lip);
	albedo = mix(albedo, vec3(1.0), smile * (1.0 - lip));
	rough = mix(rough, 0.06, smile);
	float bezel = smoothstep(0.9, 0.97, v);
	albedo = mix(albedo, vec3(0.05), bezel);
	metal = mix(metal, 0.4, bezel);

	// The indicator: an amber bulb in the chrome at the outer end, three
	// fine ribs above it (the "FFF" of the real lamp).
	vec2 cbulb = vec2(bounds.x + w * 0.88, bounds.z + h * 0.42);
	float dbulb = length(vec2(s, y) - cbulb);
	float amber_bulb = 1.0 - smoothstep(0.009, 0.012, dbulb);
	float amber_cup = (1.0 - smoothstep(0.018, 0.021, dbulb)) * (1.0 - amber_bulb);
	float amber_glow = 1.0 - smoothstep(0.015, 0.07, dbulb);
	float ribs = step(0.82, u) * step(u, 0.96) * step(0.62, v) * step(v, 0.84)
			* (1.0 - smoothstep(0.1, 0.2, abs(fract(u * 45.0) - 0.5)));
	albedo = mix(albedo, vec3(0.55, 0.56, 0.58), ribs);
	// The bulb: a small amber glass dome (lighter at its crown) in a chrome cup.
	albedo = mix(albedo, bowl(vec2(s, y) - cbulb, 0.021) * 1.05, amber_cup);
	albedo = mix(albedo, mix(vec3(1.0, 0.72, 0.3), vec3(0.85, 0.42, 0.05), smoothstep(0.0, 0.011, dbulb)), amber_bulb);
	metal = mix(metal, 0.1, amber_bulb);
	rough = mix(rough, 0.08, amber_bulb);

	vec3 glow = vec3(0.0);
	float head_on = part == 0 ? lit : beam;
	float beam_shape = in_a * (1.0 - 0.55 * length(da) / ra) * (1.0 - 0.7 * proj) + proj * 1.4
			+ in_b * (1.0 - 0.55 * length(db) / rb) * 0.85;
	glow += vec3(1.0, 0.97, 0.9) * head_on * (beam_shape * 3.2 + 0.25 * (1.0 - lip) * (1.0 - bezel));
	float turn_on = part == 1 ? lit : 0.0;
	glow += vec3(1.0, 0.5, 0.04) * turn_on * (amber_bulb * 6.0 + amber_glow * 3.0);

	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	// The clear lens: a sharp highlight over the whole lamp.
	CLEARCOAT = 0.8;
	CLEARCOAT_ROUGHNESS = 0.05;
	EMISSION = glow;
}
