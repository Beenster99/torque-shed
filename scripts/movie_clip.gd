class_name MovieClip
extends Node
## A ten-second film of the game (Simon: "can you make movie clip for 10 seconds with a countdown
## on the screen"). {movie} starts a countdown on the screen (3, 2, 1), then it films for LENGTH
## seconds with a red REC and the seconds left in the corner; {movie} again during the countdown
## calls it off, and while filming stops it early (what's filmed is kept). The film is saved as
## an AVI of JPEG frames (MjpegAvi, which Windows plays) in user://clips/, at FPS frames a second
## and at most MAX_W x MAX_H (the window's shape). On an adventure it's in the diary too (see
## AdventurePhotos.movie_job), on this machine only: a film's a few megabytes, too much to send
## the crew in the middle of a ride.
##
## Without a stutter: each frame filmed is copied off the graphics card in the background
## (RenderingDevice.texture_get_data_async, as PhotoCapture does for photos), shrunk and turned
## into a JPEG on a worker thread (the pool's low-priority ones, so the game's own threads, the
## road being built included, aren't crowded out), and the file's put together and written on a
## worker at the end.
## Should the workers fall behind, a frame's skipped (the one before it is shown twice), never
## waited for. The HUD's in the film as you see it, all but the countdown and REC (their own
## visibility layer, LAYER, is left out of the frames filmed). So that REC's still on the screen,
## no two frames running are filmed: a film frame due straight after one is taken a frame later
## (below 48 frames a second, some of the film's frames are the one before shown again).

## A film's been saved: {path (user://), file (the path on this computer), frames, w, h, secs,
## poster (an Image of a frame from it, for the HUD), job (as start() was given it)}.
signal saved(info: Dictionary)
## A film couldn't be saved (`why`, to say).
signal failed(why: String)

enum State { IDLE, COUNTDOWN, FILMING, SAVING }

const COUNTDOWN := 3.0
const LENGTH := 10.0
const FPS := 24
const MAX_W := 1280
const MAX_H := 720
const JPEG_QUALITY := 0.72
## Frames on the card or the workers at once; past this the next is skipped rather than waited for.
const MAX_PENDING := 12
## The frame of the film kept as its poster (one second in).
const POSTER_FRAME := FPS
## The countdown and REC's visibility layer (bit 20): it isn't in the frames filmed.
const LAYER := 1 << 19
## How long a finished film waits for its last frames from the workers (ms, on the clock).
const GRACE_MS := 20000

## Where the films are kept; the tests point it elsewhere.
static var root := "user://clips"
## Tests and headless runs: a Callable returning the frame as an Image (null for none).
static var fake_source: Callable = Callable()

## The viewport filmed (the game's own window by default).
var viewport: Viewport
var state := State.IDLE
## Time in the state (s).
var t := 0.0
## What start() was given, kept with the film (an adventure's diary entry).
var job := {}
## The film's size, frames asked for and the frames it'll have.
var w := 0
var h := 0
var asked := 0
var total := 0
## How long, on the main thread, the last frame's upkeep and the last frame's ask took (ms).
var last_tick_ms := 0.0
var last_grab_ms := 0.0
## Whether {movie} can start a film now: the game sets it (in a session, no menu up).
var can_film: Callable = Callable()
## The job a film's given when {movie} starts one (the game sets it: an adventure's diary entry).
var job_for: Callable = Callable()
var _box := _Box.new()
var _tasks: Array = []
var _next_at := 0.0
var _armed := false
var _armed_at := 0
var _due: Array = []           # the film's frame numbers this drawn frame stands for
var _ended_ms := 0
var _building := false
var _overlay: _Overlay
var _layer: CanvasLayer


## The frames back from the workers (a frame's number -> its JPEG), and the finished file.
class _Box extends RefCounted:
	var mutex := Mutex.new()
	var frames := {}
	var lost := {}
	var poster: Image = null
	var done := {}


func _ready() -> void:
	name = "MovieClip"
	if viewport == null:
		viewport = get_viewport()
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_overlay = _Overlay.new()
	_overlay.clip = self
	_overlay.visibility_layer = LAYER
	_overlay.visible = false
	_layer.add_child(_overlay)


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	if viewport and is_instance_valid(viewport):
		viewport.canvas_cull_mask |= LAYER


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("movie") or not event.is_action_pressed("movie") or event.is_echo():
		return
	if state == State.IDLE and can_film.is_valid() and not bool(can_film.call()):
		return
	get_viewport().set_input_as_handled()
	press()


