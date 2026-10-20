class_name PhotoCapture
extends Node
## Takes photos of the game as it's being played, for the Adventure Diary (see AdventurePhotos),
## without a stutter: the frame's picture is copied off the graphics card in the background
## (RenderingDevice.texture_get_data_async, so nothing waits on the card), and shrunk, turned into
## a JPEG and written to disk on a worker thread. The main thread only asks, and hands over.
##
## The HUD isn't in the photo: for the one frame that's taken, the screen's 2D is culled
## (Viewport.canvas_cull_mask), so it's the world and the riders in it. A clip (a short "movie")
## is CLIP_FRAMES of these a CLIP_RATE apart, each shrunk to a cell of a flipbook sheet, the
## sheet one JPEG the diary plays back a cell at a time.
##
## On the Compatibility renderer there's no RenderingDevice, so it reads the frame back the old
## way (a short wait on the card, now and then); headless there's no picture at all, unless the
## tests give it one (fake_source).

## A photo's size, and a clip's cells and how they're laid out on its sheet.
const PHOTO_W := 960
const PHOTO_H := 540
const CLIP_W := 320
const CLIP_H := 180
const CLIP_FRAMES := 12
const CLIP_COLS := 4
const CLIP_RATE := 0.25
const CELL_GRACE_MS := 30000   # how long a filmed clip waits for its last cells from the workers
const JPEG_QUALITY := 0.86
const THUMB_W := 192
const THUMB_H := 108

## A photo (or a clip) is saved: `job` as it was asked for, with "file" (its path), "w", "h",
## "image" (a thumbnail, THUMB_W wide, for the HUD; a clip's first cell) and, when the job asked
## for it with "share", "share_bytes" (the smaller JPEG for the crew, see DiaryShare).
signal saved(job: Dictionary)

## Tests and headless runs: a Callable returning the frame as an Image (null for none).
static var fake_source: Callable = Callable()

## The viewport photos are taken of (the game's own window by default).
var viewport: Viewport
## How long, on the main thread, each step took (ms): the ask, the hand over, the last frame's
## upkeep. The tests watch these.
var last_ask_ms := 0.0
var last_hand_ms := 0.0
var last_tick_ms := 0.0
var _armed := false        # waiting for this frame to be drawn
var _jobs: Array = []      # photos to take of the next frame drawn
var _cull := 0             # the cull mask to put back
var _results := _Results.new()
var _tasks: Array = []
var _clips := {}           # clip id -> {job, frames: Array[Image or null], got, asked, next_at}
var _clip_n := 0
var _told := false         # results waiting with no worker behind them (nothing to take)
var _armed_at := 0         # the frame it was asked in (headless, no frame is ever drawn)


class _Results extends RefCounted:
	var mutex := Mutex.new()
	var done: Array = []
	var cells := {}         # clip id -> {index: Image}


func _ready() -> void:
	name = "PhotoCapture"
	if viewport == null:
		viewport = get_viewport()


func _exit_tree() -> void:
	wait_all()
	if _armed and viewport:
		viewport.canvas_cull_mask = _cull
		_armed = false


## Whether a photo is being worked on (asked for, on the card, or on a worker).
func busy() -> bool:
	return _armed or not _tasks.is_empty() or not _clips.is_empty() or _told


## Takes a photo of the next frame: `job` is anything to keep with it, with "path" (where the
## JPEG goes; its folder is made). `hud` true keeps the HUD in it.
func snap(job: Dictionary, hud := false) -> void:
	var t0 := Time.get_ticks_usec()
	var j := job.duplicate()
	j["hud"] = hud
	_jobs.append(j)
	_arm(hud)
	last_ask_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Films a clip: CLIP_FRAMES frames CLIP_RATE apart, saved as one flipbook sheet at job["path"].
## Returns its id.
func film(job: Dictionary) -> int:
	_clip_n += 1
	var j := job.duplicate()
	j["clip"] = true
	j["frames"] = CLIP_FRAMES
	j["cols"] = CLIP_COLS
	j["rows"] = ceili(float(CLIP_FRAMES) / CLIP_COLS)
	j["cell_w"] = CLIP_W
	j["cell_h"] = CLIP_H
	_clips[_clip_n] = {"job": j, "got": 0, "asked": 0, "next_at": 0.0, "t": 0.0}
	return _clip_n


## Whether a clip's still being filmed (not just worked on).
func filming() -> bool:
	for id in _clips:
		if int(_clips[id]["asked"]) < CLIP_FRAMES:
			return true
	return false


func _arm(hud: bool) -> void:
	if viewport == null:
		viewport = get_viewport()
	if not _armed:
		_armed = true
		_armed_at = Engine.get_process_frames()
		_cull = viewport.canvas_cull_mask
		RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)
	if not hud:
		viewport.canvas_cull_mask = 0


