# SKYRUSH art reference images (index)

All files are JPEG, longest side <= 1280 px, re-encoded locally. Measured numbers come from
`ref/art/lookdev/tools/screenshot_stats.py` (display luminance percentiles, saturated-bright % and
dominant saturated hues). Use these for mood/value/colour only. **Never trace, never ship, never use as textures.**

## A. Real Shanghai at night (Wikimedia Commons, free licences - credit if ever shown publicly)

| File | What to learn from it | Licence / author / source |
|---|---|---|
| sh01_bund_gold_facades.jpg | Bund: warm uplit granite (measured gold #C2904D), Peace Hotel green pyramid roof lit teal-green, near-black sky #1D2027, lamps hidden ("see light, not fixtures") | CC0, DvTor8303, 2026-04-17, https://commons.wikimedia.org/wiki/File:Shanghai_Bund_at_night_20260417_(4).jpg |
| sh02_bund_bluehour_aerial.jpg | Flight-mode view: golden Bund ribbon vs. dark river, blue-hour haze #1F4963, sodium specks #BA5D27 | CC BY-SA 4.0, Dllu, https://commons.wikimedia.org/wiki/File:Blue_hour_view_of_the_Bund_from_the_Shanghai_World_Financial_Center_dllu.jpg |
| sh03_lujiazui_led_ads.jpg | Lujiazui: dark tower masses, LED ads only on a few facades (blue #0649D7, red #C62B42) = value hierarchy | CC BY-SA 3.0, Daniel Case, https://commons.wikimedia.org/wiki/File:Nighttime_Lujiazui_skyline_with_ads_on_buildings.jpg |
| sh04_pudong_aerial_sodium_grid.jpg | From the air the city is black with an orange road filigree (#BA882F); this is the flight-section look | CC BY-SA 3.0, WFan, https://commons.wikimedia.org/wiki/File:201909_%E4%B8%8A%E6%B5%B7%E6%B5%A6%E4%B8%9C%E7%A9%BA%E4%B8%AD%E5%A4%9C%E6%99%AF.jpg |
| sh05_yanan_elevated_blue_soffit.jpg | THE Shanghai signature: elevated-road underside washed saturated blue (#2357F3, 85 % of saturated pixels) | CC BY-SA 4.0, Windmemories, https://commons.wikimedia.org/wiki/File:20240120_Night_view_of_West_Yan%27an_Road_near_Huashan_Road.jpg |
| sh06_ring_road_light_trails.jpg | Expressway: sodium lamps (#CD9845), tail-light trails (#B23719), green overhead guide signs | CC BY 2.0, an.yonghua, https://commons.wikimedia.org/wiki/File:Middle_Ring_Road_Shanghai_Gudai_Rd.jpg |
| sh07_nanjing_rd_neon_rain.jpg | Nanjing Rd neon cluster in rain: red/orange/yellow dominated (#C3431B #CE1F39 #DEAB20), vertical CJK signs | CC BY 2.0, Jakob Montrasio, https://commons.wikimedia.org/wiki/File:Advertising_and_Rain_-_Flickr_-_@yakobusan_Jakob_Montrasio.jpg |
| sh08_nanjing_east_night.jpg | Historic department stores: gold-lit facades + purple/blue dome accents + white LED line facades | CC BY 4.0, Chainwit., https://commons.wikimedia.org/wiki/File:2024-Apr_Shanghai_East_Nanjing_Road_at_night_01.jpg |
| sh09_nine_dragon_pillar_day.jpg | Nine-Dragon Pillar (Yan'an x North-South elevated): structure / proportions (daytime) | CC BY-SA 4.0, 中日韩越的汉字, https://commons.wikimedia.org/wiki/File:Y%C3%A1n%27%C4%81n_G%C4%81oji%C3%A0l%C3%B9_Ji%C7%94l%C3%B3ngzh%C3%B9.jpg |
| sh10_century_ave_dusk.jpg | Lujiazui towers at dusk + light trails; purple-pink dusk sky gradient | CC BY-SA 4.0, Morio, https://commons.wikimedia.org/wiki/File:Century_Avenue_night_2016_January.jpg |
| sh11_multilevel_interchange_day.jpg | Stacked interchange ramps: deck thickness, pier rhythm, barrier profile (daytime) | Public domain, https://commons.wikimedia.org/wiki/File:Multi-level_Bridge_in_Shanghai.jpg |
| sh12_yanan_east_ramp_dusk.jpg | East end of Yan'an elevated near the Bund: landscaped ramp walls, lane paint, dusk | CC BY-SA 4.0, N509FZ, https://commons.wikimedia.org/wiki/File:East_start_of_Yan%27an_Elevated_Rd_(20250609195843).jpg |

## B. Genre mood (copyrighted - internal study only, never in builds, trailers or store pages)

| File | What to learn | Source |
|---|---|---|
| cp01_cp2077_neon_street.jpg | Neon street: warm practicals + magenta/teal accents, P50 0.16 | Steam store screenshot, Cyberpunk 2077 (CD PROJEKT RED), app 1091500 |
| cp02_cp2077_night_street.jpg | Teal/amber split, signage hierarchy | Steam app 1091500 |
| cp03_cp2077_neon_interior.jpg | Saturated blue-violet-magenta interior; too much for our streets (SAT 10.6 %) | Steam app 1091500 |
| cp04_nfs2015_wet_night.jpg | Wet asphalt, bokeh street lights, lit bridge cables, very low saturation | Steam store screenshot, Need for Speed (2015, EA), app 1262540 |
| cp05_nfsheat_police_neon.jpg | Police chase + purple/blue neon, red/blue light bar reflections | Steam store screenshot, NFS Heat (EA), app 1222680 |
| cp06_nfsheat_motel_wet.jpg | Wet road mirroring neon signs (the reflection density we want) | Steam app 1222680 |
| cp07_ruiner_red_topdown.jpg | Monochrome red set-piece with CJK floor graphics (use for police-heat moments only) | Steam store screenshot, RUINER (Reikon Games), app 464060 |
| cp08_br2049_smog_city.jpg | Blade Runner 2049: teal smog, sparse lights, huge scale cues | Film still via vfxblog.com (Warner Bros./Alcon) |
| cp09_br2049_orange_haze.jpg | Monochrome orange haze (sandstorm) - reference for a "smog alert" weather variant | Film still via film-grab.com |
| cp10_gits1995_city_aerial.jpg | Ghost in the Shell (1995): water-city aerial, cyan-teal dusk, lit street grid | Film still via theverge.com (Production I.G) |
| cp11_gits1995_neon_street.jpg | Dense CJK street signage, red-pink neon | Film still via theverge.com |

## C. Project-made

| File | What it is |
|---|---|
| lookdev_baseline_godot472.jpg | Render of `ref/art/lookdev` (Godot 4.7.2 Forward+, Metal, M1 Max) with the DOSSIER recipe. Passes screenshot_stats default targets (P50 0.142, SAT 4.2 %). Not a beauty shot: grey boxes, no props. |
| gb5768_3_2009_fig44_arrows_6m.jpg | GB 5768.3-2009 figure 44 (page 47): guide-arrow dimensions for 40-100 km/h roads, cm. Source PDF: https://upload.wikimedia.org/wikipedia/commons/6/6c/China_GB_5768.3-2009.pdf |
