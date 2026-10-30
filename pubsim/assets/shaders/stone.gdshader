shader_type spatial;
// Rubble stone in rough courses with recessed mortar, or cobbles; optional wetness and soot.
// axis 0: XY plane, 1: ZY, 2: XZ (floors), 3: follow each face (boxes such as a fireplace).
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 stone_a : source_color = vec3(0.35, 0.34, 0.32);
uniform vec3 stone_b : source_color = vec3(0.22, 0.21, 0.2);
uniform vec3 mortar : source_color = vec3(0.12, 0.11, 0.1);
uniform float scale = 3.0;
uniform float wetness = 0.0;
uniform float soot = 0.0;          // darkening up from the bottom of the face (a fireplace)
uniform float soot_top = 1.3;
uniform int axis = 2;
uniform int dressed = 0;           // 1: squared blocks laid in courses (a cut-stone fireplace)
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	int ax = axis;
	if (ax == 3) {
		vec3 an = abs(wnorm);
		ax = an.y > max(an.x, an.z) ? 2 : (an.x > an.z ? 1 : 0);
	}
	vec2 p = ax == 0 ? wpos.xy : (ax == 1 ? wpos.zy : wpos.xz);
	// walls are laid in courses: stones wider than they are tall
	vec2 sp = ax == 2 ? p * scale : p * vec2(scale * 0.62, scale);
	vec3 v = voronoi_edge2(sp);
	if (dressed == 1) {
		// courses of differing height, blocks of differing length, joints staggered row to row
		float course = 0.21;
		float row = floor(p.y / course);
		float rh = hash12(vec2(row, 5.3));
		float blen = 0.32 + 0.22 * rh;
		float bx = (p.x + hash12(vec2(row, 1.7)) * blen) / blen;
		float col = floor(bx);
		vec2 f = vec2(fract(bx) * blen, fract(p.y / course) * course);
		float ex = min(f.x, blen - f.x);
		float ey = min(f.y, course - f.y);
		v.x = min(ex, ey) * scale;      // in the same units as the rubble cells
		v.y = hash12(vec2(col, row) + 11.0);
	}
	float joint = 1.0 - smoothstep(0.035, 0.085, v.x);
	float n = fbm3(wpos * 9.0);
	float tint = hash12(vec2(v.y * 91.0, 3.1));
	vec3 c = mix(stone_a, stone_b, v.y) * (0.78 + 0.38 * n);
	c *= mix(vec3(1.0), vec3(1.08, 0.98, 0.88), step(0.7, tint));   // the odd warmer stone
	c = mix(c, mortar * (0.8 + 0.4 * n), joint);
	float puddle = smoothstep(0.55, 0.7, fbm3(vec3(wpos.xz * 0.7, 1.0))) * wetness;
	float s = soot * (1.0 - smoothstep(0.0, soot_top, wpos.y)) * (0.6 + 0.5 * fbm3(wpos * 3.0));
	c *= 1.0 - clamp(s, 0.0, 0.85);
	ALBEDO = c * (1.0 - wetness * 0.35);
	ROUGHNESS = mix(mix(0.88, 0.3, wetness), 0.05, puddle) + joint * 0.08;
	SPECULAR = 0.45 + wetness * 0.3;
	// each stone's face is gently domed, the joints sunk between them
	float h = smoothstep(0.0, 0.18, v.x) * 0.007 + n * 0.0025 * (1.0 - puddle);
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
