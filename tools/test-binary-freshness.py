#!/usr/bin/env python3
"""test-binary-freshness.py - prove the ABI decoders in check-binary-freshness.py
read exactly what the committed code returns, and refuse everything else.

WHY IT EXISTS. The gate's fourth leg DECODES `x_abi_version()`'s return value
from each committed library's machine code, and on 2026-09-25 it learned a
second PE shape: the frame MSVC keeps around the shim's exception-firewall
try/catch (`decode_msvc_guarded`), which turned the six Windows ABI SKIPs of
torrentxt, enetxt and datachannelxt into six decoded constants. A decoder that
reads more shapes is a decoder that can read a WRONG number with confidence,
which the gate's own header calls worse than no number. The gate cannot tell
you it has started doing that; its summary line would still say OK. Hence this
file, run before the gate (root CLAUDE.md, "fixture before gate").

WHAT IT PROVES, in five legs:

  1. RECORDED VECTORS. The six guarded functions' bytes (and, for x64, the
     __security_check_cookie each one calls) are recorded here from the
     2026-09-12 DLLs (release run 34657390798), with the section ranges and
     load-config cookie the decoder checks them against. They decode to 11, 2
     and 1. Recorded, not read from the tree, so a future rebuild that moves
     every address cannot silently retire the mutation battery below: leg 4
     repeats it on whatever the tree holds.
  2. NAMED MUTANTS on those vectors, each refused for its own stated reason:
     one fixed byte changed; the `mov`'s immediate sent to ecx instead of eax;
     eax overwritten after the `mov`; the x64 jmp no longer skipping the catch
     continuation (the CPU then returns 0 or -6: leg 5 executes it); the call
     target moved; a __security_check_cookie comparing another address or
     returning differently; the cookie slot outside the frame; the frame
     released differently than allocated; the cookie not the load config's; no
     cookie on record; the EH handler outside executable code.
  3. EVERY BYTE FLIPPED. For each byte of each recorded shape, three flips
     (^0x01, ^0x80, ^0xFF): a value byte must decode to the flipped value; a
     FREE byte (the x86 EH handler, the x64 catch value, the check's failure
     jmp - the gate's header says why each is off the returning path) must
     either be refused or leave the value unchanged; every other byte must be
     refused. The byte classes come from this file's OWN layout arithmetic,
     not from the gate's shape tables, and are held against the recorded bytes.
  4. THE LIVE TREE, through the gate's own functions: every committed library
     (ELF, PE, both slices of each fat dylib) decodes to its header's define
     wherever it decodes; every library the leaf decoder read before this
     change reads the same value through `decode_abi`; the gate's check_member
     skips exactly the libraries that do not decode and counts exactly those
     that do; a guarded DLL whose value disagrees with its header is a gate
     FAILURE, not a skip; the load-config refusals on a real image; and the
     leg-3 sweep again on each committed guarded function's real bytes.
     Because the gate may SKIP what it cannot read, a reader defect that made
     every guarded DLL unreadable would pass all of that; so while a committed
     DLL is still the RECORDED build (the same bytes at the same VA), it must
     read back every recorded fact - cookie VA, section classes, value. A
     rebuild lapses that anchor with a NOTE, never a failure: a release must
     not be blocked by a recording.
  5. INDEPENDENT READINGS, where this host allows (each prints a SKIP naming
     why when it does not): GNU objdump's disassembly must agree with the
     decoder's instruction boundaries, mnemonics and value; and on an x86-64
     Linux host each x64 guarded function is EXECUTED from a mapped copy of
     its DLL's sections and must return the decoded value, while its `eb 00`
     mutant must return the catch value - the refused mutant is a different
     function, not a harmless variant. (The x86 DLLs cannot execute here: that
     would need a 32-bit code segment and FS:[0], so objdump is their only
     independent reader.)

None of this is an engine result: it settles what the committed bytes do on a
CPU, which is what the gate claims, and nothing about an OXT engine.

USAGE
    python3 tools/test-binary-freshness.py
"""

import importlib.util
import os
import platform
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TAG = "test-binary-freshness"

