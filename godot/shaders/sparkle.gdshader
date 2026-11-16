shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// A four-pointed glint that always faces the camera (gold nuggets, treasure).

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float strength = 1.0;
uniform float spin = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float c = cos(spin);
	float s = sin(spin);
	p = mat2(vec2(c, -s), vec2(s, c)) * p;
	float r = length(p);
	float rays = max(0.0, 1.0 - abs(p.x) * 14.0) * max(0.0, 1.0 - abs(p.y));
	rays += max(0.0, 1.0 - abs(p.y) * 14.0) * max(0.0, 1.0 - abs(p.x));
	vec2 q = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * p;
	rays += 0.4 * max(0.0, 1.0 - abs(q.x) * 18.0) * max(0.0, 1.0 - abs(q.y) * 1.6);
	rays += 0.4 * max(0.0, 1.0 - abs(q.y) * 18.0) * max(0.0, 1.0 - abs(q.x) * 1.6);
	float core = exp(-r * r * 40.0) * 2.0 + exp(-r * r * 6.0) * 0.25;
	ALBEDO = tint.rgb * (rays + core) * strength;
}
