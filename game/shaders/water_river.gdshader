// SKYRUSH - the Huangpu river. Opaque, very dark mud-brown water with two scrolling normals
// (0.6 m/s and 0.25 m/s, 40 deg apart) so the reflections of the skyline break into moving streaks.
// SSR-friendly: low base roughness, no transparency (it is opaque water).
// New shader for the environment unit (no look-dev predecessor).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.043, 0.063, 0.086); // #0B1016 RIVER_WATER
uniform float roughness_value : hint_range(0.02, 1.0) = 0.08;   // DOSSIER 4.9
uniform float wave_strength : hint_range(0.0, 1.0) = 0.38;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable; // ripple set A
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable; // ripple set B
uniform float tile_m = 6.0;         // real size of the ripple texture
uniform vec2 flow_a = vec2(0.10, 0.0);   // 0.6 m/s along +X
uniform vec2 flow_b = vec2(0.044, 0.037); // 0.25 m/s, 40 deg from flow_a
// Rain: the surface breaks into fast small ripples while it rains (the river is not a mirror).
global uniform float skyrush_rain;    // 0 dry .. 1 raining, set by the weather controller
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_scale = 2.2;     // the rain ripples are ~1 m apart
uniform float ripple_speed = 1.6;
uniform float ripple_strength = 0.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 na = texture(normal_a, uv + TIME * flow_a).rgb * 2.0 - 1.0;
	vec3 nb = texture(normal_b, uv * 1.37 + TIME * flow_b).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3((na.xy + nb.xy) * wave_strength, 1.0));

	// Rain ripples: a third, much finer layer that only exists while it rains.
	if (skyrush_rain > 0.01) {
		vec2 ruv = world_pos.xz / (tile_m / ripple_scale) + vec2(TIME * ripple_speed, -TIME * ripple_speed * 0.6);
		vec3 nr = texture(ripple_normal, ruv).rgb * 2.0 - 1.0;
		n = normalize(n + vec3(nr.xy * ripple_strength * skyrush_rain, 0.0));
	}

	// Crest highlights: where the ripple tips up, the surface roughens and catches less reflection.
	float crest = clamp(length(na.xy + nb.xy) * 0.5, 0.0, 1.0);
	float rough = clamp(roughness_value + crest * 0.18 + skyrush_rain * 0.06, 0.02, 1.0);

	ALBEDO = water_color;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.45;
}
