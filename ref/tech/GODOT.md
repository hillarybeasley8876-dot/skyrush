# GODOT.md — Godot 4.7.2 tech validation for SKYRUSH: NEON SHANGHAI (飞驰申城)

Measured on THIS machine on 2026-10-19 by running real Godot/Blender processes (scratch project:
`/Users/minimax/m/skyrush/ref/tech/probe/`). Everything not marked (est.) or (unverified) was
executed and observed. Written for the implementer (MiniMax M3.1): follow the numbers literally.

## 0. TL;DR — the 15 rules

1. Renderer: **Forward+ on native Metal 4.0** (`rendering_device/driver.macos="metal"`). Not Vulkan/MoltenVK.
2. Physics: write `physics/3d/physics_engine="Jolt Physics"` **explicitly**. Without the key, 4.7.2 uses
   `DEFAULT` = **GodotPhysics3D** (verified by fingerprint, §6.1). GodotPhysics3D is 7x slower with debris.
3. Physics tick **120 Hz**; `continuous_cd = true` on the player car and on every debris body.
4. Car = `RigidBody3D` + 4 **ShapeCast3D sphere** wheel probes (`snippets/raycast_wheel_car.gd`).
   Do NOT use RayCast3D probes (unstable landings, §6.3). Do not use VehicleBody3D (exists, untested here).
5. Trimesh collision is **one-sided**: set `backface_collision = true` on barrier/wall shapes.
6. Post stack (per 1080p view, M1 Max): glow 0.17 + SSAO 0.42 + SSR 1.27 + vol. fog 0.60 + SMAA 0.31
   + radial blur 0.20 ≈ **3.0 ms**. Never enable SDFGI (+2.0), VoxelGI (+2.4), SSIL (+1.0).
7. Tonemapper: **AgX** (`Environment.TONE_MAPPER_AGX` = 4) is available and used for all tests.
8. Upscaling fallback: **MetalFX Spatial** (`scaling_3d_mode=3`) at 0.67–0.77 (−1.37 ms on the heavy preset).
   MetalFX Temporal saved only 0.39 ms and FSR2 nothing (+0.03 ms) → do not use them.
9. AreaLight3D (new in 4.7) is expensive: cost follows screen coverage. Max 4 visible, `area_range <= 10`.
10. Share materials. 2,000 meshes with 1 material = 22 draw calls; with 2,000 materials = 1,738 calls and
    +1.4 ms. Per-sign colour = `instance uniform` + `set_instance_shader_parameter()` (still 22 calls).
11. MultiMesh: one MultiMeshInstance3D per ~135 m city cell + `visibility_range_end`, never one giant MMI.
12. HLOD via `visibility_parent` + per-block proxy (`visibility_range_begin = 350`): from the air the city
    drops from 1,827 to 262 objects. Assign the proxy's mesh BEFORE children reference it (§10, gotcha 11).
13. Blender → glTF (.glb) → Godot works headless; suffixes `-col`, `-colonly`, `-convcol` verified (§7).
14. Screenshots need a WINDOW (headless has no framebuffer); `--write-movie` size = project viewport size.
15. `godot --check-only` exits **0 even on parse errors** — use `snippets/check_scripts.gd` (exit code = failures).

## 1. Machine and renderer (verified)

| Item | Value | How verified |
|---|---|---|
| Model | MacBookPro18,4, macOS 27.0.1 (26A434) | `OS.get_model_name()`, `sw_vers` |
| Chip | Apple M1 Max, CPU 10 cores (8 performance + 2 efficiency) | `sysctl hw.perflevel0/1.physicalcpu` |
| GPU | M1 Max, **24 GPU cores**, Metal 4 support | `system_profiler SPDisplaysDataType` |
| Memory | 32 GB unified (34,359,738,368 B) | `sysctl hw.memsize` |
| Displays | built-in 3024x1964 @120 Hz (scale 2.0); external LS27D80xU 3840x2160 @60 Hz; Sidecar | `system_profiler`, `DisplayServer` |
| Godot | 4.7.2.stable.official.ed1daf0bf, `/opt/homebrew/bin/godot` → `/Applications/Godot.app/Contents/MacOS/Godot` | `godot --version` |
| Blender | 5.2.1 LTS (build 2026-08-25) | `Blender --version` |
| Renderer line | `Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M1 Max (Apple7)` | engine stdout |
| RenderingServer | adapter `Apple M1 Max (Apple7)`, vendor `Apple`, type 1 (integrated), API `4.0`, method `forward_plus`, driver `metal` | `RenderingServer.get_video_adapter_*()` |
| Alternatives | `driver.macos` accepts `metal,vulkan` (Vulkan = MoltenVK, not tested) | ProjectSettings hint string |
| Headless | `--headless` = dummy renderer: adapter strings empty, no images, `frame_post_draw` never fires | probe run |

Engine enums present in 4.7.2 (read from ClassDB):
- `Environment.TONE_MAPPER_*`: LINEAR 0, REINHARDT 1, FILMIC 2, ACES 3, **AGX 4**.
- `Viewport.SCALING_3D_MODE_*`: BILINEAR 0, FSR 1, FSR2 2, **METALFX_SPATIAL 3, METALFX_TEMPORAL 4**, NEAREST 5.
- `Viewport.SCREEN_SPACE_AA_*`: DISABLED 0, FXAA 1, **SMAA 2**. `Viewport.MSAA_*`: 2X 1, 4X 2, 8X 3.
- `CompositorEffect.EFFECT_CALLBACK_TYPE_*`: PRE_OPAQUE 0, POST_OPAQUE 1, POST_SKY 2, PRE_TRANSPARENT 3, POST_TRANSPARENT 4.
- New in 4.7: `AreaLight3D` (props `area_size`, `area_range`, `area_attenuation`, `area_normalize_energy`,
  `area_texture`), HDR output (`display/window/hdr/request_hdr_output`, `DisplayServer.window_request_hdr_output()`).
  Source: https://godotengine.org/releases/4.7/ (HDR output not tested here).

