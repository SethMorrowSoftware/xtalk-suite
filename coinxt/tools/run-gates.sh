#!/usr/bin/env bash
# run-gates.sh - coinxt's OWN gate list: what CI and a contributor run.
# Compiler-free EXCEPT coin-kat.py, which builds the shim from the vendored
# source in a temp dir and drives it through ctypes (a C compiler; never an
# engine). The three wallet gates take HOURS - see their block for why they
# run at once.
#
# ONE LIST. The suite's tools/build-all.sh delegates to this script rather
# than carrying a probe-by-filename copy of it, so a gate runs in the suite
# and standalone alike - or nowhere. Any gate file added under tools/ or
# tests/ MUST be named here: the suite's tools/check-member-standalone.py
# refuses a gate file this script never names. A tool nobody invokes is the
# rot the suite root records more than once; this list is where that is kept
# out of this member.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. The banners match build-all.sh's, so
# a log reads the same whichever ran the walk. Nothing is probed with
# `[ -f ]` - the member knows what it ships, and a probe that finds nothing
# prints OK over a gate that has gone missing.
#
# Runs from anywhere: every gate runs from the member root.
#
# CROSS-MEMBER GATE. tools/check-wallet-boot.py boots the shipped wallet
# stack over riptide's engine object model: it IMPORTS
# ../riptide/tools/check-demo-boot.py rather than copying it (one boot
# runner, one interpreter - it refuses to run if this member's lcs-interp.py
# and the one riptide's runner loaded are not byte-identical), and that
# runner loads at import, through riptide's oracle, ../nostrxt/tools/
# nostr_reference.py. tools/test-wallet-boot.py drives the same gate, so it
# inherits the reach. Once each member is its own repository the sibling is
# not in this tree: the gate resolves it as ../<name> beside this checkout
# (its MEMBER name: riptide, nostrxt), overridable with XTALK_SIBLINGS=<dir>
# (a directory holding the sibling checkouts) or XTALK_SIBLING_<NAME>=<path>
# (one sibling, e.g. XTALK_SIBLING_RIPTIDE). An absent sibling is a FAILURE
# here, not a skip - nothing in this list runs a reduced tier without it -
# reported by the gate that needs it, naming the path, the repository to
# clone and the two variables, never a traceback (an absent riptide is exit
# 2: a setup problem, not a boot failure). XTALK_REQUIRE_SIBLINGS=1 is the
# CI knob that turns the skip-capable gates' skips (nostrxt's tier 2,
# riptide's native signing tier) into failures, because a skip and a pass
# both exit 0; the generated gates.yml sets it for every member so one rule
# holds, and it changes nothing here. See the suite's
# docs/MEMBER-REPO-SPLIT.md.
#
# COINXT_REQUIRE_CROSSCHECK is the same shape, one gate over: coin-kat.py
# and check-selftest-vectors.py cross-check the curve vectors against an
# INDEPENDENT implementation (the `ecdsa` package, the project rule
# "cross-checked against an independent implementation before pinning"
# enforced continuously rather than once) and SKIP without it - right for a
# contributor who has not installed an optional package, wrong for CI, where
# "the cross-library check silently did not run" and "it passed" print
# almost the same thing and exit 0 either way. The suite's suite-gates.yml
# runs `pip install ecdsa` and sets COINXT_REQUIRE_CROSSCHECK=1 so the skip
# is a failure there: deleting that install can never quietly downgrade the
# gate to the weaker same-repo comparison.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy).
echo "== coinxt: static gate =="
python3 tools/check-livecodescript.py

# The house-style docs gate.
echo "== coinxt: docs-style gate =="
python3 tools/check-docs-style.py

# Known-answer-vector harness: builds the shim from the vendored source in a
# temp dir and drives it via ctypes against PUBLIC vectors (the whole hash
# surface, secp256k1, RFC 6979, what verification must REJECT, ...). Needs a
# C compiler; honours COINXT_REQUIRE_CROSSCHECK (header). --check is the
# terse form: one OK line or a non-zero exit.
echo "== coinxt: tools/coin-kat.py --check =="
python3 tools/coin-kat.py --check

# The OXT self-test's vectors are hand-copied literals in a .livecodescript,
# so they can drift from the shim and from the published answers. A drifted
# expectation turns a real regression into a green run, which in a money
# library is the worst possible failure mode - so re-derive them on every
# push. Needs no compiler, unlike coin-kat.py above. Fails on any k*
# constant that is neither re-derived nor listed as an input with a reason
# and reports the honest split, because its first version printed the
# constants it had PARSED as the ones it had CHECKED.
echo "== coinxt: tools/check-selftest-vectors.py =="
python3 tools/check-selftest-vectors.py --check

# The wallet's UI version must FOLLOW its builder: coin-wallet rebuilds its
# window only when kWaUiVersion changes, and a week of new controls shipped
# under a constant nobody bumped, so no existing stack ever built them
# (2026-09-04). The constant is a fingerprint of the waBuild* handlers now,
# and this refuses a stale one (--fix writes the right value).
echo "== coinxt: tools/check-wallet-ui-version.py =="
python3 tools/check-wallet-ui-version.py

