class_name SprayMarks
extends Node
## Wet paint coming up on a part as it's sprayed, drawn on the part itself (the way BlastMarks
## draws bare metal in the sandblaster). The space round the part is split into little cubes,
## each holding how many coats of paint have landed there and how much of that landed dry; that's
## a 3D texture an extra pass on the part's paintwork reads, so wherever the fan has been the coat
## comes up wet and glossy, thin where it's only had a dusting (the old surface showing through),
## rough and speckled where it landed dry from too far off, and sagging into drips where it's been
## laid on too thick. Missed bits show the surface under the coat: the old paint flatted back for
## the new coat to key to, grey primer, or (for lacquer) the colour without its wet gloss.
## The scan (set_scan) lights it up: red where it's missed, amber where it's thin, green where
## it's a good coat, purple where it's run and blue where it's gone on dry.
## Lives on the part's BikeModel and moves with it; restore() puts the part's own look back.

const VOXEL := 0.02          # metres per cube of the mask (bigger for a big part, see setup)
const MAX_DIM := 96
const COAT_MAX := 8.0        # coats a cube's byte can hold

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler3D mask : filter_linear, repeat_disable;
uniform mat4 to_model;
uniform vec3 mask_origin;
uniform vec3 mask_size;
uniform float voxel = 0.02;
uniform vec4 coat_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float coat_rough = 0.15;
uniform float coat_metal = 0.0;
uniform float clear_layer = 0.0;   // lacquer: the film is clear
uniform vec4 under_color : source_color = vec4(0.5, 0.5, 0.5, 0.0);  // what shows where it's missed; alpha: how much
uniform float under_rough = 0.85;
uniform float run_level = 4.0;      // coats before it runs
uniform float wet = 1.0;
uniform float scan = 0.0;
uniform float scan_t = 0.0;
uniform float flash = 0.0;

