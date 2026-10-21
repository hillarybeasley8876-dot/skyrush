"""Insert blank lines before/after markdown tables (outside code fences). Usage: pad_tables.py file.md"""
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
out = []
in_code = False
for i, ln in enumerate(lines):
    if ln.startswith("```"):
        in_code = not in_code
    is_row = (not in_code) and ln.startswith("|")
    prev = out[-1] if out else ""
    prev_is_row = prev.startswith("|")
    if is_row and not prev_is_row and prev.strip() != "":
        out.append("")
    if (not is_row) and prev_is_row and ln.strip() != "" and not in_code:
        out.append("")
    if ln.startswith("```") and prev_is_row:
        out.insert(len(out), "")
    out.append(ln)
open(path, "w", encoding="utf-8").write("\n".join(out))
print("lines:", len(out))
