"""
Blender (headless) asset build for the GAZelle NEXT van (categories B / C).

    blender -b --python pipeline/blender/build_gazelle.py -- <free_gazelle_next_-_pro.glb> <out.glb>

Source: "[FREE] GAZelle Next - Pro" by UralStrong_lybnineg
(https://sketchfab.com/lybnineg),
https://sketchfab.com/3d-models/free-gazelle-next-pro-6f5f115cb8fc4bb2933b317f505d5708,
licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/).

The source (318k triangles, no textures, node names lost to an encoding
mix-up) faces +Y with the driver on -X, in metres but not to scale. This
script:
  * centres it on the axles, tyres on z = 0, scaled uniformly to the maker's
    3745 mm wheelbase (6.1 x 2.03 x 2.7 m then, as the real van);
  * assigns the game's semantic materials by the source material;
  * splits the wheels into Wheel_XX -> Spin_XX (the rear rims and hubs come as
    one mesh across the axle and are cut per side; the dense treaded tyres
    are replaced by clean lathed ones);
  * separates the lamps (headlamp reflectors, their amber turn sections, the
    rear clusters, the side markers), the door-mirror glass (MirrorEyeL/R),
    and adds a modelled steering wheel under a SteeringPivot (the source has
    none);
  * decimates to a mobile budget and adds a convex CollisionHull.
Prints the wheel centres, track and footprint used by car.gd / the C++ preset.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
REAL_WHEELBASE = 3.745

# Source objects (Sketchfab's Object_N).
FRONT_WHEELS = {"FR": ["Object_14", "Object_15"], "FL": ["Object_69", "Object_70"]}
REAR_WHEELS = ["Object_51", "Object_52"]  # hubs + rims of both rear wheels
TYRES = ["Object_16", "Object_71", "Object_54", "Object_55"]
HEAD_REFLECTOR = ["Object_47", "Object_48"]
HEAD_TURN = ["Object_49"]
HEAD_HOUSING = ["Object_46"]
HEAD_COVER = ["Object_18"]
REAR_LAMPS = ["Object_6", "Object_10"]
SIDE_MARKERS = ["Object_43", "Object_44"]
GLASS = ["Object_7", "Object_64", "Object_75", "Object_12"]
MIRROR_GLASS = ["Object_28"]
SEATS = ["Object_35", "Object_36", "Object_37", "Object_39", "Object_40", "Object_41"]
INTERIOR = ["Object_5", "Object_59", "Object_60"] + SEATS
DROP = ["Object_32", "Object_33"]  # 1 cm specks

MATERIAL = {  # source material -> semantic
    "material": "paint", "material_1": "trim_black", "material_2": "lamp_red", "material_3": "window",
    "material_4": "trim_black", "material_5": "trim_black", "material_6": "lamp_red", "009": "metal",
    "008": "window", "material_9": "rim", "material_10": "trim_black", "material_11": "rubber",
    "material_12": "trim_black", "material_13": "chrome", "001": "chrome", "004": "trim_black",
    "material_16": "mirror", "material_17": "chrome", "material_18": "chrome", "material_19": "interior",
    "material_20": "interior", "material_21": "interior_light", "material_22": "lamp_orange",
    "material_23": "headlamp", "material_24": "lamp_orange",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
collection = scene.collection
for mat in list(bpy.data.materials):
    mat.name = "src_" + mat.name


def meshes():
    return [o for o in scene.objects if o.type == "MESH"]


def base(name):
    return name.removeprefix("src_").lstrip(".").split(".")[0]


def one(name):
    o = bpy.data.objects.get(name)
    return o if o is not None and o.type == "MESH" else None


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
    mod.ratio = max(target / n, 0.004)
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
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


def partition(obj, labels, new_name):
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
            for m in obj.data.materials:
                new_me.materials.append(m)
        bm.to_mesh(target)
        bm.free()
    r = bpy.data.objects.new(new_name, new_me)
    collection.objects.link(r)
    return r


def face_labels(obj, pred):
    return [pred(p.center) for p in obj.data.polygons]


def split_by_side(obj, left_name, right_name):
    r = partition(obj, face_labels(obj, lambda c: c.x >= 0), right_name)
    obj.name = left_name
    obj.data.name = left_name
    return obj, r


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


SEMANTIC = ["paint", "trim_black", "chrome", "rim", "rubber", "metal", "window", "lamp_glass", "lamp_orange",
            "lamp_red", "lamp_white", "interior", "interior_light", "interior_black", "plate", "mirror", "headlamp"]
sem = {name: bpy.data.materials.new(name) for name in SEMANTIC}


def assign(o, rule):
    for slot in o.material_slots:
        src = base(slot.material.name) if slot.material else ""
        slot.material = sem[rule(src)]


def by_source(src):
    return MATERIAL.get(src, "trim_black")


def single_material(o, name):
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    while len(me.materials) > 1:
        me.materials.pop()
    if not me.materials:
        me.materials.append(sem[name])
    else:
        me.materials[0] = sem[name]


# --- 1. Flatten, bake transforms --------------------------------------------------------------
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
    if one(name):
        bpy.data.objects.remove(one(name), do_unlink=True)

# --- 2. Placement ------------------------------------------------------------------------------
rims = {c: bounds([one(n) for n in names]) for c, names in FRONT_WHEELS.items()}
rear_mn, rear_mx = bounds([one(n) for n in REAR_WHEELS])
tyre_bounds = [bounds([one(n)]) for n in TYRES if one(n)]
front_y = sum((mn.y + mx.y) / 2 for mn, mx in rims.values()) / 2
rear_y = (rear_mn.y + rear_mx.y) / 2
x_c = sum((mn.x + mx.x) / 2 for mn, mx in rims.values()) / 2
z_ground = min(bounds([one("Object_16"), one("Object_71")])[0].z, 0.0)
S = REAL_WHEELBASE / (front_y - rear_y)
print(f"source axles y {front_y:.3f} / {rear_y:.3f}, x centre {x_c:.3f}, ground {z_ground:.3f}, scale {S:.4f}")
PLACE = Matrix.Scale(S, 4) @ Matrix.Translation(Vector((-x_c, -(front_y + rear_y) / 2, -z_ground)))
for o in meshes():
    o.data.transform(PLACE)
    o.data.update()

# --- 3. Wheels ---------------------------------------------------------------------------------
def make_tyre(name, centre, radius, width, bead_radius, segments=36):
    """A clean lathed tyre (axis = X) with rounded shoulders and bulging walls."""
    t = width / 2
    r_out = radius
    right = [(0.3 * t, r_out), (0.84 * t, r_out - 0.002), (0.97 * t, r_out - 0.016), (1.0 * t, r_out - 0.05),
             (0.97 * t, bead_radius + 0.045), (0.88 * t, bead_radius + 0.018), (0.82 * t, bead_radius)]
    loop = [(0.0, r_out)] + right + [(0.0, bead_radius)] + [(-x, r) for x, r in reversed(right)]
    bm = bmesh.new()
    rings = []
    for j in range(segments):
        a = j / segments * math.tau
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((centre.x + x, centre.y + r * ca, centre.z + r * sa)) for x, r in loop])
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
    for p in me.polygons:
        p.use_smooth = True
    return o


# The front rims of the source are not concentric with their hubs (the rim
# sits 2.6 cm off the axis and the black inner part is 0.5 m wide): turning,
# they wobbled. The rear wheels are clean and centred, so all four wheels are
# built from them: each rear wheel is copied forward to the front axle on its
# own side (the front tyres give the front wheel centres).
front_centre = {}
for corner, tyre in (("FR", "Object_16"), ("FL", "Object_71")):
    mn, mx = bounds([one(tyre)])
    front_centre[corner] = (mn + mx) / 2
for names in FRONT_WHEELS.values():
    for n in names:
        if one(n):
            bpy.data.objects.remove(one(n), do_unlink=True)
# The source tyres (dense and treaded) give way to clean lathed ones below;
# left in, they would join the body and its collision hull would reach the road.
for n in TYRES:
    if one(n):
        bpy.data.objects.remove(one(n), do_unlink=True)
parts = {}
for n in REAR_WHEELS:
    o = one(n)
    r = partition(o, face_labels(o, lambda c: c.x >= 0), n + "_R")
    parts.setdefault("RL", []).append(o)
    parts.setdefault("RR", []).append(r)
tyre_r = {}
tyre_w = {}
centres = {}
for corner in ("RL", "RR"):
    for o in parts[corner]:
        assign(o, by_source)
        decimate(o, 1100 if "rim" in [m.name for m in o.data.materials] else 260)
    mn, mx = bounds(parts[corner])
    centres[corner] = (mn + mx) / 2
for front, rear in (("FL", "RL"), ("FR", "RR")):
    shift = front_centre[front] - centres[rear]
    shift.z = 0.0
    copies = []
    for o in parts[rear]:
        c = o.copy()
        c.data = o.data.copy()
        c.name = o.name + "_" + front
        collection.objects.link(c)
        c.data.transform(Matrix.Translation(shift))
        copies.append(c)
    parts[front] = copies
    centres[front] = centres[rear] + shift
radius = 0.342
for corner in ("FL", "FR", "RL", "RR"):
    c = centres[corner]
    c.z = radius
    w = tyre_w.get(corner, tyre_w.get("F" + corner[1], 0.2))
    rim_r = max((v.co - c).length for o in parts[corner] for v in o.data.vertices if abs(v.co.x - c.x) < 0.05)
    parts[corner].append(make_tyre("Tyre_" + corner, c, radius, 0.195, min(rim_r, radius - 0.1)))
    pivot = new_empty("Wheel_" + corner, c)
    s = join(parts[corner], "Spin_" + corner)
    set_origin(s, c)
    s.parent = pivot
    s.matrix_parent_inverse = pivot.matrix_world.inverted()

# --- 4. Lamps ------------------------------------------------------------------------------------
head = join([one(n) for n in HEAD_REFLECTOR], "Lamp_Head")
single_material(head, "lamp_white")
turn = join([one(n) for n in HEAD_TURN], "Lamp_TurnF")
single_material(turn, "lamp_orange")
split_by_side(turn, "Lamp_TurnFL", "Lamp_TurnFR")
for n in HEAD_HOUSING:
    assign(one(n), lambda s: "headlamp")
cover = join([one(n) for n in HEAD_COVER], "LampGlass")
assign(cover, lambda s: "lamp_glass")
# Rear clusters: the upper red part is the tail / stop lamp, the lower third
# the (amber-lit) indicator.
rear = join([one(n) for n in REAR_LAMPS], "Lamp_Tail")
single_material(rear, "lamp_red")
rmn, rmx = bounds([rear])
z_split = rmn.z + (rmx.z - rmn.z) * 0.36
turn_r = partition(rear, face_labels(rear, lambda c: c.z < z_split), "Lamp_TurnR")
if turn_r:
    single_material(turn_r, "lamp_orange")
    split_by_side(turn_r, "Lamp_TurnRL", "Lamp_TurnRR")
side = join([one(n) for n in SIDE_MARKERS], "Lamp_Side")
single_material(side, "lamp_orange")
split_by_side(side, "Lamp_TurnSL", "Lamp_TurnSR")

# --- 5. Glass, mirrors, interior ------------------------------------------------------------------
glass = join([one(n) for n in GLASS], "Glass")
assign(glass, lambda s: "window")
mirror = join([one(n) for n in MIRROR_GLASS], "MirrorGlass")
assign(mirror, lambda s: "mirror")
mirror_eyes = {}
for side_name, sign in (("L", -1), ("R", 1)):
    pts_m = [v.co for v in mirror.data.vertices if v.co.x * sign > 0]
    mn, mx = bounds_pts(pts_m)
    eye = Vector(((mn.x + mx.x) / 2, mn.y - 0.02, (mn.z + mx.z) / 2))
    mirror_eyes[side_name] = eye
    new_empty("MirrorEye" + side_name, eye)
seat_mn, seat_mx = bounds([one("Object_35")])  # the driver's seat
interior = join([one(n) for n in INTERIOR], "Interior")
assign(interior, lambda s: {"interior_light": "interior_light", "interior": "interior"}.get(by_source(s),
                                                                                          "interior_black"))

# --- 6. Steering wheel (modelled: the source has none) --------------------------------------------
glass_pts = [v.co for v in glass.data.vertices if abs(v.co.x) < 0.5]
screen_base = min(glass_pts, key=lambda p: p.z)
driver_x = (seat_mn.x + seat_mx.x) / 2
# Van driving position: the wheel 0.3 m ahead of the seat cushion's front
# edge, a little below the windscreen base, its axis 35 degrees above the
# horizontal (a flatter wheel than a car's).
wheel_c = Vector((driver_x, seat_mx.y + 0.3, screen_base.z - 0.2))
tilt = math.radians(35.0)  # axis angle above the horizontal, pointing at the driver
axis = Vector((0.0, -math.cos(tilt), math.sin(tilt))).normalized()
bm = bmesh.new()
R, r = 0.2, 0.017
seg, ring_seg = 28, 8
rings = []
for i in range(seg):
    a = i / seg * math.tau
    ca, sa = math.cos(a), math.sin(a)
    rings.append([bm.verts.new(((R + r * math.cos(b)) * ca, (R + r * math.cos(b)) * sa, r * math.sin(b)))
                  for b in (j / ring_seg * math.tau for j in range(ring_seg))])
for i in range(seg):
    a, b2 = rings[i], rings[(i + 1) % seg]
    for j in range(ring_seg):
        k = (j + 1) % ring_seg
        bm.faces.new((a[j], b2[j], b2[k], a[k]))
hub = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.075, radius2=0.06, depth=0.07)
bmesh.ops.translate(bm, verts=hub["verts"], vec=(0, 0, 0.02))
for ang in (math.pi * 0.5, math.pi * 1.5, math.pi * 1.0):  # 3 spokes: left, right, down
    d = Vector((math.cos(ang), math.sin(ang), 0))
    sp = bmesh.ops.create_cube(bm, size=1.0)
    m = (Matrix.Translation(d * (0.06 + (R - 0.06) / 2) + Vector((0, 0, 0.005)))
         @ Matrix.Rotation(ang, 4, "Z") @ Matrix.Diagonal((R - 0.06, 0.045, 0.016, 1.0)))
    bmesh.ops.transform(bm, matrix=m, verts=sp["verts"])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
sw_me = bpy.data.meshes.new("SteeringWheel")
bm.to_mesh(sw_me)
bm.free()
sw_me.materials.append(sem["trim_black"])
sw = bpy.data.objects.new("SteeringWheel", sw_me)
collection.objects.link(sw)
for p in sw_me.polygons:
    p.use_smooth = True
z = axis
x = Vector((1, 0, 0))
x = (x - z * x.dot(z)).normalized()
y = z.cross(x)
rotm = Matrix((x, y, z)).transposed()
spivot = new_empty("SteeringPivot", wheel_c, rot_matrix=rotm)
sw.matrix_world = spivot.matrix_world
sw.parent = spivot
sw.matrix_parent_inverse = spivot.matrix_world.inverted()
print("driver seat", tuple(round(v, 3) for v in seat_mn), tuple(round(v, 3) for v in seat_mx))
print("steering centre", tuple(round(v, 3) for v in wheel_c), "axis", tuple(round(v, 3) for v in axis),
      "windscreen base", tuple(round(v, 3) for v in screen_base))

# --- 7. Body ------------------------------------------------------------------------------------
KEEP = ("Spin_", "Lamp_", "SteeringWheel", "Glass", "LampGlass", "Interior", "MirrorGlass", "Tyre_")
rest = [o for o in meshes() if not o.name.startswith(KEEP)]
for o in rest:
    if o.name == "Object_81":
        assign(o, lambda s: "plate")
    else:
        assign(o, by_source)
body = join(rest, "Body")
budgets = {"Body": 52000, "Glass": 2500, "LampGlass": 1500, "Interior": 14000, "Lamp_Head": 2200,
           "Lamp_Tail": 500, "MirrorGlass": 200}
for o in meshes():
    if o.name in budgets:
        decimate(o, budgets[o.name])
    elif o.name.startswith("Lamp_Turn"):
        decimate(o, 300)
for o in meshes():
    for p in o.data.polygons:
        p.use_smooth = True
    try:
        activate(o)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    except Exception as exc:
        print("smooth-by-angle unavailable:", exc)

# --- 8. Collision hull ---------------------------------------------------------------------------
src_bm = bmesh.new()
src_bm.from_mesh(body.data)
ret = bmesh.ops.convex_hull(src_bm, input=[v for v in src_bm.verts if not (abs(v.co.x) > 1.0 and v.co.z > 1.0)],
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

# --- 9. Report + export ----------------------------------------------------------------------------
total = 0
for o in sorted(meshes(), key=lambda o: o.name):
    n = tri_count(o)
    total += n
    print(f"  {o.name:18s} {n:7d} tris  mats={[m.name for m in o.data.materials]}")
print("TOTAL TRIS", total)
for corner in ("FL", "FR", "RL", "RR"):
    c = centres[corner]
    print(f"WHEEL {corner} blender=({c.x:.4f},{c.y:.4f},{c.z:.4f})  godot=({c.x:.4f},{c.z:.4f},{-c.y:.4f})")
bmn, bmx = bounds([body])
print(f"FOOTPRINT front={bmx.y:.3f} rear={-bmn.y:.3f} half_width={max(abs(bmn.x), bmx.x):.3f} height={bmx.z:.3f}")
side_x = max(abs(v.co.x) for v in body.data.vertices if -1.5 < v.co.y < 0.5)
print(f"BODY SIDE half_width={side_x:.3f}")
for s, eye in mirror_eyes.items():
    print(f"MIRROR_EYE {s} godot=({eye.x:.3f},{eye.z:.3f},{-eye.y:.3f})")
plate = [v.co for v in body.data.vertices]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True,
                          export_normals=True, export_tangents=False, export_materials="EXPORT",
                          export_image_format="NONE", export_animations=False, export_extras=False)
print("exported", OUT)
