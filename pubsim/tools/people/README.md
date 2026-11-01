# Building the pub's people

The customers in `assets/people_mh/` are built from MakeHuman's CC0 data in two steps. Both steps
only read data files; no MakeHuman or MPFB code is run.

1. Get the data (once):
   - `git clone --depth 1 https://github.com/makehumancommunity/mpfb2` (its `src/mpfb/data` folder holds
     the base mesh, targets, rigs and weights, all CC0)
   - the MakeHuman system assets pack, CC0:
     `https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip`
     (unzip it somewhere)
   - Blender 4.2 LTS (no add-ons needed)
2. `python3 tools/people/mh_build.py <mpfb2>/src/mpfb/data <assets dir> [names...]`
   Morphs and dresses each character from `characters.json` and writes intermediate data to
   `tools/people/build/` (ignored by git). It also writes the textures and per-character anchors
   (`assets/people_mh/*.json`). Needs numpy, scipy and Pillow.
3. `blender -b --python tools/people/blender_export.py -- [names...]`
   Builds each character in Blender (armature, meshes, materials), reduces the body and clothes to
   about 17,000-25,000 triangles while keeping the face at full detail, and exports
   `assets/people_mh/<name>.gltf`.

Characters face -Z with their feet at y = 0. The arms rest 10 degrees out from the body
(`customer.gd` reads that angle back from the skeleton). Each body carries `blink`, `mouth_open` and
`smile` shapes. To add a character, add an entry to `characters.json`. To make a regular use it,
name it as `model` in their `look` in `data/regulars.json`.