spec = importlib.util.spec_from_file_location(
    "cbf", os.path.join(HERE, "check-binary-freshness.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

FAILURES = []
SKIPS = []


def check(ok, label):
    if not ok:
        FAILURES.append(label)
    return ok


# --------------------------------------------------------------------------
# Leg 1: the recorded vectors.
# --------------------------------------------------------------------------

# Recorded 2026-09-25 from the committed 2026-09-12 DLLs by this file's
# author, through the gate's PE reader, and confirmed instruction by
# instruction against `objdump -d -M intel` (binutils 2.42). `exec` and
# `write` are the [start, end) VA ranges of the executable and writable
# sections the decoder asks about; `cookie` is the load config's
# SecurityCookie.
VECTORS = [
    {"label": "torrentxt x86-win32", "machine": "x86", "value": 11,
     "fn_va": 0x1006e6f0,
     "fn": "55 8b ec 6a ff 68 50 46 68 10 64 a1 00 00 00 00 50 a1 00 ff 8a "
           "10 33 c5 50 8d 45 f4 64 a3 00 00 00 00 b8 0b 00 00 00 8b 4d f4 "
           "64 89 0d 00 00 00 00 59 8b e5 5d c3",
     "cookie": 0x108aff00,
     "exec": [(0x10001000, 0x106c0a00)],
     "write": [(0x108aa000, 0x108e8024), (0x108e9000, 0x108e9200)]},
    {"label": "torrentxt x86_64-win32", "machine": "x64", "value": 11,
     "fn_va": 0x18013ae20,
     "fn": "48 81 ec 88 00 00 00 48 8b 05 92 7f 9c 00 48 33 c4 48 89 44 24 "
           "70 b8 0b 00 00 00 eb 02 33 c0 48 8b 4c 24 70 48 33 cc e8 14 e7 "
           "6b 00 48 81 c4 88 00 00 00 c3",
     "check_va": 0x1807f9560,
     "check": "48 3b 0d 59 98 30 00 75 10 48 c1 c1 10 66 f7 c1 ff ff 75 01 "
              "c3 48 c1 c9 10 e9 f2 fc ff ff",
     "cookie": 0x180b02dc0,
     "exec": [(0x180001000, 0x180854400)],
     "write": [(0x180afa000, 0x180b4268c), (0x180b9c000, 0x180b9c200)]},
    {"label": "enetxt x86-win32", "machine": "x86", "value": 2,
     "fn_va": 0x10002e10,
     "fn": "55 8b ec 6a ff 68 30 be 00 10 64 a1 00 00 00 00 50 a1 40 00 01 "
           "10 33 c5 50 8d 45 f4 64 a3 00 00 00 00 b8 02 00 00 00 8b 4d f4 "
           "64 89 0d 00 00 00 00 59 8b e5 5d c3",
     "cookie": 0x10010040,
     "exec": [(0x10001000, 0x1000c600)],
     "write": [(0x10010000, 0x1001021c)]},
    {"label": "enetxt x86_64-win32", "machine": "x64", "value": 2,
     "fn_va": 0x1800032e0,
     "fn": "48 83 ec 68 48 8b 05 55 dd 00 00 48 33 c4 48 89 44 24 50 b8 02 "
           "00 00 00 eb 05 b8 fa ff ff ff 48 8b 4c 24 50 48 33 cc e8 94 88 "
           "00 00 48 83 c4 68 c3",
     "check_va": 0x18000bba0,
     "check": "48 3b 0d 99 54 00 00 75 10 48 c1 c1 10 66 f7 c1 ff ff 75 01 "
              "c3 48 c1 c9 10 e9 52 fd ff ff",
     "cookie": 0x180011040,
     "exec": [(0x180001000, 0x18000d000)],
     "write": [(0x180011000, 0x1800112e0)]},
    {"label": "datachannelxt x86-win32", "machine": "x86", "value": 1,
     "fn_va": 0x10053dd0,
     "fn": "55 8b ec 6a ff 68 d0 b3 34 10 64 a1 00 00 00 00 50 a1 00 96 43 "
           "10 33 c5 50 8d 45 f4 64 a3 00 00 00 00 b8 01 00 00 00 8b 4d f4 "
           "64 89 0d 00 00 00 00 59 8b e5 5d c3",
     "cookie": 0x10439600,
     "exec": [(0x10001000, 0x10357200)],
     "write": [(0x10434000, 0x10443714), (0x10444000, 0x10444200)]},
    {"label": "datachannelxt x86_64-win32", "machine": "x64", "value": 1,
     "fn_va": 0x1801183e0,
     "fn": "48 81 ec 88 00 00 00 48 8b 05 92 8a 50 00 48 33 c4 48 89 44 24 "
           "70 b8 01 00 00 00 eb 02 33 c0 48 8b 4c 24 70 48 33 cc e8 c4 3b "
           "34 00 48 81 c4 88 00 00 00 c3",
     "check_va": 0x18045bfd0,
     "check": "48 3b 0d a9 4e 1c 00 75 10 48 c1 c1 10 66 f7 c1 ff ff 75 01 "
              "c3 48 c1 c9 10 e9 52 fd ff ff",
     "cookie": 0x180620e80,
     "exec": [(0x180001000, 0x18049d200)],
     "write": [(0x180619000, 0x18062daac), (0x180664000, 0x180664200)]},
]

# The shapes the gate decoded BEFORE the guarded one, one recorded vector per
# class, all from committed libraries on 2026-09-25: (label, decoder, hex,
# value). "Still decodes everything it decoded before" is leg 4's job on the
# live tree; these pin the classes themselves.
LEAF_VECTORS = [
    ("mov eax ; ret (x86 ELF, MinGW and MSVC leaf DLLs)", "x86",
     "b8 0a 00 00 00 c3", 10),
    ("endbr64 ; mov eax ; ret (x86_64 ELF)", "x86",
     "f3 0f 1e fa b8 02 00 00 00 c3", 2),
    ("push rbp ; mov rbp,rsp ; mov eax ; pop rbp ; ret (mac x86_64)", "x86",
     "55 48 89 e5 b8 0b 00 00 00 5d c3", 11),
    ("MOVZ w0 ; RET (mac arm64)", "arm64", "20 00 80 52 c0 03 5f d6", 1),
]


class VectorMemory:
    """The five-member view decode_msvc_guarded reads (the same one PeImage
    provides), over recorded chunks instead of a file."""

    def __init__(self, vec):
        self.machine = vec["machine"]
        self.chunks = {vec["fn_va"]: bytearray.fromhex(vec["fn"])}
        if "check" in vec:
            self.chunks[vec["check_va"]] = bytearray.fromhex(vec["check"])
        self.cookie = vec["cookie"]
        self.exec_ranges = vec["exec"]
        self.write_ranges = vec["write"]

    def read_va(self, va, count):
        for base, blob in self.chunks.items():
            if base <= va < base + len(blob):
                return bytes(blob[va - base:va - base + count])
        return b""

    def is_exec_va(self, va):
        return any(lo <= va < hi for lo, hi in self.exec_ranges)

    def is_writable_va(self, va):
        return any(lo <= va < hi for lo, hi in self.write_ranges)

    def security_cookie_va(self):
        if self.cookie is None:
            return None, "the image has no load-config directory"
        return self.cookie, None


# --------------------------------------------------------------------------
# The byte classes, from this file's own reading of the two shapes. Offsets
# are into the function (or the check), computed from instruction lengths
# written out here, NOT taken from the gate's MSVC_GUARDED_* tables - so a
# table that declared an operand in the wrong place would disagree with this.
# --------------------------------------------------------------------------

def layout_x86():
    # push ebp(1) mov ebp,esp(2) push -1(2) | push imm32 at +5: handler +6..+9
    # mov eax,fs:0(6) push(1) mov eax,[m32](5) xor(2) push(1) lea(3)
    # mov fs:0,eax(6) = +34 | b8 at +34: value +35..+38 | the rest is 15
    # bytes: mov ecx(3) mov fs:0,ecx(7) pop(1) mov esp(2) pop(1) ret(1).
    return {"length": 54, "value": (35, 4), "free": [(6, 4)],
            "opcode_before_value": 34}


def layout_x64(frame32, cont5):
    f = 4 if frame32 else 1
    c = 5 if cont5 else 2
    value = 3 + f + 7 + 3 + 5 + 1           # sub, mov rax, xor, mov [rsp]
    cont = value + 4 + 2                    # past the imm32 and the jmp
    call = cont + c + 5 + 3                 # past mov rcx and xor rcx
    # skip_at is the jmp's rel8 byte; slot and reload are the disp8 bytes of
    # the cookie's store and reload.
    return {"length": call + 5 + 3 + f + 1, "value": (value, 4),
            "free": [(cont + 1, 4)] if cont5 else [],
            "opcode_before_value": value - 1, "skip_at": cont - 1,
            "slot": value - 2, "reload": call - 4,
            "call_rel": call + 1, "call_next": call + 5}


def layout_check():
    # cmp(7) jne(2) rol(4) test(5) jne(2) ret(1) ror(4) | e9 at +25, its
    # rel32 +26..+29 is the failure jmp's target: FREE.
    return {"length": 30, "free": [(26, 4)]}


def layout_for(fn_bytes, machine):
    """The layout for real or recorded bytes, or None for a variant this
    file does not know (the caller then has nothing to classify)."""
    if machine == "x86":
        return layout_x86()
    if bytes(fn_bytes[:3]) == b"\x48\x83\xec":
        frame32 = False
    elif bytes(fn_bytes[:3]) == b"\x48\x81\xec":
        frame32 = True
    else:
        return None
    probe = layout_x64(frame32, False)
    cont = probe["skip_at"] + 1
    return layout_x64(frame32, fn_bytes[cont] == 0xB8)


def in_spans(offset, spans):
    return any(lo <= offset < lo + n for lo, n in spans)


def decode(mem, fn_va):
    return GATE.decode_msvc_guarded(mem, fn_va)


# --------------------------------------------------------------------------
# Leg 2: named mutants.
# --------------------------------------------------------------------------

def mutant(vec, fn=None, check_=None, cookie="keep", exec_=None):
    """A VectorMemory for `vec` with edits: fn/check are {offset: byte}."""
    mem = VectorMemory(vec)
    for off, byte in (fn or {}).items():
        mem.chunks[vec["fn_va"]][off] = byte
    for off, byte in (check_ or {}).items():
        mem.chunks[vec["check_va"]][off] = byte
    if cookie != "keep":
        mem.cookie = cookie
    if exec_ is not None:
        mem.exec_ranges = exec_
    return mem


def rel32_edit(offset, value):
    return {offset + i: b for i, b in enumerate(struct.pack("<i", value))}


def named_mutants():
    by_label = {v["label"]: v for v in VECTORS}
    x86 = by_label["torrentxt x86-win32"]
    x64 = by_label["torrentxt x86_64-win32"]         # imm32 frame, xor cont
    x64b = by_label["enetxt x86_64-win32"]           # imm8 frame, mov cont
    lay = layout_x64(True, False)
    layb = layout_x64(False, True)
    call_rel = struct.unpack_from("<i", bytes.fromhex(x64["fn"]),
                                  lay["call_rel"])[0]
    cases = [
        # -- one fixed byte changed
        ("x86: EH state push -2 instead of -1 (one fixed byte)", x86,
         mutant(x86, fn={4: 0xFE}), "expected `6a ff`"),
        ("x64: xor rcx, rsp becomes xor rcx, rcx (one fixed byte)", x64,
         mutant(x64, fn={lay["call_rel"] - 2: 0xC9}), "expected `48 33 cc`"),
        # -- the immediate does not go to eax, or does not stay there
        ("x86: mov ecx, imm32 where mov eax, imm32 stood", x86,
         mutant(x86, fn={34: 0xB9}), "expected `b8`"),
        ("x64: mov ecx, imm32 where mov eax, imm32 stood", x64,
         mutant(x64, fn={lay["opcode_before_value"]: 0xB9}), "expected `b8`"),
        ("x86: eax reloaded from [ebp-0Ch] after the mov (8b 45 f4)", x86,
         mutant(x86, fn={40: 0x45}), "expected `8b 4d f4`"),
        ("x64: jmp +0 falls into the catch continuation (returns 0)", x64,
         mutant(x64, fn={lay["skip_at"]: 0x00}), "jmp skips 0 byte"),
        ("x64: jmp +0 falls into mov eax, -6 (enetxt's catch value)", x64b,
         mutant(x64b, fn={layb["skip_at"]: 0x00}), "jmp skips 0 byte"),
        # -- the call target
        ("x64: call target moved one byte on", x64,
         mutant(x64, fn=rel32_edit(lay["call_rel"], call_rel + 1)),
         "not __security_check_cookie's shape"),
        ("x64: call target moved into the function itself", x64,
         mutant(x64, fn=rel32_edit(lay["call_rel"], -lay["call_next"])),
         "not __security_check_cookie's shape"),
        ("x64: the check compares a different address", x64,
         mutant(x64, check_={3: 0x5A}), "compares against"),
        ("x64: the check's ret becomes retf (cb)", x64,
         mutant(x64, check_={20: 0xCB}), "expected `c3`"),
        ("x64: the check's jne +0x10 becomes jne +0x0f", x64,
         mutant(x64, check_={8: 0x0F}), "expected `75 10`"),
        # -- the frame
        ("x64: cookie reloaded from a different slot", x64,
         mutant(x64, fn={lay["reload"]: 0x68}), "reloaded from"),
        ("x64: cookie slot on the return address (store and reload +0x68)",
         x64b, mutant(x64b, fn={layb["slot"]: 0x68, layb["reload"]: 0x68}),
         "return address"),
        ("x64: epilogue releases 0x78, prologue allocates 0x88", x64,
         mutant(x64, fn={lay["length"] - 5: 0x78}),
         "releases a different frame"),
        ("x64 (imm8): a negative frame, sub rsp, -0x18", x64b,
         mutant(x64b, fn={3: 0xE8, 47: 0xE8}), "negative immediate"),
        # -- the cookie and the image's records
        ("x86: cookie read from 4 bytes past SecurityCookie", x86,
         mutant(x86, fn={18: 0x04}), "not the load config's"),
        ("x64: cookie rip-relative displacement off by 8", x64,
         mutant(x64, fn={10: 0x9a}), "not the load config's"),
        ("x86: the image records no /GS cookie", x86,
         mutant(x86, cookie=None), "no load-config"),
        ("x64: the image records no /GS cookie", x64,
         mutant(x64, cookie=None), "no load-config"),
        ("x64: SecurityCookie is not in a writable section", x64,
         mutant(x64, cookie=0x180001000), "not in a writable section"),
        ("x86: the EH handler outside every executable section", x86,
         mutant(x86, exec_=[(0x10001000, 0x10600000)]), "EH handler"),
        ("x64: the call target outside every executable section", x64,
         mutant(x64, exec_=[(0x180001000, 0x180200000)]),
         "not in an executable section"),
    ]
    return cases


# --------------------------------------------------------------------------
# Leg 3: every byte flipped.
# --------------------------------------------------------------------------

FLIPS = (0x01, 0x80, 0xFF)


def sweep(mem, fn_va, fn_blob, check_va, check_blob, value, label):
    """Flip every byte of the function (and its check); see leg 3 above.

    `fn_blob` / `check_blob` are the MUTABLE buffers `mem` reads through, so
    each flip is one in-place write and one restore. Returns the tallies."""
    layout = layout_for(fn_blob, mem.machine)
    if not check(layout is not None, f"{label}: no layout for these bytes"):
        return None
    tallies = {"refused": 0, "value": 0, "free": 0, "free_refused": 0,
               "bytes": 0}
    # The layout is held against the bytes before anything relies on it.
    check(layout["length"] <= len(fn_blob)
          and fn_blob[layout["opcode_before_value"]] == 0xB8
          and struct.unpack_from("<I", bytes(fn_blob), layout["value"][0])[0]
          == value,
          f"{label}: this file's layout does not fit the bytes")
    spans = [(fn_blob, fn_va, layout, "fn")]
    if check_blob is not None:
        spans.append((check_blob, check_va, layout_check(), "check"))
    for blob, _base, lay, part in spans:
        for off in range(lay["length"]):
            tallies["bytes"] += 1
            for flip in FLIPS:
                old = blob[off]
                blob[off] = old ^ flip
                got, why = decode(mem, fn_va)
                if part == "fn" and in_spans(off, [lay["value"]]):
                    want = struct.unpack_from("<I", bytes(blob),
                                              lay["value"][0])[0]
                    if check(got == want, f"{label}: value byte +{off:#x} "
                             f"^{flip:#x} read {got}, not {want} ({why})"):
                        tallies["value"] += 1
                elif in_spans(off, lay["free"]):
                    if check(got in (None, value), f"{label}: free byte "
                             f"{part}+{off:#x} ^{flip:#x} changed the value "
                             f"to {got}"):
                        tallies["free"] += 1
                        if got is None:
                            tallies["free_refused"] += 1
                else:
                    if check(got is None, f"{label}: {part}+{off:#x} "
                             f"^{flip:#x} ({old:02x} -> {old ^ flip:02x}) "
                             f"was ACCEPTED as {got} - the decoder took a "
                             f"deviation"):
                        tallies["refused"] += 1
                blob[off] = old
    got, _ = decode(mem, fn_va)
    check(got == value, f"{label}: the sweep did not restore the bytes")
    return tallies


# --------------------------------------------------------------------------
# Leg 4 helpers: the live tree.
# --------------------------------------------------------------------------

def committed_libraries():
    """(member, platform, fmt, path) for every committed ELF and PE."""
    out = []
    for member in GATE.MEMBERS:
        for plat, (suffix, fmt) in sorted(GATE.PLATFORMS.items()):
            path = os.path.join(ROOT, member["name"], "src", "code", plat,
                                f"{member['lib']}.{suffix}")
            # The fat dylibs are per-slice pairs, walked separately in main.
            if fmt != "macho" and os.path.isfile(path):
                out.append((member, plat, fmt, path))
    return out


def objdump_listing(path, lo, hi):
    tool = shutil.which("objdump")
    out = subprocess.run([tool, "-d", "-M", "intel",
                          f"--start-address={lo:#x}", f"--stop-address={hi:#x}",
                          path], capture_output=True, text=True,
                         timeout=120).stdout
    rows = []
    for line in out.splitlines():
        m = re.match(r"^\s*([0-9a-f]+):\t([0-9a-f ]+?)\s*(?:\t(\S+)\s*(.*))?$",
                     line)
        if not m:
            continue
        nbytes = len(m.group(2).split())
        if m.group(3) is None:            # a continuation line of bytes
            if rows:
                rows[-1][1] += nbytes
            continue
        rows.append([int(m.group(1), 16), nbytes, m.group(3),
                     m.group(4).strip()])
    return rows


def objdump_supports_pe():
    tool = shutil.which("objdump")
    if tool is None:
        return "objdump is not installed"
    try:
        targets = subprocess.run([tool, "-i"], capture_output=True, text=True,
                                 timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"objdump -i did not run ({exc})"
    missing = [t for t in ("pei-i386", "pei-x86-64") if t not in targets]
    return f"this objdump lacks {missing}" if missing else None


# The x64 execution leg's child. It maps every section of the DLL at its RVA
# inside one anonymous read-write-execute mapping (no imports, no
# relocations: the guarded x64 path is RIP-relative throughout and calls
# nothing outside the image), optionally patches one byte, and calls the
# function with no arguments. A child process, so a crash is a report.
EXEC_CHILD = r"""
import ctypes, mmap, struct, sys
path, rva, patch_off, patch_byte = sys.argv[1], int(sys.argv[2], 16), \
    int(sys.argv[3]), int(sys.argv[4])
data = open(path, "rb").read()
coff = struct.unpack_from("<I", data, 0x3c)[0] + 4
nsec, optsz = struct.unpack_from("<HH", data, coff + 2)[0], \
    struct.unpack_from("<H", data, coff + 16)[0]
opt = coff + 20
size = struct.unpack_from("<I", data, opt + 56)[0]
buf = mmap.mmap(-1, size, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS,
                prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
for i in range(nsec):
    b = opt + optsz + 40 * i
    vsize, va, rsize, rptr = struct.unpack_from("<IIII", data, b + 8)
    n = min(rsize, vsize) if vsize else rsize
    buf[va:va + n] = data[rptr:rptr + n]
if patch_off >= 0:
    buf[rva + patch_off] = patch_byte
base = ctypes.addressof(ctypes.c_char.from_buffer(buf))
print(ctypes.CFUNCTYPE(ctypes.c_int)(base + rva)())
"""


def execute_x64(path, rva, patch=None):
    """(int, None) from running the function natively, or (None, why)."""
    off, byte = patch if patch else (-1, 0)
    try:
        done = subprocess.run([sys.executable, "-c", EXEC_CHILD, path,
                               f"{rva:x}", str(off), str(byte)],
                              capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"the child did not complete ({exc})"
    if done.returncode != 0:
        tail = (done.stderr.strip().splitlines() or
                [f"exit status {done.returncode}, no diagnostic"])[-1]
        return None, f"the child failed ({tail})"
    try:
        return int(done.stdout.strip()), None
    except ValueError:
        return None, f"the child printed {done.stdout.strip()!r}"


def exec_host_reason():
    if not sys.platform.startswith("linux"):
        return f"the host is {sys.platform}, not Linux"
    if platform.machine() not in ("x86_64", "AMD64"):
        return f"the host CPU is {platform.machine()}, not x86-64"
    return None


# --------------------------------------------------------------------------

def main():
    # Leg 1 + the leaf classes.
    for vec in VECTORS:
        got, why = decode(VectorMemory(vec), vec["fn_va"])
        check(got == vec["value"],
              f"{vec['label']}: recorded vector decodes to {got}, not "
              f"{vec['value']} ({why})")
    for label, kind, hexs, value in LEAF_VECTORS:
        code = bytes.fromhex(hexs) + b"\xcc" * 16
        if kind == "arm64":
            got = GATE.decode_return_constant_arm64(code)
        else:
            got = GATE.decode_return_constant(code)
        check(got == value, f"leaf class {label}: decodes to {got}, not "
              f"{value}")
        # The guarded decoder must refuse a leaf outright: the gate tries the
        # leaf first, and this pins that the order is not what saves it.
        mem = VectorMemory({"machine": "x64", "fn_va": 0x1000, "fn": hexs,
                            "cookie": 0x9000, "exec": [(0x1000, 0x2000)],
                            "write": [(0x9000, 0xA000)]})
        check(decode(mem, 0x1000)[0] is None,
              f"leaf class {label}: the guarded decoder accepted a leaf")
    print(f"{TAG}: leg 1 - {len(VECTORS)} recorded guarded vectors and "
          f"{len(LEAF_VECTORS)} leaf classes decode to their recorded values")

    # Leg 2.
    cases = named_mutants()
    for label, vec, mem, reason in cases:
        got, why = decode(mem, vec["fn_va"])
        if check(got is None, f"MUTANT ACCEPTED: {label} -> {got}"):
            check(reason in (why or ""),
                  f"mutant {label}: refused, but for the wrong reason "
                  f"({why!r}; expected it to say {reason!r})")
    print(f"{TAG}: leg 2 - {len(cases)} named mutants, each refused for its "
          f"stated reason")

    # Leg 3, on the recorded vectors.
    total = {"refused": 0, "value": 0, "free": 0, "free_refused": 0,
             "bytes": 0}
    for vec in VECTORS:
        mem = VectorMemory(vec)
        fn_blob = mem.chunks[vec["fn_va"]]
        check_blob = mem.chunks.get(vec.get("check_va"))
        tallies = sweep(mem, vec["fn_va"], fn_blob, vec.get("check_va"),
                        check_blob, vec["value"], vec["label"])
        for key in total:
            total[key] += (tallies or {}).get(key, 0)
    print(f"{TAG}: leg 3 - {total['bytes']} recorded bytes x {len(FLIPS)} "
          f"flips: {total['refused']} refused, {total['value']} value flips "
          f"read back exactly, {total['free']} free-byte flips never changed "
          f"the value ({total['free_refused']} of them refused: an address "
          f"moved out of its section)")

    # Leg 4: the live tree through the gate's own functions.
    decoded_files, guarded_live = {}, []
    leaf_before, undecoded = 0, []
    for member, plat, fmt, path in committed_libraries():
        want = GATE.shim_abi(member["abi_header"], member["abi_define"])
        _exports, code_at = GATE.read_container(path, fmt)
        where = f"{member['name']}/src/code/{plat}"
        # This file's OWN expectation, from the two decoders called directly:
        # the leaf decoder (unchanged since the gate landed, so what it reads
        # is what the gate read before 2026-09-25), else, for a PE, the
        # guarded decoder. The gate's decode_abi must say exactly the same;
        # comparing decode_abi with itself would pass a gate whose wiring
        # never reached the guarded decoder at all (it did, as a mutant).
        before = GATE.decode_return_constant(code_at(member["abi_symbol"], 24))
        expect, expect_shape = before, "leaf"
        if before is None and fmt == "pe":
            fn_va = code_at.export_va(member["abi_symbol"])
            expect = (GATE.decode_msvc_guarded(code_at, fn_va)[0]
                      if fn_va is not None else None)
            expect_shape = "guarded"
        value, shape, why = GATE.decode_abi(fmt, code_at, member["abi_symbol"])
        if before is not None:
            leaf_before += 1
        if expect is None:
            expect_shape = None
        check(value == expect and shape == expect_shape,
              f"{where}: the decoders read {expect} ({expect_shape}) but the "
              f"gate's decode_abi says {value} ({shape}) - "
              f"{'a regression of a leaf read' if before is not None else 'the gate does not reach the decoder'}")
        if value is None:
            undecoded.append(f"{where} ({why})")
            continue
        decoded_files[path] = value
        check(value == want, f"{where}: decodes {value} but "
              f"{member['abi_define']} is {want}")
        if shape == "guarded":
            guarded_live.append((member, plat, path, code_at, value))
    for member in GATE.MEMBERS:
        path = os.path.join(ROOT, member["name"], "src", "code",
                            "universal-mac", f"{member['lib']}.dylib")
        if not os.path.isfile(path):
            continue
        want = GATE.shim_abi(member["abi_header"], member["abi_define"])
        for arch, _exports, code_at in GATE.read_macho_fat(path):
            code = code_at(member["abi_symbol"], 24)
            value = (GATE.decode_return_constant(code) if arch == "x86_64"
                     else GATE.decode_return_constant_arm64(code))
            if value is None:
                undecoded.append(f"{member['name']} mac {arch}")
                continue
            decoded_files[f"{path}:{arch}"] = value
            check(value == want, f"{member['name']} mac {arch}: decodes "
                  f"{value} but {member['abi_define']} is {want}")

    # The gate's wiring: check_member must skip exactly what does not decode
    # and count exactly what does. (The mac leg has its own stale-record
    # allowance; with MAC_KNOWN_STALE empty, it counts like the rest.)
    problems, skips, notes = [], [], []
    stats = {"libs": 0, "binds": 0, "distinct": 0, "abi": 0, "confirmed": 0,
             "mac": 0, "guarded": 0}
    for member in GATE.MEMBERS:
        GATE.check_member(member, problems, skips, notes, stats)
    abi_skips = [s for s in skips if "ABI pin" in s]
    # ABI problems only. The inventory, bind, source and closure legs are the
    # gate's own business on its own run, and one of them (a platform gained
    # ahead of its `ships` row) is legitimately tolerated there under
    # --installing, which this call does not pass: asserting "no problems"
    # here would fail the release job's post-install step on exactly the run
    # the gate lets through.
    abi_problems = [p for p in problems
                    if "_abi_version()" in p or "ABI DECODER" in p
                    or "DISAGREE about their own ABI" in p]
    check(not abi_problems, f"the gate reports ABI problems on the live "
          f"tree: {abi_problems[:3]}")
    check(stats["abi"] == len(decoded_files),
          f"the gate counted {stats['abi']} ABI decodes, this file "
          f"{len(decoded_files)}")
    check(stats["guarded"] == len(guarded_live),
          f"the gate counted {stats['guarded']} guarded decodes, this file "
          f"{len(guarded_live)}")
    check(len(abi_skips) == len(undecoded),
          f"the gate printed {len(abi_skips)} ABI-pin SKIPs for "
          f"{len(undecoded)} undecoded libraries: {abi_skips[:2]}")
    for _member, plat, path, _c, _v in guarded_live:
        rel = os.path.relpath(path, ROOT)
        check(not any(rel in s for s in abi_skips),
              f"{rel}: decoded here, but the gate SKIPs its ABI pin")

    # A guarded DLL whose value disagrees with its header is a FAILURE.
    if guarded_live:
        member, plat, path, code_at, value = guarded_live[0]
        fn_va = code_at.export_va(member["abi_symbol"])
        fn_off = code_at.rva_to_offset(fn_va - code_at.image_base)
        layout = layout_for(code_at.read_va(fn_va, GATE.GUARDED_READ),
                            code_at.machine)
        skewed = bytearray(code_at.data)
        struct.pack_into("<I", skewed, fn_off + layout["value"][0], value + 1)
        real_reader = GATE.read_container

        def skewed_reader(p, fmt, _path=path, _data=skewed):
            if p == _path:
                image = GATE.PeImage(_data)
                return image.exports, image
            return real_reader(p, fmt)

        GATE.read_container = skewed_reader
        try:
            problems, skips, notes = [], [], []
            stats = {"libs": 0, "binds": 0, "distinct": 0, "abi": 0,
                     "confirmed": 0, "mac": 0, "guarded": 0}
            GATE.check_member(member, problems, skips, notes, stats)
        finally:
            GATE.read_container = real_reader
        needle = (f"returns {value + 1} but {member['abi_header']} defines "
                  f"{member['abi_define']} {value}")
        check(any(needle in p for p in problems),
              f"{member['name']} {plat}: a guarded DLL answering "
              f"{value + 1} under a header saying {value} was not a gate "
              f"FAILURE (problems {problems[:2]}, skips "
              f"{[s for s in skips if 'ABI' in s][:2]})")

    # The recorded builds as an ANCHOR. Leg 4 above tolerates a library that
    # does not decode (the gate SKIPs it, by policy), so a PeImage defect that
    # made every guarded DLL undecodable - a wrong SecurityCookie offset, say
    # - would read as six SKIPs and pass here. It did, as a planted mutant.
    # So while a committed DLL still IS the recorded build (the same function
    # bytes at the same VA, and the same check bytes on x64), the live image
    # must yield the recorded facts exactly: cookie VA, section classes and
    # value. A rebuilt DLL lapses this anchor with a NOTE, never a failure: a
    # release that changes the bytes must not be blocked by a recording.
    anchored, lapsed = 0, []
    for vec in VECTORS:
        name, plat = vec["label"].split()
        member = next(m for m in GATE.MEMBERS if m["name"] == name)
        path = os.path.join(ROOT, name, "src", "code", plat,
                            f"{member['lib']}.dll")
        if not os.path.isfile(path):
            lapsed.append(f"{vec['label']} (no committed DLL)")
            continue
        _exports, image = GATE.read_pe(path)
        fn = bytes.fromhex(vec["fn"])
        same = (image.export_va(member["abi_symbol"]) == vec["fn_va"]
                and image.read_va(vec["fn_va"], len(fn)) == fn)
        if same and "check" in vec:
            chk = bytes.fromhex(vec["check"])
            same = image.read_va(vec["check_va"], len(chk)) == chk
        if not same:
            lapsed.append(f"{vec['label']} (rebuilt since 2026-09-25)")
            continue
        anchored += 1
        where = f"{vec['label']} (the recorded build)"
        check(image.security_cookie_va() == (vec["cookie"], None),
              f"{where}: the load config reads "
              f"{image.security_cookie_va()}, recorded {vec['cookie']:#x}")
        check(image.is_writable_va(vec["cookie"])
              and not image.is_exec_va(vec["cookie"]),
              f"{where}: the cookie's section is not the recorded .data")
        check(image.is_exec_va(vec["fn_va"])
              and not image.is_writable_va(vec["fn_va"]),
              f"{where}: the function's section is not the recorded .text")
        check(image.machine == vec["machine"],
              f"{where}: machine {image.machine}, recorded {vec['machine']}")
        value, shape, why = GATE.decode_abi("pe", image, member["abi_symbol"])
        check((value, shape) == (vec["value"], "guarded"),
              f"{where}: the gate reads {value} ({shape}; {why}), the "
              f"recording {vec['value']} (guarded)")

    # The load-config refusals on a real image, and the sweep on real bytes.
    live_total = {"refused": 0, "value": 0, "free": 0, "free_refused": 0,
                  "bytes": 0}
    smallest = {}
    for member, plat, path, code_at, value in guarded_live:
        fn_va = code_at.export_va(member["abi_symbol"])
        mem = GATE.PeImage(bytearray(code_at.data))
        fn_off = mem.rva_to_offset(fn_va - mem.image_base)
        layout = layout_for(mem.read_va(fn_va, GATE.GUARDED_READ),
                            mem.machine)
        fn_blob = memoryview(mem.data)[fn_off:fn_off + layout["length"]]
        check_va = check_blob = None
        if mem.machine == "x64":
            rel = struct.unpack_from("<i", mem.data,
                                     fn_off + layout["call_rel"])[0]
            check_va = fn_va + layout["call_next"] + rel
            check_off = mem.rva_to_offset(check_va - mem.image_base)
            check_blob = memoryview(mem.data)[check_off:check_off + 30]
        tallies = sweep(mem, fn_va, fn_blob, check_va, check_blob, value,
                        f"{member['name']} {plat} (live)")
        for key in live_total:
            live_total[key] += (tallies or {}).get(key, 0)
        size = len(mem.data)
        if mem.machine not in smallest or size < smallest[mem.machine][0]:
            smallest[mem.machine] = (size, member, plat, path, fn_va)
    for machine, (_size, member, plat, path, fn_va) in sorted(
            smallest.items()):
        with open(path, "rb") as fh:
            original = fh.read()
        image = GATE.PeImage(original)
        lc_off = image.rva_to_offset(image.load_config[0])
        at, width = GATE.SECURITY_COOKIE_FIELD[machine]
        entry = None
        pe_off = struct.unpack_from("<I", original, 0x3c)[0]
        opt = pe_off + 24
        magic = struct.unpack_from("<H", original, opt)[0]
        entry = opt + (96 if magic == 0x10b else 112) + 8 * 10
        edits = [
            ("SecurityCookie zeroed", lc_off + at, b"\x00" * width,
             "records no /GS cookie"),
            ("the structure's Size below SecurityCookie", lc_off,
             struct.pack("<I", at), "too few to hold SecurityCookie"),
            ("the load-config directory entry zeroed", entry, b"\x00" * 8,
             "no load-config directory"),
            ("SecurityCookie pointed into code", lc_off + at,
             struct.pack("<I" if width == 4 else "<Q", fn_va),
             "not in a writable section"),
        ]
        for label, off, patch, reason in edits:
            data = bytearray(original)
            data[off:off + len(patch)] = patch
            got, why = decode(GATE.PeImage(data), fn_va)
            if check(got is None, f"{member['name']} {plat}: {label} was "
                     f"accepted as {got}"):
                check(reason in why, f"{member['name']} {plat}: {label} "
                      f"refused for the wrong reason ({why!r})")
    print(f"{TAG}: leg 4 - {len(decoded_files)} live ABI constants equal "
          f"their headers ({len(guarded_live)} guarded; {leaf_before} leaf "
          f"reads unchanged); the gate skips {len(abi_skips)} and counts "
          f"{len(decoded_files)}; a skewed guarded DLL fails the gate; "
          f"{4 * len(smallest)} load-config refusals; {live_total['bytes']} "
          f"live bytes x {len(FLIPS)} flips: {live_total['refused']} "
          f"refused, {live_total['value']} value, {live_total['free']} free "
          f"({live_total['free_refused']} refused)")
    print(f"{TAG}: leg 4 - {anchored} of {len(VECTORS)} committed DLLs are "
          f"still the recorded builds and read back every recorded fact")
    for item in undecoded:
        print(f"{TAG}: NOTE {item} does not decode; the gate prints its SKIP")
    for item in lapsed:
        print(f"{TAG}: NOTE {item}: the recorded-build anchor lapses for it")

    # Leg 5: independent readers.
    why_not = objdump_supports_pe()
    agreed = 0
    if why_not is not None:
        SKIPS.append(f"objdump cross-check - {why_not}")
    else:
        for member, plat, path, code_at, value in guarded_live:
            fn_va = code_at.export_va(member["abi_symbol"])
            trace = []
            decode_ok = GATE.decode_msvc_guarded(code_at, fn_va, trace)[0]
            # The function's part of the trace ends at its first `ret`; for
            # x64 the called check follows, wherever it sits in .text.
            rets = [i for i, t in enumerate(trace) if t[2] == "ret"]
            if not check(decode_ok is not None and rets,
                         f"{member['name']} {plat}: the decoder returned no "
                         f"instruction trace to hold objdump against"):
                continue
            first_ret = rets[0]
            rows = []
            for part in (trace[:first_ret + 1], trace[first_ret + 1:]):
                if part:
                    rows.extend(objdump_listing(path, part[0][0],
                                                part[-1][0] + part[-1][1]))
            theirs = [(r[0], r[1], r[2]) for r in rows]
            differ = [(a, b) for a, b in zip(theirs, trace) if a != b]
            if len(theirs) != len(trace) and not differ:
                differ = [("instruction count", len(theirs), len(trace))]
            if check(not differ, f"{member['name']} {plat}: objdump's "
                     f"instruction boundaries/mnemonics differ from the "
                     f"decoder's: first difference (objdump, decoder) "
                     f"{differ[:1]}"):
                movs = [r for r in rows if r[2] == "mov" and
                        r[3] == f"eax,{decode_ok:#x}"]
                if check(len(movs) == 1, f"{member['name']} {plat}: objdump "
                         f"shows {len(movs)} `mov eax,{decode_ok:#x}` lines"):
                    agreed += 1
    exec_why = exec_host_reason()
    executed = 0
    x64_live = [g for g in guarded_live if g[3].machine == "x64"]
    if exec_why is not None:
        SKIPS.append(f"x64 execution cross-check - {exec_why}")
    else:
        for member, plat, path, code_at, value in x64_live:
            rva = code_at.export_rva_of(member["abi_symbol"])
            cookie, _ = code_at.security_cookie_va()
            stored = struct.unpack_from(
                "<Q", code_at.data,
                code_at.rva_to_offset(cookie - code_at.image_base))[0]
            if stored >> 48:
                # __security_check_cookie's `test cx, 0xffff` would send the
                # call to __report_gsfailure, which is not decoded: running
                # it here would execute code nothing has read.
                SKIPS.append(f"{member['name']} {plat} execution - the "
                             f"file's cookie {stored:#x} has high bits set")
                continue
            live, why = execute_x64(path, rva)
            if live is None:
                SKIPS.append(f"{member['name']} {plat} execution - {why}")
                continue
            if not check(live == value, f"{member['name']} {plat}: EXECUTING "
                         f"the function returns {live}, the decoder read "
                         f"{value} - the decoder is wrong"):
                continue
            layout = layout_for(code_at.read_va(rva + code_at.image_base,
                                                GATE.GUARDED_READ), "x64")
            cont = layout["skip_at"] + 1
            fn_off = code_at.rva_to_offset(rva)
            if code_at.data[fn_off + cont] == 0xB8:
                catch_value = struct.unpack_from("<i", code_at.data,
                                                 fn_off + cont + 1)[0]
            else:
                catch_value = 0
            mutated, why = execute_x64(path, rva, (layout["skip_at"], 0))
            if mutated is None:
                SKIPS.append(f"{member['name']} {plat} `eb 00` execution - "
                             f"{why}")
                continue
            if check(mutated == catch_value and mutated != value,
                     f"{member['name']} {plat}: the `eb 00` mutant returns "
                     f"{mutated}, expected the catch value {catch_value}"):
                executed += 1
    print(f"{TAG}: leg 5 - objdump agrees with the decoder on {agreed} of "
          f"{len(guarded_live)} guarded functions; {executed} of "
          f"{len(x64_live)} x64 guarded functions EXECUTED here return the "
          f"decoded value, and their `eb 00` mutants the catch value")

    for skip in SKIPS:
        print(f"{TAG}: SKIP {skip}")
    if FAILURES:
        for failure in FAILURES[:40]:
            print(f"{TAG}: FAIL {failure}")
        if len(FAILURES) > 40:
            print(f"{TAG}: ... and {len(FAILURES) - 40} more")
        print(f"{TAG}: FAILED with {len(FAILURES)} failure(s)")
        return 1
    print(f"{TAG}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
