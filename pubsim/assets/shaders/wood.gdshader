shader_type spatial;
// Procedural stained oak. Uses object-space position so no UVs are needed.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 dark_color : source_color = vec3(0.14, 0.08, 0.045);
uniform vec3 light_color : source_color = vec3(0.3, 0.19, 0.11);
uniform float grain_scale = 6.0;
uniform float plank_width = 0.0;   // >0 draws plank seams along x every N metres
uniform vec3 grain_dir = vec3(1.0, 0.0, 0.0);
uniform float roughness_base = 0.45;
uniform float wear = 0.0;
uniform bool world_space = false;
varying vec3 pos;
void vertex() {
	pos = world_space ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
}
void fragment() {
	vec3 d = normalize(grain_dir);
	float along = dot(pos, d);
	vec3 u = abs(d.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : normalize(cross(d, vec3(0.0, 1.0, 0.0)));
	vec3 v = cross(d, u);
	vec2 across = vec2(dot(pos, u), dot(pos, v));
	float n = fbm3(vec3(across * grain_scale * 3.0, along * 0.6));
	float rings = sin((across.x * 0.7 + across.y * 1.3) * grain_scale * 10.0 + n * 9.0);
	float g = smoothstep(-0.6, 1.0, rings) * 0.35 + n * 0.65;
	vec3 col = mix(dark_color, light_color, g);
	float rough = roughness_base + (1.0 - g) * 0.15;
	if (plank_width > 0.0) {
		vec3 dd = abs(d) ;
		float cross_coord = dot(pos, vec3(dd.z, 0.0, dd.x));
		float seam = abs(fract(cross_coord / plank_width) - 0.5);
		float s = smoothstep(0.485, 0.5, seam);
		float plank_id = floor(cross_coord / plank_width);
		col *= 0.85 + 0.3 * hash12(vec2(plank_id, 3.0));
		col = mix(col, col * 0.35, s);
	}
	col = mix(col, col * 1.25, wear * fbm3(pos * 2.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}
