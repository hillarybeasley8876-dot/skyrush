# Brief: bund — the Bund waterfront (外滩): 25 heritage buildings, promenade, flood wall

## Goal
The most recognisable street of Shanghai, at night: the row of classical/Art Deco banks from Asia
Building to Broadway Mansions, warm-gold uplit, the raised riverside promenade with cast-iron
lamps and balustrade, the flood wall washed blue on the river face.

## You own
`blender/bund/**`, `game/assets/bund/**`.

## Read first
`ref/shanghai/SHANGHAI_DOSSIER.md` §5 (all: building table with z-positions, frontages, depths,
heights, styles, roof cues, facade colours; night look §5.4; cross-section §5.2; promenade facts),
§12; photos `ref/shanghai/img/05_bund/` + `sheets/`; `ref/art/DOSSIER.md` §1.2 (Bund lighting facts
2500 K / 1800 K, "见光不见灯"), §3.4 (Bund uplights rhythm), §4.9 (granite conditioning),
§5 (texture IDs: granite_tile_03 etc.); `ART.md`; `CONTRACTS.md` §2; `blender/lib/*`.

## Build
1. A **classical facade kit** (`blender/bund/kit/`): rusticated granite base, pilasters and columns
   (Ionic/Doric/Corinthian approximations, fluted where photos show), entablature/cornice profiles
   swept with `geo.sweep`, window bays with surrounds/pediments/keystones/balconettes, attic
   storeys, balustrades, domes on drums (HSBC), clock tower (Customs House: 4 clock faces backlit
   `#FFF6E0`, stepped top + mast), pyramid roof (Sassoon House, dark-green copper `#2E5E4E`, lit
   `#21C08B`), Chinese hipped roof (Bank of China), Art Deco fins (Bank of Communications), corner
   cupolas, gothic gables (Commercial Bank of China), ziggurat setbacks (Broadway Mansions).
2. **All 25 buildings** of dossier §5.3 at the given positions/frontages/depths/heights, each its
   own node `Bund_<No>_<short_name>`, real heights. Front facade fully detailed; sides and backs
   simpler but textured (the player sees them from side streets). Roof clutter, flags (red, static
   mesh with slight wave), lit window interiors (warm `#FF9F40` at 30 %, sparse).
3. **Promenade + flood wall** per §5.1/§5.2: raised deck at y +2.5, stairs/ramps, balustrade with
   32 semicircular viewing balconies, 64 palace lanterns (宫灯) and 8 granite lamp columns, paving,
   planters, the flood-wall river face (emissive wash strip `#1E8BFF`→`#29D3FF`), Chen Yi Square and
   the Bund Financial Plaza with a stylised **bronze bull** (not a copy of the real sculpture's
   trademarked look — a generic charging bull), the Meteorological Signal Tower (slim Art Deco
   tower) at Yan'an Rd.
4. **Lighting data**: Empties `Uplight_*` every 5 m along each facade base (1 m from the wall, aimed
   up 80°) and `Crown_*` at domes/towers for the world unit's light pooling (export also a sidecar
   `game/assets/bund/bund_lights.json` with transforms + colour + energy); facade materials stay
   neutral granite (albedo ~#ABAAA3) — the gold comes from the lights (art dossier rule).
5. Export: `game/assets/bund/bund_buildings.glb`, `bund_promenade.glb`, simplified `-convcolonly`
   colliders for building fronts and `-colonly` for the promenade/flood wall; budget ≤ 1.2 M tris
   total LOD0 (the Bund is the hero district), shared trim sheets for mouldings.

## Evidence / acceptance
Previews of each building vs its reference photo (side-by-side composites in
`captures/bund/compare_<No>.jpg` for HSBC, Customs House, Sassoon House, Bank of China, Broadway
Mansions at least); a Godot night scene `game/assets/bund/preview_bund.tscn` with spot lights from
`bund_lights.json` and the environment unit's environment: captures from the road (driver view
heading north and south), from the promenade, and from across the river (the classic skyline
view). The lead judges recognisability: HSBC dome, Customs clock tower and the Peace Hotel pyramid
must be unmistakable; the row must read warm gold, no RGB neon.
