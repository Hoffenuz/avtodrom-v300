"""
Blender (headless): rebuilds the wheels of a finished game car from its source
model, leaving the rest of the car as it is.

    blender -b --python pipeline/blender/replace_wheels.py -- <game car.glb> <source.glb> <out.glb> nexia2

The first build decimated the whole wheel to ~3000 triangles: the Nexia's
plastic wheel cover (7000 triangles in the source) came out torn and jagged
and the treaded tyre a saw. Here, per corner:
  * the tyre is a clean lathed one (tread grooves, rounded shoulders, bulging
    sidewalls) at the car's real radius;
  * the wheel cover / rim keeps a far larger budget;
  * the brake caliper and its support stay put (Hub_XX under the pivot, they
    steer but do not spin), the disc, nuts and valve spin with the wheel.
The new parts are placed on the existing Wheel_XX pivots (the source wheel is
turned 180 deg like the car and scaled to the game tyre radius).
"""
import math
import sys

import bpy  # before bmesh: needed when run through the bpy pip module
import bmesh
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GAME, SRC, OUT, CAR = argv[0], argv[1], argv[2], argv[3]

SPEC = {
    "nexia2": {
        "tyre_radius": 0.2888,  # 185/60 R14
        "corners": {"FL": "wheel_front_left", "FR": "wheel_front_right",
                    "RL": "wheel_rear_left", "RR": "wheel_rear_right"},
        # source part suffix -> (semantic material, spins, triangle budget)
        "parts": {"_rim_rim": ("rim", True, 2200), "_brakedisk_brakedisk": ("brake_disc", True, 200),
                  "_tire_nuts_mattemetal": ("metal", True, 80), "_tire_parts_black": ("trim_black", True, 80),
                  "_caliper_brakedisk_black": ("trim_black", False, 160),
                  "_support_black": ("trim_black", False, 100)},
        "tyre": "_tire_tire",
        "turn": math.pi,  # the source faces -Y
    },
}[CAR]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GAME)
scene = bpy.context.scene
collection = scene.collection
game_objects = set(scene.objects)

pivots = {}
for corner in SPEC["corners"]:
    pivots[corner] = bpy.data.objects["Wheel_" + corner]
    for old in ("Spin_", "Hub_"):
        o = bpy.data.objects.get(old + corner)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    return m


# The game file's semantic materials, looked up before the source brings its own.
sem = {n: material(n) for n in ("rim", "rubber", "brake_disc", "metal", "trim_black")}

bpy.ops.import_scene.gltf(filepath=SRC)
source = [o for o in scene.objects if o not in game_objects]
for o in source:
    if o.type == "MESH":
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
for o in list(source):
    keep = o.type == "MESH" and any(o.name.startswith(p) for p in SPEC["corners"].values())
    if not keep:
        bpy.data.objects.remove(o, do_unlink=True)
source = [o for o in scene.objects if o not in game_objects]
for o in source:
    o.data = o.data.copy()
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)


def bounds(objs):
    pts = [v.co for o in objs for v in o.data.vertices]
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def activate(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def decimate(o, target):
    n = tri_count(o)
    if n <= target:
        return
    activate(o)
    mod = o.modifiers.new("dec", "DECIMATE")
    mod.ratio = max(target / n, 0.005)
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    res = bpy.context.view_layer.objects.active
    res.name = name
    res.data.name = name
    return res


def make_tyre(name, radius, width, bead_radius, segments=40):
    """A clean lathed tyre around the origin (axis = X)."""
    t = width / 2
    right = [(0.28 * t, radius), (0.31 * t, radius - 0.006), (0.37 * t, radius - 0.006), (0.40 * t, radius),
             (0.84 * t, radius - 0.002), (0.97 * t, radius - 0.014), (1.0 * t, radius - 0.045),
             (0.97 * t, bead_radius + 0.035), (0.88 * t, bead_radius + 0.014), (0.82 * t, bead_radius)]
    loop = [(0.0, radius)] + right + [(0.0, bead_radius)] + [(-x, r) for x, r in reversed(right)]
    bm = bmesh.new()
    rings = []
    for j in range(segments):
        a = j / segments * math.tau
        rings.append([bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for x, r in loop])
    n = len(loop)
    for j in range(segments):
        a, b = rings[j], rings[(j + 1) % segments]
        for i in range(n):
            k = (i + 1) % n
            bm.faces.new((a[i], a[k], b[k], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(sem["rubber"])
    o = bpy.data.objects.new(name, me)
    collection.objects.link(o)
    return o


def smooth(o, angle=38.0):
    activate(o)
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def source_parts(start):
    # (looked up afresh: joining the previous corner removed its objects)
    return [o for o in scene.objects if o.type == "MESH" and o.name.startswith(start)]


R = SPEC["tyre_radius"]
turn = Matrix.Rotation(SPEC["turn"], 4, "Z")
for corner, prefix in SPEC["corners"].items():
    tyre_src = source_parts(prefix + SPEC["tyre"])
    tmn, tmx = bounds(tyre_src)
    centre = (tmn + tmx) / 2
    k = R / ((tmx.z - tmn.z) / 2)
    width = (tmx.x - tmn.x) * k
    to_hub = Matrix.Scale(k, 4) @ turn @ Matrix.Translation(-centre)  # source -> pivot-local
    spin, hub = [], []
    rim_r = 0.0
    for suffix, (sem_name, spins, budget) in SPEC["parts"].items():
        for o in source_parts(prefix + suffix):
            o.data.transform(to_hub)
            for slot in o.material_slots:
                slot.material = sem[sem_name]
            decimate(o, budget)
            if sem_name == "rim":
                rmn, rmx = bounds([o])
                rim_r = max(rim_r, (rmx.z - rmn.z) / 2)
            (spin if spins else hub).append(o)
    for o in tyre_src:
        bpy.data.objects.remove(o, do_unlink=True)
    spin.append(make_tyre("Tyre_" + corner, R, width, rim_r - 0.012))
    pivot = pivots[corner]
    for objs, name in ((spin, "Spin_" + corner), (hub, "Hub_" + corner)):
        if not objs:
            continue
        o = join(objs, name)
        smooth(o)
        o.parent = pivot
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = Matrix.Identity(4)
    print(f"{corner}: tyre r {R:.4f} width {width:.3f}, rim r {rim_r:.3f}, spin {tri_count(bpy.data.objects['Spin_' + corner])}"
          f" tris, hub {tri_count(bpy.data.objects['Hub_' + corner]) if hub else 0} tris")

for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
    export_normals=True,
    export_tangents=False,
    export_materials="EXPORT",
    export_animations=False,
    export_extras=False,
    export_texcoords=True,
)
print("exported", OUT)
