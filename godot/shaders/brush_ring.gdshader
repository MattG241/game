shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/bend.gdshaderinc"
// Footprint indicator drawn on the ground under the cleaning tool.

uniform vec3 color : source_color = vec3(0.3, 1.0, 0.7);
uniform float active = 0.0;
uniform float rect = 0.0;

void vertex() {
	VERTEX = bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = mix(length(c), max(abs(c.x), abs(c.y)), rect);
	float ring = smoothstep(0.8, 0.9, d) * smoothstep(1.0, 0.93, d);
	float pulse = 0.65 + 0.35 * sin(TIME * (5.0 + active * 9.0));
	float fill = (1.0 - smoothstep(0.0, 0.95, d)) * (0.04 + 0.08 * active);
	ALBEDO = color * (ring * pulse + fill);
}
