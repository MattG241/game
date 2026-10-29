shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Glass shell with fresnel, dirt smudges and the original Kilbrack Knot emblem.
#include "res://assets/shaders/noise.gdshaderinc"
uniform float dirt = 0.0;
uniform float emblem = 1.0;           // 0 hides the emblem
uniform float emblem_y = 0.098;       // emblem centre height (mesh space)
uniform float emblem_r = 0.016;
uniform vec3 emblem_color : source_color = vec3(0.95, 0.88, 0.62);
uniform vec3 tint : source_color = vec3(0.9, 0.95, 0.95);
varying vec3 p;
void vertex() { p = VERTEX; }

float sd_seg(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float a = 0.07 + fres * 0.55;
	vec3 col = tint;
	// smudges
	float sm = fbm3(p * 90.0);
	float d = dirt * smoothstep(0.35, 0.75, sm);
	col = mix(col, vec3(0.55, 0.5, 0.42), d);
	a += d * 0.45;
	// emblem: the Kilbrack Knot, a ring split by a horizontal bar
	if (emblem > 0.5) {
		float ang = atan(p.x, p.z);
		float rad = length(p.xz);
		vec2 q = vec2(ang * rad, p.y - emblem_y);
		float ring = abs(length(q) - emblem_r) - 0.0016;
		float bar = sd_seg(q, vec2(-emblem_r * 1.55, 0.0), vec2(emblem_r * 1.55, 0.0)) - 0.0009;
		// with a diamond knot at the centre
		float diamond = (abs(q.x) + abs(q.y)) - emblem_r * 0.32;
		float e = min(min(ring, bar), diamond);
		float m = 1.0 - smoothstep(0.0, 0.0006, e);
		m *= step(abs(ang), 1.2);
		col = mix(col, emblem_color, m);
		a = mix(a, 0.95, m);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.04 + d * 0.5;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
