extends RefCounted
## Builds the jet-core cone mesh shared by every nozzle.
##
## The mesh is authored in a normalised space: length 1.0 along +Y (throat at y=0, tip at y=1),
## throat radius 0.0333 and tip radius 0.1. A nozzle scales it to metres, so the throat is
## 0.03 m and the tip 0.09 m at the 0.9 m reference length (dossier §6.3).
##
## UV: x = angle around the cone, y = position along the jet (0 = throat, 1 = tip). The jet shader
## uses UV.y for the length fade and the shock-diamond rings.

const RADIAL_SEGMENTS := 20
const RING_COUNT := 6
const THROAT_RADIUS := 0.0333
const TIP_RADIUS := 0.1

static var _cached: ArrayMesh = null


## Shared cone mesh (built once).
static func mesh() -> ArrayMesh:
	if _cached == null:
		_cached = _build()
	return _cached


## Drops the cached mesh. The engine's leak detector counts it at exit, so the owner releases
## it once the last rig is gone.
static func release() -> void:
	_cached = null


static func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_sides(st)
	_add_cap(st, false)
	_add_cap(st, true)
	return st.commit()


static func _add_sides(st: SurfaceTool) -> void:
	var slope: float = TIP_RADIUS - THROAT_RADIUS
	for i in RING_COUNT:
		var v0: float = float(i) / float(RING_COUNT)
		var v1: float = float(i + 1) / float(RING_COUNT)
		var r0: float = lerpf(THROAT_RADIUS, TIP_RADIUS, v0)
		var r1: float = lerpf(THROAT_RADIUS, TIP_RADIUS, v1)
		for j in RADIAL_SEGMENTS:
			var u0: float = float(j) / float(RADIAL_SEGMENTS)
			var u1: float = float(j + 1) / float(RADIAL_SEGMENTS)
			var a0: float = TAU * u0
			var a1: float = TAU * u1
			var p00 := _p(r0, v0, a0)
			var p10 := _p(r1, v1, a0)
			var p11 := _p(r1, v1, a1)
			var p01 := _p(r0, v0, a1)
			_vtx(st, p00, _normal(p00, slope), Vector2(u0, v0))
			_vtx(st, p10, _normal(p10, slope), Vector2(u0, v1))
			_vtx(st, p11, _normal(p11, slope), Vector2(u1, v1))
			_vtx(st, p00, _normal(p00, slope), Vector2(u0, v0))
			_vtx(st, p11, _normal(p11, slope), Vector2(u1, v1))
			_vtx(st, p01, _normal(p01, slope), Vector2(u1, v0))


## Flat disc closing the throat (bottom) or the tip (top).
static func _add_cap(st: SurfaceTool, tip: bool) -> void:
	var v: float = 1.0 if tip else 0.0
	var r: float = TIP_RADIUS if tip else THROAT_RADIUS
	var n := Vector3(0, 1, 0) if tip else Vector3(0, -1, 0)
	for j in RADIAL_SEGMENTS:
		var u0: float = float(j) / float(RADIAL_SEGMENTS)
		var u1: float = float(j + 1) / float(RADIAL_SEGMENTS)
		var p0 := Vector3(cos(TAU * u0) * r, v, sin(TAU * u0) * r)
		var p1 := Vector3(cos(TAU * u1) * r, v, sin(TAU * u1) * r)
		var c := Vector3(0, v, 0)
		if tip:
			_vtx(st, p0, n, Vector2(u0, v))
			_vtx(st, p1, n, Vector2(u1, v))
			_vtx(st, c, n, Vector2(0.5, v))
		else:
			_vtx(st, p1, n, Vector2(u1, v))
			_vtx(st, p0, n, Vector2(u0, v))
			_vtx(st, c, n, Vector2(0.5, v))


static func _p(radius: float, v: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, v, sin(angle) * radius)


## Outward normal of the conical side wall at a point.
static func _normal(p: Vector3, slope: float) -> Vector3:
	var radial := Vector3(p.x, 0, p.z)
	if radial.length() < 0.0001:
		return Vector3(0, 1, 0)
	radial = radial.normalized()
	return Vector3(radial.x, -slope, radial.z).normalized()


static func _vtx(st: SurfaceTool, pos: Vector3, nrm: Vector3, uv: Vector2) -> void:
	st.set_normal(nrm)
	st.set_uv(uv)
	st.add_vertex(pos)
