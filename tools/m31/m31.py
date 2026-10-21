#!/usr/bin/env python3
"""M3.1 job runner: runs MiniMax-M3.1 as a detached headless Claude Code worker.

  m31.py start <job> --brief FILE [--cwd DIR] [--force]   launch (detached) with brief + worker preamble
  m31.py feedback <job> (--file FILE | --text TEXT)       resume the job's session with feedback (detached)
  m31.py wait <job> [--timeout SEC]                        block until done/failed or timeout; print summary
  m31.py status [job]                                      state of one job or all jobs
  m31.py progress <job> [-n N]                             last N tool calls / messages from the log
  m31.py stop <job>                                        kill the running attempt
  m31.py nudge <job> (--file F | --text T)                 interrupt the running attempt; the supervisor
                                                           resumes the same session with this note first

State lives in <root>/jobs/<job>/: state.json, prompt-<n>.md, log.jsonl, result.md, stderr.txt.
Attempts retry with backoff on API errors (same session via --resume); outage errors stop the job.
A flock slot pool caps concurrent workers (env SKYRUSH_M31_SLOTS, default 10).
"""
import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
JOBS = os.path.join(ROOT, "jobs")
SLOTS_DIR = os.path.join(JOBS, ".slots")
MODEL = os.environ.get("SKYRUSH_M31_MODEL", "MiniMax-M3.1-Flash-Preview")
MAX_SLOTS = int(os.environ.get("SKYRUSH_M31_SLOTS", "28"))
ATTEMPT_TIMEOUT = int(os.environ.get("SKYRUSH_M31_ATTEMPT_TIMEOUT", str(150 * 60)))
MAX_ATTEMPTS = 6
BACKOFF = [60, 120, 240, 480, 900]
OUTAGE_MARKERS = ["积分不足", "预算不足", "ERR_NGROK", "bandwidth limit", "invalid api key",
                  "401", "Unauthorized"]
CONTEXT_MARKERS = ["context window exceeds", "prompt is too long", "context_length", "(2013)"]
PREAMBLE_FILE = os.path.join(os.path.dirname(__file__), "preamble.md")
TERMINAL = ("done", "failed", "stopped")


def job_dir(job):
    return os.path.join(JOBS, job)


