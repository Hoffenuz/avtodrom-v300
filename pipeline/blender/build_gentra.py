"""
Blender (headless) asset build for the Daewoo (Ravon/Chevrolet) Gentra exam car (manual).

    blender -b --python pipeline/blender/build_gentra.py -- <daewoo__gentra.glb> <out.glb>

Source: "Daewoo_ Gentra" by Doniyor 3D (https://sketchfab.com/doniyorgroup),
https://sketchfab.com/3d-models/daewoo--gentra-bf6d601e37ef4b829f27998d1c7b36c1,
licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/).

The source is a clean ~1M triangle model with real proportions, facing -Y,
the driver on +X, in arbitrary units (wheelbase 8.28). This script:
  * turns it to face +Y (driver on -X) and scales it uniformly so the
    wheelbase is the real 2600 mm, tyres standing on z = 0 (the other
    dimensions then come out right too: 4.53 x 1.73 x 1.45 m);
  * splits the wheels into Wheel_XX (pivot at the hub) -> Spin_XX; the hub
    and brake-disc meshes of the source span all four corners and are cut
    per corner;
  * assigns semantic materials (paint, trim_black, chrome, window,
    lamp_glass, interior, ...) that the game replaces with its own PBR set;
  * separates the lamps (headlamp reflectors, front turn bowls, rear
    clusters and their clear turn sections, the high stop lamp, the side
    repeaters), the steering wheel under a SteeringPivot (local Z = column
    axis) and the door-mirror glass, and adds MirrorEyeL/R empties;
  * decimates to a mobile budget and adds a convex CollisionHull.
Prints the wheel centres and the body footprint used by car.gd / the C++ preset.
"""
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

REAL_WHEELBASE = 2.600
# Steering wheel island of the interior mesh (source units, bbox centre).
SW_SRC = Vector((1.07, -1.71, 2.68))
# The parts that belong to the wheels (the hub caps and brake discs span all
# four corners in the source and are cut per corner).
WHEEL_OBJECTS = {"Object_23", "Object_48", "Object_49", "Object_50", "Object_51", "Object_52",
                 "Object_53", "Object_54", "Object_55", "Object_56"}
# Dropped: the 5 cm chrome logos on the hub caps (16.5k triangles each) and
# the number plates' blue and yellow flag details (the game shows plain plates).
DROP = {"Object_40", "Object_42", "Object_44", "Object_45", "Object_11", "Object_13"}
# The grille and boot-lid badges (15k triangles each, 10 cm across) are
# thinned before they join the body, so they do not eat its budget.
BADGES = {"Object_36": 700, "Object_39": 700}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
collection = scene.collection


# The source uses some of the semantic names ("chrome", "interior"): keep
# them apart so the new semantic materials get exactly those names.
for mat in list(bpy.data.materials):
    mat.name = "src_" + mat.name


def meshes():
    return [o for o in scene.objects if o.type == "MESH"]


def base(name):
    return name.removeprefix("src_").split(".")[0]


def one(name):
    o = bpy.data.objects.get(name)
    return o if o is not None and o.type == "MESH" else None


# --- 1. Flatten hierarchy, bake transforms ---------------------------------------------
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
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)


def bounds_pts(pts):
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def bounds(objs):
    return bounds_pts([v.co for o in objs for v in o.data.vertices])


# --- 2. Placement: face +Y, real scale, tyres on the ground -------------------------------
tyres = [o for o in meshes() if o.data.materials and o.data.materials[0] and
         base(o.data.materials[0].name) == "tire"]
assert len(tyres) == 4, [o.name for o in tyres]
tyre_c = []
for o in tyres:
    mn, mx = bounds([o])
    tyre_c.append(((mn + mx) / 2, (mx.z - mn.z) / 2))
x_c = sum(c.x for c, _ in tyre_c) / 4
front_src = sum(c.y for c, _ in tyre_c if c.y < 0) / 2  # the source faces -Y
rear_src = sum(c.y for c, _ in tyre_c if c.y > 0) / 2
y_c = (front_src + rear_src) / 2
z_ground = min(bounds([o])[0].z for o in tyres)
S = REAL_WHEELBASE / (rear_src - front_src)
print(f"source: axles y {front_src:.3f} / {rear_src:.3f}, x centre {x_c:.3f}, ground {z_ground:.3f}, scale {S:.5f}")

PLACE = (Matrix.Scale(S, 4) @ Matrix.Rotation(math.pi, 4, "Z")
         @ Matrix.Translation(Vector((-x_c, -y_c, -z_ground))))


