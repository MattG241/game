shader_type spatial;
render_mode unshaded, cull_back;
// The match on the big screen: crowd in the stand, a striped pitch, two teams and the sliotar.

uniform float on = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = vec2(UV.x, UV.y);
	float t = TIME;
	vec3 col;
	if (uv.y < 0.26) {
		float n = hash(floor(uv * vec2(150.0, 36.0)));
		float wave = 0.5 + 0.5 * sin(t * 2.0 + uv.x * 20.0);
		col = mix(vec3(0.12, 0.1, 0.09), mix(vec3(0.75, 0.6, 0.15), vec3(0.1, 0.2, 0.55), step(0.5, hash(floor(uv * vec2(9.0, 3.0))))), step(0.55, n));
		col *= 0.6 + 0.4 * n * wave;
	} else {
		float y = (uv.y - 0.26) / 0.74;
		float stripe = step(0.5, fract((uv.x - 0.5) * (5.0 + y * 3.0) + 0.5));
		col = mix(vec3(0.13, 0.42, 0.14), vec3(0.17, 0.5, 0.17), stripe);
		col = mix(col, vec3(0.9), smoothstep(0.004, 0.0, abs(uv.x - 0.5)) * 0.6);
		vec2 ball = vec2(0.5 + 0.36 * sin(t * 0.43) + 0.08 * sin(t * 1.7), 0.32 + 0.6 * (0.5 + 0.5 * sin(t * 0.61)));
		for (int i = 0; i < 12; i++) {
			float fi = float(i);
			float team = mod(fi, 2.0);
			vec2 home = vec2(fract(0.083 * fi * 7.0) * 0.8 + 0.1, 0.34 + 0.6 * fract(0.37 * fi + 0.2));
			vec2 p = mix(home, ball, 0.25 + 0.15 * sin(t * 0.5 + fi)) + 0.03 * vec2(sin(t * 1.3 + fi * 2.1), cos(t * 1.1 + fi));
			float d = length((uv - p) * vec2(1.8, 1.0));
			vec3 kit = team < 0.5 ? vec3(0.95, 0.82, 0.15) : vec3(0.1, 0.3, 0.85);
			col = mix(col, kit, smoothstep(0.016, 0.009, d));
		}
		col = mix(col, vec3(1.0), smoothstep(0.008, 0.004, length((uv - ball) * vec2(1.8, 1.0))));
	}
	col *= 0.9 + 0.1 * sin(uv.y * 500.0);
	ALBEDO = mix(vec3(0.008), col * 1.1, on);
}
