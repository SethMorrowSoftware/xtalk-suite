## Summary

<!-- What does this change do, and why? Which members does it touch? -->

## Linked issue

<!-- For example "Fixes #123". Write "None" if there is no issue. -->

## How was it tested?

- [ ] `bash tools/build-all.sh --gates` passes
- [ ] The touched members' `tools/run-gates.sh` pass
- [ ] A shim change: the member's smoke test under ASan/UBSan
- [ ] A script-layer change: every carrier regenerated (`tools/build-suite-selftest.py` and `tools/sync-demo-embeds.py`)
- [ ] Run on a real engine (say which IDE, version, platform and 32- or 64-bit, and what passed); otherwise the docs say "verified statically; needs an OXT pass"

## Checklist

- [ ] I agree that this contribution is licensed under the MIT licence
- [ ] No public handler is renamed or removed, and no handler returns something different for an input that worked before (or the new behaviour is opt-in and described above)
- [ ] Masters edited, not copies (see the carried-blocks table in CLAUDE.md)
- [ ] Committed binaries refreshed with any native-library change, or left for the `release-binaries` dispatch
