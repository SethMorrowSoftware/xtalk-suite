#!/usr/bin/env python3
"""build-test-pdfs.py - writes the PDF files pdfxt's tests and demo read.

tests/fixtures/basic.pdf, locked.pdf and form.pdf (and tests/fixtures.h, the
same bytes as C arrays for the native test) are written BY THIS FILE,
byte for byte, from the tables below: no PDF tool made them, so every
number a test asserts (a page size, where a word is, where a link leads) is
a number written here, in one place, and a test never has to trust a file
nobody can read. They are committed so a build needs no Python; the gate
form refuses a committed file that this script would not write.

So is the demo's sample, "A short guide to pdfxt" (five pages, described
above sample() below), and for the same reason: the demo stack's checks and
its headless drive assert its sizes, words, links and colours. It is not a
file of its own. examples/pdfxt-demo.livecodescript carries it, and
locked.pdf, as base64 text between two marker lines, so the demo stays one
paste-and-run script; this script writes that block and only that block
(the rest of the stack is hand-written), and the gate form refuses a block
it would not write. tools/test-build-test-pdfs.py proves the gate fires.

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

form.pdf, one page of 200 x 100 with a filled-in form: "Name:" at 20,70 in
10 pt Helvetica, and a text field "name" holding "pdfxt" whose widget covers
20,20 to 180,60 of PDF space, so 20..180 across and 40..80 down as
displayed. Its normal appearance fills that box in pure green (0,255,0) and
writes the value in black near its bottom left. PDFium draws a form's fields
only through its form module (FPDF_FFLDraw), never in a plain page drawing:
with flag 1 the box is green, without it the paper there is white. The
field's value is not text of the page.

Standard library only.
"""
import base64
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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

    def stream(self, num, data, entries=b""):
        """A stream object; `entries` are more of its dictionary's entries
        (a form XObject's /Type, /Subtype and /BBox), written before /Length."""
        if self.crypt:
            data = self.crypt.encrypt(num, data)
        self.add(num, b"<< " + (entries + b" " if entries else b"") + b"/Length %d >>\nstream\n" % len(data)
                 + data + b"\nendstream")

    def build(self, root, info, version=b"1.4"):
        out = bytearray(b"%PDF-" + version + b"\n%\xe2\xe3\xcf\xd3\n")
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


# The field's normal appearance: its whole box in pure green, with its value
# in black. Pure green, so a test can ask for the exact colour.
FORM_FIELD_LOOK = (b"0 1 0 rg\n0 0 160 40 re\nf\n"
                   b"0 0 0 rg\nBT\n/F1 12 Tf\n8 14 Td\n(pdfxt) Tj\nET\n")


