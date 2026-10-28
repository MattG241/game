shader_type spatial;
render_mode unshaded;
// Self-lit lamps, beacons and indicator lights.
#include "res://shaders/bend.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0);
uniform float strength = 2.0;

void vertex() {
	VERTEX = bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	ALBEDO = color * strength;
}
