shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// The shop name boards of the city are one MultiMesh: the cell of the atlas that carries the
// name of a board comes from the INSTANCE_CUSTOM of the instance (the uv offset and the scale).

uniform sampler2D albedo_texture : source_color, filter_linear;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;

varying vec2 v_cell_offset;
varying vec2 v_cell_scale;


void vertex() {
	v_cell_offset = INSTANCE_CUSTOM.xy;
	v_cell_scale = INSTANCE_CUSTOM.zw;
}


void fragment() {
	vec2 uv = UV * v_cell_scale + v_cell_offset;
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * emission_energy;
	ROUGHNESS = 0.35;
	SPECULAR = 0.3;
}
