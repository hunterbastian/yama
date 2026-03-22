shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 fog_color : source_color = vec4(0.85, 0.92, 0.94, 0.6);
uniform float fog_height : hint_range(0.0, 10.0) = 3.5;
uniform float fog_density : hint_range(0.0, 3.0) = 1.2;
uniform float scroll_speed : hint_range(0.0, 0.1) = 0.015;
uniform float noise_scale : hint_range(0.005, 0.1) = 0.025;
uniform float edge_softness : hint_range(0.5, 10.0) = 4.0;
uniform float time_scale : hint_range(0.0, 2.0) = 1.0;

// Depth texture for fading near camera
uniform sampler2D depth_texture : hint_depth_texture;

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

// Fractal Brownian Motion — layered noise for organic fog shapes
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * snoise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	// Pass world position to fragment
}

void fragment() {
	// World position from the fog plane
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Scrolling noise — two layers moving in different directions for organic drift
	float t = TIME * time_scale;
	vec2 uv1 = world_pos.xz * noise_scale + vec2(t * scroll_speed, t * scroll_speed * 0.7);
	vec2 uv2 = world_pos.xz * noise_scale * 0.6 + vec2(-t * scroll_speed * 0.5, t * scroll_speed * 0.3);

	// Combine two FBM layers for complex, natural-looking fog
	float noise1 = fbm(uv1);
	float noise2 = fbm(uv2 + vec2(5.3, 1.7));
	float fog_noise = (noise1 + noise2) * 0.5;

	// Remap noise from [-1,1] to [0,1] range
	fog_noise = fog_noise * 0.5 + 0.5;

	// Height-based density — fog is thickest at low altitudes
	float height_factor = 1.0 - smoothstep(0.0, fog_height, world_pos.y);
	height_factor = pow(height_factor, 1.5); // Concentrate fog lower

	// Distance fade — thin out near camera to avoid obscuring nearby terrain
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float scene_depth = -view_pos.z;
	float frag_depth = -VERTEX.z;
	float depth_diff = scene_depth - frag_depth;
	float soft_edge = smoothstep(0.0, edge_softness, depth_diff);

	// Final opacity: noise * height density * edge softness * base density
	float alpha = fog_noise * height_factor * soft_edge * fog_density;
	alpha = clamp(alpha, 0.0, fog_color.a);

	ALBEDO = fog_color.rgb;
	ALPHA = alpha;
}
