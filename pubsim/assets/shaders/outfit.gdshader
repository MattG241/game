shader_type spatial;
// The torso's clothes, painted from body-space position: trousers and belt below the waist,
// then a jacket over a shirt (style 1), a jumper with a ribbed collar (style 0) or a
// scoop-neck top (style 2). Skin shows at the neck.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 top_color : source_color = vec3(0.2, 0.3, 0.25);
uniform int top_pattern = 0;
uniform vec3 shirt_color : source_color = vec3(0.92, 0.9, 0.86);
uniform vec3 trouser_color : source_color = vec3(0.15, 0.18, 0.3);
uniform int trouser_pattern = 3;
uniform vec3 skin : source_color = vec3(0.9, 0.72, 0.6);
uniform int style = 0;
uniform float belt = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
vec3 weave(vec3 base, int pat, vec3 p) {
	if (pat == 1) {
		float hb = abs(fract(p.y * 60.0 + abs(fract(p.x * 30.0) - 0.5) * 1.6) - 0.5);
		float fleck = step(0.86, hash13(floor(p * 220.0)));
		return mix(base * (0.84 + 0.28 * hb), base * vec3(1.5, 1.3, 1.0), fleck * 0.4);
	} else if (pat == 2) {
		float col = fract(p.x * 14.0);
		float cable = abs(sin(p.y * 46.0 + (col > 0.5 ? 1.6 : 0.0)));
		float rib = smoothstep(0.06, 0.0, abs(col - 0.5) - 0.42);
		return base * (0.8 + 0.28 * cable * (1.0 - rib * 0.6));
	} else if (pat == 3) {
		float tw = abs(fract((p.x + p.y) * 120.0) - 0.5);
		return base * (0.85 + 0.25 * tw + 0.12 * fbm3(p * 40.0));
	}
	return base * (0.9 + 0.18 * fbm3(p * 90.0));
}
void fragment() {
	vec3 c;
	float rough = 0.9;
	float front = step(lp.z, 0.0);
	if (lp.y < 0.9) {
		c = weave(trouser_color, trouser_pattern, lp);
	} else if (lp.y < 0.93 && belt > 0.5) {
		c = vec3(0.12, 0.08, 0.05);
		rough = 0.45;
		if (abs(lp.x) < 0.018 && lp.z < -0.05) { c = vec3(0.7, 0.55, 0.3); rough = 0.3; }
	} else {
		c = weave(top_color, top_pattern, lp);
		if (style == 1) {
			// jacket open over a shirt: a V of shirt with dark lapel edges and a button
			float vw = clamp((lp.y - 1.16) * 0.3, 0.0, 0.065);
			float inside = step(abs(lp.x), vw) * front * step(1.12, lp.y);
			float lapel = step(abs(lp.x), vw + 0.018) * (1.0 - step(abs(lp.x), vw)) * front * step(1.12, lp.y);
			c = mix(c, c * 0.72, lapel);
			c = mix(c, shirt_color * (0.85 + 0.08 * fbm3(lp * 80.0)), inside);
			float btn = step(length(vec2(lp.x + 0.012, lp.y - 1.06)), 0.009) * front;
			c = mix(c, vec3(0.12, 0.1, 0.08), btn);
		} else if (style == 0) {
			float rib = step(1.49, lp.y) * step(lp.y, 1.53);
			c = mix(c, c * (0.75 + 0.25 * abs(sin(atan(lp.x, lp.z) * 40.0))), rib);
		} else {
			float scoop = step(1.38 + pow(lp.x / 0.1, 2.0) * 0.08, lp.y) * front;
			c = mix(c, skin, scoop);
		}
	}
	// the neck is skin above the collar
	float neck = step(1.53, lp.y);
	c = mix(c, skin, neck);
	ALBEDO = c;
	ROUGHNESS = mix(rough, 0.55, neck);
	SPECULAR = 0.25;
	RIM = 0.35;
	RIM_TINT = 0.6;
}
