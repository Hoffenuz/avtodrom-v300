// Scenery outside the avtodrom: building walls with a procedural window
// grid, plus plain vertex-coloured surfaces (roofs, trees, hills) that share
// the same material so a whole side of the scenery is one draw call.
//   COLOR.rgb = surface colour, COLOR.a > 0.5 = draw windows.
//   UV = wall position in metres (u along the wall, v = height); UV.x < 0
//   marks a plain surface (roof, tree, hill).
// Far away (window cells a few pixels big) the grid fades to its average
// colour so it does not shimmer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec2 cell = vec2(3.2, 3.0); // window spacing, floor height (m)
uniform vec3 glass_dark : source_color = vec3(0.07, 0.09, 0.12);
uniform vec3 glass_light : source_color = vec3(0.22, 0.27, 0.33);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float box_mask(vec2 f, vec2 lo, vec2 hi, vec2 aa) {
	vec2 a = smoothstep(lo - aa, lo + aa, f) * (1.0 - smoothstep(hi - aa, hi + aa, f));
	return a.x * a.y;
}

void fragment() {
	vec3 alb = COLOR.rgb;
	float rough = 0.88;
	float spec = 0.3;
	if (UV.x >= 0.0 && COLOR.a > 0.5) {
		vec2 c = UV / cell;
		vec2 id = floor(c);
		vec2 f = fract(c);
		vec2 fw = max(fwidth(c), vec2(1e-4));
		float far_fade = clamp((max(fw.x, fw.y) - 0.08) * 6.0, 0.0, 1.0);
		vec2 aa = fw * 0.75;
		// Panel seams and a darker plinth.
		float seam = max(1.0 - smoothstep(0.0, 0.02 + aa.x, f.x), 1.0 - smoothstep(0.0, 0.02 + aa.y, f.y));
		vec3 wall = COLOR.rgb * (1.0 - 0.07 * seam * (1.0 - far_fade));
		wall *= mix(0.72, 1.0, smoothstep(0.6, 0.75, UV.y));
		float h = hash12(id + floor(COLOR.rg * 97.0));
		vec3 glass = mix(glass_dark, glass_light, h);
		glass = mix(glass, vec3(0.5, 0.42, 0.32), step(0.88, h)); // curtains
		float win = box_mask(f, vec2(0.27, 0.3), vec2(0.73, 0.8), aa);
		float sill = box_mask(f, vec2(0.25, 0.26), vec2(0.75, 0.3), aa);
		win *= step(0.75, UV.y); // no windows in the plinth
		vec3 near_col = mix(wall, glass, win);
		near_col = mix(near_col, vec3(0.85), sill * (1.0 - win) * 0.6);
		vec3 avg = mix(wall, mix(glass_dark, glass_light, 0.5), 0.2);
		alb = mix(near_col, avg, far_fade);
		rough = mix(0.88, 0.15, win * (1.0 - far_fade));
		spec = mix(0.3, 0.65, win * (1.0 - far_fade));
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;
}
