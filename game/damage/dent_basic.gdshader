// SKYRUSH - a generic car surface with the dent field of dossier 7.5 A.
//
// The damage unit replaces the BaseMaterial3D of the surfaces that are not paint (the black
// trim, the door card, the inner dark, the lamp lens) with this shader, so that EVERY
// surface of the car inside the dent sphere is pushed by the same field. Without it the
// paint sinks behind the trim that stayed in place, and the dent reads as a black patch.
//
// The look of the BaseMaterial3D it replaces is kept: the albedo colour and texture, the
// roughness and metallic (with their texture channels), the normal map, the emission and
// the UV scale.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://damage/dent_field.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_albedo_map = 0.0;
uniform vec2 uv1_scale = vec2(1.0, 1.0);
uniform vec2 uv1_offset = vec2(0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_metallic_map = 0.0;
uniform int metallic_channel = 0;
uniform float roughness = 0.5;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_roughness_map = 0.0;
uniform int roughness_channel = 0;
uniform float normal_strength = 1.0;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_normal_map = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_energy = 0.0;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_emission_map = 0.0;
uniform float use_vertex_color = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

// The value of one channel of a texture (the roughness and the metallic maps of the cars
// pack two channels in one image).
float pick_channel(vec4 c, int channel) {
	if (channel == 1) {
		return c.g;
	}
	if (channel == 2) {
		return c.b;
	}
	if (channel == 3) {
		return c.a;
	}
	return c.r;
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	VERTEX = dent_displace(VERTEX);
}

void fragment() {
	vec2 uv = UV * uv1_scale + uv1_offset;
	vec4 albedo = base_color;
	if (use_albedo_map > 0.5) {
		albedo *= texture(albedo_texture, uv);
	}
	if (use_vertex_color > 0.5) {
		albedo *= COLOR;
	}
	float metal = metallic;
	if (use_metallic_map > 0.5) {
		metal *= pick_channel(texture(metallic_texture, uv), metallic_channel);
	}
	float rough = roughness;
	if (use_roughness_map > 0.5) {
		rough *= pick_channel(texture(roughness_texture, uv), roughness_channel);
	}
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	if (use_normal_map > 0.5) {
		nrm = texture(normal_texture, uv).rgb;
	}
	vec3 emission = emission_color * emission_energy;
	if (use_emission_map > 0.5) {
		emission *= texture(emission_texture, uv).rgb;
	}

	// The bowl of the dent, bent per pixel: the same field as the paint, so the trim and
	// the paint around the dent shade as one surface.
	vec3 obj_n = normalize(obj_nrm);
	float deepest = 0.0;
	float depth_of_deepest = 0.0;
	vec3 grad = dent_gradient(obj_pos, deepest, depth_of_deepest);
	vec3 bent = normalize(obj_n - (grad - obj_n * dot(grad, obj_n)));
	NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * bent, 0.0)).xyz);

	ALBEDO = albedo.rgb;
	METALLIC = clamp(metal, 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	EMISSION = emission;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
}
