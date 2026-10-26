class_name DiaryShelf
extends Node3D
## The shed's diary shelf: a wooden bookcase built in against the east wall beside bay 4 (clear of the
## engine stand), that the Adventure Diaries on this machine stand on (AdventureDiary.list),
## newest first. The newest stands face out on the top shelf with the ride's snapshot on its
## cover; the rest are spines along the shelves below, each its own colour. It restocks itself
## when a diary's saved or deleted (AdventureDiary.revision). F at it opens the shelf of diaries
## in the book (DiaryBook).
##
## It's part of the shed, so nobody moves it; each player sees their own diaries on it.

## Where it stands: its back against the east wall, facing into the shed (-X).
const XF := Transform3D(Basis(Vector3.UP, -PI * 0.5), Workshop.CENTER + Vector3(Workshop.HALF.x - 0.19, 0.0, -2.0))
const SIZE := Vector3(1.4, 1.9, 0.36)
## The heights of the shelves' tops, the bottom one first.
const SHELVES := [0.08, 0.52, 0.96, 1.4]
## Spines on the three lower shelves; the top one has the newest face out and a few beside it.
const SPINES_PER_SHELF := 18
const SPINE_W := 0.062

## The diaries on it, newest first (as AdventureDiary.list gives them).
var diaries: Array = []
var _books: Node3D
var _revision := -1
var _wood: StandardMaterial3D


func _ready() -> void:
	name = "DiaryShelf"
	transform = XF
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.42, 0.27, 0.15)
	_wood.roughness = 0.7
	# The case: sides, top, back and the shelves.
	var hw := SIZE.x * 0.5
	_box(Vector3(-hw + 0.02, SIZE.y * 0.5, 0.0), Vector3(0.04, SIZE.y, SIZE.z), _wood)
	_box(Vector3(hw - 0.02, SIZE.y * 0.5, 0.0), Vector3(0.04, SIZE.y, SIZE.z), _wood)
	_box(Vector3(0.0, SIZE.y - 0.02, 0.0), Vector3(SIZE.x, 0.04, SIZE.z), _wood)
	_box(Vector3(0.0, SIZE.y * 0.5, -SIZE.z * 0.5 + 0.01), Vector3(SIZE.x, SIZE.y, 0.02), _wood)
	for y in SHELVES:
		_box(Vector3(0.0, float(y) - 0.015, 0.0), Vector3(SIZE.x - 0.06, 0.03, SIZE.z - 0.02), _wood)
	var sign := Label3D.new()
	sign.name = "Sign"
	sign.text = "ADVENTURE DIARIES"
	sign.font_size = 34
	sign.pixel_size = 0.0022
	sign.outline_size = 0
	sign.modulate = Color(0.95, 0.85, 0.55)
	sign.position = Vector3(0.0, SIZE.y + 0.12, -SIZE.z * 0.5 + 0.03)
	add_child(sign)
	# Solid to walk into, and something to press F at.
	var solid := StaticBody3D.new()
	solid.name = "Case"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	cs.shape = shape
	cs.position.y = SIZE.y * 0.5
	solid.add_child(cs)
	add_child(solid)
	var target := StaticBody3D.new()
	target.name = "Target"
	target.collision_layer = Workshop.INTERACT_LAYER
	target.collision_mask = 0
	target.set_meta("use_node", self)
	target.set_meta("use", {"what": "diary_shelf"})
	var ts := CollisionShape3D.new()
	var tshape := BoxShape3D.new()
	tshape.size = SIZE + Vector3(0.0, 0.0, 0.1)
	ts.shape = tshape
	ts.position = Vector3(0.0, SIZE.y * 0.5, 0.05)
	target.add_child(ts)
	add_child(target)
	restock()


func _process(_delta: float) -> void:
	if AdventureDiary.revision != _revision:
		restock()


## Puts this machine's diaries on the shelves again.
func restock() -> void:
	_revision = AdventureDiary.revision
	diaries = AdventureDiary.list()
	if _books:
		_books.free()
	_books = Node3D.new()
	_books.name = "Books"
	add_child(_books)
	if diaries.is_empty():
		return
	# The newest, face out on the top shelf with its snapshot on the cover.
	var top := float(SHELVES[3])
	var face := _box(Vector3(-0.32, top + 0.17, -0.08), Vector3(0.24, 0.32, 0.03), _cover_mat(diaries[0]), _books)
	face.name = "FaceOut"
	face.rotation.x = -0.12
	var tex := _cover_tex(diaries[0])
	if tex != null:
		var photo := MeshInstance3D.new()
		photo.name = "Snapshot"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.2, 0.13)
		photo.mesh = quad
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = tex
		pm.roughness = 0.5
		photo.material_override = pm
		photo.position = Vector3(0.0, 0.04, 0.016)
		face.add_child(photo)
	# The rest as spines: beside the face-out one on top, then along the shelves below.
	var rows := [[top, -0.14, 9], [float(SHELVES[2]), -0.66, SPINES_PER_SHELF], [float(SHELVES[1]), -0.66, SPINES_PER_SHELF],
		[float(SHELVES[0]), -0.66, SPINES_PER_SHELF]]
	var i := 1
	for row in rows:
		for k in int(row[2]):
			if i >= diaries.size():
				return
			var h := 0.28 + 0.05 * float(absi(hash(str(diaries[i]["id"]))) % 5) / 4.0
			var spine := _box(Vector3(float(row[1]) + (k + 0.5) * SPINE_W, float(row[0]) + h * 0.5, 0.0),
				Vector3(SPINE_W - 0.006, h, 0.22), _cover_mat(diaries[i]), _books)
			spine.name = "Spine%d" % i
			i += 1


## How many diaries are on it.
func count() -> int:
	return diaries.size()


func use_text(_t: Dictionary) -> String:
	var n := diaries.size()
	if n == 0:
		return "Adventure diaries: none yet. Every adventure ride makes one."
	return "Adventure diaries: %d, the newest %s\n{interact}: read them" % [n, str(diaries[0]["title"])]


func use(_t: Dictionary) -> void:
	if AdventureTrip.current:
		AdventureTrip.current.open_diary()


## A diary's own cover colour: leather-ish, picked by its id so it keeps it.
static func _cover_mat(d: Dictionary) -> StandardMaterial3D:
	const COLOURS := [Color(0.45, 0.1, 0.08), Color(0.1, 0.22, 0.4), Color(0.14, 0.3, 0.16), Color(0.32, 0.2, 0.1),
		Color(0.12, 0.12, 0.13), Color(0.5, 0.36, 0.12), Color(0.3, 0.12, 0.3)]
	var m := StandardMaterial3D.new()
	m.albedo_color = COLOURS[absi(hash(str(d.get("id", "")))) % COLOURS.size()]
	m.roughness = 0.65
	return m


## The snapshot on diary `d`'s cover (its shelf entry's), small, or null.
static func _cover_tex(d: Dictionary) -> Texture2D:
	var cover := str(d.get("cover", ""))
	if cover == "" or not FileAccess.file_exists(cover):
		return null
	var img := Image.load_from_file(cover)
	if img == null or img.is_empty():
		return null
	img.resize(256, 160, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _box(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi
