"""Builds the pub customers in Blender and exports them for Godot (step 2 of 2).

Run with Blender 4.2 (no add-ons needed):
  blender -b --python tools/people/blender_export.py -- [names...]

Reads tools/people/build/<name>.npz/.json written by mh_build.py and, for each character:
  * builds the game-engine armature and every part as a mesh with UVs, skin weights and the
    MakeHuman textures (skin, eyes, brows, lashes, hair, clothes, shoes)
  * reduces the body and clothes to a phone-friendly triangle count with Blender's Decimate,
    keeping the face at full detail (eyelids and lips must stay smooth to blink and talk)
  * re-attaches the blink, mouth-open and smile shapes to the reduced mesh
  * exports assets/people_mh/<name>.gltf (+ .bin), sharing one textures folder
"""
import json
import os
import sys

import bpy
import numpy as np
from mathutils import kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
OUT = os.path.join(ROOT, "assets", "people_mh")
TEX = os.path.join(OUT, "textures")

# how much of each part to keep; the face is protected inside the body
KEEP = {"body": float(os.environ.get("BODY_KEEP", "0.4")), "hair": 1.0, "eyes": 1.0, "eyebrows": 1.0, "eyelashes": 1.0}
CLOTHES_KEEP = 0.4
SHOES_KEEP = 0.45


def g2b(a):
    """Game coordinates (Y up, facing -Z) to Blender's (Z up); the glTF exporter turns them back."""
    a = np.asarray(a, np.float64)
    return np.stack([a[..., 0], -a[..., 2], a[..., 1]], axis=-1)


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)


def image(name):
    if not name:
        return None
    path = os.path.join(TEX, name)
    for im in bpy.data.images:
        if im.filepath == path:
            return im
    im = bpy.data.images.load(path)
    if name.startswith("clothn_") or name.startswith("hairn_"):
        im.colorspace_settings.name = "Non-Color"
    return im


def material(key, spec):
    if key in bpy.data.materials:
        return bpy.data.materials[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.7)
    bsdf.inputs["Specular IOR Level"].default_value = 0.3 if spec["kind"] in ("skin", "opaque") else 0.5
    alb = image(spec.get("albedo"))
    if alb:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = alb
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if spec["kind"] == "alpha":
            # a "greater than" on alpha is what the glTF exporter writes as alphaMode MASK (cut-out)
            cut = nt.nodes.new("ShaderNodeMath")
            cut.operation = "GREATER_THAN"
            cut.inputs[1].default_value = 0.4
            nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
            nt.links.new(cut.outputs[0], bsdf.inputs["Alpha"])
    m.use_backface_culling = spec["kind"] not in ("alpha",)
    nrm = image(spec.get("normal"))
    if nrm:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = nrm
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if spec["kind"] == "eye":
        bsdf.inputs["Coat Weight"].default_value = 0.6
    return m


