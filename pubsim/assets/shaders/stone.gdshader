shader_type spatial;
// Rough stone blocks / cobbles with optional wetness.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 stone_a : source_color = vec3(0.35, 0.34, 0.32);
uniform vec3 stone_b : source_color = vec3(0.22, 0.21, 0.2);
uniform vec3 mortar : source_color = vec3(0.12, 0.11, 0.1);
uniform float scale = 3.0;
uniform float wetness = 0.0;
uniform int axis = 2;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = axis == 0 ? wpos.xy : (axis == 1 ? wpos.zy : wpos.xz);
	vec2 v = voronoi2(p * scale);
	float edge = smoothstep(0.32, 0.5, v.x);
	float n = fbm3(wpos * 8.0);
	vec3 c = mix(stone_a, stone_b, v.y) * (0.8 + 0.4 * n);
	c = mix(c, mortar, edge);
	float puddle = smoothstep(0.55, 0.7, fbm3(vec3(wpos.xz * 0.7, 1.0))) * wetness;
	ALBEDO = c * (1.0 - wetness * 0.35);
	ROUGHNESS = mix(mix(0.85, 0.3, wetness), 0.05, puddle) + edge * 0.1;
	SPECULAR = 0.5 + wetness * 0.3;
}
