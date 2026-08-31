
group_uniforms base;
uniform sampler2D color_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 color_tint : source_color = vec4(1.0);
uniform float uv_size = 1.0;
group_uniforms;

group_uniforms intensities;
uniform float normal_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float ao_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_clip : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

group_uniforms emissive;
uniform sampler2D emissive_map : source_color, hint_default_black, filter_linear_mipmap;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_intensity = 0.0;
group_uniforms;

group_uniforms coverage;
uniform bool enable_coverage = false;
uniform sampler2D coverage_color_map : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D coverage_orm_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D coverage_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float coverage_size = 1.0;
uniform float coverage_normal_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float coverage_roughness_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float coverage_metallic_intensity : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D slope_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_size = 1.0;
uniform float slope_offset = 0.0;
uniform float slope_contrast = 1.0;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
#ifdef PROPS_TWO_SIDED
	// Flip backface normals so both sides light evenly.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	vec2 uv = UV * uv_size;
	vec4 base = texture(color_map, uv) * color_tint;
	vec4 orm = texture(orm_map, uv);
	vec3 nrm = texture(normal_map, uv).rgb;
	float nrm_depth = normal_intensity;

	if (enable_coverage) {
		// Top-down projection, so coverage sits on up-facing surfaces.
		// slope_offset shifts the threshold, slope_contrast sharpens the
		// edge, noise frays the border.
		float up = clamp(normalize(v_world_normal).y, 0.0, 1.0);
		float noise = texture(slope_noise, v_world_pos.xz * 0.1 * noise_size).r;
		float threshold = 0.25 - slope_offset + (noise - 0.5) * 0.2;
		float mask = clamp((up - threshold) * 4.0 * max(slope_contrast, 0.05), 0.0, 1.0);
		vec2 cuv = uv * coverage_size;
		base = mix(base, texture(coverage_color_map, cuv) * color_tint, mask);
		vec4 corm = texture(coverage_orm_map, cuv);
		corm.g *= coverage_roughness_intensity;
		corm.b *= coverage_metallic_intensity;
		orm = mix(orm, corm, mask);
		nrm = mix(nrm, texture(coverage_normal_map, cuv).rgb, mask);
		nrm_depth = mix(normal_intensity, coverage_normal_intensity, mask);
	}

	ALBEDO = base.rgb;
	AO = mix(1.0, orm.r, ao_intensity);
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = clamp(orm.g * roughness_intensity, 0.0, 1.0);
	METALLIC = clamp(orm.b * metallic_intensity, 0.0, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = nrm_depth;
	EMISSION = texture(emissive_map, uv).rgb * emissive_color.rgb * emissive_intensity;
	if (alpha_clip > 0.0) {
		ALPHA = base.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_clip;
	}
}

