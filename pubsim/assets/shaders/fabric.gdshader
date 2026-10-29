shader_type spatial;
// Clothing: plain wool, tweed herringbone, cable knit or denim, worked out from the mesh's own
// position so no UVs are needed. A soft sheen at grazing angles makes cloth read as cloth.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.3, 0.3, 0.35);
uniform int pattern = 0;          // 0 wool, 1 tweed, 2 cable knit, 3 denim
uniform float scale = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 p = lp * scale;
	vec3 c = base_color;
	float h = 0.0;
	if (pattern == 1) {
		float hb = abs(fract(p.y * 60.0 + abs(fract(p.x * 30.0) - 0.5) * 1.6) - 0.5);
		float fleck = step(0.86, hash13(floor(p * 220.0)));
		c *= 0.82 + 0.3 * hb;
		c = mix(c, c * vec3(1.6, 1.3, 1.0), fleck * 0.5);
		h = hb * 0.0004;
	} else if (pattern == 2) {
		float col = fract(p.x * 18.0 + p.z * 18.0);
		float cable = abs(sin((p.y * 40.0) + (col > 0.5 ? 1.6 : 0.0)));
		float rib = smoothstep(0.1, 0.0, abs(col - 0.5) - 0.38);
		c *= 0.78 + 0.32 * cable * (1.0 - rib * 0.5);
		h = cable * 0.0012 - rib * 0.0008;
	} else if (pattern == 3) {
		float twill = abs(fract((p.x + p.y) * 120.0) - 0.5);
		c *= 0.85 + 0.25 * twill + 0.15 * fbm3(p * 40.0);
		h = twill * 0.0002;
	} else {
		float n = fbm3(p * 90.0);
		c *= 0.88 + 0.22 * n;
		h = n * 0.0003;
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	RIM = 0.35;
	RIM_TINT = 0.6;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
