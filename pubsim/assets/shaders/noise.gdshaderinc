// Shared cheap procedural noise helpers.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}
// returns (distance to nearest cell centre, cell id hash)
vec2 voronoi2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 17.3));
			o = 0.5 + 0.35 * sin(6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				id = hash12(i + g + 3.7);
			}
		}
	}
	return vec2(sqrt(best), id);
}

// Cells with real edges: returns (distance to the nearest cell border (F2 - F1, halved), cell id
// hash, distance to the nearest cell centre). Use it for stones, crazing and cracks.
vec3 voronoi_edge2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 17.3));
			o = 0.5 + 0.42 * sin(6.2831 * o);
			vec2 r = g + o - f;
			float d = length(r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash12(i + g + 3.7);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3((d2 - d1) * 0.5, id, d1);
}

// Soft darkening into the corners of the main room, where walls meet each other, the ceiling and
// the floor (a stand-in for baked ambient occlusion). box = (min x, min z, max x, max z).
float room_occlusion(vec3 wp, vec3 wn, vec4 box, float ceil_h) {
	vec4 d = vec4(wp.x - box.x, box.z - wp.x, wp.z - box.y, box.w - wp.z);
	float a = min(d.x, d.y);
	float b = max(d.x, d.y);
	float c = min(d.z, d.w);
	float e = max(d.z, d.w);
	float nearest = min(a, c);
	float second = min(max(a, c), min(b, e));
	if (nearest < -0.3) {
		return 1.0;   // outside the room (the street, the cellar)
	}
	float ao = 1.0;
	if (abs(wn.y) > 0.5) {
		ao *= 1.0 - 0.38 * exp(-max(nearest, 0.0) * 3.0);   // ceiling or floor meeting a wall
	} else {
		ao *= 1.0 - 0.42 * exp(-max(second, 0.0) * 3.5);    // wall meeting a wall
		ao *= 1.0 - 0.38 * exp(-max(ceil_h - wp.y, 0.0) * 3.0);
		ao *= 1.0 - 0.3 * exp(-max(wp.y, 0.0) * 5.0);
	}
	return ao;
}

// Surface relief without normal maps: perturbs the (view-space) normal by the screen-space
// gradient of a height value (Mikkelsen's surface-gradient bump). Cheap enough for phones.
vec3 bump_normal(vec3 n, vec3 view_pos, float h, float strength) {
	vec3 dpdx = dFdx(view_pos);
	vec3 dpdy = dFdy(view_pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - strength * grad);
}
