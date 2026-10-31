shader_type spatial;
// A cream lace café curtain: a fine open net with a scatter of tiny motifs, a deep band of denser
// lace along a scalloped hem, and soft vertical folds, with lamplight showing through.
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec3 color : source_color = vec3(0.9, 0.86, 0.77);
float motif(vec2 g) {
	vec2 c = fract(g) - 0.5;
	float r = length(c);
	float ang = atan(c.y, c.x);
	float petal = smoothstep(0.025, 0.0, r - 0.22 - 0.07 * cos(ang * 6.0));
	float hole = smoothstep(0.03, 0.0, r - 0.09);
	return petal * (1.0 - hole * 0.8);
}
void fragment() {
	float net = 1.0 - smoothstep(0.0, 0.22, min(abs(fract(UV.x * 260.0) - 0.5), abs(fract(UV.y * 95.0) - 0.5)) * 2.0);
	// sparse tiny sprigs in the plain part
	vec2 g = UV * vec2(56.0, 19.0);
	g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
	float sprig = motif(g) * 0.5;
	// the deep border: a denser band of larger motifs above the hem
	float band = smoothstep(0.66, 0.7, UV.y);
	float border = motif(UV * vec2(30.0, 30.0) + vec2(0.0, 0.5)) * band;
	float hem_wave = 0.95 + 0.035 * sin(UV.x * 3.1416 * 30.0);
	float inside = step(UV.y, hem_wave);
	float a = clamp(0.12 + net * 0.14 + sprig * 0.35 + border * 0.55 + band * 0.12, 0.0, 0.75) * inside;
	float fold = 0.86 + 0.14 * sin(UV.x * 42.0 + sin(UV.x * 9.0) * 1.5);
	ALBEDO = color * fold;
	EMISSION = color * 0.05 * fold;
	ROUGHNESS = 0.9;
	ALPHA = a;
}
