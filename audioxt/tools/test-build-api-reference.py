#!/usr/bin/env python3
"""test-build-api-reference.py - prove tools/build-api-reference.py keeps
what the doc blocks say.

The page's --check gate compares docs/api-reference.md with the generator's
own output, so it cannot see text the generator drops: until 2026-11-21 a
blank line ended every element, and each Description paragraph after the
first never reached the page (auEngineCreate's web note and silent device,
auCaptureOpen's permissions). This test holds the generator to its input:

  - on a hand-made block: every Description paragraph is kept, in order,
    as its own paragraph; a blank line still ends a parameter, the Summary
    and the Returns (a stray line after one is not glued onto it); an
    Example keeps its lines;
  - on the REAL binding, as the build runs it: every word of every
    Description in src/audioxt.lcb is on the page, paragraph by paragraph.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "aux_api_reference", os.path.join(HERE, "tools", "build-api-reference.py"))
GEN = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GEN)

failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else " - " + detail))
    if not ok:
        failures.append(name)


BLOCK = """Summary: Does one thing.

pFirst: The first, which
goes on a second line.

stray after a parameter

Returns: A number.

stray after Returns

Example:
put one() into x
put two() into y

Description: The first paragraph,
on two lines.

The second paragraph.

The third <auOther> paragraph."""

elements, params = GEN.parse_block(BLOCK)
check("the Summary is kept, and ends at its blank line", elements.get("Summary") == "Does one thing.",
      repr(elements.get("Summary")))
check("a parameter joins its lines and ends at its blank line",
      params == [["pFirst", "The first, which goes on a second line."]], repr(params))
check("the Returns ends at its blank line", elements.get("Returns") == "A number.", repr(elements.get("Returns")))
check("an Example keeps its lines", elements.get("Example") == "put one() into x\nput two() into y",
      repr(elements.get("Example")))
check("every Description paragraph is kept, in order, each its own",
      elements.get("Description") == "The first paragraph, on two lines.\n\nThe second paragraph.\n\n"
                                     "The third <auOther> paragraph.", repr(elements.get("Description")))

page = GEN.render("/**\n" + BLOCK + "\n*/\npublic handler auOne() returns Integer\n")
check("the page shows each paragraph apart, links as code",
      "The first paragraph, on two lines.\n\nThe second paragraph.\n\nThe third `auOther` paragraph.\n" in page,
      page)

# The real binding, through the generator as the build runs it.
source = open(os.path.join(HERE, "src", "audioxt.lcb"), encoding="utf-8").read()
page = GEN.render(source)
flat = re.sub(r"\s+", " ", page)
blocks = re.findall(r"^/\*\*\n(.*?)^\*/\npublic handler", source, re.S | re.M)
described = paragraphs = 0
missing = []
for block in blocks:
    if "\nDescription:" not in "\n" + block:
        continue
    described += 1
    text = re.split(r"(?m)^Description:", block, maxsplit=1)[1]
    for para in re.split(r"\n\s*\n", text.strip()):
        words = re.sub(r"\s+", " ", GEN.plain(para)).strip()
        if not words:
            continue
        paragraphs += 1
        if words not in flat:
            missing.append(words[:70])
check("the real binding has a Description of several paragraphs (else this proves little)",
      described > 0 and paragraphs > described, "%d paragraphs in %d Descriptions" % (paragraphs, described))
check("every Description paragraph of src/audioxt.lcb is on the page", not missing,
      "%d missing, first: %r" % (len(missing), missing[:1]))

print("test-build-api-reference: %d failed" % len(failures))
sys.exit(1 if failures else 0)
