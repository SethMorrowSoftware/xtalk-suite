#!/usr/bin/env python3
"""test-build-test-pdfs.py - prove tools/build-test-pdfs.py --check FIRES.

The gate holds two kinds of file to what the script writes: the committed
fixtures (tests/fixtures/*.pdf and tests/fixtures.h), byte for byte, and ONE
BLOCK of the demo stack, examples/pdfxt-demo.livecodescript, between its two
marker lines; the rest of that file is hand-written and the gate must leave
it alone. Each case copies the real files into a scratch tree, breaks one
thing, and requires the gate to refuse it with a message that names the
break ("fixture before gate", suite root CLAUDE.md). The unbroken copy must
pass, and the write form must mend every break while keeping the demo's
hand-written text.

The block is also read back the way the demo reads it: its constants joined
in the order pvSampleBase64 names them, then decoded. That must give the
sample and locked.pdf exactly, so a block the script wrote with its pieces in
the wrong order, or a constant missing from the join, cannot pass as "what
the script writes" (exercise a gate the way the build will).
"""
import base64
import contextlib
import importlib.util
import io
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "pdx_build_test_pdfs", os.path.join(HERE, "tools", "build-test-pdfs.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

FIXTURE_PATHS = sorted(GATE.FILES)
DEMO = GATE.DEMO


def run(root, argv):
    """The gate's exit code and everything it printed."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = GATE.main(argv, root=root)
    return code, out.getvalue()


def fresh(tmp):
    """A scratch member root holding the real committed files."""
    root = tempfile.mkdtemp(dir=tmp)
    for rel in FIXTURE_PATHS + [DEMO]:
        os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
        shutil.copyfile(os.path.join(HERE, rel), os.path.join(root, rel))
    return root


def read(root, rel):
    with open(os.path.join(root, rel), "rb") as f:
        return f.read()


def write(root, rel, data):
    with open(os.path.join(root, rel), "wb") as f:
        f.write(data)


def demo_text(root):
    return read(root, DEMO).decode("ascii")


def set_demo(root, text):
    write(root, DEMO, text.encode("ascii"))


def flip_last_byte(root, rel):
    data = bytearray(read(root, rel))
    data[-1] ^= 1
    write(root, rel, bytes(data))


def decoded_block(text):
    """The two PDFs as the demo would rebuild them from its block: the
    constants it declares, joined as pvSampleBase64's two return lines name
    them, then base64-decoded. None when the block cannot be read so."""
    consts = dict(re.findall(r'^constant (kPv\w+) = "([A-Za-z0-9+/=]*)"$', text, re.M))
    joins = re.findall(r"^\s*return (kPv\w+(?: & kPv\w+)*)$", text, re.M)
    if len(joins) != 2:
        return None
    out = []
    for join in joins:
        names = join.split(" & ")
        if any(n not in consts for n in names):
            return None
        out.append(base64.b64decode("".join(consts[n] for n in names)))
    return out   # [locked, sample]: the order the function's lines take


def main():
    failed = 0
    tmp = tempfile.mkdtemp(prefix="pdx-build-test-pdfs-")
    try:
        # The committed tree must pass, and the demo's block must rebuild
        # the very bytes the script makes.
        root = fresh(tmp)
        code, said = run(root, ["--check"])
        if code != 0 or "OK" not in said:
            print("FAIL the committed files must pass: %s" % said.strip())
            return 1
        rebuilt = decoded_block(demo_text(root))
        if rebuilt is None:
            print("FAIL the demo's sample block does not read as constants joined by "
                  "pvSampleBase64 (two return lines naming only declared constants)")
            failed += 1
        else:
            for label, have, want in (("locked.pdf", rebuilt[0], GATE.locked()),
                                      ("the sample", rebuilt[1], GATE.sample())):
                if have != want:
                    print("FAIL the demo's block does not decode to %s (%d bytes, want %d)"
                          % (label, len(have), len(want)))
                    failed += 1
        longest = max(len(c) for c in re.findall(r'^constant kPv\w+ = "([^"]*)"$',
                                                  demo_text(root), re.M))
        if longest > GATE.CHUNK:
            print("FAIL a sample constant is %d characters, over CHUNK (%d)"
                  % (longest, GATE.CHUNK))
            failed += 1

        # (label, how to break a fresh tree, the gate's exit code, words it must print)
        def edit_demo(fn):
            return lambda r: set_demo(r, fn(demo_text(r)))

        first_const = re.search(r'^constant kPvSample1 = "(.)', GATE.demo_block(), re.M)
        swap = "A" if first_const.group(1) != "A" else "B"
        cases = [
            ("basic.pdf with one byte changed",
             lambda r: flip_last_byte(r, "tests/fixtures/basic.pdf"), 1,
             "tests/fixtures/basic.pdf is not what this script writes"),
            ("locked.pdf missing",
             lambda r: os.remove(os.path.join(r, "tests/fixtures/locked.pdf")), 1,
             "tests/fixtures/locked.pdf is not what this script writes"),
            ("fixtures.h edited by hand",
             lambda r: write(r, "tests/fixtures.h", read(r, "tests/fixtures.h").replace(b"0x25", b"0x26", 1)), 1,
             "tests/fixtures.h is not what this script writes"),
            ("a letter of the sample's base64 changed in the demo",
             edit_demo(lambda t: t.replace('constant kPvSample1 = "' + first_const.group(1),
                                           'constant kPvSample1 = "' + swap, 1)), 1,
             "the sample block of %s is not what this script writes" % DEMO),
            ("the sample's last constant dropped from the join",
             edit_demo(lambda t: re.sub(r"( & kPvSample\d+)$", "", t, count=1, flags=re.M)), 1,
             "the sample block of %s is not what this script writes" % DEMO),
            ("two constants of the sample's join swapped",
             edit_demo(lambda t: t.replace("return kPvSample1 & kPvSample2",
                                           "return kPvSample2 & kPvSample1", 1)), 1,
             "the sample block of %s is not what this script writes" % DEMO),
            ("a line written inside the block by hand",
             edit_demo(lambda t: t.replace("function pvSampleBase64 pWhich",
                                           "-- a note\nfunction pvSampleBase64 pWhich", 1)), 1,
             "the sample block of %s is not what this script writes" % DEMO),
            ("the end marker gone",
             edit_demo(lambda t: t.replace(GATE.END + "\n", "", 1)), 1,
             "needs one line beginning"),
            ("the begin marker given twice",
             edit_demo(lambda t: GATE.BEGIN + " (again)\n" + t), 1,
             "needs one line beginning"),
            ("the end marker before the begin marker",
             edit_demo(lambda t: GATE.END + "\n" + t.replace(GATE.END + "\n", "", 1)), 1,
             "needs one line beginning"),
            ("the demo missing",
             lambda r: os.remove(os.path.join(r, DEMO)), 1,
             "cannot read %s" % DEMO),
            # An e acute in UTF-8: the stack must stay ASCII (rule 5's static
            # gate), and this gate reads it as ASCII, so it refuses too.
            ("the demo no longer ASCII",
             lambda r: write(r, DEMO, read(r, DEMO).replace(b"-- ", b"-- \xc3\xa9 ", 1)), 1,
             "cannot read %s" % DEMO),
        ]
        for label, breaker, want_code, want in cases:
            root = fresh(tmp)
            before = {rel: (read(root, rel) if os.path.exists(os.path.join(root, rel)) else None)
                      for rel in FIXTURE_PATHS + [DEMO]}
            breaker(root)
            after = {rel: (read(root, rel) if os.path.exists(os.path.join(root, rel)) else None)
                     for rel in FIXTURE_PATHS + [DEMO]}
            if after == before:
                print("FAIL %s: the fixture is stale (it changed nothing)" % label)
                failed += 1
                continue
            code, said = run(root, ["--check"])
            if code != want_code or want not in said:
                print("FAIL %s: the gate answered %s, printing %r; want %s and %r"
                      % (label, code, said.strip(), want_code, want))
                failed += 1

        # The hand-written part of the demo is the gate's to leave alone: an
        # edit outside the block passes, and the write form keeps it.
        root = fresh(tmp)
        text = demo_text(root)
        marked = text.replace("constant kPvUiVersion", "-- a hand-written note\nconstant kPvUiVersion", 1)
        if marked == text:
            print("FAIL the hand-written case is stale: kPvUiVersion is not in the demo")
            failed += 1
        set_demo(root, marked)
        code, said = run(root, ["--check"])
        if code != 0:
            print("FAIL an edit outside the block must pass: %s" % said.strip())
            failed += 1

        # The write form mends every break at once and keeps that note.
        flip_last_byte(root, "tests/fixtures/basic.pdf")
        os.remove(os.path.join(root, "tests/fixtures.h"))
        set_demo(root, demo_text(root).replace('constant kPvLocked1 = "', 'constant kPvLocked1 = "X', 1))
        code, said = run(root, [])
        if code != 0:
            print("FAIL the write form must succeed: %s" % said.strip())
            failed += 1
        code, said = run(root, ["--check"])
        if code != 0:
            print("FAIL after the write form the gate must pass: %s" % said.strip())
            failed += 1
        if "-- a hand-written note\n" not in demo_text(root):
            print("FAIL the write form dropped hand-written text outside the block")
            failed += 1
        for rel in FIXTURE_PATHS:
            if read(root, rel) != read(HERE, rel):
                print("FAIL the write form did not restore %s byte for byte" % rel)
                failed += 1
        if demo_text(root).replace("-- a hand-written note\n", "", 1) != demo_text(HERE):
            print("FAIL the write form changed the demo beyond its block")
            failed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failed:
        print("test-build-test-pdfs: %d case(s) FAILED" % failed)
        return 1
    print("test-build-test-pdfs: OK (the committed files pass, the demo's block decodes to the "
          "two PDFs, every break is refused, and the write form mends them)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
