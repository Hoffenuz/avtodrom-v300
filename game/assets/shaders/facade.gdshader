// Building walls with windows, from world position alone (no textures, no
// UVs): one material for the exam centre and every distant block.
// Wall colour = tint × vertex/instance colour; roofs are darker.
// The colour's alpha picks the facade style (the city's MultiMesh sets it
// per building; the exam centre's vertex colours are opaque = plain):
//   < 0.2   panel block with balconies (the Tashkent 9-storey)
//   < 0.4   panel block, seams between the panels
//   < 0.6   panel block with a glazed stair column every 5 bays
//   < 0.75  glass tower (curtain wall, mullions every bay)
//   < 0.9   blank wall (lift housings and other roof boxes)
//   < 0.97  ribbon windows: a glass band along every floor, slim mullions
//   else    plain wall with windows
// glass_color / glass_rough: the panes (the exam centre's are darker and
// glossier than the distant blocks').
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(1.0);
uniform float floor_h = 3.3;
uniform float bay_w = 3.2;
uniform float ground_floor = 1.0; // no windows below this height
uniform vec3 glass_color : source_color = vec3(0.13, 0.18, 0.25);
uniform float glass_rough = 0.12;
uniform float glass_metal = 0.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 base = tint.rgb * COLOR.rgb;
	float style = COLOR.a;
	float wall = 1.0 - step(0.5, abs(wn.y));
	float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
	vec2 cell = vec2(floor(u / bay_w), floor(wp.y / floor_h));
	float fy = fract(wp.y / floor_h);
	float fx = fract(u / bay_w);
	float above_ground = step(ground_floor, wp.y);
	float win = step(0.32, fy) * step(fy, 0.8) * step(0.16, fx) * step(fx, 0.84) * wall * above_ground;
	// Glass: some panes lit or curtained, the rest dark sky-blue.
	float h = hash(cell + floor(wp.xz / 97.0));
	vec3 glass = glass_color + vec3(0.1, 0.1, 0.08) * h;
	glass = mix(glass, vec3(0.62, 0.58, 0.48), step(0.93, h) * 0.6);
	vec3 wallc = base;
	float rough = 0.88;
	if (style < 0.6) {
		// Soviet panel block: a darker ground floor, faint panel seams.
		float seam = (1.0 - smoothstep(0.0, 0.03, fy)) + (1.0 - smoothstep(0.0, 0.02, fract(u / (bay_w * 2.0))));
		wallc *= 1.0 - 0.1 * clamp(seam, 0.0, 1.0) * wall;
		wallc = mix(wallc, base * 0.62, (1.0 - above_ground) * wall);
		if (style < 0.2) {
			// Balconies: a light slab and railing under the windows of every
			// other bay, the loggia behind them in shade.
			float balcony_bay = step(0.5, fract(cell.x * 0.5));
			float slab = step(0.02, fy) * step(fy, 0.3) * balcony_bay * above_ground * wall;
			wallc = mix(wallc, base * 1.12 + vec3(0.04), slab);
			win *= 1.0 - balcony_bay * 0.35;
		} else if (style >= 0.4) {
			// Stair column: a narrow strip of glass up the whole height.
			float stair = step(4.5, mod(cell.x, 5.0)) * wall * above_ground;
			float sw = step(0.2, fx) * step(fx, 0.8) * stair;
			win = max(win * (1.0 - stair), sw);
		}
	} else if (style < 0.75) {
		// Curtain wall: glass everywhere but thin mullions and floor bands.
		float mull = (1.0 - step(0.06, fx)) + (1.0 - step(0.08, fy));
		win = wall * (1.0 - clamp(mull, 0.0, 1.0));
		glass = glass_color * 1.35 + vec3(0.05, 0.06, 0.07) * h;
		wallc = base * 0.75;
		rough = 0.35;
	} else if (style < 0.9) {
		win = 0.0;
	} else if (style < 0.97) {
		// Ribbon windows: one glass band per floor set back in a dark frame,
		// slim aluminium mullions, a transom at door height, the slab edge
		// as a darker line; behind some panes blinds or a lit ceiling.
		float band = smoothstep(0.28, 0.285, fy) * (1.0 - smoothstep(0.86, 0.865, fy)) * wall * above_ground;
		float reveal = band * (1.0 - smoothstep(0.0, 0.03, min(fy - 0.28, 0.86 - fy)));
		float mull = 1.0 - smoothstep(0.02, 0.035, min(fx, 1.0 - fx));
		float transom = 1.0 - smoothstep(0.004, 0.012, abs(fy - 0.74));
		float frame = clamp(mull + transom, 0.0, 1.0);
		win = band * (1.0 - frame) * (1.0 - reveal);
		vec3 alu = vec3(0.42, 0.44, 0.47);
		wallc = mix(wallc, alu, band * frame);
		wallc = mix(wallc, base * 0.35, reveal);
		float slab = 1.0 - smoothstep(0.0, 0.025, fy);
		wallc = mix(wallc, base * 0.7, slab * wall);
		float hb = hash(cell * 1.7 + floor(wp.xz / 53.0));
		glass = glass_color + vec3(0.03, 0.04, 0.05) * h;
		// Blinds (light slats) behind a fifth of the panes, lit ceilings in some.
		float blinds = step(0.8, hb) * (0.5 + 0.5 * step(0.5, fract(fy * 40.0)));
		glass = mix(glass, vec3(0.62, 0.62, 0.6), blinds * 0.55);
		glass = mix(glass, vec3(0.75, 0.74, 0.66), step(hb, 0.08) * smoothstep(0.7, 0.86, fy) * 0.6);
	}
	vec3 roof = base * 0.55;
	vec3 c = mix(roof, wallc, wall);
	ALBEDO = mix(c, glass, win);
	ROUGHNESS = mix(rough, glass_rough, win);
	SPECULAR = mix(0.3, 0.7, win);
	METALLIC = glass_metal * win;
}
