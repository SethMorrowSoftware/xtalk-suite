#!/usr/bin/env python3
"""check-record-registry.py - prove the LCB record constants cannot drift from
the C++ registry ("a single fieldId registry ... so the shim writer and the
LCB walker cannot drift" - the family rule, carried from TorrentXT).

src/dcx_record.h is the SINGLE SOURCE OF TRUTH for five enums:
    FieldType      (FT_*)  -> LCB constant  kType<Name>
    FieldId        (F_*)   -> LCB constant  kField<Name>
    EventType      (E_*)   -> LCB constant  kEvent<Name>
    PeerState      (PS_*)  -> LCB constant  kPeerState<Name>
    GatheringState (GS_*)  -> LCB constant  kGathering<Name>

The LCB name is derived mechanically from the C++ name, so this checker catches
a missing constant, a wrong value, AND a value swap (because each LCB constant's
expected value is tied to its specific C++ enumerator by name). Every enumerator
in the header must have a matching `constant k... is <value>` in
src/datachannel.lcb. It ALSO asserts DCX_ABI_VERSION (dcx_abi.h) equals
kABIVersion (the .lcb) - the ABI-sync gate - and PINS the return codes
(DCX_OK / the six DCX_ERR_*) to their published numbering.

    python3 tools/check-record-registry.py [path/to/dcx_record.h] [path/to/datachannel.lcb]

Exit 0 = in sync (or datachannel.lcb not written yet -> skip), 1 = drift found.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def camel(name_after_prefix):
    """TOKEN_TOKEN -> TokenToken (each token: first char upper, rest lower)."""
    parts = name_after_prefix.split("_")
    return "".join(p[:1].upper() + p[1:].lower() for p in parts if p)


# (C++ prefix, LCB prefix) for the five registries. ORDER MATTERS in the
# matcher below: a prefix must not swallow a longer one (F_ vs FT_ is handled
# by the regex requiring the whole enumerator name to start with the prefix
# and the next char to be part of the name, so FT_INT never parses as F_T...).
REGISTRIES = [
    ("FT_", "kType"),
    ("F_", "kField"),
    ("E_", "kEvent"),
    ("PS_", "kPeerState"),
    ("GS_", "kGathering"),
]


def parse_header_enum(text, cpp_prefix):
    """Return {cpp_name: value} for every `PREFIX_NAME = N` in the header.
    The F_ registry must not swallow FT_ enumerators: an F_ match whose name
    also matches a LONGER registered prefix is skipped."""
    longer = [p for p, _ in REGISTRIES if p != cpp_prefix and p.startswith(cpp_prefix)]
    out = {}
    pat = re.compile(r"\b(" + re.escape(cpp_prefix) + r"[A-Z0-9_]+)\s*=\s*(\d+)")
    for m in pat.finditer(text):
        name = m.group(1)
        if any(name.startswith(lp) for lp in longer):
            continue
        out[name] = int(m.group(2))
    return out


def parse_lcb_constants(text):
    """Return {kName: value} for every `constant kName is <int>` in the .lcb.
    The sign is part of the value: kErrInvalidArg is -3, and a parser that
    matched only digits would read it as 3 and then agree with a header that
    said -3."""
    out = {}
    for m in re.finditer(r"\bconstant\s+(k[A-Za-z0-9_]+)\s+is\s+(-?\d+)\b", text):
        out[m.group(1)] = int(m.group(2))
    return out


# The action return codes, pinned by VALUE rather than merely parsed. Three
# things depend on this exact numbering and none of them can be checked by
# reading the header:
#   * tests/datachannel-selftest.livecodescript asserts `is -2` (and, in the
#     async half, `is -4`) as bare literals - a renumber would turn a green
#     harness red, or worse, green about the wrong condition;
#   * docs/api-reference.md publishes the list in prose at the top of the file;
#   * datachannel.lcb now RETURNS one of them on its own - kErrInvalidArg, for
#     the embedded-NUL refusal in dcSendText that the shim cannot make,
#     because by the time the string is a `const char *` the NUL IS its
#     terminator.
# Renumbering these is an ABI change like any other; this is the gate that
# says so out loud instead of letting a harness discover it on an engine.
DCX_RETURN_CODES = {
    "DCX_OK": 0,
    "DCX_ERR_GENERIC": -1,
    "DCX_ERR_BAD_HANDLE": -2,
    "DCX_ERR_INVALID_ARG": -3,
    "DCX_ERR_TOO_LARGE": -4,
    "DCX_ERR_NATIVE": -5,
    "DCX_ERR_EXCEPTION": -6,
}

# The .lcb declares only the code it issues ITSELF; the rest reach script
# straight from the shim and never need a name here. Kept as a mapping so
# adding a second one is one line, not a new check.
LCB_RETURN_CODE_CONSTANTS = {
    "kErrInvalidArg": "DCX_ERR_INVALID_ARG",
}


def check_return_codes(abi_text, lcb_consts, problems):
    """Pin DCX_OK / DCX_ERR_* to DCX_RETURN_CODES, and the .lcb mirrors of
    them to the header. Returns the number of things actually CHECKED - the
    count reports what was verified, not what was parsed (the coinxt lesson: a
    gate that overstates its coverage answers the question nobody asks
    twice)."""
    found = {}
    for m in re.finditer(r"\b(DCX_OK|DCX_ERR_[A-Z_]+)\s*=\s*(-?\d+)", abi_text):
        found[m.group(1)] = int(m.group(2))
    checked = 0
    for name, value in sorted(DCX_RETURN_CODES.items(), key=lambda kv: -kv[1]):
        if name not in found:
            problems.append("missing return code `%s` in src/dcx_abi.h "
                            "(expected %d)" % (name, value))
            continue
        checked += 1
        if found[name] != value:
            problems.append("return-code drift: dcx_abi.h %s = %d but the "
                            "published contract is %d" % (name, found[name], value))
    for extra in sorted(set(found) - set(DCX_RETURN_CODES)):
        problems.append("unpinned return code `%s = %d` in src/dcx_abi.h - add "
                        "it to DCX_RETURN_CODES here (and to the list at the "
                        "top of docs/api-reference.md)" % (extra, found[extra]))
    for lcb_name, cpp_name in sorted(LCB_RETURN_CODE_CONSTANTS.items()):
        if lcb_name not in lcb_consts:
            problems.append("missing LCB constant `%s` (for C++ %s) - "
                            "datachannel.lcb returns that code itself"
                            % (lcb_name, cpp_name))
            continue
        checked += 1
        if lcb_consts[lcb_name] != DCX_RETURN_CODES[cpp_name]:
            problems.append("value drift: LCB `%s` is %d but %s = %d"
                            % (lcb_name, lcb_consts[lcb_name], cpp_name,
                               DCX_RETURN_CODES[cpp_name]))
    return checked


def parse_abi_version(path):
    """Return the int N from `#define DCX_ABI_VERSION N`, or None if unreadable."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return None
    m = re.search(r"#define\s+DCX_ABI_VERSION\s+(\d+)", text)
    return int(m.group(1)) if m else None


