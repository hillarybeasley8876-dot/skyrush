// SKYRUSH - road paint (lane lines, arrows, Chinese road text, zebra) on thin mesh strips.
// Strips are generated in Blender 0.005 m above the road (never coplanar). UV: u = 0..1 across, v = metres along.
// Use the SAME wetness value as road_wet.gdshader. Text/arrow strips: set mask_tex to the white-on-black glyph PNG.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_color : source_color = vec3(0.914, 0.906, 0.875); // white #E9E7DF ; yellow #E8B520
uniform sampler2D mask_tex : hint_default_white, filter_linear_mipmap_anisotropic; // glyph/arrow alpha (white = paint)
uniform bool use_mask = false;
uniform sampler2D wear_noise : hint_default_white, filter_linear_mipmap, repeat_enable; // seamless noise
uniform float wear : hint_range(0.0, 1.0) = 0.25;          // 0 new paint .. 1 almost gone
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float retro_strength : hint_range(0.0, 2.0) = 0.35; // glass-bead retroreflection fake
uniform float retro_near_m = 6.0;
uniform float retro_far_m = 70.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float shape = use_mask ? texture(mask_tex, UV).r : 1.0;
	float n = texture(wear_noise, world_pos.xz * 0.9).r * 0.7 + texture(wear_noise, world_pos.xz * 4.3).r * 0.3;
	float paint = shape * smoothstep(wear - 0.05, wear + 0.05, n);
	if (paint < 0.5) {
		discard; // worn-away paint shows the real road underneath
	}
	vec3 alb = paint_color * mix(1.0, 0.8, wetness);          // paint is not porous: darkens only ~20 %
	ALBEDO = alb * mix(0.85, 1.0, n);                           // dirt mottling
	ROUGHNESS = mix(0.62, 0.18, wetness);
	SPECULAR = 0.5;
	float d = length(world_pos - CAMERA_POSITION_WORLD);
	float retro = smoothstep(retro_far_m, retro_near_m, d) * retro_strength * (1.0 - 0.5 * wetness);
	EMISSION = paint_color * retro;                             // stays far below the glow threshold
}
