// Tree bark. Colour plus optional ORM and normal maps, a moss layer on
// up-facing surfaces, darkening toward the ground, and a gentle sway.
shader_type spatial;

group_uniforms base;
uniform sampler2D color_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_size = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0);
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_intensity : hint_range(0.0, 2.0) = 0.0;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_intensity : hint_range(0.0, 2.0) = 1.0;
group_uniforms;

group_uniforms coverage;
uniform bool enable_coverage = false;
uniform sampler2D coverage_color_map : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D coverage_orm_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D coverage_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float coverage_size = 1.0;
uniform float coverage_roughness_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float slope_offset = 0.0;
uniform float slope_contrast = 1.0;
group_uniforms;

group_uniforms bottom_darken;
uniform bool darken_bottom = false;
uniform vec4 darken_tint : source_color = vec4(0.5, 0.45, 0.4, 1.0);
uniform float darken_distance = 1.0;
uniform float darken_gradience = 1.0;
group_uniforms;

group_uniforms wind;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_speed = 1.0;
uniform float wind_intensity = 0.05;
group_uniforms;

varying vec3 v_world_normal;
varying float v_local_y;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_local_y = VERTEX.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = TIME * wind_speed + _hash(origin.xz) * 6.28;
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	float sway = sin(phase) * 0.5 + sin(phase * 0.41) * 0.5;
	VERTEX.xz += dir * sway * wind_intensity * max(VERTEX.y, 0.0);
}

void fragment() {
	vec2 uv = UV * uv_size;
	vec4 base = texture(color_map, uv) * color_tint;
	vec4 orm = texture(orm_map, uv);
	vec3 nrm = texture(normal_map, uv).rgb;
	float nrm_depth = normal_intensity;

	if (enable_coverage) {
		float up = clamp((v_world_normal.y + slope_offset) * slope_contrast, 0.0, 1.0);
		float mask = smoothstep(0.25, 0.75, up);
		vec2 cuv = uv * coverage_size;
		base.rgb = mix(base.rgb, texture(coverage_color_map, cuv).rgb, mask);
		vec4 corm = texture(coverage_orm_map, cuv);
		corm.g *= coverage_roughness_intensity;
		orm = mix(orm, corm, mask);
		nrm = mix(nrm, texture(coverage_normal_map, cuv).rgb, mask);
	}

	if (darken_bottom) {
		float f = 1.0 - smoothstep(0.0, max(darken_distance * darken_gradience, 0.001), v_local_y);
		base.rgb = mix(base.rgb, base.rgb * darken_tint.rgb, f);
	}

	ALBEDO = base.rgb;
	AO = mix(1.0, orm.r, ao_intensity);
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = clamp(orm.g * roughness_intensity, 0.0, 1.0);
	METALLIC = clamp(orm.b * metallic_intensity, 0.0, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = nrm_depth;
}
