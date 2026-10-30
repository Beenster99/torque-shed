extends RefCounted
## The parts computer's page laid out: the part's picture in its photo studio, its words, the
## colour picker and the Order button all fit inside the page at the screen sizes people play
## at, run from tests/run_tests.gd (its _test_parts_page_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree(), get_window()

## Logical screen sizes the page is laid out at: the game's own (1600x900, what 1280x720 and
## 1920x1080 windows both stretch to) and, smaller and larger, 1280x720 and 1920x1080 themselves.
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
## Parts to lay out: a seat (a second colour to pick, its piping), an exhaust (headers), a tank
## (a stripe), a black tyre (no picker) and a shed bench (no picture).
const PARTS := [["saddle", "mx_ribbed_seat"], ["exhaust", "cafe_megaphone_black"], ["tank", "cafe_15"],
	["tyre", ""], ["eq:bench", ""]]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Every part's page fits inside the panel at each size: nothing in the detail column overlaps the
## next thing down, the picker and its swatches are wholly inside it, the Order button is on the
## page, and the picture is a decent size.
func test_fits() -> void:
	Shed.start_new("Tester", 41)
	Shed.garage_money = 1000000
	var win := t.get_window()
	var keep_size := win.size
	var keep_scale := win.content_scale_size
	var pc := PartsComputer.new()
	t.add_child(pc)
	pc.open()
	await _frames(2)
	var panel: Control = pc.get_child(1).get_child(0)
	var detail: Control = pc._order.get_parent()
	for logical in SIZES:
		win.size = logical
		win.content_scale_size = logical
		await _frames(3)
		var screen := pc.get_viewport().get_visible_rect()
		for pk in PARTS:
			var k := str(pk[0])
			pc._show_section(PartsComputer.section_of(k))
			pc._show_kind(k)
			var id := str(pk[1]) if str(pk[1]) != "" else str(pc._part)
			pc._show_part(id)
			await _frames(3)
			var what := "%s at %dx%d" % [id, logical.x, logical.y]
			var pr := panel.get_global_rect()
			check(screen.grow(1.0).encloses(pr), "%s: the page is on the screen (%s in %s)" % [what, pr, screen])
			var dr := detail.get_global_rect()
			check(pr.grow(1.0).encloses(dr), "%s: the detail column is inside the page (%s in %s)" % [what, dr, pr])
			var shown: Array = detail.get_children().filter(func(c): return c is Control and (c as Control).visible)
			var overlaps := []
			for i in range(1, shown.size()):
				var above: Rect2 = (shown[i - 1] as Control).get_global_rect()
				var below: Rect2 = (shown[i] as Control).get_global_rect()
				if below.position.y < above.end.y - 0.5 or not dr.grow(1.0).encloses(below):
					overlaps.append(str((shown[i] as Node).name))
			check(overlaps.is_empty(), "%s: nothing in the detail column overlaps or spills out %s" % [what, str(overlaps)])
			var ob := pc._order.get_global_rect()
			check(pc._order.is_visible_in_tree() and ob.size.y >= 30.0 and ob.end.y <= pr.end.y + 1.0,
				"%s: the Order button is on the page (%s)" % [what, ob])
			if pc._look_box.visible:
				var lr := pc._look_box.get_global_rect()
				var out := []
				for c in pc._look_box.find_children("*", "Control", true, false):
					if (c as Control).is_visible_in_tree() and not lr.grow(1.0).encloses((c as Control).get_global_rect()):
						out.append(str((c as Node).name))
				check(out.is_empty() and dr.grow(1.0).encloses(lr), "%s: the colour picker is wholly inside the page %s" % [what, str(out)])
				check(lr.size.y <= 130.0, "%s: and it's compact (%.0f px high)" % [what, lr.size.y])
			if pc.preview.visible:
				var vr := pc.preview.get_global_rect()
				# 1280x720 is smaller than the game ever lays out at (it stretches to 1600x900 or more).
				var tall := 140.0 if logical.y < 900 else 240.0
				check(vr.size.x >= 320.0 and vr.size.y >= tall and Vector2(pc.preview.viewport.size).x >= 320.0,
					"%s: the picture is a good size (%.0f x %.0f)" % [what, vr.size.x, vr.size.y])
			else:
				check(k.begins_with("eq:"), "%s: only shed kit has no picture" % what)
	win.content_scale_size = keep_scale
	win.size = keep_size
	pc.queue_free()
	await _frames(2)
	Shed.stop()


