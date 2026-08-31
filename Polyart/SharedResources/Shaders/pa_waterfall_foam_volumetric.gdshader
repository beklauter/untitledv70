// Waterfall pool foam. The volume is a vertex offset.
// Ported from Dreamscape_WaterfallFoam_Volumetric.shader.
// Godot flips FBX UV.y, so the pack's V is (1 - UV.y) here. On
// SM_Foam_Bottom_High that is 1 at the fan's hub and 0 at the rim.
shader_type spatial;
render_mode cull_disabled, unshaded;

group_uniforms foam;
uniform sampler2D foam_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// Stretches the pattern around the fan. Negative mirrors it.
uniform float scale_width = -0.29;
// Stretches the pattern from hub to rim.
uniform float acceleration = 1.27;
uniform float scale_x = 1.0;
uniform float scale_y = 1.0;
// Negative scrolls outward, positive inward.
uniform float vertical_speed = -1.0;
uniform float threshold : hint_range(-1.0, 1.0) = 0.01;
group_uniforms;

group_uniforms displacement;
// Rise of the thickest foam, in mesh units. The node's Y scale sets how much
// of it reaches the screen. The demo uses 0.115 and 0.584.
uniform float height : hint_range(0.0, 100.0) = 10.0;
group_uniforms;

group_uniforms colors;
uniform vec4 color_0 : source_color = vec4(0.0, 0.8957, 0.9906, 1.0);
uniform vec4 color_1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
group_uniforms;

group_uniforms opacity;
// On erodes the thin outer foam. The original leaves it off.
uniform bool use_opacity_mask = false;
uniform float mask_clip : hint_range(0.01, 1.0) = 0.1;
group_uniforms;

// Runs once per stage. Passing it across as a varying blocks up.
float _mask(vec2 uv, float t) {
	float v = 1.0 - uv.y;
	vec2 s = vec2(scale_x * (scale_width * uv.x),
			(v * acceleration - t * vertical_speed) * scale_y);
	return v * texture(foam_tex, s).r - threshold;
}

void vertex() {
	VERTEX.y += clamp(_mask(UV, TIME), 0.0, 1.0) * height - height * 0.25;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float m = _mask(UV, TIME);
	ALBEDO = mix(color_0.rgb, color_1.rgb, m);
	if (use_opacity_mask) {
		ALPHA = clamp(m, 0.0, 1.0);
		ALPHA_SCISSOR_THRESHOLD = mask_clip;
	}
}