## 2. project.godot — verified keys

File: `snippets/project.godot.template` (every key was loaded in a scratch project and read back with
`ProjectSettings.get_setting()`; the Jolt fingerprint confirmed Jolt was active: |v| clamped to 499.6 m/s).

```ini
config_version=5
[application]
config/features=PackedStringArray("4.7", "Forward Plus")
run/max_fps=0
[display]
window/size/viewport_width=1920            ; also the --write-movie resolution
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/vsync/vsync_mode=1                  ; 0 only for benchmarks
[physics]
3d/physics_engine="Jolt Physics"           ; REQUIRED - default "DEFAULT" means GodotPhysics3D
common/physics_ticks_per_second=120
common/max_physics_steps_per_frame=8
common/physics_interpolation=true          ; smooth 120 Hz sim on 60/120 Hz displays (visual result unverified)
common/physics_jitter_fix=0.0              ; recommended 0 with interpolation (Godot docs; not re-verified)
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.macos="metal"
anti_aliasing/quality/screen_space_aa=2    ; SMAA
anti_aliasing/quality/use_taa=false
scaling_3d/mode=0                          ; fallback: 3 (MetalFX Spatial) with scaling_3d/scale=0.77
scaling_3d/scale=1.0
occlusion_culling/use_occlusion_culling=true   ; startup-only setting; per-viewport toggle also exists
textures/vram_compression/import_s3tc_bptc=true
textures/default_filters/anisotropic_filtering_level=4   ; 16x for grazing-angle roads (cost unmeasured)
environment/defaults/default_clear_color=Color(0.02, 0.024, 0.04, 1)
```

Defaults observed in a bare project (for reference): ticks 60, max steps 8, interpolation false,
`msaa_3d` 0, `use_taa` false, `scaling_3d/mode` 0, occlusion culling false, positional shadow atlas 4096,
volumetric fog volume 64x64x64, `max_clustered_elements` 512, `3d_panning_strength` 0.5.
Jolt defaults (all under `physics/jolt_physics_3d/`): `limits/max_linear_velocity=500.0`,
`limits/max_angular_velocity=47.12`, `limits/max_bodies=10240`, `limits/world_boundary_shape_size=2000.0`,
`simulation/velocity_steps=10`, `simulation/position_steps=2`, `simulation/continuous_cd_movement_threshold=0.75`,
`simulation/continuous_cd_max_penetration=0.25`, `queries/enable_ray_cast_face_index=false`.

## 3. Rendering features — what works and what it costs

### 3.1 Method (read this before trusting any number)
- Scene (`probe/scripts/bench_world.gd`): 400 box buildings (12–90 m tall) + 400 emissive neon bands
  (`#ff2bd6 #00e5ff #ffb000 #7a5cff`, `emission_energy_multiplier = 6`), wet ground (roughness from a cellular
  `NoiseTexture2D`, `metallic_specular = 0.6`), **50 OmniLight3D** (range 14 m, energy 3), moon DirectionalLight3D
  `#8fa6ff` energy 0.35 with shadows (max distance 200 m), AgX, camera 1.4 m above a street, 1920x1080, vsync off.
- A single window never went below about **4 ms/frame (~240–260 fps)** (cause est.: macOS presentation). Single-view fps is meaningless there,
  and `RenderingServer.viewport_get_measured_render_time_gpu()` returns **0.0 on Metal** (GPU timestamps empty).
- So every cost below is measured with **GPU amplification**: the main window plus 7 `SubViewport`s (1920x1080,
  `UPDATE_ALWAYS`, same World3D and camera) = 8 views per frame. Configs are interleaved `base, X, base, Y, ...`;
  cost = (frame_ms(X) − mean of neighbouring base) / 8 = **extra ms per 1080p view**. Base was 1.82–2.04 ms/view
  across the feature runs, but the near-empty instancing scene varied 0.6–1.07 ms/view between runs (GPU clock
  states) → only compare numbers measured in the same run.
- Harness: `./run.sh 160 --path . --always-on-top --resolution 1920x1080 --script res://scripts/bench.gd --
  --views=7 --configs=base,ssr,base` then `python3 interleave.py out/file.txt`.
- One-off per-frame work (ReflectionProbe UPDATE_ALWAYS, particle simulation) is shared by the 8 views,
  so its single-view cost is UNDER-stated (unverified how much).
- Screenshots: `probe/out/bench_*.png` (feature sheet `probe/out/sheet_features.jpg`).

### 3.2 Feature cost table (extra ms per 1920x1080 view on M1 Max 24-core; base ≈ 1.9 ms)

