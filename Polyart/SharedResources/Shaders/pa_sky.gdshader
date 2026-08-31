// Gradient sky with a sun disc and up to three scrolling cloud layers.
// The sun follows the scene's DirectionalLight.
shader_type sky;

group_uniforms sky_gradient;
uniform vec4 top_color : source_color = vec4(0.32, 0.55, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.88, 0.95, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.55, 0.63, 0.71, 1.0);
uniform float horizon_min = 0.0;
uniform float horizon_max = 0.35;
uniform float gradience_pow : hint_range(0.2, 4.0) = 1.0;
group_uniforms;

group_uniforms sun;
uniform float sun_scale : hint_range(0.2, 10.0) = 3.0;
uniform vec4 sun_inner_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform vec4 sun_outer_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec4 sun_glow_color : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform float sun_glow_scale : hint_range(0.0, 1.0) = 0.6;
group_uniforms;

group_uniforms distortion;
uniform sampler2D distortion_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float distortion_scale = 20.0;
uniform float distortion_speed = 25.0;
group_uniforms;

// Each layer has its own texture. Godot cannot pass samplers into functions,
// so layers sample at top level through _cloud_uv, then _cloud_apply blends.
group_uniforms cloud_layer_1;
uniform sampler2D l1_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 l1_tiling = vec2(2.0, 1.0);
uniform vec2 l1_offset = vec2(0.0, 0.0);
uniform float l1_pan_speed = 0.0007;
uniform vec4 l1_bright : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 l1_dark : source_color = vec4(0.75, 0.8, 0.88, 1.0);
uniform float l1_max_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float l1_op_min = 0.1;
uniform float l1_op_max = 0.8;
uniform float l1_distortion = 0.02;
group_uniforms;

group_uniforms cloud_layer_2;
uniform sampler2D l2_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 l2_tiling = vec2(3.0, 1.0);
uniform vec2 l2_offset = vec2(0.74, 0.0);
uniform float l2_pan_speed = 0.001;
uniform vec4 l2_bright : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 l2_dark : source_color = vec4(0.72, 0.78, 0.85, 1.0);
uniform float l2_max_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float l2_op_min = 0.2;
uniform float l2_op_max = 0.8;
uniform float l2_distortion = 0.01;
group_uniforms;

group_uniforms cloud_layer_3;
uniform sampler2D l3_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 l3_tiling = vec2(4.0, 1.0);
uniform vec2 l3_offset = vec2(0.43, 0.0);
uniform float l3_pan_speed = 0.0008;
uniform vec4 l3_bright : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 l3_dark : source_color = vec4(0.85, 0.88, 0.92, 1.0);
uniform float l3_max_opacity : hint_range(0.0, 1.0) = 0.25;
uniform float l3_op_min = 0.3;
uniform float l3_op_max = 0.9;
uniform float l3_distortion = 0.01;
group_uniforms;

// The cloud texture wraps the dome as a strip. U goes around the horizon,
// V climbs from the horizon to the top. Use whole numbers on X tiling or the
// wrap seams. V is clamped.
vec2 _cloud_uv(vec3 eyedir, vec2 tiling, vec2 offset, float pan, float dist_amt) {
	float az = atan(eyedir.x, eyedir.z) / 6.2831853 + 0.5;
	float elev = clamp(eyedir.y, 0.0, 1.0);
	vec2 uv = vec2(az * tiling.x, (1.0 - elev) * tiling.y) + offset + TIME * pan * vec2(1.0, 0.0);
	vec2 n = texture(distortion_noise, uv * distortion_scale * 0.01 + TIME * distortion_speed * 0.0002).rg;
	uv += (n - 0.25) * dist_amt;
	uv.y = clamp(uv.y, 0.001, 0.999);
	return uv;
}

vec3 _cloud_apply(vec3 col, float c, vec4 bright, vec4 dark,
		float max_op, float op_min, float op_max) {
	vec3 cloud_col = mix(dark.rgb, bright.rgb, smoothstep(0.3, 1.0, c));
	float op = smoothstep(op_min, op_max, c) * max_op;
	return mix(col, cloud_col, op);
}

void sky() {
	float h = EYEDIR.y;
	vec3 col;
	if (h < 0.0) {
		col = bottom_color.rgb;
	} else {
		float t = pow(smoothstep(horizon_min, max(horizon_max, horizon_min + 0.001), h), gradience_pow);
		col = mix(horizon_color.rgb, top_color.rgb, t);
	}

	if (LIGHT0_ENABLED) {
		float sun_amount = clamp(dot(EYEDIR, LIGHT0_DIRECTION), 0.0, 1.0);
		float ang = degrees(acos(sun_amount));
		float disc = 1.0 - smoothstep(sun_scale * 0.5, sun_scale * 0.65, ang);
		float rim = 1.0 - smoothstep(sun_scale * 0.35, sun_scale * 0.6, ang);
		vec3 sun = mix(sun_outer_color.rgb, sun_inner_color.rgb, rim) * disc;
		float glow_pow = mix(220.0, 10.0, clamp(sun_glow_scale, 0.0, 1.0));
		vec3 glow = sun_glow_color.rgb * pow(sun_amount, glow_pow) * 0.6;
		col = col + glow;
		col = mix(col, sun, disc);
	}

	if (EYEDIR.y > 0.0) {
		if (l1_max_opacity > 0.001) {
			float c1 = texture(l1_tex, _cloud_uv(EYEDIR, l1_tiling, l1_offset, l1_pan_speed, l1_distortion)).r;
			col = _cloud_apply(col, c1, l1_bright, l1_dark, l1_max_opacity, l1_op_min, l1_op_max);
		}
		if (l2_max_opacity > 0.001) {
			float c2 = texture(l2_tex, _cloud_uv(EYEDIR, l2_tiling, l2_offset, l2_pan_speed, l2_distortion)).r;
			col = _cloud_apply(col, c2, l2_bright, l2_dark, l2_max_opacity, l2_op_min, l2_op_max);
		}
		if (l3_max_opacity > 0.001) {
			float c3 = texture(l3_tex, _cloud_uv(EYEDIR, l3_tiling, l3_offset, l3_pan_speed, l3_distortion)).r;
			col = _cloud_apply(col, c3, l3_bright, l3_dark, l3_max_opacity, l3_op_min, l3_op_max);
		}
	}

	COLOR = col;
}


