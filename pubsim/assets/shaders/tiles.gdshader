shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
// Glazed tiles (or brick with a matt glaze): pillowed faces, uneven colour, a fine craze in old
// glaze, chipped corners and grubby grout; room_ao darkens them into corners and along the floor.
uniform vec3 tile_color : source_color = vec3(0.06, 0.25, 0.16);
uniform vec3 grout_color : source_color = vec3(0.75, 0.72, 0.62);
uniform vec2 tile_size = vec2(0.15, 0.075);
uniform float glaze = 0.12;
uniform float grout_width = 0.006;
uniform float age = 0.0;          // crazing, chips and dirt
uniform float room_ao = 0.0;
uniform vec4 room_box = vec4(-7.0, -5.0, 7.0, 5.0);
uniform float room_h = 3.3;
uniform int axis = 0; // 0: XY plane (walls facing z), 1: ZY plane (walls facing x), 2: XZ (floors)
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 p = axis == 0 ? wpos.xy : (axis == 1 ? wpos.zy : wpos.xz);
	vec2 q = p / tile_size;
	q.x += mod(floor(q.y), 2.0) * 0.5;
	vec2 f = abs(fract(q) - 0.5);
	vec2 gw = vec2(grout_width) / tile_size;
	float grout = max(smoothstep(0.5 - gw.x, 0.5 - gw.x * 0.3, f.x), smoothstep(0.5 - gw.y, 0.5 - gw.y * 0.3, f.y));
	float id = hash12(floor(q));
	float id2 = hash12(floor(q) + 7.7);
	vec3 c = tile_color * (0.82 + 0.34 * id);
	c *= mix(vec3(1.0), vec3(1.05, 1.0, 0.9), step(0.8, id2));         // the odd tile from another batch
	float edge = max(f.x, f.y) * 2.0;                                   // 0 at the centre, 1 at the edge
	float dome = 1.0 - edge * edge;
	float n = vnoise3(wpos * 14.0);       // one octave is plenty at this scale (phones)
	// crazing in the glaze, and chips knocked off the corners
	float craze = (1.0 - smoothstep(0.0, 0.03, voronoi_edge2(p * 28.0 + id * 13.0).x)) * age;
	// a chip off the odd corner or edge: a random quarter of the odd tile
	float chip = smoothstep(0.86, 0.95, edge) * step(0.82, hash12(floor(q * 2.0) + 5.1)) * age;
	c *= 1.0 - craze * 0.18;
	vec3 grout_c = grout_color * mix(1.0, 0.55 + 0.35 * n, age);
	float g = max(grout, chip * 0.8);
	vec3 col = mix(c, grout_c, g);
	if (room_ao > 0.0) {
		col *= mix(1.0, room_occlusion(wpos, wnorm, room_box, room_h), room_ao);
		col *= 1.0 - 0.25 * room_ao * exp(-max(1.15 - wpos.y, 0.0) * 18.0);    // under the dado rail
	}
	float h = -grout * 0.002 + dome * 0.0011 - chip * 0.001 - craze * 0.00015;
	ALBEDO = col;
	ROUGHNESS = mix(glaze + craze * 0.15 + n * 0.08 * age, 0.92, g);
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
	SPECULAR = mix(0.6, 0.3, g);
}
