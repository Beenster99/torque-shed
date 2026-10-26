#!/usr/bin/env python3
"""Makes the sounds of place (audio/place/*.ogg) from freely licensed field recordings.

Each sound in sounds.json names its recording, an archive.org item (most are from radio aporee ::: maps, a sound map of
field recordings each with its own licence) or a Wikimedia Commons file, and how long a stretch of it to use (the
steadiest stretch unless it says where to start). The original and its description page
are fetched once into the cache (--cache, shared between threads) and never again; each sound is then cut, made mono,
levelled to the same loudness, looped seamlessly (a bed: its end crossfaded into its start) or faded out (a one-off:
bells, the call to prayer) and saved as a small Ogg Vorbis, with <sound>.ogg.licence.txt beside it saying where it came
from, who made it and under which licence. Only sounds whose inputs changed are made again.

	python3 tools/sound_of_place/make_sounds.py [--cache DIR] [sound ...]
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "audio", "place")
UA = "TorqueShed/1 (+https://github.com/Beenster99/torque-shed; game sounds)"
RATE = 44100
# Bumped when the making changes, so every sound is made again.
VERSION = 3
# Licence templates on Commons, and how the licence file names them.
LICENCES = [
	(r"cc-zero|cc0", "CC0 1.0 (public domain dedication)", "https://creativecommons.org/publicdomain/zero/1.0/"),
	(r"pd-", "Public domain", ""),
	(r"cc-by-sa-4\.0", "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
	(r"cc-by-sa-3\.0", "CC BY-SA 3.0", "https://creativecommons.org/licenses/by-sa/3.0/"),
	(r"cc-by-sa-2\.5", "CC BY-SA 2.5", "https://creativecommons.org/licenses/by-sa/2.5/"),
	(r"cc-by-sa-2\.0", "CC BY-SA 2.0", "https://creativecommons.org/licenses/by-sa/2.0/"),
	(r"cc-by-4\.0", "CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
	(r"cc-by-3\.0", "CC BY 3.0", "https://creativecommons.org/licenses/by/3.0/"),
	(r"cc-by-2\.5", "CC BY 2.5", "https://creativecommons.org/licenses/by/2.5/"),
	(r"cc-by-2\.0", "CC BY 2.0", "https://creativecommons.org/licenses/by/2.0/"),
]
# Fades (s): how long a bed's end is crossfaded into its start, and a one-off's fade in and out.
LOOP_XFADE = 3.0
FADE_IN = 0.05
FADE_OUT = 1.5


def fetch(url):
	for attempt in range(6):
		try:
			req = urllib.request.Request(url, headers={"User-Agent": UA})
			with urllib.request.urlopen(req, timeout=300) as r:
				return r.read()
		except urllib.error.HTTPError as e:
			if e.code not in (429, 503):
				raise
			time.sleep(30 * (attempt + 1))
	raise RuntimeError("gave up on " + url)


def original(cache, name):
	"""The Commons file `name` and its description page's wikitext, fetched once into `cache`."""
	path = os.path.join(cache, name)
	if not os.path.exists(path + ".wiki"):
		text = fetch("https://commons.wikimedia.org/w/index.php?" + urllib.parse.urlencode({"title": "File:" + name, "action": "raw"}))
		with open(path + ".wiki", "wb") as f:
			f.write(text)
		time.sleep(5)
	if not os.path.exists(path):
		data = fetch("https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(name))
		with open(path + ".part", "wb") as f:
			f.write(data)
		os.replace(path + ".part", path)
		time.sleep(5)
	with open(path + ".wiki", encoding="utf-8") as f:
		return path, f.read()


def archived(cache, item):
	"""The archive.org item's recording (its smallest Ogg or MP3, else its FLAC or WAV) and its metadata, fetched once."""
	meta_path = os.path.join(cache, item + ".json")
	if not os.path.exists(meta_path):
		with open(meta_path, "wb") as f:
			f.write(fetch("https://archive.org/metadata/" + item))
	with open(meta_path, encoding="utf-8") as f:
		meta = json.load(f)
	order = {"Ogg Vorbis": 0, "VBR MP3": 1, "MP3": 1, "Flac": 2, "WAVE": 3}
	files = sorted([f for f in meta["files"] if f.get("format") in order], key=lambda f: order[f["format"]])
	if not files:
		raise ValueError(item + " has no recording")
	name = files[0]["name"]
	path = os.path.join(cache, item + "__" + name)
	if not os.path.exists(path):
		data = fetch("https://archive.org/download/%s/%s" % (item, urllib.parse.quote(name)))
		with open(path + ".part", "wb") as f:
			f.write(data)
		os.replace(path + ".part", path)
	return path, meta["metadata"]


def archive_licence(url):
	"""(name, url) of an archive.org licence url, if it's a free one (no NonCommercial or NoDerivatives)."""
	u = (url or "").lower()
	if "-nc" in u or "-nd" in u or "creativecommons.org" not in u:
		raise ValueError("not a free licence: " + url)
	if "publicdomain/mark" in u:
		return "Public Domain Mark 1.0", "https://creativecommons.org/publicdomain/mark/1.0/"
	if "publicdomain/zero" in u:
		return "CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"
	m = re.search(r"licenses/(by(?:-sa)?)/(\d\.\d)", u)
	if not m:
		raise ValueError("unknown licence: " + url)
	return "CC %s %s" % (m.group(1).upper(), m.group(2)), "https://creativecommons.org/licenses/%s/%s/" % (m.group(1), m.group(2))


def duration(path):
	out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], check=True, capture_output=True, text=True)
	return float(out.stdout.strip())


