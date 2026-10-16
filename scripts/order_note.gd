class_name OrderNote
extends RefCounted
## The sticky note on a delivery box saying who ordered it ("For Simon"), so in co-op everyone
## can tell whose boxes are whose in the delivery area. The name is kept on the item ("by",
## set by Shed when the part is ordered) and the note is stuck on the lid and the front of the
## box (see BikeModel.item_display).

const PAPER := Color(1.0, 0.88, 0.25)
const INK := Color(0.1, 0.14, 0.42)


## "Ordered by Simon  ·  " for the info panel, or "" for a box with no name on it.
static func line(item: Dictionary) -> String:
	var by := str(item.get("by", ""))
	return "" if by == "" else "Ordered by %s  ·  " % by


## Sticks the notes on a box drawn by BikeModel.box_display, if the item says who ordered it.
## Returns the box.
static func attach(box: Node3D, item: Dictionary) -> Node3D:
	var by := str(item.get("by", ""))
	if by == "" or box == null:
		return box
	var size: Vector3 = box.get_meta("size", Vector3(0.3, 0.2, 0.3))
	var n := clampf(minf(size.x, size.z) * 0.42, 0.07, 0.12)
	# On the lid, in a corner and a little askew, over the shipping label if the box is small.
	var lid := make(by, n)
	lid.name = "OrderNote"
	lid.rotation_order = EULER_ORDER_YXZ
	lid.rotation = Vector3(-PI * 0.5, 0.18, 0.0)
	lid.position = Vector3(-size.x * 0.5 + n * 0.62, size.y + 0.007, size.z * 0.5 - n * 0.62)
	box.add_child(lid)
	# And on the front, for a box on a shelf, up in the corner clear of the label's middle.
	var fn := minf(n, size.y * 0.45)
	var front := make(by, fn)
	front.name = "OrderNoteFront"
	front.rotation.z = -0.12
	front.position = Vector3(size.x * 0.5 - fn * 0.6, size.y - fn * 0.6, size.z * 0.5 + 0.004)
	box.add_child(front)
	box.set_meta("ordered_by", by)
	return box


## A square note `side` metres across facing +Z: "FOR" and the name in pen.
static func make(by: String, side: float) -> Node3D:
	var root := Node3D.new()
	BikeModel._quad(root, Vector2(side, side), Vector3.ZERO, PAPER)
	# A slightly darker strip along the top, where it's sticky.
	BikeModel._quad(root, Vector2(side, side * 0.16), Vector3(0.0, side * 0.42, 0.0005), PAPER.darkened(0.12))
	BikeModel._sticker_text(root, "FOR", Vector3(0.0, side * 0.2, 0.001), Vector2(side * 0.5, side * 0.2), INK, 40)
	BikeModel._sticker_text(root, by, Vector3(0.0, -side * 0.12, 0.001), Vector2(side * 0.88, side * 0.36), INK, 48)
	return root
