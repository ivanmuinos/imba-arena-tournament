"""Builds assets/models/<class>.glb for every class. Run: blender -b --python tools/blender/build_characters.py [-- mage priest ...]"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import importlib
from lib import *
import char_common
import classes_a
import classes_b

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")
BUILDERS = {"mage": (classes_a.build_mage, {"robe": True}), "priest": (classes_a.build_priest, {"robe": True}),
            "hunter": (classes_b.build_hunter, {"ranged": True}), "warrior": (classes_b.build_warrior, {}), "rogue": (classes_b.build_rogue, {})}


def build(cls):
    reset()
    rig = char_common.make_rig(cls.capitalize() + "Rig")
    fn, style = BUILDERS[cls]
    parts = fn(rig)
    from dress import finish
    finish(rig, parts)
    char_common.animations(rig, style)
    os.makedirs(OUT, exist_ok=True)
    export_glb(os.path.abspath(os.path.join(OUT, cls + ".glb")))
    print("built", cls, len(parts), "parts")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for c in (argv or list(BUILDERS)):
        build(c)
