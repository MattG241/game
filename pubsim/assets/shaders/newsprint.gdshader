shader_type spatial;
// A folded local newspaper: masthead, columns of grey type and a photo block.
void fragment() {
	vec2 uv = UV;
	vec3 paper = vec3(0.86, 0.84, 0.78);
	vec3 c = paper;
	if (uv.y < 0.16) {
		c = mix(paper, vec3(0.1), step(0.3, fract(uv.x * 9.0)) * step(0.05, uv.y) * step(uv.y, 0.12));
	} else {
		float col = fract(uv.x * 4.0);
		float gutter = step(0.06, col) * step(col, 0.94);
		float line = step(0.5, fract(uv.y * 70.0)) * gutter;
		float photo = step(0.52, uv.x) * step(uv.x, 0.96) * step(0.22, uv.y) * step(uv.y, 0.5);
		c = mix(paper, vec3(0.45), line * 0.55);
		c = mix(c, vec3(0.3, 0.3, 0.3) + 0.2 * sin(uv.x * 40.0) * sin(uv.y * 30.0), photo);
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
