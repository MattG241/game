// "Mini-planet" horizon: everything drops away with distance from the camera, so the
// ground visibly curves. Visual only (physics stays flat). Set from game.gd each frame.
global uniform vec3 bend_origin;
global uniform float bend_k;    // 1 / (2 * visual planet radius); 0 = flat

vec3 bend_vertex(vec3 vertex, mat4 model) {
	vec3 wp = (model * vec4(vertex, 1.0)).xyz;
	vec2 d = wp.xz - bend_origin.xz;
	float drop = dot(d, d) * bend_k;
	return vertex + inverse(mat3(model)) * vec3(0.0, -drop, 0.0);
}
