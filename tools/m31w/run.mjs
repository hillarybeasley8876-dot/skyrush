#!/usr/bin/env node
// m31w — orchestrator/worker runner for SKYRUSH on Windows (replacement for tools/m31/m31.py, which needs POSIX flock).
//
// The lead (Claude) writes a job spec + brief; this runner launches a headless Claude Code worker whose model is
// MiniMax-M3.1-Flash, then does NOT trust its report: it reverts edits outside the job's owned paths, runs the job's
// acceptance commands itself, and resumes the same worker session with the concrete failures until they pass or the
// round limit is hit. Every assistant message's real model name is checked against the requested one.
//
//   node tools/m31w/run.mjs run   <spec.json> [more.json ...] [--parallel N]
//   node tools/m31w/run.mjs accept <spec.json>        run the acceptance commands only (lead use)
//   node tools/m31w/run.mjs status [id]               one line per job
//   node tools/m31w/run.mjs progress <id> [-n 20]     the worker's last tool calls
//   node tools/m31w/run.mjs reset <spec.json>         discard the job (worktree jobs: remove worktree + branch)
//   node tools/m31w/run.mjs diff <id>                 stat of job/<id> against the current branch
//   node tools/m31w/run.mjs merge <id> [<id>...]      merge accepted job branches (--no-ff, aborts on conflict)
//
// Spec: { id, title, model?, brief, owns:[paths], accept:[{name, cmd, exit?, must?:[..], mustNot?:[..], timeoutS?}],
//         maxRounds?, maxTurns?, timeoutMin?, isolation?: "worktree", sparse?: [paths], readonly?: [paths inside owns] }
//   ("re:" prefix in must/mustNot = regular expression; isolation=worktree gives the job its own sparse git worktree
//    F:/dev/skyrush-wt/<id> on branch job/<id>, committed by the runner once acceptance passes)
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync, appendFileSync, rmSync, copyFileSync, readdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';