| Feature (config) | Settings used | +ms/view | Works? | Verdict for SKYRUSH |
|---|---|---|---|---|
| Glow / bloom | `glow_enabled`, intensity 0.8, bloom 0.05, hdr_threshold 1.0 | **+0.17** | yes | ON (neon look) |
| SSR | `ssr_enabled` defaults | **+1.27** | yes, reflections on wet road visible | ON (signature wet road), 1st to drop on low |
| SSAO | `ssao_enabled` defaults | **+0.42** | yes | ON |
| SSIL | `ssil_enabled` defaults | +1.02 | yes | OFF (little value at night) |
| Depth fog | `fog_enabled`, density 0.004 | +0.17 | yes | ON |
| Volumetric fog | density 0.015, albedo `#8090b0`, volume 64³ default | **+0.60** | yes, visible haze | ON (light shafts over Huangpu) |
| SDFGI | `sdfgi_enabled` defaults | +2.02, ~0.5 GB VRAM/view | yes | OFF |
| VoxelGI | 160x100x400 m volume, `bake()` = **360–386 ms** | +2.37 | yes | OFF |
| ReflectionProbe UPDATE_ONCE | 60x40x400 m, box projection | +0.25 | yes | ON for 1 probe per district |
| ReflectionProbe UPDATE_ALWAYS | same | +0.63 (amortised) | yes | avoid |
| 64 Decals | 4x2x4 m, 256² radial gradient | +0.18 | yes | ok (skid marks, puddles) |
| 24 refractive glass panes | `refraction_enabled`, scale 0.05, alpha 0.25 | +0.29 | yes | ok for car glass / shop windows |
| 8 omni lights with shadows (static) | `shadow_enabled` on 8 of the 50 | +0.05 | yes | ≤ 8 shadowed (moving lights cost more, unmeasured) |
| GPUParticles3D 4x5000, trails + heightfield collision | RibbonTrailMesh cross, 4 sections, trail 0.2 s | **+3.20** | yes | too expensive |
| GPUParticles3D 4x1000 with trails | same | +0.52 | yes | max for sparks |
| GPUParticles3D 4x5000, no trails (billboards) | QuadMesh 0.08 m | +0.11 | yes | fine (rain, sparks) |
| Radial-blur CompositorEffect | `snippets/radial_blur_effect.gd`, 12 samples, strength 0.15 | **+0.20** | yes, visibly smears | ON during nitro / flight |
| AreaLight3D x16, range 25 m | 4x2 m, energy 4 | +3.57–3.65 | yes | see 3.4 |

### 3.3 Anti-aliasing and upscalers

Light scene (base ≈ 1.9 ms/view):

| Config | +ms/view | Notes |
|---|---|---|
| FXAA | +0.06 | blurry |
| **SMAA** (`screen_space_aa=2`) | +0.31 | default choice (spatial: no temporal ghosting by design) |
| MSAA 2x / 4x | +0.28 / +0.44 | only geometry edges; no help on shader aliasing |
| TAA | +0.54 | ghosting risk on neon at speed (visual, unverified) |
| FSR 1.0 @0.77 | −0.25 | |
| FSR 2.2 @0.67 | **+0.99** | slower than native here |
| MetalFX Spatial @0.67 | **−0.30** | |
| MetalFX Temporal @0.67 | +0.78 | |

Heavy preset `glow + SSAO + vol. fog + SSR` = **4.17–4.34 ms/view**, then:

| Added to heavy | +ms/view |
|---|---|
| MetalFX Spatial @0.67 | **−1.37** |
| FSR 1.0 @0.77 | −0.76 |
| MetalFX Temporal @0.67 | −0.39 |
| FSR 2.2 @0.67 | +0.03 |
| TAA | +0.83 |
| SMAA | +0.04 |
| Bilinear @0.50 (reference) | −1.95 |

Rule: native 1.0 + SMAA by default; quality-low preset = MetalFX Spatial 0.77; never FSR2 on this Mac.

### 3.4 AreaLight3D (new in 4.7) — cost follows screen coverage, not count

| Config | +ms/view |
|---|---|
| 4 area lights, `area_range = 25` | +3.46 |
| 16 area lights, range 25 | +3.57 / +3.65 (two runs) |
| 16, range 25, `shadow_enabled` | +3.89 |
| 16, range 25, `area_texture` (256x128 gradient) | +4.26 |
| 16 area lights, **range 10** | **+1.09** |

Rule: ≤ 4 AreaLight3D on screen, `area_range ≤ 10`, no shadows, only for hero billboards (the Bund/Lujiazui
LED walls). Everything else: emissive material + glow + OmniLight3D/SpotLight3D (cheap: 50 omnis are in the base).

### 3.5 CompositorEffect (verified: `snippets/radial_blur_effect.gd`, 136 lines)
- Attach: `var c := Compositor.new(); c.compositor_effects = [preload("res://fx/radial_blur_effect.gd").new()]; camera.compositor = c`
  (or `WorldEnvironment.compositor`). Drive `strength` from gameplay: 0 = pass skipped, 0.06 cruise, 0.15 nitro, 0.25 max.
- Runs at `EFFECT_CALLBACK_TYPE_POST_TRANSPARENT`: the HDR colour buffer, before glow and tonemapping (so neon
  streaks still bloom). Two compute passes: copy colour → temp texture, then 12-tap blur back into colour.
- Uses `RenderSceneBuffersRD.get_internal_size()`: with MetalFX/FSR the effect runs at the internal (lower) res.
- The temp texture is created with `buffers.create_texture(&"radial_blur", &"tmp", DATA_FORMAT_R16G16B16A16_SFLOAT,
  SAMPLING|STORAGE, TEXTURE_SAMPLES_1, size, view_count, 1, true, false)`; the engine recreates it on resize.
- GLSL is compiled at runtime from a string (`RDShaderSource` → `shader_compile_spirv_from_source` →
  `shader_create_from_spirv`) on the render thread via `RenderingServer.call_on_render_thread()`. It compiled
  on Metal without errors. The Compatibility renderer has no RenderingDevice, so the effect disables itself.
- Uniform sets come from `UniformSetCacheRD.get_cache(shader, 0, [uniforms])` (no manual freeing needed).

## 4. Draw calls, instancing, HLOD, occlusion (verified)

Scene `probe/scripts/inst_features.gd`, minimal world (ground + moon), same 8-view method, absolute ms/view.
Empty scene = 1.05–1.07 ms/view. "RT CPU" = render-thread CPU ms for one view.

