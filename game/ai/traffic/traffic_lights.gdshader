// SKYRUSH - traffic lamp lens: an unlit lens of light.
//
// Used for the procedural fallback bodies and for the amber indicator cards of the AI traffic.
// The npc models ship their own lens materials (see TrafficLampMaterials), so this shader only
// has to cover what the models do not have.
//
// The lens is drawn with the back faces culled, so the far side of a lamp cannot shine through
// the cabin of the car, and it is alpha blended with a soft edge so it reads as a round lens
// instead of a hard rectangle.
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 lamp_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float energy : hint_range(0.0, 12.0) = 1.0;
// The lens detail of the model, when the lens has a texture of its own.
uniform bool use_texture = false;
uniform sampler2D lens_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	// Soft edges so the lens reads as a round lamp instead of a hard rectangle.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float a = smoothstep(0.0, 0.22, edge);
	vec3 lens = vec3(1.0);
	if (use_texture) {
		lens = texture(lens_texture, UV).rgb;
	}
	ALBEDO = lamp_color * energy * a * lens;
	ALPHA = a * clamp(energy, 0.0, 1.0);
}
