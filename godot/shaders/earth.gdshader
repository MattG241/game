shader_type spatial;
render_mode unshaded, cull_back;
// Stylised Earth: procedural continents, clouds, sun-lit terminator and atmosphere rim.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.5, 0.3, 0.8);
uniform float spin = 0.0;

varying vec3 n_world;
varying vec3 n_obj;

void vertex() {
	n_obj = NORMAL;
	n_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(n_obj);
	float lon = atan(n.z, n.x) / 6.2831853 + 0.5 + spin;
	float lat = asin(clamp(n.y, -1.0, 1.0)) / 3.14159265 + 0.5;
	vec2 uv = vec2(lon, lat);
	float land = texture(noise_tex, uv * vec2(2.0, 1.0)).r * 0.65 + texture(noise_tex, uv * vec2(5.0, 2.5)).r * 0.35;
	float is_land = smoothstep(0.52, 0.56, land);
	vec3 ocean = mix(vec3(0.02, 0.12, 0.35), vec3(0.05, 0.25, 0.55), land);
	vec3 ground = mix(vec3(0.15, 0.35, 0.12), vec3(0.55, 0.45, 0.28), smoothstep(0.6, 0.75, land));
	float polar = smoothstep(0.82, 0.9, abs(lat - 0.5) * 2.0);
	vec3 col = mix(ocean, ground, is_land);
	col = mix(col, vec3(0.95), polar);
	float clouds = smoothstep(0.55, 0.75, texture(noise_tex, uv * vec2(3.0, 1.6) + vec2(spin * 2.0, 0.1)).r);
	col = mix(col, vec3(1.0), clouds * 0.85);
	vec3 nw = normalize(n_world);
	float light = clamp(dot(nw, normalize(sun_dir)) * 1.4 + 0.15, 0.0, 1.0);
	vec3 night = vec3(0.01, 0.015, 0.03) + vec3(1.0, 0.8, 0.4) * is_land * (1.0 - clouds) * step(0.62, texture(noise_tex, uv * 30.0).r) * 0.15;
	col = mix(night, col * 1.25, light);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col += vec3(0.3, 0.55, 1.0) * fres * (0.25 + light);
	ALBEDO = col;
}
