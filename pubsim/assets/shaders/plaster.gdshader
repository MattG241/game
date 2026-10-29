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
	float crack = smoothstep(0.035, 0.0, abs(fbm3(wpos * 1.7 + 9.0) - 0.5)) * smoothstep(0.55, 0.75, s);
	c *= 1.0 - crack * 0.25;
	float h = fbm3(wpos * 9.0) * 0.0025 + fbm3(wpos * 35.0) * 0.0006 - crack * 0.001;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
