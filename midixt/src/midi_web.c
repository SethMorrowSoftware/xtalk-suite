/*
 * midi_web.c
 * ----------------------------------------------------------------------------
 * The web build's MIDI backend (wasm32-emscripten): the part of RtMidi's C API
 * that midi_shim.c calls, implemented over the browser's Web MIDI API. The
 * shim (its handle table, drain records, stash and error texts) is the same
 * code on the web as on a desktop, compiled against RtMidi's own rtmidi_c.h
 * so every function here has RtMidi's signature, and the .lcb is unchanged:
 * OXT-Beyond's web engine links the archive in and finds "c:midixt>midi_*"
 * through midixt_web_exports (CMakeLists.txt generates it from the .lcb).
 *
 * Why not RtMidi's own Web MIDI backend (RtMidi.cpp under __WEB_MIDI_API__,
 * read at the pinned 6.0.0 tag):
 *   - its input never reaches the queue rtmidi_in_get_message reads: a
 *     message goes only to a callback set with rtmidi_in_set_callback, and is
 *     appended to the bytes of every message before it (the vector is never
 *     cleared). The shim registers no callback (rule 1) and polls, so it would
 *     read nothing, ever;
 *   - a port opened before the browser has answered is not opened and nothing
 *     says so (the wrapper's ok stays true), and opening a port that is not
 *     there, or any call in a browser with no Web MIDI, throws a JavaScript
 *     error out through the engine;
 *   - it calls into the module from a browser event (Module.ccall) and reads
 *     Module.HEAPU8, neither of which an engine has to export.
 * So this file is datachannelxt's pattern (its src/datachannel_web.cpp): the
 * browser's events land in a JavaScript queue and a poll drains it; nothing
 * calls into WebAssembly from an event, so nothing can reach script or run
 * inside the engine (rule 1); and every entry goes through ONE import whose
 * body is a try/catch that turns a throw into a refused call and a reason
 * (rule 2's firewall, in JavaScript). RtMidi's own sources are not compiled
 * into the web archive at all; its header is.
 *
 * What the shim relies on (its header comment lists RtMidi 6.0.0's
 * behaviour), and what this file does about each:
 *   - A wrapper whose backend could not start has ok == false and a NULL ptr:
 *     what a create returns while the browser has not answered, after it
 *     refused, or with no Web MIDI here. The shim frees it and makes another
 *     on its next call, so the ports appear once the answer is yes.
 *   - A failed call sets ok to false; the shim sets it back before a call it
 *     judges. rtmidi_get_port_count answers (unsigned)-1 when it fails, and
 *     rtmidi_in_get_message -1 with *size left alone and the message queued.
 *   - rtmidi_get_port_name answers snprintf()'s count and writes at most
 *     *bufLen - 1 bytes and a NUL; with no buffer it writes the size needed
 *     into *bufLen and answers 0.
 *   - The input queue holds queueSizeLimit - 1 messages and drops a message
 *     that arrives when it is full; the filters (RtMidi's ignoreTypes, all
 *     three on by default) drop SysEx (0xF0), time code and clock (0xF1,
 *     0xF8) and active sensing (0xFE) before they are queued; a message's
 *     time is seconds since the previous one the port took, the first 0.
 *   - A message too big for the caller's buffer is popped and lost, and
 *     *size says how big it was.
 * The shim also asks this file why a call failed (midixt_web_why), and adds
 * the answer to its own words: no Web MIDI in this browser, a page that is
 * not secure, a frame that does not allow MIDI, a question the person has
 * not answered yet, a refusal, or what the browser threw.
 *
 * The browser's side of things, as the Web MIDI API has it:
 *   - Access is asked for once, with SysEx (midixt sends and reads SysEx, as
 *     RtMidi's backend asks too), the first time anything needs a port. The
 *     answer is a promise, so the first count is 0 and says the question is
 *     out; a script asks again later. A refusal stands for the life of the
 *     page (asking again would put the question to the person again, or be
 *     refused unseen); a reload asks again. A frame whose permissions policy
 *     leaves MIDI out is refused at once, and nothing is asked.
 *   - Web MIDI has no virtual ports: the shim refuses them before it gets
 *     here (rtmidi_open_virtual_port refuses too, in case).
 *   - The ports are the access's inputs and outputs that are not
 *     disconnected, in the browser's order, numbered from 0 at each call, as
 *     RtMidi numbers a desktop's.
 *   - An input is opened with port.open() and a listener: each midimessage
 *     event carries one complete message (the browser assembles SysEx and
 *     takes running status apart) and its time. Two handles on one input
 *     each get every message. The last handle's close closes the port, so a
 *     device another program wants is let go.
 *   - open() answers later, by promise, so a handle is given at once. A port
 *     the browser could not open (another program holds it) says so at every
 *     poll or send through that handle until it is closed, as a desktop's
 *     refused open would have said so at once.
 *   - An output is opened with port.open() and sent to with port.send(); the
 *     browser checks the bytes (a whole message or several, no running
 *     status, SysEx only with SysEx access) and throws on anything else,
 *     which comes back as a refused send and the browser's words. An output
 *     is never closed: a closed output may drop what it has not yet sent,
 *     and a script that closes straight after its last note-off must not
 *     lose it. The browser closes it with the page.
 * ----------------------------------------------------------------------------
 */

