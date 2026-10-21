// SKYRUSH - wet asphalt road surface (elevated decks, streets, ramps).
// Ported from ref/art/lookdev/shaders/road_wet.gdshader [V], adapted to the game:
//   * texture uniforms use the canonical names MaterialLibrary fills from the imported material
//     (albedo_texture / normal_texture / roughness_texture)
//   * wetness and rain come from the shader globals skyrush_wetness / skyrush_rain
//     (driven by the weather controller); a per-material bias can nudge them
// World-space UVs (no UV unwrap needed), anti-tiling, macro variation, wetness + puddles + rain ripples.
// Vertex colour from the Blender generator (optional; white = neutral, so meshes without colours just work):
//   track = 1 - COLOR.r  (paint R=0 in the two wheel paths of each lane -> polished, darker)
//   low   = 1 - COLOR.g  (paint G=0 along gutters / dips -> collects puddles)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float skyrush_wetness;   // 0 dry .. 1 soaked, set by the weather controller
global uniform float skyrush_rain;      // 0 dry .. 1 raining

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable; // *_nor_gl (OpenGL Y+)
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;                 // real size of the texture (asphalt_02 = 3.0 m)
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable; // aerial_asphalt_01 diff or noise
uniform float macro_m = 37.0;               // macro repeat in metres (use a prime-ish number)
uniform float macro_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tint : source_color = vec3(1.0);
uniform float albedo_mul : hint_range(0.2, 1.5) = 0.55;   // asphalt_02 mean #5B5955 -> dry ~#424240
uniform float wetness_bias : hint_range(-1.0, 1.0) = 0.0;  // added to the global wetness
uniform float rain_bias : hint_range(-1.0, 1.0) = 0.0;     // added to the global rain

uniform float detail_strength : hint_range(0.0, 1.0) = 0.5;  // the x4 detail normal (DOSSIER 5.3 #4)
uniform float detail_fade_m = 26.0;      // beyond this distance the detail normal is gone (no sparkle)
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.20;
uniform sampler2D puddle_noise : hint_default_black, filter_linear_mipmap, repeat_enable; // seamless noise
uniform float puddle_m = 14.0;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable; // NoiseTexture2D as_normal_map

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Two samples at unrelated scale/offset, blended by macro noise -> breaks visible repetition.
vec4 sample_untiled(sampler2D t, vec2 uv, float m) {
	vec4 a = texture(t, uv);
	vec4 b = texture(t, uv * 0.61 + vec2(0.37, 0.73));
	return mix(a, b, smoothstep(0.35, 0.65, m));
}

void fragment() {
	float wetness = clamp(skyrush_wetness + wetness_bias, 0.0, 1.0);
	float rain = clamp(skyrush_rain + rain_bias, 0.0, 1.0);
	vec2 uv = world_pos.xz / tile_m;
	float macro = texture(macro_tex, world_pos.xz / macro_m).r;
	vec3 base = sample_untiled(albedo_texture, uv, macro).rgb * tint * albedo_mul;
	base *= mix(1.0, 0.75 + 0.5 * macro, macro_strength);
	vec3 nrm = sample_untiled(normal_texture, uv, macro).rgb;
	float rough = sample_untiled(roughness_texture, uv, macro).r;

	float track = 1.0 - COLOR.r;
	float low = 1.0 - COLOR.g;
	base *= 1.0 - 0.12 * track;                       // polished, oil-darkened wheel paths
	rough = mix(rough, rough * 0.75, track);

	// Puddles: noise + low spots, soft 6 cm shore line.
	float n = texture(puddle_noise, world_pos.xz / puddle_m).r + low * 0.35;
	float thr = 1.0 - puddle_amount * wetness;
	float puddle = smoothstep(thr - 0.03, thr + 0.03, n);
	float wet = clamp(wetness + puddle, 0.0, 1.0);

	// Wet darkening (porous surface ~ -45 %), puddle water is darker still.
	vec3 alb = base * mix(1.0, 0.55, wet);
	alb = mix(alb, base * 0.32, puddle);
	rough = mix(rough, rough * 0.20 + 0.025, wet);      // asphalt_02 rough ~0.77 -> ~0.18 wet: long light streaks
	rough = mix(rough, 0.03, puddle);
	vec3 flat_n = vec3(0.5, 0.5, 1.0);
	nrm = mix(nrm, flat_n, clamp(wet * 0.25 + puddle * 0.95, 0.0, 1.0));
	vec3 rip = texture(ripple_normal, world_pos.xz / 1.7 + vec2(TIME * 0.11, TIME * 0.07)).rgb;
	nrm = mix(nrm, rip, puddle * rain * 0.35);

	// Detail normal at x4 frequency, whiteout blended, faded out with the distance so it can never
	// sparkle at 100 m (DOSSIER 5.3 #4).
	float cam_dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float detail_fade = (1.0 - smoothstep(detail_fade_m * 0.3, detail_fade_m, cam_dist)) * detail_strength;
	if (detail_fade > 0.001) {
		vec3 dn = texture(normal_texture, uv * 4.0).rgb * 2.0 - 1.0;
		nrm = normalize(nrm + vec3(dn.xy * detail_fade, 0.0));
	}
	float ao = texture(ao_texture, uv).r;

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	AO = mix(1.0, ao, 0.8);
}
