"""Colour tokens for the NPC fleet (unit: npc_cars).

Every colour is an sRGB hex token from ART.md §3 / ref/art §4.7-4.8 and is
converted to linear before it reaches a Blender socket (Blender colour inputs
are linear; feeding sRGB values straight in is what made the taxi render
#61C4C2 instead of #1E8C8A).
"""


def hex_lin(token):
    """'#RRGGBB' (sRGB) -> linear (r, g, b) floats."""
    t = token.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(t[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


# --- traffic paint (ref/art §4.7) ---
PAINT_WHITE = "#E8E8E6"
PAINT_BLACK = "#0E0F11"
PAINT_SILVER = "#9DA3A8"
PAINT_BLUE = "#1F3A5F"
PAINT_GREY = "#5A5F63"
POLICE_WHITE = "#F2F4F5"
TAXI_TEAL = "#1E8C8A"
TAXI_SKIRT = "#A9ADB1"

# --- police livery (ref/art §4.8) ---
POLICE_NAVY = "#1B2A4E"
POLICE_YELLOW = "#F5C400"

# --- lamps ---
LAMP_WHITE = "#EAF2FF"
LIDAR_CYAN = "#19E6FF"
LAMP_RED = "#FF2030"
POLICE_RED = "#FF2030"
POLICE_BLUE = "#2A5CFF"
LED_STREET = "#D9E8FF"
SODIUM_STREET = "#FFB46B"

# --- wheels ---
RIM_ALLOY = "#B9BDC3"
RIM_GUNMETAL = "#6E7276"
BRAKE_DISC = "#5B5D61"
TYRE_RUBBER = "#141619"

# --- dark trim / wells ---
TRIM_BLACK = "#121316"
WELL_BLACK = "#0B0B0D"
INNER_BLACK = "#0D0D0F"
GLASS_TINT = "#0A0E12"
GLOSS_BLACK = "#0B0E13"
PLATE_BLUE = "#1E4FB8"
PLATE_GREEN_TOP = "#2FA46B"
PLATE_GREEN_BOTTOM = "#0C6B43"
