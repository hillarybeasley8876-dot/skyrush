// SKYRUSH - night-city sky. Visible sky = stylised gradient + city-lit cloud deck.
// Reflections/ambient (radiance cubemap pass) = real HDRI (Poly Haven "shanghai_bund").
// Use: Environment.background_mode = BG_SKY, Sky.sky_material = ShaderMaterial(this).
// Sky.process_mode = PROCESS_MODE_QUALITY (radiance only rebuilds when uniforms change).
shader_type sky;
render_mode use_debanding;

// --- visible gradient (all colours are sRGB hex in the inspector) ---
uniform vec3 zenith_color : source_color = vec3(0.027, 0.039, 0.086);   // #070A16
uniform vec3 mid_color : source_color = vec3(0.071, 0.090, 0.200);      // #121733
uniform vec3 horizon_color : source_color = vec3(0.231, 0.196, 0.278);  // #3B3247
uniform vec3 city_glow_color : source_color = vec3(0.353, 0.251, 0.282); // #5A4048
uniform float city_glow_height : hint_range(0.01, 0.4) = 0.10; // fraction of the dome
uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;

// --- cloud deck lit from below by sodium/LED city light ---
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable; // seamless NoiseTexture2D 512px
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.18;
uniform vec3 cloud_base_color : source_color = vec3(0.110, 0.102, 0.141); // #1C1A24 overhead
uniform vec3 cloud_lit_color : source_color = vec3(0.290, 0.227, 0.235);  // #4A3A3C near horizon
uniform float cloud_scale = 0.35;
uniform vec2 cloud_wind = vec2(0.004, 0.0015);

// --- reflections / ambient ---
uniform sampler2D radiance_hdri : filter_linear, hint_default_black; // shanghai_bund_2k.hdr (no source_color!)
uniform float radiance_energy : hint_range(0.0, 4.0) = 0.25; // > 0.3 turns wet-road puddles into gold foil
uniform float radiance_rotation_deg = 0.0; // rotate so Lujiazui sits to the east of the Bund

vec3 gradient(float y) {
	float up = clamp(y, 0.0, 1.0);
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.35, up));
	col = mix(col, zenith_color, smoothstep(0.35, 1.0, up));
	float glow = exp(-max(y, 0.0) / city_glow_height);
	return col + city_glow_color * glow;
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		vec2 uv = SKY_COORDS;
		uv.x = fract(uv.x + radiance_rotation_deg / 360.0);
		COLOR = texture(radiance_hdri, uv).rgb * radiance_energy;
	} else {
		float y = EYEDIR.y;
		vec3 col = gradient(y);
		if (y > 0.0) {
			vec2 p = EYEDIR.xz / (y + 0.08) * cloud_scale + TIME * cloud_wind;
			float n = texture(cloud_noise, p).r * 0.65 + texture(cloud_noise, p * 2.7 + 0.31).r * 0.35;
			float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, n);
			vec3 cloud = mix(cloud_lit_color, cloud_base_color, smoothstep(0.0, 0.5, y));
			col = mix(col, cloud, c * smoothstep(0.0, 0.06, y));
		} else {
			col = horizon_color * 0.35; // below horizon: dark haze (city geometry covers it)
		}
		COLOR = col * sky_energy;
	}
}
