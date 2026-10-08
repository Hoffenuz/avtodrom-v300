"""
Blender (headless) asset build for the Chevrolet Onix sedan exam car.

    blender -b --python pipeline/blender/build_onix.py -- <chevrolet_onix.glb> <onix_build.glb>
    blender -b --python pipeline/blender/refine_car.py -- onix_build.glb game/assets/cars/onix/onix.glb onix

The source is a ~310k triangle model, facing +Y with the driver on -X, Z up,
in units ~5% larger than metres, made of ~130 loosely named parts with flat
colours (no textures). This script:
  * scales it so the wheelbase is the real 2600 mm, tyres standing on z = 0,
    and puts the four wheels on one track and two axles (the source's right
    wheels sit a few centimetres off);
  * drops what the game cannot use or that shows as sharp debris: the roof
    antenna, a stray tail-lamp copy stuck under the steering column, tow-eye
    caps, the rear plate's lettering and frame and a duplicated headlamp lens;
  * assigns the semantic materials the game replaces with its own PBR set
    (paint, trim_black, window, lamp_*, interior, ...); the inner faces of
    the painted shell (roof, pillars, doors seen from the seats) become the
    headliner and trim, so a repainted car keeps a grey cabin;
  * separates the lamps (projector headlamps, fog lamps, the amber strips
    under the headlamps with the wing repeaters, the rear "wings" = tail and
    stop lamp, the light strips above them = rear turn signals, the high stop
    lamp), the steering wheel under a SteeringPivot, the wheels as
    Wheel_XX -> Spin_XX, and plain plate fields front and rear;
  * decimates the heavy pieces to a mobile budget and adds a convex hull.
refine_car.py then rebuilds the dashboard with live gauges and splits off
BodyOuter, as for the other cars.
"""
import math
import sys
from collections import deque

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

REAL_WHEELBASE = 2.600
# Centre of the steering wheel (the bow-tie on its hub), source units.
SW_SRC = Vector((-0.392, 0.539, -0.018))

DROP = {
    # stray tail-lamp copy under the steering column, with its lens pieces
    "onix_90_18_instance_0.0_0", "onix_90_18_group_5.0_0", "onix_90_19_group_6.0_0",
    "onix_90_24_onix_90_8.0_0", "onix_90_30_onix_90_8.0_0",
    # tow-eye caps, specks
    "instance_8_wheel.0_0", "instance_8_instance_2.2_0", "instance_9_wheel.0_0", "instance_9_instance_2.2_0",
    "instance_0_instance_0.0_0", "onix_90_31_instance_0.0_0", "onix_90_31.001_instance_0.0_0",
    "onix_90_1.007_onix_90_1.2_0", "onix_90_1.007_onix_90_1.3_0", "instance_2_instance_2.2_0",
    "group_9_onix_90_2.0_0", "group_9.001_onix_90_2.0_0",
    # rear plate lettering and its lettered frame (the game puts its own plate on)
    "frontbump_frontbump.1_0", "frontbump_frontbump.2_0", "frontbump_frontbump.3_0", "frontbump_instance_0.0_0",
    # the headlamp lens twice over (same mesh, another colour)
    "onix_90_23.002_onix_90_4.0_0", "onix_90_23.003_onix_90_4.0_0",
    # a small dark lens in the old instrument cluster (the dash is rebuilt)
    "onix_90_8_onix_90_8.0_0",
}
# Wheels: corner -> source objects ending in .0 face, .1 rim body, .2 tyre, .3 brake.
WHEELS = {
    "FR": ("wheel_wheel.0_0", "wheel_wheel.1_0", "wheel_wheel.2_0", "wheel_wheel.3_0"),
    "RR": ("wheel.001_wheel.004_0", "wheel.001_wheel.005_0", "wheel.001_wheel.006_0", "wheel.001_wheel.007_0"),
    "RL": ("wheel.002_wheel.008_0", "wheel.002_wheel.009_0", "wheel.002_wheel.010_0", "wheel.002_wheel.011_0"),
    "FL": ("wheel.003_wheel.012_0", "wheel.003_wheel.013_0", "wheel.003_wheel.014_0", "wheel.003_wheel.015_0"),
}
WHEEL_MATS = ("rim", "trim_black", "rubber", "brake_disc")
WHEEL_BUDGET = (300, 1300, 900, 160)
INTERIOR = ["onix_90_3_instance_0.0_0", "onix_90_3_instance_2.1_0", "group_12_instance_0.0_0",
            "group_13_instance_0.0_0", "group_14_instance_0.0_0", "group_15_instance_0.0_0",
            "instance_2_instance_0.0_0", "instance_2_instance_2.1_0", "instance_3_instance_0.0_0",
            "onix_90_5_instance_0.0_0", "onix_90_12_onix_90_4.0_0",
            "onix_90_1.006_instance_0.0_0", "onix_90_1.006_onix_90_4.0_0", "onix_90_1.006_group_5.0_0",
            "onix_90_1.007_instance_0.0_0", "onix_90_1.007_onix_90_4.0_0", "onix_90_1.007_group_5.0_0",
            "onix_90_4_onix_90_4.0_0", "onix_90_4_onix_90_4.1_0", "onix_90_14_onix_90_8.0_0"]
