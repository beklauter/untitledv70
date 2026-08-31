// Grass master. Height gradient tint, two wind layers with the roots pinned,
// and an optional moving cloud shadow.
shader_type spatial;
// Opaque with an alpha scissor. Do not add depth_prepass_alpha here: it moves
// every blade into the transparent queue, where a million of them cannot sort.
render_mode cull_disabled;

group_uniforms tint;
uniform sampler2D base_color_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 tint_bottom : source_color = vec4(0.049, 1.0, 0.0, 1.0);
uniform vec4 tint_top : source_color = vec4(0.049, 1.0, 0.0, 1.0);
uniform float grad_pow = 1.0;
// Gradient zone in local metres. Flat bottom tint up to grad_offset, then
// blends to the top tint across grad_length.
uniform float grad_offset = 0.0;
uniform float grad_length = 1.0;
group_uniforms;

group_uniforms surface;
uniform float smoothness_val : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_clip : hint_range(0.0, 1.0) = 0.0;
// Drops backfaces. Godot bakes the real cull mode into the shader.
uniform bool cull_backfaces = false;
uniform bool fade_at_glancing = false;
uniform float glancing_mul : hint_range(0.05, 5.0) = 1.0;
group_uniforms;

group_uniforms clouds;
uniform vec4 cloud_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float cloud_scale = 80.0;
uniform vec2 cloud_speed = vec2(1.5, 0.8);
// Switch the shadow source from the built-in noise to cloud_tex.
// Dark areas are shadow.
uniform bool cloud_use_texture = false;
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
group_uniforms;

// Gust waves that travel across the field and lean blades downwind. Power
// shapes the crests, dip pulls tips down as they bend, darken shades bent
// grass, ramp is the height over which sway builds from root to tip.
group_uniforms big_wind;
uniform vec2 wind_large_speed = vec2(0.0, 2.0);
uniform float wind_large_multiplier = 0.1;
uniform float wind_large_scale = 500.0;
uniform float wind_gust_power : hint_range(0.5, 8.0) = 2.0;
uniform float wind_dip : hint_range(0.0, 1.0) = 0.4;
uniform float wind_darken : hint_range(0.0, 1.0) = 0.25;
uniform float wind_ramp : hint_range(0.05, 2.0) = 0.5;
group_uniforms;
group_uniforms small_wind;
uniform vec2 wind_small_speed = vec2(0.0, 2.0);
uniform float wind_small_multiplier = 0.1;
uniform float wind_small_scale = 500.0;
// Everything below this height in local metres stays still.
uniform float wind_offset = 0.0;
// Use the mesh's painted vertex colour (red channel) as the sway mask.
uniform bool wind_use_vertex_color = false;
group_uniforms;

varying float v_grad;
varying vec3 v_wpos;
varying float v_bend;

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
	v_grad = pow(clamp((VERTEX.y - grad_offset) / max(grad_length, 0.001), 0.0, 1.0), grad_pow);
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wpos = wpos;
	float mask;
	if (wind_use_vertex_color) {
		mask = COLOR.r;
	} else {
		float m = clamp((VERTEX.y - wind_offset) / max(wind_ramp, 0.001), 0.0, 1.0);
		mask = m * m;   // squared, so roots hold and tips arc over
	}
	// Gust wave, 0 to 1, leaning downwind.
	float gust = clamp(_vnoise(wpos.xz / max(wind_large_scale, 0.01) * 60.0
		+ TIME * wind_large_speed * 0.2) * 0.5 + 0.5, 0.0, 1.0);
	gust = pow(gust, max(wind_gust_power, 0.01));
	// Flutter is signed, so blades jitter either side of their lean.
	float ns = _vnoise(wpos.xz / max(wind_small_scale, 0.01) * 250.0 + TIME * wind_small_speed * 0.6);
	vec2 dir_l = normalize(wind_large_speed + vec2(0.0001));
	vec2 dir_s = normalize(wind_small_speed + vec2(0.0001));
	vec2 disp = dir_l * gust * wind_large_multiplier
		+ dir_s * ns * wind_small_multiplier * 0.5;
	VERTEX.xz += disp * mask;
	// The harder the lean, the lower the tip.
	VERTEX.y -= length(disp) * wind_dip * mask;
	v_bend = gust * mask;
}

void fragment() {
	if (cull_backfaces && !FRONT_FACING) {
		discard;
	}
	// Flip backface normals so both sides light evenly.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 tex = texture(base_color_tex, UV);
	vec3 albedo = tex.rgb * mix(tint_bottom.rgb, tint_top.rgb, v_grad);
	vec2 cloud_uv = v_wpos.xz / max(cloud_scale, 0.01) + TIME * cloud_speed * 0.05;
	float cloud = cloud_use_texture
		? 1.0 - texture(cloud_tex, cloud_uv).r
		: clamp(_vnoise(cloud_uv) * 0.5 + 0.5, 0.0, 1.0);
	albedo = mix(albedo, albedo * cloud_color.rgb, cloud_color.a * cloud);
	// Darken bent grass, which is what makes the waves show.
	albedo *= 1.0 - wind_darken * clamp(v_bend, 0.0, 1.0);
	ALBEDO = albedo;
	if (alpha_clip > 0.0) {
		float a = tex.a;
		if (fade_at_glancing) {
			// Face normal from the position. The card's own normals are bent.
			vec3 geo_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
			float ndv = abs(dot(geo_n, normalize(VIEW)));
			a *= smoothstep(0.0, 0.2 * max(glancing_mul, 0.05), ndv);
		}
		ALPHA = a;
		ALPHA_SCISSOR_THRESHOLD = alpha_clip;
	}
	ROUGHNESS = 1.0 - smoothness_val;
	SPECULAR = 0.1;
}
