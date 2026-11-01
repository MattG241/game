shader_type spatial;
// Upholstery leather: fine grain, creases, and a soft sheen worn shiny where people sit.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.32, 0.06, 0.05);
uniform float wear = 0.5;
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	float grain = fbm3(lpos * 160.0);
	float crease = smoothstep(0.04, 0.0, abs(fbm3(lpos * 9.0) - 0.5));
	float rub = smoothstep(0.35, 0.8, fbm3(lpos * 3.0 + 2.0)) * wear;
	vec3 c = base_color * (0.85 + 0.25 * grain);
	c = mix(c, c * 0.6, crease * 0.6);
	c = mix(c, c * 1.35 + vec3(0.02), rub * 0.6);
	ALBEDO = c;
	ROUGHNESS = clamp(0.55 - rub * 0.3 + crease * 0.2, 0.15, 0.9);
	SPECULAR = 0.5;
	float h = grain * 0.0004 - crease * 0.0012;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
