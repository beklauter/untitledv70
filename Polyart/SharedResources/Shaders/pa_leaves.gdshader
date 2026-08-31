// Tree canopies. Tinted flat or by height gradient, broad colour variation,
// backlight through the leaves, an edge-on fade to kill moire, and two wind
// parts: branch sway and leaf wiggle. Vertex colour G is painted AO.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

group_uniforms color;
uniform sampler2D color_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float tiling = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0);
group_uniforms;

group_uniforms height_gradient;
uniform bool use_height_gradience = false;
uniform vec4 color_bottom : source_color = vec4(0.27, 0.45, 0.16, 1.0);
uniform vec4 color_top : source_color = vec4(0.44, 0.66, 0.12, 1.0);
uniform float grad_smoothstep_min = 0.0;
uniform float grad_smoothstep_max = 1.0;
uniform float height_gradience = 1.0;
uniform float height_weight = 1.0;
group_uniforms;

group_uniforms variation;
uniform float variation_scale = 1.0;
uniform float variation_contrast = 0.0;
uniform float hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform vec4 painted_ao_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
group_uniforms;

group_uniforms alpha;
uniform float alpha_clip : hint_range(0.0, 1.0) = 0.5;
// Mipmaps shrink alpha coverage with distance, so the clip threshold relaxes
// as the camera pulls back.
uniform float alpha_far_mul : hint_range(0.1, 1.0) = 0.45;
uniform float alpha_far_start = 12.0;
uniform float alpha_far_range = 30.0;
group_uniforms;

group_uniforms surface;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;
uniform bool cull_backfaces = false;
uniform bool fade_at_glancing = false;
uniform float glancing_mul = 1.0;
group_uniforms;

group_uniforms subsurface;
// Light coming through the leaf toward the camera adds a tinted glow.
// Runs in a custom light() pass. The built-in backlight channel does not
// survive the two-sided normal flip.
uniform bool enable_ss = false;
uniform vec4 ss_color : source_color = vec4(0.55, 0.65, 0.2, 1.0);
uniform float ss_strength : hint_range(0.0, 8.0) = 2.0;
uniform float ss_power : hint_range(0.5, 16.0) = 4.0;
uniform float ss_distortion : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

group_uniforms wind;
uniform vec2 sway_direction = vec2(1.0, 0.3);
uniform float sway_speed = 1.0;
uniform float sway_intensity = 0.15;
uniform float wiggle_speed_large = 2.0;
uniform float wiggle_speed_small = 5.0;
uniform float wiggle_size = 8.0;
uniform float wiggle_intensity = 0.04;
group_uniforms;

varying float v_h01;
varying vec3 v_wpos;
varying float v_view_dist;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_hash(i), _hash(i + vec2(1, 0)), u.x),
			mix(_hash(i + vec2(0, 1)), _hash(i + vec2(1, 1)), u.x), u.y) * 2.0 - 1.0;
}

vec3 _hue_rotate(vec3 c, float h) {
	float a = h * 6.2831853;
	vec3 k = vec3(0.57735);
	return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

void vertex() {
	v_h01 = clamp(VERTEX.y * height_weight / max(height_gradience, 0.001), 0.0, 1.0);
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wpos = wpos;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = TIME * sway_speed + _hash(origin.xz) * 6.28;
	vec2 dir = normalize(sway_direction + vec2(0.0001));
	float sway = sin(phase) * 0.5 + sin(phase * 0.37) * 0.5;
	VERTEX.xz += dir * sway * sway_intensity * v_h01;
	float wl = _vnoise(VERTEX.xz * wiggle_size + TIME * wiggle_speed_large);
	float ws = sin(TIME * wiggle_speed_small + dot(VERTEX, vec3(12.9, 78.2, 37.7)));
	VERTEX += NORMAL * (wl * 0.6 + ws * 0.4) * wiggle_intensity;
	v_view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	if (cull_backfaces && !FRONT_FACING) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 tex = texture(color_map, UV * tiling);
	vec3 tint = use_height_gradience
		? mix(color_bottom.rgb, color_top.rgb, smoothstep(grad_smoothstep_min, grad_smoothstep_max, v_h01))
		: color_tint.rgb;
	vec3 albedo = tex.rgb * tint;
	// Brightness variation in broad patches, capped at 30%.
	float vn = _vnoise(v_wpos.xz / max(variation_scale * 6.0, 0.1)) * 0.5 + 0.5;
	albedo *= 1.0 + (vn - 0.5) * 0.6 * clamp(variation_contrast, 0.0, 1.0);
	albedo = _hue_rotate(albedo, hue_shift);
	float painted_ao = mix(1.0, COLOR.g, painted_ao_color.a);
	albedo = mix(painted_ao_color.rgb, albedo, painted_ao);
	ALBEDO = albedo;

	float a = tex.a;
	if (fade_at_glancing) {
		// Fade only when the card is seen edge-on. glancing_mul widens the
		// window. The face normal comes from the position, since the card's
		// own normals are bent for soft shading.
		vec3 geo_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		float ndv = abs(dot(geo_n, normalize(VIEW)));
		float window = 0.2 * max(glancing_mul, 0.05);
		a *= smoothstep(0.0, window, ndv);
	}
	ALPHA = a;
	float far_t = clamp((v_view_dist - alpha_far_start) / max(alpha_far_range, 0.1), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_clip * mix(1.0, alpha_far_mul, far_t);
	ROUGHNESS = roughness_val;
	SPECULAR = 0.1;
}

void light() {
	// Base diffuse. The engine multiplies it by ALBEDO afterwards.
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR;
	if (enable_ss) {
		vec3 lt = normalize(LIGHT + NORMAL * ss_distortion);
		float k = pow(clamp(dot(VIEW, -lt), 0.0, 1.0), ss_power) * ss_strength;
		DIFFUSE_LIGHT += k * ATTENUATION * LIGHT_COLOR * ss_color.rgb;
	}
}
