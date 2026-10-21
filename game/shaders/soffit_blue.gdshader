// SKYRUSH - the underside of an elevated deck: dirty concrete washed blue by the LED strips that
// run along both edges of the soffit (measured Shanghai soffit colour #2357F3, DOSSIER 2.1).
// One material covers the whole soffit: a blue wash (E1) + two thin edge strips (E3).
// The real deck exports v = 0, 1/3, 2/3, 1 across the wing-flat-wing profile (blender/city/roads/
// deck.py:60-84), so v = 0 and v = 1 are the two outer drip edges where the strips sit, and the
// flat underside between the girders is v = 0.5. u is the distance along the deck in metres.
// The concrete is sampled in world space so the texture does not stretch with the deck size.
// New shader for the environment unit (no look-dev predecessor).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 wash_color : source_color = vec3(0.137, 0.341, 0.953); // #2357F3 SOFFIT_BLUE
uniform vec3 strip_color : source_color = vec3(0.353, 0.239, 1.0);  // #5A3DFF the LED strip itself
uniform float wash_energy : hint_range(0.0, 4.0) = 0.9;   // E1 - the wash itself (DOSSIER 3.7 #2)
uniform float strip_energy : hint_range(0.0, 12.0) = 4.5; // E3 - the strips bloom
uniform float wash_falloff : hint_range(0.0, 1.0) = 0.45; // how much the wash fades at the centre line
uniform float soffit_width_m = 15.4;    // full width of the soffit, for the strip width in metres
uniform float strip_width_m = 0.05;     // the LED strip is 5 cm wide (DOSSIER 4.5: >= 2 px on screen)
uniform float core_whiten : hint_range(0.0, 1.0) = 0.3;  // the tube core reads white-hot
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stain_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tex_mean : source_color = vec3(0.171, 0.140, 0.105); // measured mean of the concrete scan
uniform vec3 base_color : source_color = vec3(0.431, 0.424, 0.408); // #6E6C68 the soffit albedo
uniform float uv_scale = 1.0;    // the soffit panels are ~1 m, not the 4 m pier panels
uniform sampler2D grime_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.4;
// The structure of the deck: formwork joints and girder lines.
uniform float joint_spacing_m = 1.2;   // a formwork joint every 1.2 m along the deck
uniform float joint_width_m = 0.03;    // the joint is 3 cm wide
uniform float joint_v = 0.25;          // the girder lines sit at v = 0.25 / 0.5 / 0.75
uniform float joint_width_v = 0.002;   // ~3 cm at a 15.4 m soffit
uniform float rib_light = 0.35;        // the drip edges catch more light
uniform float stain_amount = 0.45;    // the water stains from the Leaking* opacity map

// The named constants of the wash maths (no bare numbers in the code).
const float LUMA_R = 0.2126;          // the Rec.709 luma weights
const float LUMA_G = 0.7152;
const float LUMA_B = 0.0722;
const float GRIME_DARK = 0.35;        // the grime noise darkens the wash by this much at most
const float JOINT_DARK = 0.7;         // the formwork joints are the darkest lines of the soffit
const float STAIN_FLOOR = 0.55;       // a stained patch keeps this much of the wash
const float STAIN_LO = 0.25;          // the stain mask below this is no stain
const float STAIN_HI = 0.75;          // the stain mask above this is a full stain
const float STRIP_CORE = 0.45;        // the white-hot core of the LED strip
const float EMISSION_MAX = 1.6;       // the concrete scan may not blow out to white
const float ALBEDO_JOINT = 0.7;       // the joints darken the albedo as well
const float CONTRAST = 0.35;          // how much the concrete's own contrast shows through the wash

varying vec2 soffit_uv;
varying vec3 world_pos;

void vertex() {
	soffit_uv = UV;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Wash is brightest at the edges, dimmer along the centre line (DOSSIER 3.7).
	float edge = abs(soffit_uv.y * 2.0 - 1.0);
	float wash = mix(1.0 - wash_falloff, 1.0, smoothstep(0.15, 1.0, edge));

	// Two LED strips at the deck edges, 5 cm wide in metres.
	float half_v = max(strip_width_m * 0.5 / max(soffit_width_m, 0.1), 0.0005);
	float d = min(soffit_uv.y, 1.0 - soffit_uv.y);
	float strip = 1.0 - smoothstep(0.0, half_v, d);
	float strip_core = 1.0 - smoothstep(0.0, half_v * STRIP_CORE, d);

	// The concrete: the scan is normalised by its own measured mean, so the panel joints, the
	// stains and the 4 m formwork grooves show through the blue wash instead of a flat colour.
	vec2 wuv = world_pos.xz * uv_scale;
	vec3 tex = texture(albedo_texture, wuv).rgb;
	vec3 norm = clamp(tex / max(tex_mean, vec3(0.001)), vec3(0.0), vec3(EMISSION_MAX));
	float ao = texture(ao_texture, wuv).r;
	float grime = texture(grime_noise, world_pos.xz * vec2(0.15, 0.4)).r;
	vec3 concrete = base_color * norm;
	concrete *= 1.0 - grime_amount * grime * 0.5;
	concrete *= mix(1.0, ao, 0.8);

	// The structure of the deck: the formwork joints every 1.2 m along u and the girder lines
	// at v = 0.25 / 0.5 / 0.75. This is what makes the soffit read as concrete and not paint.
	float du = abs(fract(soffit_uv.x / joint_spacing_m + 0.5) - 0.5) * joint_spacing_m;
	float joint_u = 1.0 - smoothstep(0.0, joint_width_m, du);
	float dv = min(min(abs(soffit_uv.y - joint_v), abs(soffit_uv.y - 0.5)),
		abs(soffit_uv.y - (1.0 - joint_v)));
	float joint_v_line = 1.0 - smoothstep(0.0, joint_width_v, dv);
	float joints = max(joint_u, joint_v_line);

	// The longitudinal ribs / drip edges catch more of the wash.
	float rib = smoothstep(0.12, 0.0, d);

	// Water stains: the Leaking004 OPACITY map is the shape of the stain (the colour map is the
	// stain's own dark colour, which is far too dark to read as a mask). The sheet is sampled in
	// the soffit's own UV (u in metres), so the stains run along the deck and not in one row.
	float stain = smoothstep(STAIN_LO, STAIN_HI,
		texture(stain_texture, vec2(soffit_uv.x * 0.08, soffit_uv.y * 1.5)).r);

	// The wash is modulated by the concrete, so the formwork pattern reads through it.
	// `norm` is the scan divided by its own mean, so its average luma is 1.0.
	float luma = dot(norm, vec3(LUMA_R, LUMA_G, LUMA_B));
	// The concrete's own contrast is pushed, so the formwork joints and the stains read through
	// the wash instead of a flat blue field. The average stays at 1.0.
	float luma_c = mix(1.0 - CONTRAST, 1.0 + CONTRAST, luma);
	vec3 emission = wash_color * wash * wash_energy
		* luma_c
		* (1.0 - GRIME_DARK * grime)
		* (1.0 - JOINT_DARK * joints)
		* mix(1.0, STAIN_FLOOR, stain * stain_amount)
		* (1.0 + rib_light * rib);
	emission += strip_color * strip * strip_energy;
	emission += vec3(1.0) * strip_core * strip_energy * core_whiten;

	ALBEDO = concrete * (1.0 - ALBEDO_JOINT * joints);
	ROUGHNESS = 0.85 - 0.1 * grime;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(normal_texture, wuv).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	EMISSION = emission;
}