# Thinned before they join the body, so they do not eat its budget.
PRE_DECIMATE = {"instance_1_instance_0.0_0": 2600, "instance_4_instance_0.0_0": 2600,
                "onix_90_20_instance_0.0_0": 7000, "onix_90_25_instance_0.0_0": 5000,
                "group_4_primary_0": 6500, "onix_90_26_onix_90_4.1_0": 700, "group_2_group_1.1_0": 150,
                "group_1_group_1.1_0": 1600, "group_7_instance_0.0_0": 1000, "group_7.001_instance_0.0_0": 1000,
                "onix_90_2_primary_0": 22000, "group_8_instance_0.0_0": 500, "group_8.001_instance_0.0_0": 500,
                "group_8.002_instance_0.0_0": 500, "group_8.003_instance_0.0_0": 500,
                "onix_90_5_instance_0.0_0": 2500, "onix_90_18.001_instance_0.0_0": 900,
                "onix_90_18.002_instance_0.0_0": 900, "group_17_primary_0": 2600, "group_17.001_primary_0": 2600,
                "group_18_primary_0": 2600, "group_18.001_primary_0": 2600,
                "group_19_primary_0": 2200, "group_19.001_primary_0": 2200,
                "onix_90_12_onix_90_4.0_0": 500, "group_12_instance_0.0_0": 600, "group_15_instance_0.0_0": 400,
                "group_14_instance_0.0_0": 400, "onix_90_1.006_onix_90_4.0_0": 900,
                "onix_90_1.007_onix_90_4.0_0": 900, "onix_90_1.006_instance_0.0_0": 1000,
                "onix_90_1.007_instance_0.0_0": 1000, "onix_90_1.006_group_5.0_0": 500,
                "onix_90_1.007_group_5.0_0": 500, "onix_90_23_onix_90_1.0_0": 700,
                "onix_90_23.001_onix_90_1.0_0": 700}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
collection = scene.collection
for mat in list(bpy.data.materials):
    mat.name = "src_" + mat.name


def meshes():
    return [o for o in scene.objects if o.type == "MESH"]


def one(name):
    o = bpy.data.objects.get(name)
    assert o is not None and o.type == "MESH", name
    return o


def src_mat(o, i=0):
    m = o.data.materials[i] if len(o.data.materials) > i else None
    return m.name.removeprefix("src_") if m else ""


# --- 1. Flatten, bake transforms, drop --------------------------------------------------------
for o in meshes():
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
for o in meshes():
    o.data = o.data.copy()
    m = o.matrix_world.copy()
    o.data.transform(m)
    if m.determinant() < 0.0:
        o.data.flip_normals()
    o.matrix_world = Matrix.Identity(4)
for name in DROP:
    bpy.data.objects.remove(one(name), do_unlink=True)


def bounds_pts(pts):
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def bounds(objs):
    return bounds_pts([v.co for o in objs for v in o.data.vertices])


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


