class_name PaintSplats
extends Node3D
## Wet paint (or chain lube) showing on a part as it's sprayed: a soft disc on each patch,
## more solid with each coat, and drips running down where it's been laid on too thick.
## Lives in the world over the part; set_coats() as the spray lands, finish() when it's done.

const RUN_LEVEL := 4.0

var color := Color.RED
var finish := "gloss"
var _decals: Array = []        # one per patch, null until it gets paint
var _points := PackedVector3Array()
var _normals := PackedVector3Array()
var _cell := 0.06
var _fading := -1.0
static var _blob: Texture2D
static var _drip: Texture2D


## `xf` is the part's frame in the world; `points` and `normals` are its patches in that frame.
func setup(xf: Transform3D, points: PackedVector3Array, normals: PackedVector3Array, cell: float, paint: Color,
		paint_finish := "gloss") -> void:
	transform = xf
	_points = points
	_normals = normals
	_cell = cell
	color = paint
	finish = paint_finish
	_decals.resize(points.size())


static func _blob_texture() -> Texture2D:
	if _blob == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.85))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_blob = t
	return _blob


static func _drip_texture() -> Texture2D:
	if _drip == null:
		var img := Image.create(32, 96, false, Image.FORMAT_RGBA8)
		for y in 96:
			for x in 32:
				var u := (x - 15.5) / 16.0
				var v := y / 95.0
				# A teardrop: wide at the top where it runs from, a bead at the bottom.
				var w := lerpf(0.55, 0.22, v) + (0.25 if v > 0.82 else 0.0) * (1.0 - absf(v - 0.9) * 8.0)
				var a := clampf((w - absf(u)) * 6.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_drip = ImageTexture.create_from_image(img)
	return _drip


## Patch `i` now has `coats` coats on it (1 is a full cover).
func set_coats(i: int, coats: float) -> void:
	if i < 0 or i >= _points.size() or coats <= 0.02:
		return
	var d: MeshInstance3D = _decals[i]
	var n := _normals[i] if i < _normals.size() else Vector3.UP
	if n.length() < 0.5:
		n = Vector3.UP
	n = n.normalized()
	if d == null:
		# A soft disc of paint lying on the surface (a mesh rather than a decal, so it shows
		# on every renderer).
		d = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(_cell * 1.7, _cell * 1.7)
		d.mesh = q
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var b := Basis(side, n.cross(side), n).rotated(n, randf() * TAU)
		d.transform = Transform3D(b, _points[i] + n * 0.003)
		d.material_override = _wet_material(_blob_texture())
		add_child(d)
		_decals[i] = d
	var wet := color
	if finish == "chrome":
		wet = wet.lerp(Color(0.92, 0.93, 0.95), 0.6)
	elif finish == "patina":
		wet = wet.darkened(0.25)
	var a := clampf(coats, 0.0, 1.0)
	(d.material_override as StandardMaterial3D).albedo_color = Color(wet.r, wet.g, wet.b, lerpf(0.35, 0.97, a))
	if coats > RUN_LEVEL and not d.has_meta("drip"):
		_add_drip(i, n)
		d.set_meta("drip", true)


## Too much paint in one place: it runs down the part.
func _add_drip(i: int, n: Vector3) -> void:
	var down := (global_transform.basis.inverse() * Vector3.DOWN)
	down = (down - n * down.dot(n))
	if down.length() < 0.2:
		return   # a flat top doesn't run
	down = down.normalized()
	var d := MeshInstance3D.new()
	var length := _cell * randf_range(1.6, 2.6)
	var q := QuadMesh.new()
	q.size = Vector2(_cell * 0.6, length)
	d.mesh = q
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side := (-down).cross(n).normalized()
	d.transform = Transform3D(Basis(side, -down, n), _points[i] + down * length * 0.5 + n * 0.004)
	var m := _wet_material(_drip_texture())
	var c := color.darkened(0.15)
	m.albedo_color = Color(c.r, c.g, c.b, 0.95)
	d.material_override = m
	add_child(d)


func _wet_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.roughness = 0.25 if finish == "gloss" or finish == "chrome" else 0.6
	m.metallic = 0.6 if finish == "chrome" or finish == "metallic" else 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## How many patches have any paint on them yet (for tests).
func painted_count() -> int:
	var n := 0
	for d in _decals:
		if d != null:
			n += 1
	return n


## The job's done (or abandoned): fade the wet paint out as the part shows its new colour.
func finish_job(delay := 0.4) -> void:
	_fading = delay + 0.6


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("spray_fx", pt)


func _process_body(delta: float) -> void:
	if _fading < 0.0:
		return
	_fading -= delta
	if _fading <= 0.0:
		queue_free()
		return
	var a := clampf(_fading / 0.6, 0.0, 1.0)
	for d in get_children():
		if d is MeshInstance3D and d.material_override:
			var m := d.material_override as StandardMaterial3D
			m.albedo_color.a = minf(m.albedo_color.a, a)
