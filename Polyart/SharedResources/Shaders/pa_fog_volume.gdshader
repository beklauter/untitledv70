// Ground mist for FogVolume nodes. Drifting noise, height falloff and soft
// edges.
shader_type fog;

group_uniforms color;
uniform vec4 fog_albedo : source_color = vec4(0.78, 0.88, 1.0, 1.0);
// Self-light. Fog with none of it goes near-black in shadow.
uniform vec4 fog_emission : source_color = vec4(0.32, 0.4, 0.5, 1.0);
group_uniforms;

group_uniforms shape;
uniform float density : hint_range(0.0, 8.0) = 1.0;
// Thins the mist upward. 0 fills the volume evenly.
uniform float height_falloff : hint_range(0.0, 6.0) = 1.6;
// Softens the volume boundary so patches have no hard edge.
uniform float edge_fade : hint_range(0.0, 1.0) = 0.45;
group_uniforms;

group_uniforms animation;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.06;
// How much the noise breaks up the mist. 0 is flat, even fog.
uniform float noise_contrast : hint_range(0.0, 1.0) = 0.7;
// World-space drift of the noise pattern, in units per second.
uniform vec2 drift_speed = vec2(0.03, 0.02);
group_uniforms;

void fog() {
	// UVW runs 0 to 1 across the volume, 0 at the middle, 1 at the edge.
	vec3 c = (UVW - vec3(0.5)) * 2.0;
	float r = length(c);
	float edge = 1.0 - smoothstep(1.0 - edge_fade, 1.0, r);

	// Full density at the floor, thinning toward the top.
	float h = exp(-height_falloff * max(UVW.y - 0.1, 0.0));

	// Two noise taps drifting apart, which makes the mist roll.
	vec2 p = WORLD_POSITION.xz * noise_scale;
	float n1 = texture(noise_tex, p + TIME * drift_speed).r;
	float n2 = texture(noise_tex, p * 1.63 - TIME * drift_speed * 0.7).r;
	float n = mix(1.0, clamp(n1 * n2 * 2.2, 0.0, 1.6), noise_contrast);

	DENSITY = max(density * edge * h * n, 0.0);
	ALBEDO = fog_albedo.rgb;
	EMISSION = fog_emission.rgb;
}
