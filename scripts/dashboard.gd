class_name Dashboard
extends Node3D
## A wall-mounted screen in the shed. It draws a 2D page into a SubViewport and shows it on a
## glowing panel. "crew" pages list every player; "bike" pages show one bike's numbers now
## against how it was delivered; the rest are TV channels drawn by TvChannels. It can also show
## a live picture over the page (the riding feed), and flashes the channel name when it changes.

const PX := Vector2i(1024, 576)
const BG := Color(0.03, 0.05, 0.07)
const GOOD := Color(0.35, 0.9, 0.45)
const BAD := Color(1.0, 0.35, 0.25)
const DIM := Color(1, 1, 1, 0.55)
const OSD_TIME := 2.5

var kind := "bike"
var data := {}
var width := 2.0
var _viewport: SubViewport
var _page: Control
var _feed: MeshInstance3D
var _feed_mat: StandardMaterial3D
var _caption: Label3D
var _osd: Label3D
var _osd_left := 0.0
var _osd_bg: MeshInstance3D


func _init(page_kind := "bike", screen_width := 2.0) -> void:
	kind = page_kind
	width = screen_width
	_viewport = SubViewport.new()
	_viewport.size = PX
	# The page is drawn once each time it changes (show_data()), not every frame it's in view:
	# a shed full of screens otherwise redrew a dozen pages sixty times a second indoors.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.transparent_bg = false
	add_child(_viewport)
	_page = Control.new()
	_page.size = Vector2(PX)
	_page.draw.connect(_draw_page)
	_viewport.add_child(_page)
	var height := width * PX.y / PX.x
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = _viewport.get_texture()
	mat.emission_energy_multiplier = 0.6
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.material_override = mat
	screen.position.z = 0.03
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	# The screen glows on whatever is in front of it: with the shed lights off, screens are
	# the light you work by. A wide spot from the face of the screen, pointing out into the
	# room, so nothing behind it (the wall round it, or the room through the wall) is lit.
	var spill := SpotLight3D.new()
	spill.name = "Spill"
	spill.position = Vector3(0.0, 0.0, 0.06)
	spill.spot_angle = 70.0
	spill.spot_angle_attenuation = 1.6
	spill.spot_range = 2.5 + width * 1.3
	spill.spot_attenuation = 1.4
	spill.light_energy = 0.5 + width * 0.18
	spill.light_color = Color(0.72, 0.84, 1.0)
	spill.shadow_enabled = false
	spill.light_specular = 0.2
	# A SpotLight3D shines down its -Z; turned round it shines out of the screen's face.
	spill.rotation.y = PI
	add_child(spill)
	var bezel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.08, height + 0.08, 0.05)
	bezel.mesh = box
	var bezel_mat := StandardMaterial3D.new()
	bezel_mat.albedo_color = Color(0.04, 0.04, 0.045)
	bezel_mat.roughness = 0.4
	bezel.material_override = bezel_mat
	add_child(bezel)
	# The live picture sits just in front of the page, with a caption along its bottom.
	_feed_mat = StandardMaterial3D.new()
	_feed_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feed = MeshInstance3D.new()
	var feed_quad := QuadMesh.new()
	feed_quad.size = Vector2(width, height)
	_feed.mesh = feed_quad
	_feed.material_override = _feed_mat
	_feed.position.z = 0.032
	_feed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_feed.visible = false
	add_child(_feed)
	_caption = Label3D.new()
	_caption.font_size = 32
	_caption.pixel_size = width / 1400.0
	_caption.outline_size = 8
	_caption.modulate = Color(1.0, 0.9, 0.5)
	_caption.position = Vector3(0.0, -height * 0.5 + width * 0.04, 0.034)
	_caption.visible = false
	add_child(_caption)
	# The on-screen display: the channel's number and name, top left, for a moment after a change.
	_osd = Label3D.new()
	_osd.font_size = 64
	_osd.pixel_size = width / 1700.0
	_osd.outline_size = 14
	_osd.outline_modulate = Color(0, 0, 0, 0.9)
	_osd.modulate = Color(0.45, 1.0, 0.5)
	_osd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_osd.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Just under the page's header bar, on a dark band so it reads over whatever is underneath.
	_osd.position = Vector3(-width * 0.5 + width * 0.04, height * 0.5 - height * 0.16, 0.039)
	_osd.visible = false
	add_child(_osd)
	_osd_bg = MeshInstance3D.new()
	_osd_bg.mesh = QuadMesh.new()
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.85)
	_osd_bg.material_override = bg_mat
	_osd_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_osd_bg.visible = false
	add_child(_osd_bg)