## The frame's been drawn: the HUD back, and its picture asked for.
func _grab() -> void:
	_armed = false
	if viewport == null or not is_instance_valid(viewport):
		_jobs.clear()
		return
	viewport.canvas_cull_mask = _cull
	var jobs := _jobs
	_jobs = []
	if jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	if fake_source.is_valid():
		var img = fake_source.call()
		_hand_over(jobs, img if img is Image else null)
	else:
		var rd := RenderingServer.get_rendering_device()
		var tex := viewport.get_texture()
		var rd_tex := RenderingServer.texture_get_rd_texture(tex.get_rid()) if rd != null and tex != null else RID()
		if rd != null and rd_tex.is_valid():
			var fmt := rd.texture_get_format(rd_tex)
			var err := rd.texture_get_data_async(rd_tex, 0, _on_data.bind(jobs, fmt.width, fmt.height, fmt.format))
			if err != OK:
				_hand_over(jobs, tex.get_image())
		elif tex != null and DisplayServer.get_name() != "headless":
			_hand_over(jobs, tex.get_image())   # the Compatibility renderer: read back the old way
		else:
			_hand_over(jobs, null)
	last_hand_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The card's sent the frame back (raw bytes): over to a worker.
func _on_data(data: PackedByteArray, jobs: Array, w: int, h: int, format: int) -> void:
	_tasks.append(WorkerThreadPool.add_task(_work_raw.bind(data, w, h, format, jobs, _results), true, "photo"))


func _hand_over(jobs: Array, img: Image) -> void:
	if img == null or img.is_empty():
		_results.mutex.lock()
		for j in jobs:
			_results.done.append({"job": j, "failed": true})
		_results.mutex.unlock()
		_told = true
		return
	_tasks.append(WorkerThreadPool.add_task(_work_image.bind(img, jobs, _results), true, "photo"))


# ---------------------------------------------------------------------------- on a worker

static func _work_raw(data: PackedByteArray, w: int, h: int, format: int, jobs: Array, box: _Results) -> void:
	var img: Image = null
	match format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			if data.size() >= w * h * 4:
				img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		RenderingDevice.DATA_FORMAT_B8G8R8A8_UNORM, RenderingDevice.DATA_FORMAT_B8G8R8A8_SRGB:
			if data.size() >= w * h * 4:
				var swapped := data.duplicate()
				for i in range(0, w * h * 4, 4):
					swapped[i] = data[i + 2]
					swapped[i + 2] = data[i]
				img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, swapped)
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			if data.size() >= w * h * 8:
				img = Image.create_from_data(w, h, false, Image.FORMAT_RGBAH, data)
				img.convert(Image.FORMAT_RGBA8)
				img.linear_to_srgb()
	if img == null:
		box.mutex.lock()
		for j in jobs:
			box.done.append({"job": j, "failed": true})
		box.mutex.unlock()
		return
	_work_image(img, jobs, box)


## Shrinks `src` for each job (a photo, or a clip's cell), and writes the photos out.
static func _work_image(src: Image, jobs: Array, box: _Results) -> void:
	for j in jobs:
		var img := src.duplicate() as Image
		if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGBA8)
		var cell: bool = j.has("cell")
		var w := int(j.get("cell_w", CLIP_W)) if cell else PHOTO_W
		var h := int(j.get("cell_h", CLIP_H)) if cell else PHOTO_H
		img = fit(img, w, h)
		if cell:
			box.mutex.lock()
			if not box.cells.has(int(j["clip_id"])):
				box.cells[int(j["clip_id"])] = {}
			box.cells[int(j["clip_id"])][int(j["cell"])] = img
			box.mutex.unlock()
			continue
		var ok := _write(img, str(j.get("path", "")))
		var thumb := img.duplicate() as Image   # for the HUD: small, so it's cheap to show
		thumb.resize(THUMB_W, THUMB_H, Image.INTERPOLATE_BILINEAR)
		var share := _share_bytes(img) if bool(j.get("share", false)) and ok else PackedByteArray()
		box.mutex.lock()
		box.done.append({"job": j, "image": thumb, "failed": not ok, "w": w, "h": h, "share": share})
		box.mutex.unlock()


## `img` cut to `w` x `h`'s shape from its middle and shrunk to it (in halves first, then the
## last step smoothly: sharp, without the shimmer one big jump gives).
static func fit(img: Image, w: int, h: int) -> Image:
	var aspect := float(w) / float(h)
	var cw := mini(img.get_width(), roundi(img.get_height() * aspect))
	var ch := mini(img.get_height(), roundi(cw / aspect))
	if cw != img.get_width() or ch != img.get_height():
		img = img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
	while img.get_width() >= w * 2 and img.get_height() >= h * 2:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	if img.get_width() != w or img.get_height() != h:
		img.resize(w, h, Image.INTERPOLATE_CUBIC)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


