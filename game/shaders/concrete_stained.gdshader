// SKYRUSH - stained concrete for piers, parapets, barriers and walls.
// World-space TRIPLANAR projection of the shared library textures (so seams never line up with the
// geometry), a vertical rain-drip mask, a splash-zone darkening in the lowest `splash_height_m`
// above the object's base and a per-instance tint so every pier is not the same grey.
//
// The library scans are warm and not centred on 0.5, so the albedo is divided by the MEASURED
// mean of its own scan (`tex_mean`, set per material by the factory). Without that the pier
// renders near-black and the barrier renders brown.
// The DETAIL layer is a second scan (granite_tile_03 on the Bund stone); it has its own mean
// (`detail_mean`), otherwise the detail darkens the surface by the ratio of the two scans.
// New shader for the environment unit (DOSSIER 4.3 / 5.3-7).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float skyrush_wetness;   // 0 dry .. 1 soaked, set by the weather controller

// Per-material defaults (plain) with per-object overrides (instance). Godot ignores a
// material-level value for an instance uniform, so the .tres carries the plain one.
uniform vec3 concrete_tint : source_color = vec3(1.0);      // per-material tint
uniform float splash_factor : hint_range(0.0, 1.0) = 1.0;  // strength of the wet bottom
instance uniform vec4 tint_override : source_color = vec4(0.0);   // alpha > 0 = valid
instance uniform float splash_override = -1.0;                    // >= 0 = valid
instance uniform float base_y = 0.0;   // object-space height of the object's base (0 = origin at the base)

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D drip_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_mask : hint_default_white, filter_linear_mipmap, repeat_enable; // 128x1024 stretched noise
uniform float uv_scale = 0.25;      // 1 / real texture size in metres (concrete = 4 m -> 0.25)
uniform float detail_scale = 3.0;   // the detail layer repeats 3x tighter (DOSSIER 4.3)
uniform float detail_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tex_mean : source_color = vec3(0.171, 0.140, 0.105); // measured mean of the scan (linear)
uniform vec3 base_color : source_color = vec3(0.478, 0.471, 0.455); // #7A7874 CONCRETE
uniform float albedo_mul : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D streak_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.45;
uniform float streak_scale = 0.3;    // 1 / metres across the wall
uniform float drip_amount : hint_range(0.0, 1.0) = 0.0; // drips from the Leaking* opacity maps
uniform float drip_lo_m = 1.8;       // the drips run between these heights
uniform float drip_hi_m = 6.0;
uniform float splash_height_m = 0.6;
uniform float splash_darken : hint_range(0.0, 1.0) = 0.30;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.55;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;  // the scan's normal strength (DOSSIER 4.9: 0.5 on granite)
uniform vec3 detail_mean : source_color = vec3(0.0);  // the detail scan's own mean; 0 = use tex_mean
// Masonry courses: a stone wall is laid in courses, not in a square grid (the Bund granite read as
// bathroom tiles without them). course_height_m = 0 turns the layer off (cast concrete).
uniform float course_height_m = 0.0;
uniform float course_width_m = 1.8;   // the length of one stone
uniform float course_joint : hint_range(0.0, 1.0) = 0.0;  // how dark the joint reads

// The named constants of the layer maths (no bare numbers in the code).
const float DETAIL_NORM_MAX = 1.6;   // the detail may not brighten the surface by more than 60 %
const float SCAN_NORM_MAX = 1.35;    // the base scan may not blow out to white
const float DETAIL_MIX = 0.5;        // the detail is mixed in at half of its amount
const float DRIP_U_SCALE = 0.25;     // the drip sheet repeats every 4 m along the wall
const float DRIP_LO = 0.35;          // the drip mask below this is no stain
const float DRIP_HI = 0.70;          // the drip mask above this is a full stain
const float AO_MIX = 0.8;            // how much of the AO map darkens the crevices

varying vec3 world_pos;
varying vec3 world_nrm;
varying float obj_y;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	obj_y = VERTEX.y - base_y;   // height above the object's own base, not the mesh origin
}

// Triplanar blend weights from the world normal.
vec3 tri_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	return b / max(b.x + b.y + b.z, 0.0001);
}

