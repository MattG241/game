shader_type spatial;
// Generic sci-fi hard-surface material: paint colour with procedural panel seams,
// rivets, grime and optional emissive trim. Object-space so it sticks to moving parts.

uniform vec3 paint : source_color = vec3(0.8, 0.8, 0.82);
uniform float metallic = 0.3;
uniform float roughness = 0.5;
uniform float panel_scale = 1.6;
uniform float grime = 0.35;
uniform vec3 emit_color : source_color = vec3(0.0);
uniform float emit_strength = 0.0;
uniform float stripes = 0.0;

varying vec3 obj_pos;
varying vec3 obj_n;
varying vec3 w_pos;
varying vec3 w_n;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
	obj_n = abs(NORMAL);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = obj_pos * panel_scale;
	vec3 w = obj_n / (obj_n.x + obj_n.y + obj_n.z + 1e-4);
	vec2 uv = p.yz * w.x + p.xz * w.y + p.xy * w.z;
	vec2 g = abs(fract(uv) - 0.5);
	float seam = smoothstep(0.47, 0.495, max(g.x, g.y));
	vec2 cell = floor(uv);
	float shade = 0.92 + 0.12 * h21(cell);
	float riv = smoothstep(0.06, 0.03, length(abs(fract(uv) - 0.5) - vec2(0.4)));
	float dirt = smoothstep(0.2, 1.0, h21(floor(uv * 7.0)) * (1.0 - w.y * 0.5)) * grime;
	vec3 col = paint * shade;
	if (stripes > 0.0) {
		float st = step(0.5, fract((p.x + p.z) * stripes));
		col = mix(col, vec3(0.06), st * 0.85);
	}
	// Worn paint just inside each panel edge, then the dark seam itself.
	float wear = smoothstep(0.4, 0.47, max(g.x, g.y)) * (1.0 - seam) * step(0.55, h21(cell * 1.7 + 3.1));
	col = mix(col, col * 0.7 + vec3(0.18), wear * 0.35);
	col *= 1.0 - seam * 0.45;
	col = mix(col, col * 0.55 + vec3(0.03), dirt * 0.5);
	col += riv * 0.06;
	// Lunar dust settles on whatever faces the sky.
	float up = dot(normalize(w_n), normalize(w_pos));
	float settle = smoothstep(0.55, 0.95, up) * (0.25 + 0.5 * h21(floor(w_pos.xz * 9.0))) * grime;
	col = mix(col, vec3(0.5, 0.485, 0.46), settle * 0.45);
	ALBEDO = col;
	METALLIC = metallic * (1.0 - settle * 0.6);
	ROUGHNESS = clamp(roughness + dirt * 0.3 + seam * 0.2 + settle * 0.3, 0.0, 1.0);
	// A soft rim of light so shapes read against the black sky.
	RIM = 0.25;
	RIM_TINT = 0.6;
	EMISSION = emit_color * emit_strength;
}
