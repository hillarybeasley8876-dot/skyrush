import json, os, sys
# usage: python3 -I make_index.py <img_root> <out.md>  -> markdown index of downloaded reference photos
root, out = sys.argv[1], sys.argv[2]
NOTES = {
 "pillar_day_2022": "BEST pillar close-up: brushed steel + dark bronze kui-dragon relief, T-caps, planters",
 "interchange_ground_2025": "pillar between decks, white planter boxes on parapets, deck undersides",
 "interchange_night_6658": "interchange at night: warm lamps, lit pillar base, footbridge",
 "interchange_night_6663": "night under-deck view, stacked levels",
 "interchange_aerial_unsplash": "plan view of the stack (north = right side of image)",
 "interchange_multilevel_2007": "MISLABELLED on Commons: old Bund curved ramp at night (2007), golden facades",
 "yanzhong_interchange_jingan": "interchange from a tower, decks with greenery",
 "crossroads_NS_yanan_2018": "ramps + footbridge at the interchange",
 "yanan_elev_east_of_xizang_2025": "deck view: grey barriers, green gantries, median lamps",
 "yanan_elev_east_start_2025": "east end of Yan'an elevated at night: skyline-pattern lit walls",
 "nanpu_spiral_youspinmeround_2008": "Puxi spiral approach from above (HDR)",
 "nanpu_2019_01": "night: blue LED deck edge, orange-lit underside, white towers",
 "nanpu_night_2026": "night side view: white towers, blue deck line",
 "hsbc_customs_night_2026": "gold floodlit HSBC dome + Customs clock tower; blue-lit floodwall",
 "peace_hotel_boc_night_2026": "Peace Hotel green pyramid + Bank of China at night",
 "bund_day_panorama_2015": "Bund skyline at blue hour (wide)",
 "lujiazui_intersection_ring_2014": "Pearl Ring skybridge over the Lujiazui roundabout",
 "toll_g4_xinyang_2023": "typical flat toll canopy, lane signals, striped islands",
 "sinopec_hangzhou_2018": "Sinopec canopy: red fascia band, white columns",
 "tesla_v4_post_2024": "Tesla V4 post (white, slim, red logo)",
 "byd_flash_1500kw_2026": "BYD flash-charge demo canopy (teal, overhead cable)",
 "police_vw_patrol_2011": "Shanghai police livery (white + blue, 公安)",
 "road_name_sign_xianggang_rd_2016": "E-W street sign: blue top, white text, door numbers",
}
lines = ["# Shanghai reference photos - index", "",
         "All files <=1600 px JPEG, downloaded 2026-10-19 from Wikimedia Commons (licence per row; "
         "CC BY / BY-SA need attribution if ever shipped - these are REFERENCE ONLY, do not ship them).", ""]
for topic in sorted(os.listdir(root)):
    meta = os.path.join(root, topic, "_meta.jsonl")
    if not os.path.isfile(meta):
        continue
    lines += [f"## {topic}", "", "| file | what it shows | licence | author | date | source |", "|---|---|---|---|---|---|"]
    for ln in open(meta, encoding="utf-8"):
        m = json.loads(ln); slug = m["file"][:-4]
        note = NOTES.get(slug, m["title"].replace("File:", "")[:70])
        lines.append(f"| {m['file']} | {note} | {m['license']} | {m['author'][:30]} | {m['date'][:10]} | {m['page']} |")
    lines.append("")
open(out, "w", encoding="utf-8").write("\n".join(lines))
print(out, len(lines))
