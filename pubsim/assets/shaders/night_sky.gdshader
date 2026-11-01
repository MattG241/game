shader_type spatial;
#include "res://assets/shaders/noise.gdshaderinc"
// The sky over the street, on a big dome round the pub: dusk fading to night, slow rain clouds lit
// orange from beneath by the town, and a moon glowing through a gap. Cheap: one draw, no lighting.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float night = 1.0;
uniform float cloud = 0.8;     // 0 clear .. 1 overcast
varying vec3 dir;
void vertex() { dir = normalize(VERTEX); }
void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, -0.2, 1.0);
	vec3 day_top = vec3(0.38, 0.45, 0.55);
	vec3 day_low = vec3(0.62, 0.6, 0.58);
	vec3 night_top = vec3(0.13, 0.15, 0.22);
	vec3 night_low = vec3(0.36, 0.27, 0.2);           // the town's sodium glow on the haze
	vec3 top = mix(day_top, night_top, night);
	vec3 low = mix(day_low, night_low, night);
	vec3 c = mix(low, top, smoothstep(-0.05, 0.55, up));
	// clouds drifting slowly, brighter underneath where the streetlights catch them
	vec2 cp = d.xz / max(d.y + 0.25, 0.05) * 1.6 + vec2(TIME * 0.006, TIME * 0.002);
	float cl = smoothstep(0.42 - cloud * 0.25, 0.75, fbm3(vec3(cp, TIME * 0.01)));
	vec3 cloud_c = mix(vec3(0.55, 0.55, 0.57), vec3(0.27, 0.22, 0.19), night) * (0.8 + 0.45 * (1.0 - up));
	// the moon, and its halo through thin cloud
	vec3 md = normalize(vec3(-0.45, 0.42, 0.78));
	float m = max(dot(d, md), 0.0);
	float disc = smoothstep(0.99955, 0.9997, m);
	float halo = pow(m, 220.0) * 0.5 + pow(m, 24.0) * 0.08;
	vec3 moon = vec3(0.95, 0.93, 0.85) * (disc * (1.0 - cl * 0.85) + halo) * night;
	c = mix(c, cloud_c, cl * smoothstep(-0.05, 0.12, up));
	ALBEDO = c + moon;
}