def place(p):
    return PLACE @ Vector(p)


for o in meshes():
    o.data.transform(PLACE)
    o.data.update()

# --- 3. Semantic materials --------------------------------------------------------------------
SEMANTIC = ["paint", "trim_black", "chrome", "rim", "rubber", "metal", "brake_disc", "window", "lamp_glass",
            "lamp_orange", "lamp_red", "lamp_white", "interior", "interior_light", "headliner", "plate", "mirror"]
sem = {name: bpy.data.materials.new(name) for name in SEMANTIC}
assert all(m.name == n for n, m in sem.items())


def assign(o, rule):
    """rule: callable(source material name) -> semantic name"""
    for slot in o.material_slots:
        src = slot.material.name if slot.material else ""
        slot.material = sem[rule(src)]


def single_material(o, name):
    """One material slot only: the game swaps a lamp's surface 0 on and off."""
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    while len(me.materials) > 1:
        me.materials.pop()
    if not me.materials:
        me.materials.append(sem[name])
    else:
        me.materials[0] = sem[name]


BODY_RULE = {
    "carpaint": "paint", "black": "trim_black", "chrome": "chrome", "LicPlate_white": "plate",
    "LicPlate_black": "trim_black",
    "windowglass": "window", "darkglass": "window", "clearglass": "lamp_glass",
}


def body_rule(src):
    return BODY_RULE.get(base(src), "trim_black")


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


def face_islands(obj):
    """Lists of face indices, one per connected (by vertices) piece."""
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


def island_labels(obj, pred):
    """Per-face labels: pred(bbox min, bbox max, vertex count) of the face's island."""
    me = obj.data
    labels = [False] * len(me.polygons)
    for isl in face_islands(obj):
        vids = {i for fi in isl for i in me.polygons[fi].vertices}
        mn, mx = bounds_pts([me.vertices[i].co for i in vids])
        if pred(mn, mx, len(vids)):
            for fi in isl:
                labels[fi] = True
    return labels


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


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def decimate(o, target):
    n = tri_count(o)
    if n <= target:
        return
    mod = o.modifiers.new("dec", "DECIMATE")
    mod.ratio = max(target / n, 0.005)
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)


# --- 4. Wheels ---------------------------------------------------------------------------------
def corner_of(p):
    return ("F" if p.y > 0 else "R") + ("L" if p.x < 0 else "R")


wheel_centre = {}
wheel_radius_by = {}
for o in tyres:
    mn, mx = bounds([o])
    c = (mn + mx) / 2
    wheel_centre[corner_of(c)] = c
    wheel_radius_by[corner_of(c)] = (mx.z - mn.z) / 2
wheel_radius = list(wheel_radius_by.values())
assert sorted(wheel_centre) == ["FL", "FR", "RL", "RR"], sorted(wheel_centre)
tyre_radius = sum(wheel_radius) / 4

# Per-part triangle budgets (per wheel): the rim carries the look, the rest is
# seen small or hidden behind the spokes.
WHEEL_BUDGET = {"material": 1500, "brakedisk": 220}
wheel_parts = {k: [] for k in wheel_centre}
tyre_width = {}
rim_radius = {}
for name in sorted(WHEEL_OBJECTS):
    o = one(name)
    if o is None:
        continue
    kind = base(o.data.materials[0].name)
    rule = {"tire": "rubber", "material": "metal" if name == "Object_52" else "rim",
            "brakedisk": "brake_disc"}[kind]
    assign(o, lambda s, r=rule: r)
    pieces = {}
    rest = o
    for corner in ("FL", "FR", "RL"):
        piece = partition(rest, face_labels(rest, lambda c, k=corner: corner_of(c) == k), f"{name}_{corner}")
        if piece is not None:
            pieces[corner] = piece
    if len(rest.data.polygons):
        pieces["RR"] = rest
    else:
        bpy.data.objects.remove(rest, do_unlink=True)
    for corner, piece in pieces.items():
        mn, mx = bounds([piece])
        if kind == "tire":
            # The treaded source tyre decimates into a saw: replaced below.
            tyre_width[corner] = mx.x - mn.x
            bpy.data.objects.remove(piece, do_unlink=True)
            continue
        if kind == "material" and name != "Object_52":
            rim_radius[corner] = (mx.z - mn.z) / 2
        budget = WHEEL_BUDGET[kind] if name != "Object_52" else 200
        decimate(piece, budget)
        wheel_parts[corner].append(piece)


