shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front;
// The inside of the far wall, seen through the glass: drawn before the near side so a pint looks whole.
#include "res://assets/shaders/glass_body.gdshaderinc"
