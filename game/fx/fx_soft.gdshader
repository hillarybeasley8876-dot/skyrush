shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

// Soft, lit particle material for game/fx/ (tyre smoke, spray mist, vapour, wreck smoke).
// - the puff atlas is a 4x4 flipbook: the life fraction of the particle picks the frame and
//   two consecutive frames are cross-faded, so a puff never pops (lead F-INT4)
// - the life fraction travels in the blue channel of the colour ramp (the initial ramp pins
//   its blue to 1.0), so the ramp can still carry the fade in its alpha
// - the per particle rotation comes from the particle transform itself (the angular velocity
//   of the process material), the per particle random from the red channel
// - soft particles: the quad fades where it cuts into solid geometry (road, kerbs)
// - the tint is a uniform, so the colour of an effect can be changed at runtime
// - COLOR.a carries the fade of the effect

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform float soft_distance : hint_range(0.0, 8.0) = 0.5;
uniform float depth_fade : hint_range(0.0, 1.0) = 1.0;
uniform float ambient_lift : hint_range(0.0, 1.0) = 0.14;
uniform vec3 tint : source_color = vec3(0.604, 0.639, 0.706);
uniform float alpha_scale : hint_range(0.0, 4.0) = 1.0;
uniform bool billboard = true;
uniform bool use_atlas = true;
uniform float atlas_cells : hint_range(1.0, 8.0) = 4.0;
uniform float frames : hint_range(1.0, 32.0) = 16.0;
// Half a texel of the cell, so the linear filter does not bleed the neighbour cell in.
uniform float atlas_inset : hint_range(0.0, 0.05) = 0.002;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.3;
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
// An extra glow that fades out over the first part of the life (the fire under a smoke column).
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_until : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy : hint_range(0.0, 4.0) = 0.0;

varying vec2 v_uv0;
varying vec2 v_uv1;
varying float v_blend;
varying float v_seed;
varying float v_life;
varying vec3 v_right;
varying vec3 v_up;


vec2 _cell_uv(float index, vec2 uv) {
	float cells = atlas_cells;
	vec2 cell = vec2(mod(index, cells), floor(index / cells));
	vec2 inner = mix(vec2(atlas_inset), vec2(1.0 - atlas_inset), uv);
	return (cell + inner) / cells;
}


void vertex() {
	// The red channel of the initial ramp is the per particle random, the blue channel of the
	// life ramp is the life fraction.
	v_seed = COLOR.r;
	v_life = COLOR.b;
	// The particle transform carries the spin of the particle (the angular velocity of the
	// process material): the billboard is rolled by it, so every puff has its own angle.
	float roll = atan(MODEL_MATRIX[1].x, MODEL_MATRIX[0].x);
	if (billboard) {
		float cr = cos(roll);
		float sr = sin(roll);
		vec3 right = INV_VIEW_MATRIX[0].xyz * cr + INV_VIEW_MATRIX[1].xyz * sr;
		vec3 up = -INV_VIEW_MATRIX[0].xyz * sr + INV_VIEW_MATRIX[1].xyz * cr;
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		// The third column is the face of the quad: it points at the camera, so the puff is
		// lit from the side the viewer is on.
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sx, 0.0), vec4(up * sy, 0.0),
				vec4(INV_VIEW_MATRIX[2].xyz, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	v_right = normalize(MODELVIEW_MATRIX[0].xyz);
	v_up = normalize(MODELVIEW_MATRIX[1].xyz);
	vec2 uv = UV;
	if (use_atlas) {
		float f = clamp(v_life, 0.0, 0.999) * frames;
		float fl = floor(f);
		v_blend = fract(f);
		float cells = atlas_cells * atlas_cells;
		v_uv0 = _cell_uv(mod(fl, cells), uv);
		v_uv1 = _cell_uv(mod(fl + 1.0, cells), uv);
	} else {
		v_blend = 0.0;
		v_uv0 = uv;
		v_uv1 = uv;
	}
}


void fragment() {
	// The flipbook is sampled with the mipmaps: the empty gutter around every cell keeps the
	// cells from bleeding into each other.
	vec4 tex = mix(texture(albedo_tex, v_uv0), texture(albedo_tex, v_uv1), v_blend);
	vec3 base = tex.rgb * tint;

	// Fake volume: a gentle bump from the baked density, bent towards the viewer so the puff
	// is lit from every side (wrap diffuse) and never shows a hard crescent.
	vec3 nmap = mix(texture(normal_tex, v_uv0).rgb, texture(normal_tex, v_uv1).rgb, v_blend) * 2.0 - 1.0;
	vec3 geo = normalize(NORMAL);
	vec3 n = normalize(geo + (v_right * nmap.x + v_up * nmap.y) * normal_strength);
	NORMAL = normalize(mix(n, geo, wrap));

	// Soft-particle depth test: scene depth (opaque) vs this fragment's view depth.
	float soft = 1.0;
	if (depth_fade > 0.0) {
		float d = texture(depth_tex, SCREEN_UV).r;
		if (d > 0.0) {
			vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
			view.xyz /= max(view.w, 0.00001);
			float scene_depth = -view.z;
			float frag_depth = -VERTEX.z;
			soft = clamp((scene_depth - frag_depth) / max(soft_distance, 0.001), 0.0, 1.0);
		}
	}

	float glow = 0.0;
	if (glow_until > 0.0) {
		glow = glow_energy * (1.0 - clamp(v_life / glow_until, 0.0, 1.0));
	}

	ALBEDO = base;
	ALPHA = tex.a * COLOR.a * v_seed * soft * alpha_scale;
	EMISSION = base * (ambient_lift + glow_color * glow);
}
