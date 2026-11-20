#!/usr/bin/env python3
"""build-test-pdfs.py - writes the PDF files pdfxt's tests read.

tests/fixtures/basic.pdf and tests/fixtures/locked.pdf (and tests/fixtures.h,
the same bytes as C arrays for the native test) are written BY THIS FILE, byte for byte, from the tables below: no PDF tool made them, so every
number a test asserts (a page size, where a word is, where a link leads) is
a number written here, in one place, and a test never has to trust a file
nobody can read. They are committed so a build needs no Python; the gate
form refuses a committed file that this script would not write.

    python3 tools/build-test-pdfs.py           # write them
    python3 tools/build-test-pdfs.py --check   # the gate: committed == built

basic.pdf, three pages:
  1  612 x 792 (US Letter). "Hello pdfxt" at 72,720 in 24 pt Helvetica; a
     solid red square from 100,100 to 200,200 (PDF space: its bottom left
     corner is 100 points from the page's bottom left); a link over the text
     to https://example.org/pdfxt; a second line "second line of page one".
  2  595 x 842 (A4), /Rotate 90, so it DISPLAYS 842 wide and 595 high.
     "Rotated page two"; a solid blue square from 0,0 to 50,50 in PDF space,
     which a quarter turn clockwise puts at the TOP left of the display; a
     link that goes to page 1.
  3  200 x 100. "caf\\xe9 na\\xefve" (WinAnsi: e acute, i diaeresis) and
     "needle Needle needle".
  Information: Title "pdfxt test file", Author "xTalk Suite", a Subject
  written as UTF-16 with a non-Latin letter. Outline: "Chapter 1" (page 1)
  with a child "Section 1.1" (page 2), then "Chapter 2" (page 3), then
  "Elsewhere" (a web address, no page). Page labels: "i", then "1", "2".

locked.pdf: page 1 of the above alone ("Hello pdfxt", the red square),
encrypted with the standard security handler, revision 2 (RC4, 40 bits):
user password "secret", owner password "owner", printing not allowed.
Opening it with no password must fail; "secret" opens it.

Standard library only.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests")

PAD = bytes([0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56,
             0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
             0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A])
FILE_ID = bytes(range(0x10, 0x20))


def rc4(key, data):
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    out = bytearray()
    i = j = 0
    for b in data:
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        out.append(b ^ s[(s[i] + s[j]) & 255])
    return bytes(out)


def pad_password(pw):
    return (pw + PAD)[:32]


class Crypt(object):
    """The standard security handler, revision 2 (PDF 1.7, 7.6.3)."""

    def __init__(self, user, owner, permissions):
        self.p = permissions & 0xFFFFFFFF
        okey = hashlib.md5(pad_password(owner)).digest()[:5]
        self.o = rc4(okey, pad_password(user))
        h = hashlib.md5()
        h.update(pad_password(user))
        h.update(self.o)
        h.update(self.p.to_bytes(4, "little"))
        h.update(FILE_ID)
        self.key = h.digest()[:5]
        self.u = rc4(self.key, PAD)

    def encrypt(self, num, data):
        k = hashlib.md5(self.key + num.to_bytes(3, "little") + b"\x00\x00").digest()[:10]
        return rc4(k, data)


def pdf_string(data):
    """A literal string, every byte outside plain ASCII written as octal."""
    out = bytearray(b"(")
    for b in data:
        if b in (0x28, 0x29, 0x5C):
            out += b"\\" + bytes([b])
        elif 0x20 <= b < 0x7F:
            out.append(b)
        else:
            out += ("\\%03o" % b).encode("ascii")
    return bytes(out + b")")


class Builder(object):
    def __init__(self, crypt=None):
        self.objects = {}
        self.crypt = crypt

    def text(self, num, data):
        """A string that belongs to object `num` (encrypted with its key)."""
        if self.crypt:
            data = self.crypt.encrypt(num, data)
        return pdf_string(data)

    def add(self, num, body):
        self.objects[num] = body

    def stream(self, num, data):
        if self.crypt:
            data = self.crypt.encrypt(num, data)
        self.add(num, b"<< /Length %d >>\nstream\n" % len(data) + data + b"\nendstream")

    def build(self, root, info):
        out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
        count = max(self.objects) + 1
        offsets = {}
        for num in sorted(self.objects):
            offsets[num] = len(out)
            out += b"%d 0 obj\n" % num + self.objects[num] + b"\nendobj\n"
        xref = len(out)
        out += b"xref\n0 %d\n" % count
        out += b"0000000000 65535 f \n"
        for num in range(1, count):
            if num not in offsets:
                raise SystemExit("build-test-pdfs: object %d is missing" % num)
            out += b"%010d 00000 n \n" % offsets[num]
        trailer = b"<< /Size %d /Root %d 0 R /Info %d 0 R /ID [<%s> <%s>]" % (
            count, root, info, FILE_ID.hex().encode(), FILE_ID.hex().encode())
        if self.crypt:
            trailer += b" /Encrypt %d 0 R" % (count - 1)
        out += b"trailer\n" + trailer + b" >>\nstartxref\n%d\n%%%%EOF\n" % xref
        return bytes(out)


FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

PAGE1 = (b"1 0 0 rg\n100 100 100 100 re\nf\n"
         b"0 0 0 rg\nBT\n/F1 24 Tf\n72 720 Td\n(Hello pdfxt) Tj\nET\n"
         b"BT\n/F1 12 Tf\n72 690 Td\n(second line of page one) Tj\nET\n")
PAGE2 = (b"0 0 1 rg\n0 0 50 50 re\nf\n"
         b"0 0 0 rg\nBT\n/F1 18 Tf\n100 400 Td\n(Rotated page two) Tj\nET\n")
PAGE3 = (b"BT\n/F1 10 Tf\n10 70 Td\n(caf\\351 na\\357ve) Tj\nET\n"
         b"BT\n/F1 10 Tf\n10 40 Td\n(needle Needle needle) Tj\nET\n")


def basic():
    b = Builder()
    b.add(1, b"<< /Type /Catalog /Pages 2 0 R /Outlines 13 0 R "
             b"/PageLabels << /Nums [0 << /S /r >> 1 << /S /D >>] >> >>")
    b.add(2, b"<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>")
    b.add(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R "
             b"/Resources << /Font << /F1 9 0 R >> >> /Annots [10 0 R] >>")
    b.add(4, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Rotate 90 /Contents 7 0 R "
             b"/Resources << /Font << /F1 9 0 R >> >> /Annots [11 0 R] >>")
    b.add(5, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 8 0 R "
             b"/Resources << /Font << /F1 9 0 R >> >> >>")
    b.stream(6, PAGE1)
    b.stream(7, PAGE2)
    b.stream(8, PAGE3)
    b.add(9, FONT)
    b.add(10, b"<< /Type /Annot /Subtype /Link /Rect [72 715 210 745] /Border [0 0 0] "
              b"/A << /S /URI /URI (https://example.org/pdfxt) >> >>")
    b.add(11, b"<< /Type /Annot /Subtype /Link /Rect [100 395 260 420] /Border [0 0 0] "
              b"/Dest [3 0 R /Fit] >>")
    subject = "﻿Subject with Ω".encode("utf-16-be")
    b.add(12, b"<< /Title (pdfxt test file) /Author (xTalk Suite) /Subject " + pdf_string(subject)
              + b" /Producer (pdfxt tools/build-test-pdfs.py) >>")
    b.add(13, b"<< /Type /Outlines /First 14 0 R /Last 17 0 R /Count 4 >>")
    b.add(14, b"<< /Title (Chapter 1) /Parent 13 0 R /Next 16 0 R /First 15 0 R /Last 15 0 R /Count 1 "
              b"/Dest [3 0 R /Fit] >>")
    b.add(15, b"<< /Title (Section 1.1) /Parent 14 0 R /Dest [4 0 R /Fit] >>")
    b.add(16, b"<< /Title (Chapter 2) /Parent 13 0 R /Prev 14 0 R /Next 17 0 R "
              b"/A << /S /GoTo /D [5 0 R /Fit] >> >>")
    b.add(17, b"<< /Title (Elsewhere) /Parent 13 0 R /Prev 16 0 R "
              b"/A << /S /URI /URI (https://example.org/elsewhere) >> >>")
    return b.build(1, 12)


def locked():
    # Permissions: every bit set but bit 3 (print), as a signed 32-bit number.
    permissions = -4 & ~(1 << 2)
    crypt = Crypt(b"secret", b"owner", permissions)
    b = Builder(crypt)
    b.add(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    b.add(2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    b.add(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
             b"/Resources << /Font << /F1 5 0 R >> >> >>")
    b.stream(4, PAGE1)
    b.add(5, FONT)
    b.add(6, b"<< /Title " + b.text(6, b"locked pdfxt test file") + b" >>")
    b.add(7, b"<< /Filter /Standard /V 1 /R 2 /O " + pdf_string(crypt.o) + b" /U " + pdf_string(crypt.u)
             + b" /P %d >>" % permissions)
    return b.build(1, 6)


def header():
    """tests/fixtures.h: the same two files as C arrays, so the native smoke
    test carries them and needs no path handed to it (it runs on an Android
    emulator and under ctest on six desktop rows, each with its own idea of
    where a source tree is)."""
    out = ["/* GENERATED by tools/build-test-pdfs.py from the files beside this one's",
           " * folder (tests/fixtures/). Do not edit: run the script. */",
           "#ifndef PDFXT_TEST_FIXTURES_H", "#define PDFXT_TEST_FIXTURES_H", ""]
    for name, make in (("basic", basic), ("locked", locked)):
        data = make()
        out.append("static const unsigned char k_%s_pdf[%d] = {" % (name, len(data)))
        for i in range(0, len(data), 16):
            out.append("    " + ", ".join("0x%02x" % b for b in data[i:i + 16]) + ",")
        out.append("};")
        out.append("")
    out.append("#endif")
    return ("\n".join(out) + "\n").encode("ascii")


FILES = {"fixtures/basic.pdf": basic, "fixtures/locked.pdf": locked, "fixtures.h": header}


def main(argv):
    check = "--check" in argv
    bad = 0
    for name, make in sorted(FILES.items()):
        data = make()
        path = os.path.join(OUT, name)
        if check:
            try:
                have = open(path, "rb").read()
            except OSError:
                have = None
            if have != data:
                print("build-test-pdfs: tests/%s is not what this script writes "
                      "(run tools/build-test-pdfs.py)" % name)
                bad = 1
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("build-test-pdfs: wrote tests/%s (%d bytes)" % (name, len(data)))
    if check and not bad:
        print("build-test-pdfs: OK (%d files match what this script writes)" % len(FILES))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
