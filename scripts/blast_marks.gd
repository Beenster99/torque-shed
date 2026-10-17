class_name BlastMarks
extends Node
## Bare metal coming up on an engine in the sandblaster. The space round the engine is split
## into little cubes (VOXEL across), each holding how much blasting it has had; that's a 3D
## texture every part's material reads, so wherever the jet has been the old rusty, painted
## surface turns to satin metal (aluminium on the castings, bare steel on steel parts) with a
## sandblasted grain and a ragged edge, and goes dull grey and pitted where it's had too long.
## Missed bits stay rusty, so you can see them. Lives on the engine's BikeModel and turns with it.
##
## The cubes line up on a grid measured from the middle of the engine block (the model's
## `_engine_c`), so what's been blasted can be kept on each part (export_part, as the item's
## "blast") and drawn again on the same engine anywhere the shed draws it: in the cabinet, carried,
## on the stand or fitted to a bike (show_saved). A part blasted all over is drawn bare all over.
## The scan (set_scan) lights the engine up: red where there's still rust to blast, green where
## it's bare, purple where it's pitted.

const VOXEL := 0.02          # metres per cube of the mask
const MAX_DIM := 96
const COAT_MAX := 8.0        # blasting a kept cube can hold (its byte is coats / COAT_MAX)
const MAX_SAVED := 200000    # longest kept mask, as text
const ALUMINIUM := Color(0.8, 0.81, 0.83)
const STEEL := Color(0.6, 0.61, 0.63)
## Parts that come up as bare steel rather than aluminium.
const STEEL_SLOTS := ["oil_filter", "spark_plugs"]

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler3D mask : filter_linear, repeat_disable;
uniform mat4 to_model = mat4(1.0);
uniform vec3 mask_origin;
uniform vec3 mask_size = vec3(1.0);
uniform vec3 bare_color : source_color = vec3(0.8, 0.81, 0.83);
uniform float bare_rough = 0.42;
uniform float bare_metal = 0.9;
uniform float flash = 0.0;
uniform float full = 0.0;      // blasted all over: bare everywhere, missed bits and all
uniform float rust_amt = 0.0;  // flash rust on bare metal left unprotected
uniform float dirt_amt = 0.0;
uniform float lacquer = 0.0;   // a clear protective coat over the bare metal
uniform float scan = 0.0;      // the sandblaster's scan
uniform float scan_t = 0.0;

varying vec3 mpos;

