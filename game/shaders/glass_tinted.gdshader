// SKYRUSH - tinted car glass for traffic cars (NPC). Dark, slightly dirty, cheap and opaque enough
// to hide the empty interior of a low-detail traffic model.
// New shader for the environment unit (sibling of glass_canopy.gdshader).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float skyrush_wetness;   // 0 dry .. 1 soaked
global uniform float skyrush_rain;      // 0 dry .. 1 raining

uniform vec3 tint_color : source_color = vec3(0.039, 0.055, 0.071); // #0A0E12
uniform float base_alpha : hint_range(0.0, 1.0) = 0.72;
uniform float fresnel_power : hint_range(1.0, 6.0) = 3.0;
uniform float fresnel_opacity : hint_range(0.0, 1.0) = 0.95;
uniform float roughness_value : hint_range(0.02, 1.0) = 0.08;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D grime_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// hint_default_black: Godot's unset sampler is WHITE, which would saturate the grime mask.
uniform sampler2D albedo_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable; // imported grime

varying vec2 glass_uv;

void vertex() {
	glass_uv = UV;
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power);
	float grime = texture(grime_noise, glass_uv * vec2(3.0, 6.0)).r;
	grime = max(grime, texture(albedo_texture, UV).r);   // the imported dirt map (authored UVs)
	float dirt = grime * grime_amount * (0.4 + 0.6 * skyrush_wetness);

	vec3 col = tint_color * (1.0 + dirt * 1.2);
	float alpha = clamp(mix(base_alpha, fresnel_opacity, fres) + dirt * 0.2, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = clamp(roughness_value + dirt * 0.35 + skyrush_rain * 0.05, 0.02, 1.0);
	SPECULAR = 0.85;
}
