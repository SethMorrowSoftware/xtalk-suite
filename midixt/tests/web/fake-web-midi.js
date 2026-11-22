/*
 * tests/web/fake-web-midi.js -- a stand-in for the browser's Web MIDI API, for
 * tests/midi_web_test.c under node, which has none. Linked in with --pre-js
 * (CMakeLists.txt's web tests); the test installs one scene before its first
 * midi_* call, through midixtFake.install(scene):
 *
 *   0 none      no navigator.requestMIDIAccess (node itself, Safari, WebKit)
 *   1 refused   the request is refused: NotAllowedError, as when the person
 *               answers no
 *   2 framed    the page's permissions policy leaves MIDI out (an iframe with
 *               no allow="midi", the community gallery's player): nothing may
 *               be asked
 *   3 pending   the request is never answered (the person has not answered)
 *   4 granted   the request is granted, with these ports, in this order:
 *                 inputs   "Loop Cable"    what the output "Loop Cable" sends
 *                          "Fake Keyboard" the test plays it (receive)
 *                          "Busy Port"     its open() is refused, as a device
 *                                          another program holds can be
 *                          "Unplugged Pad" disconnected: listed by the browser,
 *                                          not offered as a port
 *                 outputs  "Loop Cable"    delivers to the input of that name
 *                          "Fake Synth"    keeps what it is sent
 *
 * A port does what a browser's does for what midixt uses: open() and close()
 * are promises; listeners added for "midimessage" get one event per message,
 * { data: Uint8Array, timeStamp: milliseconds }; send() checks its bytes as a
 * browser does (whole messages, no running status, SysEx only with SysEx
 * access, nothing on a disconnected port) and throws a TypeError, an
 * InvalidAccessError or an InvalidStateError when they fail. The loop cable
 * delivers in a later microtask, never inside send(), as a real loopback
 * driver delivers on the browser's event loop.
 *
 * NOT a MIDI service: a test double. What it cannot show is in
 * docs/building.md (a browser's own prompt, its device list, its timing).
 */
