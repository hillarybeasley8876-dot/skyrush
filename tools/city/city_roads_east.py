"""city_roads_east — the Lujiazui / Pudong roads and the Yan'an E. Rd tunnel.

The geometry comes from the dossier §10.3 and §4 (the tunnel portals and the
lowest road level Y = -28 under the river).
"""
from city_road import Road


def century_ave():
    """Century Avenue, 100 m corridor, magnolia lamps."""
    plan = [(759.0, -462.4), (786.2, -475.1), (997.9, -380.8), (1099.9, -309.4),
            (1250.3, -249.0), (1341.5, -195.5), (1390.5, -181.0),
            (1540.0, -78.2), (1725.0, 51.0)]
    return Road("century_ave", "世纪大道", "Century Avenue", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=4, lanes_back=4, lane_width=3.75, median=10.0,
                shoulder=0.5, sidewalk=4.0, speed_kmh=70,
                style={"parapet": "none", "lamps": "magnolia", "trees": "plane"},
                notes="100 m corridor; the north/side green strips are park "
                      "lots (dossier 6.3).")


def lujiazui_ring_rd():
    """Lujiazui Ring Road, closed loop around the Lujiazui core."""
    plan = [(730.6, -498.9), (803.2, -630.7), (1070.1, -838.9), (1196.0, -682.5),
            (1263.1, -578.0), (1312.0, -422.4), (1349.0, -230.3),
            (1362.5, -28.9), (1333.0, 2.5), (786.2, -103.7), (730.1, -192.9),
            (717.4, -277.1), (710.2, -412.2), (730.6, -498.9)]
    return Road("lujiazui_ring_rd", "陆家嘴环路", "Lujiazui Ring Rd", "surface",
                plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=1.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=60,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="The west side of the loop stands 3 m east of the old "
                      "line, so it grazes the mouth of the Yan'an tunnel no "
                      "more.")


def pudong_south_rd():
    """Pudong South Rd, re-aligned close to the river."""
    plan = [(1540.0, -78.2), (1600.0, 100.0), (1650.0, 500.0), (1680.0, 900.0),
            (1690.0, 1280.0)]
    return Road("pudong_south_rd", "浦东南路", "Pudong South Rd", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=3, lanes_back=3, lane_width=3.75, median=1.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=60,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="The Nanpu Pudong descending loop lands here at "
                      "(1690, 1280).")


def yanan_tunnel():
    """Yan'an East Rd Tunnel: Puxi portal -> -28 m under the river -> Pudong.

    No street may cross the open trough of a ramp (between the ground and the
    6 m a bore needs over its road): a street that did stood on a ramp only
    0.2-1 m deep, and the walls of the ramp stood across the street.  So the
    tunnel starts at the east end of Fujian Rd (the old first 106 m ran under
    Fujian Rd and the Henan Rd link, at 0-1.3 m) and keeps 25 m off the centre
    of the Yan'an Rd surface road until it is 6 m down; in Pudong it comes up
    before the Lujiazui Ring Rd and crosses it at grade (it ran 0.2-0.6 m
    under the ring road).  Lujiazui West Rd still crosses it 6 m over its road.
    tools/city/check_tunnel_portals.py checks all of it.
    Rising 28 m between those two points needs a vertical curve of 1 % per
    10 m (radius ~1000 m, 0.1 g at 120 km/h) instead of the 0.5 % of a street.
    """
    plan = [(-360.0, 210.0), (-300.0, 198.0), (-225.0, 170.0), (-163.2, 118.1), (-37.4, 84.1),
            (1.7, 26.3), (150.0, -150.0), (255.9, -196.6), (410.6, -332.3),
            (617.1, -454.8), (759.0, -462.4)]
    anchors = [("start", 0.0, 0.0), ("p", 150.0, -150.0, -28.0, 0.0),
               ("p", 715.0, -465.0, 0.0, 0.0), ("end", 0.0, 0.0)]
    return Road("yanan_tunnel", "延安东路隧道", "Yan'an E. Rd Tunnel", "tunnel",
                plan, anchors, lanes_fwd=2, lanes_back=2, lane_width=3.5,
                median=7.5, shoulder=0.5, speed_kmh=60,
                style={"parapet": "barrier", "lamps": "side", "trees": "none"},
                max_grade=0.048, kink=0.010,
                notes="Two 11 m bores 15 m apart, lowest road level Y=-28.0. "
                      "At grade from the Lujiazui Ring Rd to the Pudong end.")