## {movie} pressed: the countdown started, called off, or the filming stopped early.
func press() -> void:
	match state:
		State.IDLE:
			start(job_for.call() if job_for.is_valid() else {})
		State.COUNTDOWN:
			cancel()
		State.FILMING:
			stop()


## Starts the countdown, then the film. `j` is kept with it; with "poster_path" a frame's written
## there as a JPEG too. Returns why not ("" when it's started).
func start(j := {}) -> String:
	if state != State.IDLE:
		return "Already filming."
	job = j.duplicate()
	state = State.COUNTDOWN
	t = 0.0
	if viewport:
		viewport.canvas_cull_mask |= LAYER   # (should a photo have put its cull mask back over ours)
	_overlay.visible = true
	_overlay.queue_redraw()
	_beep(false)
	return ""


## Calls the countdown off.
func cancel() -> void:
	if state != State.COUNTDOWN:
		return
	state = State.IDLE
	_overlay.visible = false


## Stops filming now; what's filmed is saved (if there's anything).
func stop() -> void:
	if state != State.FILMING:
		return
	total = asked   # (any frame still due is taken, then it's saved)


## Whether it's counting down, filming or saving.
func busy() -> bool:
	return state != State.IDLE


## The countdown's number (3, 2, 1), 0 when it isn't counting down.
func count() -> int:
	return clampi(ceili(COUNTDOWN - t), 1, ceili(COUNTDOWN)) if state == State.COUNTDOWN else 0


## The seconds of film left to take.
func seconds_left() -> float:
	match state:
		State.COUNTDOWN:
			return LENGTH
		State.FILMING:
			return maxf(0.0, LENGTH - t)
	return 0.0


## The film's size for a window `size`: its shape, at most MAX_W x MAX_H, even numbers.
static func size_for(size: Vector2i) -> Vector2i:
	var k := minf(1.0, minf(float(MAX_W) / maxf(1.0, size.x), float(MAX_H) / maxf(1.0, size.y)))
	return Vector2i(maxi(16, roundi(size.x * k / 2.0) * 2), maxi(16, roundi(size.y * k / 2.0) * 2))


## Where a film started now is saved.
static func path_now() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var p := root.path_join("film_%s.avi" % stamp)
	var k := 2
	while FileAccess.file_exists(p):
		p = root.path_join("film_%s_%d.avi" % [stamp, k])
		k += 1
	return p


# ---------------------------------------------------------------------------- each frame

func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	var t0 := Time.get_ticks_usec()
	tick(delta)
	last_tick_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The countdown, the filming and the saving moved on by `delta` seconds.
func tick(delta: float) -> void:
	if _armed and Engine.get_process_frames() > _armed_at + 1:
		# No frame drawn since it was asked for (headless): taken anyway.
		if RenderingServer.frame_post_draw.is_connected(_grab):
			RenderingServer.frame_post_draw.disconnect(_grab)
		_grab()
	match state:
		State.COUNTDOWN:
			var was := count()
			t += delta
			if t >= COUNTDOWN:
				_begin_filming(t - COUNTDOWN)
			elif count() != was:
				_beep(false)
		State.FILMING:
			t += delta
			while asked < total and t >= _next_at:
				_frame_due()
			if not _due.is_empty() and not _armed and Engine.get_process_frames() >= _armed_at + 2:
				_arm()
			if asked >= total and _due.is_empty() and not _armed:
				_to_saving()
		State.SAVING:
			_saving()
	_overlay.queue_redraw()
	_tidy()


func _begin_filming(over: float) -> void:
	var vs := Vector2i(viewport.get_visible_rect().size) if viewport else Vector2i(1280, 720)
	var s := size_for(vs)
	w = s.x
	h = s.y
	state = State.FILMING
	t = over
	asked = 0
	total = roundi(LENGTH * FPS)
	_next_at = 0.0
	_due = []
	_box = _Box.new()
	_beep(true)


## The next frame of the film is due: asked of this frame (or skipped, with the workers behind).
func _frame_due() -> void:
	var i := asked
	asked += 1
	_next_at = float(asked) / FPS
	if _due.size() > 0:
		_due.append(i)   # (two due before a frame's drawn: the same picture)
		return
	_box.mutex.lock()
	var pending := i - _box.frames.size() - _box.lost.size()
	if pending > MAX_PENDING:
		_box.lost[i] = true
	_box.mutex.unlock()
	if pending <= MAX_PENDING:
		_due.append(i)


func _arm() -> void:
	if viewport == null:
		viewport = get_viewport()
	if _armed:
		return
	_armed = true
	_armed_at = Engine.get_process_frames()
	viewport.canvas_cull_mask &= ~LAYER
	RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)


