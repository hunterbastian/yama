shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.66, 0.85, 0.92, 0.8);
uniform vec4 deep_color : source_color = vec4(0.35, 0.55, 0.70, 0.95);
uniform sampler2D depth_texture : hint_depth_texture;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.4;
uniform float wave_height : hint_range(0.0, 1.0) = 0.03;
uniform vec2 player_xz;
uniform float player_speed : hint_range(0.0, 20.0) = 0.0;
uniform float player_speed_smooth : hint_range(0.0, 20.0) = 0.0;
uniform vec4 water_effect_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	float wave = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7);
	VERTEX.y += wave * wave_height;
	float eps = 0.5;
	float hL = sin((VERTEX.x - eps) * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7) * wave_height;
	float hR = sin((VERTEX.x + eps) * 0.5 + TIME * wave_speed) * cos(VERTEX.z * 0.3 + TIME * wave_speed * 0.7) * wave_height;
	float hD = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos((VERTEX.z - eps) * 0.3 + TIME * wave_speed * 0.7) * wave_height;
	float hU = sin(VERTEX.x * 0.5 + TIME * wave_speed) * cos((VERTEX.z + eps) * 0.3 + TIME * wave_speed * 0.7) * wave_height;
	NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
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
	float water_depth = clamp((VERTEX.z - view_pos.z) * 0.15, 0.0, 1.0);
	ALBEDO = mix(water_color.rgb, deep_color.rgb, water_depth);
	// Player ripple rings
	vec3 world_pos_frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple_val = ripple(world_pos_frag.xz);
	ALBEDO += vec3(ripple_val * 0.15);
	// Player foam
	float foam_val = foam(world_pos_frag.xz);
	ALBEDO += water_effect_tint.rgb * foam_val * 0.3;
	// Tint ripples by day/night too
	ALBEDO = mix(ALBEDO, ALBEDO * water_effect_tint.rgb, 0.2);
	ALPHA = mix(water_color.a, deep_color.a, water_depth);
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
