shader_type spatial;
// Simple lit material (glass, visors, small props).
#include "res://shaders/bend.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.6;
uniform vec3 emission : source_color = vec3(0.0);

void vertex() {
	VERTEX = bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission;
}