## The frame's been drawn: the countdown's layer back, and its picture asked for.
func _grab() -> void:
	_armed = false
	var due := _due
	_due = []
	if viewport == null or not is_instance_valid(viewport):
		_lose(due)
		return
	viewport.canvas_cull_mask |= LAYER
	if due.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	if fake_source.is_valid():
		var img = fake_source.call()
		_hand_over(due, img if img is Image else null)
	else:
		var rd := RenderingServer.get_rendering_device()
		var tex := viewport.get_texture()
		var rd_tex := RenderingServer.texture_get_rd_texture(tex.get_rid()) if rd != null and tex != null else RID()
		if rd != null and rd_tex.is_valid():
			var fmt := rd.texture_get_format(rd_tex)
			if fmt.format in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT]:
				var err := rd.texture_get_data_async(rd_tex, 0, _on_data.bind(due, fmt.width, fmt.height, fmt.format))
				if err != OK:
					_hand_over(due, tex.get_image())
			else:
				_hand_over(due, tex.get_image())
		elif tex != null and DisplayServer.get_name() != "headless":
			_hand_over(due, tex.get_image())   # the Compatibility renderer: read back the old way
		else:
			_hand_over(due, null)
	last_grab_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _on_data(data: PackedByteArray, due: Array, fw: int, fh: int, format: int) -> void:
	_tasks.append(WorkerThreadPool.add_task(_work_raw.bind(data, fw, fh, format, due, w, h, _box), false, "film"))


func _hand_over(due: Array, img: Image) -> void:
	if img == null or img.is_empty():
		_lose(due)
		return
	_tasks.append(WorkerThreadPool.add_task(_work_image.bind(img, due, w, h, _box), false, "film"))


func _lose(due: Array) -> void:
	_box.mutex.lock()
	for i in due:
		_box.lost[int(i)] = true
	_box.mutex.unlock()


func _to_saving() -> void:
	state = State.SAVING
	t = 0.0
	_building = false
	_ended_ms = Time.get_ticks_msec()
	Sfx.play_ui("switch", -8.0)


## Every frame back (or given up on): the file put together on a worker; then it's told.
func _saving() -> void:
	_box.mutex.lock()
	var back := _box.frames.size() + _box.lost.size()
	var done := _box.done.duplicate()
	_box.mutex.unlock()
	if not done.is_empty():
		state = State.IDLE
		_overlay.visible = false
		if bool(done.get("ok", false)):
			done["job"] = job
			saved.emit(done)
		else:
			failed.emit(str(done.get("why", "The film couldn't be saved.")))
		return
	if _building or _armed:
		return
	if back >= total or Time.get_ticks_msec() - _ended_ms > GRACE_MS:
		_building = true
		_box.mutex.lock()
		var frames := _box.frames.duplicate()
		var poster := _box.poster
		_box.mutex.unlock()
		_tasks.append(WorkerThreadPool.add_task(_work_file.bind(frames, total, w, h, path_now(), str(job.get("poster_path", "")), poster, _box), false, "film"))


func _tidy() -> void:
	var k := 0
	while k < _tasks.size():
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.remove_at(k)
		else:
			k += 1


## Waits for every worker (the tests).
func wait_all() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _beep(go: bool) -> void:
	if is_inside_tree():
		Sfx.play_ui("beep", -4.0 if go else -10.0)


# ---------------------------------------------------------------------------- on a worker

static func _work_raw(data: PackedByteArray, fw: int, fh: int, format: int, due: Array, ow: int, oh: int, box: _Box) -> void:
	var img: Image = null
	match format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			if data.size() >= fw * fh * 4:
				img = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, data)
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			if data.size() >= fw * fh * 8:
				img = Image.create_from_data(fw, fh, false, Image.FORMAT_RGBAH, data)
				img.convert(Image.FORMAT_RGBA8)
				img.linear_to_srgb()
	if img == null:
		box.mutex.lock()
		for i in due:
			box.lost[int(i)] = true
		box.mutex.unlock()
		return
	_work_image(img, due, ow, oh, box, true)


## Shrinks `src` to the film's size (cut to its shape from the middle) and makes it a JPEG
## (`own`: `src` is this worker's to change, else it's copied first).
static func _work_image(src: Image, due: Array, ow: int, oh: int, box: _Box, own := false) -> void:
	var img := src if own else src.duplicate() as Image
	var aspect := float(ow) / float(oh)
	var cw := mini(img.get_width(), roundi(img.get_height() * aspect))
	var ch := mini(img.get_height(), roundi(cw / aspect))
	if cw != img.get_width() or ch != img.get_height():
		img = img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	if img.get_width() != ow or img.get_height() != oh:
		img.resize(ow, oh, Image.INTERPOLATE_BILINEAR)
	var jpg := img.save_jpg_to_buffer(JPEG_QUALITY)
	box.mutex.lock()
	for i in due:
		if jpg.is_empty():
			box.lost[int(i)] = true
		else:
			box.frames[int(i)] = jpg
		if int(i) == POSTER_FRAME or box.poster == null:
			box.poster = img
	box.mutex.unlock()


