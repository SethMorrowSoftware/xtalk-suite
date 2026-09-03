#!/usr/bin/env python3
"""check-wallet-ui-version: the wallet's UI version must FOLLOW its builder.

coin-wallet rebuilds its window only when kWaUiVersion differs from the
version the stack last built (waBuild: "if the uUiVersion of this stack is
kWaUiVersion then exit"). That is what makes a reopened stack open instantly,
and it is also how every control added between 2026-09-02 and 2026-09-04
(a BIP-322 checkbox, the Inscribe and Lock buttons, the label export and
import buttons, Update from main, the testnet4 button) failed to appear in
any stack that already existed: the constant read "coinwallet-1" from the
day the wallet was written, so an updated or reopened stack kept the window
it had and only a fresh paste built the new one. A hand-bumped version is a
hand-copied number, and this member's own record says what happens to those.

So the version is DERIVED: kWaUiVersion must equal "ui-" plus the first
twelve hex digits of the SHA-256 over the text of every `command waBuild*`
handler in the shipped wallet, in file order, which is exactly the text that
decides what the window holds. Editing a builder changes the fingerprint;
this gate refuses the stale constant and prints the right one; `--fix`
writes it. An updated stack then rebuilds because the constant it carries
is not the one it stored, with no one remembering to bump anything.

Usage:  python3 tools/check-wallet-ui-version.py [--fix]
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WALLET = os.path.join(os.path.dirname(HERE), "examples", "coin-wallet.livecodescript")
PATTERN = re.compile(r"^(?:private )?command (waBuild\w*)\b.*?^end \1\s*$", re.M | re.S)
CONST = re.compile(r'^constant kWaUiVersion = "([^"]*)"$', re.M)


def fingerprint(text):
    bodies = PATTERN.findall(text)
    if len(bodies) < 5:
        return None, 0
    # findall returns the group; take the whole match text instead
    whole = [m.group(0) for m in PATTERN.finditer(text)]
    digest = hashlib.sha256("\n".join(whole).encode("utf-8")).hexdigest()[:12]
    return "ui-" + digest, len(whole)


def main(argv):
    fix = "--fix" in argv[1:]
    text = open(WALLET, encoding="utf-8").read()
    want, count = fingerprint(text)
    if want is None:
        print("check-wallet-ui-version: FAILED - found fewer than five waBuild* "
              "handlers, which is not this wallet")
        return 1
    m = CONST.search(text)
    if not m:
        print("check-wallet-ui-version: FAILED - no `constant kWaUiVersion = \"...\"` line")
        return 1
    have = m.group(1)
    if have == want:
        print("check-wallet-ui-version: OK (kWaUiVersion %s follows %d waBuild* handler(s))"
              % (want, count))
        return 0
    if fix:
        text = text[:m.start(1)] + want + text[m.end(1):]
        open(WALLET, "w", encoding="utf-8").write(text)
        print("check-wallet-ui-version: wrote kWaUiVersion %s (was %s) over %d waBuild* handler(s)"
              % (want, have, count))
        return 0
    print("check-wallet-ui-version: FAILED - kWaUiVersion is %s but the %d waBuild* "
          "handlers fingerprint to %s. A window built under the old value would "
          "never gain what the builder now makes. Run with --fix." % (have, count, want))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
