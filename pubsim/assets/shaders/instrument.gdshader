shader_type spatial;
// Varnished wood, ebony, skins and accordion finishes for the session instruments.
// Works in each mesh's local frame (see tools/gen_instruments.py).
// mode: 0 plain, 1 fiddle body, 2 guitar body, 3 skin, 4 ebony fittings, 5 accordion end, 6 bellows, 7 banjo body
#include "res://assets/shaders/noise.gdshaderinc"
uniform int mode = 0;
uniform vec3 base_color : source_color = vec3(0.5, 0.2, 0.06);
uniform vec3 accent_color : source_color = vec3(0.85, 0.65, 0.3);
uniform float frets = 0.0;        // fittings: draw frets along +X from `nut_x` (scale length in metres)
uniform float nut_x = 0.66;
uniform float mottle = 0.5;       // skins
uniform float celtic = 0.0;       // skins: painted knot ring
varying vec3 lp;
varying vec3 ln;
void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float ell(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}
float smin_(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}
float fiddle_outline(vec2 xz) {
	float d = smin_(ell(xz, vec2(0.0, 0.092), vec2(0.102, 0.103)), ell(xz, vec2(0.0, -0.088), vec2(0.083, 0.078)), 0.05);
	for (int s = -1; s <= 1; s += 2) {
		float c = ell(xz, vec2(float(s) * 0.098, 0.004), vec2(0.036, 0.05));
		d = -smin_(-d, c, 0.012);
	}
	return d;
}

