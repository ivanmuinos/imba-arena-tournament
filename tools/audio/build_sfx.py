#!/usr/bin/env python3
"""Builds assets/third_party/oga_sfx/*.wav from the CC0 OpenGameArt downloads (see SOURCE.txt there).
Usage: python3 tools/audio/build_sfx.py <download_dir> [clip ...]   (the directory holding the unpacked packs, see SOURCES
below; with clip names, only those are built)
Each clip is trimmed, band-limited (no harsh highs), faded, mono, and normalised to a mean level of -22 dB (peak <= -3 dB),
which keeps every effect within ~7 dB of the Kenney UI clicks (-14.6 dB mean)."""
import os, subprocess, sys, tempfile, re

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-501/dl/z"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "third_party", "oga_sfx")
R80 = "x_80-CC0-RPG-SFX_0/"
# name -> (source file relative to SRC, max seconds, start seconds)
CLIPS = {
    # fire
    "fire_cast_1": (R80 + "spell_fire_06.ogg", 0.9, 0), "fire_cast_2": (R80 + "spell_fire_07.ogg", 0.65, 0),
    "fire_whoosh": ("flame.ogg", 0.45, 0),
    "fire_big_1": (R80 + "spell_fire_03.ogg", 1.6, 0), "fire_big_2": (R80 + "spell_fire_05.ogg", 1.2, 0),
    "fire_hit_1": (R80 + "spell_fire_01.ogg", 0.8, 0), "fire_hit_2": (R80 + "spell_fire_02.ogg", 0.8, 0),
    # frost
    "frost_cast": ("x_icespells/ice.wav", 0.9, 0), "frost_crack_1": ("x_icespells/coldsnap.wav", 1.1, 0.2),
    "frost_crack_2": ("freeze.wav", 1.2, 0), "frost_big": ("freeze.wav", 1.8, 0),
    # arcane
    "arc_1": ("magical_1.ogg", 1.3, 0), "arc_2": ("magical_2.ogg", 1.2, 0), "arc_3": ("magical_3.ogg", 1.3, 0),
    "arc_4": ("magical_4.ogg", 1.4, 0), "arc_5": ("magical_5_1.ogg", 1.2, 0), "arc_6": ("magical_6.ogg", 1.0, 0), "arc_7": ("magical_7.ogg", 1.2, 0),
    # shadow
    "shadow_1": ("x_dark/dark_magic/fout-01.flac", 1.3, 0), "shadow_2": ("x_dark/dark_magic/fout-02.flac", 1.2, 0),
    "shadow_3": ("x_dark/dark_magic/fout-03.flac", 1.6, 0), "shadow_low": ("x_dark/dark_magic/fout-01.flac", 0.9, 1.2),
    # holy / healing
    "holy_1": ("x_curemagic/Cure2.wav", 1.1, 0), "holy_2": ("x_curemagic/Cure4.wav", 1.1, 0), "holy_3": ("x_curemagic/Cure5.wav", 1.2, 0),
    "holy_4": ("x_curemagic/Cure3.wav", 1.2, 0), "holy_choir": ("x_curemagic/Cure6.wav", 2.0, 0), "heal_1": ("x_curemagic/Cure1.wav", 1.4, 0),
    "heal_2": ("x_curemagic/Cure8.wav", 1.4, 0),
    # physical
    "swish_1": ("x_swish/swishes/swish-3.wav", 0.2, 0), "swish_2": ("x_swish/swishes/swish-7.wav", 0.2, 0), "swish_3": ("x_swish/swishes/swish-9.wav", 0.2, 0),
    "swish_4": ("x_swish/swishes/swish-5.wav", 0.2, 0), "whoosh_long": ("whoosh2_0.wav", 0.9, 0.3),
    "blade_1": (R80 + "blade_01.ogg", 0.4, 0), "blade_2": (R80 + "blade_02.ogg", 0.4, 0), "blade_3": (R80 + "blade_03.ogg", 0.4, 0),
    "metal_1": (R80 + "metal_01.ogg", 0.5, 0), "metal_2": (R80 + "metal_02.ogg", 0.5, 0), "metal_3": (R80 + "metal_03.ogg", 0.45, 0),
    "chain_1": (R80 + "chain_01.ogg", 0.5, 0),
    "stone_1": (R80 + "stones_01.ogg", 0.7, 0), "stone_2": (R80 + "stones_02.ogg", 0.7, 0), "earth_big": ("Earth%20Element%20Magic%20Spell_3.ogg", 1.6, 0),
    "wood_1": (R80 + "wood_01.ogg", 0.4, 0), "death_1": (R80 + "creature_die_01.ogg", 1.0, 0),
    # movement and round cues (footsteps on stone, arena gong, brass win jingle)
    "step_1": ("x_steps/stone01.ogg", 0.29, 0), "step_2": ("x_sfx_100_v2/sfx100v2_footstep_01.ogg", 0.4, 0),
    "step_3": ("x_sfx_100_v2/sfx100v2_footstep_02.ogg", 0.35, 0),
    "gong_1": ("x_100-CC0-SFX_0/gong_01.ogg", 1.42, 0), "gong_2": ("x_100-CC0-SFX_0/gong_02.ogg", 1.19, 0),
    "win_brass": ("x_winjingle/WinBrass.ogg", 3.78, 0),
}
# amb_rumble.ogg (the arena's ambience bed) is x_sfx_100_v2/sfx100v2_loop_ambient_03.ogg copied unmodified: trimming or
# fading it would break the loop.


def run(*a):
    return subprocess.run(a, capture_output=True, text=True)


def build(name, src, dur, start):
    path = os.path.join(SRC, src.replace("%20", " ")) if not os.path.exists(os.path.join(SRC, src)) else os.path.join(SRC, src)
    fade = min(0.12, dur * 0.3)
    base = f"atrim=start={start}:duration={dur},asetpts=PTS-STARTPTS,highpass=f=60,lowpass=f=9000,afade=t=in:d=0.004,afade=t=out:st={max(0, dur - fade)}:d={fade}"
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "a.wav")
        r = run("ffmpeg", "-y", "-v", "error", "-i", path, "-ac", "1", "-ar", "44100", "-af", base, tmp)
        if r.returncode: raise SystemExit(f"{name}: {r.stderr}")
        v = run("ffmpeg", "-nostats", "-i", tmp, "-af", "volumedetect", "-f", "null", "-").stderr
        mean = float(re.search(r"mean_volume: (-?[\d.]+)", v).group(1))
        peak = float(re.search(r"max_volume: (-?[\d.]+)", v).group(1))
        gain = min(-22.0 - mean, -3.0 - peak)  # never above the peak ceiling
        out = os.path.join(OUT, name + ".wav")
        r = run("ffmpeg", "-y", "-v", "error", "-i", tmp, "-af", f"volume={gain}dB", "-c:a", "pcm_s16le", out)
        if r.returncode: raise SystemExit(f"{name}: {r.stderr}")
        return mean + gain, peak + gain


os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[2:]
for n, (s, d, st) in CLIPS.items():
    if ONLY and n not in ONLY:
        continue
    m, p = build(n, s, d, st)
    print(f"{n:14s} mean {m:6.1f} dB  peak {p:5.1f} dB")
