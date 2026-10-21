# Brief: hud — QQ飞车-style racing HUD with cyberpunk styling

## Goal
A crisp, readable, beautiful in-game HUD (Chinese first) that shows speed, N₂, boost prompts,
stunts, race/pursuit info and the Roadster reveal-stream telemetry gauges.

## You own
`game/ui/hud/**`, `game/ui/theme/**` (shared Theme, fonts setup, colours for HUD and menu).
Entry (Modules unit `hud`): `res://ui/hud/hud.tscn` (a CanvasLayer).

## Read first
`ref/gameplay/DOSSIER.md` §2.1 (QQ HUD layout), §3.2/3.4 (pursuit bars, heat), §3.5 (takedown banner
style), §5 (N₂ slots, hop charge ring, sky lane signage); `ref/roadster/DOSSIER.md` §6.4 (livestream
gauges: DOWNFORCE / attitude icon / PITCH / ALTITUDE — exact layout); `ART.md` §3 (UI palette),
§7 (typography); `ref/art/DOSSIER.md` §7 (typography); `core/contracts/car_telemetry.gd`,
`core/events.gd`, `core/contracts/world_base.gd` (minimap polylines, POIs).
Fonts available: `res://assets/fonts/SmileySans-Oblique.ttf` (得意黑, display/italic numerals),
`res://assets/fonts/NotoSansSC-Variable.ttf` (UI text). Licences next to them (OFL).

## Layout (1920×1080 reference, anchors so 16:10 and 21:9 work)
- Bottom-right: speedometer — big italic digits (Smiley Sans) km/h, an arc gauge with ticks and a
  cyan→magenta gradient, rpm-like motor-load ring; battery % small under it.
- Bottom-left: **2 N₂ COPV slots** (stylised cylinders) filling with cyan; current drift's pending
  gain striped; slot flashes when full; under them the 小喷 prompt ("小喷!" in amber, a timing bar
  when `telemetry.mini_window`), hop charge ring (Big Hop) when `hop_charge` > 0.
- Top-left: race position (big italic "1ST"/"第1名"), racer list; or in pursuit the **heat level**
  (5 police-light pips), units count, evade/busted bar (dossier §3.2 behaviour).
- Top-right: time, best, lap "1/2 圈"; minimap (rotating, player-up) from `Game.world`
  polylines + POIs (charge = cyan bolt, gas = amber, toll = white gate, sky lane = dashed cyan,
  police = red/blue blinking dots).
- Centre pop-ups (toasts) for `Events.stunt`, `toast`, `near_miss`, `drift_ended` (clean),
  `boost_started` kinds, `n2_ring`, `charge_finished` ("闪充完成 +N₂"); queue + stack, max 3.
- Takedown banner per §3.5 (amber skewed parallelogram, black text, pops large then docks top-left).
- **Flight / air gauges**: when airborne > 0.3 s or flying, show the reveal-stream cluster
  (DOWNFORCE kg + car-attitude icon bottom-left; PITCH deg + ALTITUDE m bottom-right — we use metres;
  slashed zeros, 270° arcs) per roadster dossier §6.4, sliding in over 0.2 s; corner plume ticks
  on the attitude icon when P1–P4 fire. Hide the normal speedo cluster partially to avoid clutter.
- Countdown "3 · 2 · 1 · GO!" (modes emit `race_countdown`), "完美起步!" when the launch boost
  fires at start.
- Pause overlay is the menu unit's job; you only hide the HUD on `game_paused`.

## Style
Dark glass panels (#0B0F1A @ 70 %, 1 px cyan edge, cut corners), cyan #00E5FF primary, magenta
#FF2BD6 for boost/flight, amber #FFB300 warnings, red #FF3355 police. Subtle scanline/glitch only
on transitions. All text Chinese first with small English sub-labels. Animated with Tweens, 60 fps
cheap (no per-frame allocations, no shaders > 0.1 ms).

## Evidence / acceptance
`ui/hud/demo/hud_demo.tscn` that fakes telemetry and fires every event in a loop (no world needed)
→ captures of each state (`captures/hud/`); in-game captures in the sandbox (`main.tscn`).
Text crisp at 1080p, nothing overlaps, readable over bright neon scenes (test over a white and a
saturated magenta background), check clean, < 0.3 ms CPU per frame.
