extends RefCounted
## Builds the vapour-column tube shared by every nozzle.
##
## The mesh is an open tapered tube: length 1.0 along +Y (throat at y=0, tip at y=1), the
## throat radius is THROAT_FRACTION of the tip radius. A nozzle scales it to metres: the tip
## radius is 0.32 m for the rear and lift jets and 0.12 m for the yaw jets, and the length is
## 5 m, 7 m and 1.5 m (nozzle_fx.gd). The lift column is 0.05 m -> 0.32 m wide over 7 m, so
## the plume is 0.4-0.8 m wide three metres below the car (dossier §6.1).
##
## UV: x = angle around the tube, y = position along the jet (0 = throat, 1 = tip).

const RADIAL_SEGMENTS := 12
const RING_COUNT := 8
## The throat radius as a fraction of the tip radius.
const THROAT_FRACTION := 0.143

static var _cached: ArrayMesh = null


## Shared tube mesh (built once).
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
	for i in RING_COUNT:
		var v0: float = float(i) / float(RING_COUNT)
		var v1: float = float(i + 1) / float(RING_COUNT)
		var r0: float = lerpf(THROAT_FRACTION, 1.0, v0)
		var r1: float = lerpf(THROAT_FRACTION, 1.0, v1)
		for j in RADIAL_SEGMENTS:
			var u0: float = float(j) / float(RADIAL_SEGMENTS)
			var u1: float = float(j + 1) / float(RADIAL_SEGMENTS)
			var a0: float = TAU * u0
			var a1: float = TAU * u1
			var p00 := _p(r0, v0, a0)
			var p10 := _p(r1, v1, a0)
			var p11 := _p(r1, v1, a1)
			var p01 := _p(r0, v0, a1)
			var n0 := _n(a0)
			var n1 := _n(a1)
			_vtx(st, p00, n0, Vector2(u0, v0))
			_vtx(st, p10, n0, Vector2(u0, v1))
			_vtx(st, p11, n1, Vector2(u1, v1))
			_vtx(st, p00, n0, Vector2(u0, v0))
			_vtx(st, p11, n1, Vector2(u1, v1))
			_vtx(st, p01, n1, Vector2(u1, v0))
	return st.commit()


static func _p(radius: float, v: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, v, sin(angle) * radius)


## The wall normal of the tube: radial, so the shader's facing term is 1 where the wall looks
## straight at the camera and 0 at the silhouette.
static func _n(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


static func _vtx(st: SurfaceTool, pos: Vector3, nrm: Vector3, uv: Vector2) -> void:
	st.set_normal(nrm)
	st.set_uv(uv)
	st.add_vertex(pos)
