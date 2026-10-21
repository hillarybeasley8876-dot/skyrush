# Lead workflow scripts (run with the Workflow tool, scriptPath = this folder)
- review-loop: per unit wait → Opus review → feedback (≤ maxRounds). Copy in the session scripts dir.
- accept.js: whole-game acceptance: integration check → 6 critics (aesthetic, feel, perf, e2e, shanghai, audio)
  → issues routed to owner units as reviews/accept-r<N>-<unit>.md + m31 feedback → wait → verify. args {round, units?}.

Release export needs `rendering/textures/vram_compression/import_etc2_astc=true` (arm64/universal); it is OFF during development
because it doubles every texture import. Turn it on only in the packaging step (then a full reimport runs once).
