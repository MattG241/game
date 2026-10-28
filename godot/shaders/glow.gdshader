shader_type spatial;
render_mode unshaded;
// Self-lit lamps, beacons and indicator lights.

uniform vec3 color : source_color = vec3(1.0);
uniform float strength = 2.0;

void fragment() {
	ALBEDO = color * strength;
}