const ROOT = resolve(import.meta.dirname, '..', '..');
const OUT = resolve(process.env.SKYRUSH_OUT ?? join(ROOT, '..', 'skyrush-out'));
const ENVDIR = resolve(process.env.SKYRUSH_ENV ?? join(ROOT, '..', '_env'));
const WT = resolve(process.env.SKYRUSH_WT ?? join(ROOT, '..', 'skyrush-wt'));
const JOBS = join(OUT, 'jobs');
const CLAUDE = process.env.SKYRUSH_CLAUDE ?? join(process.env.APPDATA ?? join(homedir(), 'AppData', 'Roaming'), 'npm', 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe');
const DEFAULT_MODEL = process.env.SKYRUSH_M31_MODEL ?? 'MiniMax-M3.1-Flash';
const BACKOFF_S = [60, 120, 240, 480, 900];
const OUTAGE = ['积分不足', '预算不足', 'invalid api key', 'Unauthorized', ' 401'];
const CONTEXT = ['context window exceeds', 'prompt is too long', 'context_length', '(2013)'];
// Lead-owned paths: a worker never edits these (reverted if it does). Godot's own bookkeeping files are tolerated.
const LEAD_OWNED = ['tools/m31w/', 'tools/gd.py', 'briefs/improve/', 'SPEC.md', 'CONTRACTS.md', 'ART.md', 'README.md', '.gitignore'];
const TOLERATED = [/\.import$/, /\.uid$/];
const DENY = ['WebFetch', 'WebSearch', 'Agent', 'Task', 'Workflow',
  'Bash(rm -rf:*)', 'Bash(rm -fr:*)', 'Bash(rm -r:*)', 'Bash(rmdir:*)', 'Bash(rd:*)', 'Bash(del:*)', 'Bash(format:*)',
  'Bash(git push:*)', 'Bash(git reset:*)', 'Bash(git clean:*)', 'Bash(git checkout:*)', 'Bash(git restore:*)',
  'Bash(git stash:*)', 'Bash(git rebase:*)', 'Bash(git commit:*)', 'Bash(git add:*)',
  'Bash(pip:*)', 'Bash(pip3:*)', 'Bash(npm:*)', 'Bash(winget:*)', 'Bash(curl:*)', 'Bash(wget:*)', 'Bash(powershell:*)', 'Bash(taskkill:*)'];

const userEnv = JSON.parse(readFileSync(join(homedir(), '.claude', 'settings.json'), 'utf8')).env ?? {};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const posix = (p) => p.replace(/\\/g, '/');
const stamp = () => new Date().toISOString().slice(11, 19);

function git(args, cwd = ROOT) {
  const r = spawnSync('git', ['-c', 'core.quotepath=false', ...args], { cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  return r.stdout ?? '';
}

function dirtyFiles(cwd = ROOT) {
  const parts = git(['status', '--porcelain=v1', '-z', '--untracked-files=all'], cwd).split('\0').filter(Boolean);
  const out = [];
  for (let i = 0; i < parts.length; i++) {
    const code = parts[i].slice(0, 2);
    out.push(posix(parts[i].slice(3)));
    if (code[0] === 'R' || code[0] === 'C') i++;
  }
  return out;
}

// An isolated job gets its own (optionally sparse) git worktree + branch job/<id>: parallel jobs never see each other's edits.
function prepareWorkdir(job) {
  if (job.isolation !== 'worktree') return ROOT;
  const wt = join(WT, job.id);
  if (!existsSync(wt)) {
    mkdirSync(WT, { recursive: true });
    const base = git(['rev-parse', '--abbrev-ref', 'HEAD']).trim();
    git(['worktree', 'add', '--no-checkout', '-B', `job/${job.id}`, wt, base]);
    if (job.sparse) git(['sparse-checkout', 'set', '--no-cone', ...job.sparse.map((p) => '/' + p)], wt);
    git(['reset', '--hard', '-q'], wt);
    // A full game worktree starts with the lead's Godot import cache, so its first `gd.py check` is a no-op, not a 10-minute import.
    const cache = join(ROOT, 'game', '.godot');
    if (!job.sparse && existsSync(cache)) {
      spawnSync('robocopy', [cache, join(wt, 'game', '.godot'), '/E', '/MT:16', '/NFL', '/NDL', '/NJH', '/NJS', '/NP'], { stdio: 'ignore' });
    }
  }
  return wt;
}

function commitJob(job, cwd) {
  if (cwd === ROOT) return '';
  git(['add', '-A'], cwd);
  git(['commit', '-q', '-m', `job ${job.id}: ${job.title}\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`], cwd);
  return git(['rev-parse', '--short', 'HEAD'], cwd).trim();
}

const underOwn = (path, owns) => owns.some((o) => (o.endsWith('/') ? path.startsWith(o) : path === o));
const overlaps = (a, b) => a.some((x) => b.some((y) => x.startsWith(y) || y.startsWith(x)));

function workerEnv(job) {
  const cfg = join(ENVDIR, 'claude-worker', job.id);
  mkdirSync(cfg, { recursive: true });
  mkdirSync(join(ENVDIR, 'tmp'), { recursive: true });
  const model = job.model ?? DEFAULT_MODEL;
  const env = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (/^(VSCODE|ELECTRON|CLAUDE_CODE_SSE|CLAUDECODE|CLAUDE_CODE_ENTRYPOINT|MCP_)/.test(k)) continue;
    env[k] = v;
  }
  Object.assign(env, {
    CLAUDE_CONFIG_DIR: cfg,
    ANTHROPIC_BASE_URL: process.env.SKYRUSH_M31_BASE_URL ?? userEnv.ANTHROPIC_BASE_URL,
    ANTHROPIC_API_KEY: userEnv.ANTHROPIC_API_KEY || userEnv.ANTHROPIC_AUTH_TOKEN,
    ANTHROPIC_CUSTOM_HEADERS: userEnv.ANTHROPIC_CUSTOM_HEADERS ?? '',
    ANTHROPIC_MODEL: model, ANTHROPIC_DEFAULT_HAIKU_MODEL: model, ANTHROPIC_DEFAULT_SONNET_MODEL: model,
    ANTHROPIC_DEFAULT_OPUS_MODEL: model, ANTHROPIC_DEFAULT_FABLE_MODEL: model,
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1', CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: '1',
    CLAUDE_CODE_NO_MODEL_FALLBACK: 'true', CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY: '0',
    API_TIMEOUT_MS: '600000', CLAUDE_CODE_EFFORT_LEVEL: 'high', CLAUDE_CODE_MAX_OUTPUT_TOKENS: '32000',
    CLAUDE_CODE_MAX_CONTEXT_TOKENS: '1000000', CLAUDE_CODE_AUTO_COMPACT_WINDOW: '800000', CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: '75',
    BASH_DEFAULT_TIMEOUT_MS: '600000', BASH_MAX_TIMEOUT_MS: '1800000',
    TEMP: join(ENVDIR, 'tmp'), TMP: join(ENVDIR, 'tmp'), SKYRUSH_WORKER: 'm31',
  });
  delete env.ANTHROPIC_AUTH_TOKEN;
  return env;
}

function killTree(pid) {
  spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore' });
}

// ---- one claude process: stream-json in the log, resolves with the result event ----
function runClaude(job, st, prompt, dir, cwd) {
  const model = job.model ?? DEFAULT_MODEL;
  const args = ['-p', '--model', model, '--permission-mode', 'bypassPermissions', '--output-format', 'stream-json', '--verbose',
    '--max-turns', String(job.maxTurns ?? 250), st.sessionStarted ? '--resume' : '--session-id', st.sessionId, '--disallowedTools', ...DENY];
  return new Promise((done) => {
    const proc = spawn(CLAUDE, args, { cwd, env: workerEnv(job), windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    const logPath = join(dir, 'log.jsonl');
    let buf = '';
    let result = null;
    let lastText = '';
    const seen = { tools: 0, models: {} };
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; killTree(proc.pid); }, (job.timeoutMin ?? 120) * 60000);
    st.sessionStarted = true;
    st.pid = proc.pid;
    saveState(dir, st);
    proc.stdout.on('data', (chunk) => {
      buf += chunk.toString('utf8');
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!line.trim()) continue;
        appendFileSync(logPath, line + '\n');
        let ev;
        try { ev = JSON.parse(line); } catch { continue; }
        if (ev.type === 'assistant') {
          const m = ev.message?.model ?? '?';
          seen.models[m] = (seen.models[m] ?? 0) + 1;
          for (const b of ev.message?.content ?? []) {
            if (b.type === 'tool_use') seen.tools++;
            if (b.type === 'text' && b.text?.trim()) lastText = b.text;
          }
        } else if (ev.type === 'result') result = ev;
      }
    });
    proc.stderr.on('data', (c) => appendFileSync(join(dir, 'stderr.txt'), c));
    proc.stdin.on('error', () => {});
    proc.stdin.end(prompt);
    proc.on('close', (code) => {
      clearTimeout(timer);
      st.pid = null;
      done({ code, result, lastText, seen, timedOut });
    });
  });
}

