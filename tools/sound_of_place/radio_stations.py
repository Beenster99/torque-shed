#!/usr/bin/env python3
"""Builds data/radio_by_country.json: a handful of each country's own radio stations, in its own language.

Reads the community Radio Browser directory (https://www.radio-browser.info, its data is free to use) and keeps, for
every country, the most listened-to stations that are working, stream MP3 (all the game's radio decodes) and speak the
country's most common language among its stations, so Morocco's radio is in Arabic and French and Japan's in Japanese.
Each country's answer is cached (see --cache), so running it again only fetches what isn't there yet.

	python3 tools/sound_of_place/radio_stations.py [--cache DIR] [--per N]
"""
import argparse
import collections
import json
import os
import re
import time
import urllib.parse
import urllib.request

API = "https://de1.api.radio-browser.info/json/"
UA = "TorqueShed/1 (+https://github.com/Beenster99/torque-shed)"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "radio_by_country.json")
# Tags that say a station isn't the country's own radio (relays of foreign stations, round-the-clock recitation).
SKIP_TAGS = {"quran", "koran", "religion", "religious", "christian", "gospel", "worship", "bible", "sermon", "islamic"}
# Words in a tag list that make a fair genre line, most telling first.
GENRES = ["news", "talk", "sport", "pop", "rock", "folk", "traditional", "country", "jazz", "classical", "dance",
	"hip hop", "rap", "latin", "regional mexican", "ranchera", "salsa", "chaabi", "rai", "j-pop", "enka", "schlager",
	"volksmusik", "chanson", "oldies", "80s", "90s", "hits", "top 40", "community", "public radio", "variety"]


def fetch(url):
	req = urllib.request.Request(url, headers={"User-Agent": UA})
	with urllib.request.urlopen(req, timeout=60) as r:
		return json.loads(r.read().decode("utf-8"))


def cached(cache, name, url):
	path = os.path.join(cache, name + ".json")
	if os.path.exists(path):
		with open(path, encoding="utf-8") as f:
			return json.load(f)
	data = fetch(url)
	os.makedirs(cache, exist_ok=True)
	with open(path, "w", encoding="utf-8") as f:
		json.dump(data, f)
	time.sleep(0.3)
	return data


def languages(station):
	return [l.strip().lower() for l in re.split(r"[,;/]", station.get("language") or "") if l.strip()]


def genre(station):
	tags = (station.get("tags") or "").lower()
	for g in GENRES:
		if g in tags:
			return g[0].upper() + g[1:]
	return "Local radio"


def short_name(name):
	"""A station's name short enough for the radio's display: up to the first " - " or "|" when it's long."""
	name = re.sub(r"\s+", " ", name.strip())
	if len(name) > 32:
		name = re.split(r" [-|(\[] ?", name)[0].strip()
	return name[:40]


def local_language(stations):
	"""The language most of a country's stations speak, or "" when they don't say."""
	count = collections.Counter()
	for s in stations:
		for l in languages(s):
			count[l] += 1
	return count.most_common(1)[0][0] if count else ""


def choose(stations, per):
	"""The country's best few stations: working MP3s, not religious relays, in the local language where they say."""
	ok = []
	seen = set()
	for s in stations:
		url = s.get("url_resolved") or s.get("url") or ""
		name = (s.get("name") or "").strip()
		tags = set(t.strip().lower() for t in (s.get("tags") or "").split(","))
		if s.get("codec") != "MP3" or not s.get("lastcheckok") or not url.startswith(("http://", "https://")):
			continue
		if tags & SKIP_TAGS or not name or name.lower() in seen or url in seen:
			continue
		if 0 < int(s.get("bitrate") or 0) < 48:
			continue
		seen.add(name.lower())
		seen.add(url)
		ok.append(s)
	lang = local_language(ok)
	# Stations in the local language first (then those that don't say), each lot by how many listen.
	def rank(s):
		ls = languages(s)
		return (0 if lang and lang in ls else (1 if not ls else 2), -int(s.get("clickcount") or 0), -int(s.get("votes") or 0))
	ok.sort(key=rank)
	return lang, [{"name": short_name(s["name"]), "genre": genre(s), "url": s.get("url_resolved") or s["url"],
		"language": (s.get("language") or "").strip()} for s in ok[:per]]


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--cache", default="/mnt/project-files/torque-shed/ride-anywhere-v2/cache/radio")
	ap.add_argument("--per", type=int, default=6)
	args = ap.parse_args()
	countries = cached(args.cache, "_countries", API + "countrycodes")
	out = {}
	for c in sorted(countries, key=lambda c: c["name"]):
		code = c["name"].upper()
		if len(code) != 2 or int(c.get("stationcount") or 0) < 2:
			continue
		q = urllib.parse.urlencode({"order": "clickcount", "reverse": "true", "hidebroken": "true", "limit": 80})
		stations = cached(args.cache, code, API + "stations/bycountrycodeexact/" + code + "?" + q)
		lang, chosen = choose(stations, args.per)
		if chosen:
			out[code] = {"language": lang, "stations": chosen}
	with open(OUT, "w", encoding="utf-8") as f:
		f.write("{\n")
		f.write(",\n".join("\t%s: %s" % (json.dumps(k), json.dumps(v, ensure_ascii=False)) for k, v in sorted(out.items())))
		f.write("\n}\n")
	print("%d countries, %d stations -> %s" % (len(out), sum(len(v["stations"]) for v in out.values()), OUT))


if __name__ == "__main__":
	main()