func _ready() -> void:
	# The pages' key hints read again when the player picks up the other controls.
	Controls.device_changed.connect(_on_device_changed)


func _on_device_changed(_pad: bool) -> void:
	show_data(data)


func show_data(new_data: Dictionary) -> void:
	data = new_data
	_page.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Switches to another page (see TvChannels.PAGES) with its data.
func show_page(page_kind: String, new_data: Dictionary) -> void:
	kind = page_kind
	show_data(new_data)


## Shows the live picture over the page (null goes back to the page) with a caption such as
## "LIVE: Simon on Old Faithful".
func show_feed(texture: Texture2D, caption: String) -> void:
	_feed.visible = texture != null
	_caption.visible = texture != null
	if texture:
		_feed_mat.albedo_texture = texture
		_caption.text = caption


func is_live() -> bool:
	return _feed.visible


## Flashes "CH 3  XP GOALS" in the corner, like a real TV does when you change channel.
func show_osd(text: String) -> void:
	_osd.text = text
	_osd.visible = true
	_osd_left = OSD_TIME
	# The band fits the text: about 0.62 of the font size per letter.
	var line_h := _osd.font_size * _osd.pixel_size
	var w := text.length() * line_h * 0.62 + line_h
	(_osd_bg.mesh as QuadMesh).size = Vector2(w, line_h * 1.5)
	_osd_bg.position = _osd.position + Vector3(w * 0.5 - line_h * 0.5, -line_h * 0.55, -0.0015)
	_osd_bg.visible = true


func osd_text() -> String:
	return _osd.text if _osd.visible else ""


func _process(delta: float) -> void:
	if _osd_left > 0.0:
		_osd_left -= delta
		if _osd_left <= 0.0:
			_osd.visible = false
			_osd_bg.visible = false


func _draw_page() -> void:
	var font := _page.get_theme_default_font()
	_page.draw_rect(Rect2(Vector2.ZERO, Vector2(PX)), BG)
	_page.draw_rect(Rect2(0, 0, PX.x, 70), Color(1.0, 0.55, 0.15, 0.9))
	if kind == "crew":
		_draw_crew(font)
	elif kind == "bike":
		_draw_bike(font)
	else:
		TvChannels.draw_page(_page, font, kind, data)


