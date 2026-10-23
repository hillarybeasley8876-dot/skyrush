// SKYRUSH - Roadster canopy glass: the colour is a parameter (the black and white Roadster has
// neutral smoke glass, the first one was bronze-gold), metallic sheen, fresnel, a faint interior
// read-through and optional rain streaks on the outside of the pane.
// New shader for the environment unit (no look-dev predecessor).
// The canopy's UV0 is in METRES (u -0.84..0.84, v -0.61..2.75), so nothing here may use UV: the
// interior read is driven by the view angle and the rain streaks by the world position.
// Transparency: ALPHA blend; the interior mesh behind the canopy is what shows through.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float skyrush_rain;      // 0 dry .. 1 raining, set by the weather controller
global uniform float skyrush_wetness;   // 0 dry .. 1 soaked

uniform vec3 tint_color : source_color = vec3(0.353, 0.247, 0.165); // #5A3F2A gold glass
uniform vec3 sheen_color : source_color = vec3(0.85, 0.68, 0.42);    // warm metallic rim
uniform vec3 interior_color : source_color = vec3(0.30, 0.22, 0.16); // the cabin behind the glass
uniform float base_alpha : hint_range(0.0, 1.0) = 0.68;   // how much of the interior reads through
uniform float interior_amount : hint_range(0.0, 1.0) = 0.35; // the cabin glow through the tint
uniform float fresnel_power : hint_range(1.0, 6.0) = 3.0;
uniform float fresnel_opacity : hint_range(0.0, 1.0) = 0.85;  // grazing angles turn mirror-like
uniform float sheen_strength : hint_range(0.0, 2.0) = 0.5;
uniform float roughness_value : hint_range(0.02, 1.0) = 0.05;
uniform float rain_streaks : hint_range(0.0, 1.0) = 1.0;   // 0 = no streaks option
uniform sampler2D streak_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// hint_default_black: Godot's unset sampler is WHITE, which would make every pane max-grimy.
uniform sampler2D albedo_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable; // imported grime
uniform float streak_scale = 3.0;
uniform float streak_speed = 0.35;

varying vec3 world_pos;
varying vec3 obj_pos;

// The named constants of the pane maths (no bare numbers in the code).
const float TINT_FLOOR = 0.55;   // the tint colour at a grazing angle
const float TINT_FACE = 0.45;    // the tint colour looking straight into the cabin
const float STREAK_ALPHA = 0.25; // the water film makes the pane more opaque
const float GRIME_ALPHA = 0.15;  // the grime makes the pane less opaque
const float STREAK_ROUGH = 0.25; // the water film roughens the pane
const float GRIME_ROUGH = 0.2;   // the grime roughens the pane
const float WET_ROUGH = 0.02;    // the wet street adds a touch of roughness
const float STREAK_HIGHLIGHT = 0.15;  // the wet highlight on the water film

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	obj_pos = VERTEX;   // the grime and the streaks are fixed to the car, they must not slide
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power);

	// Rain streaks run down the outside of the pane in OBJECT space, so the pattern belongs to
	// the car and does not slide over it at 250 km/h.
	vec2 suv = vec2((obj_pos.x + obj_pos.z) * streak_scale, obj_pos.y * 0.6 + TIME * streak_speed);
	float streak = texture(streak_noise, suv).r;
	streak = smoothstep(0.72, 0.95, streak) * rain_streaks * skyrush_rain;

	// The imported grime map darkens the glass where the wipers do not reach (authored UVs).
	float grime = texture(albedo_texture, UV).r;

	float alpha = mix(base_alpha, fresnel_opacity, fres);
	alpha = clamp(alpha + streak * STREAK_ALPHA - grime * GRIME_ALPHA, 0.0, 1.0);

	// The interior reads through where we look straight into the cabin (face-on), not at grazing
	// angles where the glass is a mirror.
	vec3 col = tint_color * (TINT_FLOOR + TINT_FACE * pow(ndv, 2.0));
	col = mix(col, interior_color, interior_amount * pow(ndv, 2.5));
	col = mix(col, sheen_color, fres * sheen_strength);
	col += vec3(0.9, 0.85, 0.75) * streak * STREAK_HIGHLIGHT;   // wet highlight on the water film

	ALBEDO = col;
	ALPHA = alpha;
	METALLIC = 0.15;                                   // thin metal-oxide tint layer
	ROUGHNESS = clamp(roughness_value + streak * STREAK_ROUGH + grime * GRIME_ROUGH
		+ skyrush_wetness * WET_ROUGH, 0.02, 1.0);
	SPECULAR = 0.9;
}