| Content | Draws/view | Objects/view | Tris/view | ms/view | RT CPU ms |
|---|---|---|---|---|---|
| 1 MultiMeshInstance3D, 20,000 x 64-tri cylinders | 2 | 2 | 1.92 M | 2.02 | 0.09 |
| same 20k split in 10x10 MMI chunks, `visibility_range_end=400` | 14 | 14 | 0.24 M | **1.19** | 0.08 |
| 2,000 MeshInstance3D, one shared mesh + material (~1k tris) | **22** | 1,738 | 1.69 M | 1.18 | 0.25 |
| same, **2,000 different StandardMaterial3D** | **1,738** | 1,738 | 1.69 M | **2.59** | 0.64 |
| same, one ShaderMaterial + `instance uniform vec4 tint` per node | **22** | 1,738 | 1.69 M | = shared (own run: 0.96 vs 0.97 shared vs 2.60 unique) | 0.23 |
| 10,000 MeshInstance3D shared | 35 | 8,515 | 8.28 M | 3.36 | 0.67 |
| City 45x45 = 2,025 buildings (~1k tris each), street camera | 32 | 1,813 | 1.76 M | 1.58 | 0.27 |
| + 2,025 `OccluderInstance3D` (BoxOccluder3D 0.95x) | 30 | 498 | 0.48 M | 1.20 | 0.46 |
| + HLOD (25 block proxies, `visibility_range_begin=350`, margin 20) | 47 | 298 | 0.29 M | 1.15 | 0.22 |
| + HLOD + occluders | 36 | 240 | 0.23 M | 1.17 | 0.42 |
| City, **air camera** (150 m up, flight mode) | 18 | 1,827 | 1.77 M | 1.68 | 0.27 |
| air + occluders | 18 | 1,593 | 1.55 M | 1.49 | 0.54 |
| air + HLOD | 34 | 262 | 0.25 M | **1.17** | 0.21 |
| air + HLOD + occluders | 34 | 241 | 0.23 M | 1.11 | 0.44 |

Conclusions:
- Forward+ **auto-batches** separate MeshInstance3D nodes that share mesh + material (1,738 objects → 22 calls).
  Unique material resources break it (one call per object, 2.2x GPU, 2.6x render-thread CPU).
- Per-object colour without breaking batching: shader with `instance uniform vec4 tint : source_color;` and
  `mi.set_instance_shader_parameter(&"tint", Color(...))` (verified: 22 calls).
- Occlusion culling pays off at street level (objects −73 %), but costs ~+0.2 ms render-thread CPU per view for
  2,025 box occluders and helps little from the air. HLOD is the big win for flight sections.
- `visibility_parent` semantics verified: children are hidden while the proxy is inside its visibility range.

## 5. Performance budget — city racer at 60 fps (16.7 ms) on this M1 Max

Targets assume 1920x1080, one camera, game content heavier than the probe (est. 2x geometry, real textures).

| Budget item | Limit | Basis |
|---|---|---|
| GPU frame | ≤ 10 ms at 1080p (leaves headroom for 1440p external display, thermals) | est. |
| Post stack | ≤ 3.0 ms: glow + SSAO + SSR + volumetric fog + SMAA + radial blur | §3.2 sum 2.97 ms |
| Visible draw calls | ≤ 600 per view (target 300) | each extra call ≈ 0.82 µs GPU + 0.23 µs RT CPU (§4: +1.41 ms / +0.39 ms for 1,716 extra calls) |
| Visible triangles | ≤ 3 M per view | 1.76 M = +0.5 ms; 8.3 M = +2.3 ms |
| Visible objects (nodes after culling) | ≤ 2,000 | 1,813 objects = 0.27 ms RT CPU |
| Omni/spot lights visible | ≤ 64 (clustered limit 512 elements); range ≤ 15 m | 50 omnis in base, no issue |
| Shadow-casting lights | 1 directional (4 splits, max distance 200 m) + ≤ 8 omni/spot | +0.05 ms for 8 static |
| AreaLight3D | ≤ 4 visible, range ≤ 10, no shadows | §3.4 |
| GPU particles | ≤ 20,000 billboard (+0.11 ms) and ≤ 4,000 with trails (+0.52 ms) | §3.2 |
| Decals | ≤ 64 visible | +0.18 ms |
| Reflection probes | ≤ 4 loaded, all `UPDATE_ONCE` | +0.25 ms each region (est. additive) |
| Physics (Jolt, 120 Hz = 2 ticks/frame) | ≤ 4 ms CPU per frame: ≤ 30 ShapeCast cars + ≤ 300 CCD debris | §6.4: 1.91 ms/tick |
| Audio synth voices | ≤ 2 AudioStreamGenerator (3.4 % of one core each in GDScript) | §9 |
| Textures — detail is a project requirement ("贴图纹理什么都要细化") | Roadster (always on screen): **4096²** albedo + normal + ORM, BC7 high quality ≈ 22.4 MB each with mips (≈ 67 MB set). Police car / hero props: 2048² sets (5.6 MB per map). Road: 2048² tiling asphalt set + 1024² detail normal tiled 8x via `detail_enabled` + 2048² wet/puddle mask per road section. Buildings: shared 2048² facade trim sheets per style (glass curtain wall, concrete, shikumen brick) + 2048² window-emission atlas; vary with `instance uniform`, not new textures. Neon signs/LED walls: 2048² emissive atlases, BC7 high quality (sharp hanzi edges). Props 1024²; decals 1024² atlas; UI uncompressed | import sizes §7.4 (measured); map sizes are est. |
| Texture memory total | ≤ 2 GB (est.; 32 GB unified memory). GPU cost of 4096² sampling not measured (§12) | est. |
| MultiMesh | 1 MMI per ~135 m cell, `visibility_range_end` 300–400 m | §4 |
| HLOD | per-block proxy, `visibility_range_begin` 350 m, margin 20 m | §4 |

## 6. Physics (verified)

