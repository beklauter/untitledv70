// Opaque-pass lake, for use with Godot's built-in screen reflections.
// Depth is read from a terrain heightmap, which has to be wired up.
// Same look as pa_lake, minus refraction.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.039, 0.566, 0.641, 1.0);
uniform vec4 deep_color : source_color = vec4(0.0, 0.307, 0.613, 1.0);
uniform float shallow_color_depth = 0.0;
uniform float deep_color_depth = 1.0;
uniform float smoothness_val : hint_range(0.0, 1.0) = 1.0;
uniform float reflectivity : hint_range(0.0, 1.0) = 0.7;

uniform sampler2D water_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_tiling = 2.0;
uniform float normals_speed = 0.5;
uniform float normals_strength : hint_range(0.0, 1.0) = 1.0;

// World XZ maps to UV through origin and size. Height is texel * range + min.
// Float EXR holds raw metres: min 0, range 1. A 16-bit PNG needs its own.
uniform sampler2D terrain_heightmap : hint_default_black, filter_linear;
uniform vec2 terrain_origin_xz = vec2(-50.0, -50.0);
uniform vec2 terrain_size_xz = vec2(100.0, 100.0);
uniform float terrain_height_min = 0.0;
uniform float terrain_height_range = 1.0;

uniform float edge_foam_distance = 0.6;
uniform float edge_foam_speed = 1.0;
uniform float edge_foam_waves = 8.55;
uniform float edge_foam_opacity : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform sampler2D caustics_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float caustics_intensity = 1.0;
uniform float caustics_scale = 5.0;
uniform float caustics_distance = 0.0;
uniform float caustics_distortion = 0.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = v_world_pos.xz * 0.1 * normal_tiling + TIME * normals_speed * vec2(0.021, 0.017);
	vec2 uv2 = v_world_pos.xz * 0.137 * normal_tiling - TIME * normals_speed * vec2(0.014, 0.022);
	vec3 n1 = texture(water_normal_map, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_normal_map, uv2).rgb * 2.0 - 1.0;
	vec3 nrm = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normals_strength;

	vec2 huv = (v_world_pos.xz - terrain_origin_xz) / terrain_size_xz;
	float ground_h = texture(terrain_heightmap, clamp(huv, vec2(0.0), vec2(1.0))).r
			* terrain_height_range + terrain_height_min;
	float depth_v = max(v_world_pos.y - ground_h, 0.0);

	float grade = smoothstep(shallow_color_depth, max(deep_color_depth, shallow_color_depth + 0.001), depth_v);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, grade);

	if (caustics_intensity > 0.0 && caustics_distance > 0.0) {
		vec2 cuv = v_world_pos.xz / max(caustics_scale, 0.01) + nrm.xy * caustics_distortion * 0.1;
		float ca = texture(caustics_tex, cuv + TIME * 0.03).r * texture(caustics_tex, cuv * 1.3 - TIME * 0.021).r;
		float cfall = 1.0 - clamp(depth_v / max(caustics_distance, 0.001), 0.0, 1.0);
		col += ca * caustics_intensity * cfall * (1.0 - grade);
	}

	if (edge_foam_distance > 0.0 && depth_v < edge_foam_distance) {
		float t = 1.0 - depth_v / edge_foam_distance;
		float rings = sin(t * edge_foam_waves * 3.1416 - TIME * edge_foam_speed) * 0.5 + 0.5;
		float noise = texture(noise_tex, v_world_pos.xz * 0.15 + TIME * vec2(0.01, 0.013)).r;
		float foam = smoothstep(0.45, 0.75, rings * (0.55 + 0.45 * noise)) * t;
		col = mix(col, vec3(1.0), foam * edge_foam_opacity * 2.0);
	}

	ALBEDO = col;
	ROUGHNESS = clamp(1.0 - smoothness_val, 0.02, 1.0);
	SPECULAR = 0.5;
	METALLIC = reflectivity;
}
