// SKYRUSH - a shop sign / light box: the artwork of the sign masks its own light, so the glyphs
// glow and the panel is never a flat slab of colour. The panel is also lit by the street, so the
// dark parts of the artwork read as dark grey and not as crushed black (ART 8: no pure black
// surfaces). A StandardMaterial3D cannot do this: its emission texture is not multiplied into
// the emission, so the panel would be a uniform slab.
// New shader for the environment unit (no look-dev predecessor).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 sign_color : source_color = vec4(1.0, 0.64, 0.30, 1.0);  // the colour of the sign
uniform float sign_energy : hint_range(0.0, 12.0) = 2.0;   // E2 2-4 (a shop light box)
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float artwork_mix : hint_range(0.0, 1.0) = 0.92;  // 1 = the artwork masks the light fully
uniform float panel_albedo : hint_range(0.0, 1.0) = 0.35;  // how much of the artwork is painted on
uniform float backlight : hint_range(0.0, 0.2) = 0.05;    // the panel's own dim backlight
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec3 art = texture(artwork, UV).rgb;
	// The light of the panel: the artwork masks it, but a little of the sign colour always
	// shines through, so the dark parts of the artwork are not black.
	vec3 light = sign_color.rgb * mix(vec3(1.0), art, artwork_mix);
	ALBEDO = art * panel_albedo + sign_color.rgb * backlight;
	EMISSION = light * sign_energy;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
}
