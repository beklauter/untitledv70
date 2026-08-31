// Falling water sheet. Two layers of streaks scroll down, speed up toward the
// bottom and threshold into hard lines over the deep colour. The top and
// bottom edges fade out.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

group_uniforms colors;
uniform vec4 color_deep : source_color = vec4(0.121, 0.348, 0.547, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float smoothness_val : hint_range(0.0, 1.0) = 0.6;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
group_uniforms;

group_uniforms streak_lines;
uniform sampler2D water_lines : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float line_acceleration = 1.6;
uniform float line1_scale_x = 1.0;
uniform float line1_scale_y = 1.0;
uniform float line1_speed = 0.8;
uniform float line2_scale_x = 2.0;
uniform float line2_scale_y = 1.3;
uniform float line2_speed = 1.2;
uniform float line_threshold : hint_range(0.0, 1.0) = 0.1;
uniform float line_uv_fade = 0.12;
group_uniforms;

group_uniforms waves;
uniform sampler2D normal_wave : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_normal_intensity : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms displacement;
uniform sampler2D displace_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float displace_strength : hint_range(-1.0, 1.0) = 0.04;
uniform vec2 displacement_movement = vec2(0.0, 3.0);
group_uniforms;

void vertex() {
	float d = texture(displace_tex, UV + TIME * displacement_movement * 0.1).r;
	VERTEX += NORMAL * (d - 0.5) * displace_strength;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Streaks stretch as the water falls.
	float v_warp = pow(clamp(UV.y, 0.001, 1.0), 1.0 / max(line_acceleration, 0.05));
	float l1 = texture(water_lines, vec2(UV.x * line1_scale_x, v_warp * line1_scale_y + TIME * line1_speed)).r;
	float l2 = texture(water_lines, vec2(UV.x * line2_scale_x + 0.37, v_warp * line2_scale_y + TIME * line2_speed)).r;
	float lines = step(line_threshold, l1) + step(line_threshold, l2 * 0.9);
	lines = clamp(lines, 0.0, 1.0);

	vec3 nrm = texture(normal_wave, vec2(UV.x, v_warp * 2.0 + TIME * line1_speed * 0.7)).rgb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = wave_normal_intensity;

	vec3 col = mix(color_deep.rgb, line_color.rgb, lines);
	ALBEDO = col;

	float edge_fade = smoothstep(0.0, line_uv_fade, UV.y) * (1.0 - smoothstep(1.0 - line_uv_fade, 1.0, UV.y));
	ALPHA = clamp(opacity + lines * 0.4, 0.0, 1.0) * edge_fade;
	ALPHA_SCISSOR_THRESHOLD = 0.05;
	ROUGHNESS = clamp(1.0 - smoothness_val, 0.05, 1.0);
	SPECULAR = 0.4;
}
