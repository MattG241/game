shader_type spatial;
// A worn wool hearth rug: deep red field, a dark border with a gold key pattern and a central
// medallion, faded where feet have crossed it.
#include "res://assets/shaders/noise.gdshaderinc"
void fragment() {
	vec2 uv = UV;
	vec2 d = abs(uv - 0.5);
	float border = step(0.42, max(d.x * 1.0, d.y * 1.0));
	float inner = step(0.38, max(d.x, d.y)) * (1.0 - border);
	vec3 field = vec3(0.42, 0.07, 0.06);
	vec3 c = field;
	float med = smoothstep(0.2, 0.18, length((uv - 0.5) * vec2(1.0, 0.65)));
	float ring = smoothstep(0.012, 0.0, abs(length((uv - 0.5) * vec2(1.0, 0.65)) - 0.16));
	c = mix(c, vec3(0.08, 0.16, 0.12), med);
	c = mix(c, vec3(0.75, 0.55, 0.22), ring);
	float key = step(0.5, fract((uv.x + uv.y) * 24.0));
	c = mix(c, mix(vec3(0.06, 0.05, 0.05), vec3(0.7, 0.52, 0.2), key * 0.6), border);
	c = mix(c, vec3(0.75, 0.55, 0.22), inner * 0.7);
	float pile = fbm3(vec3(uv * 300.0, 0.0));
	float wear = smoothstep(0.35, 0.0, length((uv - vec2(0.5, 0.75)) * vec2(1.5, 1.0))) * 0.35;
	c *= 0.85 + 0.2 * pile;
	c = mix(c, c * 1.3 + vec3(0.05), wear);
	ALBEDO = c;
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
}
