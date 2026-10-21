// SKYRUSH - car paint: base coat + metallic flakes + clear coat + optional livery + road grime.
// Godot 4.7 has energy-conserving clearcoat (release notes), so CLEARCOAT=1 is safe.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.639, 0.071, 0.106);  // #A3121B Roadster red (est.)
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.45;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.38;
uniform sampler2D flake_normal : hint_normal, filter_linear_mipmap, repeat_enable; // NoiseTexture2D as_normal_map, 256px
uniform float flake_tiling = 90.0;       // flakes per UV unit (UV ~ 1 per 1.2 m -> ~0.1 mm look at 2 K)
uniform float flake_strength : hint_range(0.0, 1.0) = 0.35;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.04;
uniform sampler2D livery_tex : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic; // RGBA decal sheet on UV2
uniform bool use_livery = false;
uniform float grime_height_m = 0.45;     // dirt line above the sill (object space, car origin on the ground)
uniform float grime_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 grime_color : source_color = vec3(0.180, 0.165, 0.149); // #2E2A26 road film

varying float obj_height;

void vertex() {
	obj_height = VERTEX.y;
}

void fragment() {
	vec3 col = base_color;
	float rough = base_roughness;
	float metal = metallic_amount;
	if (use_livery) {
		vec4 lv = texture(livery_tex, UV2);
		col = mix(col, lv.rgb, lv.a);
		metal = mix(metal, 0.0, lv.a);      // vinyl decals are dielectric
		rough = mix(rough, 0.45, lv.a);
	}
	float grime = smoothstep(grime_height_m, 0.05, obj_height) * grime_amount;
	col = mix(col, grime_color, grime);
	rough = mix(rough, 0.8, grime);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(flake_normal, UV * flake_tiling).rgb, flake_strength);
	CLEARCOAT = clearcoat_amount * (1.0 - grime);
	CLEARCOAT_ROUGHNESS = clearcoat_rough;
}