# The pure-SCRIPT encoding layer, actually executed. OXT cannot run a
# .livecodescript headlessly, so this member carries a small interpreter
# (tools/lcs-interp.py) for the subset its encoders are written in and
# drives the real file against the published BIP-173 / BIP-350 / EIP-55 /
# RLP vectors. It is an approximation of the engine and does not replace the
# on-engine pass; what it catches is a wrong alphabet or an inverted
# checksum, which on this surface would produce a valid-looking WRONG
# address. Slow by nature (every bit of the bech32 checksum is interpreted
# arithmetic), so it runs after the fast gates.
echo "== coinxt: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py --check

# The WALLET engine, same machinery one layer up: examples/
# wallet-core.livecodescript is what coin-wallet is built out of, and every
# byte layout in it (scripts, addresses, extended keys, fees, coin
# selection, sighashes, witnesses, PSBT, signed messages, URIs, descriptors,
# QR) is compared against tools/wallet_reference.py, an independent
# implementation anchored to the published vectors, with the real shim
# signing. A wrong length prefix there produces a transaction that parses
# and pays somebody else. Slower still than the gate above.
# And the layer ABOVE that one: check-wallet-boot BOOTS the shipped wallet
# stack, headlessly, over riptide's engine object model (imported, not
# copied - the cross-member reach in the header) with the COMMITTED CoinXT
# under it. The vector gate never opens a window, so until this landed the
# ten screens, the show/hide sweep, the click router and the wallet file
# were verified only by reading them - this member's own recorded failure
# shape, one layer up.
# THE FIXTURES FIRST, per the fixture-before-gate law: a boot runner that
# has gone blind reports OK, and the seeded defects are what make the OK
# mean anything. They boot a cut-down copy.
#
# THE THREE WALLET GATES RUN AT ONCE (2026-09-11), and their verdicts are
# READ in the order above. Each is a separate interpreter over the same
# unchanged tree, so they share nothing but the CPU; run one after another
# they were the static-gates job's whole afternoon - measured, 44 minutes of
# vectors, then 2 h 20 of boot fixtures (two of the seven are caught late in
# the boot and cost ~37 min each), then the prefill-20 boot on top - against
# GitHub's six-hour job ceiling, which the 4 h 49 m gates step of main's
# last green run was closing on. The output of each is held in a file and
# printed under its own banner once all three are in, fixtures before gate,
# so the log reads exactly as the serial walk did and a blind runner is
# still the first thing on the page. Any one failing fails the walk after
# all three have reported.
wallet_jobs=()
wallet_start() {
  local label="$1"; shift
  local log
  log="$(mktemp)"
  echo "== coinxt: $label == (running alongside the other wallet gates; output below)"
  ( "$@" ) > "$log" 2>&1 &
  wallet_jobs+=("$label|$!|$log")
}
wallet_start "tools/check-wallet-vectors.py" python3 tools/check-wallet-vectors.py --check
wallet_start "tools/test-wallet-boot.py" python3 tools/test-wallet-boot.py
wallet_start "tools/check-wallet-boot.py" python3 tools/check-wallet-boot.py --terse
wallet_failed=0
# ${arr[@]+"${arr[@]}"}: the set -u-safe array expansion (never empty here;
# the spelling is the suite's, and the plain form is an unbound-variable
# error under set -u on an empty array).
for wallet_job in ${wallet_jobs[@]+"${wallet_jobs[@]}"}; do
  wallet_label="${wallet_job%%|*}"
  wallet_rest="${wallet_job#*|}"
  wallet_pid="${wallet_rest%%|*}"
  wallet_log="${wallet_rest#*|}"
  wallet_rc=0
  wait "$wallet_pid" || wallet_rc=$?
  echo "== coinxt: $wallet_label == (exit $wallet_rc)"
  cat "$wallet_log"
  rm -f "$wallet_log"
  if [ "$wallet_rc" -ne 0 ]; then
    wallet_failed=1
  fi
done
if [ "$wallet_failed" -ne 0 ]; then
  echo "coinxt: a wallet gate failed (its output is above)"
  exit 1
fi

# Do the docs and the shipped handler set still agree? A `cx*` name in the
# docs that no handler defines costs a reader a `handler not found`, and
# every other gate stays green about it: SPEC.md named `cxSeckeyValidate`
# where the shipped handler is `cxSeckeyIsValid`, in the one document this
# member calls its source of truth. Holds BOTH directions - a documented
# name nothing defines, and a shipped public handler the api-reference never
# names - with a stale-excuse ratchet, so a rename cannot leave a permanent
# exemption behind it.
echo "== coinxt: tools/check-doc-handlers.py =="
python3 tools/check-doc-handlers.py --check

# Committed-binary FRESHNESS (distinct from the manifests below, which prove
# a committed blob is unchanged but say nothing about whether it still
# matches the source). The automated half of suite rule 5: a shim that
# gained, lost or renamed an export, or bumped its ABI, without its committed
# library being rebuilt in the same change. This member's own copy; no
# compiler and no binutils, stdlib struct walks over the binaries.
echo "== coinxt: tools/check-binary-freshness.py =="
python3 tools/check-binary-freshness.py

# Committed-binary / vendored-source integrity manifests: a committed blob
# that is unlisted or does not match its recorded SHA256 fails the gate.
echo "== coinxt: src/code/MANIFEST.sha256 =="
( cd src/code && sha256sum -c --quiet MANIFEST.sha256 )
echo "== coinxt: native/MANIFEST.sha256 =="
( cd native && sha256sum -c --quiet MANIFEST.sha256 )