def make_tyre(name, centre, radius, width, bead_radius, segments=40):
    """A clean lathed tyre (axis = X): tread with two grooves, rounded
    shoulders, bulging sidewalls, the bead hidden inside the rim flange."""
    t = width / 2
    r_out = radius
    right = [(0.28 * t, r_out), (0.31 * t, r_out - 0.006), (0.37 * t, r_out - 0.006), (0.40 * t, r_out),
             (0.84 * t, r_out - 0.002), (0.97 * t, r_out - 0.014), (1.0 * t, r_out - 0.045),
             (0.97 * t, bead_radius + 0.04), (0.88 * t, bead_radius + 0.016), (0.82 * t, bead_radius)]
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
    return o


for corner in wheel_parts:
    wheel_parts[corner].append(make_tyre("Tyre_" + corner, wheel_centre[corner], wheel_radius_by[corner],
                                         tyre_width[corner], rim_radius[corner] - 0.012))

for corner, parts in wheel_parts.items():
    centre = wheel_centre[corner]
    pivot = new_empty("Wheel_" + corner, centre)
    s = join(parts, "Spin_" + corner)
    set_origin(s, centre)
    s.parent = pivot
    s.matrix_parent_inverse = pivot.matrix_world.inverted()

# --- 5. Lamps ----------------------------------------------------------------------------------
# Headlamps: the chrome reflectors. The outer bowls (|x| > 0.65 m) hold the
# turn-signal bulbs (the tiny orange bulbs of the source join them).
head = one("Object_38")
assign(head, lambda s: "lamp_white")
turn_f = partition(head, island_labels(head, lambda mn, mx, n: abs((mn.x + mx.x) / 2) > 0.655), "Lamp_TurnF")
head = join([head], "Lamp_Head")
single_material(head, "lamp_white")
turn_f = join([turn_f, one("Object_6")], "Lamp_TurnF")
single_material(turn_f, "lamp_white")
split_by_side(turn_f, "Lamp_TurnFL", "Lamp_TurnFR")

# Rear clusters: red lens = tail + stop; the clear inner section = turn signal.
tail = join([one("Object_8")], "Lamp_Tail")
single_material(tail, "lamp_red")
turn_r = join([one("Object_3")], "Lamp_TurnR")
single_material(turn_r, "lamp_white")
split_by_side(turn_r, "Lamp_TurnRL", "Lamp_TurnRR")
brake = join([one("Object_7")], "Lamp_Brake")  # high-mounted stop lamp (LEDs)
single_material(brake, "lamp_red")
# Side repeaters on the front wings.
side = join([one("Object_43")], "Lamp_Side")
single_material(side, "lamp_orange")
split_by_side(side, "Lamp_TurnSL", "Lamp_TurnSR")

lamp_covers = [one("Object_46"), one("Object_47")]
for o in lamp_covers:
    assign(o, lambda s: "lamp_glass")
join(lamp_covers, "LampGlass")

# --- 6. Steering wheel ---------------------------------------------------------------------------
interior_src = one("Object_5")
sw_target = place(SW_SRC)
sw_labels = island_labels(interior_src, lambda mn, mx, n: n > 1000 and ((mn + mx) / 2 - sw_target).length < 0.05
                          and (mx - mn).length > 0.3)
assert sum(sw_labels) > 0, "steering wheel island not found"
sw = partition(interior_src, sw_labels, "SteeringWheel")
pts = np.array([v.co[:] for v in sw.data.vertices])


def pca(p):
    c = p.mean(axis=0)
    w, v = np.linalg.eigh(np.cov((p - c).T))
    return c, v[:, 0]  # smallest spread = the wheel's axis


c0, ax0 = pca(pts)
d = pts - c0
radial = np.linalg.norm(d - np.outer(d @ ax0, ax0), axis=1)
ring = pts[radial > 0.8 * radial.max()]  # the rim only: the hub and column would tilt the fit
c_ring, axis = pca(ring)
c = Vector(c_ring)
axis = Vector(axis).normalized()
if axis.y > 0:  # towards the driver (rearwards, -Y)
    axis = -axis
assign(sw, lambda s: "trim_black")
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
print("steering centre", tuple(round(v, 3) for v in c), "axis", tuple(round(v, 3) for v in axis),
      "ring radius", round(float(radial.max()), 3))

# --- 7. Glass, interior ----------------------------------------------------------------------------
glass = [one("Object_9"), one("Object_4")]
for o in glass:
    assign(o, lambda s: "window")
