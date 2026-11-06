shader_type spatial;
render_mode unshaded, cull_back;
// Distant planets: a banded gas giant (kind 0) or a dusty red world (kind 1), lit by the sun.

uniform int kind = 0;
uniform vec3 sun_dir = vec3(0.5, 0.4, 0.7);
uniform vec3 col_a : source_color = vec3(0.85, 0.7, 0.5);
uniform vec3 col_b : source_color = vec3(0.55, 0.38, 0.25);
uniform vec3 col_c : source_color = vec3(0.95, 0.9, 0.8);
uniform float bands = 9.0;

varying vec3 n_obj;
varying vec3 n_world;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vn(p);
		p *= 2.1;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	n_obj = NORMAL;
	n_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(n_obj);
	float lon = atan(n.z, n.x);
	float lat = n.y;
	vec3 col;
	if (kind == 0) {
		float warp = fbm(vec2(lon * 3.0, lat * 8.0)) * 0.6;
		float b = sin((lat + warp * 0.08) * bands * 3.14159) * 0.5 + 0.5;
		float fine = fbm(vec2(lon * 6.0, lat * 40.0 + warp * 4.0));
		col = mix(col_b, col_a, b);
		col = mix(col, col_c, smoothstep(0.55, 0.8, fine) * 0.5);
		// A great storm
		vec2 sp = vec2(lon - 0.8, (lat + 0.32) * 3.0);
		float storm = smoothstep(0.35, 0.1, length(sp * vec2(1.0, 1.6)));
		col = mix(col, vec3(0.8, 0.35, 0.2), storm * 0.8);
	} else {
		float t = fbm(vec2(lon * 2.5, lat * 2.5) + 3.0);
		col = mix(col_b, col_a, smoothstep(0.35, 0.7, t));
		col = mix(col, col_c, smoothstep(0.86, 0.95, abs(lat)));
	}
	float light = clamp(dot(normalize(n_world), normalize(sun_dir)) * 1.3 + 0.08, 0.0, 1.0);
	col *= light * 1.15;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += col_a * fres * 0.25 * light;
	ALBEDO = col;
}
