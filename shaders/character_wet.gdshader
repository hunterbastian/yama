shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.58, 0.52, 1.0);
uniform float water_y_world = -10.0;
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = base_color.rgb;

	// Darken fragments below water line
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float below_water = smoothstep(water_y_world + 0.05, water_y_world - 0.05, world_pos.y);
	float wet = below_water * wet_amount;

	ALBEDO *= mix(1.0, 0.7, wet);
	ROUGHNESS = mix(0.8, 0.3, wet);
}