(function () {
  "use strict";

  var F = globalThis.midixtFake = {
    asks: 0,           /* requestMIDIAccess calls */
    options: null,     /* what the last one asked for */
    opens: 0,          /* port.open() calls */
    closes: 0,         /* port.close() calls */
    sent: [],          /* { port, bytes } for every send a port took */
    inputs: [],        /* the access's input ports, every one, by position */
    outputs: [],       /* ... and its outputs */
    sysex: true,       /* the access carries SysEx (asked for and granted) */
    throwOnList: false /* the next listing throws, as a browser's could */
  };

  function domError(name, message) {
    if (typeof DOMException === "function") {
      return new DOMException(message, name);
    }
    var e = new Error(message);
    e.name = name;
    return e;
  }

  /* How many bytes a message with this status byte has (0: not a status
   * that may start one; -1: SysEx, up to its 0xF7) */
  function lengthOf(status) {
    if (status < 0x80) return 0;
    if (status < 0xC0) return 3;
    if (status < 0xE0) return 2;
    if (status < 0xF0) return 3;
    switch (status) {
    case 0xF0: return -1;
    case 0xF1: case 0xF3: return 2;
    case 0xF2: return 3;
    case 0xF6: case 0xF8: case 0xFA: case 0xFB: case 0xFC: case 0xFE: case 0xFF: return 1;
    default: return 0;   /* 0xF4, 0xF5, 0xF7 alone, 0xF9, 0xFD */
    }
  }

  /* The messages in a send, as a browser's MIDIOutput.send() checks them */
  function messagesOf(bytes) {
    var out = [];
    var i = 0;
    while (i < bytes.length) {
      var n = lengthOf(bytes[i]);
      if (n === 0) {
        throw new TypeError("Failed to execute 'send' on 'MIDIOutput': Running status is not allowed at index " + i + " (" + bytes[i] + ").");
      }
      var end;
      if (n === -1) {
        if (!F.sysex) {
          throw domError("InvalidAccessError", "Failed to execute 'send' on 'MIDIOutput': System exclusive message is not allowed at index " + i + " (240).");
        }
        end = bytes.indexOf(0xF7, i + 1);
        if (end < 0) {
          throw new TypeError("Failed to execute 'send' on 'MIDIOutput': Message is incomplete.");
        }
        end++;
      } else {
        end = i + n;
        if (end > bytes.length) {
          throw new TypeError("Failed to execute 'send' on 'MIDIOutput': Message is incomplete.");
        }
      }
      for (var j = i + 1; j < end - (n === -1 ? 1 : 0); j++) {
        if (bytes[j] >= 0x80) {
          throw new TypeError("Failed to execute 'send' on 'MIDIOutput': Unexpected status byte at index " + j + " (" + bytes[j] + ").");
        }
      }
      out.push(bytes.slice(i, end));
      i = end;
    }
    return out;
  }

  function Port(type, id, name) {
    this.type = type;
    this.id = id;
    this.name = name;
    this.manufacturer = "midixt tests";
    this.state = "connected";
    this.connection = "closed";
    this.listeners = [];
    this.refuseOpen = null;   /* an error open() is refused with */
    this.loop = null;         /* an output's: the input it delivers to */
  }
  Port.prototype.addEventListener = function (type, fn) {
    if (type === "midimessage" && this.listeners.indexOf(fn) < 0) this.listeners.push(fn);
  };
  Port.prototype.removeEventListener = function (type, fn) {
    var i = this.listeners.indexOf(fn);
    if (type === "midimessage" && i >= 0) this.listeners.splice(i, 1);
  };
  Port.prototype.open = function () {
    F.opens++;
    if (this.refuseOpen) return Promise.reject(this.refuseOpen);
    this.connection = "open";
    return Promise.resolve(this);
  };
  Port.prototype.close = function () {
    F.closes++;
    this.connection = "closed";
    return Promise.resolve(this);
  };
  /* An input takes a message now: every listener gets the event */
  Port.prototype.receive = function (bytes, stamp) {
    var ev = {
      data: Uint8Array.from(bytes),
      timeStamp: (typeof stamp === "number") ? stamp : performance.now()
    };
    this.listeners.slice().forEach(function (fn) { fn(ev); });
  };
  Port.prototype.send = function (data) {
    if (this.state === "disconnected") {
      throw domError("InvalidStateError", "Failed to execute 'send' on 'MIDIOutput': The port is disconnected.");
    }
    var bytes = Array.from(data);
    var messages = messagesOf(bytes);
    F.sent.push({ port: this.name, bytes: bytes });
    var into = this.loop;
    if (into) {
      messages.forEach(function (m) {
        queueMicrotask(function () { into.receive(m, performance.now()); });
      });
    }
  };

  function MapOf(ports) {
    var map = new Map();
    ports.forEach(function (p) { map.set(p.id, p); });
    var forEach = map.forEach.bind(map);
    map.forEach = function (fn) {
      if (F.throwOnList) {
        F.throwOnList = false;
        throw new Error("the device list went away");
      }
      return forEach(fn);
    };
    return map;
  }

  F.install = function (scene) {
    if (typeof globalThis.navigator === "undefined") globalThis.navigator = {};
    delete globalThis.navigator.requestMIDIAccess;
    if (scene === 0) return;

    if (scene === 2) {
      globalThis.document = {
        featurePolicy: { allowsFeature: function (feature) { return feature !== "midi"; } }
      };
    }
    if (scene === 4) {
      var cableIn = new Port("input", "in-cable", "Loop Cable");
      var keys = new Port("input", "in-keys", "Fake Keyboard");
      var busy = new Port("input", "in-busy", "Busy Port");
      busy.refuseOpen = domError("InvalidAccessError", "The port is in use by another program.");
      var pad = new Port("input", "in-pad", "Unplugged Pad");
      pad.state = "disconnected";
      var cableOut = new Port("output", "out-cable", "Loop Cable");
      cableOut.loop = cableIn;
      var synth = new Port("output", "out-synth", "Fake Synth");
      F.inputs = [cableIn, keys, busy, pad];
      F.outputs = [cableOut, synth];
    }
    globalThis.navigator.requestMIDIAccess = function (options) {
      F.asks++;
      F.options = options;
      if (scene === 1) {
        return Promise.reject(domError("NotAllowedError", "The person said no."));
      }
      if (scene === 3) {
        return new Promise(function () {});
      }
      F.sysex = !!(options && options.sysex);
      return Promise.resolve({
        sysexEnabled: F.sysex,
        inputs: MapOf(F.inputs),
        outputs: MapOf(F.outputs),
        onstatechange: null
      });
    };
  };
})();
