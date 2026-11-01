shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
// Old lime plaster: mottled, stained and hairline-cracked. Inside the pub (room_ao > 0) the corners
// gather shadow and a century of turf smoke has yellowed the upper wall; pattern 1 is an embossed
// (Anaglypta) ceiling paper in square panels.
uniform vec3 base_color : source_color = vec3(0.62, 0.52, 0.36);
uniform float stain = 0.25;
uniform float room_ao = 0.0;
uniform vec4 room_box = vec4(-7.0, -5.0, 7.0, 5.0);
uniform float room_h = 3.3;
uniform int pattern = 0;
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float n = fbm3(wpos * 3.0);
	float s = fbm3(wpos * 0.6 + 4.0);
	vec3 c = base_color * (0.9 + 0.2 * n);
	c = mix(c, c * vec3(0.8, 0.7, 0.5), smoothstep(0.45, 0.8, s) * stain);
	float crack = smoothstep(0.012, 0.0, abs(fbm3(wpos * 2.3 + 9.0) - 0.5)) * smoothstep(0.62, 0.8, s);
	c *= 1.0 - crack * 0.12;
	float h = fbm3(wpos * 9.0) * 0.0025 + fbm3(wpos * 35.0) * 0.0006 - crack * 0.001;
	if (pattern == 1) {
		// square panels with a raised border and a four-petal boss in each
		vec2 q = wpos.xz / 0.5;
		vec2 f = fract(q) - 0.5;
		float border = smoothstep(0.42, 0.46, max(abs(f.x), abs(f.y)));
		float r = length(f);
		float petals = smoothstep(0.2, 0.17, r * (1.0 + 0.35 * cos(atan(f.y, f.x) * 4.0)));
		float ring = smoothstep(0.02, 0.0, abs(r - 0.3));
		float relief = border + petals * 0.8 + ring * 0.5;
		h += relief * 0.0025;
		c *= 1.0 - (1.0 - relief) * 0.05 + relief * 0.03;
	}
	if (room_ao > 0.0) {
		// smoke and nicotine climb the walls and gather on the ceiling
		float up = smoothstep(1.4, room_h, wpos.y);
		c = mix(c, c * vec3(0.78, 0.66, 0.48), up * 0.45 * room_ao);
		c *= mix(1.0, room_occlusion(wpos, wnorm, room_box, room_h), room_ao);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