// Whether a colour is a real one in range: false for NaN or infinite (comparisons with NaN fail).
bool sane(vec3 v, float top) {
	return all(greaterThanEqual(v, vec3(0.0))) && all(lessThanEqual(v, vec3(top)));
}

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
	// A hair proud of the surface, so it draws over the part's own finish.
	VERTEX += NORMAL * 0.0007;
	mpos = (to_model * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 uvw = (mpos - mask_origin) / max(mask_size, vec3(1e-4));
	vec2 m = texture(mask, uvw).rg;
	// A ragged, speckled edge where the blasting stops.
	float edge = vnoise(mpos * 140.0) * 0.6 + vnoise(mpos * 40.0) * 0.4;
	float a = max(smoothstep(0.3, 0.8, m.r + (edge - 0.5) * 0.3), full);
	float grain = hash3(floor(mpos * 2200.0));
	float grain2 = vnoise(mpos * 600.0);
	vec3 col = bare_color * (0.9 + grain * 0.1 + grain2 * 0.06);
	col = mix(col, bare_color * 0.5, m.g * (0.7 + 0.3 * grain2));
	// Bare steel left out flash-rusts in orange speckles; road muck dulls it.
	float speck = smoothstep(1.0 - rust_amt, 1.0 - rust_amt * 0.5, vnoise(mpos * 90.0) * 0.7 + grain2 * 0.3);
	col = mix(col, vec3(0.45, 0.2, 0.08), speck * step(0.001, rust_amt));
	col = mix(col, vec3(0.16, 0.13, 0.09), dirt_amt * 0.65);
	vec3 emit = vec3(0.55, 0.75, 1.0) * flash * 1.5;
	if (scan > 0.0) {
		// Red where there's rust still to blast, green where it's bare, purple where it's pitted.
		float bare = step(0.5, max(m.r, full));
		vec3 sc = mix(vec3(1.0, 0.12, 0.04), vec3(0.15, 1.0, 0.35), bare);
		sc = mix(sc, vec3(0.75, 0.2, 1.0), step(0.08, m.g));
		float band = smoothstep(0.92, 1.0, fract(mpos.y * 3.0 - scan_t * 0.8));
		col = mix(col, sc, 0.55 * scan);
		emit += sc * scan * (0.35 + 1.4 * band + (1.0 - bare) * 0.5);
		a = max(a, scan * 0.9);
	}
	vec3 shown = col + vec3(flash * 0.5);
	if (!sane(shown, 2.0) || !sane(emit, 8.0) || !(a >= 0.0)) {
		discard;   // never a NaN or a blinding value to the screen
	}
	ALBEDO = min(shown, vec3(1.0));
	METALLIC = bare_metal * (1.0 - dirt_amt * 0.5);
	ROUGHNESS = clamp((bare_rough + grain * 0.12 + m.g * 0.35) * (1.0 - 0.75 * lacquer) + dirt_amt * 0.4, 0.0, 1.0);
	CLEARCOAT = lacquer;
	CLEARCOAT_ROUGHNESS = 0.08;
	EMISSION = emit;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _shader: Shader

var model: BikeModel
var origin := Vector3.ZERO       # the mask's corner, in the model's space
var lattice := Vector3i.ZERO     # the same corner in cubes from the middle of the engine block
var dims := Vector3i.ONE
var coats := PackedFloat32Array()  # blasting each cube has had (1 is bare metal)
var _over := 4.5
var _tex: ImageTexture3D
var _bytes := PackedByteArray()
var _dirty := false
var _since_upload := 0.0
var _mats := {}                  # slot -> ShaderMaterial
var _restore := []               # [mesh, its own material] to put back when it's done
var _flash := {}                 # slot -> seconds of flash left
var _scan := 0.0                 # how far the scan is lit, 0..1
var _scan_on := false
var _scan_t := 0.0


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## Covers the parts in `slots` of `engine_model`, and turns their materials over to the mask.
func setup(engine_model: BikeModel, slots: Array, over_level: float) -> void:
	model = engine_model
	_over = over_level
	var box := AABB()
	var first := true
	for slot in slots:
		var b := model.slot_bounds(slot)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	box = box.grow(VOXEL * 2.0)
	# On the grid measured from the middle of the block, so kept masks line up again.
	var centre := model._engine_c
	lattice = Vector3i(((box.position - centre) / VOXEL).floor())
	var top := Vector3i(((box.end - centre) / VOXEL).ceil())
	origin = centre + Vector3(lattice) * VOXEL
	dims = Vector3i(clampi(top.x - lattice.x, 2, MAX_DIM), clampi(top.y - lattice.y, 2, MAX_DIM), clampi(top.z - lattice.z, 2, MAX_DIM))
	coats.resize(dims.x * dims.y * dims.z)
	coats.fill(0.0)
	_bytes.resize(coats.size() * 2)
	_bytes.fill(0)
	_tex = ImageTexture3D.new()
	_tex.create(Image.FORMAT_RG8, dims.x, dims.y, dims.z, false, _images())
	for slot in slots:
		var m := ShaderMaterial.new()
		m.shader = shader()
		m.render_priority = 1
		m.set_shader_parameter("mask", _tex)
		m.set_shader_parameter("mask_origin", origin)
		m.set_shader_parameter("mask_size", Vector3(dims) * VOXEL)
		var steel := STEEL_SLOTS.has(slot)
		var c := STEEL if steel else ALUMINIUM
		m.set_shader_parameter("bare_color", Vector3(c.r, c.g, c.b))
		m.set_shader_parameter("bare_rough", 0.5 if steel else 0.42)
		m.set_shader_parameter("bare_metal", 0.85 if steel else 0.9)
		_mats[slot] = m
		for mi in model._slot_meshes.get(slot, []):
			var g := mi as GeometryInstance3D
			if g == null or not is_instance_valid(g):
				continue
			var own := g.material_override
			if own is BaseMaterial3D:
				var mine := (own as BaseMaterial3D).duplicate() as BaseMaterial3D
				mine.next_pass = m
				_restore.append([g, own])
				g.material_override = mine
	_update_transform()


func _images() -> Array[Image]:
	var out: Array[Image] = []
	var slice := dims.x * dims.y * 2
	for z in dims.z:
		out.append(Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RG8, _bytes.slice(z * slice, (z + 1) * slice)))
	return out


func index_of(p: Vector3) -> int:
	var v := Vector3i(((p - origin) / VOXEL).floor())
	if v.x < 0 or v.y < 0 or v.z < 0 or v.x >= dims.x or v.y >= dims.y or v.z >= dims.z:
		return -1
	return v.x + dims.x * (v.y + dims.y * v.z)


