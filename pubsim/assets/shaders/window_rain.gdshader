shader_type spatial;
// Pub window glass on a wet night: faint tint and reflections, beads of rain and drops running
// down in wandering trails. `rain` fades the water in and out with the weather.
render_mode blend_mix, depth_draw_opaque, cull_disabled;
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 glow : source_color = vec3(0.2, 0.25, 0.3);
uniform float rain = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = vec2(wp.x, wp.y);
	// static beads of different sizes, scattered at two scales
	float bead = 0.0;
	for (int l = 0; l < 2; l++) {
		float sc = l == 0 ? 26.0 : 61.0;
		vec2 cell = floor(p * sc + float(l) * 17.0);
		vec2 f = fract(p * sc + float(l) * 17.0) - 0.5;
		float h = hash12(cell);
		vec2 off = (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.7;
		float r = 0.06 + 0.16 * hash12(cell + 11.3);
		bead = max(bead, smoothstep(r, r * 0.4, length(f - off)) * step(l == 0 ? 0.78 : 0.7, h));
	}
	// running drops: columns with a drop sliding down and a wet trail behind it
	float col = floor(p.x * 22.0);
	float ch = hash12(vec2(col, 1.0));
	float speed = 0.15 + ch * 0.35;
	float y = fract(p.y * 0.8 + TIME * speed + ch * 9.0);
	float wob = sin(p.y * 30.0 + ch * 6.0) * 0.12;
	float xin = abs(fract(p.x * 22.0) - 0.5 - wob);
	float drop = smoothstep(0.12, 0.05, xin) * smoothstep(0.06, 0.0, abs(y - 0.5)) * step(0.6, ch);
	float trail = smoothstep(0.08, 0.02, xin) * step(0.5, y) * (1.0 - y) * 1.6 * step(0.6, ch);
	float water = clamp(bead * 0.8 + drop + trail * 0.5, 0.0, 1.0) * rain;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(vec3(0.25, 0.33, 0.4), vec3(0.85, 0.9, 0.95), water);
	EMISSION = glow * (0.3 + water * 0.6);
	ROUGHNESS = mix(0.05, 0.02, water);
	METALLIC = 0.3;
	SPECULAR = 0.9;
	ALPHA = clamp(0.18 + fres * 0.3 + water * 0.45, 0.0, 0.9);
}
