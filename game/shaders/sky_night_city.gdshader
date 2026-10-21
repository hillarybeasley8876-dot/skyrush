// SKYRUSH - night-city sky. Visible sky = stylised gradient + city-lit cloud deck.
// Reflections/ambient (radiance cubemap pass) = real HDRI (Poly Haven "shanghai_bund").
// Ported from ref/art/lookdev/shaders/sky_night_city.gdshader [V]; the cloud deck thickens and darkens
// when it rains (global skyrush_rain).
// Use: Environment.background_mode = BG_SKY, Sky.sky_material = ShaderMaterial(this).
// Sky.process_mode = PROCESS_MODE_QUALITY (radiance only rebuilds when uniforms change).
shader_type sky;
render_mode use_debanding;

global uniform float skyrush_rain;   // 0 dry .. 1 raining, set by the weather controller

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
uniform float radiance_energy : hint_range(0.0, 4.0) = 0.18;
// The rain sky: vignaioli_night (an overcast, wet night). The radiance cross-fades to it while it
// rains, so the puddles stop mirroring a clear sky.
uniform sampler2D rain_hdri : filter_linear, hint_default_black;
uniform float rain_hdri_energy : hint_range(0.0, 4.0) = 0.18;
uniform float rain_mix : hint_range(0.0, 1.0) = 0.0;  // 0 dry, 1 raining (set by the weather controller)
// The HDRI is a warm night city, so the reflection that misses a probe is tinted cool and
// desaturated: it must never read as gold foil (DOSSIER 1.4 don't #6).
uniform vec3 radiance_tint : source_color = vec3(0.494, 0.525, 0.659); // #7E86A8
uniform float radiance_saturation : hint_range(0.0, 2.0) = 0.35;
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
		vec3 tint = radiance_tint / max(dot(radiance_tint, vec3(0.2126, 0.7152, 0.0722)), 0.001);
		vec3 dry = texture(radiance_hdri, uv).rgb * radiance_energy;
		vec3 wet = texture(rain_hdri, uv).rgb * rain_hdri_energy;
		vec3 hdri = mix(dry, wet, rain_mix) * tint;
		float luma = dot(hdri, vec3(0.2126, 0.7152, 0.0722));
		COLOR = mix(vec3(luma), hdri, radiance_saturation);
	} else {
		float y = EYEDIR.y;
		vec3 col = gradient(y);
		if (y > 0.0) {
			vec2 p = EYEDIR.xz / (y + 0.08) * cloud_scale + TIME * cloud_wind;
			float n = texture(cloud_noise, p).r * 0.65 + texture(cloud_noise, p * 2.7 + 0.31).r * 0.35;
			float cover = clamp(cloud_coverage + skyrush_rain * 0.30, 0.0, 1.0);
			float c = smoothstep(1.0 - cover, 1.0 - cover + cloud_softness, n);
			vec3 cloud = mix(cloud_lit_color, cloud_base_color, smoothstep(0.0, 0.5, y));
			cloud *= mix(1.0, 0.72, skyrush_rain);  // a rain sky is a heavier, darker deck
			col = mix(col, cloud, c * smoothstep(0.0, 0.06, y));
		} else {
			col = horizon_color * 0.35; // below horizon: dark haze (city geometry covers it)
		}
		COLOR = col * sky_energy;
	}
}
