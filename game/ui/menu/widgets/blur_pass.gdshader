shader_type canvas_item;
render_mode blend_mix, unshaded;

// One pass of a separable gaussian blur.
//
// The texture is sampled along `direction` (a horizontal and a vertical pass together make the
// full blur). `texel_size` is the size of one texel of the source, so the radius is in pixels.

uniform vec2 texel_size = vec2(1.0, 1.0);
uniform vec2 direction = vec2(1.0, 0.0);
uniform float radius : hint_range(1.0, 64.0) = 14.0;
uniform float sigma : hint_range(0.5, 32.0) = 5.0;
// The energy of the blur: a wider kernel spreads the same ink thinner, so it is boosted.
uniform float gain : hint_range(0.1, 8.0) = 2.0;

void fragment() {
	vec4 sum = vec4(0.0);
	float total = 0.0;
	float two_sigma_sq = 2.0 * sigma * sigma;
	for (int i = -32; i <= 32; i++) {
		float x = float(i);
		if (abs(x) > radius) {
			continue;
		}
		float weight = exp(-x * x / two_sigma_sq);
		vec4 sample = texture(TEXTURE, UV + direction * x * texel_size);
		sum += sample * weight;
		total += weight;
	}
	COLOR = sum / max(total, 0.0001) * gain;
}
