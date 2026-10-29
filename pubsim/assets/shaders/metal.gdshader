shader_type spatial;
// Polished or aged metal (brass, chrome, iron) with fingerprints, faint scratches and tarnish.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.85, 0.62, 0.28);
uniform float roughness_base = 0.22;
uniform float tarnish = 0.15;
uniform vec3 tarnish_color : source_color = vec3(0.25, 0.2, 0.1);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float smudge = smoothstep(0.5, 0.75, fbm3(wpos * 18.0));
	float scratch = smoothstep(0.985, 1.0, sin(wpos.x * 900.0 + fbm3(wpos * 30.0) * 40.0)) * 0.4;
	float t = smoothstep(0.45, 0.8, fbm3(wpos * 5.0 + 3.0)) * tarnish;
	ALBEDO = mix(base_color, tarnish_color, t);
	METALLIC = 1.0 - t * 0.5;
	ROUGHNESS = clamp(roughness_base + smudge * 0.18 + t * 0.35 + scratch * 0.2, 0.04, 1.0);
}
