// "Mini-planet" horizon: everything drops away with distance from the camera, so the
// ground visibly curves. Visual only (physics stays flat). Set from game.gd each frame.
// Plain arithmetic only (no matrix inverse) - some phone GPU drivers crash on that.
global uniform vec3 bend_origin;
global uniform float bend_k;    // 1 / (2 * visual planet radius); 0 = flat

vec3 bend_vertex(vec3 vertex, mat4 model) {
	vec3 wp = (model * vec4(vertex, 1.0)).xyz;
	vec2 d = wp.xz - bend_origin.xz;
	float drop = dot(d, d) * bend_k;
	// World offset (0, -drop, 0) in object space. The model axes are scaled but never
	// sheared, so each local component is (axis . offset) / |axis|^2.
	vec3 ax = model[0].xyz;
	vec3 ay = model[1].xyz;
	vec3 az = model[2].xyz;
	return vertex - drop * vec3(ax.y / dot(ax, ax), ay.y / dot(ay, ay), az.y / dot(az, az));
}