#include <emscripten.h>

#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "rtmidi_c.h"

/* The operations of the one import, by number (the JavaScript switch below
 * uses the same numbers). */
#define WEB_START  1   /* ask for access, if not yet asked: 1 ready, 0 asked, -1 not here */
#define WEB_COUNT  2   /* a = is_input: the number of ports */
#define WEB_NAME   3   /* a = is_input, b = index, c = buffer, d = capacity: snprintf's count */
#define WEB_OPEN   4   /* a = is_input, b = index, c = queue limit: an open id, 0 refused */
#define WEB_CLOSE  5   /* a = open id */
#define WEB_FLAGS  6   /* a = open id, b = RtMidi's ignore flags */
#define WEB_POP    7   /* a = open id, b = buffer, c = capacity, d = &delta: the length, 0 empty */
#define WEB_SEND   8   /* a = open id, b = bytes, c = length: 0 sent */
#define WEB_WHY    9   /* a = buffer, b = capacity: the last failure's reason */

/* The one import. Every operation returns a number; -2 is "it threw", with
 * the reason kept for WEB_WHY. Pointers cross as numbers (wasm32).
 *
 * EM_JS joins the body into one line, so every statement ends with a
 * semicolon, and strings are in double quotes: the C preprocessor reads the
 * body first, and a single-quoted JavaScript string is a malformed C
 * character constant to it. */