def build(name):
    clear()
    d = np.load(os.path.join(BUILD, name + ".npz"))
    with open(os.path.join(BUILD, name + ".json")) as f:
        man = json.load(f)
    bones = man["bones"]
    # --- armature
    arm = bpy.data.armatures.new(name + "_rig")
    rig = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    heads = g2b(d["bone_heads"])
    tails = g2b(d["bone_tails"])
    ebs = []
    for i, b in enumerate(bones):
        eb = arm.edit_bones.new(b)
        eb.head = heads[i]
        t = tails[i]
        if np.linalg.norm(t - heads[i]) < 1e-3:
            t = heads[i] + np.array([0, 0, 0.05])
        eb.tail = t
        eb.roll = 0.0
        ebs.append(eb)
    for i, p in enumerate(d["bone_parents"]):
        if p >= 0:
            ebs[i].parent = ebs[p]
    bpy.ops.object.mode_set(mode="OBJECT")

    neck_z = heads[bones.index("neck_01")][2]
    objs = [rig]
    for part in man["parts"]:
        tag = part["tag"]
        pos = g2b(d[tag + "pos"])
        counts = d[tag + "counts"]
        fv = d[tag + "fv"]
        ft = d[tag + "ft"]
        uv = d[tag + "uv"]
        faces = []
        k = 0
        for c in counts:
            faces.append(tuple(fv[k:k + c]))
            k += c
        used = np.unique(fv)
        me = bpy.data.meshes.new(name + "_" + part["name"].replace(":", "_"))
        me.from_pydata(pos.tolist(), [], faces)
        me.validate(clean_customdata=False)
        # UVs, corner by corner in face order
        uvl = me.uv_layers.new(name="UVMap")
        if len(ft) == len(me.loops) and ft.max() < len(uv):
            uvl.data.foreach_set("uv", uv[ft].reshape(-1).astype(np.float32))
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(material(name.split("_")[0] + "_" + part["name"] + "_" + os.path.splitext(part["material"].get("albedo") or "none")[0], part["material"]))
        # skin weights
        bidx = d[tag + "bones"]
        bw = d[tag + "bw"]
        groups = {}
        for vi in range(len(pos)):
            for j in range(4):
                w = float(bw[vi, j])
                if w > 0.001:
                    b = bones[int(bidx[vi, j])]
                    if b not in groups:
                        groups[b] = ob.vertex_groups.new(name=b)
                    groups[b].add([vi], w, "REPLACE")
        # reduce, keeping the face
        pname = part["name"]
        keep = KEEP.get(pname, SHOES_KEEP if "shoes" in pname else CLOTHES_KEEP)
        orig = pos.copy()
        if keep < 0.999:
            # an untouched copy to take the skin weights from afterwards (Decimate blends them badly
            # where separate parts lie close together, such as a hand resting by the hip)
            src = ob.copy()
            src.data = ob.data.copy()
            bpy.context.scene.collection.objects.link(src)
            mod = ob.modifiers.new("decimate", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = keep
            mod.use_symmetry = True
            mod.symmetry_axis = "X"
            if pname == "body":
                # the head keeps every triangle (eyelids and lips must blink and talk); the rest of the
                # body keeps `keep` of its own. Decimate removes unprotected triangles first until the
                # overall ratio is met, so the ratio is worked out from the two parts.
                face = ob.vertex_groups.new(name="keep_face")
                above = [int(i) for i in np.nonzero(pos[:, 2] > neck_z)[0]]
                face.add(above, 1.0, "REPLACE")
                tri = lambda p: len(p.vertices) - 2
                head_t = sum(tri(p) for p in ob.data.polygons if all(pos[v][2] > neck_z for v in p.vertices))
                all_t = sum(tri(p) for p in ob.data.polygons)
                mod.ratio = min(1.0, (head_t + keep * (all_t - head_t)) / max(all_t, 1))
                mod.vertex_group = "keep_face"
                mod.invert_vertex_group = True
            bpy.context.view_layer.objects.active = ob
            if os.environ.get("PEOPLE_DEBUG"):
                print("   before decimate: weighted", sum(1 for v in ob.data.vertices if len(v.groups)), "of", len(ob.data.vertices))
            bpy.ops.object.modifier_apply(modifier=mod.name)
            if os.environ.get("PEOPLE_DEBUG"):
                print("   after decimate: weighted", sum(1 for v in ob.data.vertices if len(v.groups)), "of", len(ob.data.vertices))
            if pname == "body":
                ob.vertex_groups.remove(ob.vertex_groups["keep_face"])
            # fresh weights: each reduced vertex takes the weights of the nearest original surface point
            for vg in list(ob.vertex_groups):
                ob.vertex_groups.remove(vg)
            for vg in src.vertex_groups:
                ob.vertex_groups.new(name=vg.name)
            dt = ob.modifiers.new("weights", "DATA_TRANSFER")
            dt.object = src
            dt.use_vert_data = True
            dt.data_types_verts = {"VGROUP_WEIGHTS"}
            dt.vert_mapping = "POLYINTERP_NEAREST"
            dt.layers_vgroup_select_src = "ALL"
            dt.layers_vgroup_select_dst = "NAME"
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.modifier_apply(modifier=dt.name)
            if os.environ.get("PEOPLE_DEBUG"):
                print("   after transfer: weighted", sum(1 for v in ob.data.vertices if len(v.groups)), "of", len(ob.data.vertices))
            bpy.data.objects.remove(src, do_unlink=True)
        # expression shapes, carried over from the nearest original vertex
        if part["shapes"]:
            tree = kdtree.KDTree(len(orig))
            for i, p in enumerate(orig):
                tree.insert(p, i)
            tree.balance()
            near = np.array([tree.find(v.co)[1] for v in ob.data.vertices])
            ob.shape_key_add(name="Basis", from_mix=False)
            co = np.array([v.co[:] for v in ob.data.vertices])
            for s in part["shapes"]:
                delta = g2b(d[tag + "shape_" + s])
                sk = ob.shape_key_add(name=s, from_mix=False)
                sk.data.foreach_set("co", (co + delta[near]).reshape(-1).astype(np.float32))
        ob.parent = rig
        mod = ob.modifiers.new("rig", "ARMATURE")
        mod.object = rig
        objs.append(ob)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print("  %s: %d triangles" % (pname, tris))
    # --- export
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".gltf"), export_format="GLTF_SEPARATE",
                              export_texture_dir="textures", use_selection=True, export_skins=True,
                              export_morph=True, export_morph_normal=True, export_animations=False,
                              export_yup=True, export_apply=False, export_image_format="AUTO",
                              export_materials="EXPORT", export_def_bones=False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or sorted(f[:-4] for f in os.listdir(BUILD) if f.endswith(".npz"))
    for n in names:
        print("==", n)
        build(n)


main()
