shader_type spatial;
// Lunar regolith with a persistent dust layer driven by a per-chunk cleaning mask.
// mask = 1 : thick dust, mask = 0 : freshly cleaned dark basalt.
// Detail comes from a tileable regolith texture (grain, pebbles, micro-craters: see
// tools/gen_regolith.py), sampled at three scales (one rotated) so it never visibly tiles.

uniform sampler2D dirt_mask : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D regolith : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D regolith_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dust_color : source_color = vec3(0.6, 0.585, 0.56);
uniform vec3 clean_color : source_color = vec3(0.16, 0.162, 0.172);
uniform float far_fade = 240.0;
uniform float fine_detail = 1.0;      // 0 on the Low preset: skip the close-up layer

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
	float cam_d = length(world_pos - CAMERA_POSITION_WORLD);
	float n_big = texture(detail_noise, wuv * 0.013).r;
	float n_mid = texture(detail_noise, wuv * 0.11).r;
	float mask = texture(dirt_mask, UV).r;

	// Regolith detail at 4 m and (rotated) 17 m, plus a fine 1 m layer up close.
	vec2 uv_a = wuv * 0.25;
	vec2 uv_b = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * wuv * 0.059 + vec2(0.37, 0.71);
	vec4 ra = texture(regolith, uv_a);
	vec4 rb = texture(regolith, uv_b);
	float near = (1.0 - smoothstep(6.0, 22.0, cam_d)) * fine_detail;
	vec4 rc = vec4(0.5, 0.5, 0.5, 0.0);
	vec3 nc = vec3(0.5, 0.5, 1.0);
	if (near > 0.001) {
		rc = texture(regolith, wuv * 1.07 + vec2(0.13, 0.5));
		nc = texture(regolith_n, wuv * 1.07 + vec2(0.13, 0.5)).rgb;
	}
	float grain = mix(ra.r, rb.r, 0.45) + (rc.r - 0.5) * 0.35 * near;
	float pebbles = max(ra.a, rb.a * 0.8);
	float cavity = mix(ra.b, rb.b, 0.4);

	// Crisp, organic edge between dusty and clean ground.
	float edge_jitter = (ra.g - 0.5) * 0.3 + (n_mid - 0.5) * 0.12;
	float dust = smoothstep(0.12, 0.42, mask + edge_jitter);
	float partial = smoothstep(0.42, 0.95, mask);

	// The Moon's centre is the world origin: "up" is away from it.
	float slope = clamp(1.0 - dot(world_n, normalize(world_pos)), 0.0, 1.0);
	vec3 tint = COLOR.rgb;
	float interior = COLOR.a;

	// Cleaned ground: dark basalt with every pebble and pit sharp.
	vec3 rock = clean_color * (0.55 + 0.9 * grain) * (0.85 + 0.3 * n_big);
	rock = mix(rock, rock * vec3(1.18, 1.12, 1.06), pebbles * 0.8);
	rock = mix(rock, rock * vec3(1.15, 1.1, 1.05), slope);
	// Dust: soft grey powder; thin dust lets the pebbles show through.
	vec3 dustc = dust_color * tint * (0.78 + 0.32 * n_big) * (0.84 + 0.32 * grain);
	dustc *= mix(1.0, 1.12, interior);
	dustc = mix(dustc * 0.8, dustc, partial);
	float peb_show = pebbles * (1.0 - partial * 0.75);
	dustc = mix(dustc, dustc * vec3(0.82, 0.8, 0.78), peb_show * 0.6);
	// Steep slopes shed their dust a little.
	dustc = mix(dustc, dustc * 0.82, smoothstep(0.08, 0.3, slope));

	vec3 col = mix(rock, dustc, dust);
	// Thin dark rim where the brush has just passed (clean/dust boundary).
	float rim = dust * (1.0 - dust) * 4.0;
	col *= 1.0 - rim * 0.3;
	// Pits, gaps between pebbles and crater floors hold shadow.
	float ao = mix(1.0, 0.55 + 0.45 * smoothstep(0.15, 0.75, cavity), 0.85);
	col *= mix(ao, 1.0, 0.35);

	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = mix(0.5, 0.96, dust) - peb_show * 0.08 * (1.0 - dust);
	SPECULAR = mix(0.6, 0.22, dust);
	vec3 na = texture(regolith_n, uv_a).rgb;
	vec3 nb = texture(regolith_n, uv_b).rgb;
	vec3 nm = normalize(mix(na, nb, 0.4) * 2.0 - 1.0 + (nc * 2.0 - 1.0) * vec3(0.5, 0.5, 0.0) * near);
	// Dust smooths the surface but pebbles still poke through.
	nm = normalize(mix(nm, vec3(0.0, 0.0, 1.0), dust * (0.55 - 0.35 * peb_show)));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.6;
	// Tiny glints on polished, cleaned ground.
	float glint = step(0.88, rc.r) * (1.0 - dust) * 0.05 * near;
	EMISSION = vec3(glint);

	float fade = smoothstep(far_fade * 0.7, far_fade, cam_d);
	ALBEDO = mix(ALBEDO, vec3(0.045, 0.045, 0.055), fade);
}