### 6.1 Which engine is running
- Setting key: `physics/3d/physics_engine`; allowed values (hint string): `DEFAULT, Jolt Physics, GodotPhysics3D, Dummy`.
- There is **no CLI flag** for it; switch per run with an `override.cfg` next to project.godot:
  `printf '[physics]\n3d/physics_engine="Jolt Physics"\n' > override.cfg` (delete it afterwards).
- `DEFAULT` in 4.7.2 = **GodotPhysics3D**. Proof: set a free body to 1000 m/s → after 2 ticks Jolt reports 500.0
  (clamped by `jolt_physics_3d/limits/max_linear_velocity`), GodotPhysics3D and DEFAULT report 1000.0; a dropped
  sphere also rests at an identical 0.9899994 for DEFAULT and GodotPhysics3D (Jolt 0.9799998).
  The docs say "new projects will use [Jolt]" because the project manager writes the key; a hand-written
  project.godot does not get it (https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html).
- `VehicleBody3D` exists (ClassDB) but was not tested; the custom ShapeCast car below is the verified path.

### 6.2 Tunnelling at 100 m/s against trimesh (`probe/scripts/phys_tunnel.gd`)
Bodies: car box 1.9x1.2x4.6 m / 1800 kg, debris cube 0.3 m / 20 kg. Trimesh = `PlaneMesh.create_trimesh_shape()`
(same `ConcavePolygonShape3D` the importer makes for `-col`), zero thickness, road with a seam every 2 m.
Same verdict for Jolt and GodotPhysics3D at 60 and 120 Hz unless noted.

| Scenario | CCD off | `continuous_cd = true` |
|---|---|---|
| Car falls onto road at 100 m/s | **TUNNEL** (ends at y ≈ −155 m) | OK (Jolt rests at 0.58 m; GodotPhysics3D @60 Hz bounced to 12.9 m) |
| Car skims road at 100 m/s, −3 m/s vertical | OK (GodotPhysics3D @60 Hz launched car to y = 6 m) | OK |
| Car hits front face of a wall | OK (stops 2.3 m before: half car length) | OK |
| Debris 0.3 m hits wall, wall offset −30.37 m | **TUNNEL** (all 4 engine/rate combos) | OK |
| Debris, wall at exactly −30 m | 60 Hz "OK" only because a step landed exactly on the wall; 120 Hz TUNNEL | OK |
| Car hits the BACK face of a one-sided wall | **TUNNEL even with CCD** | TUNNEL |
| Same with `shape.backface_collision = true` | OK | OK |
| Car hits a 1 m guard rail at 30° | OK | OK |

Rules: CCD on for player, police, debris; one-sided trimesh walls get `backface_collision = true` (or model
closed volumes); never rely on 120 Hz alone to stop tunnelling.

### 6.3 Wheel probes at 100 m/s (`probe/scripts/phys_wheels.gd` driving `snippets/raycast_wheel_car.gd`)
Road: 1.2 km trimesh, seams every 2 m, ±5 cm sine bumps (wavelength 20 m = 5 Hz at 100 m/s), then a kicker ramp
2 m rise over 20 m at z = −300. Speed held at 100 m/s. Jolt. Final snippet parameters: spring 45,000 N/m,
damper 3,200 N·s/m, travel 0.30 m, wheel radius 0.34 m, mass 1800 kg, centre of mass y −0.1, grip 1.6,
`slip_cancel` 0.5, load cap 6x static, air-levelling torque k 20,000 / d 8,000.

| Probe | Hz | Wheel-air steps on bumps | Max compression | Airtime | After landing: lateral drift / tilt |
|---|---|---|---|---|---|
| ShapeCast3D sphere | 60 | 0 | 0.155 m | 1.98 s | **−0.02 m / 0.19°** |
| ShapeCast3D sphere | 120 | 0 | 0.155 m | 1.98 s | **0.00 m / 0.16°** |
| RayCast3D | 60 | 0 | 0.155 m | 2.17 s | −18.5 m, car fell off the 20 m road |
| RayCast3D | 120 | 0 | 0.154 m | 2.17 s | +3.7 m / 1.15° |

The first version (no load cap, full slip cancel, no air levelling) was unstable after landing: ray @60 Hz drifted
15.5 m, sphere @120 Hz drifted 13.3 m and ended tilted 17°. Keep those three stabilisers. Ray probes stay unstable
even with them → use spheres.

### 6.4 Physics CPU budget (`probe/scripts/phys_budget.gd`, headless, `--fixed-fps 120`)
World: one StaticBody3D with 2,025 BoxShape3D buildings + 1.2 x 1.2 km road trimesh (28.8k tris).
Cars = the ShapeCast car (GDScript wheel logic included). Debris = 0.4x0.3x0.6 m boxes with CCD, thrown.

| Load (per 120 Hz tick) | Jolt avg / p95 / max ms | GodotPhysics3D avg / p95 / max ms |
|---|---|---|
| empty world | 0.004 / 0.005 / 0.009 | 0.004 / 0.004 / 0.015 |
| 1 car | 0.21 / 0.36 / 0.44 | 0.22 / 0.29 / 0.36 |
| 31 cars | 1.54 / 1.72 / 2.10 | 2.69 / 2.96 / 3.17 |
| 31 cars + 300 debris | **1.91 / 2.13 / 3.56** | **13.0 / 56.4 / 183.2** |

At 120 Hz a 60 fps frame runs 2 ticks → 31 cars + 300 debris ≈ 3.8 ms of main-thread CPU (Jolt).
Recommendation (est.): civilian traffic = kinematic path followers (`AnimatableBody3D` on a `Path3D`), switched
to RigidBody3D only when hit; ≤ 8 full ShapeCast cars (player + police) near the player.
`physics/3d/run_on_separate_thread` exists (default false), not tested.

