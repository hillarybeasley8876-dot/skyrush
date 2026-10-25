"""The rules that sort the faces of a source model into the parts and roles of the car contract.

A source function (real_sources.py) gets a Ctx: the faces of the working mesh as arrays (real_mesh.Faces), already in the game
frame (nose at +Y, right at +X, ground at z = 0, metres). It names the node and the role of every face:

  node   Body, Hood, Bumper_F, Bumper_R, Mirror_L, Mirror_R, Glass, the placeholders "wheel" (split into the four Wheel_* by
         the quadrant of the face) and "lamp" (Lamp_F in front of the middle of the car, Lamp_R behind it), or "drop"; a
         node "A~b" is a piece of the part A that is decimated on its own;
  role   paint, black, matte, chrome, silver, glass, lens (a lamp lens: the head lens in Lamp_F, the tail and brake lenses
         in Lamp_R), amber, reverse, housing, tyre, rim, or a role of a source (cargo, roof, display). convert_real.diet()
         merges the trims into one black and moves the housings, indicators and reversing lenses to the Body.

The helpers find the usual parts from the geometry where the source has no object of its own for them: the mirrors (the
small parts that stick out of the side of the body in the front half), the bumpers (what is in front of the front wheels and
under the head lamps, behind the rear wheels and under the tail lamps) and the bonnet (the upward faces of the paint between
the windscreen and the nose).
"""
import numpy as np

from real_mesh import components, local_components


