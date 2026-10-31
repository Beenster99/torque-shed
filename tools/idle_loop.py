"""Turns a recording of a bike ticking over into a seamless idle loop for the game.

    python3 -I tools/idle_loop.py SOURCE.wav START END CYLINDERS OUT.wav [--rpm RPM]

Takes START..END seconds of SOURCE (any format ffmpeg reads), mixes it to mono at the game's
32 kHz, takes out DC and rumble, evens out the level (a camera moving about the bike), and cuts
a loop of whole engine cycles about four seconds long whose end runs into its start, with a
short crossfade over the seam. The engine's speed is found from the recording (how often the
sound repeats) unless --rpm gives it; it goes in the output's name, which EngineBank reads:
audio/engines/idle/<key>_<rpm>.wav. The loop is levelled to -20 dBFS RMS; the game matches
it to the made engine's own loudness when it plays.
"""
import os
import subprocess
import sys
import wave

import numpy as np

RATE = 32000
LOOP_SECONDS = 4.0
XFADE = 0.12
TARGET_RMS = 0.1


def load(path, start, end):
	raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-to", str(end), "-i", path,
		"-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"], check=True, capture_output=True).stdout
	return np.frombuffer(raw, np.int16).astype(np.float64) / 32768.0


def high_pass(x, hz):
	k = np.exp(-2.0 * np.pi * hz / RATE)
	y = np.empty_like(x)
	prev_x = prev_y = 0.0
	for i, v in enumerate(x):
		prev_y = k * (prev_y + v - prev_x)
		prev_x = v
		y[i] = prev_y
	return y


def even_level(x):
	"""Divides out slow swells (over about half a second), at most 6 dB either way."""
	win = int(RATE * 0.5)
	env = np.sqrt(np.convolve(x * x, np.ones(win) / win, "same"))
	env = np.maximum(env, 1e-6)
	gain = np.clip(np.median(env) / env, 0.5, 2.0)
	return x * gain


def cycle_seconds(x, cylinders):
	"""How long one engine cycle (two turns of the crank) takes, from how the sound repeats."""
	k = RATE // 300
	env = np.convolve(np.abs(x), np.ones(k) / k, "same")[::8]
	env = env - env.mean()
	n = len(env)
	f = np.fft.rfft(env, 2 * n)
	a = np.fft.irfft(f * np.conj(f))[:n]
	a /= a[0]
	rate = RATE / 8
	# A cycle somewhere between 3000 rpm and 500 rpm.
	lo, hi = int(rate * 120 / 3000), int(rate * 120 / 500)
	best = lo + int(np.argmax(a[lo:hi]))
	# The strongest repeat may be one firing rather than the whole cycle (too quick for an
	# idle): take the longest multiple of it, up to the cylinder count, that repeats nearly as well.
	for m in (range(min(cylinders, 4), 1, -1) if 120.0 * rate / best > 2200.0 else []):
		j = best * m
		if j < hi:
			w = a[j - 3:j + 4]
			if w.max() > 0.85 * a[best]:
				best = j - 3 + int(np.argmax(w))
				break
	return best / rate


def make_loop(x, cycle):
	c = int(XFADE * RATE)
	cyc = cycle * RATE
	n0 = int(round(round(LOOP_SECONDS / cycle) * cyc))
	if n0 + 2 * c + int(cyc) > len(x):
		n0 = int(round(int((len(x) - 2 * c - cyc) / cyc) * cyc))
	s = c
	w = int(cyc)
	head = x[s:s + w]
	best, best_n = -2.0, n0
	for n in range(n0 - int(cyc * 0.5), n0 + int(cyc * 0.5)):
		if s + n + w > len(x):
			break
		tail = x[s + n:s + n + w]
		r = np.dot(head, tail) / np.sqrt(np.dot(head, head) * np.dot(tail, tail) + 1e-12)
		if r > best:
			best, best_n = r, n
	n = best_n
	out = x[s:s + n].copy()
	# The last c samples blend into the c just before the start, so the end runs into the start:
	# a straight crossfade where the two line up well, an equal-power one where they don't (a
	# lumpy idle), so the seam doesn't dip.
	t = np.linspace(0.0, 1.0, c)
	fade_in, fade_out = (t, 1.0 - t) if best > 0.6 else (np.sin(t * np.pi / 2), np.cos(t * np.pi / 2))
	out[n - c:] = out[n - c:] * fade_out + x[s - c:s] * fade_in
	return out, best


def main():
	args = sys.argv[1:]
	rpm = None
	if "--rpm" in args:
		i = args.index("--rpm")
		rpm = float(args[i + 1])
		del args[i:i + 2]
	src, start, end, cylinders, out_path = args[0], float(args[1]), float(args[2]), int(args[3]), args[4]
	x = load(src, start, end)
	x = high_pass(x - x.mean(), 25.0)
	x = even_level(x)
	cycle = 120.0 / rpm if rpm else cycle_seconds(x, cylinders)
	rpm = 120.0 / cycle
	loop, match = make_loop(x, cycle)
	loop *= TARGET_RMS / np.sqrt(np.mean(loop * loop))
	peak = np.max(np.abs(loop))
	if peak > 0.98:
		loop *= 0.98 / peak
	base, ext = os.path.splitext(out_path)
	out_path = "%s_%d%s" % (base, round(rpm), ext)
	with wave.open(out_path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes((np.clip(loop, -1, 1) * 32767).astype("<i2").tobytes())
	print("%s: %.0f rpm, %.2f s loop, seam match %.2f, peak %.2f" % (out_path, rpm, len(loop) / RATE, match, peak))


if __name__ == "__main__":
	main()
