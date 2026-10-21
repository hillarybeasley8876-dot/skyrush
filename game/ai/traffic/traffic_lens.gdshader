// SKYRUSH - traffic lamp lens: the real lens of an npc car.
//
// The npc models ship their lamp lenses as surfaces of the lamp meshes (see
// TrafficLampMaterials). This shader replaces the model's own lens material so that:
//
//  * the lens only glows on the faces that look OUT of the car. The shell of a lamp has an
//    inner face, and the panels of the body are one sided, so a car that is seen from the
//    front used to show the red inner face of the rear lamp through the side windows.
//  * the emission is MULTIPLIED with the strip of the model's own atlas, so the 50 % duty
//    LED strip of the model modulates the glow: the lamp reads as segments with hot cores
//    and dark gaps instead of one neon tube.
//  * an unlit lens is clear glass over a chrome reflector (a dark albedo, a low roughness and
//    a high metalness), not a white sticker.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The colour of the lit lamp.
uniform vec3 lamp_color : source_color = vec3(1.0, 0.1, 0.18);
// The energy of the lit lamp (the atlas of the model is multiplied with it).
uniform float energy : hint_range(0.0, 64.0) = 1.0;
// The direction the lens looks at, in the model space of the mesh (the axis of the lamp).
uniform vec3 lamp_axis = vec3(0.0, 0.0, 1.0);
// How dark the back of the lens is (the housing of the lamp).
uniform vec3 housing_color : source_color = vec3(0.02, 0.02, 0.025);
// The colour of the lens itself (the base colour of the model's material).
uniform vec3 lens_tint : source_color = vec3(1.0, 1.0, 1.0);
// How bright the lens is when it is not lit.
uniform float albedo_scale : hint_range(0.0, 2.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// The textures of the model: the atlas of the trim holds the pattern of the lamp.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_albedo_texture = false;
uniform bool use_emission_texture = false;
// The UV transform of the model (the glTF files may carry one).
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

varying vec3 obj_n;

void vertex() {
	// The normal of the mesh in its own model space.
	obj_n = NORMAL;
}

void fragment() {
	// Only the faces that look out of the car may glow: the inner face of the lamp shell
	// points the other way and has to stay dark.
	float facing = smoothstep(0.2, 0.5, dot(normalize(obj_n), normalize(lamp_axis)));
	vec2 uv = UV * uv_scale + uv_offset;
	vec3 albedo = vec3(1.0);
	if (use_albedo_texture) {
		albedo = texture(albedo_texture, uv).rgb;
	}
	albedo *= lens_tint * albedo_scale;
	ALBEDO = mix(housing_color, albedo, facing);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	vec3 strip = vec3(1.0);
	if (use_emission_texture) {
		strip = texture(emission_texture, uv).rgb;
	}
	EMISSION = lamp_color * strip * energy * facing;
}
