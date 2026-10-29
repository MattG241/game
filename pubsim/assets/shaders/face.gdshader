shader_type spatial;
// Painted face on the sculpted head (head-local coordinates): skin with a soft warm sheen,
// lips, a mouth that opens while talking, brows, cheek colour and stubble.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 skin : source_color = vec3(0.9, 0.72, 0.6);
uniform vec3 brow_color : source_color = vec3(0.25, 0.15, 0.08);
uniform vec3 lip_color : source_color = vec3(0.7, 0.38, 0.36);
uniform float mouth_open = 0.0;
uniform float stubble = 0.0;
uniform float blush = 0.3;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = skin * (0.95 + 0.07 * fbm3(lp * 260.0));
	// warmth on cheeks, nose and ears
	float ch = exp(-pow(length(vec2(abs(lp.x) - 0.048, lp.y + 0.015)) / 0.025, 2.0)) * step(lp.z, -0.04);
	float nose = exp(-pow(length(vec2(lp.x, lp.y + 0.02)) / 0.018, 2.0)) * step(lp.z, -0.09);
	c = mix(c, c * vec3(1.08, 0.86, 0.84), clamp(ch * blush + nose * 0.3, 0.0, 1.0));
	// soft shade in the eye sockets
	float sock = exp(-pow(length(vec2(abs(lp.x) - 0.035, lp.y - 0.014)) / 0.02, 2.0)) * step(lp.z, -0.06);
	c *= 1.0 - sock * 0.18;
	// under the eyes, the lines from nose to mouth, and a shadow under the lower lip
	float bags = exp(-pow(length(vec2(abs(lp.x) - 0.034, (lp.y + 0.006) * 1.6)) / 0.014, 2.0)) * step(lp.z, -0.07);
	c *= 1.0 - bags * 0.1;
	float fold_x = abs(lp.x) - (0.026 + (lp.y + 0.03) * -0.25);
	float fold = smoothstep(0.008, 0.0, abs(fold_x)) * smoothstep(-0.005, -0.02, lp.y) * smoothstep(-0.07, -0.055, lp.y) * step(lp.z, -0.075);
	c *= 1.0 - fold * 0.06;
	float under_lip = exp(-pow(length(vec2(lp.x * 0.6, lp.y + 0.078)) / 0.008, 2.0)) * step(lp.z, -0.08);
	c *= 1.0 - under_lip * 0.15;
	// stubble on the jaw
	float jaw = smoothstep(-0.02, -0.05, lp.y) * step(lp.z, 0.0) * step(abs(lp.x), 0.075);
	float dots = step(0.55, hash13(floor(lp * 900.0)));
	c = mix(c, c * 0.62, jaw * stubble * (0.55 + 0.45 * dots));
	// brows
	for (int s = -1; s <= 1; s += 2) {
		float bx = lp.x - float(s) * 0.036;
		float by = lp.y - (0.04 + 0.006 * (1.0 - pow(bx / 0.022, 2.0)));
		float b = step(abs(bx), 0.022) * smoothstep(0.0045, 0.002, abs(by)) * step(lp.z, -0.075);
		c = mix(c, brow_color, b * 0.9);
	}
	// lips and mouth
	float mx = abs(lp.x);
	float lip = smoothstep(0.023, 0.017, mx) * smoothstep(0.0125, 0.008, abs(lp.y + 0.06)) * step(lp.z, -0.088);
	c = mix(c, lip_color * (0.9 + 0.1 * fbm3(lp * 400.0)), lip * 0.85);
	// the mouth: a closed line, or a soft oval that opens while talking, with a glimpse of teeth
	float mw = 0.0175 - mouth_open * 0.005;
	float mh = 0.0007 + mouth_open * 0.0042;
	float dy = lp.y + 0.06;
	float inside = (mx * mx) / (mw * mw) + (dy * dy) / (mh * mh);
	float slit = smoothstep(1.0, 0.7, inside) * step(lp.z, -0.09);
	vec3 mouth_c = vec3(0.16, 0.05, 0.05);
	mouth_c = mix(mouth_c, vec3(0.72, 0.68, 0.62), step(0.35, dy / mh) * step(0.25, mouth_open) * step(mx, mw * 0.7));
	c = mix(c, mouth_c, slit);
	ALBEDO = c;
	ROUGHNESS = 0.55 - lip * 0.2;
	SPECULAR = 0.35;
	RIM = 0.3;
	RIM_TINT = 0.7;
}
