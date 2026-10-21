shader_type spatial;
// Sandbox ground: dark tiles with 1 m minor / 10 m major world-space grid lines (scale + speed cues).

uniform vec3 base_color : source_color = vec3(0.07, 0.075, 0.09);
uniform vec3 minor_color : source_color = vec3(0.16, 0.17, 0.2);
uniform vec3 major_color : source_color = vec3(0.1, 0.45, 0.55);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width), vec2(width) + fw, g);
	return max(l.x, l.y);
}

void fragment() {
	float minor = grid_line(world_pos.xz, 1.0, 0.02);
	float major = grid_line(world_pos.xz, 10.0, 0.06);
	vec3 col = mix(base_color, minor_color, minor * 0.6);
	col = mix(col, major_color, major);
	ALBEDO = col;
	ROUGHNESS = 0.75;
	EMISSION = major_color * major * 0.25;
}