def loudest(path, length):
	"""Where the loudest `length` s of `path` starts (where the bells ring out, the muezzins call)."""
	total = duration(path)
	if total <= length + 2:
		return 0.0
	x = decode(path, 0.0, total)
	block = RATE // 4
	n = len(x) // block
	rms = np.array([np.mean(x[i * block:(i + 1) * block] ** 2) for i in range(n)])
	win = int(length * 4)
	sums = np.convolve(rms, np.ones(win), "valid")
	return float(np.argmax(sums[4:]) + 4) / 4.0


def steadiest(path, length, highpass=0.0, busy=False):
	"""Where the steadiest `length` s of `path` starts: the stretch whose loudness moves least (no door slams, no
	passing lorry, no handling noise), skipping the first and last few seconds where recordists start and stop. `busy`
	also favours the liveliest stretch (the most birdsong, the busiest market)."""
	total = duration(path)
	if total <= length + 6:
		return 0.0
	x = decode(path, 0.0, total, highpass)
	block = RATE // 4
	n = len(x) // block
	db = 10 * np.log10(np.array([np.mean(x[i * block:(i + 1) * block] ** 2) for i in range(n)]) + 1e-10)
	win = int(length * 4)
	best, best_at = None, 0
	for at in range(12, max(13, n - win - 12), 4):
		w = db[at:at + win]
		score = np.std(w) + 0.5 * max(0.0, np.max(w) - np.median(w) - 12) - (0.5 * (np.mean(w) - np.median(db)) if busy else 0.0)
		if best is None or score < best:
			best, best_at = score, at
	return best_at / 4.0


def plain(wikitext):
	"""Wiki markup made readable: links to their text, templates and tags dropped."""
	t = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", wikitext)
	t = re.sub(r"\[https?://\S+ ([^\]]*)\]", r"\1", t)
	t = re.sub(r"\{\{(?:en|de|fr|es|nl|ja)\|(?:1=)?([^{}]*)\}\}", r"\1", t)
	t = re.sub(r"\{\{[^{}]*\}\}", "", t)
	t = re.sub(r"<[^>]+>", "", t)
	return re.sub(r"\s+", " ", t).strip()


def field(wikitext, key):
	m = re.search(r"\|\s*" + key + r"\s*=(.*?)(?=\n\s*\||\n\}\})", wikitext, re.S | re.I)
	return plain(m.group(1)) if m else ""


def licence(wikitext):
	"""(name, url) of the file's licence, the first free one its page names; raises when there is none."""
	low = wikitext.lower()
	for pattern, name, url in LICENCES:
		if re.search(r"\{\{[^}]*(" + pattern + r")", low):
			return name, url
	raise ValueError("no free licence found")


def decode(path, start, length, highpass=0.0):
	"""`length` s of `path` from `start`, mono float32 at RATE, with what's below `highpass` Hz taken out (the rumble of
	wind on the microphone and distant traffic, which the game's own wind and roads already make)."""
	cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(length), "-i", path, "-ac", "1", "-ar", str(RATE)]
	if highpass > 0:
		cmd += ["-af", "highpass=f=%g:poles=2,highpass=f=%g:poles=2" % (highpass, highpass)]
	cmd += ["-f", "f32le", "-"]
	return np.frombuffer(subprocess.run(cmd, check=True, capture_output=True).stdout, dtype=np.float32).copy()


