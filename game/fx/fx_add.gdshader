shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Additive billboard material for hot effects (sparks, flames, flashes, ground rings).
// The per-instance colour carries the tint and the fade, INSTANCE_CUSTOM.y the energy
// multiplier, so one material serves both a dim spark tail and a 20x hot head (E5 tier).
//
// billboard_mode:
//   0 = off     the quad keeps the orientation of the emitter (the spark pool orients its
//               quads on the CPU instead, they are velocity stretched)
//   1 = full    the quad faces the camera
//   2 = upright the quad turns around the world Y only, so a flame stands up from every side
//
// The atlas (the flame) picks its cell from the rotation of the particle, which is fixed for
// the life of the particle: the shape of a lick never pops.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// A second texture for the particles that ask for it (INSTANCE_CUSTOM.z): the pool of sparks
// draws the hot streaks and the cold air ribbons with the same material.
uniform sampler2D alt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float atlas_cells : hint_range(0.0, 8.0) = 0.0;
uniform float billboard_mode : hint_range(0.0, 2.0) = 0.0;
uniform float roll_max : hint_range(0.0, 1.0) = 0.17;
uniform float push : hint_range(0.0, 10.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float energy : hint_range(0.0, 40.0) = 6.0;
uniform float alpha_scale : hint_range(0.0, 4.0) = 1.0;

varying float v_energy;
varying vec2 v_uv;
varying float v_alt;


void vertex() {
	v_energy = INSTANCE_CUSTOM.y > 0.0 ? INSTANCE_CUSTOM.y : 1.0;
	v_alt = INSTANCE_CUSTOM.z;
	// The rotation of the particle is a stable per particle random: it picks the cell of the
	// atlas and the small roll of an upright billboard.
	float hash = fract(atan(MODEL_MATRIX[1].x, MODEL_MATRIX[0].x) / TAU * 37.0 + 0.5);
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (billboard_mode > 0.5) {
		vec3 to_cam = CAMERA_POSITION_WORLD - origin;
		if (length(to_cam) < 0.0001) {
			to_cam = vec3(0.0, 0.0, 1.0);
		}
		to_cam = normalize(to_cam);
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		vec3 right;
		vec3 up;
		if (billboard_mode > 1.5) {
			// Upright: the quad turns around the world Y only, with a roll of a few degrees.
			vec3 flat_to_cam = vec3(to_cam.x, 0.0, to_cam.z);
			if (length(flat_to_cam) < 0.001) {
				flat_to_cam = vec3(0.0, 0.0, -1.0);
			}
			flat_to_cam = normalize(flat_to_cam);
			right = normalize(cross(vec3(0.0, 1.0, 0.0), flat_to_cam));
			up = vec3(0.0, 1.0, 0.0);
			float roll = (hash - 0.5) * 2.0 * roll_max;
			vec3 side = cross(up, right);
			right = right * cos(roll) + side * sin(roll);
		} else {
			right = INV_VIEW_MATRIX[0].xyz;
			up = INV_VIEW_MATRIX[1].xyz;
		}
		vec3 face = to_cam;
		origin += to_cam * push;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sx, 0.0), vec4(up * sy, 0.0),
				vec4(face, 0.0), vec4(origin, 1.0));
	}
	vec2 uv = UV;
	if (atlas_cells > 0.5) {
		float cells = atlas_cells * atlas_cells;
		float index = floor(hash * cells);
		vec2 cell = vec2(mod(index, atlas_cells), floor(index / atlas_cells));
		uv = (cell + UV) / atlas_cells;
	}
	v_uv = uv;
}


void fragment() {
	vec4 tex = vec4(1.0, 1.0, 1.0, 1.0);
	if (use_texture) {
		tex = v_alt > 0.5 ? texture(alt_tex, v_uv) : texture(albedo_tex, v_uv);
	}
	vec3 c = tex.rgb * COLOR.rgb * tint;
	ALBEDO = c * energy * v_energy;
	ALPHA = tex.a * COLOR.a * alpha_scale;
}
