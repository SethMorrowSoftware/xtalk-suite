/*
 * sodium_smoke_test.c - the Phase 0 automated suite for the C shim.
 *
 * A crypto binding's worst failure mode is silently mangling bytes (a length
 * off by one, a wrong band on the error code). Round-trip tests alone hide that
 * (mangled-then-unmangled still matches), so this suite leans on KNOWN values
 * and on the NEGATIVE paths that the length/pointer firewall exists to catch.
 *
 * It deliberately exercises the same out-buffer dance the LCB layer performs
 * (allocate small, get -needed, reallocate, fill, copy back) entirely in C,
 * which is the closest we can get to the script -> Pointer -> C -> script trip
 * without the LiveCode engine. The plan's Phase 0 gate is exactly this round
 * trip working byte-for-byte under the sanitizers.
 *
 * Build under gcc ASan + UBSan while iterating (see CLAUDE.md / docs/development/building.md):
 * a buffer-sizing bug surfaces there, not in a passing round trip.
 */
#include "sodium_shim.h"

#include <sodium.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * The pinned libsodium version. This is a known-answer test for the BUILD: it
 * fails loudly if CMake ever links a libsodium other than the one we pinned, so
 * a silent version drift cannot sneak length-constant changes past us. Update
 * this string in the same change that re-pins the version in CMakeLists.txt.
 */
#define SXT_PINNED_SODIUM "1.0.20"

static int g_failures = 0;

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (cond) {                                                         \
            printf("  ok   - %s\n", (msg));                                 \
        } else {                                                            \
            printf("  FAIL - %s   (at %s:%d)\n", (msg), __FILE__, __LINE__);\
            g_failures++;                                                   \
        }                                                                   \
    } while (0)

/* A reusable sentinel so we can prove the shim actually wrote into the buffer
 * (and did not, say, no-op while reporting success). */
static void fill_sentinel(unsigned char *p, int n)
{
    memset(p, 0xAA, (size_t)n);
}

static int all_equal(const unsigned char *p, int n, unsigned char v)
{
    int i;
    for (i = 0; i < n; i++) {
        if (p[i] != v) {
            return 0;
        }
    }
    return 1;
}

/* sxt_last_error now FILLS a caller buffer (it never returns a const char*, so
 * the engine never free()s our static storage). This convenience returns the
 * current error length (0 == clean) so the "is/isn't clean" checks read the
 * same as before. */
static int last_error_len(void)
{
    char buf[256];
    int n = sxt_last_error(buf, (int)sizeof(buf));
    return n < 0 ? -n : n;
}

static void test_init_and_versions(void)
{
    char ver[64];
    char sodver[64];
    int n;

    printf("init + versions:\n");

    CHECK(sxt_init() == SXT_OK, "sxt_init() succeeds");
    CHECK(sxt_init() == SXT_OK, "sxt_init() is idempotent");

    CHECK(sxt_abi_version() == SXT_ABI_VERSION, "abi_version matches the header");

    /* The string entry points fill a caller buffer and return the length (never
     * a const char*; the engine would free() a returned C string). */
    n = sxt_version(ver, (int)sizeof(ver));
    CHECK(n > 0, "extension version writes a non-empty string");
    CHECK(n == 5 && strcmp(ver, "0.1.0") == 0, "extension version is the expected 0.1.0");

    /* -needed contract: a too-small buffer reports the required size, writes
     * nothing, and a buffer of exactly that size then succeeds. */
    CHECK(sxt_version(ver, 3) == -6, "version into a short buffer returns -(len+1)");

    n = sxt_sodium_version(sodver, (int)sizeof(sodver));
    CHECK(n > 0, "sodium_version writes a non-empty string");
    /* The source build (Linux/macOS) links exactly the pinned SXT_PINNED_SODIUM;
     * the Windows CI links libsodium from vcpkg, which may be a different 1.0.x
     * patch release. The whole 1.0.x line shares the same API and length
     * constants, and the functional KATs below (BLAKE2b, Argon2id, ed25519, kdf)
     * are the real guard against any drift, so here we assert only the stable
     * 1.0.x line and print the actual version for visibility. */
    CHECK(n > 0 && strncmp(sodver, "1.0.", 4) == 0,
          "linked libsodium is on the stable 1.0.x line");
    printf("       (linked libsodium %s; pinned source build is %s)\n",
           (n > 0 ? sodver : "(null)"), SXT_PINNED_SODIUM);

    /* A clean call leaves no error text behind. */
    CHECK(last_error_len() == 0, "last_error is empty after a clean call");
}

static void test_randombytes_firewall(void)
{
    unsigned char buf[32];

    printf("randombytes firewall (negative paths):\n");

    /* Negative count: a hard error in the error band, with a message. */
    CHECK(sxt_randombytes(buf, (int)sizeof(buf), -1) == SXT_ERR_BADARG,
          "negative count -> SXT_ERR_BADARG");
    CHECK(last_error_len() != 0, "an error sets last_error text");

    /* Oversize count: rejected before it could collide with the error band. */
    CHECK(sxt_randombytes(buf, (int)sizeof(buf), SXT_MAX_BUFFER) == SXT_ERR_BADARG,
          "count >= SXT_MAX_BUFFER -> SXT_ERR_BADARG");

    /* cap < n is a SIZE QUERY, not an error: it reports -needed even with a
     * null/zero-capacity buffer, because nothing is written. */
    CHECK(sxt_randombytes(NULL, 0, 16) == -16,
          "size query (cap<n) returns -needed, null buffer allowed");

    /* But once cap is big enough and n > 0, a null destination is a hard error
     * (we are about to write and refuse to write through NULL). */
    CHECK(sxt_randombytes(NULL, 32, 16) == SXT_ERR_BADARG,
          "null buffer with adequate cap and n>0 -> SXT_ERR_BADARG");

    /* Zero bytes is a defined no-op success (yields an empty Data upstream). */
    CHECK(sxt_randombytes(buf, (int)sizeof(buf), 0) == 0, "n==0 writes nothing, returns 0");
    CHECK(sxt_randombytes(NULL, 0, 0) == 0, "n==0 with null/zero buffer returns 0");
}

static void test_randombytes_fills_and_has_entropy(void)
{
    unsigned char a[32];
    unsigned char b[32];

    printf("randombytes fills the buffer with entropy:\n");

    fill_sentinel(a, (int)sizeof(a));
    CHECK(sxt_randombytes(a, (int)sizeof(a), (int)sizeof(a)) == (int)sizeof(a),
          "fill of exactly cap bytes returns the byte count");
    CHECK(!all_equal(a, (int)sizeof(a), 0xAA), "the shim actually overwrote the sentinel");

    CHECK(sxt_randombytes(b, (int)sizeof(b), (int)sizeof(b)) == (int)sizeof(b),
          "second independent draw also succeeds");
    /* Two 32-byte CSPRNG draws colliding is a ~2^-256 event; a match here means
     * the buffer was not actually (re)filled. */
    CHECK(memcmp(a, b, sizeof(a)) != 0, "two draws differ (entropy is flowing)");

    CHECK(last_error_len() == 0, "last_error cleared by the successful call");
}

/*
 * The headline Phase 0 test: drive the exact out-buffer contract the LCB layer
 * implements (allocate a deliberately-too-small block, get -needed, reallocate
 * to the required size, fill, "copy back"). This is the C mirror of the
 * Data round trip the plan insists on proving before anything else.
 */
static void test_out_buffer_retry_round_trip(void)
{
    const int want = 48;
    int cap = 4;                 /* start too small on purpose */
    int rc;
    int retries = 0;
    unsigned char *block;
    unsigned char *copy;

    printf("out-buffer -needed retry round trip:\n");

    block = (unsigned char *)malloc((size_t)cap);
    CHECK(block != NULL, "initial (too-small) allocation");

    for (;;) {
        rc = sxt_randombytes(block, cap, want);
        if (rc >= 0) {
            break;                                  /* fit: rc bytes written */
        }
        if (rc <= SXT_ERR_BASE) {
            CHECK(0, "unexpected hard error during retry");
            free(block);
            return;
        }
        /* rc is in (SXT_ERR_BASE, 0): it is -needed. Grow and retry. */
        cap = -rc;
        retries++;
        block = (unsigned char *)realloc(block, (size_t)cap);
        CHECK(block != NULL, "reallocation to the needed size");
    }

    CHECK(retries == 1, "exactly one retry was needed (-needed then fit)");
    CHECK(rc == want, "final call wrote exactly the requested byte count");
    CHECK(cap == want, "buffer was grown to exactly the needed size");

    /* "Copy back" into an independently owned buffer, the way the LCB layer
     * copies the written bytes into a fresh Data with MCDataCreateWithBytes. */
    copy = (unsigned char *)malloc((size_t)rc);
    CHECK(copy != NULL, "result-copy allocation");
    memcpy(copy, block, (size_t)rc);
    CHECK(memcmp(copy, block, (size_t)rc) == 0, "copied bytes match (round trip intact)");

    free(copy);
    free(block);
}

/* ========================================================================== *
 * Phase 1: hashing + encoding + constant-time compare.
 * ========================================================================== */

static int hash_hex_equals(const char *msg, int msglen, int outlen,
                           const char *expected_hex)
{
    unsigned char dig[64];
    char hex[2 * 64 + 1];
    if (sxt_generichash(dig, (int)sizeof(dig), outlen,
                        (const unsigned char *)msg, msglen, NULL, 0) != outlen) {
        return 0;
    }
    if (sxt_bin2hex(hex, (int)sizeof(hex), dig, outlen) != outlen * 2) {
        return 0;
    }
    return strcmp(hex, expected_hex) == 0;
}

