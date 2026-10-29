shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Pint glass: fresnel, smudges, condensation, and the GALAGERS print wrapped round the glass.
#include "res://assets/shaders/noise.gdshaderinc"
uniform float dirt = 0.0;
uniform float emblem = 1.0;            // 0 hides the print (tumblers)
uniform sampler2D print_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float print_y0 = 0.05;         // printed band, metres from the glass base
uniform float print_y1 = 0.14;
uniform float print_half_angle = 0.95; // radians either side of the front
uniform float cold = 0.0;              // condensation when a cold pint is in it (0..1)
uniform float fill_y = 0.0;            // condensation only forms below the drink
uniform vec3 tint : source_color = vec3(0.9, 0.95, 0.95);
varying vec3 p;
void vertex() { p = VERTEX; }

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float a = 0.06 + fres * 0.5;
	vec3 col = tint;
	float rough = 0.04;
	// smudges on a used glass
	float sm = fbm3(p * 90.0);
	float d = dirt * smoothstep(0.35, 0.75, sm);
	col = mix(col, vec3(0.55, 0.5, 0.42), d);
	a += d * 0.45;
	rough += d * 0.5;
	// condensation: a fine mist with larger beads, only where the cold drink is
	if (cold > 0.01 && p.y < fill_y) {
		float ang = atan(p.x, p.z);
		vec2 dp = vec2(ang * 0.04, p.y) * 900.0;
		vec2 cell = voronoi2(dp);
		float bead = 1.0 - smoothstep(0.08, 0.2, cell.x);
		bead *= step(0.55, cell.y);
		float mist = 0.25 + 0.15 * vnoise3(p * 400.0);
		float edge = smoothstep(0.0, 0.01, fill_y - p.y);
		a += (mist * 0.25 + bead * 0.45) * cold * edge;
		col = mix(col, vec3(0.95, 0.97, 1.0), (mist * 0.3 + bead * 0.5) * cold * edge);
		rough = mix(rough, 0.35, mist * cold * edge);
	}
	// printed brand, mapped round the curve of the glass
	if (emblem > 0.5) {
		float ang = atan(p.x, p.z);
		vec2 uv = vec2((ang + print_half_angle) / (2.0 * print_half_angle), (print_y1 - p.y) / (print_y1 - print_y0));
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			vec4 pr = texture(print_tex, uv);
			col = mix(col, pr.rgb, pr.a);
			a = mix(a, 0.97, pr.a);
			rough = mix(rough, 0.3, pr.a);
		}
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