def level(x, target_db):
	"""`x` scaled so its loudness (RMS over its louder half-second blocks) is `target_db` dBFS, peaks kept under -1 dB."""
	block = RATE // 2
	n = max(1, len(x) // block)
	rms = np.sqrt(np.array([np.mean(x[i * block:(i + 1) * block] ** 2) for i in range(n)]) + 1e-12)
	loud = np.mean(np.sort(rms)[n // 2:])
	gain = 10 ** (target_db / 20) / loud
	peak = np.max(np.abs(x)) * gain
	if peak > 10 ** (-1 / 20):
		gain *= 10 ** (-1 / 20) / peak
	return x * gain


def make_loop(x):
	"""A seamless loop: the last LOOP_XFADE s crossfaded (equal power) into the first."""
	n = int(LOOP_XFADE * RATE)
	if len(x) < 3 * n:
		raise ValueError("too short to loop")
	t = np.linspace(0.0, np.pi / 2, n, dtype=np.float32)
	head = x[:n] * np.sin(t) + x[-n:] * np.cos(t)
	return np.concatenate([head, x[n:-n]])


def fade(x):
	n_in, n_out = int(FADE_IN * RATE), int(FADE_OUT * RATE)
	x = x.copy()
	x[:n_in] *= np.linspace(0, 1, n_in)
	x[-n_out:] *= np.linspace(1, 0, n_out) ** 2
	return x


def encode(x, path):
	pcm = np.clip(x, -1, 1).astype(np.float32).tobytes()
	cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "0", "-map_metadata", "-1", path]
	subprocess.run(cmd, input=pcm, check=True)


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--cache", default="/mnt/project-files/torque-shed/ride-anywhere-v2/cache/sound")
	ap.add_argument("only", nargs="*")
	args = ap.parse_args()
	with open(os.path.join(HERE, "sounds.json"), encoding="utf-8") as f:
		sounds = json.load(f)
	os.makedirs(OUT, exist_ok=True)
	os.makedirs(args.cache, exist_ok=True)
	for sound, s in sorted(sounds.items()):
		if sound.startswith("_") or (args.only and sound not in args.only):
			continue
		ogg = os.path.join(OUT, sound + ".ogg")
		inputs = hashlib.sha1(json.dumps([s, LOOP_XFADE, FADE_IN, FADE_OUT, RATE, VERSION], sort_keys=True).encode()).hexdigest()[:12]
		note = ogg + ".licence.txt"
		if os.path.exists(ogg) and os.path.exists(note) and ("Inputs: " + inputs) in open(note, encoding="utf-8").read():
			continue
		if "archive" in s:
			path, meta = archived(args.cache, s["archive"])
			name, url = archive_licence(meta.get("licenseurl", ""))
			source = "https://archive.org/details/" + s["archive"]
			author = "%s, on radio aporee ::: maps (https://aporee.org/maps/)" % plain(str(meta.get("creator", "") or "unnamed recordist")).split("@")[0]
			desc = plain(str(meta.get("title", ""))) + ". " + plain(str(meta.get("description", "")))
		else:
			path, wiki = original(args.cache, s["commons"])
			name, url = licence(wiki)
			source = "https://commons.wikimedia.org/wiki/File:%s" % urllib.parse.quote(s["commons"].replace(" ", "_"))
			author = field(wiki, "author") or field(wiki, "artist") or "see the source page"
			desc = field(wiki, "description")
		loop = s.get("loop", True)
		span = float(s["length"]) + (LOOP_XFADE if loop else 0.0)
		hp = float(s.get("highpass", 120.0))
		start = float(s["start"]) if "start" in s else (steadiest(path, span, hp, bool(s.get("busy", False))) if loop else loudest(path, span))
		x = decode(path, start, span, hp)
		x = level(x, float(s.get("loudness", -20.0)))
		x = make_loop(x) if loop else fade(x)
		encode(x, ogg)
		with open(note, "w", encoding="utf-8") as f:
			f.write("Sound: %s.ogg, %s\n" % (sound, s.get("what", "")))
			f.write("Source: %s\n" % source)
			f.write("Author: %s\n" % author)
			f.write("Licence: %s%s\n" % (name, " " + url if url else ""))
			f.write("Changes: %.0f s cut from %.0f s in, made mono, loudness levelled%s, Ogg Vorbis.\n"
				% (float(s["length"]), start, ", looped" if loop else ", faded out"))
			if desc:
				f.write("Original description: %s\n" % desc[:400])
			f.write("Inputs: %s\n" % inputs)
		print("%-20s %6.1f s from %6.1f s  %-22s %s" % (sound, len(x) / RATE, start, name, source), flush=True)


if __name__ == "__main__":
	main()