static void test_hashing(void)
{
    unsigned char dig[64];
    char small[8];
    unsigned char k[32];
    unsigned char a[32];
    unsigned char b[32];

    printf("hashing (BLAKE2b KATs + firewall):\n");

    /* Independent published / RFC 7693 known-answer vectors. */
    CHECK(hash_hex_equals("", 0, 32,
            "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),
          "BLAKE2b-256(\"\") matches the published vector");
    CHECK(hash_hex_equals("abc", 3, 32,
            "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"),
          "BLAKE2b-256(\"abc\") matches the published vector");
    CHECK(hash_hex_equals("abc", 3, 64,
            "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
            "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"),
          "BLAKE2b-512(\"abc\") matches the RFC 7693 vector");

    /* A keyed hash must differ from the unkeyed hash of the same message. */
    memset(k, 0x42, sizeof(k));
    CHECK(sxt_generichash(a, 32, 32, (const unsigned char *)"abc", 3, k, 32) == 32,
          "keyed hash succeeds");
    CHECK(sxt_generichash(b, 32, 32, (const unsigned char *)"abc", 3, NULL, 0) == 32,
          "unkeyed hash succeeds");
    CHECK(memcmp(a, b, 32) != 0, "keyed and unkeyed digests differ");

    /* Firewall: out-of-range digest length, then the -needed path. */
    CHECK(sxt_generichash(dig, 64, 8, (const unsigned char *)"x", 1, NULL, 0) == SXT_ERR_BADARG,
          "digest length below min -> BADARG");
    CHECK(sxt_generichash(dig, 64, 100, (const unsigned char *)"x", 1, NULL, 0) == SXT_ERR_BADARG,
          "digest length above max -> BADARG");
    CHECK(sxt_generichash((unsigned char *)small, 8, 32,
                          (const unsigned char *)"x", 1, NULL, 0) == -32,
          "too-small digest buffer -> -needed (32)");
}

static void test_encoding(void)
{
    unsigned char bin[4] = {0xde, 0xad, 0xbe, 0xef};
    unsigned char three[3] = {0xff, 0xff, 0xff};
    unsigned char hello[5] = {'H', 'e', 'l', 'l', 'o'};
    unsigned char back[16];
    char hex[16];
    char b64[16];
    int r;

    printf("encoding (hex / base64 round trips + KATs):\n");

    r = sxt_bin2hex(hex, (int)sizeof(hex), bin, 4);
    CHECK(r == 8 && strcmp(hex, "deadbeef") == 0, "bin2hex({de,ad,be,ef}) == \"deadbeef\"");

    r = sxt_hex2bin(back, (int)sizeof(back), "deadbeef", 8);
    CHECK(r == 4 && memcmp(back, bin, 4) == 0, "hex2bin round trip");

    CHECK(sxt_hex2bin(back, (int)sizeof(back), "deadbeeg", 8) == SXT_ERR_ENCODING,
          "malformed hex -> SXT_ERR_ENCODING");

    r = sxt_bin2base64(b64, (int)sizeof(b64), three, 3,
                       sxt_base64_variant_urlsafe_no_padding());
    CHECK(r == 4 && strcmp(b64, "____") == 0,
          "bin2base64 urlsafe-no-pad({ff,ff,ff}) == \"____\"");

    r = sxt_bin2base64(b64, (int)sizeof(b64), hello, 5, sxt_base64_variant_original());
    CHECK(r == 8 && strcmp(b64, "SGVsbG8=") == 0,
          "bin2base64 original(\"Hello\") == \"SGVsbG8=\"");
    r = sxt_base642bin(back, (int)sizeof(back), "SGVsbG8=", 8, sxt_base64_variant_original());
    CHECK(r == 5 && memcmp(back, hello, 5) == 0, "base642bin round trip");

    /* 4 bytes need 9 (8 hex chars + NUL); a 2-byte buffer reports -needed. */
    CHECK(sxt_bin2hex(hex, 2, bin, 4) == -9, "bin2hex short buffer -> -needed (9)");

    /* Regression guard for the LCB sxBase642Bin allocation (sodium.lcb): that
     * wrapper sizes its out buffer as b64len + 4, so the C decoder must NOT
     * report -needed for any valid input at that capacity, down to the smallest
     * groups. The old wrapper allocated b64len + 1, which is one byte short for a
     * 4-char group (needs 6, got 5): decoding "____" returned -6 and the LCB then
     * threw, so a plain base64 round trip of any 3-byte value failed. */
    {
        int variant = sxt_base64_variant_urlsafe_no_padding();
        /* the exact failing case, at the OLD (b64len + 1) capacity: -needed. */
        CHECK(sxt_base642bin(back, 4 + 1, "____", 4, variant) == -6,
              "base642bin(\"____\", cap=b64len+1) is one byte short -> -needed (6)");
        /* the NEW (b64len + 4) capacity decodes the 3 bytes cleanly. */
        r = sxt_base642bin(back, 4 + 4, "____", 4, variant);
        CHECK(r == 3 && back[0] == 0xff && back[1] == 0xff && back[2] == 0xff,
              "base642bin(\"____\", cap=b64len+4) decodes {ff,ff,ff}");
        /* empty input at the wrapper capacity is a clean 0-byte decode. */
        CHECK(sxt_base642bin(back, 0 + 4, "", 0, variant) == 0,
              "base642bin(\"\", cap=b64len+4) decodes to 0 bytes");
        /* a full round trip of a 3-byte value at the wrapper capacity. */
        r = sxt_bin2base64(b64, (int)sizeof(b64), three, 3, variant);
        CHECK(r == 4, "bin2base64(3 bytes) is a 4-char group");
        CHECK(sxt_base642bin(back, r + 4, b64, r, variant) == 3 &&
              memcmp(back, three, 3) == 0,
              "base64 round trip of a 3-byte value at cap=b64len+4 succeeds");
    }
}

static void test_memequal(void)
{
    unsigned char a[4] = {1, 2, 3, 4};
    unsigned char b[4] = {1, 2, 3, 4};
    unsigned char c[4] = {1, 2, 3, 5};
    unsigned char d[3] = {1, 2, 3};

    printf("constant-time compare:\n");
    CHECK(sxt_memequal(a, 4, b, 4) == 1, "equal buffers -> 1");
    CHECK(sxt_memequal(a, 4, c, 4) == 0, "differing buffers -> 0");
    CHECK(sxt_memequal(a, 4, d, 3) == 0, "different lengths -> 0");
    CHECK(sxt_memequal(NULL, 0, NULL, 0) == 1, "two empty buffers -> 1");
}

/* ========================================================================== *
 * Phase 2: secretbox + AEAD + Argon2id.
 * ========================================================================== */

static void test_secretbox(void)
{
    const unsigned char msg[5] = {'h', 'e', 'l', 'l', 'o'};
    unsigned char key[32];
    unsigned char wrong[32];
    unsigned char box[24 + 5 + 16];
    unsigned char plain[8];
    unsigned char manual[8];
    int boxlen;
    int r;

    printf("secretbox (round trip, framing, auth):\n");
    memset(key, 0x11, sizeof(key));
    memset(wrong, 0x22, sizeof(wrong));

    boxlen = sxt_secretbox(box, (int)sizeof(box), msg, 5, key, 32);
    CHECK(boxlen == 24 + 5 + 16, "secretbox output is nonce + msg + mac");

    r = sxt_secretbox_open(plain, (int)sizeof(plain), box, boxlen, key, 32);
    CHECK(r == 5 && memcmp(plain, msg, 5) == 0, "round trip recovers the plaintext");

    /* Framing cross-check: the leading 24 bytes ARE the nonce, so libsodium's
     * raw open of box[24:] under that nonce must recover the same plaintext. */
    CHECK(crypto_secretbox_open_easy(manual, box + 24,
                                     (unsigned long long)(boxlen - 24),
                                     box, key) == 0 &&
          memcmp(manual, msg, 5) == 0,
          "framing is exactly nonce||ciphertext (raw libsodium agrees)");

    box[24] ^= 0x01;
    CHECK(sxt_secretbox_open(plain, (int)sizeof(plain), box, boxlen, key, 32) == SXT_ERR_AUTH,
          "a tampered ciphertext byte -> SXT_ERR_AUTH");
    box[24] ^= 0x01;

    CHECK(sxt_secretbox_open(plain, (int)sizeof(plain), box, boxlen, wrong, 32) == SXT_ERR_AUTH,
          "a wrong key -> SXT_ERR_AUTH");

    CHECK(sxt_secretbox(box, (int)sizeof(box), msg, 5, key, 16) == SXT_ERR_BADARG,
          "wrong key length -> BADARG");
    CHECK(sxt_secretbox_open(plain, (int)sizeof(plain), box, 10, key, 32) == SXT_ERR_BADARG,
          "too-short ciphertext -> BADARG");
}

static void test_aead(void)
{
    const unsigned char msg[4] = {'d', 'a', 't', 'a'};
    const unsigned char ad[3] = {'h', 'd', 'r'};
    const unsigned char ad2[3] = {'h', 'd', 'x'};
    unsigned char key[32];
    unsigned char box[24 + 4 + 16];
    unsigned char plain[8];
    int boxlen;
    int r;

    printf("aead xchacha20poly1305 (AD binding + auth):\n");
    memset(key, 0x33, sizeof(key));

    boxlen = sxt_aead_encrypt(box, (int)sizeof(box), msg, 4, ad, 3, key, 32);
    CHECK(boxlen == 24 + 4 + 16, "aead output is nonce + msg + tag");

    r = sxt_aead_decrypt(plain, (int)sizeof(plain), box, boxlen, ad, 3, key, 32);
    CHECK(r == 4 && memcmp(plain, msg, 4) == 0, "round trip with AD recovers plaintext");

    CHECK(sxt_aead_decrypt(plain, (int)sizeof(plain), box, boxlen, ad2, 3, key, 32) == SXT_ERR_AUTH,
          "wrong associated data -> SXT_ERR_AUTH");

    box[24] ^= 0x80;
    CHECK(sxt_aead_decrypt(plain, (int)sizeof(plain), box, boxlen, ad, 3, key, 32) == SXT_ERR_AUTH,
          "tampered ciphertext -> SXT_ERR_AUTH");
    box[24] ^= 0x80;

    boxlen = sxt_aead_encrypt(box, (int)sizeof(box), msg, 4, NULL, 0, key, 32);
    r = sxt_aead_decrypt(plain, (int)sizeof(plain), box, boxlen, NULL, 0, key, 32);
    CHECK(r == 4 && memcmp(plain, msg, 4) == 0, "round trip with empty AD");
}

static void test_pwhash(void)
{
    const char *pinned =
        "$argon2id$v=19$m=1024,t=2,p=1$ETM71WSPez+kmgsM2ZIpqw"
        "$Pk8d58NRCAf201AQ7VFpsU7ru+EkpOQi8Ju8PzQCxZI";
    unsigned char salt[16];
    unsigned char key[32];
    char hashstr[128];
    char hex[2 * 32 + 1];
    int r;

    printf("Argon2id (KAT + pwhash_str verify):\n");
    memset(salt, 'A', sizeof(salt));

    /* Deterministic Argon2id KAT (fixed salt + ops=2 + mem=1 MiB). */
    r = sxt_pwhash(key, 32, 32, (const unsigned char *)"password", 8, salt, 16,
                   "2", "1048576");
    CHECK(r == 32, "pwhash derives 32 bytes");
    sxt_bin2hex(hex, (int)sizeof(hex), key, 32);
    CHECK(strcmp(hex, "7216b4357104ed7f8a4e900e9cc7a63a0786855abe0b59340053ee43f841228a") == 0,
          "Argon2id(password, salt=Ax16, ops=2, mem=1MiB) matches the KAT");

    CHECK(sxt_pwhash(key, 32, 32, (const unsigned char *)"password", 8, salt, 8,
                     "2", "1048576") == SXT_ERR_BADARG,
          "wrong salt length -> BADARG");
    CHECK(sxt_pwhash(key, 32, 32, (const unsigned char *)"password", 8, salt, 16,
                     "abc", "1048576") == SXT_ERR_BADARG,
          "non-numeric opslimit -> BADARG");

    /* pwhash_str round trip, then verify against a pinned stored hash. */
    r = sxt_pwhash_str(hashstr, (int)sizeof(hashstr),
                       (const unsigned char *)"hunter2", 7, "2", "1048576");
    CHECK(r > 0, "pwhash_str produces a string");
    CHECK(sxt_pwhash_str_verify(hashstr, (const unsigned char *)"hunter2", 7) == 1,
          "pwhash_str verify accepts the right passphrase");
    CHECK(sxt_pwhash_str_verify(hashstr, (const unsigned char *)"nope", 4) == 0,
          "pwhash_str verify rejects the wrong passphrase");
    CHECK(sxt_pwhash_str_verify(pinned, (const unsigned char *)"password", 8) == 1,
          "verify accepts the pinned stored Argon2id string");
    CHECK(sxt_pwhash_str_verify(pinned, (const unsigned char *)"wrongpass", 9) == 0,
          "verify rejects a wrong passphrase against the pinned string");
}

/* ========================================================================== *
 * Phase 3: streaming AEAD (secretstream) + file helpers.
 * ========================================================================== */

static void test_secretstream(void)
{
    const unsigned char m1[5] = {'a', 'l', 'p', 'h', 'a'};
    const unsigned char m2[6] = {'b', 'r', 'a', 'v', 'o', '!'};
    const unsigned char m3[1] = {'z'};
    unsigned char key[32];
    unsigned char header[24];
    unsigned char ct1[5 + 17];
    unsigned char ct2[6 + 17];
    unsigned char ct3[1 + 17];
    unsigned char pt[8];
    int tag_msg = sxt_secretstream_tag_message();
    int tag_fin = sxt_secretstream_tag_final();
    int hpush;
    int hpull;
    int h2;
    int r;

    printf("secretstream (streaming AEAD + handle table):\n");
    memset(key, 0x44, sizeof(key));

    hpush = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
    CHECK(hpush > 0, "init_push returns a positive handle");
    CHECK(sxt_secretstream_push(hpush, ct1, (int)sizeof(ct1), m1, 5, NULL, 0, tag_msg) == 5 + 17,
          "push chunk 1");
    CHECK(sxt_secretstream_push(hpush, ct2, (int)sizeof(ct2), m2, 6, NULL, 0, tag_msg) == 6 + 17,
          "push chunk 2");
    CHECK(sxt_secretstream_push(hpush, ct3, (int)sizeof(ct3), m3, 1, NULL, 0, tag_fin) == 1 + 17,
          "push final chunk");

    /* A push handle must not be usable to pull. */
    CHECK(sxt_secretstream_pull(hpush, pt, (int)sizeof(pt), ct1, (int)sizeof(ct1), NULL, 0)
              == SXT_ERR_BADHANDLE,
          "pull on a push handle -> BADHANDLE");

    hpull = sxt_secretstream_init_pull(header, (int)sizeof(header), key, 32);
    CHECK(hpull > 0, "init_pull returns a positive handle");

    r = sxt_secretstream_pull(hpull, pt, (int)sizeof(pt), ct1, (int)sizeof(ct1), NULL, 0);
    CHECK(r == 5 && memcmp(pt, m1, 5) == 0, "pull chunk 1 recovers plaintext");
    CHECK(sxt_secretstream_last_tag(hpull) == tag_msg, "chunk 1 tag is MESSAGE");

    r = sxt_secretstream_pull(hpull, pt, (int)sizeof(pt), ct2, (int)sizeof(ct2), NULL, 0);
    CHECK(r == 6 && memcmp(pt, m2, 6) == 0, "pull chunk 2 recovers plaintext");

    r = sxt_secretstream_pull(hpull, pt, (int)sizeof(pt), ct3, (int)sizeof(ct3), NULL, 0);
    CHECK(r == 1 && pt[0] == 'z', "pull final chunk recovers plaintext");
    CHECK(sxt_secretstream_last_tag(hpull) == tag_fin, "final chunk tag is FINAL");

    /* A tampered chunk fails authentication on a fresh pull stream. */
    h2 = sxt_secretstream_init_pull(header, (int)sizeof(header), key, 32);
    ct1[20] ^= 0x01;
    CHECK(sxt_secretstream_pull(h2, pt, (int)sizeof(pt), ct1, (int)sizeof(ct1), NULL, 0)
              == SXT_ERR_AUTH,
          "a tampered chunk -> SXT_ERR_AUTH");
    ct1[20] ^= 0x01;
    sxt_free_stream(h2);

    sxt_free_stream(hpush);
    sxt_free_stream(hpull);
    sxt_free_stream(hpush);   /* idempotent: freeing again is a clean no-op */
    CHECK(sxt_secretstream_last_tag(hpull) == SXT_ERR_BADHANDLE,
          "a freed handle is now stale -> BADHANDLE");
}

/* Explicit rekey: both sides must rekey at the same stream position to stay in
 * sync; a one-sided rekey desyncs and the next chunk fails to verify. */
static void test_secretstream_rekey(void)
{
    const unsigned char m1[3] = {'o', 'n', 'e'};
    const unsigned char m2[3] = {'t', 'w', 'o'};
    unsigned char key[32];
    unsigned char header[24];
    unsigned char c1[3 + 17], c2[3 + 17];
    unsigned char pt[8];
    int tag_msg = sxt_secretstream_tag_message();
    int hpush, hpull;
    int r;

    printf("secretstream explicit rekey (forward secrecy in-session):\n");
    memset(key, 0x77, sizeof key);

    hpush = sxt_secretstream_init_push(header, (int)sizeof header, key, 32);
    CHECK(hpush > 0, "init_push");
    CHECK(sxt_secretstream_push(hpush, c1, (int)sizeof c1, m1, 3, NULL, 0, tag_msg) == 3 + 17, "push chunk 1");
    CHECK(sxt_secretstream_rekey(hpush) == SXT_OK, "rekey push side");
    CHECK(sxt_secretstream_push(hpush, c2, (int)sizeof c2, m2, 3, NULL, 0, tag_msg) == 3 + 17,
          "push chunk 2 after rekey");

    /* matched rekey: pull side rekeys at the same point and both chunks decrypt. */
    hpull = sxt_secretstream_init_pull(header, (int)sizeof header, key, 32);
    CHECK(hpull > 0, "init_pull");
    r = sxt_secretstream_pull(hpull, pt, (int)sizeof pt, c1, (int)sizeof c1, NULL, 0);
    CHECK(r == 3 && memcmp(pt, m1, 3) == 0, "pull chunk 1");
    CHECK(sxt_secretstream_rekey(hpull) == SXT_OK, "rekey pull side (matched)");
    r = sxt_secretstream_pull(hpull, pt, (int)sizeof pt, c2, (int)sizeof c2, NULL, 0);
    CHECK(r == 3 && memcmp(pt, m2, 3) == 0, "pull chunk 2 after matched rekey");
    sxt_free_stream(hpull);

    /* one-sided rekey: pull WITHOUT rekeying after chunk 1 -> chunk 2 fails auth. */
    hpull = sxt_secretstream_init_pull(header, (int)sizeof header, key, 32);
    CHECK(hpull > 0, "init_pull (desync case)");
    r = sxt_secretstream_pull(hpull, pt, (int)sizeof pt, c1, (int)sizeof c1, NULL, 0);
    CHECK(r == 3, "pull chunk 1 (desync case)");
    CHECK(sxt_secretstream_pull(hpull, pt, (int)sizeof pt, c2, (int)sizeof c2, NULL, 0) == SXT_ERR_AUTH,
          "unmatched rekey -> next chunk fails auth");
    sxt_free_stream(hpull);

    CHECK(sxt_secretstream_rekey(999999) == SXT_ERR_BADHANDLE, "rekey on a bad handle -> BADHANDLE");
    sxt_free_stream(hpush);
}

static int write_pattern_file(const char *path, int n)
{
    FILE *f = fopen(path, "wb");
    int i;
    if (f == NULL) {
        return 0;
    }
    for (i = 0; i < n; i++) {
        fputc((int)((unsigned char)((i * 37 + 11) & 0xFF)), f);
    }
    return fclose(f) == 0;
}

static int files_equal(const char *a, const char *b)
{
    FILE *fa = fopen(a, "rb");
    FILE *fb = fopen(b, "rb");
    int ca;
    int cb;
    int eq = 1;
    if (fa == NULL || fb == NULL) {
        if (fa != NULL) { fclose(fa); }
        if (fb != NULL) { fclose(fb); }
        return 0;
    }
    do {
        ca = fgetc(fa);
        cb = fgetc(fb);
        if (ca != cb) { eq = 0; break; }
    } while (ca != EOF);
    fclose(fa);
    fclose(fb);
    return eq;
}

static long file_size(const char *p)
{
    FILE *f = fopen(p, "rb");
    long n;
    if (f == NULL) {
        return -1;
    }
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fclose(f);
    return n;
}

static void test_file_helpers(void)
{
    const char *plain = "sxt_ft_plain.tmp";
    const char *enc = "sxt_ft_enc.tmp";
    const char *dec = "sxt_ft_dec.tmp";
    const char *trunc = "sxt_ft_trunc.tmp";
    unsigned char key[32];
    unsigned char wrong[32];
    long encsz;

    printf("file helpers (secretstream, multi-chunk + truncation):\n");
    memset(key, 0x55, sizeof(key));
    memset(wrong, 0x66, sizeof(wrong));

    CHECK(write_pattern_file(plain, 40000),
          "wrote a 40000-byte plaintext (spans multiple chunks)");
    CHECK(sxt_encrypt_file(plain, enc, key, 32) == SXT_OK, "encrypt_file succeeds");
    CHECK(sxt_decrypt_file(enc, dec, key, 32) == SXT_OK, "decrypt_file succeeds");
    CHECK(files_equal(plain, dec), "decrypted file matches the original byte for byte");

    CHECK(sxt_decrypt_file(enc, dec, wrong, 32) == SXT_ERR_AUTH, "wrong key -> SXT_ERR_AUTH");

    encsz = file_size(enc);
    CHECK(encsz > 40, "ciphertext is non-trivial");
    {
        FILE *fi = fopen(enc, "rb");
        FILE *fo = fopen(trunc, "wb");
        long keep = encsz - 20;
        long i;
        int c;
        if (fi != NULL && fo != NULL) {
            for (i = 0; i < keep; i++) {
                c = fgetc(fi);
                if (c == EOF) { break; }
                fputc(c, fo);
            }
        }
        if (fi != NULL) { fclose(fi); }
        if (fo != NULL) { fclose(fo); }
        CHECK(sxt_decrypt_file(trunc, dec, key, 32) == SXT_ERR_AUTH,
              "a truncated ciphertext -> SXT_ERR_AUTH (truncation detected)");
        remove(trunc);
    }

    CHECK(sxt_decrypt_file("sxt_ft_no_such_file.tmp", dec, key, 32) == SXT_ERR_IO,
          "missing source file -> SXT_ERR_IO");

    remove(plain);
    remove(enc);
    remove(dec);
}

/* ========================================================================== *
 * Phase 4: public-key boxes (X25519) + signatures (ed25519).
 * ========================================================================== */

static void test_sign(void)
{
    unsigned char seed[32];
    unsigned char pk[32];
    unsigned char sk[64];
    unsigned char sig[64];
    unsigned char signed_msg[64 + 3];
    unsigned char back[8];
    char hex[2 * 64 + 1];
    int r;
    int sl;

    printf("ed25519 sign/verify (deterministic KAT + auth):\n");
    memset(seed, 0, sizeof(seed));

    CHECK(sxt_sign_keypair_from_seed(pk, 32, sk, 64, seed, 32) == SXT_OK,
          "seeded keypair succeeds");
    sxt_bin2hex(hex, (int)sizeof(hex), pk, 32);
    CHECK(strcmp(hex, "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29") == 0,
          "zero-seed public key matches the published ed25519 anchor");

    r = sxt_sign_detached(sig, 64, (const unsigned char *)"abc", 3, sk, 64);
    CHECK(r == 64, "detached signature is 64 bytes");
    sxt_bin2hex(hex, (int)sizeof(hex), sig, 64);
    CHECK(strcmp(hex,
            "885dfb07cab2796eb960531a2f09b972ad59b97bb125bef5fdda0855d6bebebf"
            "24447e705fa11575639df396c201ccf52a1a16b014a7a2f0ce73a7a161757308") == 0,
          "signature of \"abc\" matches the deterministic KAT");

    CHECK(sxt_sign_verify_detached(sig, 64, (const unsigned char *)"abc", 3, pk, 32) == 1,
          "verify accepts the valid signature");
    CHECK(sxt_sign_verify_detached(sig, 64, (const unsigned char *)"abd", 3, pk, 32) == 0,
          "verify rejects a modified message");
    sig[0] ^= 0x01;
    CHECK(sxt_sign_verify_detached(sig, 64, (const unsigned char *)"abc", 3, pk, 32) == 0,
          "verify rejects a modified signature");
    sig[0] ^= 0x01;

    /* attached form round trip + tamper */
    sl = sxt_sign(signed_msg, (int)sizeof(signed_msg), (const unsigned char *)"abc", 3, sk, 64);
    CHECK(sl == 64 + 3, "attached signed message is sig + msg");
    CHECK(sxt_sign_open(back, (int)sizeof(back), signed_msg, sl, pk, 32) == 3 &&
          memcmp(back, "abc", 3) == 0,
          "sign_open recovers the message");
    signed_msg[64] ^= 0x01;
    CHECK(sxt_sign_open(back, (int)sizeof(back), signed_msg, sl, pk, 32) == SXT_ERR_AUTH,
          "sign_open rejects a tampered signed message");
}

static void test_box(void)
{
    const unsigned char msg[7] = {'s', 'e', 'c', 'r', 'e', 't', 's'};
    unsigned char apk[32], ask[32];
    unsigned char bpk[32], bsk[32];
    unsigned char cpk[32], csk[32];
    unsigned char box[24 + 7 + 16];
    unsigned char sealed[7 + 48];
    unsigned char plain[8];
    int boxlen;
    int sealedlen;
    int r;

    printf("public-key box + seal (X25519):\n");
    CHECK(sxt_box_keypair(apk, 32, ask, 32) == SXT_OK, "keypair A");
    CHECK(sxt_box_keypair(bpk, 32, bsk, 32) == SXT_OK, "keypair B");
    CHECK(sxt_box_keypair(cpk, 32, csk, 32) == SXT_OK, "keypair C");

    boxlen = sxt_box(box, (int)sizeof(box), msg, 7, bpk, 32, ask, 32);  /* A -> B */
    CHECK(boxlen == 24 + 7 + 16, "box output is nonce + msg + mac");
    r = sxt_box_open(plain, (int)sizeof(plain), box, boxlen, apk, 32, bsk, 32);
    CHECK(r == 7 && memcmp(plain, msg, 7) == 0, "box round trip A->B recovers plaintext");

    CHECK(sxt_box_open(plain, (int)sizeof(plain), box, boxlen, apk, 32, csk, 32) == SXT_ERR_AUTH,
          "wrong recipient secret key -> SXT_ERR_AUTH");
    box[24] ^= 0x01;
    CHECK(sxt_box_open(plain, (int)sizeof(plain), box, boxlen, apk, 32, bsk, 32) == SXT_ERR_AUTH,
          "tampered box -> SXT_ERR_AUTH");
    box[24] ^= 0x01;

    sealedlen = sxt_box_seal(sealed, (int)sizeof(sealed), msg, 7, bpk, 32);
    CHECK(sealedlen == 7 + 48, "seal output is msg + sealbytes");
    r = sxt_box_seal_open(plain, (int)sizeof(plain), sealed, sealedlen, bpk, 32, bsk, 32);
    CHECK(r == 7 && memcmp(plain, msg, 7) == 0, "seal round trip to B recovers plaintext");
    CHECK(sxt_box_seal_open(plain, (int)sizeof(plain), sealed, sealedlen, cpk, 32, csk, 32)
              == SXT_ERR_AUTH,
          "seal open with the wrong keypair -> SXT_ERR_AUTH");
}

/* ========================================================================== *
 * Phase 5: key derivation (kdf), key exchange (kx), padding.
 * ========================================================================== */

static void test_kdf(void)
{
    unsigned char master[32];
    unsigned char sub[32];
    char hex[2 * 32 + 1];

    printf("kdf (deterministic subkey derivation):\n");
    memset(master, 0x01, sizeof(master));

    CHECK(sxt_kdf_derive(sub, 32, 32, "1", (const unsigned char *)"SXTctx00", 8, master, 32) == 32,
          "kdf_derive produces a 32-byte subkey");
    sxt_bin2hex(hex, (int)sizeof(hex), sub, 32);
    CHECK(strcmp(hex, "dc9d1a0879b1884c4cafbc2a68d1b22926e8a6a0043f458c7f1bc370b032058f") == 0,
          "kdf subkey (master=01x32, id=1, ctx=SXTctx00) matches the KAT");

    /* a different id gives a different subkey */
    {
        unsigned char sub2[32];
        CHECK(sxt_kdf_derive(sub2, 32, 32, "2", (const unsigned char *)"SXTctx00", 8, master, 32) == 32,
              "kdf_derive with a different id succeeds");
        CHECK(memcmp(sub, sub2, 32) != 0, "different subkey ids give different subkeys");
    }
    CHECK(sxt_kdf_derive(sub, 32, 32, "1", (const unsigned char *)"short", 5, master, 32)
              == SXT_ERR_BADARG,
          "wrong context length -> BADARG");
}

static void test_kx(void)
{
    unsigned char cpk[32], csk[32];
    unsigned char spk[32], ssk[32];
    unsigned char crx[32], ctx[32];
    unsigned char srx[32], stx[32];

    printf("kx (key exchange agreement):\n");
    CHECK(sxt_kx_keypair(cpk, 32, csk, 32) == SXT_OK, "client keypair");
    CHECK(sxt_kx_keypair(spk, 32, ssk, 32) == SXT_OK, "server keypair");

    CHECK(sxt_kx_client_session_keys(crx, 32, ctx, 32, cpk, 32, csk, 32, spk, 32) == SXT_OK,
          "client session keys");
    CHECK(sxt_kx_server_session_keys(srx, 32, stx, 32, spk, 32, ssk, 32, cpk, 32) == SXT_OK,
          "server session keys");

    CHECK(memcmp(crx, stx, 32) == 0, "client rx equals server tx");
    CHECK(memcmp(ctx, srx, 32) == 0, "client tx equals server rx");
}

/* Seeded (deterministic) box + kx keypairs, ABI 5: a single master seed can
 * derive an encryption keypair, so one backup blob reconstructs the identity.
 * KATs pin the fixed-seed public keys so a silent libsodium change would fail. */
static void test_seeded_keypairs(void)
{
    unsigned char seed[32];
    unsigned char pk1[32], sk1[32], pk2[32], sk2[32];
    unsigned char kpk[32], ksk[32];
    char hex[2 * 32 + 1];

    printf("seeded box/kx keypairs (deterministic, ABI 5):\n");
    memset(seed, 0x42, sizeof seed);

    CHECK(sxt_box_seedbytes() == 32, "box seedbytes is 32");
    CHECK(sxt_kx_seedbytes() == 32, "kx seedbytes is 32");

    /* deterministic: the same seed yields the same box keypair, and it matches
     * the published crypto_box_seed_keypair vector for seed = 0x42 x 32. */
    CHECK(sxt_box_keypair_from_seed(pk1, 32, sk1, 32, seed, 32) == SXT_OK, "box seeded keypair");
    CHECK(sxt_box_keypair_from_seed(pk2, 32, sk2, 32, seed, 32) == SXT_OK, "box seeded keypair (again)");
    CHECK(memcmp(pk1, pk2, 32) == 0 && memcmp(sk1, sk2, 32) == 0,
          "box seeded keypair is deterministic");
    sxt_bin2hex(hex, (int)sizeof hex, pk1, 32);
    CHECK(strcmp(hex, "cc4f2cdb695dd766f34118eb67b98652fed1d8bc49c330b119bbfa8a64989378") == 0,
          "box seeded pubkey (seed 0x42x32) matches the KAT");

    /* the seeded secret key really corresponds to the public key: a sealed box to
     * pk1 opens with (pk1, sk1). */
    {
        const unsigned char msg[3] = {'h', 'i', '!'};
        unsigned char sealed[3 + 48];
        unsigned char plain[8];
        int sl = sxt_box_seal(sealed, (int)sizeof sealed, msg, 3, pk1, 32);
        CHECK(sl == 3 + 48, "seal to the seeded pubkey");
        CHECK(sxt_box_seal_open(plain, (int)sizeof plain, sealed, sl, pk1, 32, sk1, 32) == 3 &&
              memcmp(plain, msg, 3) == 0, "seeded keypair opens its own sealed box");
    }

    /* kx seeded keypair: deterministic + KAT for the same seed. */
    CHECK(sxt_kx_keypair_from_seed(kpk, 32, ksk, 32, seed, 32) == SXT_OK, "kx seeded keypair");
    sxt_bin2hex(hex, (int)sizeof hex, kpk, 32);
    CHECK(strcmp(hex, "191957342799412f1a3cbeae3d3af8cf5441f2fb51d88a8c2a56175f1fae3f3a") == 0,
          "kx seeded pubkey (seed 0x42x32) matches the KAT");

    /* wrong seed length is a clean BADARG, not a crash. */
    CHECK(sxt_box_keypair_from_seed(pk1, 32, sk1, 32, seed, 16) == SXT_ERR_BADARG,
          "box wrong seed length -> BADARG");
    CHECK(sxt_kx_keypair_from_seed(kpk, 32, ksk, 32, seed, 31) == SXT_ERR_BADARG,
          "kx wrong seed length -> BADARG");
}

static void test_onion_primitives(void)
{
    unsigned char seed[32];
    unsigned char expanded[64];
    unsigned char expanded2[64];
    char hex[2 * 64 + 1];
    unsigned char mac[32];

    printf("onion-support primitives (ed25519 expanded key + HMAC-SHA256, ABI 6):\n");

    /* ed25519 seed -> expanded secret key: SHA-512(seed) with the ed25519 low-half
     * scalar clamp. KAT computed independently (Python hashlib) for seed 0x42 x 32,
     * so it cross-checks the shim's crypto_hash_sha512 + clamp against a separate
     * SHA-512. This is the (a || RH) form ADD_ONION ED25519-V3 consumes. */
    memset(seed, 0x42, sizeof seed);
    CHECK(sxt_sign_expandedkeybytes() == 64, "expanded key width is 64");
    CHECK(sxt_sign_seed_to_expanded_key(expanded, 64, seed, 32) == 64,
          "seed -> expanded key writes 64 bytes");
    sxt_bin2hex(hex, (int)sizeof hex, expanded, 64);
    CHECK(strcmp(hex,
            "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6e"
            "eda66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90") == 0,
          "expanded key (seed 0x42x32) matches the independent KAT");
    CHECK((expanded[0] & 7) == 0 && (expanded[31] & 192) == 64,
          "expanded key carries the ed25519 scalar clamp");
    CHECK(sxt_sign_seed_to_expanded_key(expanded2, 64, seed, 32) == 64 &&
          memcmp(expanded, expanded2, 64) == 0, "expanded key is deterministic");

    /* firewall: wrong seed length -> BADARG; short buffer -> -needed (64). */
    CHECK(sxt_sign_seed_to_expanded_key(expanded, 64, seed, 31) == SXT_ERR_BADARG,
          "expanded key wrong seed length -> BADARG");
    CHECK(sxt_sign_seed_to_expanded_key(expanded, 10, seed, 32) == -64,
          "expanded key short buffer -> -needed (64)");

    /* HMAC-SHA256 over an arbitrary-length key: RFC 4231 Test Case 2 (an
     * authoritative, independent vector; note the key "Jefe" is not 32 bytes,
     * which is exactly why the multipart init form is used). */
    CHECK(sxt_hmac_sha256_bytes() == 32, "HMAC-SHA256 output width is 32");
    CHECK(sxt_hmac_sha256(mac, 32, (const unsigned char *)"Jefe", 4,
                          (const unsigned char *)"what do ya want for nothing?", 28) == 32,
          "HMAC-SHA256 writes 32 bytes");
    sxt_bin2hex(hex, (int)sizeof hex, mac, 32);
    CHECK(strcmp(hex,
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843") == 0,
          "HMAC-SHA256 matches RFC 4231 Test Case 2");
    /* an empty key and message are legal (no crash); a short buffer -> -needed. */
    CHECK(sxt_hmac_sha256(mac, 32, (const unsigned char *)"", 0,
                          (const unsigned char *)"", 0) == 32,
          "HMAC-SHA256 with an empty key and message is fine");
    CHECK(sxt_hmac_sha256(mac, 8, (const unsigned char *)"k", 1,
                          (const unsigned char *)"m", 1) == -32,
          "HMAC-SHA256 short buffer -> -needed (32)");
}

static void test_pad(void)
{
    unsigned char buf[32];
    const unsigned char msg[5] = {'h', 'e', 'l', 'l', 'o'};
    int padded;

    printf("pad / unpad (length hiding):\n");

    padded = sxt_pad(buf, (int)sizeof(buf), msg, 5, 16);
    CHECK(padded == 16, "pad(5, blocksize 16) -> 16 bytes");
    CHECK(memcmp(buf, msg, 5) == 0, "padded buffer starts with the original data");
    CHECK(sxt_unpad(buf, padded, 16) == 5, "unpad recovers the original length");

    /* malformed padding -> ENCODING; a too-small buffer -> -needed. The padding
     * is a 0x80 marker (here at buf[5]) followed by zeros; erase it so there is
     * no valid marker in the final block. */
    memset(&buf[5], 0, 11);
    CHECK(sxt_unpad(buf, 16, 16) == SXT_ERR_ENCODING, "malformed padding -> SXT_ERR_ENCODING");
    CHECK(sxt_pad(buf, 4, msg, 5, 16) == -16, "too-small pad buffer -> -needed (16)");
}

/* ========================================================================== *
 * Phase 6: streaming / whole-file hashing + unbiased random.
 * ========================================================================== */

static int digest_is(const unsigned char *dig, int outlen, const char *expected_hex)
{
    char hex[2 * 64 + 1];
    if (outlen < 0 || outlen > 64) {
        return 0;
    }
    if (sxt_bin2hex(hex, (int)sizeof(hex), dig, outlen) != outlen * 2) {
        return 0;
    }
    return strcmp(hex, expected_hex) == 0;
}

static void test_phase6(void)
{
    /* The same published BLAKE2b-256("abc") vector used in test_hashing, so the
     * multipart and file paths are pinned to a known answer, not just to each
     * other. */
    static const char *KAT_ABC_256 =
        "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319";
    static unsigned char bigbuf[40000];
    const char *fpath = "sxt_hashfile.tmp";
    unsigned char dig[64];
    unsigned char dig2[64];
    unsigned char key[32];
    int h, i, r, in_range;
    FILE *f;

    printf("phase 6 (uniform random, multipart hash, file hash):\n");
    memset(key, 0x42, sizeof(key));

    /* --- randombytes_uniform: stays in range, and the firewall --- */
    in_range = 1;
    for (i = 0; i < 4096; i++) {
        r = sxt_randombytes_uniform(10);
        if (r < 0 || r >= 10) { in_range = 0; break; }
    }
    CHECK(in_range, "randombytes_uniform(10) stays in [0,10) over 4096 draws");
    CHECK(sxt_randombytes_uniform(1) == 0, "uniform(1) is always 0");
    CHECK(sxt_randombytes_uniform(0) == SXT_ERR_BADARG, "uniform(0) -> BADARG");
    CHECK(sxt_randombytes_uniform(-5) == SXT_ERR_BADARG, "uniform(negative) -> BADARG");
    CHECK(sxt_randombytes_uniform(SXT_MAX_BUFFER + 1) == SXT_ERR_BADARG,
          "uniform(> SXT_MAX_BUFFER) -> BADARG");

    /* --- multipart hash: "a"+"b"+"c" == BLAKE2b-256("abc") --- */
    h = sxt_hash_init(NULL, 0, 32);
    CHECK(h > 0, "hash_init returns a positive handle");
    CHECK(sxt_hash_update(h, (const unsigned char *)"a", 1) == SXT_OK, "update 'a'");
    CHECK(sxt_hash_update(h, (const unsigned char *)"b", 1) == SXT_OK, "update 'b'");
    CHECK(sxt_hash_update(h, (const unsigned char *)"c", 1) == SXT_OK, "update 'c'");
    CHECK(sxt_hash_final(h, dig, 8) == -32, "short final buffer -> -needed (32), state intact");
    CHECK(sxt_hash_final(h, dig, 32) == 32, "final writes 32 bytes");
    CHECK(digest_is(dig, 32, KAT_ABC_256), "multipart BLAKE2b-256(abc) matches the vector");
    CHECK(sxt_hash_update(h, (const unsigned char *)"x", 1) == SXT_ERR_BADHANDLE,
          "update after final -> BADHANDLE (handle released)");
    CHECK(sxt_hash_final(h, dig, 32) == SXT_ERR_BADHANDLE, "final after final -> BADHANDLE");

    /* abort path: init then free, no final; idempotent free must not crash. */
    h = sxt_hash_init(NULL, 0, 32);
    CHECK(h > 0, "hash_init (abort path) handle");
    sxt_hash_free(h);
    CHECK(sxt_hash_update(h, (const unsigned char *)"x", 1) == SXT_ERR_BADHANDLE,
          "update after free -> BADHANDLE");
    sxt_hash_free(h);
    CHECK(1, "double free is a harmless no-op");

    /* bogus handles, including a stream-style handle that lacks the hash tag. */
    CHECK(sxt_hash_update(0, (const unsigned char *)"x", 1) == SXT_ERR_BADHANDLE,
          "update on handle 0 -> BADHANDLE");
    CHECK(sxt_hash_final(65537, dig2, 32) == SXT_ERR_BADHANDLE,
          "final on an untagged (stream-style) handle -> BADHANDLE");

    /* keyed multipart differs from the unkeyed digest still in dig. */
    h = sxt_hash_init(key, 32, 32);
    CHECK(h > 0, "keyed hash_init");
    sxt_hash_update(h, (const unsigned char *)"abc", 3);
    CHECK(sxt_hash_final(h, dig2, 32) == 32, "keyed final writes 32 bytes");
    CHECK(memcmp(dig, dig2, 32) != 0, "keyed multipart differs from unkeyed");

    /* --- file hash: a file of "abc" == BLAKE2b-256("abc") --- */
    f = fopen(fpath, "wb");
    CHECK(f != NULL, "open temp file for write");
    if (f != NULL) {
        fwrite("abc", 1, 3, f);
        fclose(f);
    }
    CHECK(sxt_hash_file(fpath, dig, 64, 32, NULL, 0) == 32, "hash_file returns 32");
    CHECK(digest_is(dig, 32, KAT_ABC_256), "hash_file BLAKE2b-256(abc) matches the vector");
    CHECK(sxt_hash_file(fpath, dig2, 64, 32, key, 32) == 32, "keyed hash_file returns 32");
    CHECK(memcmp(dig, dig2, 32) != 0, "keyed file hash differs from unkeyed");
    CHECK(sxt_hash_file(fpath, dig, 8, 32, NULL, 0) == -32, "short hash_file buffer -> -needed (32)");
    CHECK(sxt_hash_file("sxt_no_such_file.tmp", dig, 64, 32, NULL, 0) == SXT_ERR_IO,
          "missing file -> SXT_ERR_IO");
    remove(fpath);

    /* A multi-chunk file (> SXT_FILE_CHUNK) must hash identically to a one-shot
     * hash of the same bytes: proves the chunked read loop is correct. */
    CHECK(write_pattern_file(fpath, 40000), "wrote a 40000-byte file (multi-chunk)");
    f = fopen(fpath, "rb");
    CHECK(f != NULL && fread(bigbuf, 1, sizeof(bigbuf), f) == sizeof(bigbuf),
          "read the 40000-byte pattern back");
    if (f != NULL) { fclose(f); }
    CHECK(sxt_hash_file(fpath, dig, 64, 32, NULL, 0) == 32, "hash_file (40000 bytes) returns 32");
    CHECK(sxt_generichash(dig2, 64, 32, bigbuf, 40000, NULL, 0) == 32, "one-shot hash of same bytes");
    CHECK(memcmp(dig, dig2, 32) == 0, "file hash equals the one-shot hash of the same bytes");
    remove(fpath);
}

/* --- ABI 7: SHA3-256 ------------------------------------------------------ */

static int sha3_hex_equals(const char *msg, int msglen, const char *expected_hex)
{
    unsigned char dig[32];
    char hex[2 * 32 + 1];
    if (sxt_sha3_256(dig, (int)sizeof(dig),
                     (const unsigned char *)msg, msglen) != 32) {
        return 0;
    }
    if (sxt_bin2hex(hex, (int)sizeof(hex), dig, 32) != 64) {
        return 0;
    }
    return strcmp(hex, expected_hex) == 0;
}

static void test_sha3(void)
{
    unsigned char dig[32];
    unsigned char small[8];
    /* The v3 onion checksum preimage for torproject.org's PUBLISHED onion
     * (the same address onionxt's tools/onion-kat.py pins):
     * ".onion checksum" || pubkey(32) || 0x03. The address itself carries the
     * checksum's first two bytes, so this vector is self-attesting: a wrong
     * SHA-3 here could not have produced a working published address. */
    static const unsigned char onion_pub[32] = {
        0xd1, 0xb3, 0x8b, 0x83, 0xa8, 0x3b, 0x3e, 0xd9,
        0x18, 0xc5, 0xbb, 0x69, 0xdd, 0x44, 0x4a, 0xd5,
        0x6b, 0xc8, 0xd5, 0x83, 0x5a, 0x91, 0x4d, 0xe7,
        0x34, 0x47, 0x47, 0x4e, 0x5f, 0x02, 0x59, 0x1b
    };
    unsigned char preimage[15 + 32 + 1];

    printf("SHA3-256 (ABI 7: FIPS 202 KATs + the onion checksum + firewall):\n");

    CHECK(sxt_sha3_256_bytes() == 32, "sxt_sha3_256_bytes is 32");

    /* NIST FIPS 202 / CAVP known-answer vectors. These pin the DOMAIN PADDING:
     * Keccak-256 (0x01) of "abc" starts 4e03657a..., SHA3-256 (0x06) starts
     * 3a985da7... - a wrong variant cannot pass. */
    CHECK(sha3_hex_equals("", 0,
            "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"),
          "SHA3-256(\"\") matches the FIPS 202 vector");
    CHECK(sha3_hex_equals("abc", 3,
            "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"),
          "SHA3-256(\"abc\") matches the FIPS 202 vector");
    CHECK(sha3_hex_equals("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
            "41c0dba2a9d6240849100376a8235e2c82e1b9998a999e21db32dd97496d3376"),
          "SHA3-256(448-bit message) matches the FIPS 202 vector");

    /* The consumer story, end to end: SHA3-256(".onion checksum" || pub || 3)
     * must open with the two checksum bytes the published address carries
     * (0xdd 0xd9 for this one). */
    memcpy(preimage, ".onion checksum", 15);
    memcpy(preimage + 15, onion_pub, 32);
    preimage[47] = 0x03;
    CHECK(sxt_sha3_256(dig, (int)sizeof(dig), preimage, 48) == 32,
          "onion checksum preimage hashes");
    CHECK(dig[0] == 0xdd && dig[1] == 0xd9,
          "the checksum bytes match the published torproject onion");

    /* Firewall. */
    CHECK(sxt_sha3_256(dig, (int)sizeof(dig), (const unsigned char *)"x", -1)
              == SXT_ERR_BADARG,
          "negative input length -> BADARG");
    CHECK(sxt_sha3_256(small, (int)sizeof(small), (const unsigned char *)"x", 1)
              == -32,
          "too-small digest buffer -> -needed (32)");
    CHECK(sxt_sha3_256(NULL, 64, (const unsigned char *)"x", 1) == SXT_ERR_BADARG,
          "null output buffer -> BADARG");
    CHECK(sxt_sha3_256(dig, (int)sizeof(dig), NULL, 1) == SXT_ERR_BADARG,
          "null input with a positive length -> BADARG");
    CHECK(sxt_sha3_256(dig, (int)sizeof(dig), NULL, 0) == 32,
          "an empty input is legal (and NULL with length 0 is tolerated)");
}

/*
 * The handle tables are BOUNDED (64 secretstream slots, 32 multipart-hash
 * slots; see sodium_shim.c) and until this section nothing exercised either
 * boundary: the "table full" refusal, the reclaim obligation that makes a
 * bounded table safe in a long-lived engine session (every free must actually
 * return its slot), or the 14-bit generation wrap a hot slot crosses after
 * 16383 free cycles. Capacity is measured by filling to refusal rather than
 * assumed, so silently resizing a table without updating the documentation
 * fails here instead of nowhere.
 */
/* ========================================================================== *
 * ABI 8: ristretto255 (holde-em Workstream U).
 *
 * The point/scalar vectors below were generated from the PINNED libsodium
 * this shim links, then cross-checked against an INDEPENDENT pure-Python
 * ristretto255 reference (RFC 9496 formulas: field arithmetic, sqrt-ratio,
 * the Elligator map, extended Edwards group law, canonical encode/decode -
 * committed as the reference inside holde-em/tools/protocol-kat.py, the
 * consumer's cross-check gate). Python and libsodium agree on every value
 * here, so a transcription slip in one of these literals cannot pass.
 * ========================================================================== */

static void test_ristretto(void)
{
    /* The RFC 9496 generator encoding - also independently re-derived by the
     * Python reference from y = 4/5. */
    static const unsigned char gen[32] = {
        0xe2, 0xf2, 0xae, 0x0a, 0x6a, 0xbc, 0x4e, 0x71,
        0xa8, 0x84, 0xa9, 0x61, 0xc5, 0x00, 0x51, 0x5f,
        0x58, 0xe3, 0x0b, 0x6a, 0xa5, 0x82, 0xdd, 0x8d,
        0xb6, 0xa6, 0x59, 0x45, 0xe0, 0x8d, 0x2d, 0x76
    };
    static const char *LBL0 = "HOLDEM-RISTRETTO-KAT-v1|card-00";
    static const char *LBL1 = "HOLDEM-RISTRETTO-KAT-v1|card-01";
    static const char *LBL51 = "HOLDEM-RISTRETTO-KAT-v1|card-51";
    unsigned char h[64], p0[32], p1[32], p51[32];
    unsigned char k7[32], kinv[32], kp[32], back[32];
    unsigned char r1[32], r2[32], ff[32], junk[32], small[8];

    printf("ristretto255 (ABI 8: cross-checked KATs + firewall):\n");

    CHECK(sxt_ristretto_bytes() == 32, "sxt_ristretto_bytes is 32");
    CHECK(sxt_ristretto_hashbytes() == 64, "sxt_ristretto_hashbytes is 64");
    CHECK(sxt_ristretto_scalarbytes() == 32, "sxt_ristretto_scalarbytes is 32");

    CHECK(sxt_ristretto_is_valid_point(gen, 32) == 1,
          "the RFC 9496 generator encoding is a valid point");

    /* Hash-to-group, the whole consumer pipeline in one leg: BLAKE2b-512 of a
     * domain-separated card label (sxHash(data, 64) script-side) into
     * from_hash. Both stages pinned. */
    CHECK(sxt_generichash(h, (int)sizeof(h), 64,
                          (const unsigned char *)LBL0, (int)strlen(LBL0),
                          NULL, 0) == 64, "BLAKE2b-512(card-00 label)");
    CHECK(sxt_ristretto_from_hash(p0, (int)sizeof(p0), h, 64) == 32,
          "from_hash(card-00) maps");
    CHECK(digest_is(p0, 32,
            "d4976d032129eb3cc15bb2e700e0f303c46bdb8a4874d009dc03405c3fdedd4d"),
          "from_hash(card-00) matches the cross-checked vector");
    CHECK(sxt_generichash(h, (int)sizeof(h), 64,
                          (const unsigned char *)LBL1, (int)strlen(LBL1),
                          NULL, 0) == 64, "BLAKE2b-512(card-01 label)");
    CHECK(sxt_ristretto_from_hash(p1, (int)sizeof(p1), h, 64) == 32,
          "from_hash(card-01) maps");
    CHECK(digest_is(p1, 32,
            "48a187d5d40ac12e4b95efe4d1c50e099efd7d5b1c3f9d881c32a51a6df6e70d"),
          "from_hash(card-01) matches the cross-checked vector");
    CHECK(sxt_generichash(h, (int)sizeof(h), 64,
                          (const unsigned char *)LBL51, (int)strlen(LBL51),
                          NULL, 0) == 64, "BLAKE2b-512(card-51 label)");
    CHECK(sxt_ristretto_from_hash(p51, (int)sizeof(p51), h, 64) == 32,
          "from_hash(card-51) maps");
    CHECK(digest_is(p51, 32,
            "ac60cf25f6b43db094e469884067af3ab35d8aab89d67d573ed1dc7d6da9a304"),
          "from_hash(card-51) matches the cross-checked vector");
    CHECK(sxt_ristretto_is_valid_point(p0, 32) == 1 &&
          sxt_ristretto_is_valid_point(p1, 32) == 1 &&
          sxt_ristretto_is_valid_point(p51, 32) == 1,
          "every from_hash output is a valid encoding");

    /* Mask/unmask, the deal's core algebra: k*P, k^-1, and the roundtrip
     * k^-1*(k*P) == P. The fixed scalar is 7 (LE). */
    memset(k7, 0, sizeof(k7));
    k7[0] = 7;
    CHECK(sxt_ristretto_scalarmult(kp, (int)sizeof(kp), k7, 32, p0, 32) == 32,
          "7 * from_hash(card-00) multiplies");
    CHECK(digest_is(kp, 32,
            "e4efdd42fce9e2cc212ccf6aa307b6bba55ba8f9d2b33103721be7fead96964c"),
          "7 * P matches the cross-checked vector");
    CHECK(sxt_ristretto_scalar_invert(kinv, (int)sizeof(kinv), k7, 32) == 32,
          "invert(7) inverts");
    CHECK(digest_is(kinv, 32,
            "22d5909fba32273143cdfe848dda1f4c92244992244992244992244992244902"),
          "invert(7) matches 7^-1 mod L (independently: pow(7, L-2, L))");
    CHECK(sxt_ristretto_scalarmult(back, (int)sizeof(back), kinv, 32, kp, 32) == 32,
          "7^-1 * (7*P) multiplies");
    CHECK(memcmp(back, p0, 32) == 0,
          "the mask/unmask roundtrip returns exactly P");

    /* Random scalars: right length, and two draws differ (a stuck CSPRNG or a
     * wrong buffer size would collide instantly). */
    CHECK(sxt_ristretto_scalar_random(r1, (int)sizeof(r1)) == 32 &&
          sxt_ristretto_scalar_random(r2, (int)sizeof(r2)) == 32,
          "scalar_random fills 32 bytes");
    CHECK(memcmp(r1, r2, 32) != 0, "two random scalars differ");
    CHECK(sxt_ristretto_scalarmult(kp, (int)sizeof(kp), r1, 32, gen, 32) == 32,
          "a random scalar multiplies the generator");

    /* Firewall + the failure semantics the header promises. */
    memset(ff, 0xff, sizeof(ff));
    CHECK(sxt_ristretto_is_valid_point(ff, 32) == 0,
          "all-FF is not a valid encoding");
    CHECK(sxt_ristretto_is_valid_point(gen, 31) == 0,
          "a wrong-length blob is invalid, not an error (predicate semantics)");
    CHECK(sxt_ristretto_is_valid_point(NULL, 32) == SXT_ERR_BADARG,
          "a null point with a positive length stays a hard BADARG");
    memset(junk, 0, sizeof(junk));
    CHECK(sxt_ristretto_scalarmult(kp, (int)sizeof(kp), junk, 32, p0, 32)
              == SXT_ERR_BADARG,
          "a zero scalar fails scalarmult (identity result)");
    CHECK(last_error_len() > 0, "the scalarmult failure sets a message");
    CHECK(sxt_ristretto_scalarmult(kp, (int)sizeof(kp), k7, 32, ff, 32)
              == SXT_ERR_BADARG,
          "an invalid point encoding fails scalarmult");
    CHECK(sxt_ristretto_scalar_invert(kinv, (int)sizeof(kinv), junk, 32)
              == SXT_ERR_BADARG,
          "a zero scalar has no inverse");
    CHECK(sxt_ristretto_from_hash(p0, (int)sizeof(p0), h, 63) == SXT_ERR_BADARG,
          "from_hash refuses a 63-byte input");
    CHECK(sxt_ristretto_from_hash(small, (int)sizeof(small), h, 64) == -32,
          "a short from_hash buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalarmult(small, (int)sizeof(small), k7, 32, p0, 32)
              == -32, "a short scalarmult buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalar_random(small, (int)sizeof(small)) == -32,
          "a short scalar_random buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalarmult(kp, (int)sizeof(kp), k7, 31, p0, 32)
              == SXT_ERR_BADARG, "a 31-byte scalar is refused");
    CHECK(sxt_ristretto_from_hash(NULL, 64, h, 64) == SXT_ERR_BADARG,
          "a null from_hash output buffer is refused");
}

static void test_ristretto_abi9(void)
{
    /* The ABI 9 follow-ons (holde-em Phase 5: DLEQ algebra + the one-crossing
     * batch). Vectors generated from the pinned libsodium and re-derived by
     * the independent RFC 9496 reference in holde-em/tools/protocol-kat.py
     * before being pinned here (both agreed on every value) - and the
     * base-mult of 7 additionally matches RFC 9496's own small-multiples
     * table entry B[7], a third independent witness. */
    static const char *LBLS[3] = {
        "HOLDEM-RISTRETTO-KAT-v1|card-00",
        "HOLDEM-RISTRETTO-KAT-v1|card-01",
        "HOLDEM-RISTRETTO-KAT-v1|card-51"
    };
    static const unsigned char gen[32] = {
        0xe2, 0xf2, 0xae, 0x0a, 0x6a, 0xbc, 0x4e, 0x71,
        0xa8, 0x84, 0xa9, 0x61, 0xc5, 0x00, 0x51, 0x5f,
        0x58, 0xe3, 0x0b, 0x6a, 0xa5, 0x82, 0xdd, 0x8d,
        0xb6, 0xa6, 0x59, 0x45, 0xe0, 0x8d, 0x2d, 0x76
    };
    unsigned char h[64], pts[3][32], concat[96];
    unsigned char k7[32], lm2[32], sum[32], back[32], q[32], q2[32];
    unsigned char batch[96], loop[32], small[8];
    char err[256];
    int i;

    printf("ristretto255 ABI 9 (DLEQ/batch follow-ons: cross-checked KATs + firewall):\n");

    /* Rebuild the three card points (pinned in test_ristretto above). */
    for (i = 0; i < 3; i++) {
        CHECK(sxt_generichash(h, (int)sizeof(h), 64,
                              (const unsigned char *)LBLS[i],
                              (int)strlen(LBLS[i]), NULL, 0) == 64 &&
              sxt_ristretto_from_hash(pts[i], 32, h, 64) == 32,
              "card point rebuilds");
        memcpy(concat + i * 32, pts[i], 32);
    }
    memset(k7, 0, sizeof(k7));
    k7[0] = 7;

    /* base-mult: the pinned vector, AND the structural identity against the
     * general scalarmult of the RFC 9496 generator encoding - a base-mult
     * that used a different base could still produce valid-looking points,
     * so both legs matter. */
    CHECK(sxt_ristretto_scalarmult_base(q, (int)sizeof(q), k7, 32) == 32,
          "scalarmult_base(7) multiplies");
    CHECK(digest_is(q, 32,
            "44f53520926ec81fbd5a387845beb7df85a96a24ece18738bdcfa6a7822a176d"),
          "7*B matches the cross-checked vector (== RFC 9496 B[7])");
    CHECK(sxt_ristretto_scalarmult(q2, (int)sizeof(q2), k7, 32, gen, 32) == 32 &&
          memcmp(q, q2, 32) == 0,
          "scalarmult_base agrees with scalarmult(generator)");

    /* add/sub: the pinned sum, the roundtrip P+Q-Q == P, and P-P == the
     * identity encoding (32 zero bytes) - legal here, unlike scalarmult. */
    CHECK(sxt_ristretto_add(sum, (int)sizeof(sum), pts[0], 32, pts[1], 32) == 32,
          "card00 + card01 adds");
    CHECK(digest_is(sum, 32,
            "34722b333ab7982fe4d5e2be2913c316db8f8675de2394a5cfb704abab7c8b4c"),
          "card00 + card01 matches the cross-checked vector");
    CHECK(sxt_ristretto_sub(back, (int)sizeof(back), sum, 32, pts[1], 32) == 32 &&
          memcmp(back, pts[0], 32) == 0,
          "the add/sub roundtrip (P+Q)-Q returns exactly P");
    CHECK(sxt_ristretto_sub(q, (int)sizeof(q), pts[0], 32, pts[0], 32) == 32 &&
          all_equal(q, 32, 0x00),
          "P - P is the identity encoding (32 zero bytes)");

    /* the batch call: one crossing over the three concatenated card points,
     * element-for-element equal to the loop of single scalarmults (and the
     * first element re-pins the ABI 8 k7*card00 vector by construction). */
    fill_sentinel(batch, (int)sizeof(batch));
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         k7, 32, concat, 96) == 96,
          "batch over 3 concatenated points fills 96 bytes");
    for (i = 0; i < 3; i++) {
        CHECK(sxt_ristretto_scalarmult(loop, (int)sizeof(loop),
                                       k7, 32, pts[i], 32) == 32 &&
              memcmp(batch + i * 32, loop, 32) == 0,
              "batch element equals the single-call scalarmult");
    }
    CHECK(digest_is(batch, 32,
            "e4efdd42fce9e2cc212ccf6aa307b6bba55ba8f9d2b33103721be7fead96964c"),
          "batch[0] matches the cross-checked 7*card00 vector");
    CHECK(digest_is(batch + 32, 32,
            "c4aea78979e6929435b9bfcc4dee30d0dc714c714ae28f5e3c44cc124625a345"),
          "batch[1] matches the cross-checked 7*card01 vector");
    CHECK(digest_is(batch + 64, 32,
            "58907d49b012f75999ae4231e156cdec4432851939532b1e1278f900fbfaaa2d"),
          "batch[2] matches the cross-checked 7*card51 vector");

    /* the DLEQ-shaped identity the whole surface exists for:
     * k*(P+Q) == k*P + k*Q. */
    CHECK(sxt_ristretto_scalarmult(q, (int)sizeof(q), k7, 32, sum, 32) == 32,
          "7 * (card00 + card01) multiplies");
    CHECK(sxt_ristretto_add(q2, (int)sizeof(q2),
                            batch, 32, batch + 32, 32) == 32 &&
          memcmp(q, q2, 32) == 0,
          "k*(P+Q) == k*P + k*Q (the DLEQ-shaped identity)");

    /* scalar arithmetic mod L, cross-checked: 7 + (L-2) wraps to 5, and
     * 7 * 7^-1 is 1 (reusing the ABI 8 pinned inverse). */
    memcpy(lm2, (const unsigned char *)"\xed\xd3\xf5\x5c\x1a\x63\x12\x58"
                                       "\xd6\x9c\xf7\xa2\xde\xf9\xde\x14"
                                       "\x00\x00\x00\x00\x00\x00\x00\x00"
                                       "\x00\x00\x00\x00\x00\x00\x00\x10", 32);
    lm2[0] = (unsigned char)(lm2[0] - 2);   /* L - 2, little-endian */
    CHECK(sxt_ristretto_scalar_add(q, (int)sizeof(q), k7, 32, lm2, 32) == 32,
          "scalar_add(7, L-2) adds");
    CHECK(q[0] == 5 && all_equal(q + 1, 31, 0x00),
          "7 + (L-2) wraps to 5 mod L (reduce semantics)");
    CHECK(sxt_ristretto_scalar_invert(q2, (int)sizeof(q2), k7, 32) == 32 &&
          sxt_ristretto_scalar_mul(q, (int)sizeof(q), k7, 32, q2, 32) == 32,
          "scalar_mul(7, invert(7)) multiplies");
    CHECK(q[0] == 1 && all_equal(q + 1, 31, 0x00),
          "7 * 7^-1 is 1 mod L");

    /* firewall + the failure semantics the header promises */
    memset(q2, 0xff, sizeof(q2));
    CHECK(sxt_ristretto_add(q, (int)sizeof(q), pts[0], 32, q2, 32)
              == SXT_ERR_BADARG,
          "add refuses an invalid operand encoding");
    CHECK(sxt_ristretto_sub(q, (int)sizeof(q), q2, 32, pts[0], 32)
              == SXT_ERR_BADARG,
          "sub refuses an invalid operand encoding");
    CHECK(sxt_ristretto_add(q, (int)sizeof(q), pts[0], 31, pts[1], 32)
              == SXT_ERR_BADARG, "a 31-byte add operand is refused");
    memset(q2, 0, sizeof(q2));
    CHECK(sxt_ristretto_scalarmult_base(q, (int)sizeof(q), q2, 32)
              == SXT_ERR_BADARG,
          "scalarmult_base refuses a zero scalar (identity result)");
    CHECK(last_error_len() > 0, "the base-mult failure sets a message");
    /* index-carrying batch failure: corrupt the SECOND point (all-FF is not
     * a valid encoding), expect the whole call to fail with "2 of 3" in the
     * error text (the atomic-void contract; a partial success would invite
     * using half a masked deck). */
    memset(concat + 32, 0xff, 32);
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         k7, 32, concat, 96)
              == SXT_ERR_BADARG,
          "one bad point fails the WHOLE batch call");
    CHECK(sxt_last_error(err, (int)sizeof(err)) > 0 &&
          strstr(err, "point 2 of 3") != NULL,
          "the batch failure names the 1-based failing index");
    memcpy(concat + 32, pts[1], 32);
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         q2, 32, concat, 96)
              == SXT_ERR_BADARG,
          "a zero scalar fails the batch (identity results)");
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         k7, 32, concat, 95)
              == SXT_ERR_BADARG,
          "a pointslen that is not a multiple of 32 is refused");
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         k7, 32, concat, 0)
              == SXT_ERR_BADARG, "an empty points buffer is refused");
    CHECK(sxt_ristretto_scalarmult_batch(small, (int)sizeof(small),
                                         k7, 32, concat, 96) == -96,
          "a short batch buffer -> -needed (count*32)");
    CHECK(sxt_ristretto_scalarmult_batch(batch, (int)sizeof(batch),
                                         k7, 31, concat, 96)
              == SXT_ERR_BADARG, "a 31-byte batch scalar is refused");
    CHECK(sxt_ristretto_scalarmult_batch(NULL, 96, k7, 32, concat, 96)
              == SXT_ERR_BADARG, "a null batch output buffer is refused");
    CHECK(sxt_ristretto_add(small, (int)sizeof(small), pts[0], 32, pts[1], 32)
              == -32, "a short add buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalarmult_base(small, (int)sizeof(small), k7, 32)
              == -32, "a short base-mult buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalar_add(small, (int)sizeof(small), k7, 32, lm2, 32)
              == -32, "a short scalar_add buffer -> -needed (32)");
    CHECK(sxt_ristretto_scalar_mul(q, (int)sizeof(q), k7, 32, lm2, 31)
              == SXT_ERR_BADARG, "a 31-byte scalar_mul operand is refused");
    CHECK(sxt_ristretto_scalar_add(NULL, 32, k7, 32, lm2, 32)
              == SXT_ERR_BADARG, "a null scalar_add output buffer is refused");
}

