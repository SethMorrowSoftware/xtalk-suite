/*
 * osc_smoke_test.c -- runtime smoke test for the oscxt OSC shim.
 *
 * Links directly against the oscxt shared library and drives the same C entry
 * points the LCB binding calls: round-trips every OSC type through
 * build -> parse, exercises bundles and address matching, and fuzzes malformed
 * datagrams to prove they fail cleanly (no crash / no out-of-bounds read --
 * run this under -fsanitize=address). A compile check alone cannot show this.
 *
 * Enable with -DOSCXT_BUILD_TESTS=ON, then run `ctest`.
 */
#include "osc_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <locale.h>
#include <stdint.h>
#if !defined(_WIN32)
#include <pthread.h>
#endif

static int g_pass = 0, g_fail = 0;
static void check(const char *name, int ok) {
    printf("  [%s] %s\n", ok ? "PASS" : "FAIL", name);
    if (ok) g_pass++; else g_fail++;
}

/* Switch LC_NUMERIC to a locale whose decimal mark is a comma, as an engine
 * that leaves the user's locale in place does. Returns the name it found, or
 * NULL when the machine has none installed (native-oscxt.yml installs one, so
 * CI never skips: OSCXT_REQUIRE_COMMA_LOCALE=1 turns a skip into a failure). */
static const char *enter_comma_locale(void) {
    static const char *names[] = { "de_DE.UTF-8", "de_DE.utf8", "de_DE", "fr_FR.UTF-8",
                                   "fr_FR.utf8", "German_Germany.1252", "de-DE", "German", NULL };
    for (int i = 0; names[i]; i++) {
        if (setlocale(LC_NUMERIC, names[i]) && localeconv()->decimal_point[0] == ',')
            return names[i];
    }
    setlocale(LC_NUMERIC, "C");
    return NULL;
}

/* The deep-pattern check runs on a thread with a small stack, so the depth
 * guard is what keeps it alive on every platform: on a default 8 MB Linux
 * stack the unguarded recursion survived, and only Windows's 1 MB main
 * thread fell over. */
#define DEEP_GROUPS 21000                         /* "{,}" x 21000 = a 63 KB address */
static char *g_deep_pattern;
static int g_deep_result = -1;
static void *deep_match(void *unused) {
    (void) unused;
    g_deep_result = osc_match(g_deep_pattern, "/x");
    return NULL;
}
static int run_deep_match(void) {
#if defined(_WIN32)
    deep_match(NULL);                             /* the 1 MB main thread is the small stack */
    return 1;
#else
    pthread_attr_t at; pthread_t th;
    if (pthread_attr_init(&at) != 0) return 0;
    pthread_attr_setstacksize(&at, 256 * 1024);
    if (pthread_create(&th, &at, deep_match, NULL) != 0) { pthread_attr_destroy(&at); return 0; }
    pthread_join(th, NULL);
    pthread_attr_destroy(&at);
    return 1;
#endif
}

