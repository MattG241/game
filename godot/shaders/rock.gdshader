shader_type spatial;
// Lunar boulders: grey rock with triplanar regolith detail, darker in creases, and a
// layer of dust settled on whatever faces up.

uniform sampler2D regolith : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D regolith_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_color : source_color = vec3(0.34, 0.335, 0.33);
uniform vec3 dust_color : source_color = vec3(0.58, 0.565, 0.54);

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wn);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * 0.6;
	vec4 tx = texture(regolith, p.zy);
	vec4 ty = texture(regolith, p.xz);
	vec4 tz = texture(regolith, p.xy);
	vec4 t = tx * w.x + ty * w.y + tz * w.z;
	vec4 t2 = texture(regolith, wpos.xz * 0.13 + vec2(0.3, 0.6));
	float up = dot(n, normalize(wpos));
	float dust = smoothstep(0.45, 0.85, up + (t.g - 0.5) * 0.5);
	vec3 rock = rock_color * (0.6 + 0.8 * t.r) * (0.85 + 0.3 * t2.r);
	vec3 col = mix(rock, dust_color * (0.85 + 0.3 * t.r), dust);
	float ao = 0.6 + 0.4 * smoothstep(0.1, 0.7, t.b);
	ALBEDO = col * mix(ao, 1.0, 0.4);
	AO = ao;
	ROUGHNESS = mix(0.82, 0.97, dust);
	SPECULAR = 0.35;
	// Detail normal from the face the rock is most facing.
	vec3 nm = w.y > max(w.x, w.z) ? texture(regolith_n, p.xz).rgb : (w.x > w.z ? texture(regolith_n, p.zy).rgb : texture(regolith_n, p.xy).rgb);
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), dust * 0.5);
	NORMAL_MAP_DEPTH = 1.4;
}
