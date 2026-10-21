shader_type canvas_item;
render_mode blend_mix, unshaded;

// SKYRUSH glass panel (the menu's panels, the menu rows, the pause and results screens).
// A chamfered dark plate over the blurred scene: the backdrop is sampled from the screen
// texture with a mip LOD, tinted with the panel colour, and finished with a film grain,
// 2 px scanlines, a top highlight, a cyan edge and corner brackets.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// The tint of the plate; its alpha is how much of the blurred scene shows through.
uniform vec4 tint : source_color = vec4(0.031, 0.047, 0.106, 0.70);
uniform vec4 edge_color : source_color = vec4(0.098, 0.898, 1.0, 0.55);
uniform vec4 bracket_color : source_color = vec4(0.098, 0.898, 1.0, 0.90);
uniform vec4 highlight_color : source_color = vec4(0.949, 0.965, 1.0, 0.25);
uniform vec2 panel_size = vec2(64.0, 64.0);
uniform float cut_px : hint_range(0.0, 40.0) = 14.0;
uniform float edge_px : hint_range(0.0, 4.0) = 1.0;
uniform float bracket_len : hint_range(0.0, 40.0) = 10.0;
uniform float bracket_w : hint_range(0.0, 6.0) = 2.0;
uniform float grain : hint_range(0.0, 0.2) = 0.03;
uniform float scan_alpha : hint_range(0.0, 0.2) = 0.04;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.0;
uniform float blur_amount : hint_range(0.0, 1.0) = 1.0;
uniform float header_h : hint_range(0.0, 60.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;


float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	vec2 size = panel_size;
	vec2 px = UV * size;
	float c = min(cut_px, min(size.x, size.y) * 0.5);

	// The shape: a rectangle with the two top corners chamfered (the HUD panel).
	float d = min(min(px.x, size.x - px.x), min(px.y, size.y - px.y));
	d = min(d, min(px.x + px.y - c, (size.x - px.x) + px.y - c));
	float mask = smoothstep(-0.75, 0.75, d);

	// The backdrop: the blurred scene under the plate, tinted (30 % of the scene shows through).
	vec3 screen = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	vec3 glass = mix(screen, tint.rgb, tint.a);
	glass = mix(tint.rgb, glass, blur_amount);
	// The top of the plate catches a little more light.
	float vertical = clamp(1.0 - px.y / max(size.y, 1.0), 0.0, 1.0);
	glass = mix(glass, glass * 1.15 + vec3(0.015, 0.018, 0.028), vertical * 0.55);
	// A 1 px dark inner line at the bottom of the plate.
	float bottom = 1.0 - smoothstep(0.0, 1.5, abs(px.y - (size.y - 1.0)));
	glass = mix(glass, glass * 0.45, bottom * 0.8);

	// 3 % animated film grain and 2 px scanlines at 4 %.
	float noise = hash(px + vec2(TIME * 61.0, TIME * 37.0)) - 0.5;
	glass += noise * grain;
	float scan = 0.5 + 0.5 * sin(px.y * PI);
	glass += (scan - 0.5) * scan_alpha;

	// The header strip (the panel's English label band, like the HUD's).
	if (header_h > 0.5) {
		float band = 1.0 - smoothstep(header_h - 0.5, header_h + 0.5, px.y);
		glass = mix(glass, tint.rgb * 1.7, band * 0.45);
	}

	// The 1 px top highlight between the two chamfers.
	float along_top = step(c, px.x) * step(px.x, size.x - c);
	float highlight = (1.0 - smoothstep(0.0, 1.5, abs(px.y - 1.5))) * along_top;
	glass = mix(glass, highlight_color.rgb, highlight * highlight_color.a);

	// The cyan edge and the corner brackets on the two square (bottom) corners.
	float outline = 0.0;
	if (edge_px > 0.0) {
		outline = 1.0 - smoothstep(edge_px * 0.5 - 0.75, edge_px * 0.5 + 0.75, abs(d));
	}
	glass = mix(glass, edge_color.rgb, outline * edge_color.a);

	float bl = min(sd_segment(px, vec2(0.0, size.y), vec2(bracket_len, size.y)),
			sd_segment(px, vec2(0.0, size.y), vec2(0.0, size.y - bracket_len)));
	float br = min(sd_segment(px, vec2(size.x, size.y), vec2(size.x - bracket_len, size.y)),
			sd_segment(px, vec2(size.x, size.y), vec2(size.x, size.y - bracket_len)));
	float bracket = 1.0 - smoothstep(bracket_w * 0.5 - 0.5, bracket_w * 0.5 + 0.5, min(bl, br));
	glass = mix(glass, bracket_color.rgb, bracket * bracket_color.a * mask);

	COLOR = vec4(glass, mask * alpha);
}
