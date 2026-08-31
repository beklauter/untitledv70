// Bushes and small plants. Greyscale map tinted flat or by a height gradient,
// two wind layers that darken where they push, and optional painted AO.
// Vertex colour R masks the sway, vertex colour G is the AO.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

group_uniforms color;
uniform sampler2D foliage_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 color_tint : source_color = vec4(0.655, 0.753, 0.267, 1.0);
uniform bool use_height_gradience = false;
uniform vec4 color_top : source_color = vec4(0.44, 0.66, 0.121, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.271, 0.453, 0.164, 1.0);
uniform float grad_smoothstep_min = 0.0;
uniform float grad_smoothstep_max = 1.0;
uniform vec4 painted_ao_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
group_uniforms;

group_uniforms surface;
uniform float alpha_clip : hint_range(0.0, 1.0) = 0.5;
uniform float smoothness_val : hint_range(0.0, 1.0) = 0.0;
// Drops backface pixels. Godot bakes the real cull mode into the shader,
// so this is the switchable version.
uniform bool cull_backfaces = false;
uniform bool fade_at_glancing = false;
uniform float glancing_mul : hint_range(0.05, 5.0) = 1.0;
group_uniforms;

group_uniforms wind_large;
uniform vec2 wind_large_speed = vec2(0.1, 2.0);
uniform float wind_large_intensity = 0.6;
uniform float wind_large_scale = 60.0;
uniform float large_darken_contrast = 0.0;
uniform float large_darken_multiplier = 1.0;
group_uniforms;

group_uniforms wind_small;
uniform vec2 wind_small_speed = vec2(-0.15, 1.8);
uniform float wind_small_intensity = 0.5;
uniform float wind_small_scale = 40.0;
uniform float small_darken_contrast = 0.0;
uniform float small_darken_multiplier = 1.0;
group_uniforms;

group_uniforms wind_mask;
uniform bool use_wind_height_gradience = false;
uniform float wind_grad_height_min = 0.0;
uniform float wind_grad_height_max = 1.0;
group_uniforms;

varying float v_local_y;
varying float v_wind_large;
varying float v_wind_small;

// Cheap smooth noise.
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

void vertex() {
	v_local_y = VERTEX.y;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float mask = COLOR.r;
	if (use_wind_height_gradience) {
		mask *= smoothstep(wind_grad_height_min, wind_grad_height_max, VERTEX.y);
	}
	float nl = _vnoise(wpos.xz / max(wind_large_scale, 0.01) + TIME * wind_large_speed * 0.2);
	float ns = _vnoise(wpos.xz / max(wind_small_scale, 0.01) + TIME * wind_small_speed * 0.6);
	v_wind_large = nl;
	v_wind_small = ns;
	vec2 dir_l = normalize(wind_large_speed + vec2(0.0001));
	vec2 dir_s = normalize(wind_small_speed + vec2(0.0001));
	VERTEX.xz += dir_l * nl * wind_large_intensity * mask;
	VERTEX.xz += dir_s * ns * wind_small_intensity * 0.35 * mask;
}

void fragment() {
	if (cull_backfaces && !FRONT_FACING) {
		discard;
	}
	// Flip backface normals so both sides light evenly.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 tex = texture(foliage_map, UV);
	vec3 tint = color_tint.rgb;
	if (use_height_gradience) {
		float g = smoothstep(grad_smoothstep_min, grad_smoothstep_max, v_local_y);
		tint = mix(color_bottom.rgb, color_top.rgb, g);
	}
	vec3 albedo = tex.rgb * tint;
	float dl = clamp(abs(v_wind_large) * large_darken_multiplier - large_darken_contrast, 0.0, 1.0);
	float ds = clamp(abs(v_wind_small) * small_darken_multiplier - small_darken_contrast, 0.0, 1.0);
	float darken = clamp(dl * 0.25 + ds * 0.15, 0.0, 0.5) *
			step(0.001, large_darken_contrast + small_darken_contrast);
	albedo *= 1.0 - darken;
	albedo = mix(albedo, painted_ao_color.rgb, (1.0 - COLOR.g) * painted_ao_color.a);
	ALBEDO = albedo;
	float a = tex.a;
	if (fade_at_glancing) {
		// Face normal from the position. The card's own normals are bent.
		vec3 geo_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		float ndv = abs(dot(geo_n, normalize(VIEW)));
		a *= smoothstep(0.0, 0.2 * max(glancing_mul, 0.05), ndv);
	}
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_clip;
	ROUGHNESS = 1.0 - smoothness_val;
	SPECULAR = 0.1;
}
