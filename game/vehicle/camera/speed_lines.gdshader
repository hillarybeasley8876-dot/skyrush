shader_type canvas_item;
render_mode blend_mix, unshaded;

// Screen-space speed lines: thin radial streaks that stream outwards from the motion
// vanishing point. Cyan-white and subtle (dossier: start 160 km/h, full at 280 km/h).
// The line core is measured in PIXELS, so the streaks stay thin at every radius, and every
// dash is hashed per (lane, cell) so the streaks never repeat on the same rails.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 streak_color : source_color = vec4(0.847, 0.957, 1.0, 1.0);
uniform float lanes : hint_range(40.0, 200.0) = 110.0;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.35;
uniform float line_width_px : hint_range(0.5, 6.0) = 2.0;
uniform float dash_ratio : hint_range(0.01, 0.2) = 0.09;
uniform float scroll_phase : hint_range(0.0, 1000000.0) = 0.0; // the accumulated scroll
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.24;
uniform float sky_factor : hint_range(0.0, 1.0) = 0.5;
uniform vec2 focus = vec2(0.5, 0.55);
uniform vec2 car_pos = vec2(0.5, 0.75);
uniform float car_radius : hint_range(0.0, 1.0) = 0.35;
uniform float car_feather : hint_range(0.0, 1.0) = 0.12;
uniform float horizon_y : hint_range(0.0, 1.0) = 0.5;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	// Aspect-corrected pixel space around the vanishing point (isotropic, in screen pixels).
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 dp = (UV - focus) * vec2(aspect, 1.0) / SCREEN_PIXEL_SIZE.y;
	float r_px = length(dp);
	if (r_px < 1.0) {
		discard;
	}
	float half_diag_px = 0.5 * length(vec2(aspect, 1.0)) / SCREEN_PIXEL_SIZE.y;

	// Nothing converges at the focus: the streaks fade in with the radius.
	float radius_fade = smoothstep(0.18, 0.32, r_px * SCREEN_PIXEL_SIZE.y);

	// Every dash is hashed per (lane, cell): the streaks never repeat on the same rails.
	float dash_len = max(dash_ratio * half_diag_px, 1.0);
	float cell = floor((r_px - scroll_phase) / dash_len);
	float phase = fract((r_px - scroll_phase) / dash_len);
	vec2 h = vec2(floor((atan(dp.y, dp.x) + PI) / (TAU / lanes)), cell);
	float lit_h = hash21(h);
	float bright = 0.5 + 0.5 * hash21(h + 17.0);
	float length_h = 0.5 + 0.5 * hash21(h + 31.0);
	float angle_jitter = (hash21(h + 47.0) - 0.5) * 0.7 * (TAU / lanes);

	// The ray: the lane, plus a per-cell jitter of up to a third of a lane.
	float lane_angle = TAU / lanes;
	float ang_off = (fract((atan(dp.y, dp.x) + PI) / lane_angle) - 0.5) * lane_angle + angle_jitter;
	float pixel_angle = 0.5 / max(r_px, 1.0);
	float half_width = (line_width_px * 0.5) / max(r_px, 1.0);
	float line = 1.0 - smoothstep(half_width - pixel_angle, half_width + pixel_angle, abs(ang_off));

	// The dash: a soft two pixel head and a tail that fades behind it. It fills at most
	// 45 % of the cell, so the streaks are dashes and not rails.
	float head = 0.45 * length_h;
	float dash = smoothstep(0.0, head, phase) * (1.0 - smoothstep(head - 2.0 / dash_len, head, phase));

	// Nothing over the car.
	vec2 to_car = (UV - car_pos) * vec2(aspect, 1.0);
	float car_mask = smoothstep(car_radius, car_radius + car_feather, length(to_car));

	// Half strength above the horizon line, with a soft edge.
	float sky = mix(sky_factor, 1.0, smoothstep(horizon_y - 0.03, horizon_y + 0.03, UV.y));

	// The speed ramp (160 -> 280 km/h) scales how many lanes are lit, not their alpha
	// (dossier, speed-feel effects: the amount ratio ramps with the speed).
	float lit = step(1.0 - lit_ratio * intensity, lit_h);
	float alpha = lit * line * dash * car_mask * sky * radius_fade * bright * alpha_scale;
	COLOR = vec4(streak_color.rgb, alpha * streak_color.a);
}
