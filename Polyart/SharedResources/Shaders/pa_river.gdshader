// River water. The pa_lake feature set plus flow: ripples and foam pan along
// the mesh's V axis, waves stretch lengthwise, a turbulence layer bends the
// current, and the surface bobs. Built for PARiverSpline ribbons, where U runs
// across and V runs in metres along the curve.
// Keep the shared parts in sync with pa_lake.gdshader.
shader_type spatial;
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

group_uniforms colors;
uniform vec4 shallow_color : source_color = vec4(0.25, 0.55, 0.65, 1.0);
uniform vec4 deep_color : source_color = vec4(0.121, 0.348, 0.547, 1.0);
uniform float shallow_color_depth = 0.0;
uniform float deep_color_depth = 1.2;
group_uniforms;

group_uniforms surface;
uniform float smoothness_val : hint_range(0.0, 1.0) = 0.85;
// How mirror-like the surface is. 0 is a matte pond.
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
group_uniforms;

group_uniforms flow;
// V units per second the water travels.
uniform float flow_speed = 0.25;
// Wave stretch along the flow. 1 is round ripples, 3 is a streaked current.
uniform float flow_stretch : hint_range(1.0, 6.0) = 2.5;
// Slow wobble that bends the current lines.
uniform float turbulence_scale = 0.5;
uniform float turbulence_strength : hint_range(0.0, 0.3) = 0.08;
// Surface bob, read from a height texture. Needs a dense enough mesh: see the
// PARiverSpline step and width_segments.
uniform sampler2D displacement_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float displace_strength : hint_range(0.0, 2.0) = 0.05;
// Tiling. X repeats across the width, Y repeats per V unit along.
uniform vec2 displace_tiling = vec2(0.5, 0.5);
// Pan rate of the bob, as a multiple of flow_speed. Negative reverses it.
uniform float displace_pan_speed : hint_range(-5.0, 5.0) = 1.0;
group_uniforms;

group_uniforms waves;
uniform sampler2D water_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_tiling = 3.0;
uniform float normals_strength : hint_range(0.0, 1.0) = 0.35;
// Second ripple layer. Tiling and pan are multipliers on the first.
uniform float normal2_tiling_mul : hint_range(1.0, 4.0) = 1.5;
uniform float normal2_speed_mul : hint_range(0.5, 4.0) = 1.5;
group_uniforms;

group_uniforms depth_and_clarity;
uniform float refraction_amount : hint_range(0.0, 0.3) = 0.06;
// How much water it takes to turn see-through into solid water colour.
uniform float thickness_depth_min = 0.0;
uniform float thickness_depth_max = 6.0;
// Brightness of the bed seen through the water. 1.0 is unchanged.
uniform float underwater_brightness = 1.0;
// Metres of depth over which the whole surface fades out at the banks.
uniform float shore_fade_depth : hint_range(0.0, 2.0) = 0.25;
group_uniforms;

group_uniforms edge_foam;
uniform float edge_foam_distance = 0.4;
uniform float edge_foam_speed = 2.0;
uniform float edge_foam_waves = 6.0;
uniform float edge_foam_opacity : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
group_uniforms;

group_uniforms caustics;
uniform sampler2D caustics_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float caustics_intensity = 0.8;
uniform float caustics_scale = 0.8;
uniform float caustics_distance = 0.9;
uniform float caustics_distortion = 0.0;
group_uniforms;

uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Screen reflections. Same ray march as pa_lake.
group_uniforms reflections;
uniform bool ssr_enabled = true;
uniform float ssr_stride : hint_range(1.0, 8.0) = 2.0;
uniform float ssr_max_travel : hint_range(5.0, 1000.0) = 200.0;
uniform float ssr_thickness : hint_range(0.05, 4.0) = 0.3;
uniform float ssr_mix_strength : hint_range(0.0, 1.0) = 0.7;
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
	float travel = ssr_max_travel;
	if (frag_view_pos.z + refl.z * travel > -0.1) {
		travel = (-0.1 - frag_view_pos.z) / refl.z;
	}
	if (travel < 0.05) {
		return vec4(-1.0);
	}
	vec3 v1 = frag_view_pos + refl * travel;
	vec4 c0 = projm * vec4(frag_view_pos, 1.0);
	vec4 c1 = projm * vec4(v1, 1.0);
	vec2 p0 = (c0.xy / c0.w * 0.5 + 0.5) * vp_size;
	vec2 p1 = (c1.xy / c1.w * 0.5 + 0.5) * vp_size;
	vec2 delta = p1 - p0;
	float pixel_len = max(abs(delta.x), abs(delta.y));
	if (pixel_len < 1.0) {
		return vec4(-1.0);
	}
	float stride = max(ssr_stride, pixel_len / 255.0);
	float steps = pixel_len / stride;
	vec2 p_step = delta / steps;
	float k0 = -1.0 / frag_view_pos.z;
	float k1 = -1.0 / v1.z;
	float k_step = (k1 - k0) / steps;
	vec2 p = p0 + p_step * jitter;
	float k = k0 + k_step * jitter;
	float prev_ray_z = frag_view_pos.z;
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
		if (!fb_set && rz_max >= scene_z && ray_z < scene_z - ssr_thickness) {
			vec3 occ_view = _scene_view_pos(suv, inv_projm);
			if ((inv_viewm * vec4(occ_view, 1.0)).y > water_y + 0.05) {
				fb_set = true;
				fb_uv = suv;
			}
		}
		if (rz_max >= scene_z - ssr_thickness && rz_min <= scene_z) {
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
			float scene_world_y = (inv_viewm * vec4(scene_view, 1.0)).y;
			if (scene_world_y < water_y + 0.05) {
				continue;
			}
			vec3 hit_n = texture(normal_rough_tex, huv).xyz * 2.0 - 1.0;
			if (dot(refl, hit_n) > -0.001) {
				vec2 occ_border = smoothstep(vec2(0.0), vec2(0.08), huv)
						* (1.0 - smoothstep(vec2(0.92), vec2(1.0), huv));
				return vec4(textureLod(screen_texture, huv, max(ssr_blur, 2.0)).rgb * 0.65,
						occ_border.x * occ_border.y);
			}
			vec2 border = smoothstep(vec2(0.0), vec2(0.08), huv)
					* (1.0 - smoothstep(vec2(0.92), vec2(1.0), huv));
			return vec4(textureLod(screen_texture, huv, ssr_blur).rgb, border.x * border.y);
		}
	}
	if (fb_set) {
		vec2 border = smoothstep(vec2(0.0), vec2(0.08), fb_uv)
				* (1.0 - smoothstep(vec2(0.92), vec2(1.0), fb_uv));
		return vec4(textureLod(screen_texture, fb_uv, max(ssr_blur, 2.0)).rgb * 0.65, border.x * border.y);
	}
	return vec4(-1.0);
}

void vertex() {
	// The surface bobs downstream with the current.
	float bob = texture(displacement_tex, UV * displace_tiling
			+ vec2(0.0, -TIME * flow_speed * displace_pan_speed)).r;
	VERTEX.y += (bob - 0.5) * displace_strength;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Ripples stretched along V, at two speeds, bent by the turbulence layer.
	vec2 flow_base = UV * vec2(normal_tiling, normal_tiling / max(flow_stretch, 0.1));
	vec2 turb = (texture(water_normal_map, UV * turbulence_scale
			+ vec2(0.0, -TIME * flow_speed * 0.3)).rg * 2.0 - 1.0) * turbulence_strength;
	vec2 uv1 = flow_base + vec2(0.0, -TIME * flow_speed) + turb;
	vec2 uv2 = flow_base * normal2_tiling_mul + vec2(0.05, -TIME * flow_speed * normal2_speed_mul) + turb * 0.6;
	vec3 n1 = texture(water_normal_map, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_normal_map, uv2).rgb * 2.0 - 1.0;
	vec3 nrm = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
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

	// Caustics on the bed, shallows only. Anchored in world space.
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

	// Bank foam, same rings as the lake, with the noise riding the current.
	if (edge_foam_distance > 0.0 && depth_v < edge_foam_distance) {
		float t = 1.0 - depth_v / edge_foam_distance;
		float rings = sin(t * edge_foam_waves * 3.1416 - TIME * edge_foam_speed) * 0.5 + 0.5;
		float noise = texture(noise_tex, vec2(UV.x * 1.5, UV.y * 3.0 - TIME * flow_speed * 1.2)).r;
		float foam = smoothstep(0.45, 0.75, rings * (0.55 + 0.45 * noise)) * t;
		col = mix(col, vec3(1.0), foam * edge_foam_opacity * 2.0);
	}

	if (ssr_enabled) {
		vec3 n_view = normalize(NORMAL + (TANGENT * nrm.x + BINORMAL * nrm.y) * normals_strength * 0.6);
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
