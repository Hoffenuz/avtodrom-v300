"""
Blender (headless): repairs the spinning wheel meshes (Spin_XX) of a finished
game car, leaving everything else as it is.

    blender -b --python pipeline/blender/fix_wheels.py -- <car.glb> <out.glb> [--align] [--drop <material> ...]

--align   turns each wheel so its own axis (the tyre's axis of symmetry,
          found by PCA) is the X axis the game spins it about. The Cobalt's
          left wheels sat 3.4 deg toed in the source: spun about X they
          wobbled like unbalanced wheels.
--drop    removes the faces of these materials from the wheels. The Cobalt's
          8-face "metal" plate (the decimated brake backing plate, 2.5 cm off
          the axle) spun with the wheel.

The Cobalt fix:
    ... -- game/assets/cars/cobalt/cobalt.glb game/assets/cars/cobalt/cobalt.glb --align --drop metal
"""
import math
import sys

import bpy  # before bmesh: needed when run through the bpy pip module
import bmesh
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
ALIGN = "--align" in argv
DROP = set(argv[argv.index("--drop") + 1:]) if "--drop" in argv else set()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in bpy.context.scene.objects:
    if o.type != "MESH" or not o.name.startswith("Spin_"):
        continue
    names = [m.name if m else "" for m in o.data.materials]
    if DROP:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        dead = [f for f in bm.faces if names[f.material_index] in DROP]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
        for i in reversed(range(len(o.data.materials))):
            if o.data.materials[i] and o.data.materials[i].name in DROP:
                o.data.materials.pop(index=i)
        print(o.name, "removed", len(dead), "faces of", sorted(DROP))
    if ALIGN:
        names = [m.name if m else "" for m in o.data.materials]
        tyre = names.index("rubber")
        pts = np.array([o.data.vertices[v].co[:] for p in o.data.polygons if p.material_index == tyre
                        for v in p.vertices])
        centre = pts.mean(axis=0)
        w, vecs = np.linalg.eigh(np.cov((pts - centre).T))
        axis = Vector(vecs[:, 0])
        if axis.x < 0:
            axis = -axis
        rot = axis.rotation_difference(Vector((1, 0, 0))).to_matrix().to_4x4()
        print(f"{o.name}: axis {tuple(round(a, 4) for a in axis)}, turned "
              f"{math.degrees(axis.angle(Vector((1, 0, 0)))):.2f} deg")
        o.data.transform(rot)  # about the hub (the mesh origin)
        o.data.update()

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True,
                          export_normals=True, export_tangents=False, export_materials="EXPORT",
                          export_animations=False, export_extras=False, export_texcoords=True)
print("exported", OUT)
