"""Turns the CC0 Poly Haven models from fetch_polyhaven.py into game props (run with Blender 4.2):
  blender -b --python tools/props/blender_props.py -- [names...]

For each entry in props.json: imports the glTF, joins its parts, turns it to face -Z in the
game, scales it to the given height with its base centred on the origin, reduces it to the
triangle budget, optionally re-stains the colour texture, and exports assets/props/<name>.glb.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(ROOT, "assets", "props")


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build(p):
    clear()
    pid = p["polyhaven"]
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, pid, pid + ".gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # bake every transform into the meshes, then join them
    for o in meshes:
        o.data = o.data.copy()
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = p["name"]
    me = ob.data
    # Poly Haven models face -Y in Blender (+Z in the game): turn round to face -Z, plus any extra yaw
    me.transform(Matrix.Rotation(math.pi + math.radians(p.get("yaw", 0)), 4, "Z"))
    co = [v.co for v in me.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    s = p["height"] / max(hi.z - lo.z, 1e-6)
    me.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
    me.transform(Matrix.Scale(s, 4))
    if p.get("width"):
        # fit the footprint to the game's layout (seats are placed around a fixed table size)
        w0 = (hi.x - lo.x) * s
        k = p["width"] / max(w0, 1e-6)
        me.transform(Matrix.Diagonal((k, k, 1.0, 1.0)))
    tris = sum(len(f.vertices) - 2 for f in me.polygons)
    if tris > p["tris"]:
        mod = ob.modifiers.new("decimate", "DECIMATE")
        mod.ratio = p["tris"] / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tris2 = sum(len(f.vertices) - 2 for f in me.polygons)
    if p.get("tint"):
        t = p["tint"]
        for m in me.materials:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and n.image.colorspace_settings.name == "sRGB":
                    img = n.image
                    px = list(img.pixels)
                    for i in range(0, len(px), 4):
                        px[i] *= t[0] * 2.2
                        px[i + 1] *= t[1] * 2.2
                        px[i + 2] *= t[2] * 2.2
                    img.pixels[:] = [min(v, 1.0) for v in px]
                    img.update()
    dims = me.vertices
    w = max(v.co.x for v in dims) - min(v.co.x for v in dims)
    d = max(v.co.y for v in dims) - min(v.co.y for v in dims)
    print("  %s: %d -> %d triangles, %.2f wide x %.2f deep x %.2f high m" % (p["name"], tris, tris2, w, d, p["height"]))
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, p["name"] + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=85)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    with open(os.path.join(HERE, "props.json")) as f:
        props = json.load(f)["props"]
    for p in props:
        if not argv or p["name"] in argv:
            print("==", p["name"])
            build(p)


main()
