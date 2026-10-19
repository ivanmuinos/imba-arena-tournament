"""Quaternius CC0 packs (assets/third_party/quaternius_animals/SOURCE.txt) -> companion .glb files.
Run: blender -b --python tools/blender/convert_quaternius.py -- "<Animal Pack Vol.2 folder>" "<Animated Monster Pack folder>"
Each listed .blend becomes assets/third_party/quaternius_animals/<name>.glb with every action as its own animation."""
import os, sys
import bpy

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "third_party", "quaternius_animals"))
WANTED = {"Wolf", "Cat", "Eagle", "Dragon", "Cow"}


def convert(blend):
    name = os.path.splitext(os.path.basename(blend))[0]
    bpy.ops.wm.open_mainfile(filepath=blend)
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, name.lower() + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_animations=True,
        export_animation_mode="ACTIONS", export_skins=True, export_yup=True, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_extras=False)
    print("exported", path, [a.name for a in bpy.data.actions])


if __name__ == "__main__":
    folders = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not folders:
        sys.exit("usage: blender -b --python convert_quaternius.py -- <pack folder> [<pack folder> ...]")
    os.makedirs(OUT, exist_ok=True)
    for folder in folders:
        for sub in ("Blends", "Blend"):
            d = os.path.join(folder, sub)
            if os.path.isdir(d):
                for f in sorted(os.listdir(d)):
                    if f.endswith(".blend") and f[:-6] in WANTED:
                        convert(os.path.join(d, f))
