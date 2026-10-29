shader_type spatial;
render_mode cull_disabled;
// Parametric stout/beer liquid. The mesh is the inside of the glass; everything
// above a world-horizontal plane is discarded and back faces draw the surface cap.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 up_local = vec3(0.0, 1.0, 0.0);   // world up in mesh space (includes slosh)
uniform float height = 0.15;                    // inner height of the glass
uniform float level_body = 0.0;                 // top of liquid (fraction of height)
uniform float level_total = 0.0;                // top of foam head
uniform float dark_frac = 0.0;                  // settled (dark) part from the bottom
uniform float lace_top = 0.0;                   // foam lacing left on the walls up to here
uniform vec3 body_color : source_color = vec3(0.04, 0.015, 0.01);
uniform vec3 cascade_color : source_color = vec3(0.42, 0.26, 0.14);
uniform vec3 foam_color : source_color = vec3(0.93, 0.86, 0.72);
uniform float cascade_strength = 1.0;
uniform float clarity = 0.0;                    // 1 for lager-like translucent glow

varying vec3 p;
void vertex() {
	p = VERTEX;
}

float plane_d(float frac) {
	return dot(p - vec3(0.0, frac * height, 0.0), normalize(up_local));
}

void fragment() {
	float d_total = plane_d(level_total);
	float d_body = plane_d(level_body);
	if (d_total > 0.0) {
		// above the drink: optional foam lacing rings left behind while drinking
		float lace_d = plane_d(lace_top);
		if (lace_d > 0.0 || !FRONT_FACING) {
			discard;
		}
		float ang = atan(p.x, p.z);
		float ring = vnoise3(vec3(ang * 9.0, p.y * 260.0, 0.0));
		float lace = step(0.58, ring) * step(0.4, vnoise3(vec3(ang * 60.0, p.y * 900.0, 1.0)));
		if (lace < 0.5) {
			discard;
		}
		ALBEDO = foam_color * 0.95;
		ROUGHNESS = 0.6;
	} else if (!FRONT_FACING) {
		// surface cap seen from above
		float head = level_total - level_body;
		vec3 top;
		if (head > 0.004) {
			float bub = vnoise3(p * 900.0 + vec3(0.0, TIME * 0.05, 0.0));
			top = foam_color * (0.92 + 0.08 * bub);
			EMISSION = foam_color * 0.12;
			ROUGHNESS = 0.55;
		} else {
			bool settled = dark_frac >= level_body - 0.002;
			top = settled ? body_color * 1.4 : cascade_color * 0.9;
			ROUGHNESS = 0.08;
		}
		ALBEDO = top;
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(up_local, 0.0)).xyz);
	} else if (d_body > 0.0) {
		// side of the foam head: fine bubbles, slightly darker at the base
		float bub = vnoise3(p * 700.0);
		float base_t = clamp(-d_total / max((level_total - level_body) * height, 0.001), 0.0, 1.0);
		ALBEDO = foam_color * (0.82 + 0.1 * bub + 0.08 * (1.0 - base_t));
		EMISSION = foam_color * 0.1;
		ROUGHNESS = 0.6;
	} else {
		float d_dark = plane_d(dark_frac);
		vec3 c = body_color;
		if (d_dark > 0.0) {
			// unsettled cascade: creamy tan with bubbles drifting down the glass walls
			float t = TIME;
			float ang = atan(p.x, p.z);
			float streak = vnoise3(vec3(ang * 14.0, p.y * 160.0 + t * 9.0, t * 0.7));
			float fine = vnoise3(vec3(ang * 40.0, p.y * 420.0 + t * 14.0, 3.0));
			float mixv = clamp(0.55 + 0.35 * streak + 0.25 * fine, 0.0, 1.0);
			float edge = smoothstep(0.0, 0.012, d_dark);
			vec3 casc = mix(cascade_color * 0.65, cascade_color * 1.15, mixv);
			c = mix(body_color * 1.6, casc, edge * cascade_strength);
		} else {
			// settled body: ruby glints near the edges
			float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
			c = mix(body_color, body_color * vec3(4.0, 1.4, 0.9), rim * 0.6);
		}
		float glow = clarity * (0.35 + 0.15 * vnoise3(vec3(p.xz * 200.0, p.y * 60.0 - TIME * 2.0)));
		ALBEDO = c;
		EMISSION = c * glow;
		ROUGHNESS = 0.12;
		SPECULAR = 0.6;
	}
}
