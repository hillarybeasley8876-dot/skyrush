#!/usr/bin/env python3
"""SKYRUSH Windows wrapper: Godot, Blender and machine-wide run slots in one script.
Port of tools/godot.sh + blender.sh + slots.py + godot_import.sh (those are macOS-only).

Nothing is written to C: -- Godot user data, caches, TEMP and captures all live under F:
(ENV_DIR = <repo>/../_env, OUT = <repo>/../skyrush-out; override with SKYRUSH_ENV / SKYRUSH_OUT).

  python tools/gd.py import                       import changed assets (serialized, coalesced)
  python tools/gd.py check [--only=res://a/,res://b/]
                                                  import, then load every script/scene/shader; exit 1 on errors
  python tools/gd.py test res://path/test_x.gd [-- args]
                                                  headless Node test (PASS/FAIL lines, quits with 0|1), 120 Hz
  python tools/gd.py run res://scene.tscn [seconds]   windowed smoke run, prints errors + fps
  python tools/gd.py drive --timeline=res://tools/timelines/x.json [--shots=1,4] [--log=ABS.csv] [game opts]
                                                  scripted input play-through with telemetry CSV (windowed)
  python tools/gd.py shot --scene res://x.tscn --out name [--shots spec] [--warm N] [--size WxH]
                                                  windowed capture -> OUT/captures/<name>_<shot>.jpg
  python tools/gd.py perf --skip-menu [--spawn=x,y,z,yaw] [--warm=240]
  python tools/gd.py play                         launch the game normally (for humans)
  python tools/gd.py blender run <script.py> [-- args]   headless Blender build script

Pools (cap on concurrent runs, shared by every process on the machine): light 6, heavy 3, import 1.
A run that exceeds its timeout is killed (exit 124, "[slots] TIMEOUT"). Windowed runs open a window.
"""
import msvcrt
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "game"
DEV = ROOT.parent
ENV_DIR = Path(os.environ.get("SKYRUSH_ENV", str(DEV / "_env")))
OUT = Path(os.environ.get("SKYRUSH_OUT", str(DEV / "skyrush-out")))
GODOT = os.environ.get("SKYRUSH_GODOT", "F:/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
BLENDER = os.environ.get(
    "SKYRUSH_BLENDER",
    str(Path.home() / "AppData/Local/Programs/Blender Foundation/blender-5.2.1-windows-x64/blender.exe").replace("\\", "/"),
)
SLOT_DIR = ENV_DIR / "slots"
STAMP = SLOT_DIR / "import.stamp"
POOLS = {"light": 6, "heavy": 3, "import": 1}
TIMEOUT = {"light": 300, "heavy": 600, "import": 2400}
MAX_WAIT = 540  # give up before a caller's 10-minute tool timeout instead of piling up stale waiters


def child_env():
    env = dict(os.environ)
    for key, sub in (("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"), ("TEMP", "tmp"), ("TMP", "tmp")):
        path = ENV_DIR / sub
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["BLENDER_USER_RESOURCES"] = str(ENV_DIR / "blender")
    return env


def acquire(pool):
    """Hold one of the pool's lock files (OS-level byte lock, released automatically if we die)."""
    SLOT_DIR.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + MAX_WAIT
    noted = False
    while True:
        for i in range(POOLS[pool]):
            handle = open(SLOT_DIR / ("%s_%d.lock" % (pool, i)), "a+b")
            try:
                if handle.seek(0, os.SEEK_END) == 0:
                    handle.write(b"x")
                    handle.flush()
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                return handle
            except OSError:
                handle.close()
        if time.time() > deadline:
            sys.stderr.write("[slots] gave up after %d s waiting for a free '%s' slot - retry later\n" % (MAX_WAIT, pool))
            sys.exit(75)
        if not noted:
            sys.stderr.write("[slots] waiting for a free '%s' slot...\n" % pool)
            noted = True
        time.sleep(3)


def run(cmd, timeout, cwd=None):
    proc = subprocess.Popen([str(c) for c in cmd], cwd=cwd, env=child_env())
    try:
        return proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.stderr.write("[slots] TIMEOUT after %d s, killing: %s\n" % (timeout, " ".join(str(c) for c in cmd)[:200]))
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        return 124


def pooled(pool, cmd, timeout=None):
    handle = acquire(pool)
    try:
        return run(cmd, timeout or TIMEOUT[pool])
    finally:
        handle.close()


def changed_since(stamp_time):
    for dirpath, dirnames, filenames in os.walk(PROJ):
        dirnames[:] = [d for d in dirnames if d != ".godot"]
        for name in filenames:
            if name.endswith((".import", ".uid")):
                continue
            try:
                if os.stat(os.path.join(dirpath, name)).st_mtime > stamp_time:
                    return True
            except OSError:
                pass
    return False


def do_import():
    """Serialized, coalesced `godot --import`: skip when nothing changed since the last import started."""
    requested = time.time()
    handle = acquire("import")
    try:
        doctor = subprocess.run([sys.executable, str(ROOT / "tools" / "import_doctor.py"), str(PROJ)],
                                capture_output=True, text=True)
        print(doctor.stdout.strip())
        try:
            healed = int(doctor.stdout.strip().splitlines()[-1].split()[1])
        except (IndexError, ValueError):
            healed = 0
        if STAMP.exists() and healed == 0:
            stamp_time = STAMP.stat().st_mtime
            if stamp_time >= requested:
                print("[import] coalesced: an import that started after this request already finished")
                return 0
            if not changed_since(stamp_time):
                print("[import] up to date")
                return 0
        started = time.time()
        code = run([GODOT, "--headless", "--path", PROJ, "--import"], TIMEOUT["import"])
        if code == 0:
            STAMP.touch()
            os.utime(STAMP, (started, started))
        return code
    finally:
        handle.close()


def import_quiet():
    code = do_import()
    if code != 0:
        sys.stderr.write("[import] failed with exit code %d\n" % code)
    return code


def godot_args(*tail):
    return [GODOT, "--path", PROJ] + list(tail)


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "captures").mkdir(exist_ok=True)
    quality = "--quality=high"
    for arg in rest:
        if arg.startswith("--quality="):
            quality = arg
    outdir = "--outdir=%s" % (OUT / "captures")
    window = ["--windowed", "--resolution", "1600x900"]

    if cmd == "import":
        return do_import()
    if cmd == "check":
        if import_quiet() != 0:
            return 1
        return pooled("light", godot_args("--headless", "-s", "res://tools/check_all.gd", "--", *rest), 900)
    if cmd == "test":
        script = rest[0]
        extra = [a for a in rest[1:] if a != "--"]
        import_quiet()
        source = PROJ / script.replace("res://", "")
        legacy = source.exists() and "extends SceneTree" in source.read_text(encoding="utf-8", errors="replace")
        if legacy:
            return pooled("light", godot_args("--headless", "--fixed-fps", "120", "-s", script, "--", *extra, quality))
        return pooled("light", godot_args("--headless", "--fixed-fps", "120", "-s", "res://tools/test_host.gd",
                                          "--", "--test=" + script, *extra, quality))
    if cmd == "run":
        scene = rest[0]
        seconds = rest[1] if len(rest) > 1 else "20"
        import_quiet()
        return pooled("heavy", godot_args(*window, "-s", "res://tools/smoke_run.gd", "--", "--scene", scene,
                                          "--seconds", seconds, quality))
    if cmd == "drive":
        import_quiet()
        return pooled("heavy", godot_args(*window, "-s", "res://tools/autodrive.gd", "--", outdir, *rest, quality))
    if cmd == "shot":
        import_quiet()
        return pooled("heavy", godot_args(*window, "-s", "res://tools/capture.gd", "--", outdir, *rest, quality))
    if cmd == "perf":
        import_quiet()
        return pooled("heavy", godot_args(*window, "-s", "res://tools/perf_probe.gd", "--", *rest, quality))
    if cmd == "play":
        return run(godot_args(), 24 * 3600)
    if cmd == "blender":
        if len(rest) < 2 or rest[0] != "run":
            print("usage: gd.py blender run <script.py> [-- args]")
            return 2
        script = rest[1]
        extra = [a for a in rest[2:] if a != "--"]
        return pooled("heavy", [BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "--python", script,
                                "--", *extra], 2400)
    print("unknown command: %s\n" % cmd)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
