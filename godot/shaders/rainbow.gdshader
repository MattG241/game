shader_type spatial;
// Rainbow tool skin: hues flowing along the tool.

varying vec3 obj_pos;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 c = hue(obj_pos.y * 1.5 + obj_pos.x * 0.7 + TIME * 0.3);
	ALBEDO = c;
	METALLIC = 0.3;
	ROUGHNESS = 0.3;
	EMISSION = c * 0.35;
}
