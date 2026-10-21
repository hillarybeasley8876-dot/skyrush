// SKYRUSH - the hologram curtain of a race gate.
// Additive and unshaded: 120 scanlines over the world height, a 2 px RGB split at the edges
// (the three channels are sampled at +-chroma_px * fwidth(UV.x)), 12 Hz glitch slots (8 % of
// them), a +-10 % jitter at 24 Hz and a rim that keeps the middle of the curtain transparent
// (ART.md 5: holograms are additive, scanlined and never fully opaque).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec3 tint : source_color = vec3(0.098, 0.902, 1.0);
instance uniform float energy : hint_range(0.0, 8.0) = 3.5;
uniform float world_height = 6.5;   // m: the scanlines are counted in world height
uniform float scan_lines = 120.0;   // the scanlines over the world height
uniform float chroma_px = 2.0;      // the RGB split at the edges, in pixels
uniform float glitch_rate = 0.08;   // the share of the slots that glitch
uniform float jitter = 0.10;        // the horizontal jitter of a glitching slot
uniform float jitter_hz = 24.0;     // the jitter slots per second
uniform float max_alpha = 0.35;     // the alpha in the middle of the curtain
uniform float middle = 0.35;        // the light of the middle of the curtain (the rim is 1.0)

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// The light of the curtain at one horizontal position: the scanlines and the rim.
float shade(float x, float height, float t) {
	float lines = 0.72 + 0.28 * sin(height * (scan_lines / world_height) * 6.28318 - t * 2.0);
	float rim = pow(abs(x - 0.5) * 2.0, 3.0);
	return lines * mix(middle, 1.0, rim);
}

void fragment() {
	float t = TIME;
	float height = UV.y * world_height;
	// The glitch slots: 12 per second, 8 % of them jump.
	float slot = floor(t * 12.0);
	float glitch = step(1.0 - glitch_rate, hash11(slot));
	float jitter_slot = floor(t * jitter_hz);
	float jump = (hash11(jitter_slot) - 0.5) * 2.0 * jitter * glitch;
	float x = clamp(UV.x + jump, 0.0, 1.0);
	// The RGB split: the three channels are sampled a couple of pixels apart, so the edges
	// of the curtain show a real colour fringe and not a brighter copy of themselves.
	float dx = chroma_px * max(fwidth(UV.x), 0.0001);
	vec3 col = vec3(
		shade(clamp(x + dx, 0.0, 1.0), height, t),
		shade(x, height, t),
		shade(clamp(x - dx, 0.0, 1.0), height, t)
	);
	col *= tint * energy;
	float rim = pow(abs(x - 0.5) * 2.0, 3.0);
	float alpha = mix(max_alpha, 0.9, rim);
	// The additive blend scales the light with the alpha, so the middle stays transparent.
	ALBEDO = col * 0.3;
	ALPHA = alpha;
}
