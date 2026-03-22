shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.65, 0.5, 1.0);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = base_color.rgb;
	ALBEDO *= mix(0.4, 1.0, day_factor);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Rim light — matches terrain shader
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = smoothstep(0.5, 1.0, rim);
	EMISSION = vec3(0.85, 0.93, 0.95) * rim * 0.3 * day_factor;
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float cel = floor(NdotL * 3.0 + 0.5) / 3.0;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * cel;
}
