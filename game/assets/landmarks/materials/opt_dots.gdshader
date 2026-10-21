shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
	fog_disabled, specular_disabled;

// The Oriental Pearl's LED dot skin (dossier 6.1, L-NIGHT2).
//
// A dot grid at a 0.4 m pitch (the UV is in METRES on the sphere) with a
// brightness wave chasing up the sphere at 0.75 Hz, and the colour driven by
// the wrapper script: #FF3FA4 -> #8A3CFF -> #2E7BFF over 40 s.
//
// The shell floats 0.6 m off the glass, so the dots read as a skin of light
// over the pink-magenta glass and the silver bands show between the rings.

uniform vec3 led_color : source_color = vec3(1.0, 0.247, 0.643);
uniform float energy : hint_range(0.0, 8.0) = 4.0;
uniform float dot_pitch = 0.4;
uniform float dot_radius = 0.28;
uniform float chase_hz : hint_range(0.1, 2.0) = 0.75;
uniform float chase_freq : hint_range(0.01, 1.0) = 0.1;

void fragment() {
	vec2 g = fract(UV / dot_pitch) - vec2(0.5);
	float d = length(g);
	float dot = 1.0 - smoothstep(dot_radius - 0.07, dot_radius, d);
	float wave = 0.55 + 0.45 * sin(TAU * (chase_hz * TIME - UV.y * chase_freq));
	ALBEDO = vec3(0.02, 0.01, 0.02);
	EMISSION = led_color * energy * dot * wave;
	ALPHA = dot;
}
