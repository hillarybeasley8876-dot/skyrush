"""Convert a (possibly GBK) HTML file to readable text. Usage: html2txt.py in.html out.txt"""
import sys, re, html
from html.parser import HTMLParser

class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.out, self.skip = [], 0
    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript"):
            self.skip += 1
        if tag in ("p", "br", "div", "li", "tr", "h1", "h2", "h3", "h4", "td"):
            self.out.append("\n")
    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript") and self.skip:
            self.skip -= 1
    def handle_data(self, d):
        if not self.skip:
            self.out.append(d)

raw = open(sys.argv[1], "rb").read()
text = None
m = re.search(rb'charset=["\']?([A-Za-z0-9_-]+)', raw[:4000])
cands = ([m.group(1).decode()] if m else []) + ["utf-8", "gb18030"]
for enc in cands:
    try:
        text = raw.decode(enc)
        break
    except Exception:
        continue
if text is None:
    text = raw.decode("gb18030", errors="replace")
p = P()
p.feed(text)
s = html.unescape("".join(p.out))
s = re.sub(r"[ \t\r\f\v]+", " ", s)
s = re.sub(r"\n\s*\n+", "\n", s)
open(sys.argv[2], "w", encoding="utf-8").write(s.strip() + "\n")