varying vec3 mpos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
	// A hair proud of the surface, so it draws over the part's own finish (and any bare metal).
	VERTEX += NORMAL * 0.0009;
	mpos = (to_model * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 uvw = (mpos - mask_origin) / mask_size;
	vec2 m = texture(mask, uvw).rg;
	float coats = m.r * 8.0;
	float dryf = m.g;
	// Too thick and it sags: drips run down from a patch that's over the run level, in streaks.
	float streak = smoothstep(0.35, 0.75, vnoise(vec3(mpos.x * 70.0, mpos.y * 4.0, mpos.z * 70.0)));
	float run = smoothstep(0.0, 1.2, coats - run_level);
	for (int k = 1; k <= 5; k++) {
		vec3 up = vec3(0.0, float(k) * voxel * 0.8, 0.0) / mask_size;
		float above = texture(mask, uvw + up).r * 8.0;
		run = max(run, smoothstep(0.0, 1.2, above - run_level) * streak * (1.0 - float(k) / 6.0));
	}
	// A ragged, misty edge where the fan stops; a dusting lets the old surface show through.
	float edge = vnoise(mpos * 160.0) * 0.6 + vnoise(mpos * 45.0) * 0.4;
	float film = smoothstep(0.06, 0.8, coats + (edge - 0.5) * 0.22);
	float grain = hash3(floor(mpos * 1100.0));
	// Dry spray: lands as a rough, chalky speckle rather than flowing out.
	float dry = dryf * step(0.05, coats);
	film *= mix(1.0, 0.55 + 0.45 * grain, dry);
	vec3 col = coat_color.rgb;
	col = mix(col, col * 0.75 + vec3(0.12), dry * 0.55);
	col *= 1.0 - 0.28 * run;
	float rough = mix(coat_rough, 0.06, wet * 0.65);
	rough = mix(rough, 0.95, dry * 0.9);
	rough = mix(rough, 0.04, run);
	float alpha;
	vec3 albedo;
	if (clear_layer > 0.5) {
		// Lacquer: a clear wet film over the colour, glossy where it's gone on.
		float a_film = film * (0.42 + 0.2 * wet) + run * 0.35;
		albedo = mix(under_color.rgb, col, film);
		alpha = max(under_color.a * (1.0 - film), a_film);
	} else {
		albedo = mix(under_color.rgb, col, film);
		alpha = max(under_color.a, max(film, run));
	}
	rough = mix(under_rough, rough, film);
	vec3 emit = vec3(0.6, 0.8, 1.0) * flash;
	if (scan > 0.0) {
		// Red: missed. Amber: thin. Green: a good coat. Purple: run. Blue: dry.
		vec3 sc = vec3(1.0, 0.1, 0.05);
		sc = mix(sc, vec3(1.0, 0.65, 0.05), step(0.05, coats));
		sc = mix(sc, vec3(0.15, 1.0, 0.35), step(0.8, coats));
		sc = mix(sc, vec3(0.3, 0.5, 1.0), step(0.5, dry));
		sc = mix(sc, vec3(0.8, 0.2, 1.0), step(run_level, coats));
		float band = smoothstep(0.92, 1.0, fract(mpos.y * 3.0 - scan_t * 0.8));
		albedo = mix(albedo, sc, 0.6 * scan);
		emit += sc * scan * (0.3 + 1.2 * band + (1.0 - step(0.8, coats)) * 0.5);
		alpha = max(alpha, scan * 0.9);
	}
	ALBEDO = albedo + vec3(flash * 0.4);
	METALLIC = mix(0.0, coat_metal, film);
	ROUGHNESS = clamp(rough + grain * 0.04, 0.0, 1.0);
	CLEARCOAT = film * (1.0 - dry) * mix(0.4, 1.0, max(wet, clear_layer));
	CLEARCOAT_ROUGHNESS = 0.05;
	EMISSION = emit;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""

static var _shader: Shader

var model: BikeModel
var slots: Array = []
var voxel := VOXEL
var origin := Vector3.ZERO       # the mask's corner, in the model's space
var dims := Vector3i.ONE
var coats := PackedFloat32Array()  # coats each cube has had (1 is a full, even coat)
var dry := PackedFloat32Array()    # how much of that landed dry
var run_level := 4.0
var _tex: ImageTexture3D
var _bytes := PackedByteArray()
var _dirty := false
var _since_upload := 0.0
var _mats := {}                  # slot -> ShaderMaterial
var _restore := []               # [mesh, its own material, chain tail to unhook or null]
var _scan := 0.0
var _scan_on := false
var _scan_t := 0.0
var _flash := 0.0
var _wet := 1.0
var _drying := false


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## Covers the parts in `slots` of `part_model` and lays a pass over their paintwork.
## `look`: {color (the coat), rough, metal, clear (lacquer), under (what missed bits show, with
## its alpha as how much it hides the part), under_rough}.
func setup(part_model: BikeModel, part_slots: Array, runs: float, look: Dictionary) -> bool:
	model = part_model
	run_level = runs
	var box := AABB()
	var first := true
	for slot in part_slots:
		var b := model.slot_bounds(slot)
		if b.size == Vector3.ZERO:
			continue
		slots.append(slot)
		box = b if first else box.merge(b)
		first = false
	if first:
		return false
	# A big part (a whole frame) gets bigger cubes, so the mask still fits.
	voxel = maxf(VOXEL, maxf(box.size.x, maxf(box.size.y, box.size.z)) / float(MAX_DIM - 6))
	box = box.grow(voxel * 2.0)
	origin = box.position
	dims = Vector3i(clampi(ceili(box.size.x / voxel), 2, MAX_DIM), clampi(ceili(box.size.y / voxel), 2, MAX_DIM),
		clampi(ceili(box.size.z / voxel), 2, MAX_DIM))
	coats.resize(dims.x * dims.y * dims.z)
	coats.fill(0.0)
	dry.resize(coats.size())
	dry.fill(0.0)
	_bytes.resize(coats.size() * 2)
	_bytes.fill(0)
	_tex = ImageTexture3D.new()
	_tex.create(Image.FORMAT_RG8, dims.x, dims.y, dims.z, false, _images())
	for slot in slots:
		var m := ShaderMaterial.new()
		m.shader = shader()
		m.render_priority = 2
		m.set_shader_parameter("mask", _tex)
		m.set_shader_parameter("mask_origin", origin)
		m.set_shader_parameter("mask_size", Vector3(dims) * voxel)
		m.set_shader_parameter("voxel", voxel)
		m.set_shader_parameter("run_level", run_level)
		set_look_on(m, look)
		_mats[slot] = m
		var meshes: Array = model._slot_meshes.get(slot, [])
		# Only the painted surfaces take the coat (not the rubber, chrome or cables), unless
		# nothing on the part is painted, when the lot does.
		var painted := meshes.filter(func(mi): return is_instance_valid(mi) and (mi as GeometryInstance3D).material_override != null \
			and (mi as GeometryInstance3D).material_override.has_meta("paint_surface"))
		for mi in (painted if not painted.is_empty() else meshes):
			var g := mi as GeometryInstance3D
			if g == null or not is_instance_valid(g):
				continue
			var own := g.material_override
			if own == null:
				continue
			var mine := own.duplicate() as Material
			# Over anything already drawn on top of it (bare metal from the sandblaster).
			var tail: Material = mine
			var hooked: Material = null
			while tail.next_pass != null:
				tail = tail.next_pass
				hooked = tail
			tail.next_pass = m
			_restore.append([g, own, hooked])
			g.material_override = mine
	_update_transform()
	return not _restore.is_empty()


## Sets how the coat and what's under it look on one of the pass materials.
static func set_look_on(m: ShaderMaterial, look: Dictionary) -> void:
	var c: Color = look.get("color", Color(0.8, 0.1, 0.1))
	m.set_shader_parameter("coat_color", Color(c.r, c.g, c.b, 1.0))
	m.set_shader_parameter("coat_rough", float(look.get("rough", 0.15)))
	m.set_shader_parameter("coat_metal", float(look.get("metal", 0.0)))
	m.set_shader_parameter("clear_layer", 1.0 if look.get("clear", false) else 0.0)
	m.set_shader_parameter("under_color", look.get("under", Color(0.5, 0.5, 0.5, 0.0)))
	m.set_shader_parameter("under_rough", float(look.get("under_rough", 0.85)))


func _images() -> Array[Image]:
	var out: Array[Image] = []
	var slice := dims.x * dims.y * 2
	for z in dims.z:
		out.append(Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RG8, _bytes.slice(z * slice, (z + 1) * slice)))
	return out