function classify(r) {
  if (r.timedOut) return { kind: 'timeout', msg: 'attempt timed out' };
  const res = r.result;
  if (res && !res.is_error && res.subtype === 'success') return { kind: 'ok', msg: res.result ?? '' };
  if (res?.subtype === 'error_max_turns') return { kind: 'max_turns', msg: 'ran out of turns' };
  const msg = String(res?.result ?? `exit ${r.code}`);
  if (CONTEXT.some((m) => msg.includes(m))) return { kind: 'context', msg };
  if (OUTAGE.some((m) => msg.includes(m))) return { kind: 'outage', msg };
  return { kind: 'retry', msg };
}

// ---- acceptance: the runner executes the commands, the worker's own claims count for nothing ----
function runCmd(cmd, timeoutS, cwd) {
  return new Promise((done) => {
    const t0 = Date.now();
    const proc = spawn(cmd, { cwd, shell: true, windowsHide: true, env: { ...process.env, TEMP: join(ENVDIR, 'tmp'), TMP: join(ENVDIR, 'tmp') } });
    let out = '';
    const timer = setTimeout(() => { out += `\n[acceptance] TIMEOUT after ${timeoutS}s\n`; killTree(proc.pid); }, timeoutS * 1000);
    proc.stdout.on('data', (c) => { out += c.toString('utf8'); });
    proc.stderr.on('data', (c) => { out += c.toString('utf8'); });
    proc.on('close', (code) => { clearTimeout(timer); done({ code, out, ms: Date.now() - t0 }); });
  });
}

