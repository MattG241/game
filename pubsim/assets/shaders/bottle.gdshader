shader_type spatial;
// Back-bar bottles (MultiMesh): tinted glass with a glassy rim, a printed front label and a
// foil or screw cap. Instance colour = glass tint; instance custom = label colour (+ dark ink if a>0.5).
uniform float label_y0 = 0.06;
uniform float label_y1 = 0.15;
uniform float cap_y = 0.27;
varying vec4 tint;
varying vec4 lab;
varying vec3 lp;
void vertex() {
	tint = COLOR;
	lab = INSTANCE_CUSTOM;
	lp = VERTEX;
}
void fragment() {
	float r = max(length(lp.xz), 1e-4);
	float facing = lp.z / r;                      // 1 at the front of the bottle
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 col = tint.rgb * 0.55;
	float rough = 0.05;
	float spec = 0.8;
	if (lp.y > label_y0 && lp.y < label_y1 && facing > 0.25) {
		float v = (lp.y - label_y0) / (label_y1 - label_y0);
		float u = atan(lp.x, lp.z);
		vec3 ink = lab.a > 0.5 ? vec3(0.06, 0.05, 0.04) : vec3(0.78, 0.6, 0.26);
		float edge = smoothstep(0.32, 0.28, facing);
		float border = step(v, 0.07) + step(0.93, v) + edge;
		// a line of "lettering": short strokes of varying width, then a fine second line
		float letters = step(0.35, fract(u * 14.0 + floor(u * 3.0) * 0.37));
		float title = step(0.5, v) * step(v, 0.6) * step(abs(u), 0.55) * letters;
		float small = step(0.27, v) * step(v, 0.31) * step(abs(u), 0.38) * step(0.5, fract(u * 26.0));
		col = mix(lab.rgb, ink, clamp(border * 0.85 + title * 0.9 + small * 0.6, 0.0, 1.0));
		rough = 0.75;
		spec = 0.25;
	} else if (lp.y > cap_y) {
		col = lab.a > 0.5 ? vec3(0.55, 0.42, 0.16) : vec3(0.08, 0.07, 0.07);
		rough = 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = tint.rgb * fres * 0.25;
}
