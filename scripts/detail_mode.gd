class_name DetailMode
extends RefCounted
## The polisher in your hands with the detailing controls up (F with it on a washed bike in the
## wash bay): what the Walker hands its frames to while you polish or coat a bike (DetailJob),
## like the wash controls (see Walker.enter_wash_mode). F settles you in at the bike (a moment
## to get set before the pad works), F again steps back. T switches between polishing and ceramic
## coating; X is the scan (dull amber, burnt red, smeared purple, good green).
##   Polishing: hold the work button with the pad on the paint, the second button to lean on it
##   (quicker, and hotter: the whine drops as it bogs down). Keep it moving.
##   Coating: hold the work button to wipe the coat on with the applicator (along the bike, then
##   across it), and the second button to buff the residue off with the microfibre in time.
## The crew hear the polisher (your status says you're polishing) and see the paint change as
## each update reaches the shed.

const SETTLE := 0.8          # seconds to get set at the bike before the pad works
const SEND := 0.2            # how often what's been done goes to the shed
const PITCH_FREE := 1.12     # the polisher's pitch spinning free, on the paint, and leaned on
const PITCH_ON := 1.0
const PITCH_HARD := 0.86

var walker: Walker
var bike := 0
var mode := "polish"
var job: DetailJob
var settle := 0.0
var scan := false
var working := false          # the pad's working on the paint this frame
var pressing := false         # leaning on it (polish) or buffing (coat)
var cues: Array = []          # for the HUD: {kind, name}
var _sound := ""
var _send := 0.0
var _started := false
var _wait := 0.0


func _init(w: Walker) -> void:
	walker = w


func active() -> bool:
	return bike != 0


## F with the polisher on a bike: the detailing controls come up on it, if it's in the wash bay
## and (to polish) washed. `start_mode`: "polish" or "coat".
func enter(bike_id: int, start_mode := "") -> bool:
	if not Shed.bikes.has(bike_id):
		return false
	var at: Vector3 = (Shed.bikes[bike_id]["xf"] as Transform3D).origin
	if not Wash.reaches(at):
		Shed.feedback.emit(Detail.NO_REACH, false)
		return false
	if Detail.panels_of(bike_id).is_empty():
		Shed.feedback.emit("There's no painted panel on it to polish.", false)
		return false
	if start_mode != "":
		mode = start_mode
	if mode == "polish" and not Detail.clean_enough(bike_id):
		Shed.feedback.emit(Detail.WASH_FIRST, false)
		return false
	bike = bike_id
	settle = SETTLE
	job = null
	cues.clear()
	_send = SEND
	_wait = 0.0
	_started = false
	# Panels with no finish of their own get the default one, so the bike's drawn with it.
	Shed.request({"a": "shine_start", "bike": bike})
	Sfx.play_at("switch", walker.camera.global_position, -8.0)
	return true


## F again (or putting the polisher away, or the bike going): the controls go and what's been
## done goes to the shed.
func leave() -> void:
	if bike == 0:
		return
	_send_updates()
	if job != null:
		job.finish()
	job = null
	bike = 0
	working = false
	pressing = false
	_set_sound("")
	walker.call("_send_status", "")


## T: polishing or coating.
func switch_mode() -> void:
	mode = "coat" if mode == "polish" else "polish"
	if job != null:
		job.mode = mode
		job._stats_age = 1.0
	settle = maxf(settle, SETTLE * 0.5)
	Shed.feedback.emit("Polisher: compound on, the pad buffs the swirls out" if mode == "polish" else
		"Ceramic coat: wipe it on with the applicator, across and back; buff it off with the microfibre", true)
	Sfx.play_at("switch", walker.camera.global_position, -6.0)


func set_scan(on: bool) -> void:
	scan = on
	if job != null and job.layer != null and is_instance_valid(job.layer):
		job.layer.set_scan(on)
	Sfx.play_at("blast_scan" if on else "switch", walker.camera.global_position, -6.0)