def binjiang_ave():
    """Binjiang Ave: the 25 m riverside promenade road of Pudong (6.3)."""
    plan = [(300.0, -600.0), (420.0, -400.0), (520.0, -180.0), (600.0, 30.0),
            (660.0, 150.0)]
    return Road("binjiang_ave", "滨江大道", "Binjiang Ave", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.5, median=0.0,
                shoulder=0.5, sidewalk=4.0, speed_kmh=40,
                style={"parapet": "none", "lamps": "magnolia", "trees": "plane"},
                notes="Riverside promenade road, 25 m wide (dossier 6.3).")


def bund_tunnel():
    """Bund Tunnel: optional shortcut under the Bund, Y = -12."""
    plan = [(-180.0, 120.0), (-60.0, 20.0), (-60.0, -300.0), (-95.0, -700.0),
            (-110.0, -1100.0), (-120.0, -1200.0)]
    anchors = [("start", 0.0, 0.0), ("p", -95.0, -700.0, -12.0, 0.0),
               ("end", 0.0, 0.0)]
    return Road("bund_tunnel", "外滩隧道", "Bund Tunnel", "tunnel", plan, anchors,
                lanes_fwd=2, lanes_back=2, lane_width=3.5, median=1.0,
                shoulder=0.5, speed_kmh=60,
                style={"parapet": "barrier", "lamps": "side", "trees": "none"},
                max_grade=0.04)


def lujiabang_rd():
    """Lujiabang Rd: the south continuation of Zhongshan S Rd (dossier 3.3)."""
    plan = [(802.0, 1490.0), (770.0, 1560.0), (710.0, 1640.0), (650.0, 1720.0)]
    return Road("lujiabang_rd", "鲁班路", "Lujiabang Rd", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.5, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=40,
                style={"parapet": "none", "lamps": "side", "trees": "plane"})


def lujiazui_w_rd():
    """Lujiazui West Rd, the western side of the Lujiazui peninsula (6.3)."""
    plan = [(560.0, -700.0), (540.0, -480.0), (640.0, -260.0), (700.0, -40.0),
            (760.0, 140.0)]
    return Road("lujiazui_w_rd", "陆家嘴西路", "Lujiazui West Rd", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.75, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=50,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="The road crosses the Yan'an tunnel 60 m further west, "
                      "where the tunnel is deep enough under it.")


def dongchang_rd():
    """Dongchang Rd, the Bund's back street (dossier 7.2 / 5.2)."""
    plan = [(-200.0, -20.0), (-260.0, -260.0), (-300.0, -520.0), (-290.0, -700.0)]
    return Road("dongchang_rd", "东长治路", "Dongchang Rd", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=1, lanes_back=1, lane_width=3.5, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=30,
                style={"parapet": "none", "lamps": "heritage", "trees": "plane"})


def yincheng_rd():
    """Yincheng Rd, the road that meets the Pudong tunnel portal (dossier 4)."""
    plan = [(700.0, -700.0), (740.0, -560.0), (759.0, -462.4)]
    return Road("yincheng_rd", "银城路", "Yincheng Rd", "surface", plan,
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.75, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=40,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="The Pudong portal of the Yan'an E. Rd tunnel.")


def fujian_rd_puxi():
    """Fujian Rd at the Puxi tunnel portal (dossier 4)."""
    plan = [(-560.0, 150.0), (-459.8, 184.4), (-360.0, 210.0)]
    return Road("st_fujian_portal", "福建路", "Fujian Rd (tunnel portal)",
                "surface", plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=2, lanes_back=2, lane_width=3.5, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=40,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="The Puxi portal of the Yan'an E. Rd tunnel.")


def henan_portal_link():
    """The short link from the tunnel's Puxi portal to Henan Rd.

    The portal of the Yan'an E. Rd tunnel stands at (-459.8, 184.4) and
    Henan Rd runs at x = -408: this link joins the two, so the traffic that
    comes out of the tunnel can go north on Henan Rd.
    """
    plan = [(-459.8, 184.4), (-408.0, 195.7)]
    return Road("st_henan_portal", "河南路隧道接线", "Henan Rd portal link",
                "surface", plan, [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=1, lanes_back=1, lane_width=3.75, median=0.0,
                shoulder=0.5, sidewalk=3.0, speed_kmh=30,
                style={"parapet": "none", "lamps": "side", "trees": "plane"},
                notes="Joins the Puxi tunnel portal with Henan Rd.")
