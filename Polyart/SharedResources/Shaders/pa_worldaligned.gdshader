// Triplanar surface. Colour, normal and roughness are sampled in world space,
// so scattered rocks and pebbles blend into the ground.
shader_type spatial;

group_uniforms textures;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms surface;
uniform vec2 tiling = vec2(1.0, 1.0);
uniform float normal_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float smoothness_intensity : hint_range(-1.0, 1.0) = 1.0;
uniform float blend_sharpness : hint_range(1.0, 16.0) = 4.0;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(blend_sharpness));
	w /= (w.x + w.y + w.z);
	vec2 uv_x = v_world_pos.zy * tiling;
	vec2 uv_y = v_world_pos.xz * tiling;
	vec2 uv_z = v_world_pos.xy * tiling;

	vec3 albedo = texture(albedo_tex, uv_x).rgb * w.x
		+ texture(albedo_tex, uv_y).rgb * w.y
		+ texture(albedo_tex, uv_z).rgb * w.z;
	float rough = texture(roughness_tex, uv_x).r * w.x
		+ texture(roughness_tex, uv_y).r * w.y
		+ texture(roughness_tex, uv_z).r * w.z;

	// Triplanar normal blend in world space.
	vec3 tn_x = texture(normal_tex, uv_x).rgb * 2.0 - 1.0;
	vec3 tn_y = texture(normal_tex, uv_y).rgb * 2.0 - 1.0;
	vec3 tn_z = texture(normal_tex, uv_z).rgb * 2.0 - 1.0;
	vec3 nx = vec3(0.0, tn_x.y, tn_x.x) * w.x;
	vec3 ny = vec3(tn_y.x, 0.0, tn_y.y) * w.y;
	vec3 nz = vec3(tn_z.x, tn_z.y, 0.0) * w.z;
	vec3 world_n = normalize(n + (nx + ny + nz) * normal_intensity);

	ALBEDO = albedo;
	ROUGHNESS = clamp(1.0 - (1.0 - rough) * max(smoothness_intensity, 0.0), 0.05, 1.0);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}
