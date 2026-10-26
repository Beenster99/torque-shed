#!/usr/bin/env bash
# Vulkan drawn on the processor (Mesa's lavapipe) for a CI machine without a graphics card, without apt installing
# anything: the driver is taken out of Mesa's own package (the version the machine's OpenGL already is, so it matches
# its LLVM) into DIR, and the Vulkan loader pointed at it. `apt-get install` sometimes waits ten minutes on a fresh
# machine, and the postcards then quietly fell back to OpenGL.
#   tests/postcards/lavapipe.sh DIR      # fills DIR if it hasn't the driver (CI caches DIR), and sets $GITHUB_ENV
set -euo pipefail
DIR="$1"
mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd)"
if [ ! -f "$DIR/libvulkan_lvp.so" ] || [ ! -f "$DIR/libvulkan.so.1" ]; then
	V=$(dpkg-query -W -f='${Version}' libgl1-mesa-dri)
	TMP="$(mktemp -d)"
	(
		cd "$TMP"
		apt-get download "mesa-vulkan-drivers=$V" libvulkan1 > /dev/null 2>&1 || {
			sudo apt-get update -qq -o DPkg::Lock::Timeout=60
			apt-get download "mesa-vulkan-drivers=$V" libvulkan1 > /dev/null
		}
		for d in *.deb; do dpkg-deb -x "$d" x; done
	)
	cp "$TMP"/x/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so "$DIR/"
	cp -L "$TMP"/x/usr/lib/x86_64-linux-gnu/libvulkan.so.1 "$DIR/"
	rm -rf "$TMP"
fi
printf '{"file_format_version": "1.0.1", "ICD": {"library_path": "%s/libvulkan_lvp.so", "api_version": "1.4.0"}}\n' "$DIR" > "$DIR/lvp_icd.json"
if [ -n "${GITHUB_ENV:-}" ]; then
	echo "VK_DRIVER_FILES=$DIR/lvp_icd.json" >> "$GITHUB_ENV"
	echo "VK_ICD_FILENAMES=$DIR/lvp_icd.json" >> "$GITHUB_ENV"
	echo "LD_LIBRARY_PATH=$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" >> "$GITHUB_ENV"
fi
echo "lavapipe in $DIR (mesa $(dpkg-query -W -f='${Version}' libgl1-mesa-dri))"