const has = (out, pat) => (pat.startsWith('re:') ? new RegExp(pat.slice(3), 'm').test(out) : out.includes(pat));

async function runAccept(job, cwd = ROOT) {
  const results = [];
  for (const a of job.accept ?? []) {
    let r;
    let why;
    // Godot sometimes exits with -1 at shutdown on a busy machine after a clean verdict: a failed acceptance
    // command that runs Godot gets one more try before it counts against the worker.
    const tries = /gd\.py|run_tests\.py/.test(a.cmd) ? 2 : 1;
    for (let k = 0; k < tries; k++) {
      r = await runCmd(a.cmd, a.timeoutS ?? 900, cwd);
      why = [];
      // "exit": null in a spec = any exit code (a test that prints its known failures and exits 1); `??` turned null into 0
      const want = a.exit === undefined ? 0 : a.exit;
      if (want !== null && r.code !== want) why.push(`exit code ${r.code}, expected ${want}`);
      for (const m of a.must ?? []) if (!has(r.out, m)) why.push(`output lacks: ${m}`);
      for (const m of a.mustNot ?? []) if (has(r.out, m)) why.push(`output must not contain: ${m}`);
      if (why.length === 0) break;
    }
    results.push({ name: a.name, cmd: a.cmd, pass: why.length === 0, why, tail: r.out.split('\n').slice(-40).join('\n').slice(-3500), ms: r.ms });
  }
  return results;
}

// ---- ownership: edits outside the job's paths are quarantined and reverted ----
function enforceOwnership(job, baseline, others, dir, round, cwd) {
  const mine = [...job.owns, `status/improve/${job.id}.md`];
  const stray = [];
  for (const p of dirtyFiles(cwd)) {
    // `readonly` paths (the lead's oracle tests) are reverted even inside an owned folder
    const locked = underOwn(p, job.readonly ?? []);
    if (!locked && (baseline.has(p) || underOwn(p, mine) || others.some((o) => underOwn(p, o)) || TOLERATED.some((re) => re.test(p)))) continue;
    stray.push(p);
  }
  const q = join(OUT, 'quarantine', job.id, `r${round}`);
  for (const p of stray) {
    const abs = join(cwd, p);
    if (existsSync(abs)) {
      mkdirSync(dirname(join(q, p)), { recursive: true });
      copyFileSync(abs, join(q, p));
    }
    const tracked = git(['ls-files', '--', p], cwd).trim() !== '';
    if (tracked) git(['checkout', '--', p], cwd);
    else rmSync(abs, { force: true });
  }
  return stray;
}

// ---- prompts ----
function firstPrompt(job) {
  const preamble = readFileSync(join(ROOT, 'tools', 'm31w', 'preamble.md'), 'utf8').replaceAll('{JOB}', job.id);
  const brief = readFileSync(join(ROOT, job.brief), 'utf8');
  const owns = [...job.owns, `status/improve/${job.id}.md`].map((o) => `- \`${o}\``).join('\n');
  const acc = (job.accept ?? []).map((a, i) => `${i + 1}. **${a.name}** — run \`${a.cmd}\`` +
    `${(a.must ?? []).length ? ` and the output must contain: ${a.must.map((m) => `\`${m}\``).join(', ')}` : ''}` +
    `${(a.mustNot ?? []).length ? `; it must NOT contain: ${a.mustNot.map((m) => `\`${m}\``).join(', ')}` : ''}` +
    `${a.exit === null ? '' : ` (exit code ${a.exit === undefined ? 0 : a.exit})`}`).join('\n');
  return `${preamble}\n\n# YOUR BRIEF — ${job.title}\n\n${brief}\n\n## Files you own (the only paths you may edit)\n${owns}\n\n## Acceptance (the runner executes these itself after you finish)\n${acc}\n`;
}

