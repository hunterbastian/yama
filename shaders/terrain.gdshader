shader_type spatial;

uniform float seed : hint_range(0.0, 1000.0) = 0.0;
uniform float height_scale : hint_range(0.0, 30.0) = 12.0;
uniform float noise_scale : hint_range(0.01, 0.2) = 0.05;
uniform float island_radius : hint_range(10.0, 100.0) = 55.0;

varying float v_height;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

// --- Simplex 2D noise (Ashima Arts) ---
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439,
	                    -0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod289_2(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x_ = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x_) - 0.5;
	vec3 ox = floor(x_ + 0.5);
	vec3 a0 = x_ - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

float terrain_height(vec2 pos) {
	// Seed offsets sample position — CPU code must mirror this exactly
	vec2 p = pos * noise_scale + vec2(seed, seed);
	float h = snoise(p) * 0.6 + snoise(p * 2.0 + vec2(43.0, 17.0)) * 0.4;

	// Island falloff — distance from center fades to 0
	float dist = length(pos) / island_radius;
	float falloff = 1.0 - smoothstep(0.5, 1.0, dist);

	return h * height_scale * falloff;
}

void vertex() {
	// Terrain must be at origin — MODEL_MATRIX converts local → world for noise sampling
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = terrain_height(world_pos.xz);
	VERTEX.y += h;
	v_height = h;
	v_world_pos = world_pos;

	// Compute normal from finite differences
	float eps = 0.5;
	float hL = terrain_height(world_pos.xz + vec2(-eps, 0.0));
	float hR = terrain_height(world_pos.xz + vec2(eps, 0.0));
	float hD = terrain_height(world_pos.xz + vec2(0.0, -eps));
	float hU = terrain_height(world_pos.xz + vec2(0.0, eps));
	NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
	v_world_normal = NORMAL;
}

void fragment() {
	// --- Howl's Countryside palette ---
	float slope = v_world_normal.y;
	float h = v_height;

	// Base colors
	vec3 shore = vec3(0.91, 0.86, 0.78);
	vec3 grass_low = vec3(0.55, 0.75, 0.62);
	vec3 grass_high = vec3(0.77, 0.90, 0.82);
	vec3 rock = vec3(0.60, 0.60, 0.54);

	// Grass: mint gradient by height
	vec3 grass = mix(grass_low, grass_high, smoothstep(2.0, 10.0, h));

	// Blend shore → grass by height
	vec3 col = mix(shore, grass, smoothstep(0.0, 1.5, h));

	// Blend in rock on steep slopes
	float rock_blend = 1.0 - smoothstep(0.55, 0.75, slope);
	col = mix(col, rock, rock_blend);

	// Painted variation — noise shifts color slightly so flat areas aren't CG-perfect
	float variation = snoise(v_world_pos.xz * 0.3) * 0.04;
	col += vec3(variation, variation * 0.8, variation * 0.6);

	ALBEDO = col;
}