static void test_handle_table_stress(void)
{
    unsigned char key[32];
    unsigned char header[64];
    int hashes[32];
    int streams[64];
    int i, h, h2, count, refusal, ok;

    printf("handle-table stress (exhaustion, refusal, reclaim, generation wrap):\n");
    memset(key, 0x42, sizeof(key));

    /* --- hash table: fill to refusal; the boundary must be exact and clean --- */
    count = 0;
    refusal = 0;
    for (;;) {
        h = sxt_hash_init(NULL, 0, 32);
        if (h <= 0) {
            refusal = h;
            break;
        }
        if (count < (int)(sizeof(hashes) / sizeof(hashes[0]))) {
            hashes[count] = h;
        }
        count++;
        if (count > 4096) {
            break;               /* runaway guard: the table is supposed to bound us */
        }
    }
    CHECK(count == 32, "the hash table holds exactly the documented 32 states");
    CHECK(refusal == SXT_ERR_BADHANDLE, "the 33rd init is refused cleanly (BADHANDLE)");
    CHECK(last_error_len() > 0, "the hash-table refusal sets a last-error message");
    sxt_hash_free(hashes[0]);
    h = sxt_hash_init(NULL, 0, 32);
    CHECK(h > 0, "one free returns exactly one usable hash slot");
    hashes[0] = h;
    for (i = 0; i < 32; i++) {
        sxt_hash_free(hashes[i]);
    }

    /* --- reclaim + generation wrap: 40000 init/use/free rounds on an empty
     * table always land in slot 0 (first-free scan), so slot 0's generation
     * wraps (0x3FFF = 16383) partway through and the tail of the loop proves a
     * post-wrap slot still allocates AND its handle still validates. --- */
    ok = 1;
    for (i = 0; i < 40000 && ok; i++) {
        h = sxt_hash_init(NULL, 0, 32);
        if (h <= 0 || sxt_hash_update(h, key, 32) != SXT_OK) {
            ok = 0;
        }
        sxt_hash_free(h);
    }
    CHECK(ok, "40000 hash init/use/free rounds reclaim their slots (incl. past the generation wrap)");

    /* a recycled slot must invalidate the handle that used to name it */
    h = sxt_hash_init(NULL, 0, 32);
    sxt_hash_free(h);
    h2 = sxt_hash_init(NULL, 0, 32);
    CHECK(h2 != h, "a recycled hash slot issues a DIFFERENT handle");
    CHECK(sxt_hash_update(h, key, 32) == SXT_ERR_BADHANDLE,
          "the pre-recycle hash handle stays dead after the slot is reused");
    sxt_hash_free(h2);

    /* full capacity must survive all of the above: fill to 32 once more */
    ok = 1;
    for (i = 0; i < 32; i++) {
        hashes[i] = sxt_hash_init(NULL, 0, 32);
        if (hashes[i] <= 0) {
            ok = 0;
        }
    }
    CHECK(ok, "all 32 hash slots are usable again after the stress");
    for (i = 0; i < 32; i++) {
        sxt_hash_free(hashes[i]);
    }

    /* --- stream table: the same contract at its own boundary (64 slots) --- */
    count = 0;
    refusal = 0;
    for (;;) {
        h = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
        if (h <= 0) {
            refusal = h;
            break;
        }
        if (count < (int)(sizeof(streams) / sizeof(streams[0]))) {
            streams[count] = h;
        }
        count++;
        if (count > 4096) {
            break;
        }
    }
    CHECK(count == 64, "the stream table holds exactly the documented 64 states");
    CHECK(refusal == SXT_ERR_BADARG, "the 65th init_push is refused cleanly (BADARG)");
    CHECK(last_error_len() > 0, "the stream-table refusal sets a last-error message");
    sxt_free_stream(streams[0]);
    h = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
    CHECK(h > 0, "one free returns exactly one usable stream slot");
    streams[0] = h;
    for (i = 0; i < 64; i++) {
        sxt_free_stream(streams[i]);
    }

    /* reclaim + wrap, rekey as the cheap liveness probe on each handle */
    ok = 1;
    for (i = 0; i < 40000 && ok; i++) {
        h = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
        if (h <= 0 || sxt_secretstream_rekey(h) != SXT_OK) {
            ok = 0;
        }
        sxt_free_stream(h);
    }
    CHECK(ok, "40000 stream init/rekey/free rounds reclaim their slots (incl. past the generation wrap)");

    h = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
    sxt_free_stream(h);
    h2 = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
    CHECK(h2 != h, "a recycled stream slot issues a DIFFERENT handle");
    CHECK(sxt_secretstream_rekey(h) == SXT_ERR_BADHANDLE,
          "the pre-recycle stream handle stays dead after the slot is reused");
    sxt_free_stream(h2);

    ok = 1;
    for (i = 0; i < 64; i++) {
        streams[i] = sxt_secretstream_init_push(header, (int)sizeof(header), key, 32);
        if (streams[i] <= 0) {
            ok = 0;
        }
    }
    CHECK(ok, "all 64 stream slots are usable again after the stress");
    for (i = 0; i < 64; i++) {
        sxt_free_stream(streams[i]);
    }
}

int main(void)
{
    printf("SodiumXT smoke test\n");
    printf("===================\n");

    test_init_and_versions();
    test_randombytes_firewall();
    test_randombytes_fills_and_has_entropy();
    test_out_buffer_retry_round_trip();
    test_hashing();
    test_encoding();
    test_memequal();
    test_secretbox();
    test_aead();
    test_pwhash();
    test_secretstream();
    test_secretstream_rekey();
    test_file_helpers();
    test_sign();
    test_box();
    test_kdf();
    test_kx();
    test_seeded_keypairs();
    test_onion_primitives();
    test_pad();
    test_phase6();
    test_sha3();
    test_ristretto();
    test_ristretto_abi9();
    test_handle_table_stress();

    printf("-------------------\n");
    if (g_failures == 0) {
        printf("ALL CHECKS PASSED\n");
        return 0;
    }
    printf("%d CHECK(S) FAILED\n", g_failures);
    return 1;
}