function feedbackPrompt(job, round, acc, stray, ended) {
  const L = [`# Feedback from the lead — round ${round} did NOT pass`, ''];
  if (ended.kind === 'max_turns') L.push('Your previous run stopped because it ran out of turns; continue where you stopped.', '');
  if (ended.kind === 'timeout') L.push('Your previous run hit the time limit; continue where you stopped and work in smaller steps.', '');
  for (const a of acc.filter((x) => !x.pass)) {
    L.push(`## FAILED acceptance: ${a.name}`, `command: \`${a.cmd}\``, `problems: ${a.why.join('; ')}`, 'last output lines:', '```', a.tail, '```', '');
  }
  if (stray.length) L.push('## Edits outside your owned paths were REVERTED', ...stray.map((s) => `- ${s}`), 'Put requests for those files under `## Requests` in your status file instead.', '');
  L.push('Fix the root cause in your owned files, re-run the failing commands yourself and read their output, update your status file, then report. Do not edit any check to make it pass.');
  return L.join('\n');
}

// ---- job state ----
const stPath = (dir) => join(dir, 'state.json');
const loadState = (dir) => (existsSync(stPath(dir)) ? JSON.parse(readFileSync(stPath(dir), 'utf8')) : null);
const saveState = (dir, st) => writeFileSync(stPath(dir), JSON.stringify(st, null, 1));

async function runJob(job, others) {
  const dir = join(JOBS, job.id);
  mkdirSync(dir, { recursive: true });
  const cwd = prepareWorkdir(job);
  const st = loadState(dir) ?? { id: job.id, title: job.title, status: 'new', rounds: 0, sessionId: randomUUID(), sessionStarted: false, history: [] };
  st.cwd = cwd;
  const maxRounds = job.maxRounds ?? 4;
  let prompt = null;
  let acc = [];
  let ended = { kind: 'ok' };
  if (st.rounds >= maxRounds) st.rounds = Math.max(0, maxRounds - 1);
  while (st.rounds < maxRounds) {
    st.rounds++;
    st.status = 'running';
    st.startedAt = new Date().toISOString();
    prompt = prompt ?? (st.sessionStarted ? `The lead resumes this job. Re-read your status file and the brief, check what is on disk, and continue until the acceptance commands pass.` : firstPrompt(job));
    writeFileSync(join(dir, `prompt-${st.rounds}.md`), prompt);
    saveState(dir, st);
    const baseline = new Set(dirtyFiles(cwd));
    let r;
    for (let attempt = 0; attempt <= BACKOFF_S.length; attempt++) {
      r = await runClaude(job, st, prompt, dir, cwd);
      ended = classify(r);
      if (ended.kind === 'ok' || ended.kind === 'max_turns' || ended.kind === 'timeout') break;
      if (ended.kind === 'outage') { st.status = 'outage'; st.error = ended.msg; saveState(dir, st); return st; }
      if (ended.kind === 'context') { st.sessionId = randomUUID(); st.sessionStarted = false; prompt = firstPrompt(job) + '\n\n# CONTINUATION: a fresh session on an existing task; everything you did is on disk. Read your status file first.'; }
      console.log(`[${stamp()}] ${job.id}: ${ended.kind} (${String(ended.msg).slice(0, 120)}) -> retry in ${BACKOFF_S[Math.min(attempt, BACKOFF_S.length - 1)]}s`);
      await sleep(BACKOFF_S[Math.min(attempt, BACKOFF_S.length - 1)] * 1000);
    }
    const requested = job.model ?? DEFAULT_MODEL;
    const wrong = Object.entries(r.seen.models).filter(([m]) => m !== requested);
    const stray = enforceOwnership(job, baseline, others(), dir, st.rounds, cwd);
    acc = await runAccept(job, cwd);
    const pass = acc.every((a) => a.pass) && stray.length === 0;
    st.history.push({ round: st.rounds, end: ended.kind, tools: r.seen.tools, models: r.seen.models, wrongModel: wrong.length > 0, stray, acc: acc.map((a) => ({ name: a.name, pass: a.pass, why: a.why })) });
    console.log(`[${stamp()}] ${job.id} round ${st.rounds}: end=${ended.kind} tools=${r.seen.tools} stray=${stray.length} accept=${acc.filter((a) => a.pass).length}/${acc.length}${wrong.length ? ` WRONG MODEL ${JSON.stringify(r.seen.models)}` : ''}`);
    if (wrong.length) { st.status = 'wrong_model'; saveState(dir, st); return st; }
    st.lastText = r.lastText;
    if (pass) { st.status = 'accepted_mechanical'; st.commit = commitJob(job, cwd); break; }
    st.status = 'failed_round';
    prompt = feedbackPrompt(job, st.rounds, acc, stray, ended);
    saveState(dir, st);
  }
  if (st.status !== 'accepted_mechanical') st.status = 'needs_lead';
  writeFileSync(join(dir, 'result.md'), [`# ${job.id} — ${st.status}`, '', `rounds: ${st.rounds}`, '', '## Worker final message', st.lastText ?? '', '', '## Acceptance',
    ...acc.map((a) => `- ${a.pass ? 'PASS' : 'FAIL'} ${a.name}${a.why.length ? ` (${a.why.join('; ')})` : ''}`)].join('\n'));
  saveState(dir, st);
  return st;
}

