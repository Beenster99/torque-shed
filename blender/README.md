# Blender bike parts

The bike parts modelled in Blender, by script (bike look overhaul, geometry track). Each part family is a
bpy script; the glbs it writes are committed, so the game and its tests never need Blender.

- `lib/kit.py`: the shared kit: surface tags, shapes, UVs, mount points, the glb export, triangle caps.
- `parts/<kind>/<family>.py`: one script per family, with a `parts()` list of the glbs it writes.
- `../assets/bike_parts/<kind>/<part_id>.glb`: the exports. A top end (kind `head`) depends on the
  engine's layout too: `head/<layout>/<head_part_id>.glb`.
- `../scripts/blender_parts.gd`: the game side (BlenderParts): finds a part's glb and places it. A part
  with no glb is drawn by BikeModel's own code, as before.

Every glb follows the parts agreement (`/mnt/project-files/torque-shed/bike-look/parts-agreement.md`,
written with the materials track): bike model space in metres (Blender +Y is the bike's front, +Z up),
meshes `lod0`, `lod1`, `lod2`, mount points as empties `mount_<name>`, every face's material named for
its surface tag, UVs at 1 unit = 1 m, and each kind's triangle caps.

```
pip install -r blender/requirements.txt         # Blender as a Python module (Python 3.13)
python3 blender/build.py [family ...]           # rebuild the glbs
python3 blender/check.py                        # the agreement's checks
python3 blender/contact_sheet.py out.png [head/twin]
xvfb-run -a godot --path . res://tests/top_end_shots.tscn -- --out=/tmp/shots   # in-game close-ups
xvfb-run -a godot --path . res://tests/exhaust_shots.tscn -- --out=/tmp/shots    # the exhausts, the same
```

After a rebuild, run `godot --headless --path . --import` and commit the glbs with their `.import` files
(LOD generation is off in them: the parts bring their own). CI rebuilds every family and fails if the
glbs it makes differ from the committed ones, then runs the checks and keeps a contact sheet.
