shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 tile_color : source_color = vec3(0.06, 0.25, 0.16);
uniform vec3 grout_color : source_color = vec3(0.75, 0.72, 0.62);
uniform vec2 tile_size = vec2(0.15, 0.075);
uniform float glaze = 0.12;
uniform float grout_width = 0.006;
uniform int axis = 0; // 0: XY plane (walls facing z), 1: ZY plane (walls facing x), 2: XZ (floors)
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = axis == 0 ? wpos.xy : (axis == 1 ? wpos.zy : wpos.xz);
	vec2 q = p / tile_size;
	q.x += mod(floor(q.y), 2.0) * 0.5;
	vec2 f = abs(fract(q) - 0.5);
	vec2 gw = vec2(grout_width) / tile_size;
	float grout = max(smoothstep(0.5 - gw.x, 0.5 - gw.x * 0.3, f.x), smoothstep(0.5 - gw.y, 0.5 - gw.y * 0.3, f.y));
	float id = hash12(floor(q));
	vec3 c = tile_color * (0.85 + 0.3 * id);
	float dome = (1.0 - max(f.x, f.y) * 2.0);
	float h = -grout * 0.002 + dome * 0.0008;
	ALBEDO = mix(c, grout_color, grout);
	ROUGHNESS = mix(glaze, 0.9, grout);
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
	SPECULAR = 0.6;
}
