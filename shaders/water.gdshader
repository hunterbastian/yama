shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 water_color : source_color = vec4(0.66, 0.85, 0.92, 0.8);
uniform vec4 deep_color : source_color = vec4(0.35, 0.55, 0.70, 0.95);
uniform sampler2D depth_texture : hint_depth_texture;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.4;
uniform float wave_height : hint_range(0.0, 1.0) = 0.03;

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

void fragment() {
	// Shore blending via depth buffer
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = clamp((VERTEX.z - view_pos.z) * 0.15, 0.0, 1.0);
	ALBEDO = mix(water_color.rgb, deep_color.rgb, water_depth);
	ALPHA = mix(water_color.a, deep_color.a, water_depth);
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
