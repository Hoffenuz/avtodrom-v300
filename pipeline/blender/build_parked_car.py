"""
Blender (headless): a light but clean version of a game car for the parked
cars in the exam-centre car park (Surroundings._park_cars).

    blender -b --python pipeline/blender/build_parked_car.py -- <game car.glb> <out.glb> [tris] [voxel] [--npc]
    # or, with the bpy wheel: python3 -c "import sys; sys.argv=['x','--',SRC,OUT]; exec(open(SCRIPT).read())"

Decimating the game model part by part (build_car_lod.py) crumples it: the
body is many thin open shells, and collapsing them to a few percent tears
them into shards. Here the car is first rebuilt as one closed, even surface
(voxel remesh of everything outside the cabin), which then decimates cleanly
and symmetrically. The look of the original is carried over as vertex
colours taken from the nearest original face:
    rgb = surface colour, alpha = kind (1 paint, 0.5 glass, 0 anything else)
so the whole car is one surface with one material (car_parked.gdshader,
which tints the paint per instance).

--npc: the "other participants" cars that drive round the avtodrom
(src/game/traffic_cars.gd). The body is built without the wheels, and the
file also carries one wheel mesh ("NpcWheel", the left front wheel, centred
on its axle) and four empties Wheel_FL/FR/RL/RR at the wheel centres, so the
wheels can turn.
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
NPC = "--npc" in argv
argv = [a for a in argv if a != "--npc"]
SRC, OUT = argv[0], argv[1]
BUDGET = int(argv[2]) if len(argv) > 2 else 2400
VOXEL = float(argv[3]) if len(argv) > 3 else 0.035 # m
WHEEL_BUDGET = 900

DROP = ("Interior", "SteeringWheel", "CollisionHull", "Gauge", "MirrorGlass")
# (colour, kind) per source material; anything else is dark trim.
LOOK = {
    "paint": ((1.0, 1.0, 1.0), 1.0),
    "window": ((0.05, 0.07, 0.09), 0.5),
    "lamp_glass": ((0.8, 0.82, 0.85), 0.5),
    "mirror": ((0.05, 0.07, 0.09), 0.5),
    "chrome": ((0.7, 0.72, 0.74), 0.0),
    "metal": ((0.55, 0.56, 0.58), 0.0),
    "rim": ((0.62, 0.63, 0.65), 0.0),
    "brake_disc": ((0.35, 0.35, 0.36), 0.0),
    "plate": ((0.85, 0.86, 0.86), 0.0),
    "lamp_red": ((0.55, 0.04, 0.03), 0.5),
    "lamp_orange": ((0.85, 0.4, 0.05), 0.5),
    "rubber": ((0.05, 0.05, 0.05), 0.0),
}
DARK = ((0.07, 0.07, 0.075), 0.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene

for o in list(scene.objects):
    if o.type == "MESH" and o.name.startswith(DROP):
        bpy.data.objects.remove(o, do_unlink=True)
wheel_centres = {}
for o in scene.objects:
    if o.name.startswith("Wheel_") and o.type != "MESH":
        wheel_centres[o.name[:8]] = o.matrix_world.translation.copy()
meshes = [o for o in scene.objects if o.type == "MESH"]
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
wheel_parts = []
if NPC:
    wheel_parts = [o for o in meshes if o.name.startswith(("Spin_", "Hub_"))]
    meshes = [o for o in meshes if o not in wheel_parts]


def only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def join_with_look(objs, name):
    """Joins `objs` into one mesh whose face-corner colour carries the look."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    out = bpy.context.view_layer.objects.active
    out.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    c = out.data.color_attributes.new("Look", "FLOAT_COLOR", "CORNER")
    names = [m.name.split(".")[0] if m else "" for m in out.data.materials]
    for poly in out.data.polygons:
        rgb, kind = LOOK.get(names[poly.material_index] if poly.material_index < len(names) else "", DARK)
        for li in poly.loop_indices:
            c.data[li].color = (rgb[0], rgb[1], rgb[2], kind)
    return out


# 1. One reference mesh with the look baked into a face-corner colour.
ref = join_with_look(meshes, "Ref")
before = tris(ref)

# 2. A closed, even copy of the whole car, decimated symmetrically.
car = ref.copy()
car.data = ref.data.copy()
car.name = "CarParked"
scene.collection.objects.link(car)
only(car)
rm = car.modifiers.new("remesh", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = VOXEL
rm.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=rm.name)
dims = car.dimensions
sym_axis = "X" if dims.x < dims.y else "Y"
dec = car.modifiers.new("dec", "DECIMATE")
dec.ratio = min(1.0, BUDGET / max(1, tris(car)))
dec.use_collapse_triangulate = True
dec.use_symmetry = True
dec.symmetry_axis = sym_axis
bpy.ops.object.modifier_apply(modifier=dec.name)

# 3. Colours back from the nearest original face.
for a in list(car.data.color_attributes):
    car.data.color_attributes.remove(a)
car.data.color_attributes.new("Look", "FLOAT_COLOR", "CORNER")
dt = car.modifiers.new("look", "DATA_TRANSFER")
dt.object = ref
dt.use_loop_data = True
dt.data_types_loops = {"COLOR_CORNER"}
dt.loop_mapping = "POLYINTERP_NEAREST"
bpy.ops.object.modifier_apply(modifier=dt.name)
bpy.ops.object.shade_smooth_by_angle(angle=0.7)
bpy.data.objects.remove(ref, do_unlink=True)

car.data.materials.clear()
car.data.materials.append(bpy.data.materials.new("car_parked"))
print(f"PARKED {SRC}: {before} -> {tris(car)} tris")

if NPC:
    # One wheel (the front left), moved to the origin; the game places four
    # copies at the empties and mirrors the right-hand ones.
    fl = [o for o in wheel_parts if o.name.endswith("_FL")]
    others = [o.name for o in wheel_parts if o not in fl]
    wheel = join_with_look(fl, "NpcWheel")
    centre = wheel_centres.get("Wheel_FL")
    if centre is None:
        centre = sum((v.co for v in wheel.data.vertices), wheel.data.vertices[0].co * 0) / len(wheel.data.vertices)
    for v in wheel.data.vertices:
        v.co -= centre
    only(wheel)
    dec = wheel.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, WHEEL_BUDGET / max(1, tris(wheel)))
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dec.name)
    bpy.ops.object.shade_smooth_by_angle(angle=0.6)
    wheel.data.materials.clear()
    wheel.data.materials.append(car.data.materials[0])
    for name in others:
        if name in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    for key, pos in wheel_centres.items():
        e = bpy.data.objects.new(key, None)
        e.location = pos
        scene.collection.objects.link(e)
    print(f"NPC wheel: {tris(wheel)} tris, centres {sorted(wheel_centres)}")

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True,
                          export_normals=True, export_tangents=False, export_materials="EXPORT",
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                          export_animations=False)