func _text(font: Font, pos: Vector2, text: String, size: int, color := Color.WHITE, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_page.draw_string(font, pos, Controls.hint(text), align, width, size, color)


func _draw_crew(font: Font) -> void:
	_text(font, Vector2(24, 50), "THE CREW", 40, Color(0.05, 0.05, 0.05))
	var players: Array = data.get("players", [])
	if players.is_empty():
		_text(font, Vector2(24, 140), "Nobody here yet.", 30, DIM)
		return
	var cols := ["", "Doing", "Fitted", "Painted", "Cleaned", "Restored", Units.distance_unit(), "Top " + Units.speed_unit()]
	var xs := [24, 230, 560, 650, 750, 850, 945, 1000]
	for i in cols.size():
		if i >= 2:
			_text(font, Vector2(xs[i] - 40, 105), cols[i], 18, DIM, 90, HORIZONTAL_ALIGNMENT_RIGHT)
		elif i == 1:
			_text(font, Vector2(xs[i], 105), cols[i], 18, DIM)
	var y := 150.0
	for p in players:
		_page.draw_rect(Rect2(14, y - 34, PX.x - 28, 52), Color(1, 1, 1, 0.04))
		_page.draw_rect(Rect2(14, y - 34, 8, 52), p.get("color", Color.WHITE))
		_text(font, Vector2(34, y), str(p["name"]).left(14), 28)
		_text(font, Vector2(xs[1], y), str(p.get("doing", "")).left(30), 20, Color(1, 0.8, 0.55))
		var nums := [p.get("fitted", 0), p.get("painted", 0), p.get("cleaned", 0), p.get("repaired", 0),
			"%.1f" % Units.distance_value(float(p.get("km", 0.0))), "%d" % Units.speed_value(float(p.get("top_kmh", 0.0)) / 3.6)]
		for i in nums.size():
			_text(font, Vector2(xs[i + 2] - 40, y), str(nums[i]), 24, Color.WHITE, 90, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 62.0
		if y > PX.y - 20:
			break


## A summary number in the units the player picked.
func _shown(key: String, v: float) -> float:
	match key:
		"health":
			return v * 100.0
		"top_kmh":
			return float(Units.speed_value(v / 3.6))
		"mass":
			return Units.mass_value(v)
		"economy":
			return Units.economy_value(v)
		"pw":
			return v * 100.0 / (Units.LB_PER_KG if Units.imperial() else 1.0)
	return v


func _draw_bike(font: Font) -> void:
	if data.has("blueprint"):
		_draw_blueprint(font)
		return
	if data.has("contract"):
		_draw_contract(font)
		return
	if data.is_empty():
		_text(font, Vector2(24, 50), "EMPTY BAY", 40, Color(0.05, 0.05, 0.05))
		_text(font, Vector2(24, 160), "Order a project bike from the {menu} menu,", 28, DIM)
		_text(font, Vector2(24, 200), "or ride one in and park it here.", 28, DIM)
		return
	_text(font, Vector2(24, 50), str(data["name"]).to_upper(), 40, Color(0.05, 0.05, 0.05))
	var status: String = data.get("status", "")
	_text(font, Vector2(560, 48), status, 24, Color(0.05, 0.05, 0.05), 440, HORIZONTAL_ALIGNMENT_RIGHT)
	var now: Dictionary = data["now"]
	var was: Dictionary = data["delivered"]
	var rows := [
		["Power", "hp", "hp", "%.0f", true],
		["Torque", "torque", "Nm", "%.0f", true],
		["Top speed", "top_kmh", Units.speed_unit(), "%.0f", true],
		["Weight", "mass", Units.mass_unit(), "%.0f", false],
		["hp per 100 " + Units.mass_unit(), "pw", "", "%.1f", true],
		["Brakes", "brake", "Nm", "%.0f", true],
		["Economy", "economy", Units.economy_unit(), "%.1f" if not Units.imperial() else "%.0f", Units.imperial()],
		["Condition", "health", "%", "%.0f", true],
	]
	_text(font, Vector2(220, 108), "NOW", 16, DIM, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(font, Vector2(340, 108), "DELIVERED", 16, DIM, 110, HORIZONTAL_ALIGNMENT_RIGHT)
	var y := 146.0
	for r in rows:
		var key: String = r[1]
		var v_now := _shown(key, float(now.get(key, 0.0)))
		var v_was := _shown(key, float(was.get(key, 0.0)))
		var diff := v_now - v_was
		var better: bool = diff > 0.0 if r[4] else diff < 0.0
		_text(font, Vector2(24, y), r[0], 24, DIM)
		_text(font, Vector2(220, y), (r[3] % v_now) + " " + r[2], 26, Color.WHITE, 120, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(font, Vector2(340, y), (r[3] % v_was), 22, DIM, 110, HORIZONTAL_ALIGNMENT_RIGHT)
		if absf(diff) >= 0.5:
			_text(font, Vector2(462, y), ("+" if diff > 0 else "") + (r[3] % diff), 20, GOOD if better else BAD)
		y += 40.0
	# What doesn't suit: fuel starvation, overheating, worn plugs.
	for note in data.get("notes", []):
		_text(font, Vector2(24, y + 6), str(note).left(46), 17, Color(1.0, 0.75, 0.3))
		y += 26.0
		if y > PX.y - 90:
			break
	# Fluid levels along the bottom: petrol, oil and both brakes.
	var fluids: Array = data.get("fluids", [])
	for i in fluids.size():
		var f: Array = fluids[i]
		var fx := 24.0 + i * 130.0
		var level := clampf(float(f[1]), 0.0, 1.0)
		_text(font, Vector2(fx, PX.y - 40), str(f[0]), 15, DIM)
		_page.draw_rect(Rect2(fx, PX.y - 30, 110, 14), Color(1, 1, 1, 0.1))
		var col := BAD if level < 0.3 else (Color(1.0, 0.75, 0.3) if level < 0.6 or float(f[2]) > 0.6 else GOOD)
		_page.draw_rect(Rect2(fx, PX.y - 30, 110 * level, 14), col)
	if not fluids.is_empty():
		_text(font, Vector2(24, PX.y - 62), "Range on this tank: %s" % Units.distance(float(data.get("range_km", 0.0)), 0), 16, DIM)
	# Part list with condition bars, in two columns.
	var parts: Array = data.get("parts", [])
	var rows_per_col := 16
	for i in parts.size():
		var p: Dictionary = parts[i]
		var px := 560.0 + (i / rows_per_col) * 232.0
		var py := 84.0 + (i % rows_per_col) * 30.0
		_text(font, Vector2(px, py + 14), str(p["name"]).left(19), 14, Color.WHITE if p["fitted"] else BAD)
		if p["fitted"]:
			var h := float(p["health"])
			_page.draw_rect(Rect2(px + 150, py + 3, 70, 12), Color(1, 1, 1, 0.1))
			_page.draw_rect(Rect2(px + 150, py + 3, 70 * h, 12), GOOD.lerp(BAD, 1.0 - h) if h < 0.95 else GOOD)
			if not p["bolted"]:
				_text(font, Vector2(px + 152, py + 26), "LOOSE", 11, Color(1, 0.85, 0.3))
		else:
			_text(font, Vector2(px + 150, py + 14), "MISSING", 12, BAD)


## A customer's bike: the job's checklist ticked off as the work gets done (an MOT's fails to
## fix under it), and on the right the deadline, the fee, the parts spent against the budget,
## what handing it back now pays and the profit after the parts.
func _draw_contract(font: Font) -> void:
	var job: Dictionary = data["contract"]
	var ink := Color(0.02, 0.08, 0.06)
	_page.draw_rect(Rect2(0, 0, PX.x, 70), Color(0.25, 0.8, 0.55, 0.95))
	_text(font, Vector2(24, 50), ("JOB: " + str(job.get("title", data.get("name", "")))).to_upper().left(28), 36, ink)
	_text(font, Vector2(560, 48), str(data.get("status", "")), 22, ink, 440, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(font, Vector2(24, 102), "%s for %s" % [job.get("kind", ""), job.get("customer", "")], 20, Color(0.6, 1.0, 0.8), 600)
	var rows: Array = job.get("rows", [])
	var met := int(job.get("met", 0))
	var frac := float(met) / maxf(1.0, rows.size())
	_page.draw_rect(Rect2(24, 114, 520, 14), Color(1, 1, 1, 0.1))
	_page.draw_rect(Rect2(24, 114, 520 * frac, 14), GOOD if met == rows.size() else Color(1.0, 0.75, 0.3))
	_text(font, Vector2(556, 127), "%d of %d done" % [met, rows.size()], 15, DIM)
	var y := 172.0
	for r in rows:
		var done := bool(r.get("done", false))
		var box := Rect2(24, y - 21, 24, 24)
		_page.draw_rect(box, GOOD if done else Color(1, 1, 1, 0.08))
		_page.draw_rect(box, GOOD if done else Color(1, 1, 1, 0.5), false, 2.0)
		if done:
			_page.draw_polyline(PackedVector2Array([Vector2(29, y - 9), Vector2(35, y - 3), Vector2(44, y - 17)]), BG, 3.5)
		_text(font, Vector2(60, y), str(r.get("text", "")).left(44), 19, Color(0.75, 0.95, 0.8) if done else Color.WHITE, 400)
		_text(font, Vector2(470, y), str(r.get("have", "")).left(22), 15, GOOD if done else DIM, 150, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 38.0
		if y > PX.y - 60:
			break
	if str(job.get("mot", "")) != "" and y < PX.y - 60:
		var fixes: Array = job.get("fixes", [])
		_text(font, Vector2(24, y), str(job["mot"]), 17, BAD if not fixes.is_empty() else Color(1.0, 0.75, 0.3), 600)
		y += 26.0
		for f in fixes:
			if y > PX.y - 46:
				break
			_text(font, Vector2(40, y), "FAIL  %s: %s" % [f.get("text", ""), f.get("fix", "")], 14, Color(1.0, 0.6, 0.5), 580)
			y += 22.0
	# The deadline and the money, on the right.
	_page.draw_rect(Rect2(640, 86, 370, 430), Color(1, 1, 1, 0.04))
	var late := bool(job.get("late", false))
	_text(font, Vector2(656, 116), "DEADLINE", 15, DIM)
	_text(font, Vector2(656, 154), str(job.get("due", "")), 30, BAD if late else Color.WHITE, 340)
	_text(font, Vector2(656, 178), "due on day %d" % int(job.get("due_day", 1)), 15, DIM)
	var lines := [["Fee", int(job.get("fee", 0)), Color.WHITE]]
	if int(job.get("budget", 0)) > 0:
		lines.append(["Parts budget", int(job["budget"]), Color.WHITE])
	lines.append(["Parts spent so far", int(job.get("spent", 0)), BAD if int(job.get("over", 0)) > 0 else Color.WHITE])
	lines.append(["Hand back now pays", int(job.get("payout", 0)), Color(0.6, 1.0, 0.8)])
	var my := 226.0
	for l in lines:
		_text(font, Vector2(656, my), str(l[0]), 18, DIM)
		_text(font, Vector2(850, my), TvChannels.money_text(int(l[1])), 22, l[2], 150, HORIZONTAL_ALIGNMENT_RIGHT)
		my += 36.0
	var profit := int(job.get("profit", 0))
	_page.draw_line(Vector2(656, my - 18), Vector2(1000, my - 18), Color(1, 1, 1, 0.25), 1.0)
	_text(font, Vector2(656, my + 10), "Profit", 22, Color.WHITE)
	_text(font, Vector2(800, my + 10), TvChannels.money_text(profit), 30, GOOD if profit > 0 else BAD, 200, HORIZONTAL_ALIGNMENT_RIGHT)
	_page.draw_multiline_string(font, Vector2(656, my + 44), str(job.get("note", "")), HORIZONTAL_ALIGNMENT_LEFT, 344, 15, 3, DIM)
	if bool(job.get("ready", false)):
		_text(font, Vector2(24, PX.y - 16), "Ready: {menu}, Contracts, Hand back. The customer comes out for it.", 17, GOOD, 600)
	else:
		_text(font, Vector2(24, PX.y - 16), str(job.get("why", "")).left(70), 16, DIM, 600)


## A blueprint build's checklist: every part the blueprint needs, ticked off as it goes on.
func _draw_blueprint(font: Font) -> void:
	var blue := Color(0.45, 0.75, 1.0)
	_page.draw_rect(Rect2(0, 0, PX.x, 70), Color(0.2, 0.5, 0.95, 0.95))
	_text(font, Vector2(24, 50), ("BLUEPRINT: " + str(data["name"])).to_upper().left(30), 36, Color(0.02, 0.05, 0.1))
	_text(font, Vector2(560, 48), str(data.get("status", "")), 22, Color(0.02, 0.05, 0.1), 440, HORIZONTAL_ALIGNMENT_RIGHT)
	var rows: Array = data["blueprint"]
	var needed := rows.filter(func(r): return r["state"] == "needed").size()
	var ordered := rows.filter(func(r): return r["state"] == "ordered").size()
	var hint := "Hold a frame and put it on this bay's stand to start." if not data.get("framed", false) else \
		"Fit the parts the hologram shows. Ghost parts go as the real ones go on."
	_text(font, Vector2(24, 100), hint, 18, blue)
	_text(font, Vector2(24, 126), "%d needed, %d on order. Order missing parts at the parts computer or {menu}, Blueprints." % [needed, ordered], 16, DIM)
	var price := int(data.get("price", 0))
	_text(font, Vector2(24, PX.y - 18), "Price of what's needed: %s, from the business's account" % TvChannels.money_text(price), 16, DIM)
	var per_col := 13
	for i in rows.size():
		var r: Dictionary = rows[i]
		var col := i / per_col
		if col > 2:
			break
		var px := 24.0 + col * 336.0
		var py := 160.0 + (i % per_col) * 29.0
		var state := str(r["state"])
		var c := GOOD if state == "fitted" else (Color(1.0, 0.75, 0.3) if state in ["other", "ordered"] else BAD)
		var mark: String = {"fitted": "FITTED", "other": "OTHER PART", "ordered": "ON ORDER", "needed": "NEEDED"}.get(state, "")
		_text(font, Vector2(px, py), str(r["name"]).left(24), 15, Color.WHITE if state != "needed" else Color(1, 1, 1, 0.8))
		_text(font, Vector2(px + 220, py), mark, 12, c)
