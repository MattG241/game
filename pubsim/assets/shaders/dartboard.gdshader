shader_type spatial;
// Regulation-proportioned dartboard drawn on a quad (UV centre = bullseye).
uniform float board_r = 0.2255;   // quad half-size in metres
varying vec2 uvv;
void vertex() { uvv = UV; }
void fragment() {
	vec2 p = (uvv - 0.5) * 2.0 * board_r;   // metres, x right, y down
	p.y = -p.y;
	float r = length(p) * 1000.0;           // mm
	float a = atan(p.x, p.y);               // 0 at top, clockwise
	float seg = floor(mod(a / (6.2831853 / 20.0) + 0.5, 20.0));
	bool dark = mod(seg, 2.0) < 0.5;
	vec3 black = vec3(0.04, 0.04, 0.04);
	vec3 cream = vec3(0.88, 0.82, 0.66);
	vec3 red = vec3(0.7, 0.08, 0.06);
	vec3 green = vec3(0.05, 0.42, 0.18);
	vec3 col;
	if (r < 6.35) col = red;
	else if (r < 15.9) col = green;
	else if (r < 99.0) col = dark ? black : cream;
	else if (r < 107.0) col = dark ? red : green;
	else if (r < 162.0) col = dark ? black : cream;
	else if (r < 170.0) col = dark ? red : green;
	else if (r < 225.5) col = vec3(0.06, 0.05, 0.05);
	else { discard; }
	// thin wire spider
	float wire_a = abs(fract(a / (6.2831853 / 20.0) + 0.5) - 0.5) * (6.2831853 / 20.0) * r;
	bool ring_wire = abs(r - 99.0) < 0.6 || abs(r - 107.0) < 0.6 || abs(r - 162.0) < 0.6 || abs(r - 170.0) < 0.6 || abs(r - 15.9) < 0.5;
	if ((wire_a < 0.5 && r > 15.9 && r < 170.0) || ring_wire) col = vec3(0.75, 0.75, 0.72);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	METALLIC = (wire_a < 0.5 || ring_wire) ? 0.6 : 0.0;
}
