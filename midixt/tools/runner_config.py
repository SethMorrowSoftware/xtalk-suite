"""runner_config.py - what midixt's two headless runners need to know about it.

tools/run-lcb-tests.py and tools/run-lcs-tests.py are byte-identical in the
three ShowControl members (oscxt, midixt, artnetxt; the suite's
tools/check-checker-drift.py holds them equal). Everything that differs between
the members is here, and only here.
"""

MEMBER = "midixt"

# The extensions this member ships: (module name, source file). Both runners
# compile each one with lc-compile -Werror, as the IDE's Extension Builder does.
EXTENSIONS = [("midi", "src/midi.lcb")]

# The native libraries a test may require, by key: key -> (the bare token the
# binding binds to, "built" | "mock"). A "built" library is found in the CMake
# build folder (or, failing that, the member's committed src/code/<platform-id>/
# copy); a "mock" one in <build>/mock/. A test names keys on a header line:
#     -- requires: midixt-mock
# midixt-mock is the shim over tests/mock/rtmidi_mock.c, a controllable RtMidi
# double with a virtual loopback cable: the whole MIDI stack runs with no MIDI
# service. midixt is the real library over the machine's own MIDI service.
LIBRARIES = {"midixt-mock": ("midixt", "mock"), "midixt": ("midixt", "built")}

# The engine runs (tools/run-lcs-tests.py) load the extensions in the packaged
# layout <dir>/module.lcm + <dir>/code/<platform-id>/<token>.<ext>, in the order
# of the folder names: (folder, module name, library keys in preference order).
# The first key the test file `requires:` is used; otherwise the first listed.
# zz-midimock (the mock's test controls) carries no library of its own: its
# "c:midixt>" bindings resolve through the mapping the midi folder registers,
# so it must load after it (hence the name).
ENGINE_EXTENSIONS = [("midi", "midi", ["midixt-mock", "midixt"]),
                     ("zz-midimock", "midimock", [])]

# Extra LCB modules compiled for the engine runs only (test controls).
ENGINE_SUPPORT = [("midimock", "tests/lcb/_midimock.lcb")]

# The shipped helper script every engine run `start using`s (SC_HELPERS).
HELPERS = "examples/midi-helpers.livecodescript"

# The first UDP port an engine run may use. Each member has its own range, so
# the three can run side by side on one machine (the suite's build-all.sh).
PORT_BASE = 47900
