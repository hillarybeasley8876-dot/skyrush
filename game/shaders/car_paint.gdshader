// SKYRUSH - car paint: base coat + micro flake + orange peel + clear coat + optional livery + road grime.
// Ported from ref/art/lookdev/shaders/car_paint.gdshader [V], re-tuned for the Ano White Roadster:
//   * the paint colour is a PLAIN uniform (per material) with an instance override, because Godot
//     ignores a material-level value for an instance uniform
//   * `albedo_texture` (the imported base-colour map) and `roughness_texture` (the imported paint
//     roughness) are multiplied over the base values, so a per-asset paint map is not thrown away
//   * the orange peel and the flake are sampled in OBJECT SPACE (metres): the Roadster's UV0 is
//     ~1 unit per millimetre, so a UV-sampled micro normal would be mip-averaged into nothing
//   * the grime is based on the panel's height in car space (`panel_offset_y`), not on the mesh's
//     own origin, and it is darker and glossier when the street is wet
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float skyrush_wetness;   // 0 dry .. 1 soaked, set by the weather controller
global uniform float skyrush_rain;      // 0 dry .. 1 raining

uniform vec3 base_color : source_color = vec3(0.925, 0.929, 0.937); // Ano White #ECEDEF
instance uniform vec4 base_color_override : source_color = vec4(0.0); // per-car override (alpha > 0)
uniform bool allow_override = true;   // false: this paint keeps its colour whatever the car wears (the black panels of the two-tone Roadster)
instance uniform float panel_offset_y = 0.0;  // height of the mesh origin in car space (0 = the body root)
// The rest are PLAIN uniforms: they differ per material (hero vs traffic vs police vs taxi) and
// must survive in the .tres, which cannot store instance-uniform values.
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.12;
uniform float flake_strength : hint_range(0.0, 1.0) = 0.06;  // hero: almost none
uniform float grime_amount : hint_range(0.0, 1.0) = 0.15;   // hero stays clean
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float grime_height_m = 0.30;     // dirt line above the sill (metres above the car's base)
uniform vec3 grime_color : source_color = vec3(0.180, 0.165, 0.149); // #2E2A26 road film

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // imported base colour
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // imported paint roughness
uniform sampler2D clearcoat_roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // micro breakup of the clear coat
uniform float clearcoat_detail_scale = 0.5;   // the breakup map tiles every 2 m of the car
uniform float clearcoat_breakup : hint_range(0.0, 0.2) = 0.06; // how much the dust dulls the coat
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable; // baked panel gaps
uniform float panel_normal_strength : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D peel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable; // orange peel
uniform float peel_scale = 6.0;    // texture tiles per metre -> ~10 mm orange-peel cells
uniform float peel_strength : hint_range(0.0, 1.0) = 0.10;
uniform sampler2D flake_normal : hint_normal, filter_linear_mipmap, repeat_enable; // very fine flake
uniform float flake_scale = 60.0;  // texture tiles per metre -> ~1 mm flake
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.04;
uniform sampler2D livery_tex : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic; // RGBA decal sheet on UV2
uniform bool use_livery = false;

varying vec3 obj_pos;
varying vec3 obj_nrm;

// The named constants of the micro-relief maths (no bare numbers in the code).
const vec3 FLAT_NORMAL = vec3(0.5, 0.5, 1.0);  // the neutral normal in a normal map
const float TRI_POWER = 4.0;   // how sharp the three projections blend (the Golus triplanar)
const float CLEARCOAT_BASE = 0.0;   // the clear coat is never perfect on its own
const float GRIME_DOWN = 0.35;   // the grime on a downward-facing surface
const float GRIME_UP = 0.2;      // the grime on an upward-facing surface
const float WET_GRIME = 0.6;     // wet road film is heavier than dry road film
const float RAIN_FILM = 0.35;     // the water film on the panels


// The triplanar blend weights of a normal (the Golus whiteout blend).
vec3 tri_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(TRI_POWER));
	return b / max(b.x + b.y + b.z, 0.0001);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 paint = base_color;
	if (allow_override && base_color_override.a > 0.0) {
		paint = base_color_override.rgb;
	}
	vec3 col = paint * texture(albedo_texture, UV).rgb;
	float rough = base_roughness * texture(roughness_texture, UV).r;
	float metal = metallic_amount;
	if (use_livery) {
		vec4 lv = texture(livery_tex, UV2);
		col = mix(col, lv.rgb, lv.a);
		metal = mix(metal, 0.0, lv.a);      // vinyl decals are dielectric
		rough = mix(rough, 0.45, lv.a);
	}

	// Road grime: the height of the panel in car space, the wetness of the street, and only on the
	// surfaces that actually face down (a roof never collects road film).
	float height = obj_pos.y + panel_offset_y;
	float down = clamp(-obj_nrm.y, 0.0, 1.0);
	float up = clamp(obj_nrm.y, 0.0, 1.0);
	float grime = smoothstep(grime_height_m, 0.05, height) * grime_amount;
	grime *= mix(GRIME_DOWN, 1.0, down) * mix(1.0, GRIME_UP, up);
	grime *= mix(WET_GRIME, 1.0, skyrush_wetness);        // wet grime is heavier
	col = mix(col, grime_color * mix(1.0, 0.6, skyrush_wetness), grime);
	rough = mix(rough, mix(0.8, 0.5, skyrush_wetness), grime);

	// Micro relief in object space (metres): the panel's own three projections blended by its
	// normal, so a curved panel never switches axis in the middle of the orange peel.
	vec3 w = tri_weights(obj_nrm);
	vec3 nrm = texture(normal_texture, UV).rgb;
	nrm = mix(FLAT_NORMAL, nrm, panel_normal_strength);
	vec3 peel = texture(peel_normal, obj_pos.zy * peel_scale).rgb * w.x
		+ texture(peel_normal, obj_pos.xz * peel_scale).rgb * w.y
		+ texture(peel_normal, obj_pos.xy * peel_scale).rgb * w.z;
	nrm.xy += (peel.xy - 0.5) * peel_strength;
	vec3 flake = texture(flake_normal, obj_pos.zy * flake_scale).rgb * w.x
		+ texture(flake_normal, obj_pos.xz * flake_scale).rgb * w.y
		+ texture(flake_normal, obj_pos.xy * flake_scale).rgb * w.z;
	nrm.xy += (flake.xy - 0.5) * flake_strength;

	// Rain: a water film on the panels, glossier and a touch darker.
	float film = skyrush_rain * RAIN_FILM;
	col *= 1.0 - 0.05 * film;
	rough = mix(rough, 0.02, film);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	// The clear coat is never perfect: the dust map (SurfaceImperfections001) dulls it a touch.
	// It is sampled in object space, so the dust belongs to the car.
	float dust = texture(clearcoat_roughness_map, obj_pos.zy * clearcoat_detail_scale).r * w.x
		+ texture(clearcoat_roughness_map, obj_pos.xz * clearcoat_detail_scale).r * w.y
		+ texture(clearcoat_roughness_map, obj_pos.xy * clearcoat_detail_scale).r * w.z;
	float cc_rough = clearcoat_rough + CLEARCOAT_BASE + dust * clearcoat_breakup;
	CLEARCOAT = clearcoat_amount * (1.0 - grime);
	CLEARCOAT_ROUGHNESS = mix(cc_rough, 0.02, film);
	SPECULAR = 0.6;
}
