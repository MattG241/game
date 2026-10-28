shader_type sky;
// Black lunar sky: dense starfield, faint galactic band and a bright sun disc.

uniform float star_density = 0.0045;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float stars(vec3 dir, float scale, float density) {
	vec3 p = dir * scale;
	vec3 c = floor(p);
	float h = hash3(c);
	if (h > 1.0 - density) {
		vec3 f = fract(p) - 0.5;
		vec3 off = vec3(hash3(c + 1.7), hash3(c + 3.1), hash3(c + 5.3)) - 0.5;
		float d = length(f - off * 0.6);
		float b = smoothstep(0.12, 0.0, d);
		return b * (0.4 + 0.6 * fract(h * 37.0));
	}
	return 0.0;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float s = stars(d, 180.0, star_density) + stars(d, 420.0, star_density * 2.5) * 0.6;
	// Milky way band
	vec3 band_n = normalize(vec3(0.3, 0.8, 0.5));
	float band = exp(-pow(dot(d, band_n) * 4.0, 2.0));
	float bn = stars(d, 900.0, 0.02) * band;
	vec3 col = vec3(s) * vec3(0.9, 0.95, 1.0) + vec3(bn * 0.5) + vec3(0.025, 0.028, 0.045) * band;
	// Sun
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		col += vec3(1.0, 0.97, 0.9) * smoothstep(0.9993, 0.9996, sd) * 6.0;
		col += vec3(1.0, 0.9, 0.75) * pow(max(sd, 0.0), 300.0) * 0.6;
	}
	COLOR = col;
}
