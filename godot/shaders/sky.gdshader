shader_type sky;
// Lunar sky: a painted Milky Way and nebulae (texture), crisp coloured twinkling
// stars, a blazing sun with a corona, shooting stars and meteor showers.

uniform sampler2D milky : source_color, filter_linear, repeat_enable;
uniform float milky_strength = 1.0;
uniform float star_density = 0.011;
uniform vec3 sky_up = vec3(0.0, 1.0, 0.0);      // "up" where the camera is
uniform float meteor_period = 9.0;               // seconds between shooting stars (per lane)
uniform float shower = 0.0;                      // 0..1 meteor shower strength
uniform vec3 shower_dir = vec3(0.0, 1.0, 0.0);   // the shower's radiant

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float h1(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

vec3 hdir(float x) {
	return normalize(vec3(h1(x), h1(x + 1.13), h1(x + 2.37)) * 2.0 - 1.0);
}

// One layer of stars: colour (rgb) and brightness, twinkling a little.
vec3 stars(vec3 dir, float scale, float density, float size, float time) {
	vec3 p = dir * scale;
	vec3 c = floor(p);
	float h = hash3(c);
	if (h > 1.0 - density) {
		vec3 off = vec3(hash3(c + 1.7), hash3(c + 3.1), hash3(c + 5.3)) - 0.5;
		// Angular distance to the star's direction (in cell units), so every star
		// whose cell the view ray crosses is seen, not just those right on the sphere.
		vec3 sp = normalize((c + 0.5 + off * 0.4) / scale);
		float d = length(cross(dir, sp)) * scale;
		float b = smoothstep(size, 0.0, d);
		float mag = 0.35 + 0.65 * pow(fract(h * 37.0), 3.0);
		float tw = 0.8 + 0.2 * sin(time * (1.5 + 3.0 * fract(h * 91.0)) + h * 60.0);
		float t = fract(h * 53.0);
		vec3 tint = t < 0.15 ? vec3(1.0, 0.7, 0.5) : (t < 0.35 ? vec3(1.0, 0.92, 0.75) : (t < 0.8 ? vec3(0.95, 0.97, 1.0) : vec3(0.7, 0.82, 1.0)));
		return tint * b * mag * tw;
	}
	return vec3(0.0);
}

// Distance from d to the segment a-b (all unit vectors; short arcs).
float seg_dist(vec3 d, vec3 a, vec3 b, out float s) {
	vec3 ab = b - a;
	s = clamp(dot(d - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
	return length(d - (a + ab * s));
}

vec3 meteors(vec3 d, float time) {
	vec3 col = vec3(0.0);
	for (int i = 0; i < 22; i++) {
		float fi = float(i);
		bool in_shower = i >= 4;
		if (in_shower && fi - 4.0 >= shower * 18.0) {
			break;
		}
		float period = in_shower ? 2.2 + h1(fi * 7.1) * 2.8 : meteor_period * (0.6 + h1(fi * 3.7) * 0.8);
		float tt = time + h1(fi * 1.3) * period;
		float cyc = floor(tt / period);
		float ph = (tt / period - cyc) * period;
		float seed = cyc * 7.77 + fi * 13.1;
		float dur = 0.5 + h1(seed) * 0.8;
		if (ph > dur) {
			continue;
		}
		float k = ph / dur;
		vec3 a;
		vec3 t;
		if (in_shower) {
			a = normalize(shower_dir + hdir(seed + 3.0) * 0.5);
			t = normalize(a - shower_dir * dot(a, shower_dir));
		} else {
			a = normalize(hdir(seed + 3.0) + sky_up * 1.4);
			t = normalize(cross(a, hdir(seed + 9.0)));
		}
		float len = 0.18 + 0.3 * h1(seed + 5.0);
		vec3 head = normalize(a + t * len * k);
		vec3 tail = normalize(a + t * len * max(k - 0.4, 0.0));
		float s;
		float dist = seg_dist(d, tail, head, s);
		float fade = sin(k * 3.14159);
		float w = 0.0016 + 0.0016 * h1(seed + 8.0);
		vec3 tint = h1(seed + 4.0) < 0.3 ? vec3(0.6, 1.0, 0.75) : vec3(0.9, 0.95, 1.0);
		col += tint * smoothstep(w, 0.0, dist) * s * s * fade * 3.0;
		col += tint * smoothstep(w * 5.0, 0.0, length(d - head)) * fade * 1.5;
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, d.z) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	vec4 mw = texture(milky, uv);
	vec3 col = mw.rgb * milky_strength;
	// Stars: sparse bright ones, a main field, and a dense dusting inside the Milky Way
	col += stars(d, 60.0, 0.02, 0.12, TIME) * 2.6;
	col += stars(d, 60.0, 0.02, 0.35, TIME) * 0.25;         // soft glow round the bright ones
	col += stars(d, 160.0, star_density, 0.17, TIME);
	col += stars(d, 330.0, star_density * 2.0, 0.2, TIME) * 0.5;
	col += stars(d, 520.0, 0.08 * mw.a, 0.22, TIME) * (0.35 + 0.5 * mw.a);
	// Sun: disc, corona with soft rays, wide glow
	if (LIGHT0_ENABLED) {
		vec3 L = normalize(LIGHT0_DIRECTION);
		float sd = dot(d, L);
		col += vec3(1.0, 0.97, 0.9) * smoothstep(0.9993, 0.9996, sd) * 8.0;
		vec3 sx = normalize(cross(L, vec3(0.0, 1.0, 0.01)));
		vec3 sy = cross(L, sx);
		float ang = atan(dot(d, sy), dot(d, sx));
		float rays = 0.55 + 0.45 * sin(ang * 9.0 + sin(ang * 23.0) * 1.5) * sin(ang * 5.0 + 1.3);
		float halo = max(sd, 0.0);
		col += vec3(1.0, 0.88, 0.7) * pow(halo, 900.0) * 2.5 * rays;
		col += vec3(1.0, 0.85, 0.65) * pow(halo, 200.0) * 0.5;
		col += vec3(0.6, 0.65, 0.9) * pow(halo, 18.0) * 0.05;
	}
	if (!AT_CUBEMAP_PASS) {
		col += meteors(d, TIME);
	}
	COLOR = col;
}
