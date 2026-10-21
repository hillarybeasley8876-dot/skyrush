shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled, fog_disabled,
	specular_disabled, diffuse_burley;

// The vapour column of one nozzle (review MUST-FIX 5): an open tapered tube whose alpha is
// noise scrolling along the jet. The particles only break the column up further out, so the
// plume reads as a continuous rope of vapour instead of a string of puffs.
//
// The noise is a seamless fbm texture sampled per fragment. The first version evaluated it per
// vertex on a 12 x 8 tube, where there are fewer samples than noise cells: the noise collapsed
// into smooth facets and the tube read as a glass bottle with a hard rim.
//
// The tube is drawn alpha blended and lit, so the scene's neon tints the column, and it fades
// out where it meets the road (the ground height is fed in by the rig).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.949, 0.965, 0.980);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// The alpha of the column at the throat.
uniform float alpha_max : hint_range(0.0, 1.0) = 0.72;
// A little self-illumination, so the column still reads in an unlit alley.
uniform float emission_gain : hint_range(0.0, 2.0) = 0.45;
// The column's current length in metres.
uniform float column_length : hint_range(0.1, 20.0) = 8.0;
// How long one noise billow of the first layer is, in metres.
uniform float billow_m : hint_range(0.1, 6.0) = 2.5;
// The second layer's billow is 1.6 times as long.
uniform float billow2_factor : hint_range(1.0, 4.0) = 1.6;
// How fast the gas moves along the jet, in m/s. The two noise layers scroll at 1.0x and 0.6x.
uniform float jet_speed : hint_range(0.0, 200.0) = 35.0;
// How many noise cells go around the tube.
uniform float around_scale : hint_range(0.5, 8.0) = 2.0;
// The soft fade where the column meets the road, in metres.
uniform float soft_fade : hint_range(0.0, 4.0) = 0.4;
// The height of the road under the plume. The column dissolves into it.
uniform float ground_y : hint_range(-20.0, 20.0) = 0.0;

// The world normal, for the fake top light.
varying vec3 world_normal;
// The world position of this fragment, for the ground fade.
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float v = clamp(UV.y, 0.0, 1.0);
	// The distance from the throat, in metres.
	float m = v * column_length;
	// Two noise layers, scrolling along the jet at the jet speed and at 0.6 of it.
	vec2 uv1 = vec2(UV.x * around_scale, m / billow_m - TIME * jet_speed / billow_m);
	vec2 uv2 = vec2(UV.x * around_scale * 1.7 + 0.37,
			m / (billow_m * billow2_factor) - TIME * jet_speed * 0.6 / (billow_m * billow2_factor));
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex, uv2).r;
	float body = smoothstep(0.25, 0.7, n1 * n2 * 2.0);

	// The tube is seen from the side: the wall that faces the camera is the thick one.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// The rope: dense in the middle, soft at the silhouette, and the noise shapes it. The
	// noise only modulates the profile, so the column cannot break into thin filaments.
	float a = smoothstep(0.0, 0.35, facing) * (0.7 + 0.3 * body) * alpha_max;
	// The column starts softly under the core and dissolves towards the tip.
	a *= smoothstep(0.0, 0.12, v);
	a *= pow(1.0 - v, 1.5);
	// The throttle changes the density, not the exit speed: a choked nozzle keeps its jet.
	a *= mix(0.85, 1.0, intensity);
	// The column dissolves into the road instead of cutting it off.
	a *= smoothstep(ground_y, ground_y + soft_fade, world_pos.y);

	// A fake top light: the top of the tube is brighter than the bottom.
	float top = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = tint * (0.75 + 0.25 * top);
	ALPHA = clamp(a, 0.0, 1.0);
	EMISSION = tint * emission_gain * (0.5 + 0.5 * top);
}