def face_islands(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        isl = []
        while stack:
            g = stack.pop()
            isl.append(g.index)
            for v in g.verts:
                for h in v.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(isl)
    bm.free()
    return out


def partition(obj, labels, new_name):
    """Moves the faces whose label is True into a new object (None if none)."""
    if not any(labels):
        return None
    new_me = bpy.data.meshes.new(new_name)
    for keep_new, target in ((True, new_me), (False, obj.data)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        dead = [f for f in bm.faces if labels[f.index] != keep_new]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        if keep_new:
            for mat in obj.data.materials:
                new_me.materials.append(mat)
        bm.to_mesh(target)
        bm.free()
    r = bpy.data.objects.new(new_name, new_me)
    collection.objects.link(r)
    return r


def island_labels(obj, pred):
    me = obj.data
    labels = [False] * len(me.polygons)
    for isl in face_islands(obj):
        vids = {i for fi in isl for i in me.polygons[fi].vertices}
        mn, mx = bounds_pts([me.vertices[i].co for i in vids])
        if pred(mn, mx, len(vids)):
            for fi in isl:
                labels[fi] = True
    return labels


# --- 1b. Face orientation ----------------------------------------------------------------------
# The source was made for a double-sided viewer: about half the faces are
# wound backwards. A one-sided engine drops those (the body shows as torn
# patches) and smooth normals across them cancel out: every face is turned
# outwards (weld, then orient).
INTERIOR_SET = set(INTERIOR)


def weld(o):
    """Welded first: the import splits every corner (normals, UVs), and
    unwelded faces share no edges to agree over. The same face twice (the
    source's two-sided panels) keeps one copy. Then the winding is made to
    agree across manifold edges."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    dup, keys = [], set()
    for f in bm.faces:
        k = tuple(sorted(v.index for v in f.verts))
        if k in keys:
            dup.append(f)
        else:
            keys.add(k)
    if dup:
        bmesh.ops.delete(bm, geom=dup, context="FACES")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


GLASS_MATS = {"glass", "onix_90_8.0", "onix_90_1.0"}


def occluders():
    """Everything but the glass, in one BVH: the rays below see out through the windows."""
    bm = bmesh.new()
    for o in meshes():
        mats = [src_mat(o, i) for i in range(len(o.data.materials))]
        if mats and all(m in GLASS_MATS for m in mats):
            continue
        bm.from_mesh(o.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def orient(o, tree):
    """Each face is turned to the side it sees the open sky from: a ray
    each way from its centre, and the side that escapes the car (through
    the windows too: the glass is not in the BVH) is outside. A face that
    cannot tell (both or neither ray escapes: inside a lamp, under a seat)
    takes the winding of its neighbours across manifold edges. Whatever is
    still unknown falls back to the shape: away from the car's centre line,
    or, for the cabin parts, towards it. A whole-piece decision did not do:
    the body shell's winding was mixed within one piece."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    state = {}
    for f in bm.faces:
        n = f.normal
        if n.length < 0.5:
            continue
        c = f.calc_center_median()
        out = tree.ray_cast(c + n * 0.003, n, 30.0)[0] is None
        back = tree.ray_cast(c - n * 0.003, -n, 30.0)[0] is None
        if out != back:
            state[f.index] = 1 if out else -1
    queue = deque(f for f in bm.faces if f.index in state)
    while queue:
        f = queue.popleft()
        sf = state[f.index]
        for loop in f.loops:
            e = loop.edge
            if len(e.link_faces) != 2:
                continue
            g = e.link_faces[0] if e.link_faces[1] == f else e.link_faces[1]
            if g.index in state:
                continue
            lg = next(lp for lp in g.loops if lp.edge == e)
            # Consistent winding runs the shared edge the other way round.
            state[g.index] = sf if lg.vert != loop.vert else -sf
            queue.append(g)
    flipped = 0
    for f in bm.faces:
        sf = state.get(f.index)
        if sf is None:
            c = f.calc_center_median()
            axis = Vector((0.0, max(-1.4, min(1.6, c.y)), -0.2))
            d = (c - axis) if o.name not in INTERIOR_SET else (axis - c)
            sf = 1 if f.normal.dot(d) >= 0.0 else -1
        if sf < 0:
            f.normal_flip()
            flipped += 1
    bm.to_mesh(o.data)
    bm.free()
    return flipped


for o in meshes():
    weld(o)
TREE = occluders()
total_flipped = sum(orient(o, TREE) for o in meshes())
print("orientation: flipped", total_flipped, "faces")

# The roof antenna: islands of the black trim above the roof's rear half.
trim = one("onix_90_20_instance_0.0_0")
ant = partition(trim, island_labels(trim, lambda mn, mx, n: abs((mn.x + mx.x) / 2) < 0.2
                                    and -1.6 < (mn.y + mx.y) / 2 < -0.4 and (mn.z + mx.z) / 2 > 0.5), "Antenna")
assert ant is not None, "antenna not found"
print("antenna: dropped", tri_count(ant), "tris")
bpy.data.objects.remove(ant, do_unlink=True)

# --- 2. Placement: real scale, wheels square, tyres on the ground --------------------------------
tyre_c = {}
for corner, parts in WHEELS.items():
    mn, mx = bounds([one(parts[2])])
    tyre_c[corner] = ((mn + mx) / 2, (mx.z - mn.z) / 2)
half_track = sum(abs(c.x) for c, _ in tyre_c.values()) / 4
y_front = (tyre_c["FL"][0].y + tyre_c["FR"][0].y) / 2
y_rear = (tyre_c["RL"][0].y + tyre_c["RR"][0].y) / 2
z_hub = sum(c.z for c, _ in tyre_c.values()) / 4
r_src = sum(r for _, r in tyre_c.values()) / 4
# Each wheel moved onto the common track and axle (the source's right wheels sit off).
for corner, parts in WHEELS.items():
    c = tyre_c[corner][0]
    target = Vector(((-1 if corner[1] == "L" else 1) * half_track,
                     y_front if corner[0] == "F" else y_rear, z_hub))
    for name in parts:
        one(name).data.transform(Matrix.Translation(target - c))
    print(f"wheel {corner}: moved by {tuple(round(v, 3) for v in (target - c))}")
y_c = (y_front + y_rear) / 2
z_ground = z_hub - r_src
S = REAL_WHEELBASE / (y_front - y_rear)
print(f"source: axles y {y_front:.3f} / {y_rear:.3f}, half track {half_track:.3f}, ground {z_ground:.3f}, scale {S:.5f}")
PLACE = Matrix.Scale(S, 4) @ Matrix.Translation(Vector((0.0, -y_c, -z_ground)))
for o in meshes():
    o.data.transform(PLACE)
    o.data.update()


def place(p):
    return PLACE @ Vector(p)


# --- 3. Semantic materials ------------------------------------------------------------------------
SEMANTIC = ["paint", "trim_black", "chrome", "rim", "rubber", "metal", "brake_disc", "window", "lamp_glass",
            "lamp_orange", "lamp_red", "lamp_white", "headlamp", "interior", "interior_light", "headliner",
            "lamp_glass_red",
            "plate", "mirror", "badge"]
sem = {name: bpy.data.materials.new(name) for name in SEMANTIC}
assert all(m.name == n for n, m in sem.items())
# Kept by the game as authored (no entry in its material table): the gold bow-tie.
bsdf_badge = sem["badge"]
bsdf_badge.use_nodes = True
bn = bsdf_badge.node_tree.nodes["Principled BSDF"]
bn.inputs["Base Color"].default_value = (0.86, 0.66, 0.16, 1.0)
bn.inputs["Metallic"].default_value = 0.85
bn.inputs["Roughness"].default_value = 0.3

MAT_RULE = {
    "primary": "paint", "instance_0.0": "trim_black", "glass": "window", "onix_90_8.0": "mirror",
    "onix_90_2.0": "trim_black", "group_1.1": "trim_black", "onix_90_4.0": "trim_black",
    "onix_90_4.1": "badge", "group_5.0": "chrome", "group_6.0": "lamp_red", "frontbump.4": "plate",
    "right_front_light": "lamp_white", "right_rear_light": "lamp_red", "onix_90_1.0": "lamp_glass",
    "onix_90_1.2": "headlamp", "onix_90_1.3": "lamp_orange", "onix_90_21.1": "chrome",
    "material_0": "trim_black", "instance_2.1": "trim_black",
}


def assign(o, rule):
    for slot in o.material_slots:
        src = slot.material.name.removeprefix("src_") if slot.material else ""
        slot.material = sem[rule(src)]


def single_material(o, name):
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    while len(me.materials) > 1:
        me.materials.pop()
    me.materials[0] = sem[name]


def join(objs, name):
    objs = [o for o in objs if o is not None]
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


def new_empty(name, loc, rot_matrix=None):
    e = bpy.data.objects.new(name, None)
    collection.objects.link(e)
    m = Matrix.Translation(loc)
    if rot_matrix is not None:
        m = m @ rot_matrix.to_4x4()
    e.matrix_world = m
    return e


def set_origin(obj, point):
    obj.data.transform(Matrix.Translation(-point))
    obj.matrix_world = Matrix.Translation(point)


# --- 4. Wheels -------------------------------------------------------------------------------------
wheel_centre = {}
for corner, parts in WHEELS.items():
    objs = []
    for name, mat, budget in zip(parts, WHEEL_MATS, WHEEL_BUDGET):
        o = one(name)
        single_material(o, mat)
        decimate(o, budget)
        objs.append(o)
    mn, mx = bounds([objs[2]])
    centre = (mn + mx) / 2
    wheel_centre[corner] = centre
    pivot = new_empty("Wheel_" + corner, centre)
    s = join(objs, "Spin_" + corner)
    set_origin(s, centre)
    s.parent = pivot
    s.matrix_parent_inverse = pivot.matrix_world.inverted()
tyre_radius = r_src * S

# --- 5. Lamps --------------------------------------------------------------------------------------
def lamp(names, name, mat):
    o = join([one(n) for n in names], name)
    single_material(o, mat)
    return o


def split_side(obj, left, right):
    r = partition(obj, [p.center.x >= 0 for p in obj.data.polygons], right)
    obj.name = left
    obj.data.name = left
    return obj, r


lamp(["onix_90_1_right front light_0", "onix_90_1.004_right front light_0",
      "onix_90_1.002_group_5.0_0", "onix_90_1.003_group_5.0_0"], "Lamp_Head", "lamp_white")
lamp(["onix_90_21_right front light_0", "onix_90_21.001_right front light_0"], "Lamp_Fog", "lamp_white")
split_side(lamp(["onix_90_1.002_onix_90_1.3_0", "onix_90_1.003_onix_90_1.3_0"], "Lamp_TurnF", "lamp_orange"),
           "Lamp_TurnFL", "Lamp_TurnFR")
lamp(["onix_90_19.001_right rear light_0", "onix_90_19.002_right rear light_0"], "Lamp_Tail", "lamp_red")
split_side(lamp(["onix_90_18.001_group_5.0_0", "onix_90_18.002_group_5.0_0"], "Lamp_TurnR", "lamp_white"),
           "Lamp_TurnRL", "Lamp_TurnRR")
lamp(["group_6_group_6.0_0"], "Lamp_Brake", "lamp_red")
for o in meshes():
    if o.name.startswith("Lamp_"):
        decimate(o, 1400 if o.name in ("Lamp_Head", "Lamp_Tail") else 600)

# --- 6. Steering wheel -----------------------------------------------------------------------------
dash_src = one("onix_90_3_instance_0.0_0")
sw_target = place(SW_SRC)
sw_labels = island_labels(dash_src, lambda mn, mx, n: ((mn + mx) / 2 - sw_target).length < 0.12
                          and (mx - mn).length < 0.55)
sw = partition(dash_src, sw_labels, "SteeringWheel")
assert sw is not None, "steering wheel not found"
logo = one("onix_90_4_onix_90_4.1_0")
INTERIOR.remove("onix_90_4_onix_90_4.1_0")
sw = join([sw, logo], "SteeringWheel")
pts = np.array([v.co[:] for v in sw.data.vertices])


def pca(p):
    c = p.mean(axis=0)
    w, v = np.linalg.eigh(np.cov((p - c).T))
    return c, v[:, 0]


c0, ax0 = pca(pts)
d = pts - c0
radial = np.linalg.norm(d - np.outer(d @ ax0, ax0), axis=1)
ring = pts[radial > 0.8 * radial.max()]
c_ring, axis = pca(ring)
c = Vector(c_ring)
axis = Vector(axis).normalized()
if axis.y > 0:
    axis = -axis
assign(sw, lambda s: "badge" if s == "onix_90_4.1" else "trim_black")
z = axis
x = Vector((1, 0, 0))
x = (x - z * x.dot(z)).normalized()
y = z.cross(x)
rotm = Matrix((x, y, z)).transposed()
spivot = new_empty("SteeringPivot", c, rot_matrix=rotm)
sw.data.transform(Matrix.Translation(-c))
sw.data.transform(rotm.inverted().to_4x4())
sw.matrix_world = spivot.matrix_world
sw.parent = spivot
sw.matrix_parent_inverse = spivot.matrix_world.inverted()
decimate(sw, 2400)
print("steering centre", tuple(round(v, 3) for v in c), "axis", tuple(round(v, 3) for v in axis),
      "ring radius", round(float(radial.max()), 3), "tris", tri_count(sw))

# --- 7. Interior ------------------------------------------------------------------------------------
for name, budget in PRE_DECIMATE.items():
    o = bpy.data.objects.get(name)
    if o is not None:
        decimate(o, budget)
interior_objs = [one(n) for n in INTERIOR]
for o in interior_objs:
    assign(o, lambda s: {"onix_90_4.0": "interior_light", "group_5.0": "interior_light",
                         "onix_90_8.0": "mirror"}.get(s, "interior"))
interior = join(interior_objs, "Interior")

# --- 8. Glass ---------------------------------------------------------------------------------------
# The windows are the dark tinted panes; the clear "glass" parts are the lamp
# lenses (and the side-marker lenses).
glass = join([one("onix_90_22_onix_90_8.0_0"), one("onix_90_22.001_onix_90_8.0_0"), one("group_0_onix_90_8.0_0")],
             "Glass")
assign(glass, lambda s: "window")
lens = join([one("onix_90_22_glass_0"), one("onix_90_22.001_glass_0"), one("onix_90_23_onix_90_1.0_0"), one("onix_90_23.001_onix_90_1.0_0"),
             one("onix_90_1.001_onix_90_1.0_0"), one("onix_90_1.005_onix_90_1.0_0")], "LampGlass")
assign(lens, lambda s: "lamp_glass")
# The rear clusters' outer lens is smoked red, as on the car: clear, it read
# as a pale grey blob over the lamps (worst on OpenGL).
lens.data.materials.append(sem["lamp_glass_red"])
for p in lens.data.polygons:
    if p.center.y < -1.6:
        p.material_index = len(lens.data.materials) - 1
decimate(lens, 2600)

# --- 9. Body ----------------------------------------------------------------------------------------
KEEP = ("Spin_", "Lamp_", "SteeringWheel", "Glass", "LampGlass", "Interior")
rest = [o for o in meshes() if not o.name.startswith(KEEP)]
for o in rest:
    assign(o, lambda s: MAT_RULE.get(s, "trim_black"))
body = join(rest, "Body")

# The painted shell's inner faces (roof, pillars, door shuts and the doors
# from the inside: faces in the cabin turned towards its middle) become
# cabin trim; seen from the seats or through the windows they must not wear
# the paint.
me = body.data
DRIVER_EYE = Vector((-0.376, -0.07, 1.26))  # behind the steering wheel (car.gd cockpit_eye)
mi_head = len(me.materials)
me.materials.append(sem["headliner"])
mi_trim = len(me.materials)
me.materials.append(sem["interior_light"])
paint_i = [i for i, m in enumerate(me.materials) if m and m.name == "paint"]
inner = 0
for p in me.polygons:
    if p.material_index not in paint_i:
        continue
    c, n = p.center, p.normal
    if not (-1.75 < c.y < 1.15 and abs(c.x) < 0.9 and 0.3 < c.z < 1.6):
        continue
    if c.y < -1.25 and c.z < 0.95:
        continue  # the boot
    to_mid = Vector((0.0, max(-1.2, min(0.9, c.y)), 0.95)) - c
    # Or turned to the driver's eye (door shuts, pillar edges round the
    # glass): the outer panels all face away from it. The door mirrors and
    # the bonnet stay paint.
    to_eye = (DRIVER_EYE - c).normalized()
    if n.dot(to_mid.normalized()) < 0.35 and not (n.dot(to_eye) > 0.2 and abs(c.x) < 0.86 and c.y < 1.0):
        continue
    p.material_index = mi_head if (c.z > 1.05 and n.z < -0.5) else mi_trim
    inner += 1
print("paint faces turned to cabin trim:", inner)

# Plain plate fields of the real plate's size (520 x 112 mm), flat in their
# recesses: the game lays its AVTOSMART plates exactly over them. The rear
# one replaces the source's field (smaller, bent with the bumper: its edge
# showed above the new plate, which stood off at an angle); the front one
# sits in the plate recess of the lower grille.
plate_i = [i for i, m in enumerate(me.materials) if m and m.name == "plate"]
old_field = [p for p in me.polygons if p.material_index in plate_i]
assert old_field, "rear plate field not found"
rear_pts = [me.vertices[v].co for p in old_field for v in p.vertices]
rmn, rmx = bounds_pts(rear_pts)
rear_c = (rmn + rmx) / 2

rear_y = min(v.y for v in rear_pts)
# The recess is the flat black panel in the lower grille (the slats around it
# are small faces): its big forward-facing faces, area-weighted.
recess = [p for p in me.polygons if abs(p.center.x) < 0.3 and p.center.y > 2.0 and 0.38 < p.center.z < 0.65
          and p.normal.y > 0.9 and p.area > 0.01 and me.materials[p.material_index].name == "trim_black"]
assert recess, "front plate recess not found"
front_y = max(p.center.y for p in recess)
front_z = sum(p.center.z * p.area for p in recess) / sum(p.area for p in recess)
bm = bmesh.new()
bm.from_mesh(me)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[p.index] for p in old_field], context="FACES")
w, h = 0.52 / 2, 0.112 / 2
for cy, cz, outward in ((front_y + 0.006, front_z, 1.0), (rear_y - 0.006, rear_c.z, -1.0)):
    vs = [bm.verts.new((dx * w, cy, cz + dz * h)) for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    f = bm.faces.new(vs)
    f.material_index = plate_i[0]
    f.normal_update()
    if f.normal.y * outward < 0:
        f.normal_flip()
bm.to_mesh(me)
bm.free()
print(f"PLATES rear y={rear_y - 0.006:.3f} z={rear_c.z:.3f} (old field {tuple(round(v, 3) for v in rmx - rmn)})"
      f" front y={front_y:.3f} z={front_z:.3f}")

decimate(body, 70000)
for o in meshes():
    activate(o)
    for p in o.data.polygons:
        p.use_smooth = True
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    except Exception as exc:
        print("smooth-by-angle unavailable:", exc)

# --- 10. Mirror eyes ---------------------------------------------------------------------------------
mirror_eyes = {}
for side_name, sign in (("L", -1), ("R", 1)):
    pts_m = [v.co for v in me.vertices if v.co.x * sign > 0.86 and 0.4 < v.co.y < 1.1 and v.co.z > 0.8]
    mn, mx = bounds_pts(pts_m)
    eye = Vector(((mn.x + mx.x) / 2, mn.y - 0.02, (mn.z + mx.z) / 2))
    mirror_eyes[side_name] = eye
    new_empty("MirrorEye" + side_name, eye)

# --- 11. Collision hull (body without the door mirrors) ---------------------------------------------
src_bm = bmesh.new()
src_bm.from_mesh(body.data)
ret = bmesh.ops.convex_hull(src_bm, input=[v for v in src_bm.verts if not (abs(v.co.x) > 0.84 and v.co.z > 0.8
                                                                           and 0.3 < v.co.y < 1.1)],
                            use_existing_faces=False)
hull_faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
hull_bm = bmesh.new()
vmap = {}
for f in hull_faces:
    vs = []
    for v in f.verts:
        if v not in vmap:
            vmap[v] = hull_bm.verts.new(v.co)
        vs.append(vmap[v])
    try:
        hull_bm.faces.new(vs)
    except ValueError:
        pass
src_bm.free()
hull_mesh = bpy.data.meshes.new("CollisionHull")
hull_bm.to_mesh(hull_mesh)
hull_bm.free()
hull_obj = bpy.data.objects.new("CollisionHull", hull_mesh)
collection.objects.link(hull_obj)
decimate(hull_obj, 160)

for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)
for img in list(bpy.data.images):
    if img.users == 0:
        bpy.data.images.remove(img)