async function runMany(specs, parallel) {
  const queue = [...specs];
  const active = [];
  const finished = [];
  const launch = () => {
    for (let i = 0; i < queue.length && active.length < parallel; i++) {
      const job = queue[i];
      if (active.some((a) => overlaps(a.job.owns, job.owns) && a.job.isolation !== 'worktree' && job.isolation !== 'worktree')) continue;
      queue.splice(i--, 1);
      const entry = { job };
      entry.p = runJob(job, () => active.filter((a) => a !== entry && a.job.isolation !== 'worktree' && job.isolation !== 'worktree').map((a) => a.job.owns)).then((st) => ({ entry, st }));
      active.push(entry);
    }
  };
  while (queue.length || active.length) {
    launch();
    if (!active.length) break;
    const { entry, st } = await Promise.race(active.map((a) => a.p));
    active.splice(active.indexOf(entry), 1);
    finished.push(st);
    console.log(`[${stamp()}] FINISHED ${st.id}: ${st.status} after ${st.rounds} round(s)`);
  }
  return finished;
}

function loadSpec(path) {
  const spec = JSON.parse(readFileSync(resolve(path), 'utf8'));
  for (const f of ['id', 'title', 'brief', 'owns']) if (!spec[f]) throw new Error(`spec ${path}: missing "${f}"`);
  for (const o of spec.owns) if (LEAD_OWNED.some((l) => o.startsWith(l) || l.startsWith(o))) throw new Error(`spec ${spec.id}: owns "${o}" is lead-owned`);
  return spec;
}

