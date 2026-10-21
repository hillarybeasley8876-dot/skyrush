#!/bin/zsh
# usage: wiki_extract.sh <lang> <outdir> <title1> [title2 ...]
# Fetches plain-text extracts of Wikipedia articles via the MediaWiki API (data only).
lang=$1; out=$2; shift 2
mkdir -p "$out"
UA="SkyrushRefBot/0.1 (research; https://github.com/hillarybeasley8876-dot/skyrush)"
for t in "$@"; do
  f="$out/${lang}_$(echo "$t" | tr ' /' '__').json"
  curl -s -m 30 -A "$UA" --get "https://${lang}.wikipedia.org/w/api.php" \
    --data-urlencode "action=query" --data-urlencode "prop=extracts" \
    --data-urlencode "explaintext=1" --data-urlencode "redirects=1" \
    --data-urlencode "format=json" --data-urlencode "titles=$t" -o "$f"
  echo "$t -> $(wc -c < "$f") bytes"
  sleep 1
done
