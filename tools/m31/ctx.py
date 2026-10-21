#!/usr/bin/env python3
"""Print the current context size (tokens) of each M3.1 job's live session (last assistant usage)."""
import json
import os
import sys

JOBS = os.path.join(os.path.dirname(__file__), "..", "..", "jobs")


def last_context(job):
    path = os.path.join(JOBS, job, "log.jsonl")
    state = json.load(open(os.path.join(JOBS, job, "state.json")))
    sid = state.get("session_id")
    last = 0
    if not os.path.exists(path):
        return state, 0
    for raw in open(path, "rb"):
        try:
            ev = json.loads(raw)
        except ValueError:
            continue
        if ev.get("session_id") not in (None, sid):
            continue
        if ev.get("type") == "assistant":
            u = ev.get("message", {}).get("usage", {})
            last = sum(u.get(k) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    return state, last


def main():
    for job in sorted(d for d in os.listdir(JOBS) if not d.startswith(".")):
        try:
            state, size = last_context(job)
        except (OSError, ValueError):
            continue
        flag = "  <-- near limit" if size > 800000 else ""
        print("%-14s %-9s ctx=%7d%s" % (job, state.get("status"), size, flag))


if __name__ == "__main__":
    main()
