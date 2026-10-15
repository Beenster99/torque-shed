class_name BlastGrit
extends RefCounted
## The sand in a blast cabinet stays in the cabinet. The jet and the grit that ricochets off the
## engine are GPU particles with their own process shader: they fly, fall and bounce off the
## engine like before, and on every step each grain is also held inside the chamber, the floor,
## roof, sides, back, low front and the sloping glass, bouncing back off whichever it would cross.
## However fast a grain goes or however long a step is, it can't leave. The same sum is here in
## GDScript (contain) for the tests.

## Grains stay this far inside the chamber's walls.
const MARGIN := 0.02

const SHADER := """
shader_type particles;

uniform vec3 direction = vec3(0.0, 0.0, -1.0);
uniform float spread = 3.0;
uniform float speed_min = 1.0;
uniform float speed_max = 2.0;
uniform vec3 gravity = vec3(0.0, -9.8, 0.0);
uniform float damping_min = 0.0;
uniform float damping_max = 0.0;
uniform float emit_radius = 0.004;
uniform float scale_min = 1.0;
uniform float scale_max = 1.0;
uniform float bounce = 0.3;
uniform float friction = 0.25;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D color_ramp : repeat_disable;
// The cabinet's own space: world to it and back.
uniform mat4 to_local;
uniform mat4 to_world;
// The chamber's walls in the cabinet's space: inward normal (xyz) and offset (w). Inside is
// where dot(normal, point) >= offset for every one of them.
uniform vec4 walls[7];

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_POSITION) {
		vec3 off = vec3(rand_from_seed(seed), rand_from_seed(seed), rand_from_seed(seed)) * 2.0 - 1.0;
		float sc = mix(scale_min, scale_max, rand_from_seed(seed));
		TRANSFORM = EMISSION_TRANSFORM * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(off * emit_radius, 1.0));
	}
	if (RESTART_VELOCITY) {
		float a = radians(spread) * sqrt(rand_from_seed(seed));
		float b = 6.2831853 * rand_from_seed(seed);
		vec3 dir = normalize(direction);
		vec3 side = normalize(abs(dir.y) < 0.99 ? cross(dir, vec3(0.0, 1.0, 0.0)) : cross(dir, vec3(1.0, 0.0, 0.0)));
		vec3 up = cross(side, dir);
		vec3 d = dir * cos(a) + (side * cos(b) + up * sin(b)) * sin(a);
		VELOCITY = normalize((EMISSION_TRANSFORM * vec4(d, 0.0)).xyz) * mix(speed_min, speed_max, rand_from_seed(seed));
	}
	CUSTOM = vec4(rand_from_seed(seed), 0.0, 0.0, 0.0);
	COLOR = tint * texture(color_ramp, vec2(0.0, 0.0));
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	VELOCITY += gravity * DELTA;
	float damp = mix(damping_min, damping_max, CUSTOM.x);
	float spd = length(VELOCITY);
	if (spd > 0.0001) {
		VELOCITY = VELOCITY / spd * max(spd - damp * DELTA, 0.0);
	}
	if (COLLIDED) {
		// Off the engine (and the walls' colliders): bounce, losing some of it.
		TRANSFORM[3].xyz += COLLISION_NORMAL * COLLISION_DEPTH;
		float vn = dot(VELOCITY, COLLISION_NORMAL);
		if (vn < 0.0) {
			VELOCITY -= COLLISION_NORMAL * vn * (1.0 + bounce);
			VELOCITY -= (VELOCITY - COLLISION_NORMAL * dot(VELOCITY, COLLISION_NORMAL)) * friction;
		}
	}
	// Held inside the chamber: back onto any wall it's through, and bounced off any it would
	// cross on this step (the engine moves it on by VELOCITY * DELTA after this).
	vec3 p = (to_local * vec4(TRANSFORM[3].xyz, 1.0)).xyz;
	vec3 v = (to_local * vec4(VELOCITY, 0.0)).xyz;
	for (int k = 0; k < 2; k++) {
		for (int i = 0; i < 7; i++) {
			vec3 n = walls[i].xyz;
			float d = walls[i].w;
			float at = dot(n, p);
			if (at < d) {
				p += n * (d - at);
			}
			if (dot(n, p + v * DELTA) < d) {
				float vn = dot(v, n);
				if (vn < 0.0) {
					v -= n * vn * (1.0 + bounce);
					v -= (v - n * dot(v, n)) * friction;
				}
				// Still crossing (sliding along the wall): stop it going through.
				float left = dot(n, p + v * DELTA) - d;
				if (left < 0.0) {
					v -= n * left / max(DELTA, 0.0001);
				}
			}
		}
	}
	TRANSFORM[3].xyz = (to_world * vec4(p, 1.0)).xyz;
	VELOCITY = (to_world * vec4(v, 0.0)).xyz;
	COLOR = tint * texture(color_ramp, vec2(clamp(CUSTOM.y, 0.0, 1.0), 0.0));
	if (CUSTOM.y > 1.0) {
		ACTIVE = false;
	}
}
"""

