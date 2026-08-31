// Baked billboard cards, the last LOD of each tree. Static cutout quads with
// a foliage atlas and a top to bottom colour gradient.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

group_uniforms textures;
uniform sampler2D foliage_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false;
group_uniforms;

group_uniforms tint;
uniform vec4 color_top : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 color_bottom : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float bottom_level = 0.0;
uniform float bottom_fade : hint_range(-1.0, 0.0) = 0.0;
group_uniforms;

group_uniforms surface;
uniform float smoothness_val : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_clip : hint_range(0.0, 1.0) = 0.35;
uniform bool cull_backfaces = false;
group_uniforms;

varying float v_local_y;

void vertex() {
	v_local_y = VERTEX.y;
}

void fragment() {
	if (cull_backfaces && !FRONT_FACING) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 tex = texture(foliage_tex, UV);
	// The atlas is greyscale, so the tints always apply. Their alpha is unused.
	// bottom_level is in local mesh height.
	float band = max(-bottom_fade, 0.001) * 10.0 + 0.001;
	float g = smoothstep(bottom_level, bottom_level + band, v_local_y);
	vec3 tint = mix(color_bottom.rgb, color_top.rgb, g);
	ALBEDO = tex.rgb * tint;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_clip;
	ROUGHNESS = 1.0 - smoothness_val;
	SPECULAR = 0.05;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
