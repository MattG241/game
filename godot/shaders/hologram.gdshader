shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Holographic projection: glowing edges, moving scanlines, flicker.

uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float strength = 1.0;     // fades the whole hologram in/out

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float h = dot(wpos, normalize(INV_VIEW_MATRIX[1].xyz));
	float scan = 0.65 + 0.35 * step(0.45, fract(h * 38.0 - TIME * 1.6));
	float band = smoothstep(0.0, 0.05, abs(fract(h * 1.5 - TIME * 0.6) - 0.5)) * 0.4 + 0.6;
	float flick = 0.88 + 0.12 * sin(TIME * 47.0) * sin(TIME * 13.0);
	ALBEDO = tint.rgb * (0.18 + fres * 1.3) * scan * band * flick * strength;
}
