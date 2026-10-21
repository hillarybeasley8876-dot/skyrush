export const meta = {
  name: 'skyrush-accept',
  description: 'Whole-game acceptance for SKYRUSH: integration check, 6 independent critics, route issues to owner M3.1 units, wait, verify',
  phases: [
    { title: 'Integrate', detail: 'boot main.tscn with all real units, zero-error gate, collect cross-unit requests' },
    { title: 'Critics', detail: 'aesthetic, feel, perf, e2e, shanghai fidelity, audio — each writes issues tagged by owner unit' },
    { title: 'Fix', detail: 'one feedback file per owner unit → M3.1 job → wait' },
    { title: 'Verify', detail: 'per unit: did the fixes land (captures/tests)?' },
  ],
}

const ROOT = '/Users/minimax/m/skyrush'
const ROUND = (args && args.round) || 1
const ONLY = (args && args.units) || null
const UNITS = ['car_model', 'npc_cars', 'vehicle', 'camera', 'fx_thrusters', 'fx', 'hud', 'audio', 'environment', 'city_layout',
  'roads', 'buildings', 'bund', 'landmarks', 'props', 'world', 'menu', 'traffic', 'damage', 'police', 'modes']

let consecutiveNull = 0
async function ag(prompt, opts) {
  for (let i = 0; i < 4; i++) {
    if (consecutiveNull >= 6) { log('circuit breaker open: skipping ' + opts.label); return null }
    const r = await agent(prompt, opts)
    if (r) { consecutiveNull = 0; return r }
    consecutiveNull++
    log(`retry ${i + 1} for ${opts.label}`)
  }
  return null
}

const COMMON = `Project SKYRUSH (飞驰申城) at ${ROOT}: cyberpunk night-Shanghai racer, Godot 4.7.2 + Blender, built by MiniMax M3.1 worker units (see CONTRACTS.md ownership table) and reviewed by Opus. Read SPEC.md, ART.md, CONTRACTS.md first. Tools: tools/godot.sh (check|test|shot|drive|movie|perf|run), tools/blender.sh preview. Always pass --skip-menu when you want gameplay. IMAGE BUDGET: view ≤ 15 images total, downscale first (captures are JPEG; use ffmpeg tile/hstack contact sheets). HARD API LIMIT: every Write/Edit ≤ 120 lines. Never edit unit files — you only observe, measure and write reports under reviews/ and captures/accept/. Be concrete: every issue has the owning unit, evidence (capture path / numbers), what to change, and how to verify.`

const ISSUES = {
  type: 'object',
  properties: {
    pass: { type: 'boolean' }, score: { type: 'number' }, summary: { type: 'string' },
    issues: { type: 'array', items: { type: 'object', properties: {
      unit: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
      title: { type: 'string' }, detail: { type: 'string' } }, required: ['unit', 'severity', 'title', 'detail'] } },
  },
  required: ['pass', 'score', 'summary', 'issues'],
}

const CRITICS = [
  { key: 'aesthetic', prompt: `AESTHETIC critic. Capture the real game (main.tscn --skip-menu) at the 6 standard viewpoints (Bund road heading north at driver height, Yan'an elevated deck, under the dragon-pillar interchange, Lujiazui Century Ave, Nanpu spiral top, flight altitude 120 m over the river) plus 3 chase-cam frames of the Roadster (rest, 250 km/h, N2 boost with thrusters) and 1 frame each of the toll plaza, gas station and charge station. Use tools/godot.sh shot with --cams and --spawn options (see game/tools/capture.gd header). Judge with ART.md §10 checklist and ref/art/DOSSIER.md value targets (run ref/art/lookdev/tools/screenshot_stats.py on each frame). Is every surface textured? Does it read as Shanghai at night, store-screenshot quality?` },
  { key: 'feel', prompt: `FEEL critic. Drive with tools/godot.sh drive using input timelines (existing ones in game/tools/timelines/; you may add new files named game/tools/timelines/accept_*.json — the only place you may write inside game/) on the real map (default) and the sandbox (--stub=world): launch, top speed, braking, QQ-style drift + 小喷 + N2, hop/Big Hop, barrel roll, sky-lane flight, charge bay, crash into traffic and a police car. Use --log=<csv> telemetry and compare with ref/gameplay/DOSSIER.md §0 and §8.1 targets; check the camera (FOV ramp, lag, shake) from shot sequences.` },
  { key: 'perf', prompt: `PERFORMANCE critic. Run tools/godot.sh perf --skip-menu at the 6 standard viewpoints (use --spawn=x,y,z,yaw) and report fps, draw calls, objects, primitives per subsystem vs ref/tech/GODOT.md §5 budgets (≤ 600 draws, ≤ 2,000 objects, ≥ 60 fps at 1080p high). Also: load time to playable (main.tscn), memory, engine error count in a 60 s drive (tools/godot.sh drive ... must report errors=0).` },
  { key: 'e2e', prompt: `END-TO-END critic (real user). Simulate a player with scripted input: boot main.tscn WITHOUT --skip-menu, title → main menu → free roam (drive 30 s, trigger a stunt, charge, police chase start) → pause → settings (quality, volume) → back → race (pick a route, countdown, finish or quit) → results → pursuit mode → busted or escape. Use tools/godot.sh drive timelines with key presses (ui_accept, ui_down, etc. — check game/ui/menu for the actions it uses). Report every dead end, crash, unreadable text, wrong state, error spam.` },
  { key: 'shanghai', prompt: `SHANGHAI FIDELITY critic. Compare the game against ref/shanghai/SHANGHAI_DOSSIER.md and its photos: Bund building order and silhouettes (HSBC dome, Customs clock tower, Peace Hotel pyramid), Lujiazui skyline order seen from the Bund (OPT front-left, trio behind, Shanghai Tower tallest/rightmost), dragon-pillar interchange (levels, pillar look), elevated parapet planters + blue under-deck light, Nanpu spiral + H towers, green guide signs with correct Chinese/English text, road markings, street furniture. Capture side-by-sides with the reference photos.` },
  { key: 'audio', prompt: `AUDIO critic. Record a 40 s gameplay movie with tools/godot.sh movie --movie=${ROOT}/captures/accept/audio_r${ROUND}.avi --timeline=res://tools/timelines/feel_sandbox.json --skip-menu, extract the audio with ffmpeg, and analyse it offline (levels, clipping, spectral centroid of the thruster hiss 2–4 kHz, presence of motor whine, wind, tyres, impacts, music, voice lines, ducking). Use python3 (numpy is available in Blender's python: /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I). Report what is missing or badly mixed.` },
]