## Blasts a patch: the jet along `along` (model space) landing at `at`, `reach` wide. Every cube
## in the jet, from just in front of the surface to a little way into it, gets `amount` of
## blasting, less towards the edge of the jet.
func paint(at: Vector3, along: Vector3, reach: float, amount: float) -> void:
	var a := along.normalized()
	var span := reach + 0.09
	var lo := Vector3i(((at - Vector3.ONE * span - origin) / VOXEL).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var hi := Vector3i(((at + Vector3.ONE * span - origin) / VOXEL).floor()).clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := origin + (Vector3(x, y, z) + Vector3.ONE * 0.5) * VOXEL
				var v := p - at
				var depth := v.dot(a)
				if depth < -0.045 or depth > 0.085:
					continue
				var d := (v - a * depth).length()
				if d >= reach:
					continue
				var i := x + dims.x * (y + dims.y * z)
				var c := coats[i] + amount * (1.0 - 0.6 * d / reach)
				coats[i] = c
				_bytes[i * 2] = clampi(roundi(c * 255.0), 0, 255)
				_bytes[i * 2 + 1] = clampi(roundi((c - _over) / _over * 255.0), 0, 255)
	_dirty = true


## Lights a part up for a moment: it's just come back to bare metal.
func flash_part(slot: String) -> void:
	_flash[slot] = 0.6


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
		for slot in _mats:
			(_mats[slot] as ShaderMaterial).set_shader_parameter("scan", _scan)
			(_mats[slot] as ShaderMaterial).set_shader_parameter("scan_t", _scan_t)
	_since_upload += delta
	if _dirty and _since_upload >= 1.0 / 30.0:
		_dirty = false
		_since_upload = 0.0
		_tex.update(_images())
	for slot in _flash.keys():
		var left := float(_flash[slot]) - delta
		if _mats.has(slot):
			(_mats[slot] as ShaderMaterial).set_shader_parameter("flash", clampf(left / 0.6, 0.0, 1.0))
		if left <= 0.0:
			_flash.erase(slot)
		else:
			_flash[slot] = left


## Puts the parts' own materials back (the job's done or abandoned).
func restore() -> void:
	for r in _restore:
		if is_instance_valid(r[0]):
			(r[0] as GeometryInstance3D).material_override = r[1]
	_restore.clear()


## The shader material on a part (for tests).
func material_for(slot: String) -> ShaderMaterial:
	return _mats.get(slot, null)


## How many cubes show any bare metal yet (for tests).
func bare_count() -> int:
	var n := 0
	for c in coats:
		if c > 0.5:
			n += 1
	return n


func patch_count() -> int:
	return coats.size()


## Turns the scan on or off: the engine lights up red where there's still rust to blast.
func set_scan(on: bool) -> void:
	_scan_on = on


func scanning() -> bool:
	return _scan_on


## How bare a part is drawn all over (1 once it's done), and how it's weathered since.
func set_look(slot: String, full_bare: float, rust := 0.0, dirt := 0.0, lacquer := 0.0) -> void:
	var m: ShaderMaterial = _mats.get(slot, null)
	if m == null:
		return
	m.set_shader_parameter("full", full_bare)
	m.set_shader_parameter("rust_amt", clampf(rust, 0.0, 1.0))
	m.set_shader_parameter("dirt_amt", clampf(dirt, 0.0, 1.0))
	m.set_shader_parameter("lacquer", clampf(lacquer, 0.0, 1.0))


# ---------------------------------------------------------------------------- keeping it

## What's been blasted on one part, to keep on its item: the cubes round the part's own surface
## patches (`vox`, their indices in this mask) and one cube either side, packed small:
## {o: corner in cubes from the middle of the block, d: size in cubes, v: the bytes}.
func export_part(vox: PackedInt32Array) -> Dictionary:
	var keep := {}
	var lo := Vector3i(MAX_DIM * 4, MAX_DIM * 4, MAX_DIM * 4)
	var hi := -lo
	for i in vox:
		if i < 0:
			continue
		var v := Vector3i(i % dims.x, (i / dims.x) % dims.y, i / (dims.x * dims.y))
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := v + Vector3i(dx, dy, dz)
					if n.x < 0 or n.y < 0 or n.z < 0 or n.x >= dims.x or n.y >= dims.y or n.z >= dims.z:
						continue
					var k := n.x + dims.x * (n.y + dims.y * n.z)
					if keep.has(k):
						continue
					keep[k] = true
					lo = Vector3i(mini(lo.x, n.x), mini(lo.y, n.y), mini(lo.z, n.z))
					hi = Vector3i(maxi(hi.x, n.x), maxi(hi.y, n.y), maxi(hi.z, n.z))
	if keep.is_empty():
		return {}
	var size := hi - lo + Vector3i.ONE
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * size.z)
	bytes.fill(0)
	for k in keep:
		var ki := int(k)
		var c := coats[ki]
		if c <= 0.0:
			continue
		var v := Vector3i(ki % dims.x, (ki / dims.x) % dims.y, ki / (dims.x * dims.y)) - lo
		bytes[v.x + size.x * (v.y + size.y * v.z)] = clampi(roundi(c / COAT_MAX * 255.0), 0, 255)
	return {"o": lattice + lo, "d": size, "v": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_DEFLATE))}


