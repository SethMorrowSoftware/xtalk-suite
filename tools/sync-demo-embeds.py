#!/usr/bin/env python3
"""sync-demo-embeds.py - every demo carries the script libraries it needs.

WHY THIS EXISTS
    A demo that requires `start using stack "coinxt"` before it will run is a
    demo most people meet as an error message. The libraries are pure script,
    so there is no reason a reader should have to wire them up by hand just to
    look at the thing: paste the demo into a stack script, open it, and it
    works. That is the whole goal - one file per demo, no wiring.

    The pieces stay usable both ways. `<member>/src/*.livecodescript` remains
    the single source of truth and the right dependency for a real project;
    this tool copies it into each demo between sentinels so the SHIPPED demo is
    self-contained. Nobody hand-edits inside the sentinels, and `--check` fails
    the build when a copy drifts from its source - the same contract
    box2dxt/tools/sync-embedded-kit.py has for the embedded b2k Kit and
    tools/build-suite-selftest.py has for the folded suite harness. It also
    REPLACED onionxt/tools/build-standalone.py, which used to emit generated
    `*-standalone` twins beside their sources; embedding in place means there is
    one file to open rather than a source and a launchable copy of it.

ORDER IS LOAD-BEARING, NOT COSMETIC
    The embedded block goes ABOVE the demo's own code, and the providers go in
    dependency order within it. OXT resolves script-level `constant` and
    `local` names by LEXICAL POSITION - the root CLAUDE.md records a fold that
    put 106 declarations below their first reader and produced a tidy wrong
    answer rather than an error, because LiveCodeScript evaluates an undeclared
    name as the literal text of its own name. Libraries first is what keeps
    that from happening here.

COLLISIONS ARE REFUSED, NEVER MERGED
    If a demo and a library define the same handler, or the same column-0
    declaration, the merged script would not compile - and the maintainer would
    meet that at PASTE TIME on an engine, which is the scarce resource this
    whole tree is organised around protecting. So this tool refuses to write,
    names both sides, and stops.

    One real collision is known and deliberately NOT worked around here:
    torrentxt/examples/torrent-quickshare.livecodescript defines
    socketError/socketClosed/socketTimeout with genuine clearweb-server logic
    that `pass`es everything else through to OnionXT's copies. Those are not
    pass-through stubs that can be dropped, and merging two real bodies is a
    behaviour change to an unverified inbound path, not a packaging change. It
    is recorded in the registry below with its reason instead of being forced.

THE BANNER DELIBERATELY AVOIDS ONE PHRASE
    tools/check-ui-kit-drift.py and tools/check-harness-scaffold-drift.py both
    SKIP any file whose first 4000 characters contain "GENERATED - do not
    edit". These demos are only PARTLY generated - the region between the
    sentinels - so bannering them with that phrase would silently switch off
    UI-kit drift checking for every demo this tool touches. The header below
    says the same thing in words that do not trip that test, and this paragraph
    exists so nobody "tidies" it back.

USAGE
    python3 tools/sync-demo-embeds.py            # write every embed
    python3 tools/sync-demo-embeds.py --check    # verify the committed copies
    Exit 0 when clean, 1 when a copy is stale or a collision is found.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BEGIN = "-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>"
END = "-- <<< END EMBEDDED LIBRARIES <<<"

# demo -> the libraries it needs, IN DEPENDENCY ORDER (a library that uses
# another must come after it).
REGISTRY = {
    "coinxt/examples/coinxt-demo.livecodescript": [
        "coinxt/src/coinxt.livecodescript"],
    "enetxt/examples/enet-lan-chat.livecodescript": [
        "enetxt/examples/enet-helpers.livecodescript"],
    # The internet chat carries BOTH poll dispatchers: enet-helpers pumps the
    # chat transport, torrent-helpers pumps the TorrentXT session whose only
    # jobs are the router mapping (btMapPort) and public-IP discovery (the
    # externalIp event). The two layers' names are held disjoint by
    # check-cross-library-names, which is what makes this co-embed legal.
    "enetxt/examples/enet-internet-chat.livecodescript": [
        "enetxt/examples/enet-helpers.livecodescript",
        "torrentxt/examples/torrent-helpers.livecodescript"],
    "datachannelxt/examples/datachannel-loopback.livecodescript": [
        "datachannelxt/examples/datachannel-helpers.livecodescript"],
    "datachannelxt/examples/datachannel-dht-chat.livecodescript": [
        "datachannelxt/examples/datachannel-helpers.livecodescript"],
    # The demo carries its own self-test harness too, because the About tab
    # runs it - this is exactly what the retired onionxt-demo-standalone.
    # livecodescript used to bundle, now folded into the demo itself so there
    # is ONE onionxt demo file rather than a source and a generated twin.
    "onionxt/examples/onionxt-demo.livecodescript": [
        "onionxt/src/onionxt.livecodescript",
        "onionxt/src/onion-httpd.livecodescript",
        "onionxt/examples/onionxt-tests.livecodescript"],
    "onionxt/examples/onion-httpd/spike.livecodescript": [
        "onionxt/src/onionxt.livecodescript",
        "onionxt/src/onion-httpd.livecodescript"],
    "torrentxt/examples/torrent-dht-channels.livecodescript": [
        "onionxt/src/onionxt.livecodescript"],
    # Both of these are offered by the launcher, so a reader can pick them and
    # meet the same wiring error the demos used to give. coin-selftest is also
    # FOLDED into the suite paste, which already embeds coinxt once as a script
    # layer - so build-suite-selftest.py cuts this copy back out (strip_spans on
    # the coin row), exactly as it does for box2dxt's embedded Kit. Without that
    # cut the paste would define every cx* handler twice, and the maintainer
    # would meet it at paste time on an engine.
    "coinxt/tests/coin-selftest.livecodescript": [
        "coinxt/src/coinxt.livecodescript"],
    # The two POLL DISPATCHERS are shipped libraries that live under examples/,
    # which is why tools/check-suite-coverage.py could not see them: its enetxt
    # and datachannelxt rows scope to src/. Measured 2026-08-19, the suite paste
    # named ZERO of their 15 public handlers - the layer every demo drives, every
    # doc teaches, and this session edited twice. Carrying them into each
    # member's own harness is what lets that harness test them, and the fold
    # then prefixes both together so the paste tests them too.
    "enetxt/tests/enet-selftest.livecodescript": [
        "enetxt/examples/enet-helpers.livecodescript"],
    "datachannelxt/tests/datachannel-selftest.livecodescript": [
        "datachannelxt/examples/datachannel-helpers.livecodescript"],
    "tests/suite-closing-pass.livecodescript": [
        "onionxt/src/onionxt.livecodescript"],
    "riptide/examples/riptide-social.livecodescript": [
        "riptide/src/riptide.livecodescript",
        "onionxt/src/onionxt.livecodescript",
        "onionxt/src/onion-httpd.livecodescript"],
    # The nostrxt demo carries its harness for the self-test button (the
    # onionxt-demo precedent). Order is load-bearing: the relay layer calls
    # the core, and the harness calls both, so core -> relay -> tests. The
    # relay layer is the one that defines socketError/socketClosed/
    # socketTimeout, which is fine HERE (this demo embeds no other socket
    # library) and is exactly why it stays out of the suite paste.
    "nostrxt/examples/nostrxt-demo.livecodescript": [
        "nostrxt/src/nostrxt.livecodescript",
        "nostrxt/src/nostr-relay.livecodescript",
        "nostrxt/examples/nostrxt-tests.livecodescript"],
}

# Demos deliberately NOT embedded, each with the reason. An entry here is a
# standing admission, not a way to quiet the tool.
NOT_EMBEDDED = {
    "torrentxt/examples/torrent-quickshare.livecodescript":
        "defines socketError/socketClosed/socketTimeout with real clearweb "
        "logic that passes through to OnionXT's copies; embedding OnionXT "
        "would define all three twice. Merging two live bodies is a behaviour "
        "change to the inbound socket path, which has no engine pass yet "
        "(runbook S2). Keeps its optional `start using onionxt` for Tor.",
}

DEF = re.compile(r'^(?:private\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)', re.M)
DECL = re.compile(r'^(?:local|constant)\s+(.+)$', re.M)


def names(text):
    """Script-level handler and declaration names. Column 0 only: an indented
    `local` is a HANDLER local, scoped to its handler, and cannot collide.

    THE TRAILING COMMENT MUST COME OFF FIRST, and the first version of this
    function did not do it - so it was very nearly blind. It matched the
    declaration line, then required the remainder to be a bare identifier:

        local sPolling          -- "true" while the timer loop is armed

    fails that test on the comment, and nearly every declaration in this
    codebase carries one. Only `constant kFoo = "bar"` survived, because
    splitting on "=" happened to cut the comment off with the value. The
    result was a collision checker that reported CLEAN over a real duplicate
    and let it reach an engine, where it is a hard compile error:
    `name shadows another variable or constant near "sPolling"`.

    That is this session's own recurring failure - a gate that looks like it
    checks something and does not - built into the gate meant to prevent it.
    Comments off, then commas, then values."""
    handlers = set(DEF.findall(text))
    decls = set()
    for line in DECL.findall(text):
        line = line.split("--", 1)[0].split("#", 1)[0]
        # `=` BEFORE `,`, not after. `constant kDeck = "Ac,Ad,Ah"` splits on
        # commas into `Ad` and `Ah`, which look exactly like identifiers - a
        # tree-wide scan built the other way round reported holde-em as
        # declaring `Ac`, `bank` and `ante` several times each, in a file that
        # compiles clean and has run 538 checks green on an engine. Take the
        # left of the first `=` (the declared names), then split THAT on commas.
        line = line.split("=", 1)[0]
        for part in line.split(","):
            n = part.strip()
            if re.fullmatch(r"[A-Za-z_]\w*", n):
                decls.add(n)
    return handlers, decls


SCRIPT_HEADER = re.compile(r'^script\s+"[^"]*"[^\n]*\n', re.M)


def strip_script_header(text, rel):
    """Drop a provider's leading `script "Name"` line before embedding it.

    THE JUSTIFICATION IS STRUCTURAL, NOT EMPIRICAL - which is a correction to
    what this docstring said until 2026-08-19. A `script "..."` line is a
    stack-NAME marker, meaningful only when the file IS its own stack. Four of
    the six providers open with one - enet-helpers, datachannel-helpers, coinxt,
    riptide - and embedding them verbatim drops a SECOND marker into the middle
    of a demo that already carries its own on line 1, naming a stack that is not
    there. That is wrong on structure alone, whatever the engine does with it,
    which is why the strip is unconditional and build_block asserts below that
    none survived. Hygiene needs no engine pass to justify it.

    WHAT THIS DOCSTRING USED TO CLAIM, AND WHY IT DOES NOT ANY MORE. It opened
    "THIS IS THE BUG THAT SHIPPED AND CAME BACK FROM AN ENGINE (2026-08-17)"
    and read the engine's `Chunk: error in object expression` on
    `the number of keys of sPeers` as proof that everything below a second
    marker falls out of the demo's declaration scope. It was not proof of that.
    `keys` is not a chunk, so `the number of keys of X` fails whether or not X
    is declared: the same error recurred on the same line AFTER this function
    had stripped that demo's header (b9fa4b3) and went quiet only when the
    spelling was rewritten (61c14ea). See docs/OXT-ENGINE-NOTES.md 1.7 for the
    spelling and 1.1 for the scope claim, now filed INFERRED with nothing
    observed under it. The rule survives; the story behind it did not.

    The collision check could never have caught this either way: the two names
    do not clash, and nothing about them is a duplicate DEFINITION. It is a
    structural marker, not an identifier, which is why it needs its own rule."""
    stripped, n = SCRIPT_HEADER.subn("", text, count=1)
    if n and not SCRIPT_HEADER.match(text):
        # only strip it when it is genuinely the file's opening line
        return text
    return stripped


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def build_block(demo_rel, provider_rels, demo_text):
    """The embedded region, providers in order, collisions refused."""
    seen_h, seen_d = names(demo_text)
    # the demo's own names minus anything inside a previous embed
    out = [BEGIN,
           "-- Pasted from the sources below so this demo runs with NO `start",
           "-- using` wiring. Do not edit inside these sentinels: run",
           "-- `python3 tools/sync-demo-embeds.py` instead. The sources under",
           "-- src/ stay the single source of truth for real projects.",
           "--",
           "-- Libraries come FIRST because OXT resolves script-level constants",
           "-- and locals by lexical position.",
           ""]
    for rel in provider_rels:
        text = strip_script_header(read(rel), rel)
        ph, pd = names(text)
        clash_h, clash_d = seen_h & ph, seen_d & pd
        if clash_h or clash_d:
            raise SystemExit(
                f"sync-demo-embeds: {demo_rel} collides with {rel}\n"
                f"  handlers: {sorted(clash_h) or '-'}\n"
                f"  declarations: {sorted(clash_d) or '-'}\n"
                "  A merged script would not compile. Resolve the collision at "
                "the source, or record the demo in NOT_EMBEDDED with a reason.")
        seen_h |= ph
        seen_d |= pd
        out.append(f"-- ---- {rel} ----")
        out.append(text.rstrip("\n"))
        out.append("")
    out.append(END)
    block = "\n".join(out)
    stray = [ln for ln in block.split("\n") if re.match(r'^script\s+"', ln)]
    if stray:
        raise SystemExit(
            f"sync-demo-embeds: {demo_rel}: a provider's `script \"...\"` header "
            f"survived into the embed ({stray[0]!r}). A `script \"...\"` line "
            "names the stack the file IS, so a second one mid-file names a "
            "stack that is not there - see strip_script_header.")
    return block


def splice(demo_text, block):
    """Put the block above the demo's own CODE but below its own HEADER.

    Two things must stay on top and the first version of this got both wrong.
    A leading `script "Name"` line is not a comment, so a naive
    skip-while-comment stopped at line 1 and pushed the script name down past
    two hundred lines of library - five of the seven demos start that way.
    And the demo's header prose is what a reader opens the file for: burying
    it under an embedded library makes the file LESS readable, which is the
    opposite of the point.

    So: an optional leading `script "..."`, then the whole leading comment
    header, and the libraries go after that - purpose first, machinery second,
    demo code last."""
    if BEGIN in demo_text:
        start = demo_text.index(BEGIN)
        end = demo_text.index(END) + len(END)
        return demo_text[:start] + block + demo_text[end:]
    lines = demo_text.split("\n")
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and re.match(r'^script\s+"', lines[i]):
        i += 1
    while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("--")):
        i += 1
    head, tail = lines[:i], lines[i:]
    return "\n".join(head + ["", block, ""] + tail)


def main(argv):
    check = "--check" in argv
    stale, wrote = [], 0
    for demo_rel, provider_rels in sorted(REGISTRY.items()):
        demo_path = os.path.join(ROOT, demo_rel)
        current = read(demo_rel)
        # strip any existing embed before collision-checking, or the demo
        # appears to collide with the copy of the library it already carries.
        bare = current
        if BEGIN in bare:
            s, e = bare.index(BEGIN), bare.index(END) + len(END)
            bare = bare[:s] + bare[e:]
        block = build_block(demo_rel, provider_rels, bare)
        want = splice(current, block)
        if want == current:
            continue
        if check:
            stale.append(demo_rel)
        else:
            with open(demo_path, "w", encoding="utf-8") as fh:
                fh.write(want)
            wrote += 1
            print(f"sync-demo-embeds: wrote {demo_rel} "
                  f"({len(provider_rels)} librar{'y' if len(provider_rels)==1 else 'ies'})")
    if stale:
        for s in stale:
            print(f"sync-demo-embeds: {s} is STALE - run "
                  f"`python3 tools/sync-demo-embeds.py`")
        print(f"sync-demo-embeds: {len(stale)} demo(s) out of date")
        return 1
    total = len(REGISTRY)
    if check:
        print(f"sync-demo-embeds: OK ({total} demo(s) carry their libraries; "
              f"{len(NOT_EMBEDDED)} recorded as not embedded, with reasons)")
    elif not wrote:
        print(f"sync-demo-embeds: {total} demo(s) already up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