void fragment() {
	vec3 col = base_color;
	float rough = 0.3;
	float spec = 0.5;
	float h = 0.0;
	if (mode == 1) {
		// fiddle: amber varnish, darker at the edges and worn lighter in the middle
		float d = fiddle_outline(lp.xz);
		bool top = ln.y > 0.4 && lp.z > -0.165;
		bool back = ln.y < -0.4 && lp.z > -0.165;
		float grain = fbm3(vec3(lp.x * 260.0, lp.y * 30.0, lp.z * 8.0));
		col = mix(base_color * 0.55, base_color * 1.25, smoothstep(-0.002, -0.05, d));
		if (top) {
			col *= 0.9 + 0.2 * grain;
			// purfling: a fine black-white-black line just inside the edge
			float pf = abs(d + 0.0045);
			col = mix(col, vec3(0.03), smoothstep(0.0012, 0.0004, pf));
			// f-holes
			for (int s = -1; s <= 1; s += 2) {
				float zz = lp.z - 0.012;
				float fx = float(s) * (0.041 + 0.007 * sin(zz * 42.0)) ;
				float stroke = abs(lp.x - fx);
				float along = smoothstep(0.042, 0.036, abs(zz));
				float hole = smoothstep(0.0018, 0.0009, stroke) * along;
				float eyes = smoothstep(0.0038, 0.0028, length(vec2(lp.x - float(s) * (0.041 + 0.007 * sin(0.042 * 42.0)), zz - 0.04)));
				eyes = max(eyes, smoothstep(0.0034, 0.0024, length(vec2(lp.x - float(s) * (0.041 + 0.007 * sin(-0.042 * 42.0)), zz + 0.04))));
				col = mix(col, vec3(0.015, 0.008, 0.004), max(hole, eyes));
			}
		} else if (back) {
			// flamed maple
			float flame = sin(lp.z * 260.0 + fbm3(lp * 40.0) * 6.0);
			col *= 0.85 + 0.25 * smoothstep(-0.2, 0.8, flame);
		} else {
			col *= 0.85 + 0.2 * grain;
		}
		// bridge: plain pale maple
		if (lp.y > 0.0255 && abs(lp.z - 0.035) < 0.0035 && abs(lp.x) < 0.022) {
			col = vec3(0.72, 0.58, 0.38);
			rough = 0.6;
		}
		rough = 0.22 + 0.15 * (1.0 - grain);
		spec = 0.6;
	} else if (mode == 2 || mode == 7) {
		bool top = ln.z < -0.6 && lp.z < -0.04 && lp.x < 0.27;
		if (mode == 2 && top) {
			// spruce top, rosette, soundhole
			float lines = sin(lp.y * 900.0 + fbm3(lp * 30.0) * 3.0);
			col = accent_color * (0.92 + 0.08 * lines);
			float r = length(lp.xy - vec2(0.045, 0.0));
			col = mix(col, vec3(0.12, 0.06, 0.03), smoothstep(0.004, 0.0, abs(r - 0.056)) * 0.9);
			col = mix(col, vec3(0.7, 0.55, 0.3), smoothstep(0.003, 0.0, abs(r - 0.05)) * 0.6);
			col = mix(col, vec3(0.008), smoothstep(0.0445, 0.0435, r));
			// pickguard
			float pg = ell(lp.xy, vec2(-0.005, -0.075), vec2(0.06, 0.04));
			if (pg < 0.0 && r > 0.06) col = mix(col, vec3(0.05, 0.03, 0.02), 0.85);
			rough = 0.25;
		} else {
			float grain = fbm3(vec3(lp.x * 12.0, lp.y * 200.0, lp.z * 200.0));
			col = base_color * (0.8 + 0.35 * grain);
			rough = 0.28;
		}
		spec = 0.55;
	} else if (mode == 3) {
		// skin: cream goatskin with darker mottling and a ring of knotwork
		float m = fbm3(lp * 18.0) * 0.6 + fbm3(lp * 70.0) * 0.4;
		col = accent_color * (1.0 - mottle * 0.35 * smoothstep(0.35, 0.8, m));
		float r = length(lp.xy);
		col = mix(col, col * 0.75, smoothstep(0.17, 0.22, r));
		if (celtic > 0.0) {
			float a = atan(lp.y, lp.x);
			float band = smoothstep(0.012, 0.009, abs(r - 0.155));
			float knot = abs(sin(a * 12.0 + sin((r - 0.155) * 220.0) * 1.6));
			float strand = smoothstep(0.5, 0.25, knot) * band;
			col = mix(col, base_color, max(strand, band * 0.25) * celtic);
			float inner = smoothstep(0.0025, 0.001, abs(r - 0.135)) + smoothstep(0.0025, 0.001, abs(r - 0.175));
			col = mix(col, base_color, clamp(inner, 0.0, 1.0) * celtic);
		}
		rough = 0.75;
		spec = 0.3;
		h = m * 0.0006;
	} else if (mode == 4) {
		col = base_color * (0.8 + 0.4 * fbm3(lp * 120.0));
		rough = 0.35;
		if (frets > 0.0) {
			// frets on the fingerboard: spacing shrinks towards the body
			float dist = nut_x - lp.x;
			if (dist > 0.0 && lp.z < -0.0465) {
				float n = 12.0 * log2(frets / max(frets - dist, 0.001));
				float f = abs(fract(n + 0.5) - 0.5);
				float w = smoothstep(0.06, 0.02, f);
				col = mix(col, vec3(0.75, 0.73, 0.68), w);
				rough = mix(rough, 0.2, w);
				// position dots
				float fi = floor(n + 0.5);
				if ((fi == 3.0 || fi == 5.0 || fi == 7.0 || fi == 9.0 || fi == 12.0) && f > 0.4 && abs(lp.y) < 0.004)
					col = vec3(0.85, 0.82, 0.75);
			}
		}
		spec = 0.5;
	} else if (mode == 5) {
		// accordion end: glossy pearloid with gold trim near the edges and a chrome grille
		float pearl = fbm3(lp * 40.0);
		col = base_color * (0.75 + 0.5 * pearl);
		vec3 e = vec3(0.045, 0.15, 0.09) - abs(lp);
		float edge = min(e.y, e.z);
		col = mix(col, accent_color, smoothstep(0.006, 0.003, abs(edge - 0.012)));
		bool grille = lp.y > -0.01 && lp.y < 0.13 && abs(lp.z) < 0.07 && abs(lp.x) > 0.044;
		if (grille) {
			vec2 g = fract(lp.yz * 70.0) - 0.5;
			float hole = smoothstep(0.32, 0.26, length(g));
			col = mix(vec3(0.75, 0.74, 0.7), vec3(0.05), hole);
			rough = 0.25;
			spec = 0.9;
		} else {
			rough = 0.12;
			spec = 0.65;
		}
	} else if (mode == 6) {
		// bellows: black card with light pleat ridges and metal corners
		float ridge = abs(sin(lp.x * PI / 0.0115));
		col = mix(vec3(0.02), vec3(0.75, 0.7, 0.62), smoothstep(0.92, 1.0, ridge) * 0.7);
		bool corner = abs(lp.y) > 0.115 && abs(lp.z) > 0.058;
		if (corner) col = vec3(0.7, 0.68, 0.62);
		rough = corner ? 0.25 : 0.6;
		spec = corner ? 0.8 : 0.35;
	} else {
		col = base_color * (0.85 + 0.3 * fbm3(lp * 60.0));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (h != 0.0) NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