def main(argv):
    header = argv[1] if len(argv) > 1 else os.path.join(HERE, "src", "dcx_record.h")
    lcb = argv[2] if len(argv) > 2 else os.path.join(HERE, "src", "datachannel.lcb")

    with open(header, "r", encoding="utf-8") as f:
        htext = f.read()

    if not os.path.exists(lcb):
        print("check-record-registry: %s not written yet - skipping (will enforce once it exists)"
              % os.path.relpath(lcb, HERE))
        return 0

    with open(lcb, "r", encoding="utf-8") as f:
        ltext = f.read()
    lcb_consts = parse_lcb_constants(ltext)

    problems = []
    checked = 0

    # The ABI version must match between dcx_abi.h (#define DCX_ABI_VERSION)
    # and datachannel.lcb (constant kABIVersion) - a skew makes _checkABI()
    # throw at runtime, and a forgotten bump is an easy mistake. Catch it here.
    abi_h = parse_abi_version(os.path.join(HERE, "src", "dcx_abi.h"))
    abi_lcb = lcb_consts.get("kABIVersion")
    if abi_h is None:
        problems.append("could not read DCX_ABI_VERSION from src/dcx_abi.h")
    elif abi_lcb is None:
        problems.append("missing `constant kABIVersion` in datachannel.lcb")
    elif abi_h != abi_lcb:
        problems.append("ABI version skew: dcx_abi.h DCX_ABI_VERSION=%d but "
                        "datachannel.lcb kABIVersion=%d" % (abi_h, abi_lcb))
    else:
        checked += 1

    for cpp_prefix, lcb_prefix in REGISTRIES:
        header_enum = parse_header_enum(htext, cpp_prefix)
        if not header_enum:
            problems.append("no `%s*` enumerators found in %s" % (cpp_prefix, header))
        for cpp_name, value in sorted(header_enum.items(), key=lambda kv: kv[1]):
            expected = lcb_prefix + camel(cpp_name[len(cpp_prefix):])
            checked += 1
            if expected not in lcb_consts:
                problems.append("missing LCB constant `%s` (for C++ %s = %d)"
                                % (expected, cpp_name, value))
            elif lcb_consts[expected] != value:
                problems.append("value drift: LCB `%s` is %d but C++ %s = %d"
                                % (expected, lcb_consts[expected], cpp_name, value))

    # DCX_MAX_MESSAGE (dcx_abi.h) must equal kMaxMessage (the .lcb) - the
    # documented size budget is part of the contract, not folklore. The same
    # header read serves the return-code pin below it.
    abi_text = open(os.path.join(HERE, "src", "dcx_abi.h"), encoding="utf-8").read()
    m = re.search(r"#define\s+DCX_MAX_MESSAGE\s+(\d+)", abi_text)
    if not m:
        problems.append("could not read DCX_MAX_MESSAGE from src/dcx_abi.h")
    elif lcb_consts.get("kMaxMessage") != int(m.group(1)):
        problems.append("size-budget drift: dcx_abi.h DCX_MAX_MESSAGE=%s but "
                        "datachannel.lcb kMaxMessage=%s"
                        % (m.group(1), lcb_consts.get("kMaxMessage")))
    else:
        checked += 1

    checked += check_return_codes(abi_text, lcb_consts, problems)

    if problems:
        for p in problems:
            print("DRIFT:", p)
        print("\n%d registry drift problem(s)" % len(problems))
        return 1
    print("check-record-registry: %d constants in sync between dcx_record.h and datachannel.lcb"
          % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