## The film's frames in order (a skipped one shown as the one before it, or after it at the
## start), put together as an AVI and written to `path`; the poster frame to `poster_path`.
static func _work_file(frames: Dictionary, n: int, ow: int, oh: int, path: String, poster_path: String, poster: Image, box: _Box) -> void:
	var list := []
	var last: PackedByteArray = PackedByteArray()
	for i in n:
		if frames.has(i):
			last = frames[i]
			break
	var got := 0
	for i in n:
		if frames.has(i):
			last = frames[i]
			got += 1
		list.append(last)
	var out := {}
	if got == 0:
		out = {"ok": false, "why": "Nothing was filmed: the film wasn't saved."}
	else:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			out = {"ok": false, "why": "Couldn't write the film to %s." % ProjectSettings.globalize_path(path)}
		else:
			f.store_buffer(MjpegAvi.build(list, ow, oh, FPS))
			f.close()
			if poster_path != "" and poster != null:
				DirAccess.make_dir_recursive_absolute(poster_path.get_base_dir())
				var pic := PhotoCapture.fit(poster.duplicate() as Image, PhotoCapture.PHOTO_W, PhotoCapture.PHOTO_H)
				pic.save_jpg(poster_path, PhotoCapture.JPEG_QUALITY)
			var thumb: Image = null
			if poster != null:
				thumb = poster.duplicate() as Image
				thumb.resize(PhotoCapture.THUMB_W, PhotoCapture.THUMB_H, Image.INTERPOLATE_BILINEAR)
			out = {"ok": true, "path": path, "file": ProjectSettings.globalize_path(path), "frames": n, "got": got, "w": ow, "h": oh,
				"secs": snappedf(float(n) / FPS, 0.1), "poster": thumb}
	box.mutex.lock()
	box.done = out
	box.mutex.unlock()


# ---------------------------------------------------------------------------- on the screen

## The countdown in the middle of the screen, then REC, the seconds left and a bar at the top
## right (under the level and money) while it films.
class _Overlay extends Control:
	var clip: MovieClip

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := get_theme_default_font()
		match clip.state:
			MovieClip.State.COUNTDOWN:
				var mid := size * 0.5
				var frac := fmod(clip.t, 1.0)
				draw_circle(mid, 92.0, Color(0, 0, 0, 0.45))
				draw_arc(mid, 92.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - frac), 64, Color(1, 0.3, 0.25, 0.9), 6.0, true)
				var n := str(clip.count())
				var fs := 120
				var sz := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, mid + Vector2(-sz.x * 0.5, fs * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
				draw_string(font, Vector2(0, mid.y + 140.0), "Filming %d seconds in..." % roundi(MovieClip.LENGTH), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, 0.9))
				draw_string(font, Vector2(0, mid.y + 172.0), Controls.hint("{movie} to call it off"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.65))
			MovieClip.State.FILMING:
				var box := Rect2(size.x - 236.0, 64.0, 212.0, 62.0)
				draw_rect(box, Color(0, 0, 0, 0.55))
				if fmod(clip.t, 1.0) < 0.6:
					draw_circle(box.position + Vector2(22, 22), 9.0, Color(1, 0.12, 0.08))
				draw_string(font, box.position + Vector2(40, 30), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.3, 0.25))
				var left := ceili(clip.seconds_left())
				draw_string(font, box.position + Vector2(96, 30), "%d s left" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
				var bar := Rect2(box.position + Vector2(12, 44), Vector2(box.size.x - 24.0, 6))
				draw_rect(bar, Color(1, 1, 1, 0.2))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(clip.t / MovieClip.LENGTH, 0.0, 1.0), bar.size.y)), Color(1, 0.3, 0.25))
				draw_string(font, Vector2(box.position.x - 60.0, box.end.y + 20.0), Controls.hint("{movie} to stop"), HORIZONTAL_ALIGNMENT_RIGHT, box.size.x + 60.0, 14, Color(1, 1, 1, 0.6))
			MovieClip.State.SAVING:
				var box := Rect2(size.x - 236.0, 64.0, 212.0, 40.0)
				draw_rect(box, Color(0, 0, 0, 0.55))
				draw_string(font, box.position + Vector2(14, 27), "Saving the film...", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