def load_state(job):
    path = os.path.join(job_dir(job), "state.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def save_state(job, state):
    path = os.path.join(job_dir(job), "state.json")
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def pid_alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def worker_settings():
    env = {k: MODEL for k in ("ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL",
                              "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL")}
    # M3.1 has a ~1M-token window that Claude Code does not know: make it compact at ~600k instead of
    # overflowing ("400 context window exceeds limit (2013)").
    env.update({"API_TIMEOUT_MS": "600000", "CLAUDE_CODE_EFFORT_LEVEL": "high", "SKYRUSH_WORKER": "m31",
                "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT": "0",
                "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "1000000", "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "800000",
                "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "75"})
    return json.dumps({"disableAllHooks": True, "env": env})


def claude_cmd(state):
    cmd = ["claude", "-p", "--model", MODEL, "--permission-mode", "bypassPermissions",
           "--strict-mcp-config", "--mcp-config", os.path.join(os.path.dirname(__file__), "no-mcp.json"),
           "--disallowedTools", "Agent", "Workflow", "Task",
           "--settings", worker_settings(), "--output-format", "stream-json", "--verbose"]
    if state.get("session_started"):
        cmd += ["--resume", state["session_id"]]
    else:
        cmd += ["--session-id", state["session_id"]]
    return cmd


def acquire_slot():
    os.makedirs(SLOTS_DIR, exist_ok=True)
    while True:
        for i in range(MAX_SLOTS):
            fd = os.open(os.path.join(SLOTS_DIR, "m31_%d.lock" % i), os.O_CREAT | os.O_RDWR)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except OSError:
                os.close(fd)
        time.sleep(10)


def scan_result(log_path, offset):
    """Return (result_event or None, new_text) for log lines written after offset."""
    result = None
    with open(log_path, "rb") as f:
        f.seek(offset)
        for raw in f:
            try:
                ev = json.loads(raw)
            except ValueError:
                continue
            if ev.get("type") == "result":
                result = ev
    return result


def run_attempt(job, state, prompt):
    jd = job_dir(job)
    n = state["attempts"] + 1
    with open(os.path.join(jd, "prompt-%d.md" % n), "w") as f:
        f.write(prompt)
    log_path = os.path.join(jd, "log.jsonl")
    offset = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    state.update(status="running", attempts=n, attempt_started=time.time())
    env = {k: v for k, v in os.environ.items() if not k.startswith(("VSCODE", "ELECTRON", "CLAUDE_CODE_SSE"))}
    with open(log_path, "ab") as out, open(os.path.join(jd, "stderr.txt"), "ab") as err:
        proc = subprocess.Popen(claude_cmd(state), cwd=state["cwd"], stdin=subprocess.PIPE,
                                stdout=out, stderr=err, env=env, start_new_session=True)
        state.update(pid=proc.pid, session_started=True)
        save_state(job, state)
        proc.stdin.write(prompt.encode())
        proc.stdin.close()
        try:
            code = proc.wait(timeout=ATTEMPT_TIMEOUT)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            time.sleep(5)
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
            code = "timeout"
    return code, scan_result(log_path, offset)


def classify(code, result):
    """-> ('done'|'retry'|'outage', message)"""
    if code == 0 and result and not result.get("is_error"):
        return "done", result.get("result") or ""
    msg = (result or {}).get("result") or ("exit %s" % code)
    if any(m in msg for m in CONTEXT_MARKERS):
        return "context", msg
    if any(m in msg for m in OUTAGE_MARKERS):
        return "outage", msg
    return "retry", msg


RESUME_PROMPT = ("Your previous run was interrupted by an error ({err}). Continue the SAME task from where "
                 "you stopped: re-read your checkpoint file under status/ and your brief, check what is "
                 "already on disk, then finish the remaining work and report as instructed.")


NUDGE_PROMPT = ("The lead interrupted you on purpose to change direction. Read this note first and follow it; "
                "it overrides your current plan. Afterwards continue the task (brief + review feedback) as instructed.\n\n")


CONTINUE_NOTE = ("# CONTINUATION — this is a fresh session on an existing task\n"
                 "You already worked on this unit in earlier sessions; everything you built is on disk. Before doing "
                 "anything: read your checkpoint `status/{job}.md`, `git status`/`ls` your owned paths, the newest "
                 "`reviews/{job}-r*.md` and `reviews/{job}-lead.md`, then continue. Do not restart from scratch.\n\n")


def fresh_prompt(job, state, extra):
    with open(PREAMBLE_FILE) as f:
        preamble = f.read().replace("{JOB}", job)
    with open(state["brief"]) as f:
        brief = f.read()
    return (preamble + "\n\n# YOUR BRIEF (" + os.path.relpath(state["brief"], ROOT) + ")\n\n" + brief + "\n\n"
            + CONTINUE_NOTE.format(job=job) + extra)


def take_nudge(job):
    path = os.path.join(job_dir(job), "nudge.md")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        text = f.read()
    os.remove(path)
    return text


def session_exists(sid):
    base = os.path.expanduser("~/.claude/projects")
    for d in os.listdir(base):
        if os.path.exists(os.path.join(base, d, sid + ".jsonl")):
            return True
    return False


def supervise(job, prompt):
    state = load_state(job)
    state.update(status="queued", sup_pid=os.getpid(), chain_attempts=0)
    save_state(job, state)
    fd = acquire_slot()
    try:
        while True:
            state = load_state(job)
            if state["status"] == "stopped":
                return
            state["session_started"] = session_exists(state["session_id"])
            state["chain_attempts"] += 1
            code, result = run_attempt(job, state, prompt)
            verdict, msg = classify(code, result)
            state = load_state(job)
            if state["status"] == "stopped":
                return
            state.update(pid=None, last_exit=str(code))
            if verdict == "done":
                with open(os.path.join(job_dir(job), "result.md"), "w") as f:
                    f.write(msg)
                state.update(status="done", ended=time.time(), error=None)
                save_state(job, state)
                return
            if verdict == "outage" or state["chain_attempts"] >= MAX_ATTEMPTS:
                state.update(status="failed", ended=time.time(), error=msg[:2000])
                save_state(job, state)
                return
            nudge = take_nudge(job)
            delay = 5 if (nudge or verdict == "context") else BACKOFF[min(state["chain_attempts"] - 1, len(BACKOFF) - 1)]
            if verdict == "context":
                state.update(session_id=str(uuid.uuid4()), session_started=False)
            state.update(status="backoff", error=msg[:500], next_try=time.time() + delay)
            save_state(job, state)
            time.sleep(delay)
            if verdict == "context":
                prompt = fresh_prompt(job, state, "Your previous session ran out of context and was closed. " + (nudge or ""))
            else:
                prompt = RESUME_PROMPT.format(err=msg[:300].replace("\n", " "))
                if nudge:
                    prompt = NUDGE_PROMPT + nudge
    finally:
        os.close(fd)


def daemonize(job, prompt):
    pid = os.fork()
    if pid > 0:
        os.waitpid(pid, 0)
        return
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    null = os.open(os.devnull, os.O_RDWR)
    os.dup2(null, 0)
    os.dup2(null, 1)
    err = os.open(os.path.join(job_dir(job), "supervisor.err"), os.O_WRONLY | os.O_CREAT | os.O_APPEND)
    os.dup2(err, 2)
    try:
        supervise(job, prompt)
    except Exception as exc:  # record, never leave a job "running" silently
        state = load_state(job) or {}
        state.update(status="failed", error="supervisor crash: %r" % (exc,))
        save_state(job, state)
        raise
    finally:
        os._exit(0)


def effective_status(state):
    if state["status"] in ("queued", "running", "backoff", "starting") and not pid_alive(state.get("sup_pid")):
        if time.time() - state.get("created", 0) > 30:
            return "orphaned"
    return state["status"]


def cmd_start(args):
    jd = job_dir(args.job)
    old = load_state(args.job)
    if old and effective_status(old) not in TERMINAL + ("orphaned",) and not args.force:
        sys.exit("job %s is %s; use wait/stop" % (args.job, effective_status(old)))
    if old and not args.force:
        sys.exit("job %s exists (%s); use feedback to continue it, or --force for a fresh session"
                 % (args.job, old["status"]))
    os.makedirs(jd, exist_ok=True)
    with open(PREAMBLE_FILE) as f:
        preamble = f.read()
    with open(args.brief) as f:
        brief = f.read()
    prompt = preamble.replace("{JOB}", args.job) + "\n\n# YOUR BRIEF (" + os.path.relpath(args.brief, ROOT) + ")\n\n" + brief
    if args.extra:
        prompt += "\n\n# EXTRA NOTES FROM THE LEAD\n\n" + args.extra
    state = {"job": args.job, "cwd": os.path.abspath(args.cwd or ROOT), "session_id": str(uuid.uuid4()),
             "session_started": False, "status": "starting", "attempts": 0, "created": time.time(),
             "brief": os.path.abspath(args.brief), "model": MODEL}
    save_state(args.job, state)
    daemonize(args.job, prompt)
    print(json.dumps({"job": args.job, "status": "started", "session_id": state["session_id"]}))


def cmd_feedback(args):
    state = load_state(args.job)
    if not state:
        sys.exit("no such job " + args.job)
    st = effective_status(state)
    if st not in TERMINAL + ("orphaned",):
        sys.exit("job %s is %s; wait for it first" % (args.job, st))
    text = open(args.file).read() if args.file else args.text
    feedback = ("# FEEDBACK FROM THE LEAD (Opus reviewer / art director)\n\nYour previous work on this task was "
                "reviewed. Address EVERY point below, in order. Verify each fix by actually running the "
                "checks/tests/screenshots, update your status file, then report what you changed and the "
                "evidence.\n\n" + text)
    # Every feedback round starts a fresh session (checkpoint + brief + feedback): sessions otherwise grow
    # towards M3.1's ~1M-token limit and fail with "context window exceeds".
    state.update(session_id=str(uuid.uuid4()), session_started=False)
    prompt = fresh_prompt(args.job, state, feedback)
    state.update(status="starting", created=time.time(), error=None)
    save_state(args.job, state)
    daemonize(args.job, prompt)
    print(json.dumps({"job": args.job, "status": "resumed", "session_id": state["session_id"]}))


def tail_events(job, n):
    path = os.path.join(job_dir(job), "log.jsonl")
    if not os.path.exists(path):
        return []
    out = []
    with open(path, "rb") as f:
        for raw in f:
            try:
                ev = json.loads(raw)
            except ValueError:
                continue
            if ev.get("type") != "assistant":
                continue
            for block in ev.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    inp = block.get("input", {})
                    arg = inp.get("command") or inp.get("file_path") or inp.get("pattern") or ""
                    out.append("%s: %s" % (block.get("name"), str(arg).replace("\n", " ")[:140]))
                elif block.get("type") == "text" and block.get("text", "").strip():
                    out.append("text: " + block["text"].strip().replace("\n", " ")[:200])
    return out[-n:]


def summary(job):
    state = load_state(job)
    st = effective_status(state)
    info = {"job": job, "status": st, "attempts": state.get("attempts"),
            "minutes": round((time.time() - state.get("created", time.time())) / 60, 1)}
    if state.get("error") and st != "done":
        info["error"] = state["error"][:600]
    return info


def cmd_wait(args):
    deadline = time.time() + args.timeout
    while True:
        state = load_state(args.job)
        if not state:
            sys.exit("no such job " + args.job)
        st = effective_status(state)
        if st in TERMINAL + ("orphaned",) or time.time() >= deadline:
            break
        time.sleep(5)
    print(json.dumps(summary(args.job), ensure_ascii=False))
    if st == "done":
        res = open(os.path.join(job_dir(args.job), "result.md")).read()
        lines = res.splitlines()
        print("--- result (last 60 lines) ---")
        print("\n".join(lines[-60:]))
    else:
        print("--- recent activity ---")
        print("\n".join(tail_events(args.job, 8)))


def cmd_status(args):
    jobs = [args.job] if args.job else sorted(d for d in os.listdir(JOBS) if not d.startswith("."))
    for job in jobs:
        if load_state(job):
            print(json.dumps(summary(job), ensure_ascii=False))


def cmd_progress(args):
    print("\n".join(tail_events(args.job, args.n)))


def cmd_nudge(args):
    state = load_state(args.job)
    if not state:
        sys.exit("no such job " + args.job)
    text = open(args.file).read() if args.file else args.text
    with open(os.path.join(job_dir(args.job), "nudge.md"), "w") as f:
        f.write(text)
    pid = state.get("pid")
    if effective_status(state) == "running" and pid_alive(pid):
        os.killpg(pid, signal.SIGTERM)
        print(json.dumps({"job": args.job, "status": "nudged (attempt interrupted; resumes with the note)"}))
    else:
        print(json.dumps({"job": args.job, "status": "note queued; job not running — it is used on the next retry only"}))


def cmd_stop(args):
    state = load_state(args.job)
    if not state:
        sys.exit("no such job " + args.job)
    state["status"] = "stopped"
    save_state(args.job, state)
    for key in ("pid", "sup_pid"):
        pid = state.get(key)
        if pid_alive(pid):
            try:
                os.killpg(pid, signal.SIGTERM) if key == "pid" else os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
    print(json.dumps({"job": args.job, "status": "stopped"}))


def main():
    os.makedirs(JOBS, exist_ok=True)
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("job")
    s.add_argument("--brief", required=True)
    s.add_argument("--cwd")
    s.add_argument("--extra")
    s.add_argument("--force", action="store_true")
    s.set_defaults(fn=cmd_start)
    s = sub.add_parser("feedback")
    s.add_argument("job")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--file")
    g.add_argument("--text")
    s.set_defaults(fn=cmd_feedback)
    s = sub.add_parser("wait")
    s.add_argument("job")
    s.add_argument("--timeout", type=int, default=540)
    s.set_defaults(fn=cmd_wait)
    s = sub.add_parser("status")
    s.add_argument("job", nargs="?")
    s.set_defaults(fn=cmd_status)
    s = sub.add_parser("progress")
    s.add_argument("job")
    s.add_argument("-n", type=int, default=20)
    s.set_defaults(fn=cmd_progress)
    s = sub.add_parser("nudge")
    s.add_argument("job")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--file")
    g.add_argument("--text")
    s.set_defaults(fn=cmd_nudge)
    s = sub.add_parser("stop")
    s.add_argument("job")
    s.set_defaults(fn=cmd_stop)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
