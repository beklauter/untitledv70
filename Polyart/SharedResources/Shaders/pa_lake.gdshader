// Still water. Depth-graded colour, scrolling ripple normals, refraction,
// edge foam rings, caustics on the bottom, and its own screen reflections.
shader_type spatial;
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

group_uniforms colors;
uniform vec4 shallow_color : source_color = vec4(0.039, 0.566, 0.641, 1.0);
uniform vec4 deep_color : source_color = vec4(0.0, 0.307, 0.613, 1.0);
uniform float shallow_color_depth = 0.0;
uniform float deep_color_depth = 1.0;
group_uniforms;

group_uniforms surface;
uniform float smoothness_val : hint_range(0.0, 1.0) = 1.0;
// How mirror-like the surface is. 0 is a matte pond.
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
// Strength of the blended wave layers. Also feeds the reflections.
uniform float normals_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

// Two ripple layers, big swells and small chop, blended into one normal.
group_uniforms waves_large;
uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float tiling_a = 2.0;
uniform float speed_a = 0.5;
uniform float strength_a : hint_range(0.0, 2.0) = 1.0;
group_uniforms;
group_uniforms waves_small;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float tiling_b = 6.0;
uniform float speed_b = 0.8;
uniform float strength_b : hint_range(0.0, 2.0) = 0.5;
group_uniforms;
group_uniforms depth_and_clarity;
uniform float refraction_amount : hint_range(0.0, 0.3) = 0.1;
// How much water it takes to turn see-through into solid water colour.
uniform float thickness_depth_min = 0.0;
uniform float thickness_depth_max = 30.0;
// Brightness of the bottom seen through the water. 1.0 is unchanged.
uniform float underwater_brightness = 1.0;
// Metres of depth over which the whole surface fades out at the shore.
uniform float shore_fade_depth : hint_range(0.0, 2.0) = 0.35;
group_uniforms;

group_uniforms edge_foam;
uniform float edge_foam_distance = 0.6;
uniform float edge_foam_speed = 1.0;
uniform float edge_foam_waves = 8.55;
uniform float edge_foam_opacity : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms caustics;
uniform sampler2D caustics_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float caustics_intensity = 1.0;
uniform float caustics_scale = 5.0;
uniform float caustics_distance = 0.0;
uniform float caustics_distortion = 0.0;
group_uniforms;

uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// The water traces its own screen reflections. Screen-space DDA after McGuire
// and Mara, JCGT 2014: the ray is walked pixel by pixel with a
// perspective-correct 1/z.
group_uniforms reflections;
uniform bool ssr_enabled = true;
// March step in pixels. Auto-coarsens on very long rays to stay in budget.
uniform float ssr_stride : hint_range(1.0, 8.0) = 2.0;
uniform float ssr_max_travel : hint_range(5.0, 1000.0) = 60.0;
// Assumed surface thickness in metres. A hit counts when the ray's step
// overlaps that slab.
uniform float ssr_thickness : hint_range(0.05, 4.0) = 0.3;
uniform float ssr_mix_strength : hint_range(0.0, 1.0) = 0.65;
// Softness of the mirror. 0 sharp, 4 very soft.
uniform float ssr_blur : hint_range(0.0, 4.0) = 1.5;
group_uniforms;
uniform sampler2D normal_rough_tex : hint_normal_roughness_texture, filter_nearest;

varying vec3 v_world_pos;

float _scene_z(vec2 suv, mat4 inv_projm) {
	float d = texture(depth_texture, suv).r;
	vec4 vb = inv_projm * vec4(suv * 2.0 - 1.0, d, 1.0);
	return vb.z / vb.w;
}

vec3 _scene_view_pos(vec2 suv, mat4 inv_projm) {
	float d = texture(depth_texture, suv).r;
	vec4 vb = inv_projm * vec4(suv * 2.0 - 1.0, d, 1.0);
	return vb.xyz / vb.w;
}

