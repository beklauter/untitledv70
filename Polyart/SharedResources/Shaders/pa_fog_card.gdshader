// Fog bank card, ported from the pack's Unreal M_Fog graph. Unlit, translucent.
// Shape = blob texture times a panning detail noise. Three fades stack on top:
// view angle (the card dims as it turns parallel), contact with nearby meshes,
// and camera approach. Movement is UV panning, randomised per instance from
// world position. The Y-locked billboard replaces the graph's hand-rotated
// cards, since our placements are upright.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

group_uniforms shape;
// RGB tints the card, alpha cuts the shape.
uniform sampler2D fog_tex : source_color, filter_linear_mipmap;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_noise_tiling = 1.0;
// UE "detail intensity exponent": sharpens the noise into wisps.
uniform float detail_intensity_exponent = 4.545;
// How much the wisps eat into the blob. 0 is a plain solid blob.
uniform float detail_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float overall_intensity_exponent = 1.0;
uniform float overall_intensity_multiplier = 1.0;
uniform vec4 tint : source_color = vec4(0.694, 0.962, 0.925, 0.435);
group_uniforms;

group_uniforms movement;
uniform bool use_random_movement = true;
uniform float x_speed = 0.05;
uniform float y_speed = 0.02;
group_uniforms;

group_uniforms fades;
// Fades the card out as it turns parallel to the view. The UE graph ships
// 0.1734 for its hand-rotated cards; the billboard needs a narrower fade.
uniform float fresnel_exponent = 4.0;
// Metres of overlap that blend the card into ground and rock it touches.
uniform float depth_fade_distance = 7.0;
// Fully faded in this close to the camera, in metres.
uniform float fog_thickest_distance = 8.4;
// Metres over which the card fades back in past that.
uniform float transition_distance = 13.2;
group_uniforms;

varying vec3 v_view_pos;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Y-locked billboard that keeps the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 blob = texture(fog_tex, UV);

	// Panning detail noise, offset and direction randomised per instance.
	vec2 pan = vec2(x_speed, y_speed);
	vec2 uv_off = vec2(0.0);
	if (use_random_movement) {
		vec2 seed = MODEL_MATRIX[3].xz;
		uv_off = vec2(_hash(seed), _hash(seed + 17.0));
		pan.x *= _hash(seed + 5.0) < 0.5 ? -1.0 : 1.0;
	}
	float detail = texture(detail_tex, UV * detail_noise_tiling + uv_off + pan * TIME).r;
	detail = mix(1.0, pow(detail, detail_intensity_exponent), detail_intensity);

	float shape = pow(blob.a * detail, overall_intensity_exponent) * overall_intensity_multiplier;
	shape = clamp(shape, 0.0, 1.0);

	// Fade as the card turns parallel to the view.
	float ndv = clamp(dot(NORMAL, normalize(-v_view_pos)), 0.0, 1.0);
	float angle_fade = 1.0 - pow(1.0 - ndv, fresnel_exponent);

	// Soft contact where the card meets ground and rock.
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = sv.z / sv.w;
	float contact = d < 0.0000001 ? 1.0
			: clamp((v_view_pos.z - scene_z) / max(depth_fade_distance, 0.001), 0.0, 1.0);

	// Fade back in as the camera backs away.
	float dist = length(v_view_pos);
	float near_fade = clamp((dist - fog_thickest_distance) / max(transition_distance, 0.001), 0.0, 1.0);

	ALBEDO = blob.rgb * tint.rgb;
	ALPHA = shape * tint.a * angle_fade * contact * near_fade;
}
