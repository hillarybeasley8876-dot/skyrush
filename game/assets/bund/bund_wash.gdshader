shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// The far-field wash of the Bund (bund unit).
//
// The pooled uplights fade out at 60-80 m (the light budget of the art dossier 3.4), so
// beyond that the row would go grey. The facade cards carry a light map baked in metres
// (blender/bund/washmap.py) and the crown shells carry a ramp, so both are additive,
// unshaded and free of fog.
//
// The facade wash ramps up where the pooled uplights fade (45-85 m), the crown wash
// earlier (25-60 m): the crown has to be the brightest thing on the row.

uniform sampler2D wash_tex : source_color, filter_linear, repeat_disable;
uniform vec3 facade_colour : source_color = vec3(1.0, 0.702, 0.278);   // #FFB347
uniform vec3 crown_colour : source_color = vec3(1.0, 0.769, 0.416);     // #FFC46A
uniform float energy : hint_range(0.0, 4.0) = 0.80;
uniform float crown_energy : hint_range(0.0, 4.0) = 0.55;
uniform float facade_min = 45.0;
uniform float facade_max = 85.0;
uniform float crown_min = 25.0;
uniform float crown_max = 60.0;
uniform float crown_mix : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec4 t = texture(wash_tex, UV);
	float d = distance(CAMERA_POSITION_WORLD, world_pos);
	// the facade wash ramps up where the pooled uplights fade; the crown wash ramps up
	// earlier - the crown has to be the brightest thing on the row from the road
	float lo = mix(facade_min, crown_min, crown_mix);
	float hi = mix(facade_max, crown_max, crown_mix);
	float f = clamp((d - lo) / max(0.001, hi - lo), 0.0, 1.0);
	// the facade wash also carries the near field (the uplights pool under it), the
	// crown shell stands on its own
	f = mix(mix(0.30, 0.55, crown_mix), 1.0, f);
	vec3 col = mix(facade_colour, crown_colour, crown_mix);
	float e = mix(energy, crown_energy, crown_mix);
	ALBEDO = col * t.r * e;
	ALPHA = t.a * f;
}
