shader_type spatial;
// A flickering turf flame on a vertical quad: tapered tongue shape, rising noise, white-hot core
// and red edges. Added on top of the scene, so a few crossed quads read as a living fire.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://assets/shaders/noise.gdshaderinc"
uniform float seed = 0.0;
uniform float speed = 1.0;
uniform float intensity = 1.0;
void fragment() {
	float y = 1.0 - UV.y;                 // 0 at the base, 1 at the tip
	float t = TIME * speed + seed * 7.0;
	float n = fbm3(vec3(UV.x * 3.0 + seed, y * 2.2 - t * 1.4, t * 0.25));
	float n2 = fbm3(vec3(UV.x * 8.0, y * 6.0 - t * 3.2, seed + t * 0.5));
	float x = (UV.x - 0.5) * 2.0 + (n - 0.5) * 0.9 * y;
	float width = mix(0.85, 0.04, pow(y, 0.75));
	float body = smoothstep(width, width * 0.25, abs(x));
	float top = smoothstep(1.0, 0.35, y + (n2 - 0.5) * 0.45);
	float f = body * top * smoothstep(0.0, 0.06, y);
	vec3 col = mix(vec3(0.75, 0.1, 0.01), vec3(1.0, 0.45, 0.06), smoothstep(0.05, 0.45, f));
	col = mix(col, vec3(1.0, 0.86, 0.5), smoothstep(0.5, 0.95, f));
	ALBEDO = col * intensity * (0.6 + f * 1.6);
	ALPHA = clamp(f * 1.2, 0.0, 1.0);
}