### 6.5 Jolt behaviours that affect this game (docs: link in 6.1, settings verified in 4.7.2)
- Contact impulses from `PhysicsDirectBodyState3D.get_contact_impulse()` are **estimates** under Jolt. For crash
  damage use the body's velocity change per tick (Δv · mass), not contact impulses (est. recommendation).
- `face_index` from RayCast3D/`intersect_ray` is −1 unless `physics/jolt_physics_3d/queries/enable_ray_cast_face_index=true`
  (+25 % ConcavePolygonShape3D memory). Per-surface type (asphalt/metal grate) → use separate bodies + metadata.
- `WorldBoundaryShape3D` is finite under Jolt: `limits/world_boundary_shape_size = 2000` m. The Shanghai map is
  larger than 2 km → use a thick BoxShape3D "kill floor" instead.
- Velocity limits: 500 m/s linear, 47.12 rad/s angular (fine for 100 m/s; barrel roll 2π/s = 6.3 rad/s).
- A `RigidBody3D` frozen as kinematic does not report contacts with static geometry unless
  `simulation/generate_all_kinematic_contacts=true`.

## 7. Asset pipeline: Blender 5.2 → .glb → Godot 4.7.2 (verified headless both ends)

### 7.1 Commands
```bash
# export (2 s): builds and exports the test asset; replace the build part with the real model code
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python ref/tech/snippets/blender_export_glb.py -- /abs/path/game/assets/cars/roadster.glb
# import every new/changed asset (3.9 s for the probe project) - also refreshes the class_name cache
godot --headless --path /abs/path/game --import
# inspect what Godot made of it (node tree, materials, LODs, collision shapes, metadata)
godot --headless --path /abs/path/game --script res://tools/inspect_import.gd -- res://assets/cars/roadster.glb
```
Exporter call used (Blender 5.2.1): `bpy.ops.export_scene.gltf(filepath=..., export_format="GLB",
use_selection=False, export_apply=True, export_yup=True, export_extras=True, export_cameras=False,
export_lights=False)` → `{'FINISHED'}`.

### 7.2 Result of the probe asset (`snippets/inspect_import.gd` output, abridged)
```
Barrier                      MeshInstance3D  M_Concrete #7a7a78   (Blender name "Barrier-col")
Barrier/StaticBody3D/CollisionShape3D   ConcavePolygonShape3D faces=12 backface=false
LampPole                     MeshInstance3D  M_Neon_Cyan emission #00e5ff x8.0   ("LampPole-convcol")
LampPole/StaticBody3D/CollisionShape3D  ConvexPolygonShape3D points=24
Ramp                         StaticBody3D (no mesh)                ("Ramp-colonly")
Ramp/CollisionShape3D        ConcavePolygonShape3D faces=12
Roadster_Body                MeshInstance3D meta=extras:{"skyrush_type": "player_car"}
    SURFACE 0 tris=640 lods=3 M_Paint_Red #b0001e metal 0.60 rough 0.25
    SURFACE 1 tris=128 lods=2 M_Glass #1a233059 transparency=4 (ALPHA_DEPTH_PRE_PASS)
Roadster_Body/Wheel_FL       MeshInstance3D pos=(-0.85, -0.21, -1.4)  tris=92 lods=4 M_Tyre
```
Verified facts:
- Node names = Blender object names with the suffix stripped; parenting is kept (wheels under body).
- Axes: Blender +Y forward / +Z up → Godot −Z forward / +Y up (`export_yup=True`). Model the car facing
  Blender +Y; the front wheels then sit at Godot z = −1.4. 1 Blender unit = 1 m = 1 Godot unit.
- Material names, sRGB base colour (exact hex), metallic, roughness, emission colour and strength (x8) survive.
  Blender material with alpha < 1 and `surface_render_method="BLENDED"` → Godot transparency 4 (alpha + depth pre-pass).
- Suffixes: `-col` = mesh + StaticBody3D child with trimesh (backface off); `-colonly` = StaticBody3D with trimesh, no mesh;
  `-convcol` = mesh + convex hull. Modifiers are baked by `export_apply=True` (Subsurf level 3 → 768 tris).
- LODs are generated automatically (`meshes/generate_lods=true` default): 2–4 LOD levels per surface.
- Custom properties → glTF extras → node metadata key `extras` (a Dictionary).
- In Blender 5.x read Principled BSDF by type (`n.type == "BSDF_PRINCIPLED"`); socket names used:
  "Base Color", "Metallic", "Roughness", "Alpha", "Emission Color", "Emission Strength".

### 7.3 Import options (`*.glb.import`, keys as generated by 4.7.2)
`nodes/root_type`, `nodes/root_name`, `nodes/apply_root_scale=true`, `nodes/root_scale=1.0`,
`nodes/use_name_suffixes=true`, `nodes/use_node_type_suffixes=true`, `meshes/ensure_tangents=true`,
`meshes/generate_lods=true`, `meshes/create_shadow_meshes=true`, `meshes/light_baking=1`,
`meshes/lightmap_texel_size=0.2`, `meshes/force_disable_compression=false`, `materials/extract=0`,
`_subresources={}`, `gltf/naming_version=2`, `gltf/embedded_image_handling=1`. Commit these files.

### 7.4 Textures (verified)
`compress/mode=2` (VRAM Compressed) on macOS imports as S3TC even though
`rendering/textures/vram_compression/import_s3tc_bptc` read `false` in the bare project (set it true anyway):
2048² RGB with mipmaps → **DXT1, 2.80 MB** (`.s3tc.ctex`); with `compress/high_quality=true` → **BPTC (BC7), 5.59 MB**.
Uncompressed RGBA8 with mips would be 22.4 MB. Use high_quality for the car and hero signs, normal for the rest.
Close-up detail without bigger maps (property names verified on BaseMaterial3D in 4.7.2; GPU cost not measured):
`detail_enabled = true`, `detail_uv_layer = BaseMaterial3D.DETAIL_UV_2`, `uv2_scale = Vector3(8, 8, 1)`,
`detail_albedo` / `detail_normal` = 1024² tiling grit, `detail_mask` = where it applies; buildings without UVs can
use `uv1_triplanar = true` / `uv2_world_triplanar = true`.

