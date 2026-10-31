shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Pint glass: the near side. The far side is drawn first by glass_back.gdshader (next_pass order).
#include "res://assets/shaders/glass_body.gdshaderinc"
