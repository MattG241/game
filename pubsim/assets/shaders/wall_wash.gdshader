shader_type spatial;
// The splash of warm light a wall sconce throws on the wall round it: bright at the fitting, a
// scalloped fan up and a fainter one down, fading out. Added on top of the lit wall.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.72, 0.42);
uniform float strength = 0.35;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // -1..1 across, -1 top .. 1 bottom
	p.y = -p.y;                       // +1 at the top
	float up = step(0.0, p.y);
	float spread = mix(0.55, 0.42, up) * (0.25 + abs(p.y) * 0.9);
	float fan = 1.0 - smoothstep(spread * 0.6, spread, abs(p.x));
	float fall = exp(-abs(p.y) * mix(3.2, 2.2, up));
	float core = exp(-dot(p, p) * 14.0) * 0.8;
	float a = (fan * fall * mix(0.45, 1.0, up) + core) * strength;
	ALBEDO = color * a;
}
