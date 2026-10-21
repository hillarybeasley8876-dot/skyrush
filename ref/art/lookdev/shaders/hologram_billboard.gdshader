// SKYRUSH - holographic / LED billboard (additive, unshaded). For giant LED screens on towers use
// mode = 0 (LED pixel grid, opaque-looking), for floating holograms use mode = 1 (scanlines, glitch, transparent).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D content : source_color, filter_linear_mipmap, repeat_disable; // ad artwork (PNG, sRGB)
uniform int mode : hint_range(0, 1) = 1;
uniform float energy : hint_range(0.0, 12.0) = 3.5;        // hologram 3-5; LED screen 2-3 (they are big!)
uniform vec3 tint : source_color = vec3(0.553, 0.918, 1.0);  // #8DEAFF cyan hologram tint (mode 1)
uniform float scan_lines = 220.0;                           // lines over the full height
uniform float scan_speed = 0.6;
uniform float chroma_px = 2.0;                              // RGB split in texels
uniform float glitch_rate : hint_range(0.0, 1.0) = 0.08;
uniform vec2 led_grid = vec2(320.0, 180.0);                 // LED screen pixel count (mode 0)
uniform float edge_fade : hint_range(0.0, 0.2) = 0.04;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float g_slot = floor(t * 12.0);
	float glitching = step(1.0 - glitch_rate, hash11(g_slot));
	float band = smoothstep(0.06, 0.0, abs(uv.y - hash11(g_slot + 3.0)));
	uv.x += (hash11(g_slot + 7.0) - 0.5) * 0.06 * band * glitching;

	vec3 col;
	if (mode == 0) {
		vec2 cell = fract(uv * led_grid);
		vec2 dotmask = smoothstep(0.0, 0.25, cell) * smoothstep(1.0, 0.75, cell);
		col = texture(content, (floor(uv * led_grid) + 0.5) / led_grid).rgb * (0.35 + 0.65 * dotmask.x * dotmask.y);
	} else {
		vec2 px = vec2(chroma_px) / vec2(textureSize(content, 0));
		col.r = texture(content, uv + vec2(px.x, 0.0)).r;
		col.g = texture(content, uv).g;
		col.b = texture(content, uv - vec2(px.x, 0.0)).b;
		col *= tint;
		float scan = 0.72 + 0.28 * sin((uv.y * scan_lines - t * scan_speed * scan_lines * 0.05) * 6.2831853);
		col *= scan;
	}
	float flick = 0.9 + 0.1 * hash11(floor(t * 24.0));
	vec2 e = smoothstep(vec2(0.0), vec2(edge_fade), uv) * smoothstep(vec2(1.0), vec2(1.0 - edge_fade), uv);
	ALBEDO = col * energy * flick * (1.0 + glitching * band);
	ALPHA = e.x * e.y;
}
