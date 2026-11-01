shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
// Heavy woollen or waxed cloth hanging from a hook: soft vertical folds gathering towards the top,
// a faint weave, and a darker hem.
uniform vec3 base_color : source_color = vec3(0.24, 0.19, 0.12);
uniform float weave = 1.0;
uniform float sheen = 0.0;          // waxed cotton catches the light
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	float folds = sin(lpos.x * 55.0 + sin(lpos.y * 6.0) * 1.2) * 0.5 + 0.5;
	folds = mix(folds, 0.5, smoothstep(-0.5, 0.0, lpos.y) * 0.6);   // pulled flatter near the collar
	float w = fbm3(lpos * 240.0) * weave;
	vec3 c = base_color * (0.78 + 0.32 * folds) * (0.92 + 0.12 * w);
	c *= 1.0 - smoothstep(-0.35, -0.48, lpos.y) * 0.18;
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.45, sheen);
	SPECULAR = mix(0.25, 0.5, sheen);
	NORMAL = bump_normal(NORMAL, VERTEX, folds * 0.004 + w * 0.0004, 1.0);
}
