shader_type spatial;
render_mode unshaded, cull_back;
// The map globe: equirectangular relief + cleaning-state overlay, looked up from the
// direction of each point (no UV seam), lit from a fixed direction in view space.

uniform sampler2D relief : source_color, filter_linear, repeat_enable;
uniform sampler2D state : source_color, filter_linear, repeat_enable;
uniform float ready = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 d = normalize(local_pos);
	vec2 uv = vec2(atan(d.z, d.x) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = mix(vec3(0.35, 0.36, 0.4), texture(relief, uv).rgb, ready);
	vec4 s = texture(state, uv);
	c = mix(c, s.rgb, s.a);
	float l = 0.32 + 0.8 * max(dot(NORMAL, normalize(vec3(-0.35, 0.45, 0.82))), 0.0);
	// Thin rim glow so the globe stands out against the dark menu.
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	ALBEDO = c * l + vec3(0.25, 0.45, 0.8) * rim * 0.6;
}