def form():
    b = Builder()
    b.add(1, b"<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] /DA (/F1 12 Tf 0 g) >> >>")
    b.add(2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    b.add(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R "
             b"/Resources << /Font << /F1 6 0 R >> >> /Annots [5 0 R] >>")
    b.stream(4, b"0 0 0 rg\nBT\n/F1 10 Tf\n20 70 Td\n(Name:) Tj\nET\n")
    # One dictionary that is both the field and its widget, as most forms write it.
    b.add(5, b"<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /V (pdfxt) /DA (/F1 12 Tf 0 g) "
             b"/Rect [20 20 180 60] /F 4 /P 3 0 R /AP << /N 7 0 R >> >>")
    b.add(6, FONT)
    b.stream(7, FORM_FIELD_LOOK, b"/Type /XObject /Subtype /Form /BBox [0 0 160 40] "
                                 b"/Resources << /Font << /F1 6 0 R >> >>")
    b.add(8, b"<< /Title (pdfxt form test file) >>")
    return b.build(1, 8)


# ---------------------------------------------------------------------------
# The demo's sample: "A short guide to pdfxt", five pages, which
# examples/pdfxt-demo.livecodescript opens without a file. It is written here
# for the reason the fixtures are: every fact the demo's checks assert (a
# label, a size, where a link leads, how often a word occurs, the colour at a
# point) is a number or a word on this page of Python.
#
#   i    612 x 792. A band in the suite's accent colour with the title in
#        white; three lines of text, one naming PDFium; a red, a green and a
#        blue square; https://openxtalk.org/ as a web link; and a filled-in
#        form field, "Made with:" OXT-Beyond and pdfxt, its box 140..440
#        across and 512..540 down as displayed, light blue (the kit's
#        kUiAccentSub) inside an accent-coloured line. A form's fields are
#        drawn only with flag 1 (PDFium's form module draws them).
#   ii   612 x 792. "Contents": three lines, each a link to its page.
#   1    612 x 792. "1 Opening a document", then "Passwords".
#   2    A4 (595 x 842) with /Rotate 90, so it DISPLAYS 842 x 595, and its
#        content is drawn turned the other way, so it reads upright as
#        displayed (a viewer's landscape page): six bars and a circle.
#   3    612 x 792. "3 Text and search": the line "needle, Needle, needles"
#        (three matches with no flags, two when capitals must match, two as
#        whole words, one with both), text outside ASCII, and a link back to
#        the contents.
#   Labels i, ii, 1, 2, 3. Outline of eight entries, two of them nested and
#   the last a web address. All eight Information entries are set.
# ---------------------------------------------------------------------------

ACCENT = (44, 90, 160)        # the suite UI kit's kUiAccent
ACCENT_SUB = (199, 216, 241)  # and its kUiAccentSub
WHITE = (255, 255, 255)
INK = (28, 34, 46)
GREY = (138, 146, 158)
LINK = (20, 80, 200)
RED = (255, 0, 0)
GREEN = (0, 160, 0)
BLUE = (0, 0, 255)
BARS = ((44, 90, 160), (23, 128, 63), (214, 150, 30), (176, 58, 46), (0, 128, 128), (110, 60, 150))


def rgb(c):
    return b"%.3f %.3f %.3f" % (c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)


def show(font, size, x, y, text, color=INK):
    """One line of text in WinAnsi, its baseline starting at x,y (PDF space)."""
    return (rgb(color) + b" rg\nBT\n/%s %d Tf\n%d %d Td\n" % (font, size, x, y)
            + pdf_string(text.encode("cp1252")) + b" Tj\nET\n")


def show_turned(font, size, x, y, text, color=INK):
    """One line on a page the file turns a quarter clockwise, drawn turned
    back so it reads upright: x,y is where its baseline starts on the page
    AS DISPLAYED, from the displayed page's top left. A quarter turn
    clockwise takes PDF x to displayed y and PDF y to displayed x."""
    return (rgb(color) + b" rg\nBT\n/%s %d Tf\n0 1 -1 0 %d %d Tm\n" % (font, size, y, x)
            + pdf_string(text.encode("cp1252")) + b" Tj\nET\n")


def box(x, y, w, h, color):
    """A filled rectangle in PDF space (x,y its bottom left)."""
    return rgb(color) + b" rg\n%d %d %d %d re\nf\n" % (x, y, w, h)


def box_turned(x, y, w, h, color):
    """A filled rectangle given on the page as displayed (x,y its top left)."""
    return box(y, x, h, w, color)


def circle(cx, cy, r, color):
    """A filled circle of four Bezier quarters, centre cx,cy in PDF space."""
    k = 0.5523 * r
    pts = ((cx + r, cy), (cx + r, cy + k, cx + k, cy + r, cx, cy + r),
           (cx - k, cy + r, cx - r, cy + k, cx - r, cy),
           (cx - r, cy - k, cx - k, cy - r, cx, cy - r),
           (cx + k, cy - r, cx + r, cy - k, cx + r, cy))
    out = rgb(color) + b" rg\n%.2f %.2f m\n" % pts[0]
    for p in pts[1:]:
        out += b"%.2f %.2f %.2f %.2f %.2f %.2f c\n" % p
    return out + b"f\n"


def body(x, y, lines, size=12, leading=16):
    out = b""
    for i, line in enumerate(lines):
        out += show(b"F1", size, x, y - i * leading, line)
    return out


def footer(label):
    return show(b"F1", 9, 72, 40, "A short guide to pdfxt, page " + label, GREY)


SAMPLE_PAGES = [
    # i: the cover
    box(0, 642, 612, 150, ACCENT)
    + show(b"F2", 48, 72, 700, "pdfxt", WHITE)
    + show(b"F1", 16, 72, 668, "A short guide, and the sample the demo opens", WHITE)
    + body(72, 600, ["pdfxt draws the pages of a PDF, reads their text, finds words in it,",
                     "follows its outline and its links, and tells a script all of it.",
                     "It binds PDFium, the PDF engine of the Chromium browser."])
    + box(72, 420, 100, 100, RED) + box(222, 420, 100, 100, GREEN) + box(372, 420, 100, 100, BLUE)
    + show(b"F1", 10, 72, 400, "Three squares, to see the colours come through.", GREY)
    + show(b"F1", 12, 72, 340, "https://openxtalk.org/", LINK)
    + show(b"F1", 10, 72, 296, "A form field, filled in: drawn only with flag 1, Annotations and forms on the Draw tab.", GREY)
    + show(b"F1", 12, 72, 262, "Made with:")
    + footer("i"),
    # ii: the contents, each line a link
    show(b"F2", 24, 72, 700, "Contents")
    + show(b"F1", 14, 72, 650, "1 Opening a document")
    + show(b"F1", 14, 72, 624, "2 Drawing pages")
    + show(b"F1", 14, 72, 598, "3 Text and search")
    + show(b"F1", 10, 72, 560, "Each line above is a link to its page.", GREY)
    + footer("ii"),
    # 1
    show(b"F2", 20, 72, 720, "1 Opening a document")
    + body(72, 690, ["pdfOpen opens a file by its path, and PDFium reads each page only when",
                     "it is asked for, so a long document opens at once. pdfOpenData opens a",
                     "PDF that is already in memory: this sample is one, carried inside the",
                     "demo stack as text and decoded before PDFium sees it."])
    + show(b"F2", 14, 72, 600, "Passwords")
    + body(72, 578, ["A locked PDF needs its password. pdfOpen and pdfOpenData take it as",
                     "their second parameter and refuse without it, and pdfLastError says",
                     "why. The demo's Locked sample opens with the word secret."])
    + footer("1"),
    # 2: A4 turned on its side, its content drawn to read upright
    show_turned(b"F2", 20, 60, 70, "2 Drawing pages")
    + b"".join(show_turned(b"F1", 12, 60, 100 + i * 16, line) for i, line in enumerate([
        "This page is A4 turned on its side: the file says /Rotate 90, and every",
        "size, drawing and rectangle pdfxt returns is of the page as you see it.",
        "pdfRenderPage draws a whole page. pdfRenderPageRegion draws only the part",
        "a zoomed-in viewer shows, so memory follows the window, not the zoom."]))
    + b"".join(box_turned(60 + i * 80, 500 - h, 56, h, BARS[i])
               for i, h in enumerate((80, 140, 110, 190, 160, 220)))
    + circle(360, 680, 110, ACCENT_SUB)
    + show_turned(b"F1", 10, 60, 530, "Shapes are drawn as curves and lines: zoom in, and their edges stay sharp.", GREY)
    + show_turned(b"F1", 9, 60, 570, "A short guide to pdfxt, page 2", GREY),
    # 3
    show(b"F2", 20, 72, 720, "3 Text and search")
    + body(72, 690, ["pdfPageText returns the text of a page in reading order, a line of the",
                     "page to a line. pdfPageSearch finds every place a word occurs, and",
                     "pdfPageTextRects gives the rectangles to highlight. Search this page",
                     "for the word on the next line, with and without the two flags:"])
    + show(b"F2", 14, 72, 610, "needle, Needle, needles")
    + show(b"F2", 14, 72, 570, "Searching")
    + body(72, 548, ["Capitals must match: two of the three. Whole words: two, since the",
                     "third is longer. Both flags: one.",
                     "Text outside ASCII comes out as itself: café, naïve, Zürich, 25 °C.",
                     "Drag a box around words on any page to read the text inside it."])
    + show(b"F1", 12, 72, 460, "Back to the contents", LINK)
    + footer("3"),
]


# The cover's form field: its normal appearance, 300 x 28 points.
SAMPLE_FIELD_LOOK = (box(0, 0, 300, 28, ACCENT_SUB)
                     + rgb(ACCENT) + b" RG\n1 w\n0.5 0.5 299 27 re\nS\n"
                     + show(b"F1", 12, 6, 9, "OXT-Beyond and pdfxt"))


def sample():
    b = Builder()
    fonts = b"/Resources << /Font << /F1 13 0 R /F2 14 0 R >> >>"
    b.add(1, b"<< /Type /Catalog /Pages 2 0 R /Outlines 21 0 R /PageMode /UseOutlines "
             b"/PageLabels << /Nums [0 << /S /r >> 2 << /S /D >>] >> "
             b"/AcroForm << /Fields [30 0 R] /DA (/F1 12 Tf 0 g) >> >>")
    b.add(2, b"<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R 7 0 R] /Count 5 >>")
    b.add(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 8 0 R "
             + fonts + b" /Annots [15 0 R 30 0 R] >>")
    b.add(4, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 9 0 R "
             + fonts + b" /Annots [16 0 R 17 0 R 18 0 R] >>")
    b.add(5, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 10 0 R " + fonts + b" >>")
    b.add(6, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Rotate 90 /Contents 11 0 R "
             + fonts + b" >>")
    b.add(7, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 12 0 R "
             + fonts + b" /Annots [19 0 R] >>")
    for i, page in enumerate(SAMPLE_PAGES):
        b.stream(8 + i, page)
    b.add(13, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    b.add(14, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    link = b"<< /Type /Annot /Subtype /Link /Border [0 0 0] /Rect [%d %d %d %d] "
    b.add(15, link % (70, 335, 206, 353) + b"/A << /S /URI /URI (https://openxtalk.org/) >> >>")
    for num, (y, target) in zip((16, 17, 18), ((650, 5), (624, 6), (598, 7))):
        b.add(num, link % (70, y - 5, 330, y + 15) + b"/Dest [%d 0 R /Fit] >>" % target)
    b.add(19, link % (70, 455, 196, 473) + b"/Dest [4 0 R /Fit] >>")
    b.add(20, b"<< /Title (A short guide to pdfxt) /Author (xTalk Suite) "
              b"/Subject (The sample PDF of the pdfxt demo stack) /Keywords (pdf, pdfium, openxtalk) "
              b"/Creator (pdfxt tools/build-test-pdfs.py) /Producer (pdfxt tools/build-test-pdfs.py) "
              b"/CreationDate (D:20261121000000Z) /ModDate (D:20261121000000Z) >>")
    b.add(21, b"<< /Type /Outlines /First 22 0 R /Last 29 0 R /Count 8 >>")
    b.add(22, b"<< /Title (Cover) /Parent 21 0 R /Next 23 0 R /Dest [3 0 R /Fit] >>")
    b.add(23, b"<< /Title (Contents) /Parent 21 0 R /Prev 22 0 R /Next 24 0 R /Dest [4 0 R /Fit] >>")
    b.add(24, b"<< /Title (1 Opening a document) /Parent 21 0 R /Prev 23 0 R /Next 26 0 R "
              b"/First 25 0 R /Last 25 0 R /Count 1 /Dest [5 0 R /Fit] >>")
    b.add(25, b"<< /Title (Passwords) /Parent 24 0 R /Dest [5 0 R /XYZ 72 620 0] >>")
    b.add(26, b"<< /Title (2 Drawing pages) /Parent 21 0 R /Prev 24 0 R /Next 27 0 R /Dest [6 0 R /Fit] >>")
    b.add(27, b"<< /Title (3 Text and search) /Parent 21 0 R /Prev 26 0 R /Next 29 0 R "
              b"/First 28 0 R /Last 28 0 R /Count 1 /Dest [7 0 R /Fit] >>")
    b.add(28, b"<< /Title (Searching) /Parent 27 0 R /Dest [7 0 R /XYZ 72 590 0] >>")
    b.add(29, b"<< /Title (OpenXTalk on the web) /Parent 21 0 R /Prev 27 0 R "
              b"/A << /S /URI /URI (https://openxtalk.org/) >> >>")
    b.add(30, b"<< /Type /Annot /Subtype /Widget /FT /Tx /T (madewith) /V (OXT-Beyond and pdfxt) "
              b"/DA (/F1 12 Tf 0 g) /Rect [140 252 440 280] /F 4 /P 3 0 R /AP << /N 31 0 R >> >>")
    b.stream(31, SAMPLE_FIELD_LOOK, b"/Type /XObject /Subtype /Form /BBox [0 0 300 28] "
                                    b"/Resources << /Font << /F1 13 0 R >> >>")
    return b.build(1, 20, b"1.7")


def header():
    """tests/fixtures.h: the same two files as C arrays, so the native smoke
    test carries them and needs no path handed to it (it runs on an Android
    emulator and under ctest on six desktop rows, each with its own idea of
    where a source tree is)."""
    out = ["/* GENERATED by tools/build-test-pdfs.py from the files beside this one's",
           " * folder (tests/fixtures/). Do not edit: run the script. */",
           "#ifndef PDFXT_TEST_FIXTURES_H", "#define PDFXT_TEST_FIXTURES_H", ""]
    for name, make in (("basic", basic), ("locked", locked), ("form", form)):
        data = make()
        out.append("static const unsigned char k_%s_pdf[%d] = {" % (name, len(data)))
        for i in range(0, len(data), 16):
            out.append("    " + ", ".join("0x%02x" % b for b in data[i:i + 16]) + ",")
        out.append("};")
        out.append("")
    out.append("#endif")
    return ("\n".join(out) + "\n").encode("ascii")


# Every file this script writes, by its path from the member root.
FILES = {"tests/fixtures/basic.pdf": basic, "tests/fixtures/locked.pdf": locked,
         "tests/fixtures/form.pdf": form, "tests/fixtures.h": header}

# The demo stack carries the sample and locked.pdf as text, so it stays one
# paste-and-run file: a block of it, between these two marker lines, is
# written here too. The rest of that file is hand-written.
DEMO = "examples/pdfxt-demo.livecodescript"
BEGIN = "-- >>> BEGIN SAMPLE PDFS"
END = "-- <<< END SAMPLE PDFS <<<"
# The IDE's script editor stays quick on lines of this length; the suite's
# stacks already carry base64 constants of up to about 3,200 characters.
CHUNK = 2000


def demo_block():
    """The lines between (and including) the demo's two marker lines."""
    out = [BEGIN + " (tools/build-test-pdfs.py writes this block: change that script, then run it) >>>",
           "-- The guide that \"The sample\" opens (5 pages, written by that script) and",
           "-- tests/fixtures/locked.pdf (its password is secret), as base64 text cut into",
           "-- constants of %d characters, and the one function that joins them." % CHUNK]
    names = {}
    for name, make in (("Sample", sample), ("Locked", locked)):
        text = base64.b64encode(make()).decode("ascii")
        names[name] = []
        for i in range(0, len(text), CHUNK):
            constant = "kPv%s%d" % (name, i // CHUNK + 1)
            names[name].append(constant)
            out.append('constant %s = "%s"' % (constant, text[i:i + CHUNK]))
    out += ["",
            "-- The base64 of a sample: pWhich is \"locked\" for the locked page, anything",
            "-- else for the guide.",
            "function pvSampleBase64 pWhich",
            '   if pWhich is "locked" then',
            "      return " + " & ".join(names["Locked"]),
            "   end if",
            "   return " + " & ".join(names["Sample"]),
            "end pvSampleBase64",
            END]
    return "\n".join(out) + "\n"


def with_demo_block(text):
    """The demo's text with its block as this script writes it, or None when
    the two marker lines are not there exactly once each, in order."""
    lines = text.splitlines(True)
    starts = [i for i, line in enumerate(lines) if line.startswith(BEGIN)]
    ends = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == END]
    if len(starts) != 1 or len(ends) != 1 or ends[0] < starts[0]:
        return None
    return "".join(lines[:starts[0]]) + demo_block() + "".join(lines[ends[0] + 1:])


def main(argv, root=ROOT):
    check = "--check" in argv
    bad = 0
    for name, make in sorted(FILES.items()):
        data = make()
        path = os.path.join(root, name)
        if check:
            try:
                with open(path, "rb") as f:
                    have = f.read()
            except OSError:
                have = None
            if have != data:
                print("build-test-pdfs: %s is not what this script writes "
                      "(run tools/build-test-pdfs.py)" % name)
                bad = 1
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("build-test-pdfs: wrote %s (%d bytes)" % (name, len(data)))
    path = os.path.join(root, DEMO)
    try:
        with open(path, encoding="ascii", newline="") as f:
            have = f.read()
    except (OSError, UnicodeDecodeError) as e:
        print("build-test-pdfs: cannot read %s (%s)" % (DEMO, e))
        return 1
    want = with_demo_block(have)
    if want is None:
        print("build-test-pdfs: %s needs one line beginning %r and, after it, one line %r"
              % (DEMO, BEGIN, END))
        return 1
    if check:
        if have != want:
            print("build-test-pdfs: the sample block of %s is not what this script writes "
                  "(run tools/build-test-pdfs.py)" % DEMO)
            bad = 1
    elif have != want:
        with open(path, "w", encoding="ascii", newline="") as f:
            f.write(want)
        print("build-test-pdfs: wrote the sample block of %s" % DEMO)
    if check and not bad:
        print("build-test-pdfs: OK (%d files and the demo's sample block match what this "
              "script writes)" % len(FILES))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