# --- 12. Report + export ------------------------------------------------------------------------------
total = 0
for o in sorted(meshes(), key=lambda o: o.name):
    n = tri_count(o)
    total += n
    print(f"  {o.name:18s} {n:7d} tris  mats={[m.name for m in o.data.materials]}")
print("TOTAL TRIS", total)
print(f"TYRE radius={tyre_radius:.4f}")
for corner in ("FL", "FR", "RL", "RR"):
    c = wheel_centre[corner]
    print(f"WHEEL {corner} blender=({c.x:.4f},{c.y:.4f},{c.z:.4f})  godot=({c.x:.4f},{c.z:.4f},{-c.y:.4f})")
bmn, bmx = bounds([body])
side_x = max(abs(v.co.x) for v in body.data.vertices if -1.2 < v.co.y < -0.4)
print(f"FOOTPRINT front={bmx.y:.3f} rear={-bmn.y:.3f} half_width={side_x:.3f} height={bmx.z:.3f}")
for s, eye in mirror_eyes.items():
    print(f"MIRROR_EYE {s} godot=({eye.x:.3f},{eye.z:.3f},{-eye.y:.3f})")

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True,
                          export_normals=True, export_tangents=False, export_materials="EXPORT",
                          export_image_format="NONE", export_animations=False, export_extras=False)
print("exported", OUT)
