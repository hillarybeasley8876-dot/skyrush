// SKYRUSH - neon tube / LED strip sign (lit geometry: tubes are real cylinders 12-20 mm radius, or flat LED strips).
// White-hot core + saturated rim, rare dropouts, optional "faulty" sign. Per-sign variety via instance uniforms,
// so ONE material is shared by every neon sign in the city (no material duplication).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

instance uniform vec4 neon_color : source_color = vec4(1.0, 0.165, 0.541, 1.0); // #FF2A8A magenta
instance uniform float neon_energy = 6.0;   // hero 8-12, normal 4-6, background 2-3 (see DOSSIER palette)
instance uniform float neon_seed = 0.0;     // any number, unique per sign
instance uniform float faulty = 0.0;        // 0 healthy, 1 broken (frequent stutter)
uniform float core_whiten : hint_range(0.0, 1.0) = 0.3;
uniform float dropout_rate : hint_range(0.0, 0.2) = 0.015;   // share of 120 ms slots that are off (healthy)
uniform bool is_flat_strip = false;          // LED strips: no cylinder core

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float neon_flicker(float t, float s, float broken) {
	float slot = floor(t * 8.3 + s * 5.0);                     // ~120 ms slots
	float rate = mix(dropout_rate, 0.22, broken);
	float off = step(hash11(slot * 1.37 + s * 91.7), rate);
	float stutter = step(0.5, hash11(floor(t * 31.0) + s)) * broken * off; // fast buzz while failing
	float hum = 0.97 + 0.03 * sin(t * 37.0 + s * 11.0) * sin(t * 23.0 + s);
	return mix(hum, 0.06 + 0.5 * stutter, off);
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = is_flat_strip ? 0.5 : pow(ndv, 3.0);
	vec3 c = neon_color.rgb;
	vec3 e = mix(c, vec3(1.0), core * core_whiten);             // tube centre reads white-hot, edges saturated
	float fl = neon_flicker(TIME, neon_seed, faulty);
	ALBEDO = c * 0.08;                                           // unlit glass tube is dark tinted
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
	EMISSION = e * neon_energy * fl;
}
