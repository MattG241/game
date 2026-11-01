shader_type spatial;
// A sleeve or trouser leg that ends in skin (wrist) or a shoe (ankle): cloth above split_y,
// the "end" colour below, with an optional cuff band. Limb-local coordinates.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 cloth : source_color = vec3(0.3, 0.3, 0.35);
uniform int pattern = 0;
uniform vec3 end_color : source_color = vec3(0.9, 0.72, 0.6);
uniform float end_rough = 0.55;
uniform float split_y = -0.255;
uniform vec3 cuff_color : source_color = vec3(0.9, 0.9, 0.88);
uniform float cuff = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
vec3 weave(vec3 base, vec3 p) {
	if (pattern == 1) {
		float hb = abs(fract(p.y * 60.0 + abs(fract(p.x * 30.0 + p.z * 30.0) - 0.5) * 1.6) - 0.5);
		return base * (0.84 + 0.28 * hb);
	} else if (pattern == 2) {
		float rib = abs(sin((p.x + p.z) * 160.0));
		return base * (0.82 + 0.25 * rib);
	} else if (pattern == 3) {
		float tw = abs(fract((p.x + p.y + p.z) * 120.0) - 0.5);
		return base * (0.85 + 0.25 * tw + 0.12 * fbm3(p * 40.0));
	}
	return base * (0.9 + 0.18 * fbm3(p * 90.0));
}
void fragment() {
	float below = step(lp.y, split_y);
	float band = cuff * step(split_y, lp.y) * step(lp.y, split_y + 0.022);
	vec3 c = weave(cloth, lp);
	c = mix(c, cuff_color, band);
	c = mix(c, end_color, below);
	ALBEDO = c;
	ROUGHNESS = mix(0.9, end_rough, below);
	SPECULAR = mix(0.25, 0.4, below);
	RIM = mix(0.35, 0.25, below);
	RIM_TINT = 0.6;
}
