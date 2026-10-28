shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Additive animated energy surface (region barriers, cleaning beams, holograms).

uniform vec3 color : source_color = vec3(0.1, 0.8, 1.0);
uniform float intensity = 1.0;
uniform float speed = 1.0;
uniform float bands = 6.0;

void fragment() {
	float t = TIME * speed;
	float b = 0.5 + 0.5 * sin((UV.y * bands - t) * 6.2831);
	float edge = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.6, UV.y);
	float flicker = 0.85 + 0.15 * sin(t * 13.0 + UV.x * 40.0);
	ALBEDO = color * (0.35 + 0.65 * b) * edge * flicker * intensity;
}