## The picture is taken in a little studio: an opaque grey backdrop, a shadow under the part, and
## a light from behind as well as the key and fill; the turntable still holds just the part. The
## page's words are smaller than the other pages'.
func test_studio() -> void:
	Shed.start_new("Tester", 42)
	var pc := PartsComputer.new()
	t.add_child(pc)
	pc.open()
	await _frames(2)
	pc._show_section("bike")
	pc._show_kind("tyre")
	pc._show_part(str(pc.listed("tyre")[0]))
	await _frames(2)
	var pv := pc.preview
	check(pv.studio and not pv.viewport.transparent_bg and pv._env.background_mode == Environment.BG_SKY,
		"the part is shown against a backdrop, not the dark page behind it")
	var sky := pv._env.sky.sky_material as ProceduralSkyMaterial
	check(sky != null and sky.sky_top_color.get_luminance() > sky.ground_bottom_color.get_luminance()
		and sky.ground_bottom_color.get_luminance() > 0.3, "a soft grey: light overhead to mid grey at the floor")
	check(pv.viewport.get_node_or_null("Rim") is DirectionalLight3D, "with a rim light so dark parts stand out")
	var size: Vector3 = pv.pivot.get_child(0).get_meta("size")
	check(pv.shadow.visible and absf(pv.shadow.position.y + size.y * 0.5) < 0.01 and pv.pivot.get_child_count() == 1,
		"a shadow on the floor under the part, and only the part turns")
	# Framed close: the whole part in the picture whichever way it's turned, and filling a good
	# part of it, from a long thin seat to a tall exhaust.
	var framed := []
	for pk in [["saddle", "mx_ribbed_seat"], ["exhaust", "cafe_megaphone_black"], ["tyre", "knobbly_mx"],
			["handlebars", "sm_fat_black"], ["tank", "cafe_15"], ["front_mudguard", "carbon_hugger"]]:
		pc._show_kind(str(pk[0]))
		pc._show_part(str(pk[1]))
		await _frames(2)
		var shown: Node3D = pv.pivot.get_child(0)
		var box: Vector3 = shown.get_meta("size")
		var view := Rect2(Vector2.ZERO, Vector2(pv.viewport.size))
		var worst := 1.0
		var all_in := true
		for turn in 8:
			pv.pivot.rotation = Vector3(0.0, TAU * turn / 8.0, 0.0)
			var seen := Rect2()
			for i in 8:
				var corner := Vector3(box.x * ((i & 1) - 0.5), box.y * (((i >> 1) & 1) - 0.5), box.z * (((i >> 2) & 1) - 0.5))
				var at := pv.camera.unproject_position(pv.pivot.global_transform * corner)
				seen = Rect2(at, Vector2.ZERO) if i == 0 else seen.expand(at)
				all_in = all_in and view.has_point(at)
			worst = minf(worst, maxf(seen.size.x / view.size.x, seen.size.y / view.size.y))
		if not all_in or worst < 0.45:
			framed.append("%s (%.2f%s)" % [pk[1], worst, "" if all_in else ", cut off"])
	check(framed.is_empty(), "each part is framed close, all of it in the picture %s" % str(framed))
	# The line saying what colours were picked goes with the part they were picked for.
	pc._show_kind("saddle")
	pc._show_part("mx_ribbed_seat")
	pc.pick_colour(Shed.PAINTS[1])
	var said := pc._status.text
	pc._show_part(str(pc.listed("saddle")[0]))
	check(said.begins_with("In ") and pc._status.text == "", "the colours picked for one seat aren't said of the next (%s)" % said)
	pc._show_section("shed")
	pc._show_kind("eq:bench")
	check(not pv.visible and not pv.shadow.visible, "shed kit has neither")
	check(pc.theme.default_font_size < UITheme.make().default_font_size, "the page's words are a size smaller (%d)" % pc.theme.default_font_size)
	# Other turntables keep their see-through background.
	var plain := PartPreview.new()
	check(not plain.studio and plain.viewport.transparent_bg, "other pages' turntables are unchanged")
	plain.free()
	pc.queue_free()
	await _frames(2)
	Shed.stop()
