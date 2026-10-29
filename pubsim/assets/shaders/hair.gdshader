shader_type spatial;
// Hair, beards and caps: fine strands running down the head with a soft sheen.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 color : source_color = vec3(0.25, 0.15, 0.08);
uniform float strands = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float a = atan(lp.x, lp.z);
	float s = fbm3(vec3(a * 30.0, lp.y * 6.0, 0.0)) * 0.6 + fbm3(vec3(a * 90.0, lp.y * 14.0, 3.0)) * 0.4;
	vec3 c = color * mix(1.0, 0.7 + 0.6 * s, strands);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.45, strands);
	SPECULAR = 0.5;
	RIM = 0.4;
	RIM_TINT = 0.8;
	NORMAL = bump_normal(NORMAL, VERTEX, s * 0.0015 * strands, 1.0);
}
