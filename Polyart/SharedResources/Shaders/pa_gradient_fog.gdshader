// Gradient fog, the Firewatch look. Colour and strength come from a colour
// ramp sampled by distance, so each ridge line picks up the next band. A
// second ramp is sampled by how much the view points at the sun. Height only
// thins the fog, so peaks stay clear. One fullscreen pass over the frame.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

group_uniforms distance_fog;
// RGB is the fog colour at that distance, alpha is how strong it is.
uniform sampler2D distance_gradient : source_color, repeat_disable, filter_linear;
// Metres mapped to the two ends of the gradient.
uniform float distance_start : hint_range(0.0, 500.0) = 25.0;
uniform float distance_end : hint_range(50.0, 4000.0) = 700.0;
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0;
// How much of the fog reaches the sky.
uniform float sky_affect : hint_range(0.0, 1.0) = 0.55;
group_uniforms;

group_uniforms sun_tint;
// Sampled by view direction: left end away from the sun, right end at it.
// The alpha blends this ramp over the distance colour.
uniform sampler2D direction_gradient : source_color, repeat_disable, filter_linear;
uniform float direction_amount : hint_range(0.0, 1.0) = 1.0;
// Written by PAGradientFog from the scene's DirectionalLight3D.
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);
group_uniforms;

group_uniforms height_thinning;
// Fog keeps full strength below this world height.
uniform float height_start = 130.0;
// How fast it thins above. 0 turns thinning off.
uniform float height_falloff : hint_range(0.0, 0.1) = 0.004;
group_uniforms;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_frag = world - cam;
	float dist = length(to_frag);
	vec3 dir = to_frag / max(dist, 0.001);

	// Godot's depth buffer reads 0 where nothing was drawn.
	bool is_sky = depth < 0.0000001;

	float d01 = clamp((dist - distance_start)
			/ max(distance_end - distance_start, 0.001), 0.0, 1.0);
	if (is_sky) {
		d01 = 1.0;
	}
	vec4 fog = texture(distance_gradient, vec2(d01, 0.5));

	// Sun tint by view direction.
	float sundot = clamp(dot(dir, -normalize(sun_direction)) * 0.5 + 0.5, 0.0, 1.0);
	vec4 sun = texture(direction_gradient, vec2(sundot, 0.5));
	fog.rgb = mix(fog.rgb, sun.rgb, sun.a * direction_amount);

	// Thin with the height of what the pixel lands on.
	float h = is_sky ? 1.0 : exp(-max(world.y - height_start, 0.0) * height_falloff);

	ALBEDO = fog.rgb;
	ALPHA = fog.a * h * max_opacity * (is_sky ? sky_affect : 1.0);
}