## The smaller JPEG of `img` sent to the crew (see DiaryShare): at most DiaryShare.SHARE_W wide.
static func _share_bytes(img: Image) -> PackedByteArray:
	var small := img
	if img.get_width() > DiaryShare.SHARE_W:
		small = img.duplicate() as Image
		small.resize(DiaryShare.SHARE_W, roundi(img.get_height() * float(DiaryShare.SHARE_W) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	return small.save_jpg_to_buffer(DiaryShare.SHARE_QUALITY)


static func _write(img: Image, path: String) -> bool:
	if path == "":
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_jpg(path, JPEG_QUALITY) == OK


## A clip's cells laid out on its sheet, and written.
static func _work_sheet(cells: Dictionary, job: Dictionary, box: _Results) -> void:
	var cols := int(job["cols"])
	var rows := int(job["rows"])
	var cw := int(job["cell_w"])
	var chh := int(job["cell_h"])
	var sheet := Image.create(cw * cols, chh * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.05))
	var first: Image = null
	var got := 0
	for i in int(job["frames"]):
		var c: Image = cells.get(i)
		if c == null:
			continue
		got += 1
		if first == null:
			first = c
		sheet.blit_rect(c, Rect2i(0, 0, cw, chh), Vector2i((i % cols) * cw, (i / cols) * chh))
	var ok := got > 0 and _write(sheet, str(job.get("path", "")))
	job["got"] = got
	# (A clip's sheet goes to the crew whole: its cells are what's played.)
	var share := sheet.save_jpg_to_buffer(DiaryShare.SHARE_QUALITY) if bool(job.get("share", false)) and ok else PackedByteArray()
	box.mutex.lock()
	box.done.append({"job": job, "image": first, "failed": not ok, "w": cw * cols, "h": chh * rows, "share": share})
	box.mutex.unlock()


# ---------------------------------------------------------------------------- each frame

func _process(delta: float) -> void:
	if _tasks.is_empty() and _clips.is_empty() and not _told and not _armed:
		return
	_told = false
	var pt := Perf.t0()
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	last_tick_ms = (Time.get_ticks_usec() - t0) / 1000.0
	Perf.add("photos", pt)


func _tick(delta: float) -> void:
	if _armed and Engine.get_process_frames() > _armed_at + 1:
		# No frame drawn since it was asked for (headless): taken anyway.
		if RenderingServer.frame_post_draw.is_connected(_grab):
			RenderingServer.frame_post_draw.disconnect(_grab)
		_grab()
	# The clips being filmed: a cell asked for every CLIP_RATE.
	for id in _clips.keys():
		var c: Dictionary = _clips[id]
		c["t"] = float(c["t"]) + delta
		if int(c["asked"]) < CLIP_FRAMES and float(c["t"]) >= float(c["next_at"]):
			var cell := {"clip_id": int(id), "cell": int(c["asked"]), "cell_w": CLIP_W, "cell_h": CLIP_H}
			c["asked"] = int(c["asked"]) + 1
			if int(c["asked"]) >= CLIP_FRAMES:
				c["filmed_ms"] = Time.get_ticks_msec()
			c["next_at"] = float(c["next_at"]) + CLIP_RATE
			_jobs.append(cell)
			_arm(false)
	# Workers done: tidied up, and what's saved told.
	var k := 0
	while k < _tasks.size():
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.remove_at(k)
		else:
			k += 1
	_results.mutex.lock()
	var done := _results.done
	_results.done = []
	var cells := _results.cells
	_results.mutex.unlock()
	# A clip with every cell back (or failed to come back, past a while): its sheet made.
	for id in _clips.keys():
		var c: Dictionary = _clips[id]
		var have: Dictionary = cells.get(int(id), {})
		# (The workers can be busy a while, building the road: a cell's given half a minute, on
		# the clock rather than in game time, since frames can run faster than real time.)
		var late := int(c["asked"]) >= CLIP_FRAMES and Time.get_ticks_msec() - int(c.get("filmed_ms", 0)) > CELL_GRACE_MS
		if int(c["asked"]) >= CLIP_FRAMES and (have.size() + int(c.get("lost", 0)) >= CLIP_FRAMES or late) and not _armed:
			_clips.erase(id)
			_results.mutex.lock()
			_results.cells.erase(int(id))
			_results.mutex.unlock()
			_tasks.append(WorkerThreadPool.add_task(_work_sheet.bind(have.duplicate(), (c["job"] as Dictionary).duplicate(), _results), true, "clip"))
	for r in done:
		var job: Dictionary = r["job"]
		if job.has("cell"):
			if _clips.has(int(job["clip_id"])):
				_clips[int(job["clip_id"])]["lost"] = int(_clips[int(job["clip_id"])].get("lost", 0)) + 1   # no picture for it
			continue
		if bool(r.get("failed", false)):
			job["failed"] = true
		job["file"] = str(job.get("path", ""))
		job["w"] = int(r.get("w", 0))
		job["h"] = int(r.get("h", 0))
		job["image"] = r.get("image")
		job["share_bytes"] = r.get("share", PackedByteArray())
		saved.emit(job)


## Waits for every worker (leaving, or the tests).
func wait_all() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