## 8. Capture, movie, script-check recipes (verified)

macOS has no `timeout`; wrap every unattended run: `perl -e 'alarm shift; exec @ARGV' 60 godot ...`
(exit code 142 = killed by the alarm). Keep ONE Godot window at a time.

| Task | Command | Verified result |
|---|---|---|
| Screenshot | `godot --path . --resolution 1920x1080 --always-on-top --script res://tools/capture.gd -- --scene=res://scenes/x.tscn --frames=30 --out=res://captures/x.png` | 1920x1080 PNG, `CAPTURE_OK <path>`, exit 0 |
| Several shots | add `--shots=3 --interval=10` → `x_0.png x_1.png x_2.png` | ok |
| Other camera | add `--camera=Path/To/Camera3D` (relative to scene root) | ok |
| Headless screenshot | impossible: `frame_post_draw` never fires (hangs); capture.gd exits 2 instead | verified |
| Movie (AVI) | `godot --path . --write-movie /abs/out/clip.avi --fixed-fps 60 --quit-after 120 res://scenes/x.tscn` | MJPEG 1920x1080 60 fps + PCM audio, 5.1 MB for 2 s |
| Movie (PNGs) | `--write-movie /abs/out/frames/f.png` → `f00000000.png ...` + `f.wav` | ok |
| Movie size | `--resolution` is IGNORED; size = `display/window/size/viewport_width/height`. Use `override.cfg` with `[display] window/size/viewport_width=1280 ...` | 1280x720 verified |
| To MP4 | `ffmpeg -i clip.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -an clip.mp4` | ok |
| Check one script | `godot --headless --path . --check-only --script res://x.gd` → prints `SCRIPT ERROR: Parse Error ... (res://x.gd:LINE)` but **exit code 0** | grep the output |
| Check ALL scripts | `godot --headless --path . --script res://tools/check_scripts.gd` → `SCRIPT_FAIL <path>` lines + `CHECKED 23 scripts, 3 failed`, exit code = failures | 0.27 s for 23 scripts |
| Benchmark window | always add `--always-on-top`; check `Engine.get_frames_drawn()` advanced (occluded macOS windows stop drawing) | §10 |

Folders that hold captures or other non-asset files need an empty `.gdignore`, otherwise the editor
imports every PNG (it did in the probe: `out/*.png` became `.ctex`).

## 9. Audio (verified, `probe/scripts/audio_test.gd`, `snippets/ev_synth.gd`)
- `AudioStreamGenerator` + GDScript synth (saw/sine partials + noise, `push_buffer(PackedVector2Array)` once per
  frame, `buffer_length = 0.1`): **0.70–0.77 ms CPU per 1000 frames ≈ 3.1–3.4 % of one core**, 0 skips, on
  Dummy (44.1 kHz) and CoreAudio (48 kHz). CoreAudio uses 48 kHz here even though `audio/driver/mix_rate`
  defaults to 44100 → always read `AudioServer.get_mix_rate()`.
- The Roadster is electric: use `snippets/ev_synth.gd` (motor whine following `motor_rpm` + thruster hiss
  following `thrust`), verified 0 skips. Max 2 synth voices; police sirens/traffic = looping WAV/OGG + `pitch_scale`.
- Doppler works when BOTH `AudioStreamPlayer3D.doppler_tracking` and `Camera3D.doppler_tracking` are
  `DOPPLER_TRACKING_PHYSICS_STEP`: 440 Hz source passing at 50 m/s measured **514–518 Hz approaching (theory 515)**
  and **374–386 Hz receding (theory 384)** with `AudioEffectSpectrumAnalyzer` on the Master bus.
- Nodes added in a SceneTree script's `_initialize()` are not in the tree yet: `play()` fails there → defer.

## 10. Gotchas (all hit or verified during this probe)

1. **Physics default is GodotPhysics3D** unless `physics/3d/physics_engine="Jolt Physics"` is written (§6.1).
2. **`--check-only` returns exit code 0 on parse errors.** Gate CI on `check_scripts.gd` instead.
3. Loading the currently running SceneTree script with `ResourceLoader.CACHE_MODE_IGNORE` **hangs** the engine
   (check_scripts.gd skips itself for this reason).
4. **Class cache:** `class_name` types resolve only after `.godot/global_script_class_cache.cfg` exists. Deleting it
   made a valid `var car: RaycastWheelCar` fail with "Could not find type". Run `godot --headless --import` after
   adding/renaming `class_name` scripts and on fresh clones (`.godot/` is not committed).
