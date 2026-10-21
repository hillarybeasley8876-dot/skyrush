shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;

// Skid-mark ribbon material. The mark multiplies the road (blend_mul), so it always darkens the
// asphalt and kills the wet reflection instead of reading as a light grey stripe.
//   track_tex : the baked tyre track (7 tread grooves, shoulder lines, scuff breaks)
//   COLOR.a    : the fade of the mark (1 = fresh, 0 = gone), written by the pool
//   COLOR.rgb  : the bite of the tyre at the start of a strip (a fresh mark is darker)
// The material is unshaded: at night the road is nearly black, and a lit mark would multiply
// the road by almost nothing and read as a black hairline.
uniform sampler2D track_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float fade_time : hint_range(1.0, 120.0) = 20.0;
uniform vec3 rubber : source_color = vec3(0.082, 0.082, 0.082);
uniform float strength : hint_range(0.0, 1.0) = 0.6;


void fragment() {
	float detail = texture(track_tex, UV).a;
	float a = detail * COLOR.a;
	// blend_mul: the output multiplies the road underneath, so a fresh mark keeps 45% of the
	// road (and of its wet reflection) and a groove of the tread keeps 80%.
	ALBEDO = mix(vec3(1.0), rubber, clamp(a * strength, 0.0, 1.0)) * COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
