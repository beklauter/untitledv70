// Waterfall foam streaks. Two scrolling noise layers multiplied together,
// faded out at both ends, then alpha tested.
shader_type spatial;
render_mode cull_disabled, unshaded;

// Builds polar UVs from object space: U goes around, V goes out from the
// centre. For the pool foam meshes, whose own unwrap is not circular.
group_uniforms mapping;
uniform bool use_radial_uv = false;
// Object-space radius that maps to V = 1.
uniform float radial_extent = 1.0;
// Fraction of a turn the mesh covers. 1.0 full ring, 0.5 half ring.
uniform float radial_arc : hint_range(0.05, 1.0) = 1.0;
// Rotates where U = 0 sits, to place the seam at the mesh opening.
uniform float radial_angle_offset : hint_range(0.0, 1.0) = 0.0;
uniform vec2 radial_center = vec2(0.0, 0.0);
// Flips V, putting 1 at the centre.
uniform bool radial_flip_v = false;
group_uniforms;

group_uniforms foam_layers;
uniform sampler2D tex_a : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_b : hint_default_white, filter_linear_mipmap, repeat_enable;
// Stretches U for both layers, before their own scales.
uniform float scale_width = 1.0;
uniform float a_scale_x = 0.5;
uniform float a_scale_y = 1.3;
uniform float b_scale_x = 2.0;
uniform float b_scale_y = 1.0;
group_uniforms;

group_uniforms motion;
// Scroll rates down the sheet. Horizontal drift is layer A only.
uniform float a_speed = 0.85;
uniform float b_speed = 1.0;
uniform float horizontal_speed = 0.0;
group_uniforms;

group_uniforms colors;
uniform vec4 color_0 : source_color = vec4(0.202, 0.799, 1.0, 1.0);
uniform vec4 color_1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
group_uniforms;

group_uniforms opacity;
// Where the strip is solid. It fades to nothing toward both ends.
uniform float edge_bias : hint_range(0.0, 1.0) = 0.5;
// Lower reaches further, higher tightens the band.
uniform float edge_sharpness : hint_range(0.5, 8.0) = 2.0;
uniform float threshold_bias : hint_range(0.0, 4.0) = 1.0;
// Pixels below this are dropped. Raise for thinner streaks.
uniform float mask_clip : hint_range(0.01, 1.0) = 0.333;
group_uniforms;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec2 src_uv = UV;
	if (use_radial_uv) {
		vec2 d = (v_local.xz - radial_center) / max(radial_extent, 0.001);
		float ang = atan(d.y, d.x) / TAU + 0.5;
		ang = fract((ang - radial_angle_offset) / radial_arc);
		float rad = clamp(length(d), 0.0, 1.0);
		src_uv = vec2(ang, radial_flip_v ? 1.0 - rad : rad);
	}
	vec2 base = vec2(src_uv.x * scale_width, src_uv.y);
	vec2 uv_a = vec2((base.x + TIME * horizontal_speed) * a_scale_x,
			(base.y - TIME * a_speed) * a_scale_y);
	vec2 uv_b = vec2(base.x * b_scale_x,
			(base.y - TIME * b_speed) * b_scale_y);

	// Raw product, no threshold. Keeps the streaks soft.
	float foam = texture(tex_a, uv_a).r * texture(tex_b, uv_b).r;
	float edge = 1.0 - clamp(abs(src_uv.y - edge_bias) * edge_sharpness, 0.0, 1.0);

	ALBEDO = mix(color_0.rgb, color_1.rgb, foam);
	ALPHA = clamp(foam * edge * threshold_bias, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = mask_clip;
}