EM_JS(int, midixt_web_js, (int op, int a, int b, int c, int d), {
  var X = globalThis.__oxtMidixtWeb;
  if (!X) {
    X = globalThis.__oxtMidixtWeb = {
      state: 0, access: null, why: "", err: "",
      opens: new Map(), next: 1, users: new Map()
    };
  }
  function said(e) {
    if (e && typeof e === "object" && e.name) {
      return e.message ? e.name + ": " + e.message : String(e.name);
    }
    return String(e);
  }
  function put(s, p, cap) {
    var bytes = new TextEncoder().encode(String(s));
    if (p && cap > 0) {
      var n = Math.min(bytes.length, cap - 1);
      HEAPU8.set(bytes.subarray(0, n), p);
      HEAPU8[p + n] = 0;
    }
    return bytes.length;
  }
  function ports(isIn) {
    var all = isIn ? X.access.inputs : X.access.outputs;
    var list = [];
    all.forEach(function (port) {
      if (port && port.state !== "disconnected") {
        list.push(port);
      }
    });
    return list;
  }
  function start() {
    if (X.state === 2) {
      return 1;
    }
    if (X.state === 1) {
      X.err = "the browser has not yet answered whether this page may use MIDI: ask again in a moment";
      return 0;
    }
    if (X.state === 3) {
      X.err = X.why;
      return -1;
    }
    var nav = (typeof navigator !== "undefined") ? navigator : null;
    if (!nav || typeof nav.requestMIDIAccess !== "function") {
      if (typeof isSecureContext !== "undefined" && isSecureContext === false) {
        X.err = "browsers give MIDI only to a secure page (https), and this one is not";
      } else {
        X.err = "this browser has no Web MIDI";
      }
      return -1;
    }
    var doc = (typeof document !== "undefined") ? document : null;
    var policy = doc ? (doc.permissionsPolicy || doc.featurePolicy) : null;
    if (policy && typeof policy.allowsFeature === "function" && !policy.allowsFeature("midi")) {
      X.state = 3;
      X.why = "this page may not use MIDI: the frame it is shown in does not allow it";
      X.err = X.why;
      return -1;
    }
    X.state = 1;
    var asked;
    try {
      asked = nav.requestMIDIAccess({ sysex: true });
    } catch (e) {
      X.state = 3;
      X.why = "the browser refused this page MIDI (" + said(e) + ")";
      X.err = X.why;
      return -1;
    }
    Promise.resolve(asked).then(function (access) {
      if (access && access.inputs && access.outputs) {
        X.access = access;
        X.state = 2;
      } else {
        X.state = 3;
        X.why = "the browser answered, but gave no MIDI access";
      }
    }, function (e) {
      X.state = 3;
      X.why = "the browser refused this page MIDI (" + said(e) + ")";
    });
    X.err = "asked the browser whether this page may use MIDI: ask again once it has answered";
    return 0;
  }
  function take(rec, ev) {
    var data = ev ? ev.data : null;
    if (!data || !data.length) {
      return;
    }
    var status = data[0];
    if ((status === 0xF0 && (rec.flags & 1)) ||
        ((status === 0xF1 || status === 0xF8) && (rec.flags & 2)) ||
        (status === 0xFE && (rec.flags & 4))) {
      return;
    }
    var now = (ev && typeof ev.timeStamp === "number" && isFinite(ev.timeStamp)) ? ev.timeStamp
            : ((typeof performance !== "undefined") ? performance.now() : Date.now());
    var delta = (rec.last === null) ? 0 : Math.max(0, (now - rec.last) / 1000);
    rec.last = now;
    if (rec.queue.length >= rec.room) {
      rec.dropped++;
      return;
    }
    rec.queue.push({ bytes: new Uint8Array(data), delta: delta });
  }
  try {
    var rec, list, port, id, users, msg;
    switch (op) {
    case 1:
      return start();
    case 2:
      return ports(a !== 0).length;
    case 3:
      list = ports(a !== 0);
      return put((b >= 0 && b < list.length) ? (list[b].name || "") : "", c, d);
    case 4:
      list = ports(a !== 0);
      if (b < 0 || b >= list.length) {
        X.err = "there is no MIDI " + (a !== 0 ? "input" : "output") + " " + b + " now";
        return 0;
      }
      port = list[b];
      id = X.next++;
      rec = { port: port, isIn: a !== 0, queue: [], room: Math.max(0, c - 1),
              flags: 7, last: null, dropped: 0, failed: "", listener: null };
      if (rec.isIn) {
        rec.listener = function (ev) { take(rec, ev); };
        port.addEventListener("midimessage", rec.listener);
      }
      if (rec.isIn) {
        users = X.users.get(port) || 0;
        X.users.set(port, users + 1);
      }
      X.opens.set(id, rec);
      if (typeof port.open === "function") {
        Promise.resolve(port.open()).then(null, function (e) {
          rec.failed = "the browser could not open " + (port.name || "the port") + " (" + said(e) + ")";
        });
      }
      return id;
    case 5:
      rec = X.opens.get(a);
      if (!rec) {
        return 0;
      }
      X.opens.delete(a);
      if (rec.isIn) {
        rec.port.removeEventListener("midimessage", rec.listener);
        users = (X.users.get(rec.port) || 1) - 1;
        if (users > 0) {
          X.users.set(rec.port, users);
        } else {
          X.users.delete(rec.port);
          if (typeof rec.port.close === "function") {
            Promise.resolve(rec.port.close()).then(null, function () {});
          }
        }
      }
      return 0;
    case 6:
      rec = X.opens.get(a);
      if (rec) {
        rec.flags = b;
      }
      return 0;
    case 7:
      rec = X.opens.get(a);
      if (!rec || !rec.isIn) {
        X.err = "not an open input";
        return -1;
      }
      if (rec.failed) {
        X.err = rec.failed;
        return -1;
      }
      msg = rec.queue.shift();
      if (!msg) {
        return 0;
      }
      if (msg.bytes.length <= c) {
        HEAPU8.set(msg.bytes, b);
      }
      new DataView(HEAPU8.buffer).setFloat64(d, msg.delta, true);
      return msg.bytes.length;
    case 8:
      rec = X.opens.get(a);
      if (!rec || rec.isIn) {
        X.err = "not an open output";
        return -1;
      }
      if (rec.failed) {
        X.err = rec.failed;
        return -1;
      }
      rec.port.send(HEAPU8.slice(b, b + c));
      return 0;
    case 9:
      return put(X.err, a, b);
    default:
      X.err = "midixt_web_js: no operation " + op;
      return -1;
    }
  } catch (e) {
    X.err = said(e);
    return -2;
  }
});