void fragment() {
	vec3 w = tri_weights(world_nrm);
	vec3 p = world_pos * uv_scale;
	vec3 alb = texture(albedo_texture, p.zy).rgb * w.x
		+ texture(albedo_texture, p.xz).rgb * w.y
		+ texture(albedo_texture, p.xy).rgb * w.z;
	float rough = texture(roughness_texture, p.zy).r * w.x
		+ texture(roughness_texture, p.xz).r * w.y
		+ texture(roughness_texture, p.xy).r * w.z;
	float ao = texture(ao_texture, p.zy).r * w.x
		+ texture(ao_texture, p.xz).r * w.y
		+ texture(ao_texture, p.xy).r * w.z;

	// The whiteout triplanar normal (Golus): each projection is built in its own plane and the
	// three are summed in WORLD space, so no axis loses its detail and no texel flips.
	vec3 n = world_nrm;
	vec3 tx = texture(normal_texture, p.zy).rgb * 2.0 - 1.0;
	vec3 ty = texture(normal_texture, p.xz).rgb * 2.0 - 1.0;
	vec3 tz = texture(normal_texture, p.xy).rgb * 2.0 - 1.0;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 n_world = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);

	// Detail layer (DOSSIER 4.3): the same scan 3x tighter, multiplied in with a stretched noise
	// mask. It is normalised by ITS OWN measured mean, or it would darken the surface by the
	// ratio between the two scans (the Bund granite's detail is a different scan than its base).
	vec2 duv = abs(world_nrm.y) > 0.5 ? p.xz
		: (abs(world_nrm.x) > abs(world_nrm.z) ? p.zy : p.xy);
	vec3 detail = texture(detail_texture, duv * detail_scale).rgb;
	vec3 dmean = detail_mean.r > 0.001 ? detail_mean : tex_mean;
	vec3 detail_norm = clamp(detail / max(dmean, vec3(0.001)), vec3(0.0), vec3(DETAIL_NORM_MAX));
	float dmask = texture(detail_mask, vec2(duv.x * 0.35, duv.y * 3.0)).r;
	alb *= mix(vec3(1.0), detail_norm, detail_amount * DETAIL_MIX * (0.5 + 0.5 * dmask));

	// Rain streaks: thin vertical drips on the vertical faces only. The horizontal coordinate
	// runs ALONG the wall, so the drips are narrow lines and not wide bands.
	float vertical = 1.0 - abs(world_nrm.y);
	float tangent = abs(world_nrm.x) > abs(world_nrm.z) ? world_pos.z : world_pos.x;
	float streak = texture(streak_noise, vec2(tangent * streak_scale, world_pos.y * 0.045)).r;
	float streak_mask = streak_amount * vertical * smoothstep(0.55, 0.92, streak);

	// Drips from the Leaking* opacity maps: the sheet is white at its top and black at its
	// bottom, so it is mapped ONCE over the 1.8-6 m band - the stains hang from the top of the
	// band and fade out downwards. Tiling it vertically would read as wallpaper.
	if (drip_amount > 0.0) {
		float band_h = max(drip_hi_m - drip_lo_m, 0.01);
		float v = 1.0 - clamp((world_pos.y - drip_lo_m) / band_h, 0.0, 1.0);
		float drip = texture(drip_texture, vec2(tangent * DRIP_U_SCALE, v)).r;
		float band = smoothstep(drip_lo_m - 0.2, drip_lo_m + 0.2, world_pos.y)
			* (1.0 - smoothstep(drip_hi_m - 0.2, drip_hi_m + 0.2, world_pos.y));
		streak_mask += drip_amount * vertical * band * smoothstep(DRIP_LO, DRIP_HI, drip);
	}

	// Masonry courses: a horizontal joint every course_height_m and a vertical joint every
	// course_width_m, offset by half a stone on the odd courses (a staggered bond).
	float course_mask = 0.0;
	if (course_height_m > 0.01 && course_joint > 0.001) {
		float row = floor(world_pos.y / course_height_m);
		float dy = abs(world_pos.y - (row + 0.5) * course_height_m);
		float joint_h = 1.0 - smoothstep(0.0, course_height_m * 0.06, dy);
		float u_along = abs(world_nrm.x) > abs(world_nrm.z) ? world_pos.z : world_pos.x;
		float offset = mod(row, 2.0) * 0.5 * course_width_m;
		float dx = abs(fract((u_along + offset) / course_width_m + 0.5) - 0.5) * course_width_m;
		float joint_v = 1.0 - smoothstep(0.0, course_width_m * 0.012, dx);
		course_mask = max(joint_h, joint_v) * vertical;
		alb *= 1.0 - course_joint * course_mask;
	}

	// The scan is normalised by its own measured mean, so the material keeps its intended hue.
	// The ratio is clamped: the bright end of a scan must not turn into a white blow-out.
	vec3 tint = concrete_tint;
	if (tint_override.a > 0.0) {
		tint = tint_override.rgb;
	}
	vec3 norm = clamp(alb / max(tex_mean, vec3(0.001)), vec3(0.0), vec3(SCAN_NORM_MAX));
	vec3 col = base_color * norm * albedo_mul * tint;
	col *= 1.0 - clamp(streak_mask, 0.0, 1.0);            // dirt runs down the wall
	col *= mix(1.0, ao, AO_MIX);                          // the AO map darkens the crevices

	// Splash zone: the bottom `splash_height_m` above the base is darker, wetter and rougher.
	float splash_amount = splash_override < 0.0 ? splash_factor : splash_override;
	float splash = (1.0 - smoothstep(0.0, splash_height_m, obj_y)) * splash_amount;
	col *= 1.0 - splash_darken * splash;
	rough = mix(rough, wet_roughness, splash * skyrush_wetness);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	// normal_scale < 1 keeps the scan's relief subtle (the granite sparkles beyond 15 m at full
	// strength, DOSSIER 4.9).
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(world_nrm, n_world, normal_scale)), 0.0)).xyz);
}
