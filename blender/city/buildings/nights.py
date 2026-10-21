"""The night parameters of a building.

The near facades are the shaders unit's material, but the parameters of a building
(how many of its windows are lit, whether the lit windows form bands and how warm
the light is) belong to the buildings unit: they are a property of the building, not
of the shader.  They go into the sidecar next to the building seed, so the world can
set the instance uniforms of the facade shader per building.

ART.md 11: an office lights 20-30 % of its windows in clustered floors and in cool
white; a residential block lights 15-25 % of them, scattered and warm.
"""
import zlib

# style -> (lit_ratio, band_ratio, cool_mix)
NIGHT = {
    "office_tower": (0.28, 0.25, 0.75),
    "residential_slab": (0.20, 0.05, 0.15),
    "midrise": (0.18, 0.08, 0.30),
    "heritage": (0.22, 0.10, 0.25),
    "neon_street": (0.24, 0.12, 0.35),
    "shikumen": (0.16, 0.04, 0.20),
    "industrial": (0.08, 0.02, 0.30),
    "park": (0.0, 0.0, 0.5),
    "plaza": (0.0, 0.0, 0.5),
}
DEFAULT = (0.18, 0.05, 0.30)


def params_for(style, seed):
    """The night parameters of one building (and its shader seed)."""
    lit, band, cool = NIGHT.get(style, DEFAULT)
    digest = zlib.crc32(("%s:%s" % (style, seed)).encode("utf-8"))
    # the per-building seed shifts the window pattern of the facade shader
    building_seed = (digest % 9973) / 9973.0
    # the ratios move a little from building to building
    jitter = ((digest >> 8) % 100) / 100.0 - 0.5
    return {"building_seed": round(building_seed, 4),
            "lit_ratio": round(max(0.0, min(1.0, lit + jitter * 0.08)), 3),
            "band_ratio": round(max(0.0, min(1.0, band + jitter * 0.04)), 3),
            "cool_mix": round(max(0.0, min(1.0, cool + jitter * 0.10)), 3)}