function progress(id, n) {
  const lines = readFileSync(join(JOBS, id, 'log.jsonl'), 'utf8').split('\n').filter(Boolean);
  const calls = [];
  for (const l of lines) {
    let ev; try { ev = JSON.parse(l); } catch { continue; }
    for (const b of ev.message?.content ?? []) {
      if (ev.type === 'assistant' && b.type === 'tool_use') calls.push(`${b.name}: ${String(b.input.command ?? b.input.file_path ?? b.input.pattern ?? JSON.stringify(b.input)).slice(0, 150)}`);
      if (ev.type === 'assistant' && b.type === 'text' && b.text.trim()) calls.push(`SAY: ${b.text.trim().slice(0, 150).replace(/\n/g, ' ')}`);
    }
  }
  console.log(`${calls.length} events; last ${n}:`);
  calls.slice(-n).forEach((c) => console.log('  ' + c));
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const flag = (name, dflt) => { const i = rest.indexOf(name); return i >= 0 ? rest[i + 1] : dflt; };
  const files = rest.filter((a, i) => a.endsWith('.json') && rest[i - 1] !== '--parallel');
  if (cmd === 'run') {
    const finished = await runMany(files.map(loadSpec), +flag('--parallel', 3));
    console.log('\n' + finished.map((s) => `${s.status.padEnd(20)} ${s.id} (${s.rounds} rounds)`).join('\n'));
    process.exitCode = finished.every((s) => s.status === 'accepted_mechanical') ? 0 : 1;
  } else if (cmd === 'accept') {
    const spec = loadSpec(files[0]);
    const wt = spec.isolation === 'worktree' && existsSync(join(WT, spec.id)) ? join(WT, spec.id) : ROOT;
    const acc = await runAccept(spec, wt);
    acc.forEach((a) => console.log(`${a.pass ? 'PASS' : 'FAIL'}  ${a.name}${a.why.length ? '  -> ' + a.why.join('; ') : ''}`));
    process.exitCode = acc.every((a) => a.pass) ? 0 : 1;
  } else if (cmd === 'status') {
    for (const id of existsSync(JOBS) ? readdirSync(JOBS) : []) {
      const st = loadState(join(JOBS, id));
      if (st && (!rest[0] || rest[0] === id)) console.log(`${(st.status ?? '?').padEnd(20)} ${id.padEnd(28)} rounds=${st.rounds} tools=${st.history?.at(-1)?.tools ?? 0}`);
    }
  } else if (cmd === 'progress') {
    progress(rest[0], +flag('-n', 20));
  } else if (cmd === 'reset') {
    const job = loadSpec(files[0]);
    if (job.isolation === 'worktree') {
      git(['worktree', 'remove', '--force', join(WT, job.id)]);
      git(['branch', '-D', `job/${job.id}`]);
      rmSync(join(JOBS, job.id), { recursive: true, force: true });
      console.log('removed worktree, branch and state of', job.id);
    } else {
      const paths = [...job.owns, `status/improve/${job.id}.md`];
      git(['checkout', '--', ...paths]);
      git(['clean', '-fdq', '--', ...paths]);
      console.log('reset', paths.join(', '));
    }
  } else if (cmd === 'diff') {
    const base = git(['rev-parse', '--abbrev-ref', 'HEAD']).trim();
    console.log(git(['diff', '--stat', `${base}...job/${rest[0]}`]));
  } else if (cmd === 'merge') {
    for (const id of rest) {
      const r = spawnSync('git', ['merge', '--no-ff', '-m', `Merge job/${id}\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, `job/${id}`], { cwd: ROOT, encoding: 'utf8' });
      console.log((r.stdout ?? '') + (r.stderr ?? ''));
      if (r.status !== 0) {
        // files Godot generates (.uid, .import) conflict when the lead committed them while the job generated its own:
        // take ours; any other conflict aborts the merge
        const unmerged = git(['diff', '--name-only', '--diff-filter=U']).split('\n').filter(Boolean);
        if (unmerged.length > 0 && unmerged.every((f) => /\.(uid|import)$/.test(f))) {
          for (const f of unmerged) { git(['checkout', '--ours', '--', f]); git(['add', '--', f]); }
          const c = spawnSync('git', ['commit', '--no-edit'], { cwd: ROOT, encoding: 'utf8' });
          console.log('auto-resolved generated files (ours):', unmerged.join(', '));
          if (c.status === 0) continue;
        }
        git(['merge', '--abort']); console.log('MERGE FAILED, aborted:', id); process.exitCode = 1; break;
      }
    }
  } else {
    console.log(readFileSync(import.meta.filename, 'utf8').split('\n').slice(0, 17).join('\n'));
  }
}

main().catch((e) => { console.error('FATAL', e.stack ?? e); process.exit(2); });
