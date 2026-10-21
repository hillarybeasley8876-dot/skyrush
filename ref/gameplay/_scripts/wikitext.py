"""Extract wikitext from a MediaWiki parse API JSON file. Usage: wikitext.py in.json out.txt"""
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if "parse" not in d:
    open(sys.argv[2], "w").write("ERROR " + json.dumps(d)[:300] + "\n")
    sys.exit(0)
t = d["parse"]["wikitext"]["*"]
t = re.sub(r"<ref[^>]*?/>", "", t)
t = re.sub(r"<ref.*?</ref>", "", t, flags=re.S)
t = re.sub(r"\[\[(?:File|Image):[^\]]*\]\]", "", t)
t = re.sub(r"\[\[([^\]|]*\|)?([^\]]*)\]\]", r"\2", t)
t = re.sub(r"'''?", "", t)
open(sys.argv[2], "w", encoding="utf-8").write(t)