vec4 _ssr_color(vec3 frag_view_pos, vec3 n_view, mat4 projm, mat4 inv_projm, mat4 inv_viewm, float water_y, vec2 vp_size, float jitter) {
	vec3 view_dir = normalize(frag_view_pos);
	vec3 refl = normalize(reflect(view_dir, n_view));
	// Clip the segment so its end stays in front of the camera plane.
	float travel = ssr_max_travel;
	if (frag_view_pos.z + refl.z * travel > -0.1) {
		travel = (-0.1 - frag_view_pos.z) / refl.z;
	}
	if (travel < 0.05) {
		return vec4(-1.0);
	}
	vec3 v1 = frag_view_pos + refl * travel;
	// Both endpoints in pixel coordinates.
	vec4 c0 = projm * vec4(frag_view_pos, 1.0);
	vec4 c1 = projm * vec4(v1, 1.0);
	vec2 p0 = (c0.xy / c0.w * 0.5 + 0.5) * vp_size;
	vec2 p1 = (c1.xy / c1.w * 0.5 + 0.5) * vp_size;
	vec2 delta = p1 - p0;
	float pixel_len = max(abs(delta.x), abs(delta.y));
	if (pixel_len < 1.0) {
		return vec4(-1.0);
	}
	// Long rays coarsen to stay inside the step budget.
	float stride = max(ssr_stride, pixel_len / 255.0);
	float steps = pixel_len / stride;
	vec2 p_step = delta / steps;
	// 1/z interpolates linearly along the screen line.
	float k0 = -1.0 / frag_view_pos.z;
	float k1 = -1.0 / v1.z;
	float k_step = (k1 - k0) / steps;
	// Sub-step jitter, which turns staircase bands into fine grain.
	vec2 p = p0 + p_step * jitter;
	float k = k0 + k_step * jitter;
	float prev_ray_z = frag_view_pos.z;
	// Entry pixel of the first thing the ray goes behind. Used to cap the
	// silhouette when the ray never comes back out.
	bool fb_set = false;
	vec2 fb_uv = vec2(0.0);
	for (int i = 0; i < 256; i++) {
		if (float(i) >= steps) {
			break;
		}
		p += p_step;
		k += k_step;
		vec2 suv = p / vp_size;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
			break;
		}
		float ray_z = -1.0 / k;
		float rz_min = min(prev_ray_z, ray_z);
		float rz_max = max(prev_ray_z, ray_z);
		prev_ray_z = ray_z;
		float scene_z = _scene_z(suv, inv_projm);
		// Ray jumped the whole slab in one step. Keep the entry pixel if what
		// it went behind stands above the water.
		if (!fb_set && rz_max >= scene_z && ray_z < scene_z - ssr_thickness) {
			vec3 occ_view = _scene_view_pos(suv, inv_projm);
			if ((inv_viewm * vec4(occ_view, 1.0)).y > water_y + 0.05) {
				fb_set = true;
				fb_uv = suv;
			}
		}
		// Hit when the ray's z range across this step overlaps the slab.
		if (rz_max >= scene_z - ssr_thickness && rz_min <= scene_z) {
			// Refine inside the last step for sub-pixel accuracy.
			vec2 lo_p = p - p_step;
			float lo_k = k - k_step;
			vec2 hi_p = p;
			float hi_k = k;
			for (int j = 0; j < 4; j++) {
				vec2 mid_p = (lo_p + hi_p) * 0.5;
				float mid_k = (lo_k + hi_k) * 0.5;
				if (-1.0 / mid_k <= _scene_z(mid_p / vp_size, inv_projm)) {
					hi_p = mid_p;
					hi_k = mid_k;
				} else {
					lo_p = mid_p;
					lo_k = mid_k;
				}
			}
			vec2 huv = hi_p / vp_size;
			vec3 scene_view = _scene_view_pos(huv, inv_projm);
			// Skip anything under the surface.
			float scene_world_y = (inv_viewm * vec4(scene_view, 1.0)).y;
			if (scene_world_y < water_y + 0.05) {
				continue;
			}
			// Ray hit something from behind. Stop and stand in with its
			// blurred, darkened colour.
			vec3 hit_n = texture(normal_rough_tex, huv).xyz * 2.0 - 1.0;
			if (dot(refl, hit_n) > -0.001) {
				vec2 occ_border = smoothstep(vec2(0.0), vec2(0.08), huv)
						* (1.0 - smoothstep(vec2(0.92), vec2(1.0), huv));
				return vec4(textureLod(screen_texture, huv, max(ssr_blur, 2.0)).rgb * 0.65,
						occ_border.x * occ_border.y);
			}
			// Soft fade near the screen edges.
			vec2 border = smoothstep(vec2(0.0), vec2(0.08), huv)
					* (1.0 - smoothstep(vec2(0.92), vec2(1.0), huv));
			return vec4(textureLod(screen_texture, huv, ssr_blur).rgb, border.x * border.y);
		}
	}
	if (fb_set) {
		// Cap the silhouette with its blurred entry pixel, darkened.
		vec2 border = smoothstep(vec2(0.0), vec2(0.08), fb_uv)
				* (1.0 - smoothstep(vec2(0.92), vec2(1.0), fb_uv));
		return vec4(textureLod(screen_texture, fb_uv, max(ssr_blur, 2.0)).rgb * 0.65, border.x * border.y);
	}
	return vec4(-1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Two ripple layers, each sampled twice, blended by strength.
	vec2 a_uv1 = v_world_pos.xz * 0.1 * tiling_a + TIME * speed_a * vec2(0.021, 0.017);
	vec2 a_uv2 = v_world_pos.xz * 0.137 * tiling_a - TIME * speed_a * vec2(0.014, 0.022);
	vec2 na = (texture(normal_map_a, a_uv1).rg * 2.0 - 1.0)
			+ (texture(normal_map_a, a_uv2).rg * 2.0 - 1.0);
	vec2 b_uv1 = v_world_pos.xz * 0.1 * tiling_b + TIME * speed_b * vec2(0.019, -0.023);
	vec2 b_uv2 = v_world_pos.xz * 0.137 * tiling_b - TIME * speed_b * vec2(-0.016, 0.021);
	vec2 nb = (texture(normal_map_b, b_uv1).rg * 2.0 - 1.0)
			+ (texture(normal_map_b, b_uv2).rg * 2.0 - 1.0);
	vec3 nrm = normalize(vec3(na * strength_a * 0.5 + nb * strength_b * 0.5, 1.0));
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normals_strength;

	// Rebuild what sits behind the surface.
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view_behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view_behind.xyz /= view_behind.w;
	float thickness_view = max(-view_behind.z + VERTEX.z, 0.0);
	vec3 world_behind = (INV_VIEW_MATRIX * vec4(view_behind.xyz, 1.0)).xyz;
	float depth_v = max(v_world_pos.y - world_behind.y, 0.0);

	// Water colour by depth.
	float grade = smoothstep(shallow_color_depth, max(deep_color_depth, shallow_color_depth + 0.001), depth_v);
	vec3 water_col = mix(shallow_color.rgb, deep_color.rgb, grade);

	// Refraction. Sample the scene through wobbled UVs.
	vec2 distort = nrm.xy * refraction_amount * clamp(thickness_view, 0.0, 1.0);
	vec3 refracted = texture(screen_texture, SCREEN_UV + distort).rgb * underwater_brightness;

	// Caustics on the bottom, only in the shallows.
	if (caustics_intensity > 0.0 && caustics_distance > 0.0) {
		vec2 cuv = world_behind.xz / max(caustics_scale, 0.01) + nrm.xy * caustics_distortion * 0.1;
		float ca = texture(caustics_tex, cuv + TIME * 0.03).r * texture(caustics_tex, cuv * 1.3 - TIME * 0.021).r;
		float cfall = 1.0 - clamp(depth_v / max(caustics_distance, 0.001), 0.0, 1.0);
		refracted += ca * caustics_intensity * cfall;
	}

	float absorb = clamp((thickness_view - thickness_depth_min) /
			max(thickness_depth_max - thickness_depth_min, 0.001), 0.0, 1.0);
	absorb = 1.0 - exp(-absorb * 4.0);
	vec3 col = mix(refracted, water_col, max(absorb, grade * 0.7));

	// Moving foam rings against shores and obstacles.
	if (edge_foam_distance > 0.0 && depth_v < edge_foam_distance) {
		float t = 1.0 - depth_v / edge_foam_distance;
		float rings = sin(t * edge_foam_waves * 3.1416 - TIME * edge_foam_speed) * 0.5 + 0.5;
		float noise = texture(noise_tex, v_world_pos.xz * 0.15 + TIME * vec2(0.01, 0.013)).r;
		float foam = smoothstep(0.45, 0.75, rings * (0.55 + 0.45 * noise)) * t;
		col = mix(col, vec3(1.0), foam * edge_foam_opacity * 2.0);
	}

	if (ssr_enabled) {
		vec3 n_view = normalize(NORMAL + (TANGENT * nrm.x + BINORMAL * nrm.y) * normals_strength * 0.6);
		// Steady per-pixel jitter for the ray march.
		float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		vec4 ssr = _ssr_color(VERTEX, n_view, PROJECTION_MATRIX, INV_PROJECTION_MATRIX,
				INV_VIEW_MATRIX, v_world_pos.y, VIEWPORT_SIZE, jitter);
		if (ssr.x >= 0.0) {
			float grazing = pow(1.0 - clamp(dot(-normalize(VERTEX), n_view), 0.0, 1.0), 1.5);
			col = mix(col, ssr.rgb, ssr_mix_strength * ssr.a * (0.35 + 0.65 * grazing));
		}
	}

	ALBEDO = col;
	ROUGHNESS = clamp(1.0 - smoothness_val, 0.02, 1.0);
	SPECULAR = 0.5;
	METALLIC = metallic;
	ALPHA = smoothstep(0.0, max(shore_fade_depth, 0.001), depth_v);
}