join(glass, "Glass")

interior = [interior_src, one("Object_18")]  # Object_18: the dash's black details
assign(interior_src, lambda s: "interior")
# Headliner and pillar trims (the cabin shell above the waist line) are light
# grey in the real car; seats, headrests and the mirror are separate pieces.
interior_src.data.materials.append(sem["headliner"])
shell = max(face_islands(interior_src), key=len)
for fi in shell:
    p = interior_src.data.polygons[fi]
    if p.center.z > 1.02:
        p.material_index = len(interior_src.data.materials) - 1
assign(one("Object_18"), lambda s: "trim_black")
join(interior, "Interior")

# --- 8. Door mirrors ----------------------------------------------------------------------------------
# The mirror glass is the chrome inside the painted housings (|x| > 0.83 m,
# beside the A-pillars).
chrome_trim = one("Object_41")
mirror_glass = partition(chrome_trim, face_labels(chrome_trim, lambda c: abs(c.x) > 0.83 and 0.3 < c.y < 0.8),
                         "MirrorGlass")
assign(mirror_glass, lambda s: "mirror")
mirror_eyes = {}
for side_name, sign in (("L", -1), ("R", 1)):
    pts_m = [v.co for v in mirror_glass.data.vertices if v.co.x * sign > 0]
    mn, mx = bounds_pts(pts_m)
    eye = Vector(((mn.x + mx.x) / 2, mn.y - 0.02, (mn.z + mx.z) / 2))
    mirror_eyes[side_name] = eye
    new_empty("MirrorEye" + side_name, eye)
    print(f"mirror {side_name}: glass {tuple(round(v, 3) for v in mn)} .. {tuple(round(v, 3) for v in mx)}")

# --- 9. Everything else is the body ---------------------------------------------------------------------
# Number plates: keep the black border, drop the lettering (plain plates).
plate_ink = one("Object_10")
lettering = partition(plate_ink, island_labels(plate_ink, lambda mn, mx, n: mx.x - mn.x < 0.3), "PlateLettering")
bpy.data.objects.remove(lettering, do_unlink=True)

KEEP = ("Spin_", "Lamp_", "SteeringWheel", "Glass", "LampGlass", "Interior", "MirrorGlass", "CollisionHull")
rest = [o for o in meshes() if not o.name.startswith(KEEP)]
for name, budget in BADGES.items():
    decimate(bpy.data.objects[name], budget)
for o in rest:
    assign(o, body_rule)
body = join(rest, "Body")

# --- 10. Decimation ------------------------------------------------------------------------------------
budgets = {
    "Body": 70000, "Glass": 4000, "LampGlass": 3000, "Interior": 24000, "SteeringWheel": 2400,
    "Lamp_Head": 1800, "Lamp_Tail": 1600, "Lamp_Brake": 300, "MirrorGlass": 300,
}
for o in meshes():
    if o.name.startswith("Lamp_Turn"):
        decimate(o, 500)
    elif o.name in budgets:
        decimate(o, budgets[o.name])

for o in meshes():
    for p in o.data.polygons:
        p.use_smooth = True
    try:
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    except Exception as exc:
        print("smooth-by-angle unavailable:", exc)

# --- 11. Collision hull (body without the door mirrors) ----------------------------------------------------
src_bm = bmesh.new()
src_bm.from_mesh(body.data)
ret = bmesh.ops.convex_hull(src_bm, input=[v for v in src_bm.verts if not (abs(v.co.x) > 0.8 and v.co.z > 0.9)
                                           or v.co.y < 0.2 or v.co.y > 0.85],
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

# Unused source materials and images would only bloat the file.
for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)
for img in list(bpy.data.images):
    if img.users == 0:
        bpy.data.images.remove(img)

# --- 12. Report + export ---------------------------------------------------------------------------------
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
side_x = max(abs(v.co.x) for v in body.data.vertices if -1.2 < v.co.y < -0.6)  # rear door, no mirror
print(f"FOOTPRINT front={bmx.y:.3f} rear={-bmn.y:.3f} half_width={side_x:.3f} height={bmx.z:.3f}")
for s, eye in mirror_eyes.items():
    print(f"MIRROR_EYE {s} godot=({eye.x:.3f},{eye.z:.3f},{-eye.y:.3f})")

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
    export_normals=True,
    export_tangents=False,
    export_materials="EXPORT",
    export_image_format="NONE",
    export_animations=False,
    export_extras=False,
)
print("exported", OUT)
