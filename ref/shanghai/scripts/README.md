# scripts/ — how the Shanghai reference data was produced (2026-10-19)

Run from `/Users/minimax/m/skyrush/ref/shanghai`. Scripts that read downloaded data are run with
`python3 -I` (or `-E -s` when they import `maplib`); downloads live only in `dl/` and `img/`.

| step | command | output |
|---|---|---|
| Wikipedia text | `./scripts/wiki_extract.sh zh dl/<new_dir> "<title>" ...` then `python3 -I scripts/show_extract.py <json>` | plain-text extracts |
| OSM | `curl --data-urlencode data@scripts/overpass_qN.txt <overpass endpoint> -o dl/osm_N/qN.json` | raw OSM JSON |
| OSM inspection | `osm_summary.py`, `osm_lines.py`, `osm_waylist.py`, `osm_buildings.py`, `osm_junction.py`, `river_perp.py` | printed real-frame coordinates |
| river | `python3 -E -s scripts/build_river.py dl/osm_1/q1.json dl/osm_5/q5.json build/river.json` | banks/creek in GAME frame |
| map | `python3 -E -s scripts/build_map.py build/river.json build/map_layout_v1.json` | full layout JSON |
| sketch | `python3 -E scripts/plot_map.py build/map_layout_v1.json build/map_sketch_v1.png` | top-down PNG |
| photos | `commons_search.py` / `commons_cat.py` to find, `commons_get.py img/<topic> slug=File:...` to fetch | `img/<topic>/*.jpg` + `_meta.jsonl` |
| photo index | `python3 -I scripts/make_index.py img img/INDEX.md` | `img/INDEX.md` |
| contact sheets | `python3 scripts/sheet.py <out.jpg> <cols> <tile_w> <imgs...>`, `crop_combine.py` | `sheets/*.jpg` |

`maplib.py` holds the frame definition (origin lat 31.23514, lon 121.48739) and the compression T.
