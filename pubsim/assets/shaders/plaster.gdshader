shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.62, 0.52, 0.36);
uniform float stain = 0.25;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = fbm3(wpos * 3.0);
	float s = fbm3(wpos * 0.6 + 4.0);
	vec3 c = base_color * (0.9 + 0.2 * n);
	c = mix(c, c * vec3(0.8, 0.7, 0.5), smoothstep(0.45, 0.8, s) * stain);
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