phase('Integrate')
const integ = await ag(`${COMMON}
INTEGRATION check (acceptance round ${ROUND}). 1) tools/godot.sh check (whole project) — list failures by owner unit. 2) tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,8,14 --out=accept_r${ROUND}_smoke — Modules must load every unit as real (the [main] units line), list engine errors by source file and owner. 3) Collect every "## Requests" item from status/*.md that is still open, decide which unit must act (or "core" for the lead). Return issues tagged by unit (use unit "core" for project.godot/core/tools requests).`, { label: `integrate:r${ROUND}`, phase: 'Integrate', schema: ISSUES, effort: 'high' })

phase('Critics')
const crit = await parallel(CRITICS.map(c => () => ag(`${COMMON}\n${c.prompt}\nThis is acceptance round ${ROUND}. Save your evidence under captures/accept/r${ROUND}/${c.key}/. pass = no blocker and no major issues.`, { label: `critic:${c.key}:r${ROUND}`, phase: 'Critics', schema: ISSUES, effort: 'high' })))

const all = [integ, ...crit].filter(Boolean)
const byUnit = {}
for (const report of all) for (const it of report.issues || []) {
  const u = UNITS.includes(it.unit) ? it.unit : (it.unit === 'core' ? 'core' : 'world')
  ;(byUnit[u] = byUnit[u] || []).push(it)
}
log('issues per unit: ' + Object.entries(byUnit).map(([u, l]) => `${u}:${l.length}`).join(' '))
const targets = Object.keys(byUnit).filter(u => u !== 'core' && (!ONLY || ONLY.includes(u)))

phase('Fix')
const fixed = await pipeline(targets,
  u => ag(`${COMMON}
Write ${ROOT}/reviews/accept-r${ROUND}-${u}.md for the "${u}" unit from these acceptance issues (keep every detail, order by severity, number them, add a "## How to verify" line per item; mention which critic found it):
${JSON.stringify(byUnit[u], null, 1)}
Then send it to the worker: python3 ${ROOT}/tools/m31/m31.py feedback ${u} --file ${ROOT}/reviews/accept-r${ROUND}-${u}.md
If the job is still running, wait for it first with: python3 ${ROOT}/tools/m31/m31.py wait ${u} --timeout 540 (repeat until done), then send. Then wait for the job to finish (repeat the wait command until status is done/failed). Return the final status line.`, { label: `fix:${u}`, phase: 'Fix', effort: 'low' }),
  (r, u) => ag(`${COMMON}
VERIFY the "${u}" unit's acceptance fixes: read reviews/accept-r${ROUND}-${u}.md and jobs/${u}/result.md, re-run the relevant checks/captures for each item, and report which items are fixed. Return issues = the items still open (same unit).`, { label: `verify:${u}`, phase: 'Verify', schema: ISSUES, effort: 'high' }))

return {
  round: ROUND,
  critics: all.map(r => ({ pass: r.pass, score: r.score, summary: r.summary, n: (r.issues || []).length })),
  core_issues: byUnit.core || [],
  verify: targets.map((u, i) => ({ unit: u, open: fixed[i] ? (fixed[i].issues || []).length : null, summary: fixed[i] ? fixed[i].summary : 'verifier died' })),
}