/* Why the last call that failed here failed: the browser's words, or this
 * file's. Cleared as each call starts and filled when it fails, so the shim
 * reads it straight after the call it judged (midi_shim.c, err_set_backend). */
static char g_why[256];

const char *midixt_web_why(void);
const char *midixt_web_why(void) { return g_why; }

static void why_clear(void) { g_why[0] = '\0'; }
static void why_take(void) {
    if (midixt_web_js(WEB_WHY, (int) (intptr_t) g_why, (int) sizeof g_why, 0, 0) < 0)
        g_why[0] = '\0';
}
static void why_say(const char *text) {
    size_t n = strlen(text);
    if (n >= sizeof g_why) n = sizeof g_why - 1;
    memcpy(g_why, text, n);
    g_why[n] = '\0';
}

/* What a wrapper's ptr points at on the web: one direction, and the port it
 * has open, by the JavaScript side's id (0: none). */
typedef struct {
    int          is_input;
    int          open_id;
    unsigned int queue_limit;   /* RtMidi's queueSizeLimit: it holds one fewer */
    int          flags;         /* RtMidi's ignore flags: 1 SysEx, 2 time, 4 sensing */
} web_port;

static web_port *port_of(RtMidiPtr device) {
    return device ? (web_port *) device->ptr : NULL;
}

/* A wrapper, as rtmidi_c.cpp makes one: ok and a port when the backend is
 * up; ok false and a NULL ptr when it is not (RtMidi's "the constructor
 * threw"), which the shim frees and asks for again on its next call. msg is
 * never set to anything but "" (the shim never reads it). */
static RtMidiPtr make(int is_input, unsigned int queue_limit) {
    RtMidiPtr w = (RtMidiPtr) calloc(1, sizeof *w);
    if (!w) return NULL;
    w->msg = "";
    why_clear();
    if (midixt_web_js(WEB_START, 0, 0, 0, 0) != 1) {
        why_take();
        w->ok = false;
        return w;
    }
    web_port *p = (web_port *) calloc(1, sizeof *p);
    if (!p) {
        why_say("out of memory");
        w->ok = false;
        return w;
    }
    p->is_input = is_input;
    p->queue_limit = queue_limit;
    p->flags = 7;                /* RtMidi's default: SysEx, time and sensing ignored */
    w->ptr = p;
    w->ok = true;
    return w;
}

/* RtMidi's default queue size limit (RtMidi.h: RtMidiIn's queueSizeLimit). */
#define WEB_DEFAULT_QUEUE_LIMIT 100

RtMidiInPtr rtmidi_in_create_default(void) {
    return make(1, WEB_DEFAULT_QUEUE_LIMIT);
}
/* Any API is Web MIDI here (RtMidi falls back to the first compiled API
 * when the one asked for is not compiled in). The client name names nothing
 * a page can show. */
RtMidiInPtr rtmidi_in_create(enum RtMidiApi api, const char *clientName, unsigned int queueSizeLimit) {
    (void) api; (void) clientName;
    return make(1, queueSizeLimit);
}
RtMidiOutPtr rtmidi_out_create_default(void) {
    return make(0, 0);
}
RtMidiOutPtr rtmidi_out_create(enum RtMidiApi api, const char *clientName) {
    (void) api; (void) clientName;
    return make(0, 0);
}

enum RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device) {
    (void) device;
    return RTMIDI_API_WEB_MIDI_API;
}
enum RtMidiApi rtmidi_out_get_current_api(RtMidiPtr device) {
    (void) device;
    return RTMIDI_API_WEB_MIDI_API;
}

unsigned int rtmidi_get_port_count(RtMidiPtr device) {
    web_port *p = port_of(device);
    if (!p) {
        if (device) device->ok = false;
        return (unsigned int) -1;
    }
    why_clear();
    int n = midixt_web_js(WEB_COUNT, p->is_input, 0, 0, 0);
    if (n < 0) {
        why_take();
        device->ok = false;
        return (unsigned int) -1;
    }
    return (unsigned int) n;
}