## One frame with the controls up.
func step(delta: float) -> void:
	if not Shed.bikes.has(bike) or int(Shed.bikes[bike].get("rider", 0)) != 0 or walker.tool != "polisher" \
			or Shed.held_by(Shed.me()) != 0:
		leave()
		return
	var view: Node = walker.get_tree().get_first_node_in_group("workshop")
	var model: BikeModel = view.bike_model(bike) if view and view.has_method("bike_model") else null
	if model == null or walker.camera.global_position.distance_to(model.global_position) > 4.0:
		Shed.feedback.emit("Too far from the bike: the detailing controls are down.", false)
		leave()
		return
	if job == null or not job.attached():
		# Not drawn with its panels' finish yet (it is a moment after shine_start), or redrawn.
		if job != null:
			_send_updates()
		var made := DetailJob.new()
		if not made.setup(bike, model, mode):
			job = null
			_wait += delta
			if _wait > 3.0:
				Shed.feedback.emit("There's no paint on it the pad can get to.", false)
				leave()
			return
		job = made
		job.layer.set_scan(scan)
	job.prepare()
	settle = maxf(0.0, settle - delta)
	var work: bool = walker.controls_enabled and bool(walker.call("_main_button")) and settle <= 0.0
	var alt: bool = walker.controls_enabled and (Input.is_action_pressed("alt_act") or Controls.trigger(false) > 0.5) and settle <= 0.0
	if mode == "polish" and (work or alt) and not Detail.clean_enough(bike):
		Shed.feedback.emit(Detail.WASH_FIRST, false)
		work = false
		alt = false
	var eye := walker.camera.global_position
	var dir := -walker.camera.global_transform.basis.z
	# In polish mode the second button only leans on the pad that's already running.
	var polish_on: bool = mode == "polish" and work
	job.step(delta, eye, dir, polish_on or (mode == "coat" and work), alt and (mode == "coat" or work),
		1.0 + Progress.STAGE_SPEED * Progress.tool_stage(Shed.me(), "polisher"))
	var contact: bool = job.pad.get("contact", false)
	working = contact and (polish_on or (mode == "coat" and (work or alt)))
	pressing = alt
	walker.progress = float(job.stats()["gloss" if mode == "polish" else "coat"]) if job.ready else 0.0
	# The sound: the polisher's whine, lower as you lean on it and higher spinning free; the
	# applicator and towel are a soft rub.
	if mode == "polish":
		_set_sound("polisher" if polish_on else "")
		if polish_on:
			var p := PITCH_HARD if alt and contact else (PITCH_ON if contact else PITCH_FREE)
			var snd: AudioStreamPlayer3D = walker._work_sound
			if snd:
				var base := float(snd.get_meta("base_pitch", 1.0))
				snd.pitch_scale = lerpf(snd.pitch_scale, base * p, minf(1.0, delta * 8.0))
	else:
		_set_sound("scrub" if working else "")
	walker.call("_send_status", ("Polishing" if mode == "polish" else "Ceramic coating") if working or polish_on else "")
	for c in job.cues:
		cues.append(c)
		match str(c["kind"]):
			"burn":
				Sfx.play_ui("scrap", -6.0)
				Shed.feedback.emit("Burnt through the clear coat on the %s! Keep the pad moving." % str(c["name"]).to_lower(), false)
			"smear":
				Sfx.play_ui("beep", -8.0)
				Shed.feedback.emit("The coat flashed on the %s before it was buffed: a smear to polish off." % str(c["name"]).to_lower(), false)
			_:
				Sfx.play_ui("wash_ding", -5.0)
	job.cues.clear()
	_send -= delta
	if _send <= 0.0:
		_send = SEND
		_send_updates()


func _send_updates() -> void:
	if job == null or not job.ready:
		return
	var news := job.take_updates()
	if not news.is_empty():
		Shed.request({"a": "shine_cells", "bike": bike, "parts": news})


func _set_sound(s: String) -> void:
	if s == _sound:
		return
	_sound = s
	var snd: AudioStreamPlayer3D = walker._work_sound
	if snd == null:
		return
	Sfx.set_loop(snd, s)
	if s == "":
		snd.pitch_scale = float(snd.get_meta("base_pitch", 1.0))
	elif s == "scrub":
		snd.pitch_scale = float(snd.get_meta("base_pitch", 1.0)) * 0.8


## How to work it, for the HUD.
func controls() -> String:
	if mode == "polish":
		return Controls.hint("Hold {work} with the pad on the paint and keep it moving  ·  hold {work2} too to lean on it (quicker, hotter)  ·  {spray_finish}: ceramic coat  ·  {blast_scan}: scan  ·  {interact}: step back")
	return Controls.hint("Hold {work} to wipe the coat on: along the bike, then across  ·  hold {work2} to buff it off before it flashes  ·  {spray_finish}: polisher  ·  {blast_scan}: scan  ·  {interact}: step back")
