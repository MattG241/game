shader_type spatial;
// The faint glow of lamplight hanging in the air under a pendant: strongest at the shade,
// fading towards the floor and at the cone's edges. Added light, no depth write.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.78, 0.5);
uniform float strength = 0.05;
varying float vy;
void vertex() { vy = clamp(-VERTEX.y / 1.6 + 0.5, 0.0, 1.0); }
void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	float fall = pow(1.0 - vy, 1.6);
	ALBEDO = color * strength * edge * fall;
}
