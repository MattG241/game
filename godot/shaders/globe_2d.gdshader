shader_type canvas_item;
// The map globe, painted in 2D: each pixel of the square is a point on the front half
// of a unit sphere, turned into a Moon direction and looked up in the relief and
// cleaning-progress textures (SphereMesh UV layout: u round from +Z towards +X).

uniform sampler2D relief : source_color, filter_linear, repeat_enable;
uniform sampler2D state : source_color, filter_linear, repeat_enable;
uniform float relief_ready = 0.0;
uniform mat3 view_to_moon = mat3(1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	if (r2 >= 1.0) {
		discard;
	}
	vec3 v = vec3(p.x, -p.y, sqrt(1.0 - r2));
	vec3 d = normalize(view_to_moon * v);
	float u = atan(d.x, d.z) / 6.2831853;
	if (u < 0.0) {
		u += 1.0;
	}
	vec2 tuv = vec2(u, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	vec3 c = mix(vec3(0.42, 0.43, 0.47), texture(relief, tuv).rgb, relief_ready);
	vec4 s = texture(state, tuv);
	c = mix(c, s.rgb, s.a);
	float light = 0.35 + 0.75 * max(dot(v, normalize(vec3(-0.35, 0.45, 0.82))), 0.0);
	float rim = pow(1.0 - v.z, 3.0);
	float edge = smoothstep(1.0, 0.985, sqrt(r2));
	COLOR = vec4(c * light + vec3(0.25, 0.45, 0.8) * rim * 0.6, edge);
}
