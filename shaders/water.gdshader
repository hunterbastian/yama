shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D depth_texture : hint_depth_texture;
uniform vec2 player_xz;
uniform float player_speed : hint_range(0.0, 20.0) = 0.0;
uniform float player_speed_smooth : hint_range(0.0, 20.0) = 0.0;
uniform vec4 water_effect_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Gerstner wave parameters — must match CPU _water_height_at() exactly
const int WAVE_COUNT = 4;
const vec2 WAVE_DIR[4] = {vec2(1.0, 0.0), vec2(0.7, 0.7), vec2(0.3, 1.0), vec2(-0.5, 0.8)};
const float WAVE_AMP[4] = {0.35, 0.20, 0.15, 0.10};
const float WAVE_FREQ[4] = {0.8, 1.2, 1.8, 2.5};
const float WAVE_Q[4] = {0.4, 0.3, 0.3, 0.2};
const float WAVE_SPEED[4] = {1.0, 1.3, 0.9, 1.5};

varying vec3 v_wave_normal;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 displaced = world_pos;
	vec3 wave_normal = vec3(0.0, 1.0, 0.0);

	for (int i = 0; i < WAVE_COUNT; i++) {
		vec2 dir = normalize(WAVE_DIR[i]);
		float phase = WAVE_FREQ[i] * dot(dir, world_pos.xz) + TIME * WAVE_SPEED[i];
		float c = cos(phase);
		float s = sin(phase);

		// Gerstner displacement
		displaced.x += WAVE_Q[i] * WAVE_AMP[i] * dir.x * c;
		displaced.z += WAVE_Q[i] * WAVE_AMP[i] * dir.y * c;
		displaced.y += WAVE_AMP[i] * s;

		// Analytical Gerstner normal
		wave_normal.x -= dir.x * WAVE_FREQ[i] * WAVE_AMP[i] * c;
		wave_normal.z -= dir.y * WAVE_FREQ[i] * WAVE_AMP[i] * c;
		wave_normal.y -= WAVE_Q[i] * WAVE_FREQ[i] * WAVE_AMP[i] * s;
	}

	// Apply displacement in local space
	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced, 1.0)).xyz;
	NORMAL = normalize(wave_normal);
	v_wave_normal = wave_normal;
}

float ripple(vec2 frag_xz) {
	float dist = length(frag_xz - player_xz);
	// 3 expanding rings using TIME
	float ring1 = sin((dist - TIME * 2.0) * 8.0) * exp(-dist * 0.5);
	float ring2 = sin((dist - TIME * 2.5) * 6.0) * exp(-dist * 0.6);
	float ring3 = sin((dist - TIME * 1.5) * 10.0) * exp(-dist * 0.7);
	float rings = (ring1 + ring2 + ring3) * 0.33;
	// Fade with distance from player, scale with speed
	float fade = exp(-dist * 0.3) * clamp(player_speed * 0.15, 0.0, 1.0);
	return rings * fade;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float foam(vec2 frag_xz) {
	float dist = length(frag_xz - player_xz);
	// Foam radius shrinks as speed decays
	float radius = player_speed_smooth * 0.3;
	float foam_mask = smoothstep(radius, radius * 0.3, dist);
	// Noise texture so it looks organic
	float noise = value_noise(frag_xz * 3.0 + TIME * 0.2);
	return foam_mask * noise * clamp(player_speed_smooth * 0.2, 0.0, 1.0);
}

void fragment() {
	// Shore blending via depth buffer
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = clamp((VERTEX.z - view_pos.z) * 0.4, 0.0, 1.0);

	// Multi-stop depth gradient
	vec3 shallow = vec3(0.55, 0.85, 0.82);
	vec3 mid     = vec3(0.30, 0.65, 0.65);
	vec3 deep    = vec3(0.15, 0.40, 0.50);
	vec3 abyss   = vec3(0.08, 0.20, 0.30);

	vec3 col = shallow;
	col = mix(col, mid, smoothstep(0.0, 0.3, water_depth));
	col = mix(col, deep, smoothstep(0.3, 0.6, water_depth));
	col = mix(col, abyss, smoothstep(0.6, 1.0, water_depth));

	ALBEDO = col;

	// Whitecap foam — where wave surface is steep
	float slope = 1.0 - normalize(v_wave_normal).y;
	float whitecap = smoothstep(0.3, 0.6, slope) * value_noise(
		(INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 3.0 + TIME * 0.5);
	ALBEDO += vec3(whitecap * 0.6);

	// Shore foam — animated bands near shore
	float shore_dist = 1.0 - water_depth;
	float foam_band1 = smoothstep(0.6, 0.8, shore_dist) *
		(0.5 + 0.5 * sin(shore_dist * 20.0 - TIME * 2.0));
	float foam_band2 = smoothstep(0.7, 0.9, shore_dist) *
		(0.5 + 0.5 * sin(shore_dist * 15.0 - TIME * 1.5 + 1.0));
	float shore_foam = max(foam_band1, foam_band2) *
		value_noise((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 5.0);
	ALBEDO += vec3(shore_foam * 0.5);

	// Player ripple rings (preserved)
	vec3 world_pos_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple_val = ripple(world_pos_frag.xz);
	ALBEDO += vec3(ripple_val * 0.15);

	// Player foam (preserved)
	float foam_val = foam(world_pos_frag.xz);
	ALBEDO += water_effect_tint.rgb * foam_val * 0.3;

	// Day/night tint (preserved)
	ALBEDO = mix(ALBEDO, ALBEDO * water_effect_tint.rgb, 0.2);

	ALPHA = mix(0.8, 0.95, water_depth);
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