## The cube a point (model space) is in, or -1 outside the mask.
func index_of(p: Vector3) -> int:
	var v := Vector3i(((p - origin) / voxel).floor())
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= dims.x or v.y >= dims.y or v.z >= dims.z:
		return -1
	return v.x + dims.x * (v.y + dims.y * v.z)


## Whether a point (model space) is within `margin` of the mask.
func reaches(p: Vector3, margin: float) -> bool:
	return AABB(origin, Vector3(dims) * voxel).grow(margin).has_point(p)


## Sprays a patch: the fan along `along` (model space) landing at `at`, `reach` wide. Every cube
## in the fan, from just in front of the surface to a little way into it, gets `amount` coats,
## less towards the edge (by `falloff`); `dryness` of it lands dry.
func paint(at: Vector3, along: Vector3, reach: float, amount: float, dryness := 0.0, falloff := 0.5) -> int:
	if amount <= 0.0 or reach <= 0.0 or not reaches(at, reach + 0.12):
		return 0
	var a := along.normalized()
	var span := reach + 0.12
	var lo := Vector3i(((at - Vector3.ONE * span - origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((at + Vector3.ONE * span - origin) / voxel).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var n := 0
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := origin + (Vector3(x, y, z) + Vector3.ONE * 0.5) * voxel
				var v := p - at
				var depth := v.dot(a)
				if depth < -0.05 or depth > 0.11:
					continue
				var d := (v - a * depth).length()
				if d >= reach:
					continue
				var i := x + dims.x * (y + dims.y * z)
				var add := amount * (1.0 - falloff * d / reach)
				coats[i] += add
				dry[i] += add * dryness
				_store(i)
				n += 1
	_dirty = true
	return n


func _store(i: int) -> void:
	var c := coats[i]
	_bytes[i * 2] = clampi(roundi(c / COAT_MAX * 255.0), 0, 255)
	_bytes[i * 2 + 1] = clampi(roundi(dry[i] / maxf(c, 0.001) * 255.0), 0, 255) if c > 0.0 else 0


## Takes over what another mask had laid on (the part was redrawn mid-job). False if the two
## don't line up.
func adopt(other: SprayMarks) -> bool:
	if other == null or other.dims != dims or not other.origin.is_equal_approx(origin) or not is_equal_approx(other.voxel, voxel):
		return false
	coats = other.coats.duplicate()
	dry = other.dry.duplicate()
	for i in coats.size():
		_store(i)
	_dirty = true
	return true


func _update_transform() -> void:
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return
	var inv := model.global_transform.affine_inverse()
	for slot in _mats:
		# A part moved by the bike's own fit (geometry mode) is read where it was drawn.
		var rest := Transform3D.IDENTITY
		if model._geo_nodes.has(slot) and model._geo_pivots.has(slot):
			rest = GeoGizmo.offset_xform(model.geometry.get(slot, {}), model._geo_pivots[slot]).affine_inverse()
		(_mats[slot] as ShaderMaterial).set_shader_parameter("to_model", Projection(rest * inv))


func _process(delta: float) -> void:
	_update_transform()
	var want := 1.0 if _scan_on else 0.0
	if _scan != want or _scan_on:
		_scan = move_toward(_scan, want, delta * 3.0)
		_scan_t += delta
		_param("scan", _scan)
		_param("scan_t", _scan_t)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		_param("flash", _flash)
	if _drying:
		_wet = maxf(0.0, _wet - delta * 0.8)
		_param("wet", _wet)
	_since_upload += delta
	if _dirty and _since_upload >= 1.0 / 30.0:
		_dirty = false
		_since_upload = 0.0
		_tex.update(_images())


func _param(key: String, value) -> void:
	for slot in _mats:
		(_mats[slot] as ShaderMaterial).set_shader_parameter(key, value)


## Pushes the latest coats to the texture now (for tests and screenshots).
func flush() -> void:
	_dirty = false
	_tex.update(_images())


## Lights the part up for a moment: the coat's done.
func flash_done() -> void:
	_flash = 0.7
	_drying = true


## Puts the parts' own materials back (the job's done or abandoned).
func restore() -> void:
	for r in _restore:
		if r[2] != null:
			(r[2] as Material).next_pass = null
		if is_instance_valid(r[0]):
			(r[0] as GeometryInstance3D).material_override = r[1]
	_restore.clear()


func _exit_tree() -> void:
	# Unhook from anything shared (the sandblaster's bare-metal pass) when the part goes.
	for r in _restore:
		if r[2] != null:
			(r[2] as Material).next_pass = null


## The pass material on a part (for tests).
func material_for(slot: String) -> ShaderMaterial:
	return _mats.get(slot, null)


## How many meshes carry the pass (for tests).
func mesh_count() -> int:
	return _restore.size()


func set_scan(on: bool) -> void:
	_scan_on = on


func scanning() -> bool:
	return _scan_on


## How many cubes have any paint on them yet (for tests).
func painted_count() -> int:
	var n := 0
	for c in coats:
		if c > 0.05:
			n += 1
	return n