class Ctx:
    def __init__(self, faces, model_id):
        self.f = faces
        self.model = model_id
        n = faces.n
        self.node = np.full(n, "", dtype=object)
        self.role = np.full(n, "", dtype=object)
        self.notes = []
        self.backing = []       # (node, lo, hi): dark plates behind the openings of a grille, see backing()
        lo = faces.lo.min(axis=0)
        hi = faces.hi.max(axis=0)
        self.lo, self.hi = lo, hi
        self.length = hi[1] - lo[1]
        self.width = hi[0] - lo[0]
        self.height = hi[2]

    # -------------------------------------------------------------------------------------------- selections
    def src(self, *names):
        """The faces whose source object name contains one of the names."""
        out = np.zeros(self.f.n, dtype=bool)
        for name in names:
            out |= np.array([name in s for s in self.f.source], dtype=bool)
        return out

    def mat(self, *names):
        """The faces whose source material name contains one of the names."""
        out = np.zeros(self.f.n, dtype=bool)
        for name in names:
            out |= np.array([name in s for s in self.f.material], dtype=bool)
        return out

    def free(self):
        """The faces that have no node yet."""
        return self.node == ""

    def uv_box(self, u, v):
        """The textured faces whose centre in the UV space of their texture is inside the ranges (an area of an atlas)."""
        uv = self.f.uv
        return (self.f.textured == 1) & (uv[:, 0] >= u[0]) & (uv[:, 0] <= u[1]) & (uv[:, 1] >= v[0]) & (uv[:, 1] <= v[1])

    def set(self, mask, node=None, role=None):
        if node is not None:
            self.node[mask] = node
        if role is not None:
            self.role[mask] = role
        return int(mask.sum())

    def drop(self, mask):
        self.set(mask, "drop", "drop")

    # -------------------------------------------------------------------------------------------- colours
    def by_colour(self, mask, protos, node=None):
        """Gives every selected face the role of the nearest prototype colour: protos = {role: [hex, ...]}."""
        idx = np.nonzero(mask)[0]
        if len(idx) == 0:
            return
        roles = []
        cols = []
        for role, hexes in protos.items():
            for h in hexes:
                roles.append(role)
                cols.append([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
        cols = np.array(cols)
        rgb = self.f.rgb[idx]
        d = ((rgb[:, None, :] - cols[None, :, :]) ** 2).sum(axis=2)
        pick = d.argmin(axis=1)
        self.role[idx] = np.array(roles, dtype=object)[pick]
        if node is not None:
            self.node[idx] = node

    def survey(self, mask, label=""):
        """Prints the colours under the selected faces (quantised, by area): to choose the prototypes of a source."""
        idx = np.nonzero(mask)[0]
        bins = {}
        for i in idx:
            q = tuple(int(round(v * 15)) for v in self.f.rgb[i])
            a, n = bins.get(q, (0.0, 0))
            bins[q] = (a + self.f.area[i], n + 1)
        total = sum(a for a, _ in bins.values()) or 1.0
        print("   SURVEY %s: %d faces" % (label, len(idx)))
        for q, (a, n) in sorted(bins.items(), key=lambda kv: -kv[1][0])[:14]:
            print("      #%02x%02x%02x  %5.1f %%  %d faces" % (q[0] * 17, q[1] * 17, q[2] * 17, 100.0 * a / total, n))

    # -------------------------------------------------------------------------------------------- the wheels and the lamps
    def axles(self):
        """{'front': (y, radius, z), 'rear': (y, radius, z)} from the faces of the node 'wheel'."""
        w = self.node == "wheel"
        if not w.any():
            raise RuntimeError("%s: no wheel faces" % self.model)
        c = self.f.centre
        out = {}
        for key, sel in (("front", c[:, 1] > 0.0), ("rear", c[:, 1] <= 0.0)):
            m = w & sel
            lo = self.f.lo[m].min(axis=0)
            hi = self.f.hi[m].max(axis=0)
            out[key] = ((lo[1] + hi[1]) * 0.5, (hi[2] - lo[2]) * 0.5, (hi[2] + lo[2]) * 0.5)
        return out

    def lamp_bounds(self, front, lens_only=False):
        """(lo, hi) of the lamp faces of one end (only the lenses with lens_only), or None."""
        lamp = np.array([n.startswith("lamp") for n in self.node], dtype=bool)
        m = lamp & ((self.f.centre[:, 1] > 0.0) if front else (self.f.centre[:, 1] <= 0.0))
        if lens_only:
            m &= self.role == "lens"
        if not m.any():
            return None
        return self.f.lo[m].min(axis=0), self.f.hi[m].max(axis=0)

    # -------------------------------------------------------------------------------------------- mirrors
    def side(self, mask, below):
        """The half width of the body: the |x| that 99.5 % of the selected faces under the height `below` stay inside."""
        m = mask & (self.f.centre[:, 2] < below)
        x = np.abs(np.concatenate([self.f.lo[m][:, 0], self.f.hi[m][:, 0]]))
        return float(np.percentile(x, 99.5))

    def mirrors(self, mask, below=None, min_z=None, max_size=0.75, margin=0.03, front_of=None):
        """Marks the mirrors among the selected faces: the connected parts in the front half that reach `margin` beyond
        the side of the body (measured under the height `below`) and are not bigger than `max_size`."""
        below = below if below is not None else 0.62 * self.height
        min_z = min_z if min_z is not None else 0.45 * self.height
        front_of = front_of if front_of is not None else -0.05 * self.length
        side = self.side(mask, below)
        found = {"Mirror_L": 0, "Mirror_R": 0}
        for part, idx in components(mask, self.f.part).items():
            lo = self.f.lo[idx].min(axis=0)
            hi = self.f.hi[idx].max(axis=0)
            size = hi - lo
            centre = (lo + hi) * 0.5
            out = max(-lo[0], hi[0])
            if out < side + margin or size.max() > max_size or centre[2] < min_z or centre[1] < front_of:
                continue
            if abs(centre[0]) < side - 0.3:
                continue
            name = "Mirror_L" if centre[0] < 0.0 else "Mirror_R"
            self.node[idx] = name
            found[name] += len(idx)
        self.notes.append("mirrors: side %.3f m, faces L %d R %d" % (side, found["Mirror_L"], found["Mirror_R"]))
        if not found["Mirror_L"] or not found["Mirror_R"]:
            raise RuntimeError("%s: mirrors not found (side %.3f): %s" % (self.model, side, found))
        return side

    # -------------------------------------------------------------------------------------------- bumpers and bonnet
    def bumpers(self, mask, front_top, rear_top, front_gap=0.06, rear_gap=0.06, front=True, rear=True, depth=None):
        """Bumper_F: the selected faces in front of the front wheel arches and under `front_top`; Bumper_R: behind the rear
        wheel arches and under `rear_top`. With `depth`, a bumper only reaches that far from its end of the car (a bus)."""
        ax = self.axles()
        c = self.f.centre
        if front:
            fy = ax["front"][0] + ax["front"][1] + front_gap
            if depth is not None:
                fy = max(fy, self.hi[1] - depth)
            self.set(mask & (c[:, 1] > fy) & (c[:, 2] < front_top), "Bumper_F")
        if rear:
            ry = ax["rear"][0] - ax["rear"][1] - rear_gap
            if depth is not None:
                ry = min(ry, self.lo[1] + depth)
            self.set(mask & (c[:, 1] < ry) & (c[:, 2] < rear_top), "Bumper_R")

    def hood(self, mask, back_y, min_z, half_x, min_nz=0.3, keep_largest=True):
        """Hood: the upward faces of the selection in front of `back_y`, above `min_z` and within |x| < half_x (the largest
        connected piece of them)."""
        c = self.f.centre
        m = mask & (c[:, 1] > back_y) & (c[:, 2] > min_z) & (np.abs(c[:, 0]) < half_x) & (self.f.normal[:, 2] > min_nz)
        if keep_largest and m.any():
            parts = components(m, self.f.part)
            best = max(parts.values(), key=lambda idx: self.f.area[idx].sum())
            m = np.zeros(self.f.n, dtype=bool)
            m[best] = True
        self.set(m, "Hood")
        return int(m.sum())

    def back_openings(self, mask, node, min_tris=60):
        """A grille that is a lattice (holes between its bars) shows the empty inside of the car: every connected piece of
        the selection gets a dark plate behind it (the converter adds the plates to `node`)."""
        for part, idx in local_components(mask, self.f.face_verts).items():
            if self.f.tris[idx].sum() < min_tris:
                continue
            lo = self.f.lo[idx].min(axis=0)
            hi = self.f.hi[idx].max(axis=0)
            self.backing.append((node, lo, hi))
        self.notes.append("backing: %d plates behind the openings of %s" % (len(self.backing), node))

    def drop_inner_glass(self):
        """Drops the inner surface of the panes of a source that models both surfaces of every pane (the glass of the fleet
        is opaque: the inner surface is never seen). A pane is inner when its normal looks towards the middle of the glass
        house; nothing is dropped unless 30-70 % of the glass looks inwards (a source with one surface per pane)."""
        glass = self.node == "Glass"
        if not glass.any():
            return 0
        c = self.f.centre
        lo = self.f.lo[glass].min(axis=0)
        hi = self.f.hi[glass].max(axis=0)
        mid = (lo + hi) * 0.5
        out = c - np.array([0.0, mid[1], mid[2]])
        inner = glass & ((self.f.normal * out).sum(axis=1) < 0.0)
        share = self.f.area[inner].sum() / max(self.f.area[glass].sum(), 1e-9)
        if 0.3 < share < 0.7:
            self.drop(inner)
            self.notes.append("glass: dropped the inner surface (%d faces, %.0f %% of the area)" % (int(inner.sum()),
                                                                                                   100.0 * share))
            return int(inner.sum())
        self.notes.append("glass: one surface per pane (%.0f %% looks inwards)" % (100.0 * share))
        return 0

    def windscreen_base(self):
        """The y of the lower (front) edge of the windscreen: the front-most point of the upward-looking glass."""
        g = (self.node == "Glass") & (self.f.normal[:, 1] > 0.25) & (self.f.centre[:, 1] > 0.0)
        if not g.any():
            return None
        return float(self.f.hi[g][:, 1].max())

    def check(self):
        """Every face has a node and a role."""
        missing = (self.node == "") | (self.role == "")
        if missing.any():
            sources = sorted(set(self.f.source[missing]))
            raise RuntimeError("%s: %d faces without a node or a role (%s)" % (self.model, int(missing.sum()), sources))
