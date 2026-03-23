shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color = vec3(0.35, 0.70, 0.45);
uniform vec3 tip_color = vec3(0.55, 0.90, 0.65);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec2 player_xz = vec2(0.0, 0.0);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.8;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway_factor = UV.y;

	// Two overlapping wind frequencies for organic movement
	float wind1 = sin(TIME * 1.5 + world_pos.x * 0.8 + world_pos.z * 0.3) * wind_strength;
	float wind2 = sin(TIME * 2.3 + world_pos.x * 0.3 + world_pos.z * 1.1) * wind_strength * 0.4;
	float wind = (wind1 + wind2) * sway_factor;

	VERTEX.x += wind * 0.15;
	VERTEX.z += wind * 0.08;

	// Player push-away (guard against zero-length)
	vec2 to_player = world_pos.xz - player_xz;
	float dist = length(to_player);
	float push = smoothstep(1.5, 0.3, dist) * sway_factor;
	vec2 push_dir = normalize(to_player + vec2(0.001, 0.001)) * push * 0.4;
	VERTEX.x += push_dir.x;
	VERTEX.z += push_dir.y;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, UV.y);
	col *= mix(0.4, 1.0, day_factor);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Rim light matching terrain
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = smoothstep(0.5, 1.0, rim);
	EMISSION = vec3(0.85, 0.93, 0.95) * rim * 0.2 * day_factor;
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cel = floor(NdotL * 3.0 + 0.3) / 3.0;
	cel = cel * cel;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
