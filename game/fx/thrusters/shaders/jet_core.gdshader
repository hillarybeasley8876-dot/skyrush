shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled,
	fog_disabled, specular_disabled;

// Cold-gas jet core (dossier §6.1 / §6.3): a tight, very bright cone right at the throat that
// fades along its length, with Mach shock diamonds as brighter bands. White-blue, never orange.
//
// The base between the diamonds stays at 0.15-0.2 HDR and the diamonds peak at about 1.5 HDR
// (the brief's "emission ~1.5, just enough bloom"), so the bands read as bands instead of one
// white slab, and only the diamonds catch the scene glow.

uniform vec3 core_color : source_color = vec3(0.918, 0.957, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// HDR energy: just enough for the scene glow to catch the bright core.
uniform float energy : hint_range(0.0, 8.0) = 1.5;
// Positions of the four shock diamonds, in METRES from the throat.
uniform vec4 ring_pos = vec4(0.06, 0.15, 0.24, 0.33);
// Relative brightness of each diamond.
uniform vec4 ring_bright = vec4(1.0, 0.7, 0.45, 0.25);
// The width of a diamond, in metres.
uniform float ring_width : hint_range(0.001, 0.2) = 0.025;
// The cone's current length in metres. The diamonds are placed in metres, so they stay at the
// same distance from the throat however far the throttle stretches the cone.
uniform float cone_length : hint_range(0.01, 4.0) = 0.9;
// How much the cone is pinched at a diamond.
uniform float pinch : hint_range(0.0, 0.5) = 0.25;
// Flicker phase so the ten nozzles do not pulse in lockstep.
uniform float phase = 0.0;
uniform float flicker_amount : hint_range(0.0, 0.3) = 0.08;
// The axial core: a narrow bright line down the middle of the jet.
uniform float core_gain : hint_range(0.0, 2.0) = 0.15;
// How much brighter a diamond is than the base between them.
uniform float ring_gain : hint_range(0.0, 20.0) = 6.0;

float _flicker() {
	// 25 Hz and 33 Hz, mixed: the real plume shimmers, it does not strobe.
	float s = sin(TIME * 157.08 + phase) * 0.6 + sin(TIME * 207.35 + phase * 1.7) * 0.4;
	return 1.0 + flicker_amount * s;
}

// The shock diamonds, as a function of the distance from the throat in metres.
float _rings(float m) {
	float w = max(ring_width, 0.001);
	float d0 = (m - ring_pos.x) / w;
	float d1 = (m - ring_pos.y) / w;
	float d2 = (m - ring_pos.z) / w;
	float d3 = (m - ring_pos.w) / w;
	return ring_bright.x * exp(-d0 * d0) + ring_bright.y * exp(-d1 * d1)
		+ ring_bright.z * exp(-d2 * d2) + ring_bright.w * exp(-d3 * d3);
}

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	float f = _flicker();
	VERTEX.y *= f;
	// Pinch the cone at the shock diamonds, so they read as diamonds and not as flat rings.
	float pin = min(_rings(UV.y * cone_length), 1.0);
	VERTEX.xz *= 1.0 - pinch * pin;
	// Correct the normal for the y-only stretch (inverse transpose of diag(1, f, 1)).
	NORMAL = normalize(vec3(NORMAL.x, NORMAL.y / f, NORMAL.z));
}

void fragment() {
	float v = clamp(UV.y, 0.0, 1.0);
	// The distance from the throat, in metres: the diamonds sit at fixed distances.
	float m = v * cone_length;
	// Facing term: the thickest part of the cone is where the wall looks straight at the camera,
	// so the jet reads as a solid bright core with soft silhouette edges. The absolute value
	// makes it independent of the sign convention of VIEW and lets both walls of the cone
	// contribute (the mesh is drawn with culling off).
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, 1.5);
	// Fade out along the length; the tip dissolves into vapour.
	float fade = pow(1.0 - v, 1.4);

	// The diamonds are brightest on the axis and fade out at the silhouette.
	float rings = _rings(m) * pow(facing, 3.0);
	// Streaky noise scrolling along the jet behind the third diamond, so the cone is not
	// CG-smooth.
	float streak = 1.0;
	if (m > ring_pos.z) {
		float n = _noise(vec2(UV.x * 9.0, m * 46.0 - TIME * 10.0));
		streak = 0.72 + 0.56 * n;
	}

	// The base between the diamonds stays at 0.15-0.2 HDR and the first diamond peaks at about
	// 1.5 HDR, so the bands read against the core instead of merging into one white slab.
	float base = energy * (0.10 + 0.03 * fade);
	float bright = base * (1.0 + rings * ring_gain) * streak;
	// The axial core: a narrow bright line down the middle of the jet. It is multiplied by the
	// diamonds, so it lights them and not the gaps between them.
	float core = exp(-pow((1.0 - facing) * 6.0, 2.0));
	bright += core * energy * core_gain * fade * rings;
	ALBEDO = core_color * bright;
	ALPHA = clamp(body * fade * intensity * (0.30 + rings * 1.2) * streak, 0.0, 1.0);
}
