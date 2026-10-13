class_name Dashboard
extends Node3D
## A wall-mounted screen in the shed. It draws a 2D page into a SubViewport and shows it on a
## glowing panel. "crew" pages list every player; "bike" pages show one bike's numbers now
## against how it was delivered.

const PX := Vector2i(1024, 576)
const BG := Color(0.03, 0.05, 0.07)
const GOOD := Color(0.35, 0.9, 0.45)
const BAD := Color(1.0, 0.35, 0.25)
const DIM := Color(1, 1, 1, 0.55)

var kind := "bike"
var data := {}
var _viewport: SubViewport
var _page: Control


func _init(page_kind := "bike", width := 2.0) -> void:
	kind = page_kind
	_viewport = SubViewport.new()
	_viewport.size = PX
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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
	var bezel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.08, height + 0.08, 0.05)
	bezel.mesh = box
	var bezel_mat := StandardMaterial3D.new()
	bezel_mat.albedo_color = Color(0.04, 0.04, 0.045)
	bezel_mat.roughness = 0.4
	bezel.material_override = bezel_mat
	add_child(bezel)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.75, 1.0)
	glow.light_energy = 0.25
	glow.omni_range = 2.5
	glow.position.z = 0.6
	add_child(glow)


func show_data(new_data: Dictionary) -> void:
	data = new_data
	_page.queue_redraw()


func _draw_page() -> void:
	var font := _page.get_theme_default_font()
	_page.draw_rect(Rect2(Vector2.ZERO, Vector2(PX)), BG)
	_page.draw_rect(Rect2(0, 0, PX.x, 70), Color(1.0, 0.55, 0.15, 0.9))
	if kind == "crew":
		_draw_crew(font)
	else:
		_draw_bike(font)


func _text(font: Font, pos: Vector2, text: String, size: int, color := Color.WHITE, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_page.draw_string(font, pos, text, align, width, size, color)


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
	if data.is_empty():
		_text(font, Vector2(24, 50), "EMPTY BAY", 40, Color(0.05, 0.05, 0.05))
		_text(font, Vector2(24, 160), "Order a project bike from the Esc menu,", 28, DIM)
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
