shader_type spatial;
// The beer falling from the nozzle: a glossy column with streaks rushing downwards.
#include "res://assets/shaders/noise.gdshaderinc"
uniform vec3 color : source_color = vec3(0.62, 0.44, 0.28);
void fragment() {
	float t = TIME;
	float streak = fbm3(vec3(UV.x * 12.0, UV.y * 6.0 - t * 9.0, 0.0));
	float fine = vnoise3(vec3(UV.x * 40.0, UV.y * 30.0 - t * 16.0, 2.0));
	ALBEDO = color * (0.75 + 0.35 * streak + 0.15 * fine);
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
	RIM = 0.4;
}
