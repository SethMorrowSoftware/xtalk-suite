"""runner_config.py - what artnetxt's two headless runners need to know about it.

tools/run-lcb-tests.py and tools/run-lcs-tests.py are byte-identical in the
three ShowControl members (oscxt, midixt, artnetxt; the suite's
tools/check-checker-drift.py holds them equal). Everything that differs between
the members is here, and only here.
"""

MEMBER = "artnetxt"

# The extensions this member ships: (module name, source file). Both runners
# compile each one with lc-compile -Werror, as the IDE's Extension Builder does.
EXTENSIONS = [("artnet", "src/artnet.lcb")]

# The native libraries a test may require, by key. Art-Net is pure LCB: there
# is no native library, so no test names one (`-- requires:` is empty).
LIBRARIES = {}

# The engine runs (tools/run-lcs-tests.py) load the extensions in the packaged
# layout <dir>/module.lcm (+ code/<platform-id>/<token>.<ext> for a native
# one): (folder, module name, library keys in preference order). None here.
ENGINE_EXTENSIONS = [("artnet", "artnet", [])]

# Extra LCB modules compiled for the engine runs only (test controls): none.
ENGINE_SUPPORT = []

# The shipped helper script every engine run `start using`s (SC_HELPERS).
HELPERS = "examples/artnet-helpers.livecodescript"

# The first UDP port an engine run may use. Each member has its own range, so
# the three can run side by side on one machine (the suite's build-all.sh).
PORT_BASE = 48000