static var _shader: Shader


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


## The chamber's walls for a cabinet model, in its own space: inward normal and offset
## (inside where normal.dot(point) >= offset), MARGIN in from the metal and the glass.
static func walls(model_id: String) -> PackedVector4Array:
	var inside := Equipment.blaster_inside(model_id)
	var floor_y := float(inside["floor"]) + MARGIN
	var roof := float(inside["roof"]) - MARGIN
	var hw := float(inside["half_w"]) - MARGIN
	var back := float(inside["back"]) + MARGIN
	var front := float(inside["front"]) - MARGIN
	var front_top := float(inside["front_top"])
	var glass_z := float(inside["glass_z"])
	var out := PackedVector4Array()
	out.append(Vector4(0.0, 1.0, 0.0, floor_y))
	out.append(Vector4(0.0, -1.0, 0.0, -roof))
	out.append(Vector4(1.0, 0.0, 0.0, -hw))
	out.append(Vector4(-1.0, 0.0, 0.0, -hw))
	out.append(Vector4(0.0, 0.0, 1.0, back))
	out.append(Vector4(0.0, 0.0, -1.0, -front))
	# The sloping glass, from the top of the low front up and back to the roof: inside is below
	# and behind it.
	var n := Vector3(0.0, -(float(inside["front"]) - glass_z), -(float(inside["roof"]) - front_top)).normalized()
	var on := Vector3(0.0, front_top, float(inside["front"]))
	out.append(Vector4(n.x, n.y, n.z, n.dot(on) + MARGIN))
	return out


## Whether a point (in the cabinet's space) is inside the chamber.
static func holds(walls_list: PackedVector4Array, p: Vector3, slack := 0.0001) -> bool:
	for w in walls_list:
		if Vector3(w.x, w.y, w.z).dot(p) < w.w - slack:
			return false
	return true


## One grain's step, as the shader does it: [position, velocity] after `delta`, held inside.
static func contain(walls_list: PackedVector4Array, p: Vector3, v: Vector3, delta: float, bounce := 0.3, friction := 0.25) -> Array:
	for _k in 2:
		for w in walls_list:
			var n := Vector3(w.x, w.y, w.z)
			var at := n.dot(p)
			if at < w.w:
				p += n * (w.w - at)
			if n.dot(p + v * delta) < w.w:
				var vn := v.dot(n)
				if vn < 0.0:
					v -= n * vn * (1.0 + bounce)
					v -= (v - n * v.dot(n)) * friction
				var left := n.dot(p + v * delta) - w.w
				if left < 0.0:
					v -= n * left / maxf(delta, 0.0001)
	return [p + v * delta, v]


## A process material for grains from `emitter`'s settings, held inside cabinet `model_id`.
static func material(model_id: String, settings: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	for key in settings:
		m.set_shader_parameter(key, settings[key])
	m.set_shader_parameter("walls", walls(model_id))
	m.set_shader_parameter("to_local", Projection(Transform3D()))
	m.set_shader_parameter("to_world", Projection(Transform3D()))
	return m


## Tells a cabinet's grain materials where the cabinet stands now (`xf`, its global transform).
static func place(m: ShaderMaterial, xf: Transform3D) -> void:
	if m == null:
		return
	m.set_shader_parameter("to_local", Projection(xf.affine_inverse()))
	m.set_shader_parameter("to_world", Projection(xf))