int rtmidi_get_port_name(RtMidiPtr device, unsigned int portNumber, char *bufOut, int *bufLen) {
    if (bufOut == NULL && bufLen == NULL) return -1;
    web_port *p = port_of(device);
    if (!p) {
        if (device) device->ok = false;
        return -1;
    }
    /* A number past INT_MAX names no port: the JavaScript side sees -1 */
    int index = portNumber > (unsigned int) INT_MAX ? -1 : (int) portNumber;
    int cap = (bufOut && bufLen) ? *bufLen : 0;
    why_clear();
    int n = midixt_web_js(WEB_NAME, p->is_input, index, (int) (intptr_t) bufOut, cap);
    if (n < 0) {
        why_take();
        device->ok = false;
        return -1;
    }
    if (bufOut == NULL) {
        *bufLen = n + 1;
        return 0;
    }
    return n;
}

void rtmidi_open_port(RtMidiPtr device, unsigned int portNumber, const char *portName) {
    (void) portName;   /* a page names no port of its own */
    web_port *p = port_of(device);
    if (!p) {
        if (device) device->ok = false;
        return;
    }
    if (p->open_id) return;   /* RtMidi: a WARNING (already open), ok stays */
    int index = portNumber > (unsigned int) INT_MAX ? -1 : (int) portNumber;
    why_clear();
    int id = midixt_web_js(WEB_OPEN, p->is_input, index,
                           p->queue_limit > (unsigned int) INT_MAX ? INT_MAX : (int) p->queue_limit, 0);
    if (id <= 0) {
        why_take();
        device->ok = false;
        return;
    }
    p->open_id = id;
    if (p->is_input) (void) midixt_web_js(WEB_FLAGS, id, p->flags, 0, 0);
}

void rtmidi_open_virtual_port(RtMidiPtr device, const char *portName) {
    (void) portName;
    why_say("a web page has no virtual ports (Web MIDI makes none)");
    if (device) device->ok = false;
}

void rtmidi_close_port(RtMidiPtr device) {
    web_port *p = port_of(device);
    if (!p || !p->open_id) return;
    (void) midixt_web_js(WEB_CLOSE, p->open_id, 0, 0, 0);
    p->open_id = 0;
}

void rtmidi_in_ignore_types(RtMidiInPtr device, bool midiSysex, bool midiTime, bool midiSense) {
    web_port *p = port_of(device);
    if (!p || !p->is_input) return;
    p->flags = (midiSysex ? 1 : 0) | (midiTime ? 2 : 0) | (midiSense ? 4 : 0);
    if (p->open_id) (void) midixt_web_js(WEB_FLAGS, p->open_id, p->flags, 0, 0);
}

double rtmidi_in_get_message(RtMidiInPtr device, unsigned char *message, size_t *size) {
    web_port *p = port_of(device);
    if (!p || !p->is_input || !size) {
        if (device) device->ok = false;
        return -1.0;
    }
    if (!p->open_id) {          /* a port not open has nothing queued */
        *size = 0;
        return 0.0;
    }
    double delta = 0.0;
    int cap = (!message) ? 0 : (*size > (size_t) INT_MAX ? INT_MAX : (int) *size);
    why_clear();
    int n = midixt_web_js(WEB_POP, p->open_id, (int) (intptr_t) message, cap, (int) (intptr_t) &delta);
    if (n < 0) {
        why_take();
        device->ok = false;    /* *size left alone, as RtMidi leaves it */
        return -1.0;
    }
    *size = (size_t) n;
    return delta;
}

int rtmidi_out_send_message(RtMidiOutPtr device, const unsigned char *message, int length) {
    web_port *p = port_of(device);
    if (!p || p->is_input) {
        if (device) device->ok = false;
        return -1;
    }
    if (!p->open_id || !message || length <= 0) {
        why_say(!p->open_id ? "the port is not open" : "nothing to send");
        device->ok = false;
        return -1;
    }
    why_clear();
    if (midixt_web_js(WEB_SEND, p->open_id, (int) (intptr_t) message, length, 0) != 0) {
        why_take();
        device->ok = false;
        return -1;
    }
    return 0;
}

static void free_device(RtMidiPtr device) {
    if (!device) return;
    rtmidi_close_port(device);
    free(device->ptr);
    free(device);
}
void rtmidi_in_free(RtMidiInPtr device) { free_device(device); }
void rtmidi_out_free(RtMidiOutPtr device) { free_device(device); }
