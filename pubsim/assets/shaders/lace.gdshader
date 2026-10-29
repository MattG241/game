shader_type spatial;
// A cream lace café curtain: a faint fine net, small flower sprigs in staggered rows, a scalloped
// hem and soft vertical folds, with lamplight showing through.
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec3 color : source_color = vec3(0.93, 0.89, 0.8);
void fragment() {
	vec2 g = UV * vec2(34.0, 11.0);
	g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
	vec2 c = fract(g) - 0.5;
	float ang = atan(c.y, c.x);
	float petal = smoothstep(0.03, 0.0, length(c) - 0.13 - 0.06 * cos(ang * 5.0));
	float centre = smoothstep(0.05, 0.03, length(c));
	float net = 1.0 - smoothstep(0.0, 0.18, min(abs(fract(UV.x * 220.0) - 0.5), abs(fract(UV.y * 80.0) - 0.5)) * 2.0);
	float hem_wave = 0.93 + 0.03 * sin(UV.x * 160.0);
	float inside = step(UV.y, hem_wave);
	float a = clamp(0.1 + net * 0.12 + petal * 0.45 + centre * 0.3, 0.0, 0.75) * inside;
	float fold = 0.85 + 0.15 * sin(UV.x * 48.0);
	ALBEDO = color * fold;
	EMISSION = color * 0.12 * fold;
	ROUGHNESS = 0.9;
	ALPHA = a;
}
