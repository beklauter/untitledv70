// Background mountains and other big sculpted surfaces.
// mesh_normal_tex is the baked whole-mesh normal map. It lights the low-poly
// mesh and drives the grass to stone blend. The top and side textures tile in
// world space, and world noise frays the blend edge.
shader_type spatial;
render_mode cull_back;

group_uniforms textures;
uniform sampler2D top_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D top_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D side_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D side_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mesh_normal_tex : hint_default_transparent, filter_linear_mipmap;
// How far the baked normal map wins over the tiling detail normals.
uniform float mesh_normal_weight : hint_range(0.0, 1.0) = 0.6;
group_uniforms;

group_uniforms mapping;
uniform float top_tiling = 0.35;
uniform float side_tiling = 0.22;
uniform vec4 top_tint : source_color = vec4(1.0);
uniform vec4 side_tint : source_color = vec4(1.0);
group_uniforms;

group_uniforms blending;
// Slope where stone takes over. 0 is flat ground, 1 is a vertical cliff.
uniform float slope_start : hint_range(0.0, 1.0) = 0.55;
uniform float slope_end : hint_range(0.0, 1.0) = 0.8;
// World noise pushed into the slope threshold, to fray the blend edge.
uniform float blend_noise_strength : hint_range(0.0, 1.0) = 0.18;
uniform float blend_noise_scale = 14.0;
group_uniforms;

group_uniforms surface;
uniform float normal_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

varying vec3 v_wpos;
varying vec3 v_wnormal;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_hash(i), _hash(i + vec2(1, 0)), u.x),
			mix(_hash(i + vec2(0, 1)), _hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnormal);
	vec3 an = abs(n);

	// Top layer: world XZ
	vec2 top_uv = v_wpos.xz * top_tiling;
	vec3 top = texture(top_tex, top_uv).rgb * top_tint.rgb;
	vec3 top_nrm = texture(top_normal_tex, top_uv).rgb;

	// Side layer: world triplanar on the two wall planes
	float wsum = max(an.x + an.z, 0.001);
	vec2 side_uv_x = v_wpos.zy * side_tiling;
	vec2 side_uv_z = v_wpos.xy * side_tiling;
	vec3 side = (texture(side_tex, side_uv_x).rgb * an.x
		+ texture(side_tex, side_uv_z).rgb * an.z) / wsum * side_tint.rgb;
	vec3 side_nrm = (texture(side_normal_tex, side_uv_x).rgb * an.x
		+ texture(side_normal_tex, side_uv_z).rgb * an.z) / wsum;

	// Slope blend from the geometry, plus the ragged noise edge
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float noise = (_vnoise(v_wpos.xz / max(blend_noise_scale, 0.1)) - 0.5) * blend_noise_strength;
	float steep = smoothstep(slope_start, slope_end, slope + noise);

	ALBEDO = mix(top, side, steep);

	// Baked whole-mesh normal map over the tiling detail normals.
	vec3 detail_nrm = mix(top_nrm, side_nrm, steep);
	vec4 baked = texture(mesh_normal_tex, UV);
	NORMAL_MAP = baked.a > 0.5 ? mix(detail_nrm, baked.rgb, mesh_normal_weight) : detail_nrm;
	NORMAL_MAP_DEPTH = normal_intensity;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.1;
}
