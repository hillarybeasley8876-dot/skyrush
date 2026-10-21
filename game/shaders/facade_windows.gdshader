// SKYRUSH - procedural office/residential facade with lit windows (one material for thousands of windows).
// Ported from ref/art/lookdev/shaders/facade_windows.gdshader [V], extended with a wall texture,
// a normal map and rain grime so no facade is a flat untextured slab.
// Facade coordinates: horizontal = OBJECT-SPACE position along the wall, vertical = WORLD height above ground_y
// (so floors line up and the ground floor is always at street level). No UV unwrap needed for box towers.
// Bake object scale into the mesh (scale = 1). Per-building variety: set instance uniform building_seed.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float building_seed = 0.0;
uniform vec3 wall_color : source_color = vec3(0.180, 0.184, 0.196); // #2E2F32 spandrel / cladding
uniform float wall_roughness : hint_range(0.0, 1.0) = 0.55;
uniform vec3 glass_color : source_color = vec3(0.043, 0.055, 0.075); // #0B0E13 unlit glass
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float floor_h = 3.8;        // offices 3.8-4.2 m, residential 2.9-3.0 m
uniform float bay_w = 1.5;          // mullion spacing
uniform vec2 window_frac = vec2(0.86, 0.62); // window size inside one bay x floor cell
uniform float sill_frac = 0.22;
uniform float ground_floors = 1.0;  // floors without office windows (lobby/shopfronts handled by other meshes)
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.38;
uniform float dark_floor_ratio : hint_range(0.0, 1.0) = 0.18; // whole floors switched off
uniform float tv_ratio : hint_range(0.0, 0.3) = 0.04;         // flickering blue TV windows (residential)
uniform vec3 light_warm : source_color = vec3(1.0, 0.655, 0.341);    // #FFA757 2700 K
uniform vec3 light_neutral : source_color = vec3(1.0, 0.757, 0.553); // #FFC18D 3500 K
uniform vec3 light_cool : source_color = vec3(0.871, 0.910, 1.0);    // #DEE8FF cool LED office (stylised)
uniform vec3 light_tv : source_color = vec3(0.616, 0.706, 1.0);      // #9DB4FF
uniform float window_energy : hint_range(0.0, 4.0) = 1.0; // keep below glow threshold: windows must not bloom
uniform float blinds_max : hint_range(0.0, 1.0) = 0.7;
uniform float ground_y = 0.0;       // world height of the street the building stands on
// --- surface detail (never a flat slab) ---
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // cladding
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;   // cladding relief
uniform float wall_uv_scale = 0.5;   // 1 / real cladding size in metres
uniform sampler2D grime_noise : hint_default_white, filter_linear_mipmap, repeat_enable; // vertical streaks
uniform float grime_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tex_mean : source_color = vec3(0.171, 0.140, 0.105); // measured mean of the cladding scan

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying float world_h;
varying float mm_seed;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	world_h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - ground_y;
	mm_seed = INSTANCE_CUSTOM.x;   // 0 for a plain MeshInstance3D, per-instance for a MultiMesh
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Facade plane coordinates in metres (u along the wall, v up).
	vec2 p = abs(obj_nrm.x) > abs(obj_nrm.z) ? vec2(obj_pos.z * sign(obj_nrm.x), world_h)
	                                         : vec2(-obj_pos.x * sign(obj_nrm.z), world_h);
	vec2 q = p / vec2(bay_w, floor_h);
	vec2 id = floor(q);
	vec2 f = fract(q);
	float seed = (building_seed + mm_seed * 997.0) * 17.31 + (abs(obj_nrm.x) > 0.5 ? 3.7 : 0.0);

	// Window rectangle, anti-aliased edges.
	vec2 fw = max(fwidth(q), vec2(1e-4));
	vec2 lo = vec2((1.0 - window_frac.x) * 0.5, sill_frac);
	vec2 hi = lo + window_frac;
	vec2 inside = smoothstep(lo - fw, lo + fw, f) * (1.0 - smoothstep(hi - fw, hi + fw, f));
	float win = inside.x * inside.y * step(ground_floors, id.y) * step(abs(obj_nrm.y), 0.5);
	vec2 w = (f - lo) / window_frac; // 0..1 inside the window

	// Occupancy and colour per window.
	float floor_on = step(dark_floor_ratio, hash12(vec2(id.y, seed)));
	float h = hash12(id + seed);
	float lit = step(h, lit_ratio) * floor_on;
	float pick = hash12(id.yx + seed * 1.7);
	// Real Shanghai at night is warm dominated: 30 % cool office LED, 28 % neutral, 42 % warm.
	vec3 lc = pick < 0.30 ? light_cool : (pick < 0.58 ? light_neutral : light_warm);
	float tv = step(1.0 - tv_ratio, hash12(id * 1.3 + seed)) * (1.0 - lit);
	float tv_flick = 0.55 + 0.45 * sin(TIME * (5.0 + 9.0 * h) + h * 40.0) * sin(TIME * 2.3 + h * 7.0);

	// Interior cues: bright ceiling strip, darker sides, blinds with slats.
	// The ceiling term peaks at 0.95 so a window never crosses the glow threshold (1.2).
	float ceiling = 0.35 + 0.6 * smoothstep(0.62, 0.95, w.y);
	float sides = 1.0 - 0.45 * pow(abs(w.x * 2.0 - 1.0), 3.0);
	float cover = hash12(id + seed + 9.1) * blinds_max;
	float blind = step(1.0 - cover, w.y) * (0.35 + 0.25 * step(0.5, fract(w.y * 28.0)));
	float shade = mix(1.0, blind, step(1.0 - cover, w.y));
	vec3 emit = (lc * lit * ceiling * sides * shade + light_tv * tv * tv_flick * 0.6) * window_energy;

	// Far LOD: when a window cell gets smaller than ~2 px, fade to the average to kill moire.
	float tiny = smoothstep(0.25, 0.6, max(fw.x, fw.y));
	vec3 avg_emit = mix(light_neutral, light_cool, 0.4) * lit_ratio * (1.0 - dark_floor_ratio) * 0.35 * window_energy;
	emit = mix(emit * win, avg_emit * step(ground_floors, id.y), tiny);
	float glass = mix(win, window_frac.x * window_frac.y, tiny);

	// Cladding texture + vertical rain grime below every sill + slab shadow at each floor line.
	vec2 wuv = p * wall_uv_scale;
	vec3 tex = clamp(texture(albedo_texture, wuv).rgb / max(tex_mean, vec3(0.001)), 0.0, 1.6);
	vec3 wall = wall_color * tex;
	float streak = texture(grime_noise, vec2(p.x * 0.35, p.y * 0.06)).r;
	wall *= 1.0 - grime_amount * streak * smoothstep(1.0, 0.0, fract(p.y / floor_h) * 1.4);
	wall *= 1.0 - 0.18 * smoothstep(0.08, 0.0, fract(p.y / floor_h));  // slab edge shadow
	vec3 nrm = texture(normal_texture, wuv).rgb;

	ALBEDO = mix(wall, glass_color, glass);
	ROUGHNESS = mix(wall_roughness, glass_roughness, glass);
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.5, glass);
	EMISSION = emit;
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), glass);   // the cladding relief is not on the glass
	NORMAL_MAP_DEPTH = 0.6;
}
