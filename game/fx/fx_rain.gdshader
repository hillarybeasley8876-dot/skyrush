shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Rain streaks. The quad faces the camera around the axis (rain velocity - camera velocity), so
// at 200 km/h the streaks rush at the camera instead of hanging vertically. The length grows
// with the relative speed.

uniform sampler2D streak_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.72, 0.80, 0.88);
uniform vec3 relative_velocity = vec3(0.0, -17.0, 0.0);
uniform float width : hint_range(0.005, 0.2) = 0.035;
uniform float length_scale : hint_range(0.1, 4.0) = 1.0;
uniform float alpha_scale : hint_range(0.0, 2.0) = 0.4;
// How much the streaks converge on the vanishing point (0 = vertical, 1 = full).
uniform float convergence : hint_range(0.0, 1.0) = 0.0;


void vertex() {
	vec3 axis = (VIEW_MATRIX * vec4(relative_velocity, 0.0)).xyz;
	// The vanishing point of the view: at speed the streaks point at it, so they read as
	// rain that rushes past the camera.
	vec3 view_position = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_vanishing = normalize(vec3(0.0, 0.0, -1000.0) - view_position);
	axis = normalize(axis + to_vanishing * convergence);
	vec3 up = axis - axis.z * vec3(0.0, 0.0, 1.0);
	if (length(up) < 0.0001) {
		up = vec3(0.0, 1.0, 0.0);
	}
	up = normalize(up);
	vec3 right = normalize(cross(up, vec3(0.0, 0.0, 1.0)));
	float particle_scale = length(MODEL_MATRIX[0].xyz);
	float speed = length(axis);
	float streak_length = width * particle_scale * 2.0
			+ speed * 0.025 * length_scale;
	MODELVIEW_MATRIX[0] = vec4(right * width * particle_scale, 0.0);
	MODELVIEW_MATRIX[1] = vec4(up * streak_length, 0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, 1.0, 0.0);
}


void fragment() {
	vec4 tex = texture(streak_tex, UV);
	ALBEDO = tint * tex.rgb;
	ALPHA = tex.a * COLOR.a * alpha_scale;
}