## A kept mask unpacked: {o, d, bytes}, or {} if it's damaged or too big.
static func unpack(data) -> Dictionary:
	if not (data is Dictionary) or not (data.get("o") is Vector3i) or not (data.get("d") is Vector3i) or not (data.get("v") is String):
		return {}
	var d: Vector3i = data["d"]
	if d.x < 1 or d.y < 1 or d.z < 1 or d.x > MAX_DIM or d.y > MAX_DIM or d.z > MAX_DIM:
		return {}
	var text: String = data["v"]
	if text.length() > MAX_SAVED or text.is_empty():
		return {}
	var packed := Marshalls.base64_to_raw(text)
	var n := d.x * d.y * d.z
	var bytes := packed.decompress_dynamic(n, FileAccess.COMPRESSION_DEFLATE) if not packed.is_empty() else PackedByteArray()
	if bytes.size() != n:
		return {}
	return {"o": data["o"], "d": d, "bytes": bytes}


## Whether a kept mask is sound (the host checks what it's sent).
static func valid(data) -> bool:
	return not unpack(data).is_empty()


## Puts a kept mask back into this one (each cube keeps the most blasting either has had).
## Returns how many cubes it set.
func import_data(data) -> int:
	var u := unpack(data)
	if u.is_empty():
		return 0
	var o: Vector3i = u["o"]
	var d: Vector3i = u["d"]
	var bytes: PackedByteArray = u["bytes"]
	var n := 0
	for z in d.z:
		for y in d.y:
			for x in d.x:
				var b := bytes[x + d.x * (y + d.y * z)]
				if b == 0:
					continue
				var g := o + Vector3i(x, y, z) - lattice
				if g.x < 0 or g.y < 0 or g.z < 0 or g.x >= dims.x or g.y >= dims.y or g.z >= dims.z:
					continue
				var i := g.x + dims.x * (g.y + dims.y * g.z)
				var c := maxf(coats[i], b / 255.0 * COAT_MAX)
				coats[i] = c
				_bytes[i * 2] = clampi(roundi(c * 255.0), 0, 255)
				_bytes[i * 2 + 1] = clampi(roundi((c - _over) / _over * 255.0), 0, 255)
				n += 1
	if _tex and n > 0:
		_tex.update(_images())
	return n


## Draws what's been blasted on an engine wherever the shed draws it, from what's kept on each
## part (`looks`: slot -> its condition, with "blast" and "blast_full"). Returns the marks, or null
## when nothing on it has been blasted.
static func show_saved(engine_model: BikeModel, looks: Dictionary) -> BlastMarks:
	var slots := []
	for slot in looks:
		var cond = looks[slot]
		if not (cond is Dictionary) or not engine_model.is_fitted(slot) or (engine_model._slot_meshes.get(slot, []) as Array).is_empty():
			continue
		if (cond as Dictionary).has("blast") or bool((cond as Dictionary).get("blast_full", false)):
			slots.append(slot)
	if slots.is_empty():
		return null
	var marks := BlastMarks.new()
	marks.name = "BlastSaved"
	marks.setup(engine_model, slots, BlastGame.OVER)
	for slot in slots:
		var cond: Dictionary = looks[slot]
		if cond.has("blast"):
			marks.import_data(cond["blast"])
		marks.set_look(slot, 1.0 if cond.get("blast_full", false) else 0.0, float(cond.get("rust", 0.0)),
			float(cond.get("dirt", 0.0)), Shed.coat_gloss(str(cond.get("coat", ""))))
	engine_model.add_child(marks)
	return marks
