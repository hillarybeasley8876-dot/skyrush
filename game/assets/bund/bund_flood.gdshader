shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The light curtains of the Bund's flood wall (bund unit).
//
// The curtains are the only blue on the row: every 6 m a 4.2 m curtain falls from the
// lip of the wall (y +2.5) to the water (y -3), #29D3FF at the top and #1E8BFF at the
// foot, with a 1.8 m dark gap between the modules.
//
// The curtain is additive and free of fog, so it stays readable from the Pudong bank,
// 400 m away - the reference photo (hsbc_customs_night_2026.jpg) shows the blue clearly
// against the water.

uniform sampler2D curtain_tex : source_color, filter_linear, repeat_enable;
uniform float energy : hint_range(0.0, 8.0) = 1.15;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec4 t = texture(curtain_tex, UV);
	ALBEDO = t.rgb * energy;
	ALPHA = t.a;
}