5. In a SceneTree script, `_initialize()` runs before nodes are inside the tree: `look_at()` errors ("Node not inside
   tree"), `AudioStreamPlayer.play()` fails, `get_visible_rect()` returns 100x100. Do setup in `_setup.call_deferred()`;
   for cameras set `camera.basis = Basis.looking_at(target - pos)` before `add_child`.
6. Headless (`--headless`) = dummy renderer: no adapter info, `frame_post_draw` never emits (await hangs),
   no screenshots. Physics and audio (Dummy driver) DO run in real time headless.
7. `--write-movie` ignores `--resolution` (uses project viewport size); AVI is MJPEG.
8. macOS stops drawing occluded/unfocused windows: a benchmark run showed stale stats and a fixed 6.90 ms
   frame time. Use `--always-on-top` and verify `Engine.get_frames_drawn()` advances (`drawn=1.00` in bench output).
9. `RenderingServer.viewport_get_measured_render_time_gpu()` = 0.0 and RD captured timestamps have 0 GPU time on Metal
   in 4.7.2 → measure GPU cost with the 8-view amplification method (§3.1), not with these APIs.
10. A single window bottoms out at about 4 ms/frame; any "fps > 240" comparison is noise. Apple GPU clocks also vary
    between runs (empty scene 4.8–8.5 ms for 8 views) → always interleave a baseline in the same run.
11. **HLOD error spam:** setting `visibility_parent` to a proxy MeshInstance3D that has no mesh yet produced
    8,100 `Condition "dep_instance->array_index == -1"` errors and 2.6 ms render-thread CPU; building proxies (with
    mesh) first fixed both (0.22 ms).
12. Unique `StandardMaterial3D` per object (e.g. `material.duplicate()` to recolour a sign) disables auto-batching;
    use `instance uniform` + `set_instance_shader_parameter()` (§4).
13. ConcavePolygonShape3D is one-sided; back-face hits pass through even with CCD (§6.2).
14. RayCast3D wheel probes destabilise the car on landings; ShapeCast3D spheres do not (§6.3).
15. Jolt reports `PhysicsServer3D.get_process_info(INFO_ACTIVE_OBJECTS / COLLISION_PAIRS / ISLAND_COUNT)` as 0, and
    `Performance.TIME_PHYSICS_PROCESS` read 0.000 in one headless Jolt run → time ticks with `Time.get_ticks_usec()`.
16. GDScript typing traps hit here: `PackedStringArray` has no `filter()` (wrap in `Array(...)`); `var x := ...` cannot
    infer from an untyped loop variable or Variant expression → write `var x: float = ...`.
17. zsh does not word-split `$var`: `godot ... -- $args` passes ONE argument. Use `${=args}` or arrays in zsh scripts.
18. The skyrush repo `.gitignore` currently ignores `*.import`. For the Godot game project that is wrong: Godot
    docs list only `.godot/` and `*.translation` as ignorable; commit `*.import` and `*.uid` files
    (https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html).
19. Put `.gdignore` into capture/output/reference folders inside the project, or the editor imports every image.
20. A runtime-created `VoxelGI.bake()` blocks the main thread for 360–386 ms; never bake during gameplay.
21. Godot printed `WARNING: 14 RIDs of type "Texture" were leaked` at exit after runs that toggled GI/probes at
    runtime (source not investigated; harmless for a probe).
22. `SDFGI` alone used ~0.5 GB VRAM per view (VRAM 131 MB → 631 MB in a single-view run).
23. Jolt clamps |v| to 500 m/s and finite `WorldBoundaryShape3D` (2,000 m) (§6.5).

## 11. Files

Snippets (copy into the game; each was executed as listed):
| File | What | Verified by |
|---|---|---|
| `ref/tech/snippets/project.godot.template` | baseline settings | key read-back + Jolt fingerprint |
| `ref/tech/snippets/capture.gd` | windowed screenshot tool (multi-shot, camera override, exit codes) | 1280x720 x3 and 1920x1080 captures |
| `ref/tech/snippets/radial_blur_effect.gd` | speed/nitro radial blur CompositorEffect | rendered + costed (+0.20 ms) |
| `ref/tech/snippets/raycast_wheel_car.gd` | `RaycastWheelCar` RigidBody3D, ShapeCast3D sphere wheels | phys_wheels.gd at 60/120 Hz |
| `ref/tech/snippets/check_scripts.gd` | parse-check all .gd in one run, exit code = failures | 3 deliberately broken scripts caught |
| `ref/tech/snippets/inspect_import.gd` | dump imported scene: nodes, materials, LODs, shapes, metadata | probe .glb |
| `ref/tech/snippets/blender_export_glb.py` | Blender 5.2 headless .glb export with suffix meshes + extras | Blender 5.2.1 run |
| `ref/tech/snippets/ev_synth.gd` | `EvSynth` AudioStreamPlayer3D: EV whine + thruster hiss | 0 skips CoreAudio/Dummy |

Probe harnesses (`ref/tech/probe/`, run with `./run.sh <seconds> <godot args>`): `scripts/bench.gd` (+ `bench_world.gd`,
`bench_features.gd`, `inst_features.gd`, `interleave.py`), `scripts/phys_tunnel.gd`, `scripts/phys_wheels.gd`,
`scripts/phys_budget.gd`, `scripts/audio_test.gd`, `scripts/info2.gd` (GPU/driver info), `scripts/enums.gd`,
`tools/capture.gd`, `tools/check_scripts.gd`, `scenes/capture_test.tscn`, `assets/test_asset.glb`.
Raw results: `probe/out/il1.txt il2.txt il3_heavy.txt il4_area.txt il5_area.txt inst_all8.txt tunnel.txt tunnel2.txt
wheels_jolt_v2.txt phys_budget.txt` (files prefixed `SUPERSEDED_` or `_v1_` are earlier invalid/noisy runs kept for the record); images `probe/out/sheet_features.jpg`, `bench_*.png`.

## 12. Not verified / open
- Visual quality of TAA / MetalFX Temporal ghosting at 100 m/s (only cost measured).
- Moving shadowed omni lights (police light bars) — shadow atlas update cost not measured.
- `physics/common/physics_interpolation=true` visual smoothness and camera-follow jitter (setting read back only).
- `physics/3d/run_on_separate_thread`, VehicleBody3D, SoftBody3D, HDR output, Vulkan/MoltenVK path.
- GPU cost of large (4096²) textures / texture bandwidth; only import size and format were measured.
- Real-game frame time: the probe city is boxes; re-run `bench.gd` against the real city once it exists.
