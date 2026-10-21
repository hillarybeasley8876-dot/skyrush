shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The soft shaft of the search light of the police drone.
//
// The cone is drawn with an additive blend and a very low alpha: a hard mesh with a bright
// material lays a grey veil over the whole screen when the game camera stands under the
// drone. The alpha is the product of four fades:
//   - the rim of the cone fades out (the soft edge of the shaft),
//   - the shaft fades along its length (full at the lamp, a quarter at the ground),
//   - the shaft fades within two metres of the ground (no hard circle on the road),
//   - the shaft fades out when the camera stands inside it.

uniform float beam_alpha : hint_range(0.0, 0.2) = 0.05;
uniform vec3 beam_color : source_color = vec3(0.85, 0.91, 1.0);
// The length of the beam (m): the fade at the ground needs it.
uniform float beam_length = 40.0;
// The alpha at the lamp and at the ground.
uniform float lamp_alpha = 1.0;
uniform float ground_alpha = 0.25;
// How much of the beam the camera sees (0 when the camera is inside it).
uniform float camera_fade = 1.0;
// The clock of the dust (s).
uniform float dust_time = 0.0;

varying vec3 local_pos;
varying vec3 world_pos;


float hash_noise(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash_noise(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash_noise(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash_noise(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash_noise(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash_noise(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash_noise(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash_noise(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash_noise(i + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}


void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// The rim of the cone: the silhouette fades out, so the shaft has no hard edge.
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.5);
	// Along the shaft: the lamp is bright, the ground is faint.
	float t = clamp(local_pos.y + 0.5, 0.0, 1.0);
	float along = mix(lamp_alpha, ground_alpha, t);
	// The last two metres before the ground fade out, so the shaft does not end in a circle.
	float to_ground = (1.0 - t) * beam_length;
	float ground = smoothstep(0.0, 2.0, to_ground);
	// The dust of the shaft: slow noise that drifts down.
	float dust = value_noise(world_pos * 0.12 + vec3(0.0, 0.0, dust_time * 0.35));
	float a = beam_alpha * edge * along * ground * camera_fade * (0.55 + 0.45 * dust);
	ALBEDO = beam_color;
	ALPHA = a;
}
