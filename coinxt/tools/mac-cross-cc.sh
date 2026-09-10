#!/bin/sh
# mac-cross-cc.sh - a `cc` for cross-building coinxt's macOS slices on Linux.
#
# WHY THIS EXISTS. The release lane builds the universal dylib on a real Mac
# with Apple's ld64, which honours -exported_symbols_list; that is the only
# builder that had ever produced the committed universal-mac/coinxt.dylib.
# Cross-building here uses Zig's clang for the COMPILE (it ships macOS
# headers and libSystem stubs) - but Zig's own Mach-O linker IGNORES
# -exported_symbols_list without a word (measured 2026-09-10: 257 vendored
# names in the export trie) and refuses -exported_symbol outright. LLVM's
# ld64.lld takes the list and produces the same export trie ld64 does (44
# cnx_* names, nothing else - checked against the previous release-built
# dylib), so this wrapper compiles with Zig and LINKS with ld64.lld. build.sh
# is unchanged: it sees a `cc` that takes -c and -shared like any other.
#
#   MAC_ARCH=arm64  CC="sh tools/mac-cross-cc.sh" NM=llvm-nm-18 STRIP=llvm-strip-18 \
#       sh native/build.sh pack arm64-mac
#   MAC_ARCH=x86_64 CC="sh tools/mac-cross-cc.sh" ... sh native/build.sh pack x86_64-mac
#   llvm-lipo-18 -create src/code/arm64-mac/coinxt.dylib src/code/x86_64-mac/coinxt.dylib \
#       -output src/code/universal-mac/coinxt.dylib
#
# What this does NOT do: sign or notarize (neither does the release lane), or
# run the result - a cross-built dylib is verified by its export trie, its ABI
# constant and both slices being present (tools/check-binary-freshness.py at
# the suite root reads all three), never by execution. Both the release lane's
# dylib and this one are labelled the same way in coinxt's CLAUDE.md.
set -eu
arch="${MAC_ARCH:-arm64}"
zig="${ZIG:-python3 -m ziglang}"
ld64="${LD64:-ld64.lld-18}"
libsys="${MAC_LIBSYSTEM_DIR:-$(python3 -c 'import ziglang,os;print(os.path.join(os.path.dirname(ziglang.__file__),"lib","libc","darwin"))')}"
# Zig spells the Apple silicon target aarch64; ld64 and lipo spell it arm64.
case "$arch" in
  arm64) target="aarch64-macos" ;;
  *)     target="$arch-macos" ;;
esac
# one deployment floor on both halves, so the linker has nothing to warn about
minver="${MAC_MIN_VERSION:-11.0}"
# a link: -shared anywhere on the line
link=0
for a in "$@"; do [ "$a" = -shared ] && link=1; done
if [ "$link" = 0 ]; then
  exec $zig cc -target "$target" -mmacos-version-min="$minver" "$@"
fi
# translate the cc-style link line into an ld64 one
out=""; objs=""; exp=""
while [ $# -gt 0 ]; do
  case "$1" in
    -shared) ;;
    -o) out="$2"; shift ;;
    -Wl,-exported_symbols_list,*) exp="${1#-Wl,-exported_symbols_list,}" ;;
    -l*) ;;                     # no platform libs on the mac (bcrypt is Windows')
    -x) shift ;;                # the toolchain probe's `-xc /dev/null`
    -xc) ;;
    /dev/null) ;;
    -fPIC) ;;
    *) objs="$objs $1" ;;
  esac
  shift
done
# the toolchain probe links a trivial empty object: answer it truthfully
if [ -z "$objs" ] || [ "$out" = /dev/null ]; then
  exit 0
fi
explist=""
[ -n "$exp" ] && explist="-exported_symbols_list $exp"
exec $ld64 -dylib -arch "$arch" -platform_version macos "$minver" 14.0 \
  -o "$out" $objs -lSystem -L"$libsys" $explist
