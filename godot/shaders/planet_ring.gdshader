shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Ring system of the gas giant: banded, semi-transparent, lit by the sun.

uniform vec3 sun_dir = vec3(0.5, 0.4, 0.7);
uniform vec3 ring_col : source_color = vec3(0.9, 0.82, 0.68);
uniform float inner = 0.55;

float h(float x) {
	return fract(sin(x * 91.3) * 43758.5453);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	if (r > 1.0 || r < inner) {
		discard;
	}
	float k = (r - inner) / (1.0 - inner);
	float bands = 0.55 + 0.45 * sin(k * 60.0) * sin(k * 23.0 + 1.0);
	float gap = smoothstep(0.02, 0.0, abs(k - 0.62)) ;
	float a = bands * smoothstep(0.0, 0.05, k) * smoothstep(1.0, 0.92, k) * (1.0 - gap * 0.9) * 0.75;
	vec3 col = ring_col * (0.7 + 0.3 * h(floor(k * 40.0)));
	float light = 0.45 + 0.55 * abs(dot(normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), normalize(sun_dir)));
	ALBEDO = col * light;
	ALPHA = a;
}
