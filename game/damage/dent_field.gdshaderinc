// SKYRUSH - the dent field of dossier 7.5 A, shared by the damage paint and the damage
// basic shader. INCLUDE this file in a spatial shader to give every surface of a car the
// same displacement field.
//
// The field lives in the space of the CAR, not in the space of the mesh: every surface of
// the car (the paint, the black trim, the door card, the lamp lens) is pushed by the same
// vector, so the paint never sinks behind the trim that did not move. The mesh finds its
// place in the car with the instance uniform `car_from_obj` (the mesh -> the car), which
// is rigid, so the inverse of its rotation is its transpose.

uniform vec4 dent_pos[8];   // xyz = the point in car space, w = the radius (0 = the slot is free)
uniform vec4 dent_dir[8];   // xyz = the push direction in car space, w = the depth (m)
uniform float dent_scale : hint_range(0.5, 2.0) = 1.0;
uniform float crumple_strength : hint_range(0.0, 1.0) = 0.2;
uniform float crumple_scale : hint_range(1.0, 60.0) = 14.0;
uniform float damage_enabled : hint_range(0.0, 1.0) = 0.0;
// The place of the mesh in the car, as four rows: Godot does not allow a matrix as an
// instance uniform, and the field of the car is the same for every surface of the car.
instance uniform vec4 car_from_obj_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 car_from_obj_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 car_from_obj_z = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec4 car_from_obj_o = vec4(0.0, 0.0, 0.0, 1.0);

// The transform of the mesh in the space of the car.
mat4 car_from_obj_matrix() {
	return mat4(car_from_obj_x, car_from_obj_y, car_from_obj_z, car_from_obj_o);
}

// The limits of the review (dossier 7.5 A): the crumple of the vertex is at most 1 cm and
// the tilt of the bowl at most 25 degrees (|grad| <= 0.47).
const float CRUMPLE_MAX = 0.006;
const float GRAD_MAX = 0.47;

// A cheap 3D value noise (the crumple of a dented panel).
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.x),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.x), f.z);
}

// The centre and the direction of one dent, in the space of the mesh.
void dent_slot(int i, out vec3 centre, out vec3 dir, out float depth, out float radius) {
	mat3 inv_rot = transpose(mat3(car_from_obj_matrix()));
	centre = inv_rot * (dent_pos[i].xyz - car_from_obj_o.xyz);
	dir = inv_rot * normalize(dent_dir[i].xyz);
	depth = dent_dir[i].w * dent_scale;
	radius = dent_pos[i].w;
}

// The displacement of a vertex by the whole field, in the space of the mesh.
vec3 dent_displace(vec3 obj_pos) {
	if (damage_enabled < 0.5) {
		return obj_pos;
	}
	vec3 p = obj_pos;
	for (int i = 0; i < 8; i++) {
		if (dent_pos[i].w <= 0.0) {
			continue;
		}
		vec3 centre;
		vec3 dir;
		float depth;
		float radius;
		dent_slot(i, centre, dir, depth, radius);
		float dist = distance(obj_pos, centre);
		float f = 1.0 - smoothstep(0.0, radius, dist);
		if (f <= 0.0) {
			continue;
		}
		float push = depth * f * f;
		// The crumple of a folded panel, at most 1 cm.
		float crumple = value_noise(obj_pos * crumple_scale) * 2.0 - 1.0;
		push += clamp(crumple_strength * depth * f * crumple, -CRUMPLE_MAX, CRUMPLE_MAX);
		p += dir * push;
	}
	return p;
}

// The gradient of the bowl (the surface rises outwards, so the normal tilts towards the
// centre of the dent) and the depth of the deepest dent, in the space of the mesh.
vec3 dent_gradient(vec3 obj_pos, out float deepest, out float depth_of_deepest) {
	deepest = 0.0;
	depth_of_deepest = 0.0;
	vec3 grad = vec3(0.0);
	if (damage_enabled < 0.5) {
		return grad;
	}
	for (int i = 0; i < 8; i++) {
		if (dent_pos[i].w <= 0.0) {
			continue;
		}
		vec3 centre;
		vec3 dir;
		float depth;
		float radius;
		dent_slot(i, centre, dir, depth, radius);
		vec3 to_centre = obj_pos - centre;
		float dist = length(to_centre);
		if (dist > radius) {
			continue;
		}
		float t = clamp(dist / max(radius, 0.001), 0.0, 1.0);
		float f = 1.0 - smoothstep(0.0, 1.0, t);
		// The derivative of the bowl depth with respect to the distance.
		float dfdd = -6.0 * t * (1.0 - t) / max(radius, 0.001);
		vec3 radial = dist > 0.0001 ? to_centre / dist : vec3(0.0, 0.0, 1.0);
		grad += radial * (-2.0 * f * dfdd * depth);
		if (f > deepest) {
			deepest = f;
			depth_of_deepest = depth;
		}
	}
	// The tilt of the bowl is capped at 25 degrees.
	float g = length(grad);
	if (g > GRAD_MAX) {
		grad *= GRAD_MAX / g;
	}
	return grad;
}
