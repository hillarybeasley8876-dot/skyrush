shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Analytic ground ring for the 闪充 charge flash: a thin ring with tick marks and a scrolling
// energy pulse, drawn in a shader instead of a stretched texture (no blur, no pixelation).

uniform vec3 tint : source_color = vec3(0.098, 0.902, 1.0);
uniform float energy : hint_range(0.0, 40.0) = 5.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.005, 0.3) = 0.05;
uniform float tick_count : hint_range(0.0, 32.0) = 12.0;


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float radius = mix(0.18, 0.96, sqrt(progress));
	float ring = smoothstep(thickness, 0.0, abs(d - radius));
	float angle = atan(p.y, p.x);
	float ticks = smoothstep(0.45, 0.95, abs(sin(angle * tick_count)));
	float scroll = 0.55 + 0.45 * sin(angle * 6.0 - TIME * 7.0);
	float a = ring * (0.55 + 0.45 * ticks) * scroll;
	a *= smoothstep(1.0, 0.92, d);
	ALBEDO = tint * energy * a;
	ALPHA = a;
}
