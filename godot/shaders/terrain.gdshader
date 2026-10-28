shader_type spatial;
// Lunar regolith with a persistent dust layer driven by a per-chunk cleaning mask.
// mask = 1 : thick dust, mask = 0 : freshly cleaned dark basalt.

uniform sampler2D dirt_mask : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 dust_color : source_color = vec3(0.66, 0.63, 0.58);
uniform vec3 clean_color : source_color = vec3(0.15, 0.155, 0.17);
uniform float far_fade = 240.0;

varying vec3 world_pos;
varying vec3 world_n;
varying vec2 surf_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	surf_uv = UV2;   // metres along the cube face (continuous across chunks)
}

void fragment() {
	vec2 wuv = surf_uv;
	float n_big = texture(detail_noise, wuv * 0.013).r;
	float n_mid = texture(detail_noise, wuv * 0.11).r;
	float n_fine = texture(detail_noise, wuv * 0.9).r;
	float mask = texture(dirt_mask, UV).r;

	// Crisp, organic edge between dusty and clean ground.
	float edge_jitter = (n_fine - 0.5) * 0.22 + (n_mid - 0.5) * 0.12;
	float dust = smoothstep(0.12, 0.42, mask + edge_jitter);
	float partial = smoothstep(0.42, 0.95, mask);

	// The Moon's centre is the world origin: "up" is away from it.
	float slope = clamp(1.0 - dot(world_n, normalize(world_pos)), 0.0, 1.0);
	vec3 tint = COLOR.rgb;
	float interior = COLOR.a;

	vec3 rock = clean_color * (0.7 + 0.6 * n_mid) * (0.85 + 0.3 * n_big);
	rock = mix(rock, rock * vec3(1.15, 1.1, 1.05), slope);
	// Cleaned ground: subtle brushed sheen pattern.
	float streak = 0.5 + 0.5 * sin(wuv.x * 9.0 + n_fine * 6.0);
	rock *= 0.93 + 0.1 * streak;

	vec3 dustc = dust_color * tint * (0.82 + 0.28 * n_big) * (0.9 + 0.18 * n_fine);
	dustc *= mix(1.0, 1.12, interior);
	dustc = mix(dustc * 0.82, dustc, partial);

	vec3 col = mix(rock, dustc, dust);
	// Thin dark rim where the brush has just passed (clean/dust boundary).
	float rim = dust * (1.0 - dust) * 4.0;
	col *= 1.0 - rim * 0.28;

	ALBEDO = col;
	ROUGHNESS = mix(0.38, 0.97, dust);
	SPECULAR = mix(0.75, 0.25, dust);
	vec3 nm = texture(detail_normal, wuv * 0.35).rgb;
	vec3 nm2 = texture(detail_normal, wuv * 0.05).rgb;
	NORMAL_MAP = mix(mix(nm, nm2, 0.5), vec3(0.5, 0.5, 1.0), dust * 0.45);
	NORMAL_MAP_DEPTH = 1.2;
	// Tiny glints on polished, cleaned ground.
	float glint = step(0.86, n_fine) * (1.0 - dust) * 0.06;
	EMISSION = vec3(glint);

	float d = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = smoothstep(far_fade * 0.7, far_fade, d);
	ALBEDO = mix(ALBEDO, vec3(0.045, 0.045, 0.055), fade);
}