int main(void) {
    printf("osc ABI version = %d\n", osc_abi_version());
    check("ABI version is 2", osc_abi_version() == 2);

    uint8_t buf[1024];
    char sbuf[256];
    int32_t ok;

    /* ---- numeric build args via decimal STRINGS (ABI 2 path the .lcb uses) ----
       The xTalk engine hands script numbers to a foreign `any` as strings; the
       binding stringifies every numeric value and these parse it in C. */
    { int32_t sh = osc_build_new("/numstr");
      osc_build_add_int32_str (sh, "-42");
      osc_build_add_float_str (sh, "0.5");      /* the value that broke any->Number */
      osc_build_add_double_str(sh, "3.25");
      int32_t sn = osc_build_finish(sh, buf, sizeof buf);
      osc_build_free(sh);
      int32_t sm = osc_parse(buf, sn);
      osc_typetag(sm, sbuf, sizeof sbuf);
      check("str-built typetag is ifd", strcmp(sbuf, "ifd") == 0);
      check("int32_str -42",  osc_arg_int32 (sm, 0, &ok) == -42 && ok);
      check("float_str 0.5",  fabsf(osc_arg_float (sm, 1, &ok) - 0.5f) < 1e-6 && ok);
      check("double_str 3.25", fabs(osc_arg_double(sm, 2, &ok) - 3.25) < 1e-12 && ok);
      osc_parse_free(sm); }

    /* ---- build a message with one of every common type ---- */
    int32_t b = osc_build_new("/test/all");
    check("build_new returns a handle", b != 0);
    osc_build_add_int32(b, -42);
    osc_build_add_float(b, 0.5f);
    osc_build_add_string(b, "hello");
    osc_build_add_int64(b, 0x1122334455667788LL);
    osc_build_add_double(b, 3.14159265358979);
    osc_build_add_true(b);
    osc_build_add_false(b);
    osc_build_add_nil(b);
    osc_build_add_impulse(b);
    { uint8_t blob[3] = {0xDE, 0xAD, 0xBE}; osc_build_add_blob(b, blob, 3); }

    int32_t n = osc_build_finish(b, buf, sizeof buf);
    check("build_finish > 0", n > 0);
    check("serialized length is a multiple of 4", (n % 4) == 0);
    osc_build_free(b);

    /* ---- parse it back ---- */
    int32_t m = osc_parse(buf, n);
    check("parse returns a handle", m != 0);
    check("parsed is not a bundle", osc_is_bundle(m) == 0);

    osc_address(m, sbuf, sizeof sbuf);
    check("address round-trips", strcmp(sbuf, "/test/all") == 0);

    osc_typetag(m, sbuf, sizeof sbuf);
    check("typetag is ifshdTFNIb", strcmp(sbuf, "ifshdTFNIb") == 0);
    check("arg_count is 10", osc_arg_count(m) == 10);

    check("arg0 int32 == -42", osc_arg_int32(m, 0, &ok) == -42 && ok);
    check("arg1 float == 0.5", fabsf(osc_arg_float(m, 1, &ok) - 0.5f) < 1e-6 && ok);
    osc_arg_string(m, 2, sbuf, sizeof sbuf);
    check("arg2 string == hello", strcmp(sbuf, "hello") == 0);
    check("arg3 int64 round-trips", osc_arg_int64(m, 3, &ok) == 0x1122334455667788LL && ok);
    check("arg4 double round-trips", fabs(osc_arg_double(m, 4, &ok) - 3.14159265358979) < 1e-12 && ok);
    check("arg5 type is T", osc_arg_type(m, 5) == 'T');
    check("arg6 type is F", osc_arg_type(m, 6) == 'F');
    check("arg7 type is N", osc_arg_type(m, 7) == 'N');
    check("arg8 type is I", osc_arg_type(m, 8) == 'I');
    { uint8_t ob[8]; int32_t bl = osc_arg_blob(m, 9, ob, sizeof ob);
      check("arg9 blob len 3", bl == 3);
      check("arg9 blob bytes", bl == 3 && ob[0]==0xDE && ob[1]==0xAD && ob[2]==0xBE); }

    /* type-mismatch getter is a clean miss, not a crash */
    osc_arg_int32(m, 2, &ok);            /* arg2 is a string */
    check("int getter on a string sets ok=0", ok == 0);

    /* 64-bit-as-decimal-string path (no 64-bit foreign int in the engine) */
    osc_arg_int64_str(m, 3, sbuf, sizeof sbuf);
    check("arg3 int64 as decimal string", strcmp(sbuf, "1234605616436508552") == 0);
    osc_parse_free(m);

    /* build an int64 from a decimal string -> read it back as a string */
    int32_t bj = osc_build_new("/big");
    osc_build_add_int64_str(bj, "9223372036854775807");   /* INT64_MAX */
    int32_t bjn = osc_build_finish(bj, buf, sizeof buf);
    osc_build_free(bj);
    int32_t mj = osc_parse(buf, bjn);
    osc_arg_int64_str(mj, 0, sbuf, sizeof sbuf);
    check("int64 max round-trips via string", strcmp(sbuf, "9223372036854775807") == 0);
    osc_parse_free(mj);

    /* ---- empty-arg message ---- */
    int32_t e = osc_build_new("/x");
    int32_t en = osc_build_finish(e, buf, sizeof buf);
    osc_build_free(e);
    int32_t em = osc_parse(buf, en);
    check("no-arg message parses", em != 0 && osc_arg_count(em) == 0);
    osc_address(em, sbuf, sizeof sbuf);
    check("no-arg address is /x", strcmp(sbuf, "/x") == 0);
    osc_parse_free(em);

    /* ---- bundle of two messages ---- */
    uint8_t m1[64], m2[64];
    int32_t h1 = osc_build_new("/a"); osc_build_add_int32(h1, 1);
    int32_t n1 = osc_build_finish(h1, m1, sizeof m1); osc_build_free(h1);
    int32_t h2 = osc_build_new("/b"); osc_build_add_float(h2, 2.0f);
    int32_t n2 = osc_build_finish(h2, m2, sizeof m2); osc_build_free(h2);

    int32_t bb = osc_bundle_new(1 /*immediately*/);
    osc_bundle_add_message(bb, m1, n1);
    osc_bundle_add_message(bb, m2, n2);
    int32_t bn = osc_bundle_finish(bb, buf, sizeof buf);
    osc_bundle_free(bb);
    check("bundle_finish > 0", bn > 0);

    int32_t pb = osc_parse(buf, bn);
    check("bundle parses", pb != 0 && osc_is_bundle(pb));
    check("bundle timetag == 1", osc_bundle_timetag(pb) == 1);
    check("bundle has 2 messages", osc_bundle_count(pb) == 2);
    int32_t sub0 = osc_bundle_message(pb, 0);
    osc_address(sub0, sbuf, sizeof sbuf);
    check("bundle msg0 is /a", strcmp(sbuf, "/a") == 0 && osc_arg_int32(sub0,0,&ok)==1 && ok);
    int32_t sub1 = osc_bundle_message(pb, 1);
    osc_address(sub1, sbuf, sizeof sbuf);
    check("bundle msg1 is /b", strcmp(sbuf, "/b") == 0);
    osc_parse_free(pb);                  /* frees sub-messages too */

    /* ---- nested bundle: a bundle element that is itself a bundle keeps its
       structure (the LCB layer recurses on this; prove the C parser supports it) ---- */
    { uint8_t inner[64];
      int32_t hi = osc_build_new("/inner"); osc_build_add_int32(hi, 7);
      int32_t ni = osc_build_finish(hi, inner, sizeof inner); osc_build_free(hi);
      int32_t ib = osc_bundle_new(1);            /* inner bundle holding /inner */
      osc_bundle_add_message(ib, inner, ni);
      uint8_t innerb[96];
      int32_t nib = osc_bundle_finish(ib, innerb, sizeof innerb); osc_bundle_free(ib);
      int32_t ob = osc_bundle_new(1);            /* outer bundle holding the inner bundle */
      osc_bundle_add_message(ob, innerb, nib);
      uint8_t outerb[160];
      int32_t nob = osc_bundle_finish(ob, outerb, sizeof outerb); osc_bundle_free(ob);

      int32_t po = osc_parse(outerb, nob);
      check("nested bundle parses", po != 0 && osc_is_bundle(po) && osc_bundle_count(po) == 1);
      int32_t child = osc_bundle_message(po, 0);
      check("nested element is itself a bundle", osc_is_bundle(child) == 1);
      check("nested bundle has the inner message", osc_bundle_count(child) == 1);
      int32_t leaf = osc_bundle_message(child, 0);
      osc_address(leaf, sbuf, sizeof sbuf);
      check("nested leaf is /inner == 7", strcmp(sbuf, "/inner") == 0 && osc_arg_int32(leaf,0,&ok)==7 && ok);
      osc_parse_free(po); }

    /* ---- address pattern matching ---- */
    check("'*' matches a segment",         osc_match("/1/fader*", "/1/fader1") == 1);
    check("'*' stops at '/'",              osc_match("/*/x", "/a/x") == 1);
    check("'*' does not cross '/'",         osc_match("/*", "/a/b") == 0);
    check("'?' matches one char",          osc_match("/fader?", "/fader7") == 1);
    check("'[range]' matches",             osc_match("/ch[0-9]", "/ch5") == 1);
    check("'[!neg]' excludes",             osc_match("/ch[!0-9]", "/ch5") == 0);
    check("'{alt}' matches an option",     osc_match("/{foo,bar}/x", "/bar/x") == 1);
    check("literal mismatch fails",        osc_match("/a/b", "/a/c") == 0);
    check("exact literal matches",         osc_match("/comp/1/opacity", "/comp/1/opacity") == 1);

    /* ---- malformed datagrams must fail cleanly (run under ASan) ---- */
    check("NULL data is rejected",         osc_parse(NULL, 8) == 0);
    check("too-short is rejected",         osc_parse((const uint8_t*)"/x", 2) == 0);
    { uint8_t bad[8] = {'/','x',0,0, ',','i',0,0};   /* declares an int, supplies none */
      check("missing-int-payload rejected", osc_parse(bad, 8) == 0); }
    { uint8_t bad[8] = {'/','x',0,0, 'i','i',0,0};   /* no leading comma on type tag */
      check("no-comma typetag rejected",   osc_parse(bad, 8) == 0); }
    { uint8_t bad[12]= {'/','x',0,0, ',','b',0,0, 0xFF,0xFF,0xFF,0xFF}; /* blob len huge */
      check("over-long blob rejected",     osc_parse(bad, 12) == 0); }
    { uint8_t bad[4] = {'/','x','y','z'};            /* address never terminated */
      check("unterminated address rejected", osc_parse(bad, 4) == 0); }

    /* ---- security regressions: hostile datagrams must be rejected, not crash ----
       These reproduce defects found in pre-release review; run under ASan/UBSan. */
    { /* bundle element size overflows int32 (old `p + elen > len` wrapped) */
      uint8_t bad[20] = {'#','b','u','n','d','l','e',0, 0,0,0,0,0,0,0,0,
                         0x7F,0xFF,0xFF,0xFC};
      check("huge bundle element size rejected", osc_parse(bad, 20) == 0); }
    { /* deeply nested bundles must hit the depth cap, not overflow the stack */
      int32_t blen = 16;
      uint8_t *nest = (uint8_t*) malloc(16);
      memset(nest, 0, 16); memcpy(nest, "#bundle", 7);
      for (int lvl = 0; lvl < 100; lvl++) {
          int32_t nlen = 16 + 4 + blen;
          uint8_t *nb = (uint8_t*) malloc((size_t) nlen);
          memset(nb, 0, (size_t) nlen); memcpy(nb, "#bundle", 7);
          nb[16]=(uint8_t)(blen>>24); nb[17]=(uint8_t)(blen>>16);
          nb[18]=(uint8_t)(blen>>8);  nb[19]=(uint8_t)blen;
          memcpy(nb + 20, nest, (size_t) blen);
          free(nest); nest = nb; blen = nlen;
      }
      check("deeply nested bundle rejected (no stack overflow)", osc_parse(nest, blen) == 0);
      free(nest); }
    { /* positive INT32_MAX blob length (old `p + 4 + bl > len` wrapped -> 32-bit OOB) */
      uint8_t bad[12] = {'/','x',0,0, ',','b',0,0, 0x7F,0xFF,0xFF,0xFF};
      check("INT32_MAX blob length rejected", osc_parse(bad, 12) == 0); }
    { /* a timetag ('t') is UNSIGNED -- a high-bit value must not read back negative */
      uint8_t tt[16] = {'/','t',0,0, ',','t',0,0, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
      int32_t th = osc_parse(tt, 16);
      osc_arg_int64_str(th, 0, sbuf, sizeof sbuf);
      check("UINT64_MAX timetag reads unsigned", strcmp(sbuf, "18446744073709551615") == 0);
      osc_parse_free(th); }
    { /* control: an int64 ('h') stays signed */
      uint8_t hh[16] = {'/','h',0,0, ',','h',0,0, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
      int32_t hhh = osc_parse(hh, 16);
      osc_arg_int64_str(hhh, 0, sbuf, sizeof sbuf);
      check("int64 'h' stays signed (-1)", strcmp(sbuf, "-1") == 0);
      osc_parse_free(hhh); }
    { /* out-of-range float/double coerced to int32 must NOT be UB (float-cast-
         overflow): a hostile OSC float argument read as an int saturates, no trap.
         Build it with -fsanitize=float-cast-overflow to make this assertion bite. */
      int32_t hb = osc_build_new("/coerce");
      osc_build_add_float(hb, 1e30f);            /* far above INT32_MAX */
      osc_build_add_double(hb, -1e300);          /* far below INT32_MIN */
      uint8_t cb[64];
      int32_t cn = osc_build_finish(hb, cb, sizeof cb);
      osc_build_free(hb);
      int32_t cm = osc_parse(cb, cn);
      int32_t v0 = osc_arg_int32(cm, 0, &ok);
      check("huge float -> int32 saturates to INT32_MAX (no UB)", v0 == 2147483647 && ok);
      int32_t v1 = osc_arg_int32(cm, 1, &ok);
      check("huge -double -> int32 saturates to INT32_MIN (no UB)", v1 == (-2147483647 - 1) && ok);
      osc_parse_free(cm); }

    { /* a bundle element length near INT32_MAX must be rejected, not overflow the
         4+len size math and write through an unsized buffer (reproduced a segfault
         in pre-release review). msg is a real 1-byte pointer so only the size guard
         can stop it. */
      int32_t hb = osc_bundle_new(1);
      uint8_t one = 0;
      int32_t r = osc_bundle_add_message(hb, &one, 2147483646);   /* 4 + len overflows int32 */
      check("huge bundle element rejected (no overflow/crash)", r == 0);
      check("bundle in error state finishes as 0", osc_bundle_finish(hb, buf, sizeof buf) == 0);
      osc_bundle_free(hb); }

    { /* a pathological '*'-heavy pattern must return promptly, not hang (ReDoS) */
      char pat[128] = "/"; char str[128] = "/";
      for (int i = 0; i < 20; i++) strcat(pat, "*a");
      strcat(pat, "*b");
      for (int i = 0; i < 40; i++) strcat(str, "a");
      int r = osc_match(pat, str);
      check("pathological match pattern returns (no ReDoS hang)", r == 0 || r == 1); }

    { /* int32 text out of range CLAMPS on every platform. It used to wrap on
         64-bit Linux and macOS (long is 64 bits there: "3000000000" sent
         -1294967296) and saturate on Windows and 32-bit Linux. */
      int32_t h = osc_build_new("/clamp");
      osc_build_add_int32_str(h, "3000000000");
      osc_build_add_int32_str(h, "-3000000000");
      osc_build_add_int32_str(h, "99999999999999999999999");
      osc_build_add_int32_str(h, "2147483647");
      osc_build_add_int32_str(h, "-2147483648");
      osc_build_add_int32_str(h, "4294967295");
      osc_build_add_int32_str(h, "2.7");
      osc_build_add_int32_str(h, "-2.7");
      int32_t n = osc_build_finish(h, buf, sizeof buf);
      osc_build_free(h);
      int32_t m = osc_parse(buf, n);
      check("int32 text 3000000000 clamps to INT32_MAX", osc_arg_int32(m, 0, &ok) == INT32_MAX && ok);
      check("int32 text -3000000000 clamps to INT32_MIN", osc_arg_int32(m, 1, &ok) == INT32_MIN && ok);
      check("int32 text beyond int64 clamps to INT32_MAX", osc_arg_int32(m, 2, &ok) == INT32_MAX && ok);
      check("int32 text INT32_MAX is exact", osc_arg_int32(m, 3, &ok) == INT32_MAX && ok);
      check("int32 text INT32_MIN is exact", osc_arg_int32(m, 4, &ok) == INT32_MIN && ok);
      check("int32 text 4294967295 clamps (did wrap to -1 on 64-bit Linux/mac)",
            osc_arg_int32(m, 5, &ok) == INT32_MAX && ok);
      check("int32 text 2.7 still reads as 2 (unchanged)", osc_arg_int32(m, 6, &ok) == 2 && ok);
      check("int32 text -2.7 still reads as -2 (unchanged)", osc_arg_int32(m, 7, &ok) == -2 && ok);
      osc_parse_free(m); }

    { /* Float text is read with a "." whatever LC_NUMERIC says: under a comma
         locale strtod("0.5") is 0, which is what an engine that left the
         user's locale in place used to send. */
      const char *loc = enter_comma_locale();
      if (!loc) {
          int must = getenv("OSCXT_REQUIRE_COMMA_LOCALE") && strcmp(getenv("OSCXT_REQUIRE_COMMA_LOCALE"), "1") == 0;
          printf("  [%s] no comma-decimal locale installed: the locale check %s\n",
                 must ? "FAIL" : "SKIP", must ? "is required here" : "did not run");
          if (must) g_fail++;
      } else {
          printf("  (LC_NUMERIC is %s, decimal mark ',')\n", loc);
          check("the comma locale really reads \"0.5\" as 0 with plain strtod", strtod("0.5", NULL) == 0.0);
          int32_t h = osc_build_new("/locale");
          osc_build_add_float_str(h, "0.5");
          osc_build_add_double_str(h, "1.25");
          osc_build_add_float_str(h, "-3.75e2");
          osc_build_add_float_str(h, "0,5");
          int32_t n = osc_build_finish(h, buf, sizeof buf);
          osc_build_free(h);
          int32_t m = osc_parse(buf, n);
          check("float text 0.5 under a comma locale is 0.5", osc_arg_float(m, 0, &ok) == 0.5f && ok);
          check("double text 1.25 under a comma locale is 1.25", osc_arg_double(m, 1, &ok) == 1.25 && ok);
          check("float text -3.75e2 under a comma locale is -375", osc_arg_float(m, 2, &ok) == -375.0f && ok);
          check("float text 0,5 reads as 0 (a '.' locale's answer, everywhere)", osc_arg_float(m, 3, &ok) == 0.0f && ok);
          osc_parse_free(m);
          setlocale(LC_NUMERIC, "C");
      } }

    { /* a bundle may not grow to where finish's 16-byte header overflows int32 */
      int32_t hb = osc_bundle_new(1);
      uint8_t one = 0;
      int32_t r = osc_bundle_add_message(hb, &one, 2147483647 - 19);   /* 4 + len = INT32_MAX - 15 */
      check("bundle element that leaves no room for the header is rejected", r == 0);
      check("that bundle finishes as 0 (error state)", osc_bundle_finish(hb, buf, sizeof buf) == 0);
      osc_bundle_free(hb); }

    { /* a blob longer than any datagram is refused before it is copied */
      int32_t h = osc_build_new("/big");
      uint8_t one = 0;
      check("2 GB blob is refused, not copied", osc_build_add_blob(h, &one, 2147483647) == 0);
      check("its builder finishes as 0 (error state)", osc_build_finish(h, buf, sizeof buf) == 0);
      osc_build_free(h); }

    { /* osc_match: nesting depth is bounded, so a hostile 63 KB address cannot
         blow the stack; real patterns are untouched */
      g_deep_pattern = (char *) malloc(3 * DEEP_GROUPS + 2);
      g_deep_pattern[0] = '/';
      for (int i = 0; i < DEEP_GROUPS; i++) memcpy(g_deep_pattern + 1 + 3 * i, "{,}", 3);
      g_deep_pattern[1 + 3 * DEEP_GROUPS] = '\0';
      check("deep {,} pattern runs on a 256 KB stack", run_deep_match());
      check("deep {,} pattern does not match (and did not crash)", g_deep_result == 0);
      free(g_deep_pattern);
      char pat[512] = "/"; char str[512] = "/";
      for (int i = 0; i < 100; i++) strcat(pat, "*a");
      for (int i = 0; i < 100; i++) strcat(str, "a");
      check("100 stars still match 100 a's", osc_match(pat, str) == 1);
      char alt[1024] = "/"; char str2[512] = "/";
      for (int i = 0; i < 200; i++) strcat(alt, "{a,b}");
      for (int i = 0; i < 200; i++) strcat(str2, (i % 2) ? "a" : "b");
      check("200 alternations still match", osc_match(alt, str2) == 1); }

    /* stale-handle no-ops */
    osc_address(999999, sbuf, sizeof sbuf);
    check("stale parse handle is a no-op", osc_arg_count(999999) == 0);
    osc_build_add_int32(888888, 1);      /* must not crash */
    check("stale builder handle is a no-op", 1);

    /* last-error is populated after a failure */
    osc_parse((const uint8_t*)"\x01\x02\x03\x04", 4);
    int32_t el = osc_last_error(sbuf, sizeof sbuf);
    check("last_error is set after a bad parse", el > 0);

    printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
