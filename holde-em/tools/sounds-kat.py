#!/usr/bin/env python3
"""Pin the vendored casino-audio WAVs against the stack's sound wiring.

v0.15.0 vendors Kenney "Casino Audio" (CC0) as WAVs in assets/sounds; the stack
lists them in kHeSoundFiles, imports each as an audioClip (heSndTryInit), and maps
game moments to files in heSndFilesFor. None of that is runnable headless, so this
KAT pins everything that IS checkable as data:

  1. every file in kHeSoundFiles exists in assets/sounds
  2. every vendored .wav is in kHeSoundFiles (no orphan drift, either direction)
  3. each WAV is engine-friendly: RIFF/WAVE, PCM (fmt 1), 16-bit, mono, 44100 Hz,
     a sane duration (0.05..10 s), nonzero audio payload
  4. the heSndFilesFor mapping (mirrored here) references only listed files, and
     every listed file is reachable from some kind (nothing vendored but unmapped)

A wrong file name silently never plays (heSndPlay guards it), which no other gate
would ever notice -- this closes that gap the way atlas-kat does for card frames.

Pure stdlib (wave/struct); no engine, no deps.
"""
import re
import sys
import wave
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOUNDS = ROOT / "assets" / "sounds"
STACK = ROOT / "src" / "holdem.livecodescript"

# mirror of heSndFilesFor (keep in lockstep with the stack)
KIND_MAP = {
    "shuffle": ["cardShuffle.wav"],
    "deal": ["cardSlide1.wav", "cardSlide2.wav"],
    "board": ["cardPlace1.wav", "cardPlace2.wav"],
    "fold": ["cardShove1.wav"],
    "check": ["chipLay1.wav"],
    "chips": ["chipsHandle1.wav", "chipsHandle2.wav"],
    "allin": ["chipsCollide1.wav"],
    "win": ["chipsStack1.wav"],
}


def stack_constant(name):
    """read `constant <name> = "..."` from the stack source (pin the exact value
    the stack uses -- no hardcoded copy to drift)."""
    m = re.search(r'constant\s+' + re.escape(name) + r'\s*=\s*"([^"]*)"', STACK.read_text())
    return m.group(1) if m else None


def main():
    fails = 0

    listed = stack_constant("kHeSoundFiles")
    if listed is None:
        print("FAILED -- kHeSoundFiles constant not found in the stack")
        return 1
    listed = [f.strip() for f in listed.split(",") if f.strip()]

    # 1. every listed file exists on disk
    for name in listed:
        if not (SOUNDS / name).exists():
            print("FAIL  kHeSoundFiles lists '%s' but assets/sounds has no such file" % name)
            fails += 1

    # 2. no orphan .wav on disk that the stack does not know about
    on_disk = sorted(p.name for p in SOUNDS.glob("*.wav"))
    for name in on_disk:
        if name not in listed:
            print("FAIL  assets/sounds/%s is not in kHeSoundFiles (orphan drift)" % name)
            fails += 1

    # 3. each WAV is engine-friendly
    for name in listed:
        path = SOUNDS / name
        if not path.exists():
            continue  # already failed above
        try:
            with wave.open(str(path), "rb") as w:
                ch, width, rate, frames = (w.getnchannels(), w.getsampwidth(),
                                           w.getframerate(), w.getnframes())
        except wave.Error as e:
            print("FAIL  %s is not a readable PCM WAV (%s)" % (name, e))
            fails += 1
            continue
        dur = frames / float(rate) if rate else 0
        if ch != 1:
            print("FAIL  %s has %d channels (want mono)" % (name, ch))
            fails += 1
        if width != 2:
            print("FAIL  %s is %d-byte samples (want 16-bit PCM)" % (name, width * 8))
            fails += 1
        if rate != 44100:
            print("FAIL  %s is %d Hz (want 44100)" % (name, rate))
            fails += 1
        if not (0.05 <= dur <= 10.0):
            print("FAIL  %s duration %.2fs is out of the sane 0.05..10s range" % (name, dur))
            fails += 1

    # 4. the kind mapping only uses listed files, and every listed file is mapped
    mapped = set()
    for kind, files in KIND_MAP.items():
        for name in files:
            mapped.add(name)
            if name not in listed:
                print("FAIL  heSndFilesFor('%s') -> '%s' is not in kHeSoundFiles" % (kind, name))
                fails += 1
    for name in listed:
        if name not in mapped:
            print("FAIL  '%s' is vendored + listed but no sound kind ever plays it" % name)
            fails += 1

    print()
    if fails:
        print("FAILED -- %d sound-pack problem(s)." % fails)
        return 1
    print("All %d vendored WAVs are listed, engine-friendly (PCM16 mono 44100), "
          "and reachable from the %d sound kinds." % (len(listed), len(KIND_MAP)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
