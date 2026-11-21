/*
 * xlsx_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of xlsxt: Excel .xlsx files behind a flat C ABI that the xTalk
 * Builder (LCB) foreign function interface can call. Two halves:
 *
 *   WRITING is libxlsxwriter (John McNamara, BSD-2-Clause): workbooks, sheets,
 *   cell formats, formulas, images and charts.
 *
 *   READING is this file's own: libxlsxwriter only writes. A .xlsx is a zip of
 *   XML parts, so the reader opens the zip with minizip (the copy in the
 *   pinned zlib release), parses each part with Expat, and keeps one sheet at
 *   a time in memory as a sparse grid.
 *
 * box3dxt/src/box3d_shim.c is this file's ancestor and its conventions are
 * kept:
 *
 *   - Every object (a workbook being written, a sheet, a format, a chart, a
 *     file being read) lives in a shim-side handle table and crosses as a
 *     positive 32-bit int (0 = invalid). Handles are generation-tagged: a
 *     handle stays dead after its object is gone, even once the table slot is
 *     recycled. Closing a workbook kills the handles of everything in it.
 *   - Every number crosses as `double` or `int`, every yes/no as `int`, and
 *     every text IN as a NUL-terminated UTF-8 string (the binding's
 *     ZStringUTF8), which is checked here to BE valid UTF-8 before any of it
 *     is written into a file.
 *   - Every text OUT is a pointer to a buffer this file owns, valid until the
 *     next call that returns text. The binding copies it at once (as a
 *     Pointer through its textOf(), never as ZStringNative: the engine FREES
 *     a returned C string).
 *   - Rows and columns are 1-BASED on this side, as they are in Excel and in
 *     xTalk: cell A1 is row 1, column 1. Sheets, series and list items are
 *     1-based too.
 *   - Nothing here throws or aborts. A refused call returns 0 or an empty
 *     text and xlx_last_error() says why; a workbook also counts its refused
 *     calls, so a script can write ten thousand cells and ask once.
 *
 * Safety. The reader is handed files from strangers. It trusts nothing in
 * one: every size is bounded (XLX_MAX_* below), a DOCTYPE is refused, a part
 * is inflated in pieces and never by its declared size, and a cell reference
 * outside Excel's grid is refused. tests/fuzz_test.c feeds it damaged files
 * under ASan and UBSan.
 *
 * Threads. None. Nothing here starts one, and no callback reaches script
 * (suite rule 1 costs this member nothing).
 *
 * Build: compiled with libxlsxwriter, zlib and Expat into ONE shared library
 * named "xlsxt" (xlsxt.so / xlsxt.dll / xlsxt.dylib), or for the web into a
 * static archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

/* 64-bit file offsets where the C library has them behind a switch. Android
 * before API 24 has no 64-bit ftello for 32-bit code, and asking for one
 * there removes the declarations altogether. */
#if !defined(_WIN32) && !(defined(__ANDROID__) && defined(__ANDROID_API__) && __ANDROID_API__ < 24)
    #ifndef _FILE_OFFSET_BITS
        #define _FILE_OFFSET_BITS 64
    #endif
#endif

#include <ctype.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "xlsxwriter.h"
#include "minizip/unzip.h"
#include "expat.h"

#if defined(_WIN32)
    #ifndef WIN32_LEAN_AND_MEAN
        #define WIN32_LEAN_AND_MEAN
    #endif
    #include <windows.h>
#endif

#ifndef LC_API
    #if defined(_WIN32)
        #define LC_API __declspec(dllexport)
    #else
        #define LC_API __attribute__((visibility("default")))
    #endif
#endif

/* Bump when the exported ABI changes; src/xlsxt.lcb's checkABI() names the
 * same number and refuses a library that answers another. */
#define XLX_ABI_VERSION 1

/* ------------------------------------------------------------------ */
/* Limits. Excel's own where it has one, otherwise a bound chosen so   */
/* that no file, however it was made, can ask this process for more    */
/* memory than a person would expect a spreadsheet to need.            */
/* ------------------------------------------------------------------ */
#define XLX_MAX_ROW        1048576          /* Excel's grid                */
#define XLX_MAX_COL        16384
#define XLX_MAX_CELL_TEXT  32767            /* characters in one cell      */
#define XLX_MAX_PATH       4096             /* bytes of a file path        */
#define XLX_MAX_NAME       255              /* names, titles, formats      */
#define XLX_MAX_FORMULA    8192             /* Excel's formula limit       */
#define XLX_MAX_GRID_TEXT  (64u << 20)      /* one xlx_sheet_write_grid    */
#define XLX_MAX_SHEETS     4096             /* sheets read from one file   */
#define XLX_MAX_PART_BYTES ((uint64_t)1 << 30)  /* one XML part, inflated  */
#define XLX_MAX_CELLS      10000000u        /* cells of one loaded sheet   */
#define XLX_MAX_POOL       ((size_t)1 << 30)    /* text of one sheet, of   */
                                                /* the shared strings      */
#define XLX_MAX_VALUE_TEXT ((size_t)16 << 20)   /* one cell's text, read   */
#define XLX_MAX_STRINGS    50000000u        /* shared strings              */
#define XLX_MAX_STYLES     1000000u         /* cell formats of a file      */
#define XLX_MAX_TEXT_OUT   ((size_t)512 << 20)  /* one text result         */

/* ------------------------------------------------------------------ */
/* Generic handle tables (box3dxt's, with one change).                 */
/* Handles are positive ints; 0 == null/invalid. Each packs, from the  */
/* top: 3 bits that say WHAT it is a handle of, an 8-bit generation,   */
/* and a 20-bit slot number (slot + 1). The generation keeps a stale   */
/* handle DEAD after its slot is recycled; a slot whose generation     */
/* would wrap is retired, never reused.                                */
/*                                                                     */
/* The kind bits are the change. In box3dxt a world and a body may     */
/* both be handle 1, which costs nothing there: no call takes one      */
/* where the other belongs. Here a write takes a sheet AND a format,   */
/* and the first sheet and the first format of a workbook would be the */
/* same number: a script that passed its sheet as the format would get */
/* a cell silently styled by whatever format sat in that slot (this    */
/* member's first smoke run did exactly that). With the kind in the    */
/* handle, a handle of one kind is never a valid handle of another.    */
/* ------------------------------------------------------------------ */
#define XLX_H_SLOT_BITS 20
#define XLX_H_SLOT_MASK 0xFFFFF            /* low 20 bits: slot + 1     */
#define XLX_H_GEN_MASK  0xFF               /* 8 bits of generation      */
#define XLX_H_KIND_SHIFT 28                /* 3 bits of kind, 1 to 5    */
#define XLX_H_MAX_SLOTS (XLX_H_SLOT_MASK - 1)

#define DEFINE_TABLE(NAME, TYPE, KIND)                                        \
    static TYPE *NAME##_arr = NULL;                                           \
    static unsigned char  *NAME##_used = NULL;                                \
    static unsigned short *NAME##_gen = NULL;                                 \
    static int   NAME##_cap = 0;                                              \
    static int   NAME##_cnt = 0;                                              \
    static int   NAME##_live = 0;                                             \
    static int  *NAME##_free = NULL;                                          \
    static int   NAME##_freeCap = 0;                                          \
    static int   NAME##_freeCnt = 0;                                          \
    static int NAME##_grow_slots(int nc) {                                    \
        TYPE *na = (TYPE *)realloc(NAME##_arr, (size_t)nc * sizeof(TYPE));    \
        if (!na) return 0;                                                    \
        NAME##_arr = na;                                                      \
        unsigned char *nu = (unsigned char *)realloc(NAME##_used,             \
                                                     (size_t)nc);             \
        if (!nu) return 0;                                                    \
        NAME##_used = nu;                                                     \
        unsigned short *ng = (unsigned short *)realloc(NAME##_gen,            \
                                            (size_t)nc * sizeof(short));      \
        if (!ng) return 0;                                                    \
        NAME##_gen = ng;                                                      \
        memset(NAME##_used + NAME##_cap, 0, (size_t)(nc - NAME##_cap));       \
        memset(NAME##_gen + NAME##_cap, 0,                                    \
               (size_t)(nc - NAME##_cap) * sizeof(short));                    \
        NAME##_cap = nc;                                                      \
        return 1;                                                             \
    }                                                                         \
    static int NAME##_encode(int idx) {                                       \
        return (int)(((unsigned)(KIND) << XLX_H_KIND_SHIFT)                   \
                     | ((unsigned)NAME##_gen[idx] << XLX_H_SLOT_BITS)         \
                     | (unsigned)(idx + 1));                                  \
    }                                                                         \
    /* handle -> slot index, or -1 if stale / never created */               \
    static int NAME##_slot_of(int h) {                                        \
        if (h <= 0) return -1;                                                \
        int idx = (h & XLX_H_SLOT_MASK) - 1;                                   \
        unsigned gen = ((unsigned)h >> XLX_H_SLOT_BITS) & XLX_H_GEN_MASK;       \
        if (((unsigned)h >> XLX_H_KIND_SHIFT) != (unsigned)(KIND)) return -1; \
        if (idx < 0 || idx >= NAME##_cnt) return -1;                          \
        if (!NAME##_used[idx] || NAME##_gen[idx] != gen) return -1;           \
        return idx;                                                           \
    }                                                                         \
    static int NAME##_add(TYPE v) {                                           \
        int idx;                                                              \
        if (NAME##_freeCnt > 0) {                                             \
            do {                                                              \
                idx = NAME##_free[--NAME##_freeCnt];                          \
            } while (NAME##_freeCnt > 0 && NAME##_used[idx]);                 \
            if (NAME##_used[idx]) idx = -1;                                   \
        } else {                                                              \
            idx = -1;                                                         \
        }                                                                     \
        if (idx < 0) {                                                        \
            if (NAME##_cnt >= XLX_H_MAX_SLOTS) return 0;                       \
            if (NAME##_cnt >= NAME##_cap) {                                   \
                int nc = NAME##_cap ? NAME##_cap * 2 : 64;                    \
                if (!NAME##_grow_slots(nc)) return 0;                         \
            }                                                                 \
            idx = NAME##_cnt++;                                               \
        }                                                                     \
        NAME##_arr[idx] = v;                                                  \
        NAME##_used[idx] = 1;                                                 \
        NAME##_live++;                                                        \
        return NAME##_encode(idx);                                            \
    }                                                                         \
    static int NAME##_free_slot(int idx) {                                    \
        if (idx < 0 || idx >= NAME##_cnt || !NAME##_used[idx]) return 0;      \
        if (NAME##_freeCnt >= NAME##_freeCap) {                               \
            int nc = NAME##_freeCap ? NAME##_freeCap * 2 : 64;                \
            int *nf = (int *)realloc(NAME##_free, (size_t)nc * sizeof(int));  \
            if (!nf) return 0;                                                \
            NAME##_free = nf; NAME##_freeCap = nc;                            \
        }                                                                     \
        { TYPE z; memset(&z, 0, sizeof z); NAME##_arr[idx] = z; }             \
        NAME##_used[idx] = 0;                                                 \
        NAME##_live--;                                                        \
        if (NAME##_gen[idx] >= XLX_H_GEN_MASK) return 1; /* retired */       \
        NAME##_gen[idx] = (unsigned short)(NAME##_gen[idx] + 1);              \
        NAME##_free[NAME##_freeCnt++] = idx;                                  \
        return 1;                                                             \
    }

/* ------------------------------------------------------------------ */
/* The last refusal, for xlx_last_error(): "" after a call that was    */
/* not refused. Every export begins by clearing it.                    */
/* ------------------------------------------------------------------ */
static char s_error[320] = "";

static void ok_clear(void) { s_error[0] = '\0'; }

#if defined(__GNUC__)
static int fail(const char *format, ...) __attribute__((format(printf, 1, 2)));
#endif
static int fail(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vsnprintf(s_error, sizeof s_error, format, ap);
    va_end(ap);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Text out: one growing buffer, returned by pointer. "" for nothing.  */
/* ------------------------------------------------------------------ */
static char  *s_text = NULL;
static size_t s_text_cap = 0;
static size_t s_text_len = 0;

static int text_reserve(size_t extra)
{
    if (extra > XLX_MAX_TEXT_OUT || s_text_len > XLX_MAX_TEXT_OUT - extra) return 0;
    size_t need = s_text_len + extra + 1;
    if (need <= s_text_cap) return 1;
    size_t cap = s_text_cap ? s_text_cap : 256;
    while (cap < need) cap *= 2;
    char *grown = (char *)realloc(s_text, cap);
    if (!grown) return 0;
    s_text = grown;
    s_text_cap = cap;
    return 1;
}

static void text_begin(void)
{
    s_text_len = 0;
    if (s_text) s_text[0] = '\0';
}

static int text_add(const char *bytes, size_t n)
{
    if (!text_reserve(n)) return 0;
    memcpy(s_text + s_text_len, bytes, n);
    s_text_len += n;
    s_text[s_text_len] = '\0';
    return 1;
}

static int text_addc(char c) { return text_add(&c, 1); }

static const char *text_done(void) { return s_text ? s_text : ""; }

static const char *text_of(const char *s)
{
    text_begin();
    if (!s || !text_add(s, strlen(s))) return "";
    return text_done();
}

/* A buffer released by the reader's teardown and the last workbook does not
 * matter: one buffer, the size of the largest text ever returned, for the
 * life of the process. */

/* ------------------------------------------------------------------ */
/* Text in                                                             */
/* ------------------------------------------------------------------ */
/* Valid UTF-8 as RFC 3629 has it: no overlong form, no surrogate, nothing
 * above U+10FFFF. What is refused here would otherwise be written into an
 * XML part, and a part that is not UTF-8 is a file Excel calls corrupt. */
static int utf8_ok(const char *text, size_t n)
{
    const unsigned char *s = (const unsigned char *)text;
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        if (c < 0x80) { i++; continue; }
        if (c >= 0xC2 && c <= 0xDF) {
            if (i + 1 >= n || (s[i + 1] & 0xC0) != 0x80) return 0;
            i += 2;
        } else if (c >= 0xE0 && c <= 0xEF) {
            if (i + 2 >= n || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80) return 0;
            if (c == 0xE0 && s[i + 1] < 0xA0) return 0;
            if (c == 0xED && s[i + 1] > 0x9F) return 0;
            /* U+FFFE and U+FFFF are not XML characters */
            if (c == 0xEF && s[i + 1] == 0xBF && s[i + 2] >= 0xBE) return 0;
            i += 3;
        } else if (c >= 0xF0 && c <= 0xF4) {
            if (i + 3 >= n || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80
                || (s[i + 3] & 0xC0) != 0x80) return 0;
            if (c == 0xF0 && s[i + 1] < 0x90) return 0;
            if (c == 0xF4 && s[i + 1] > 0x8F) return 0;
            i += 4;
        } else {
            return 0;
        }
    }
    return 1;
}

/* A name-like text: valid UTF-8, within max BYTES, no control character. */
static int name_ok(const char *s, size_t max)
{
    if (!s) return 0;
    size_t n = strlen(s);
    if (n > max || !utf8_ok(s, n)) return 0;
    for (size_t i = 0; i < n; i++)
        if ((unsigned char)s[i] < 0x20 || s[i] == 0x7F) return 0;
    return 1;
}

/* Cell-like text: valid UTF-8 within max bytes. Of the control characters
 * only tab, newline and return are XML characters; the rest are refused. */
static int body_ok(const char *s, size_t max)
{
    if (!s) return 0;
    size_t n = strlen(s);
    if (n > max || !utf8_ok(s, n)) return 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') return 0;
    }
    return 1;
}

/* Characters, not bytes: Excel's cell limit counts UTF-16 units. */
static size_t utf16_units(const char *s)
{
    size_t units = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if ((*p & 0xC0) == 0x80) continue;
        units += (*p >= 0xF0) ? 2 : 1;
    }
    return units;
}

static int same_word(const char *a, const char *b)
{
    for (; *a && *b; a++, b++)
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
    return *a == *b;
}

typedef struct { const char *word; int value; } xlx_choice;

/* A word from a list, by any letter case. */
static int choose(const char *word, const xlx_choice *list, int *out)
{
    if (!word) return 0;
    for (; list->word; list++)
        if (same_word(word, list->word)) { *out = list->value; return 1; }
    return 0;
}

/* A colour: "#RRGGBB", "RRGGBB", "r,g,b" (0 to 255 each, as xTalk writes a
 * colour) or one of a few names. libxlsxwriter keeps 0 for "not set", so
 * black travels as its LXW_COLOR_BLACK. */
static int color_in(const char *s, lxw_color_t *out)
{
    static const xlx_choice names[] = {
        {"black", 0x000000}, {"white", 0xFFFFFF}, {"red", 0xFF0000}, {"green", 0x008000},
        {"blue", 0x0000FF}, {"yellow", 0xFFFF00}, {"orange", 0xFF6600}, {"gray", 0x808080},
        {"grey", 0x808080}, {"silver", 0xC0C0C0}, {"purple", 0x800080}, {"pink", 0xFF00FF},
        {"magenta", 0xFF00FF}, {"cyan", 0x00FFFF}, {"navy", 0x000080}, {"brown", 0x800000},
        {"lime", 0x00FF00}, {NULL, 0}};
    int value = -1;
    if (!s || !*s) return 0;
    if (strchr(s, ',')) {
        int r, g, b, used = 0;
        if (sscanf(s, " %d , %d , %d %n", &r, &g, &b, &used) != 3 || s[used] != '\0') return 0;
        if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return 0;
        value = (r << 16) | (g << 8) | b;
    } else if (!choose(s, names, &value)) {
        const char *p = (*s == '#') ? s + 1 : s;
        if (strlen(p) != 6) return 0;
        value = 0;
        for (int i = 0; i < 6; i++) {
            int c = tolower((unsigned char)p[i]);
            int digit = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
            if (digit < 0) return 0;
            value = value * 16 + digit;
        }
    }
    *out = value == 0 ? LXW_COLOR_BLACK : (lxw_color_t)value;
    return 1;
}

static int cell_in(int row, int col) { return row >= 1 && row <= XLX_MAX_ROW && col >= 1 && col <= XLX_MAX_COL; }

static int range_in(int r1, int c1, int r2, int c2)
{
    return cell_in(r1, c1) && cell_in(r2, c2) && r1 <= r2 && c1 <= c2;
}

static int fin(double v) { return isfinite(v); }

/* ------------------------------------------------------------------ */
/* Numbers as text, in and out, with a "." in every locale. An engine  */
/* built on GTK calls setlocale(), after which printf and strtod use   */
/* the user's decimal comma.                                           */
/* ------------------------------------------------------------------ */
static char decimal_point(void)
{
    struct lconv *lc = localeconv();
    return (lc && lc->decimal_point && lc->decimal_point[0]) ? lc->decimal_point[0] : '.';
}

/* The grammar of a plain decimal number, and nothing strtod would also
 * take ("inf", "nan", hex, leading space):
 *   [+-] digits [. digits] [(e|E) [+-] digits]   or   [+-] . digits ...   */
static int number_shape(const char *s, size_t n)
{
    size_t i = 0, digits = 0;
    if (i < n && (s[i] == '+' || s[i] == '-')) i++;
    while (i < n && s[i] >= '0' && s[i] <= '9') { i++; digits++; }
    if (i < n && s[i] == '.') {
        i++;
        while (i < n && s[i] >= '0' && s[i] <= '9') { i++; digits++; }
    }
    if (digits == 0) return 0;
    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
        size_t exp_digits = 0;
        i++;
        if (i < n && (s[i] == '+' || s[i] == '-')) i++;
        while (i < n && s[i] >= '0' && s[i] <= '9') { i++; exp_digits++; }
        if (exp_digits == 0) return 0;
    }
    return i == n;
}

static int number_in(const char *s, size_t n, double *out)
{
    char buf[80];
    if (n == 0 || n >= sizeof buf || !number_shape(s, n)) return 0;
    char point = decimal_point();
    for (size_t i = 0; i < n; i++) buf[i] = (s[i] == '.') ? point : s[i];
    buf[n] = '\0';
    char *end = NULL;
    double v = strtod(buf, &end);
    if (end != buf + n || !isfinite(v)) return 0;
    *out = v;
    return 1;
}

/* The shortest of %.15g, %.16g and %.17g that reads back as the same double:
 * 0.1 prints as 0.1, and no digit of a value is lost. */
static void number_out(double v, char *buf, size_t size)
{
    if (!isfinite(v)) { snprintf(buf, size, "0"); return; }
    if (v == 0) { snprintf(buf, size, "0"); return; }
    for (int precision = 15; precision <= 17; precision++) {
        snprintf(buf, size, "%.*g", precision, v);
        if (precision == 17 || strtod(buf, NULL) == v) break;
    }
    char point = decimal_point();
    if (point != '.')
        for (char *p = buf; *p; p++) if (*p == point) *p = '.';
}

/* libxlsxwriter's number printer. With USE_DTOA_LIBRARY it writes every
 * cell's number through emyg_dtoa(value, buffer) (declared by its
 * third_party/dtoa/emyg_dtoa.h, into a 32-byte buffer) instead of printf,
 * which is what keeps a decimal comma out of the file. The implementation it
 * bundles reads past the end of a table for some small numbers, so that file
 * is not compiled (CMakeLists.txt says more) and this is the function:
 * the same shortest-round-trip text the reader half prints, 24 characters at
 * most. Not static, not exported: the library's symbols are hidden. */
void emyg_dtoa(double value, char *buffer);
void emyg_dtoa(double value, char *buffer)
{
    number_out(value, buffer, 32);
}

/* ------------------------------------------------------------------ */
/* Dates. Excel counts days: serial 1 is 1900-01-01, and serial 60 is  */
/* a 1900-02-29 that never happened (a bug kept on purpose since       */
/* Lotus 1-2-3), so from 1900-03-01 on a serial is a day count from    */
/* 1899-12-30. A file may instead count from 1904-01-01.               */
/* ------------------------------------------------------------------ */
/* Days from 1970-01-01 to a civil date and back (Howard Hinnant's
 * algorithms; proleptic Gregorian). */
static int64_t days_from_civil(int64_t y, int m, int d)
{
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    int64_t yoe = y - era * 400;
    int64_t doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void civil_from_days(int64_t z, int *y, int *m, int *d)
{
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t yy = yoe + era * 400;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = (int)(yy + (*m <= 2));
}

#define XLX_SERIAL_MAX 2958465.0          /* 9999-12-31 */
#define XLX_EPOCH_1900 (-25569)           /* 1899-12-30 as days from 1970 */
#define XLX_EPOCH_1904 (-24107)           /* 1904-01-01 */

static int days_in_month(int y, int m)
{
    static const int days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) return 29;
    return days[m - 1];
}

/* A serial as text. style 0: always "YYYY-MM-DD hh:mm:ss". style 1, what a
 * cell shows: the date alone when there is no time of day, the time alone
 * when there is no day (a serial below 1), both otherwise. Returns 0 for a
 * serial that is no date (negative, past 9999, not a number). */
static int serial_text(double serial, int date1904, int style, char *buf, size_t size)
{
    if (!isfinite(serial) || serial < 0 || serial >= XLX_SERIAL_MAX + 1) return 0;
    double whole = floor(serial);
    int64_t seconds = (int64_t)floor((serial - whole) * 86400.0 + 0.5);
    int64_t day = (int64_t)whole;
    if (seconds >= 86400) { seconds -= 86400; day += 1; }
    int hh = (int)(seconds / 3600), mi = (int)(seconds / 60 % 60), ss = (int)(seconds % 60);
    int y, m, d;
    if (date1904) {
        civil_from_days(day + XLX_EPOCH_1904, &y, &m, &d);
    } else if (day == 60) {
        y = 1900; m = 2; d = 29;
    } else if (day < 60) {
        civil_from_days(day + XLX_EPOCH_1900 + 1, &y, &m, &d);
    } else {
        civil_from_days(day + XLX_EPOCH_1900, &y, &m, &d);
    }
    if (style == 1 && day == 0 && !date1904) {
        snprintf(buf, size, "%02d:%02d:%02d", hh, mi, ss);
    } else if (style == 1 && seconds == 0) {
        snprintf(buf, size, "%04d-%02d-%02d", y, m, d);
    } else {
        snprintf(buf, size, "%04d-%02d-%02d %02d:%02d:%02d", y, m, d, hh, mi, ss);
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* Cell names                                                          */
/* ------------------------------------------------------------------ */
static void column_letters(int col, char *out)     /* out: at least 4 bytes */
{
    char tmp[4];
    int n = 0;
    while (col > 0 && n < 3) {
        col--;
        tmp[n++] = (char)('A' + col % 26);
        col /= 26;
    }
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

/* "B3", "$B$3", "b3" -> row and column. A reference outside the grid, or
 * anything else, is 0. `end` (optional) receives where the reference ended. */
static int cell_ref(const char *s, int *row, int *col, const char **end)
{
    const char *p = s;
    int c = 0, letters = 0;
    int64_t r = 0;
    if (!p) return 0;
    if (*p == '$') p++;
    while (isalpha((unsigned char)*p) && letters < 4) {
        c = c * 26 + (toupper((unsigned char)*p) - 'A' + 1);
        p++; letters++;
    }
    if (letters == 0 || letters > 3 || c > XLX_MAX_COL) return 0;
    if (*p == '$') p++;
    if (!(*p >= '1' && *p <= '9')) return 0;
    int digits = 0;
    while (*p >= '0' && *p <= '9' && digits < 8) { r = r * 10 + (*p - '0'); p++; digits++; }
    if (r < 1 || r > XLX_MAX_ROW) return 0;
    if (end) *end = p; else if (*p != '\0') return 0;
    *row = (int)r;
    *col = c;
    return 1;
}

/* ------------------------------------------------------------------ */
/* Files with UTF-8 paths                                              */
/* ------------------------------------------------------------------ */
static FILE *open_utf8(const char *path, const char *mode)
{
#if defined(_WIN32)
    wchar_t wide[XLX_MAX_PATH + 1], wide_mode[8];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, XLX_MAX_PATH)) return NULL;
    if (!MultiByteToWideChar(CP_UTF8, 0, mode, -1, wide_mode, 8)) return NULL;
    return _wfopen(wide, wide_mode);
#else
    return fopen(path, mode);
#endif
}

static char *copy_text(const char *s)
{
    size_t n = strlen(s);
    char *copy = (char *)malloc(n + 1);
    if (copy) memcpy(copy, s, n + 1);
    return copy;
}

/* ================================================================== */
/*                               WRITING                              */
/* ================================================================== */

#define XLX_PROPERTY_COUNT 9

typedef struct xlx_book {
    lxw_workbook *wb;
    char *tmpdir;                         /* libxlsxwriter keeps the pointer   */
    char *props[XLX_PROPERTY_COUNT];
    lxw_format *date_formats[3];          /* date, date and time, time         */
    int sheet_count;
    int errors;                           /* refused calls on this workbook    */
    char first_error[sizeof s_error];
} xlx_book;

typedef struct { lxw_worksheet *ws; int book; } xlx_sheet;
typedef struct { lxw_format *fmt; int book; } xlx_format;
typedef struct xlx_chart {
    lxw_chart *chart;
    int book;
    int inserted;
    lxw_chart_series **series;
    int series_count, series_cap;
} xlx_chart;

DEFINE_TABLE(books, xlx_book *, 1)
DEFINE_TABLE(sheets, xlx_sheet, 2)
DEFINE_TABLE(formats, xlx_format, 3)
DEFINE_TABLE(charts, xlx_chart *, 4)

/* The folder libxlsxwriter makes its temporary files in; "" = its default. */
static char s_tmpdir[XLX_MAX_PATH + 1] = "";

static xlx_book *book_of(int h)
{
    int slot = books_slot_of(h);
    return slot < 0 ? NULL : books_arr[slot];
}

/* A refusal that belongs to a workbook: counted there, the first one kept. */
static int refuse(xlx_book *book)
{
    if (book) {
        if (book->errors == 0) memcpy(book->first_error, s_error, sizeof s_error);
        if (book->errors < INT_MAX) book->errors++;
    }
    return 0;
}

static xlx_book *book_in(int h)
{
    xlx_book *book = book_of(h);
    if (!book) fail("not an open workbook (handle %d)", h);
    return book;
}

static xlx_sheet *sheet_in(int h, xlx_book **book)
{
    int slot = sheets_slot_of(h);
    if (slot < 0 || !(*book = book_of(sheets_arr[slot].book))) {
        fail("not a sheet of an open workbook (handle %d)", h);
        return NULL;
    }
    return &sheets_arr[slot];
}

static xlx_format *format_in(int h, xlx_book **book)
{
    int slot = formats_slot_of(h);
    if (slot < 0 || !(*book = book_of(formats_arr[slot].book))) {
        fail("not a format of an open workbook (handle %d)", h);
        return NULL;
    }
    return &formats_arr[slot];
}

static xlx_chart *chart_in(int h, xlx_book **book)
{
    int slot = charts_slot_of(h);
    if (slot < 0 || !(*book = book_of(charts_arr[slot]->book))) {
        fail("not a chart of an open workbook (handle %d)", h);
        return NULL;
    }
    return charts_arr[slot];
}

/* The format argument of a write: 0 is "none"; anything else must be a
 * format of the SAME workbook (libxlsxwriter holds formats by pointer, and
 * one from another workbook dies with that workbook). */
static int cell_format(int h, int book, lxw_format **out)
{
    *out = NULL;
    if (h == 0) return 1;
    int slot = formats_slot_of(h);
    if (slot < 0) return fail("not a format (handle %d); pass 0 for no format", h);
    if (formats_arr[slot].book != book) return fail("that format belongs to another workbook");
    *out = formats_arr[slot].fmt;
    return 1;
}

static int lxw_ok(lxw_error e)
{
    if (e == LXW_NO_ERROR) return 1;
    return fail("%s", lxw_strerror(e));
}

static void book_release(int h)
{
    int slot = books_slot_of(h);
    if (slot < 0) return;
    xlx_book *book = books_arr[slot];
    for (int i = 0; i < sheets_cnt; i++)
        if (sheets_used[i] && sheets_arr[i].book == h) sheets_free_slot(i);
    for (int i = 0; i < formats_cnt; i++)
        if (formats_used[i] && formats_arr[i].book == h) formats_free_slot(i);
    for (int i = 0; i < charts_cnt; i++)
        if (charts_used[i] && charts_arr[i]->book == h) {
            free(charts_arr[i]->series);
            free(charts_arr[i]);
            charts_free_slot(i);
        }
    for (int i = 0; i < XLX_PROPERTY_COUNT; i++) free(book->props[i]);
    free(book->tmpdir);
    free(book);
    books_free_slot(slot);
}

/* ------------------------------------------------------------------ */
/* The library                                                         */
/* ------------------------------------------------------------------ */
LC_API int xlx_abi_version(void)
{
    return XLX_ABI_VERSION;
}

LC_API const char *xlx_library_version(void)
{
    static char text[160];
    XML_Expat_Version expat = XML_ExpatVersionInfo();
    snprintf(text, sizeof text, "xlsxt ABI %d; libxlsxwriter %s; zlib %s; Expat %d.%d.%d",
             XLX_ABI_VERSION, lxw_version(), zlibVersion(), expat.major, expat.minor, expat.micro);
    return text;
}

/* NOT cleared by itself, so asking twice gives the same answer. */
LC_API const char *xlx_last_error(void)
{
    static char copy[sizeof s_error];
    memcpy(copy, s_error, sizeof copy);
    return copy;
}

/* The length in bytes of a text this library returned. The binding's
 * textOf() asks, then has the engine copy that many bytes; it has no public
 * handler. */
LC_API int xlx_text_length(const char *text)
{
    if (!text) return 0;
    size_t n = strlen(text);
    return n > (size_t)INT_MAX ? INT_MAX : (int)n;
}

LC_API void xlx_set_temp_folder(const char *folder)
{
    ok_clear();
    if (!folder || !*folder) { s_tmpdir[0] = '\0'; return; }
    if (!name_ok(folder, XLX_MAX_PATH)) { fail("the folder path is not valid text, or is too long"); return; }
    memcpy(s_tmpdir, folder, strlen(folder) + 1);
}

LC_API const char *xlx_temp_folder(void)
{
    ok_clear();
    return text_of(s_tmpdir);
}

/* ------------------------------------------------------------------ */
/* Cell names and dates: pure functions                                */
/* ------------------------------------------------------------------ */
LC_API const char *xlx_column_name(int column)
{
    char letters[4];
    ok_clear();
    if (column < 1 || column > XLX_MAX_COL) { fail("a column is 1 to %d", XLX_MAX_COL); return ""; }
    column_letters(column, letters);
    return text_of(letters);
}

LC_API const char *xlx_cell_name(int row, int column)
{
    char letters[4], name[24];
    ok_clear();
    if (!cell_in(row, column)) { fail("a row is 1 to %d and a column 1 to %d", XLX_MAX_ROW, XLX_MAX_COL); return ""; }
    column_letters(column, letters);
    snprintf(name, sizeof name, "%s%d", letters, row);
    return text_of(name);
}

LC_API const char *xlx_range_name(int first_row, int first_column, int last_row, int last_column)
{
    char a[4], b[4], name[48];
    ok_clear();
    if (!range_in(first_row, first_column, last_row, last_column)) {
        fail("not a range: the first cell must be above and left of the last, inside the grid");
        return "";
    }
    column_letters(first_column, a);
    column_letters(last_column, b);
    snprintf(name, sizeof name, "%s%d:%s%d", a, first_row, b, last_row);
    return text_of(name);
}

/* "=Sheet1!$A$2:$A$7", the form a chart series wants. A sheet name that is
 * not plain letters, digits and underscores is quoted, its own apostrophes
 * doubled. */
LC_API const char *xlx_range_formula(const char *sheet_name, int first_row, int first_column,
                                     int last_row, int last_column)
{
    char a[4], b[4], tail[64];
    ok_clear();
    if (!name_ok(sheet_name, XLX_MAX_NAME) || !*sheet_name) { fail("the sheet name is empty or not valid text"); return ""; }
    if (!range_in(first_row, first_column, last_row, last_column)) {
        fail("not a range: the first cell must be above and left of the last, inside the grid");
        return "";
    }
    int plain = !(sheet_name[0] >= '0' && sheet_name[0] <= '9');
    for (const char *p = sheet_name; *p; p++)
        if (!(isalnum((unsigned char)*p) && (unsigned char)*p < 0x80) && *p != '_') plain = 0;
    text_begin();
    text_addc('=');
    if (!plain) text_addc('\'');
    for (const char *p = sheet_name; *p; p++) {
        if (*p == '\'') text_addc('\'');
        text_addc(*p);
    }
    if (!plain) text_addc('\'');
    column_letters(first_column, a);
    column_letters(last_column, b);
    snprintf(tail, sizeof tail, "!$%s$%d:$%s$%d", a, first_row, b, last_row);
    text_add(tail, strlen(tail));
    return text_done();
}

LC_API int xlx_cell_row(const char *name)
{
    int row, col;
    ok_clear();
    if (!cell_ref(name, &row, &col, NULL)) return fail("not a cell name such as B3");
    return row;
}

LC_API int xlx_cell_column(const char *name)
{
    int row, col;
    ok_clear();
    if (!cell_ref(name, &row, &col, NULL)) return fail("not a cell name such as B3");
    return col;
}

/* A date and time of day as a serial. year, month and day all 0 means "a
 * time of day only". Refused (-1) for anything that is not a date Excel
 * has: before 1900-01-01, after 9999-12-31, a 30th of February. */
LC_API double xlx_date_to_serial(int year, int month, int day, int hour, int minute, double second)
{
    ok_clear();
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || !(second >= 0 && second < 60)) {
        fail("not a time of day: hours 0 to 23, minutes 0 to 59, seconds 0 up to 60");
        return -1;
    }
    double fraction = (hour * 3600.0 + minute * 60.0 + second) / 86400.0;
    if (year == 0 && month == 0 && day == 0) return fraction;
    if (year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1 || day > days_in_month(year, month)) {
        fail("not a date between 1900-01-01 and 9999-12-31");
        return -1;
    }
    int64_t days = days_from_civil(year, month, day) - XLX_EPOCH_1900;
    if (days < 61) days -= 1;             /* before 1900-03-01: see "Dates" above */
    return (double)days + fraction;
}

LC_API const char *xlx_serial_to_date(double serial)
{
    char text[40];
    ok_clear();
    if (!serial_text(serial, 0, 0, text, sizeof text)) { fail("not a date serial (0 up to 2958466)"); return ""; }
    return text_of(text);
}

/* xTalk's `the seconds` counts from 1970-01-01, which is serial 25569. No
 * time zone is applied in either direction: a serial has none. */
LC_API double xlx_seconds_to_serial(double seconds)
{
    ok_clear();
    double serial = seconds / 86400.0 + 25569.0;
    if (!isfinite(seconds) || serial < 0 || serial >= XLX_SERIAL_MAX + 1) {
        fail("those seconds are not a date between 1900 and 9999");
        return -1;
    }
    return serial;
}

LC_API double xlx_serial_to_seconds(double serial)
{
    ok_clear();
    if (!isfinite(serial) || serial < 0 || serial >= XLX_SERIAL_MAX + 1) {
        fail("not a date serial (0 up to 2958466)");
        return 0;
    }
    return floor((serial - 25569.0) * 86400.0 + 0.5);
}

/* ------------------------------------------------------------------ */
/* Workbooks                                                           */
/* ------------------------------------------------------------------ */
LC_API int xlx_workbook_count(void)
{
    return books_live;
}

LC_API int xlx_workbook_new(const char *path)
{
    ok_clear();
    if (!name_ok(path, XLX_MAX_PATH) || !*path) return fail("the file path is empty, too long or not valid text");
    xlx_book *book = (xlx_book *)calloc(1, sizeof *book);
    if (!book) return fail("out of memory");

    /* Where the temporary files go: the folder the script chose; else, on
     * Android (which has no /tmp an app may write to), the folder the
     * workbook itself is being saved in; else libxlsxwriter's default (the
     * TMPDIR / TEMP of the process). */
    if (s_tmpdir[0]) {
        book->tmpdir = copy_text(s_tmpdir);
    }
#if defined(__ANDROID__)
    else {
        const char *slash = strrchr(path, '/');
        if (slash && slash != path) {
            book->tmpdir = (char *)malloc((size_t)(slash - path) + 1);
            if (book->tmpdir) {
                memcpy(book->tmpdir, path, (size_t)(slash - path));
                book->tmpdir[slash - path] = '\0';
            }
        }
    }
#endif
    lxw_workbook_options options;
    memset(&options, 0, sizeof options);
    options.tmpdir = book->tmpdir;
    book->wb = workbook_new_opt(path, &options);
    if (!book->wb) {
        free(book->tmpdir);
        free(book);
        return fail("out of memory");
    }
    int h = books_add(book);
    if (!h) {
        lxw_workbook_free(book->wb);
        free(book->tmpdir);
        free(book);
        return fail("too many open workbooks");
    }
    return h;
}

LC_API int xlx_workbook_is_valid(int book)
{
    return book_of(book) != NULL;
}

/* Writes the file. The workbook and every sheet, format and chart of it are
 * gone afterwards, whether the file could be written or not. */
LC_API int xlx_workbook_close(int book)
{
    static const char *const empty = NULL;
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return 0;

    lxw_doc_properties props;
    memset(&props, 0, sizeof props);
    props.title = b->props[0];
    props.subject = b->props[1];
    props.author = b->props[2];
    props.manager = b->props[3];
    props.company = b->props[4];
    props.category = b->props[5];
    props.keywords = b->props[6];
    props.comments = b->props[7];
    props.status = b->props[8];
    int any = 0;
    for (int i = 0; i < XLX_PROPERTY_COUNT; i++) any |= b->props[i] != empty;
    if (any) workbook_set_properties(b->wb, &props);

    lxw_error e = workbook_close(b->wb);      /* frees the workbook either way */
    b->wb = NULL;
    book_release(book);
    return lxw_ok(e);
}

LC_API void xlx_workbook_discard(int book)
{
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return;
    lxw_workbook_free(b->wb);
    b->wb = NULL;
    book_release(book);
}

LC_API int xlx_workbook_error_count(int book)
{
    xlx_book *b = book_of(book);
    return b ? b->errors : 0;
}

LC_API const char *xlx_workbook_first_error(int book)
{
    xlx_book *b = book_of(book);
    return text_of(b && b->errors ? b->first_error : "");
}

LC_API int xlx_workbook_sheet_count(int book)
{
    xlx_book *b = book_of(book);
    return b ? b->sheet_count : 0;
}

LC_API int xlx_workbook_add_sheet(int book, const char *name)
{
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return 0;
    if (!name) name = "";
    if (*name) {
        if (!name_ok(name, XLX_MAX_NAME)) { fail("the sheet name is not valid text"); return refuse(b); }
        lxw_error e = workbook_validate_sheet_name(b->wb, name);
        if (e != LXW_NO_ERROR) {
            fail("sheet name refused: %s (at most 31 characters, none of [ ] : * ? / \\, no "
                 "apostrophe at either end, and no name used twice)", lxw_strerror(e));
            return refuse(b);
        }
    }
    lxw_worksheet *ws = workbook_add_worksheet(b->wb, *name ? name : NULL);
    if (!ws) { fail("the sheet could not be added"); return refuse(b); }
    xlx_sheet sheet;
    sheet.ws = ws;
    sheet.book = book;
    int h = sheets_add(sheet);
    if (!h) { fail("too many sheets"); return refuse(b); }
    b->sheet_count++;
    return h;
}

LC_API int xlx_workbook_add_format(int book)
{
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return 0;
    xlx_format format;
    format.fmt = workbook_add_format(b->wb);
    format.book = book;
    if (!format.fmt) { fail("out of memory"); return refuse(b); }
    int h = formats_add(format);
    if (!h) { fail("too many formats"); return refuse(b); }
    return h;
}

LC_API int xlx_workbook_add_chart(int book, const char *kind)
{
    static const xlx_choice kinds[] = {
        {"column", LXW_CHART_COLUMN}, {"column stacked", LXW_CHART_COLUMN_STACKED},
        {"column percent", LXW_CHART_COLUMN_STACKED_PERCENT},
        {"bar", LXW_CHART_BAR}, {"bar stacked", LXW_CHART_BAR_STACKED},
        {"bar percent", LXW_CHART_BAR_STACKED_PERCENT},
        {"line", LXW_CHART_LINE}, {"line stacked", LXW_CHART_LINE_STACKED},
        {"line percent", LXW_CHART_LINE_STACKED_PERCENT},
        {"area", LXW_CHART_AREA}, {"area stacked", LXW_CHART_AREA_STACKED},
        {"area percent", LXW_CHART_AREA_STACKED_PERCENT},
        {"pie", LXW_CHART_PIE}, {"doughnut", LXW_CHART_DOUGHNUT},
        {"scatter", LXW_CHART_SCATTER}, {"scatter lines", LXW_CHART_SCATTER_STRAIGHT_WITH_MARKERS},
        {"scatter smooth", LXW_CHART_SCATTER_SMOOTH_WITH_MARKERS},
        {"radar", LXW_CHART_RADAR}, {"radar markers", LXW_CHART_RADAR_WITH_MARKERS},
        {NULL, 0}};
    int type = 0;
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return 0;
    if (!choose(kind, kinds, &type)) {
        fail("not a chart kind: column, bar, line, area (each also \"... stacked\" and \"... percent\"), "
             "pie, doughnut, scatter, scatter lines, scatter smooth, radar, radar markers");
        return refuse(b);
    }
    xlx_chart *chart = (xlx_chart *)calloc(1, sizeof *chart);
    if (!chart) { fail("out of memory"); return refuse(b); }
    chart->chart = workbook_add_chart(b->wb, (uint8_t)type);
    chart->book = book;
    if (!chart->chart) { free(chart); fail("out of memory"); return refuse(b); }
    int h = charts_add(chart);
    if (!h) { free(chart); fail("too many charts"); return refuse(b); }
    return h;
}

/* The document properties Excel shows under File > Info. Kept here and
 * handed to libxlsxwriter once, when the workbook is closed. */
LC_API void xlx_workbook_set_property(int book, const char *name, const char *value)
{
    static const xlx_choice names[] = {
        {"title", 0}, {"subject", 1}, {"author", 2}, {"manager", 3}, {"company", 4},
        {"category", 5}, {"keywords", 6}, {"comments", 7}, {"status", 8}, {NULL, 0}};
    int which = 0;
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return;
    if (!choose(name, names, &which)) {
        fail("not a property: title, subject, author, manager, company, category, keywords, comments, status");
        refuse(b);
        return;
    }
    if (!body_ok(value, XLX_MAX_CELL_TEXT)) { fail("the property value is not valid text, or is too long"); refuse(b); return; }
    char *copy = *value ? copy_text(value) : NULL;
    if (*value && !copy) { fail("out of memory"); refuse(b); return; }
    free(b->props[which]);
    b->props[which] = copy;
}

/* A defined name: "Rate" for "=Sheet1!$B$1", or "Sheet2!Total" for a name
 * local to one sheet. */
LC_API void xlx_workbook_define_name(int book, const char *name, const char *formula)
{
    ok_clear();
    xlx_book *b = book_in(book);
    if (!b) return;
    /* libxlsxwriter keeps both in fixed fields of 128 bytes and cuts what
     * does not fit; a name cut short is another name, so it is refused. */
    if (!name_ok(name, LXW_DEFINED_NAME_LENGTH - 1) || !*name) {
        fail("the name is empty, longer than %d bytes or not valid text", LXW_DEFINED_NAME_LENGTH - 1);
        refuse(b);
        return;
    }
    if (!name_ok(formula, LXW_DEFINED_NAME_LENGTH - 1) || !*formula) {
        fail("the formula is empty, longer than %d bytes or not valid text", LXW_DEFINED_NAME_LENGTH - 1);
        refuse(b);
        return;
    }
    /* Excel's rules for the name itself (after an optional "Sheet!"), which
     * libxlsxwriter does not check: a file with a name that breaks them is
     * one Excel offers to repair. It starts with a letter, an underscore or
     * a backslash, goes on with letters, digits, underscores and full
     * stops, and does not read as a cell (B3). */
    const char *bang = strrchr(name, '!');
    const char *own = bang ? bang + 1 : name;
    int row, col, good = *own && (isalpha((unsigned char)*own) || *own == '_' || *own == '\\' || (unsigned char)*own >= 0x80);
    for (const char *p = own; good && *p; p++)
        good = isalnum((unsigned char)*p) || *p == '_' || *p == '.' || *p == '\\' || (unsigned char)*p >= 0x80;
    if (!good || cell_ref(own, &row, &col, NULL) || bang == name) {
        fail("not a name Excel allows: a letter or underscore first, then letters, digits, underscores and full "
             "stops, and not the name of a cell");
        refuse(b);
        return;
    }
    if (!lxw_ok(workbook_define_name(b->wb, name, formula))) refuse(b);
}

/* ------------------------------------------------------------------ */
/* Formats. A format is a live object: cells hold it by reference, so  */
/* changing one changes every cell written with it, before or after.   */
/* ------------------------------------------------------------------ */
#define FORMAT_OR_RETURN                                                      \
    xlx_book *b = NULL;                                                       \
    ok_clear();                                                               \
    xlx_format *f = format_in(format, &b);                                    \
    if (!f) return;

LC_API int xlx_format_is_valid(int format)
{
    int slot = formats_slot_of(format);
    return slot >= 0 && book_of(formats_arr[slot].book) != NULL;
}

LC_API void xlx_format_set_bold(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->bold = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_format_set_italic(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->italic = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_format_set_strikeout(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->font_strikeout = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_format_set_underline(int format, const char *style)
{
    static const xlx_choice styles[] = {
        {"none", LXW_UNDERLINE_NONE}, {"single", LXW_UNDERLINE_SINGLE}, {"double", LXW_UNDERLINE_DOUBLE},
        {"single accounting", LXW_UNDERLINE_SINGLE_ACCOUNTING},
        {"double accounting", LXW_UNDERLINE_DOUBLE_ACCOUNTING}, {NULL, 0}};
    int value = 0;
    FORMAT_OR_RETURN
    if (!choose(style, styles, &value)) {
        fail("not an underline: none, single, double, single accounting, double accounting");
        refuse(b);
        return;
    }
    f->fmt->underline = (uint8_t)value;
}

LC_API void xlx_format_set_script(int format, const char *style)
{
    static const xlx_choice styles[] = {
        {"none", 0}, {"superscript", LXW_FONT_SUPERSCRIPT}, {"subscript", LXW_FONT_SUBSCRIPT}, {NULL, 0}};
    int value = 0;
    FORMAT_OR_RETURN
    if (!choose(style, styles, &value)) { fail("not a script: none, superscript, subscript"); refuse(b); return; }
    f->fmt->font_script = (uint8_t)value;
}

LC_API void xlx_format_set_font_name(int format, const char *name)
{
    FORMAT_OR_RETURN
    /* libxlsxwriter keeps a font name in a fixed 128-byte field. */
    if (!name_ok(name, LXW_FORMAT_FIELD_LEN - 1) || !*name) {
        fail("the font name is empty, longer than %d bytes or not valid text", LXW_FORMAT_FIELD_LEN - 1);
        refuse(b);
        return;
    }
    format_set_font_name(f->fmt, name);
}

LC_API void xlx_format_set_font_size(int format, double size)
{
    FORMAT_OR_RETURN
    if (!(size >= 1 && size <= 409)) { fail("a font size is 1 to 409 points"); refuse(b); return; }
    format_set_font_size(f->fmt, size);
}

LC_API void xlx_format_set_font_color(int format, const char *color)
{
    lxw_color_t value;
    FORMAT_OR_RETURN
    if (!color_in(color, &value)) { fail("not a colour: #RRGGBB, r,g,b or a basic colour name"); refuse(b); return; }
    format_set_font_color(f->fmt, value);
}

/* The fill of the cell. A colour alone does nothing in Excel without a
 * pattern, so this sets the solid one too. */
LC_API void xlx_format_set_background_color(int format, const char *color)
{
    lxw_color_t value;
    FORMAT_OR_RETURN
    if (!color_in(color, &value)) { fail("not a colour: #RRGGBB, r,g,b or a basic colour name"); refuse(b); return; }
    format_set_pattern(f->fmt, LXW_PATTERN_SOLID);
    format_set_bg_color(f->fmt, value);
}

/* An Excel number format code: "0.00", "#,##0", "0%", "yyyy-mm-dd", "@". */
LC_API void xlx_format_set_number_format(int format, const char *code)
{
    FORMAT_OR_RETURN
    if (!name_ok(code, LXW_FORMAT_FIELD_LEN - 1) || !*code) {
        fail("the number format is empty, longer than %d bytes or not valid text", LXW_FORMAT_FIELD_LEN - 1);
        refuse(b);
        return;
    }
    format_set_num_format(f->fmt, code);
}

LC_API void xlx_format_set_align(int format, const char *alignment)
{
    static const xlx_choice choices[] = {
        {"general", LXW_ALIGN_NONE}, {"left", LXW_ALIGN_LEFT}, {"center", LXW_ALIGN_CENTER},
        {"centre", LXW_ALIGN_CENTER}, {"right", LXW_ALIGN_RIGHT}, {"fill", LXW_ALIGN_FILL},
        {"justify", LXW_ALIGN_JUSTIFY}, {"center across", LXW_ALIGN_CENTER_ACROSS},
        {"distributed", LXW_ALIGN_DISTRIBUTED}, {NULL, 0}};
    int value = 0;
    FORMAT_OR_RETURN
    if (!choose(alignment, choices, &value)) {
        fail("not an alignment: general, left, center, right, fill, justify, center across, distributed");
        refuse(b);
        return;
    }
    f->fmt->text_h_align = (uint8_t)value;
}

LC_API void xlx_format_set_vertical_align(int format, const char *alignment)
{
    static const xlx_choice choices[] = {
        {"top", LXW_ALIGN_VERTICAL_TOP}, {"middle", LXW_ALIGN_VERTICAL_CENTER},
        {"center", LXW_ALIGN_VERTICAL_CENTER}, {"centre", LXW_ALIGN_VERTICAL_CENTER},
        {"bottom", LXW_ALIGN_VERTICAL_BOTTOM}, {"justify", LXW_ALIGN_VERTICAL_JUSTIFY},
        {"distributed", LXW_ALIGN_VERTICAL_DISTRIBUTED}, {NULL, 0}};
    int value = 0;
    FORMAT_OR_RETURN
    if (!choose(alignment, choices, &value)) {
        fail("not a vertical alignment: top, middle, bottom, justify, distributed");
        refuse(b);
        return;
    }
    f->fmt->text_v_align = (uint8_t)value;
}

LC_API void xlx_format_set_text_wrap(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->text_wrap = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_format_set_shrink(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->shrink = flag ? LXW_TRUE : LXW_FALSE;
}

/* Degrees, -90 to 90; 270 stacks the letters top to bottom. */
LC_API void xlx_format_set_rotation(int format, int degrees)
{
    FORMAT_OR_RETURN
    if (!((degrees >= -90 && degrees <= 90) || degrees == 270)) {
        fail("a rotation is -90 to 90 degrees, or 270 for stacked letters");
        refuse(b);
        return;
    }
    format_set_rotation(f->fmt, (int16_t)degrees);
}

LC_API void xlx_format_set_indent(int format, int level)
{
    FORMAT_OR_RETURN
    if (level < 0 || level > 250) { fail("an indent is 0 to 250"); refuse(b); return; }
    f->fmt->indent = (uint8_t)level;
}

static const xlx_choice k_borders[] = {
    {"none", LXW_BORDER_NONE}, {"thin", LXW_BORDER_THIN}, {"medium", LXW_BORDER_MEDIUM},
    {"dashed", LXW_BORDER_DASHED}, {"dotted", LXW_BORDER_DOTTED}, {"thick", LXW_BORDER_THICK},
    {"double", LXW_BORDER_DOUBLE}, {"hair", LXW_BORDER_HAIR},
    {"medium dashed", LXW_BORDER_MEDIUM_DASHED}, {"dash dot", LXW_BORDER_DASH_DOT},
    {"medium dash dot", LXW_BORDER_MEDIUM_DASH_DOT}, {"dash dot dot", LXW_BORDER_DASH_DOT_DOT},
    {"medium dash dot dot", LXW_BORDER_MEDIUM_DASH_DOT_DOT}, {"slant dash dot", LXW_BORDER_SLANT_DASH_DOT},
    {NULL, 0}};
#define XLX_BORDER_WORDS "none, thin, medium, thick, dashed, dotted, double, hair, medium dashed, " \
                         "dash dot, medium dash dot, dash dot dot, medium dash dot dot, slant dash dot"

LC_API void xlx_format_set_border(int format, const char *style)
{
    int value = 0;
    FORMAT_OR_RETURN
    if (!choose(style, k_borders, &value)) { fail("not a border: " XLX_BORDER_WORDS); refuse(b); return; }
    format_set_border(f->fmt, (uint8_t)value);
}

LC_API void xlx_format_set_border_side(int format, const char *side, const char *style)
{
    static const xlx_choice sides[] = {{"left", 0}, {"right", 1}, {"top", 2}, {"bottom", 3}, {NULL, 0}};
    int which = 0, value = 0;
    FORMAT_OR_RETURN
    if (!choose(side, sides, &which)) { fail("not a side: left, right, top, bottom"); refuse(b); return; }
    if (!choose(style, k_borders, &value)) { fail("not a border: " XLX_BORDER_WORDS); refuse(b); return; }
    switch (which) {
        case 0: format_set_left(f->fmt, (uint8_t)value); break;
        case 1: format_set_right(f->fmt, (uint8_t)value); break;
        case 2: format_set_top(f->fmt, (uint8_t)value); break;
        default: format_set_bottom(f->fmt, (uint8_t)value); break;
    }
}

LC_API void xlx_format_set_border_color(int format, const char *color)
{
    lxw_color_t value;
    FORMAT_OR_RETURN
    if (!color_in(color, &value)) { fail("not a colour: #RRGGBB, r,g,b or a basic colour name"); refuse(b); return; }
    format_set_border_color(f->fmt, value);
}

/* Both only matter on a sheet protected with xlx_sheet_protect. */
LC_API void xlx_format_set_locked(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->locked = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_format_set_formula_hidden(int format, int flag)
{
    FORMAT_OR_RETURN
    f->fmt->hidden = flag ? LXW_TRUE : LXW_FALSE;
}

/* ------------------------------------------------------------------ */
/* Sheets: cells                                                       */
/* ------------------------------------------------------------------ */
#define SHEET_OR_RETURN(RET)                                                  \
    xlx_book *b = NULL;                                                       \
    ok_clear();                                                               \
    xlx_sheet *s = sheet_in(sheet, &b);                                       \
    if (!s) return RET;

#define CELL_OR_RETURN(RET)                                                   \
    SHEET_OR_RETURN(RET)                                                      \
    lxw_format *fmt = NULL;                                                   \
    if (!cell_in(row, column)) {                                              \
        fail("no such cell: a row is 1 to %d and a column 1 to %d",           \
             XLX_MAX_ROW, XLX_MAX_COL);                                       \
        refuse(b);                                                            \
        return RET;                                                           \
    }                                                                         \
    if (!cell_format(format, s->book, &fmt)) { refuse(b); return RET; }

#define ROW0 ((lxw_row_t)(row - 1))
#define COL0 ((lxw_col_t)(column - 1))

LC_API int xlx_sheet_is_valid(int sheet)
{
    int slot = sheets_slot_of(sheet);
    return slot >= 0 && book_of(sheets_arr[slot].book) != NULL;
}

LC_API const char *xlx_sheet_name(int sheet)
{
    SHEET_OR_RETURN("")
    return text_of(s->ws->name);
}

LC_API void xlx_sheet_write_number(int sheet, int row, int column, double number, int format)
{
    CELL_OR_RETURN()
    if (!fin(number)) { fail("not a number a cell can hold (infinite, or not a number at all)"); refuse(b); return; }
    if (!lxw_ok(worksheet_write_number(s->ws, ROW0, COL0, number, fmt))) refuse(b);
}

static int cell_text_ok(const char *text)
{
    if (!body_ok(text, (size_t)XLX_MAX_CELL_TEXT * 4))
        return fail("the text is not valid UTF-8, or holds a control character other than tab and newline");
    if (utf16_units(text) > XLX_MAX_CELL_TEXT)
        return fail("a cell holds at most %d characters", XLX_MAX_CELL_TEXT);
    return 1;
}

/* A cell's text is stored in the file with ONE escape of the format's own:
 * "_xHHHH_" (four hex digits) stands for the character with that code,
 * which is how a file holds a carriage return ("_x000D_"). So a text that
 * really is the seven characters "_x0041_" must be written with its first
 * underscore escaped ("_x005F_x0041_") or Excel, and this library's reader,
 * show an "A". libxlsxwriter does not do that; this does. Returns `text`
 * itself when there is nothing to escape (nearly always), else a copy the
 * caller frees through *owned; NULL when memory ran out. */
static int is_hex(char c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static int escape_at(const char *p)
{
    return p[0] == '_' && p[1] == 'x' && is_hex(p[2]) && is_hex(p[3]) && is_hex(p[4]) && is_hex(p[5]) && p[6] == '_';
}

static const char *literal_text(const char *text, char **owned)
{
    size_t hits = 0, n = 0;
    *owned = NULL;
    for (const char *p = text; *p; p++, n++) if (*p == '_' && escape_at(p)) hits++;
    if (!hits) return text;
    char *copy = (char *)malloc(n + hits * 6 + 1), *out = copy;
    if (!copy) { fail("out of memory"); return NULL; }
    for (const char *p = text; *p; p++) {
        if (*p == '_' && escape_at(p)) { memcpy(out, "_x005F", 6); out += 6; }
        *out++ = *p;
    }
    *out = '\0';
    *owned = copy;
    return copy;
}

static int write_string(xlx_sheet *s, int row, int column, const char *text, lxw_format *fmt)
{
    char *owned = NULL;
    const char *literal = literal_text(text, &owned);
    if (!literal) return 0;
    int ok = lxw_ok(worksheet_write_string(s->ws, ROW0, COL0, literal, fmt));
    free(owned);
    return ok;
}

LC_API void xlx_sheet_write_text(int sheet, int row, int column, const char *text, int format)
{
    CELL_OR_RETURN()
    if (!cell_text_ok(text)) { refuse(b); return; }
    if (!write_string(s, row, column, text, fmt)) refuse(b);
}

static int formula_ok(const char *formula)
{
    if (!name_ok(formula, XLX_MAX_FORMULA) || !*formula)
        return fail("the formula is empty, longer than %d bytes or not valid text", XLX_MAX_FORMULA);
    return 1;
}

/* libxlsxwriter does not calculate: the file stores the formula with a
 * result of 0, and Excel computes it on opening. A viewer that does not
 * calculate (and this library's own reader) shows the stored result, which
 * xlx_sheet_write_formula_value lets the script supply. */
LC_API void xlx_sheet_write_formula(int sheet, int row, int column, const char *formula, int format)
{
    CELL_OR_RETURN()
    if (!formula_ok(formula)) { refuse(b); return; }
    if (!lxw_ok(worksheet_write_formula(s->ws, ROW0, COL0, formula, fmt))) refuse(b);
}

LC_API void xlx_sheet_write_formula_value(int sheet, int row, int column, const char *formula,
                                          double value, int format)
{
    CELL_OR_RETURN()
    if (!formula_ok(formula)) { refuse(b); return; }
    if (!fin(value)) { fail("not a number a cell can hold (infinite, or not a number at all)"); refuse(b); return; }
    if (!lxw_ok(worksheet_write_formula_num(s->ws, ROW0, COL0, formula, fmt, value))) refuse(b);
}

LC_API void xlx_sheet_write_boolean(int sheet, int row, int column, int flag, int format)
{
    CELL_OR_RETURN()
    if (!lxw_ok(worksheet_write_boolean(s->ws, ROW0, COL0, flag ? 1 : 0, fmt))) refuse(b);
}

/* A cell with a format and no value. With format 0 there is nothing to
 * write, and libxlsxwriter writes nothing. */
LC_API void xlx_sheet_write_blank(int sheet, int row, int column, int format)
{
    CELL_OR_RETURN()
    if (!lxw_ok(worksheet_write_blank(s->ws, ROW0, COL0, fmt))) refuse(b);
}

/* A date is a number that a format shows as a date. With format 0 the cell
 * gets one of three formats this workbook keeps for the purpose, chosen by
 * what the serial holds: a date, a date and a time, or a time alone. */
LC_API void xlx_sheet_write_date(int sheet, int row, int column, double serial, int format)
{
    static const char *const codes[3] = {"yyyy-mm-dd", "yyyy-mm-dd hh:mm:ss", "hh:mm:ss"};
    CELL_OR_RETURN()
    if (!isfinite(serial) || serial < 0 || serial >= XLX_SERIAL_MAX + 1) {
        fail("not a date serial (0 up to 2958466); xlx_date_to_serial makes one");
        refuse(b);
        return;
    }
    if (!fmt) {
        int which = serial < 1 ? 2 : (serial == floor(serial) ? 0 : 1);
        if (!b->date_formats[which]) {
            b->date_formats[which] = workbook_add_format(b->wb);
            if (!b->date_formats[which]) { fail("out of memory"); refuse(b); return; }
            format_set_num_format(b->date_formats[which], codes[which]);
        }
        fmt = b->date_formats[which];
    }
    if (!lxw_ok(worksheet_write_number(s->ws, ROW0, COL0, serial, fmt))) refuse(b);
}

/* A link: http://, https://, ftp://, mailto:, internal:Sheet2!A1 or
 * external:other.xlsx. `text` is what the cell shows; "" shows the link
 * (a mailto: link without its "mailto:", as Excel shows one).
 * libxlsxwriter takes any text at all as a link and writes it as one, which
 * gives a cell that looks like a link and goes nowhere; the kinds it knows
 * are asked for here. */
static int link_ok(const char *url)
{
    static const char *const starts[] = {"http://", "https://", "ftp://", "ftps://", "file://", "mailto:",
                                         "internal:", "external:", NULL};
    for (int i = 0; starts[i]; i++) {
        size_t n = strlen(starts[i]);
        if (strncmp(url, starts[i], n) == 0 && url[n] != '\0') return 1;
    }
    return 0;
}

LC_API void xlx_sheet_write_link(int sheet, int row, int column, const char *url, const char *text, int format)
{
    CELL_OR_RETURN()
    if (!name_ok(url, 2079) || !*url) { fail("the link is empty, longer than 2079 bytes or not valid text"); refuse(b); return; }
    if (!link_ok(url)) {
        fail("not a link: it must begin http://, https://, ftp://, ftps://, file://, mailto:, internal: or external:");
        refuse(b);
        return;
    }
    if (!text) text = "";
    if (*text && !cell_text_ok(text)) { refuse(b); return; }
    if (!fmt) fmt = workbook_get_default_url_format(b->wb);
    if (!lxw_ok(worksheet_write_url_opt(s->ws, ROW0, COL0, url, fmt, *text ? text : NULL, NULL))) refuse(b);
}

LC_API void xlx_sheet_write_comment(int sheet, int row, int column, const char *text)
{
    SHEET_OR_RETURN()
    if (!cell_in(row, column)) { fail("no such cell: a row is 1 to %d and a column 1 to %d", XLX_MAX_ROW, XLX_MAX_COL); refuse(b); return; }
    if (!cell_text_ok(text) || !*text) { if (text && !*text) fail("the comment is empty"); refuse(b); return; }
    if (!lxw_ok(worksheet_write_comment(s->ws, ROW0, COL0, text))) refuse(b);
}

/* A block of cells from one text: rows separated by newlines, cells by tabs,
 * which is how xTalk holds a table and what a field with tab stops shows.
 * Inside a cell a vertical tab (ASCII 11, xTalk's line break within a field
 * line) becomes a line break. An empty cell writes nothing. `mode`:
 *   "text"      every cell is text
 *   "numbers"   a cell that reads as a plain number is written as a number
 *   "formulas"  as "numbers", and a cell that begins with = is a formula
 * A number here is digits with an optional sign, decimal point and exponent,
 * at most 15 significant digits and no leading zero: a postcode, a phone
 * number and a 16-digit card number stay text, as their owners want.
 * Returns the number of cells written; a refused cell is skipped and counted
 * in the workbook's errors. */
static int grid_number(const char *s, size_t n, double *out)
{
    size_t i = 0, significant = 0, leading = 1;
    if (n > 40) return 0;
    if (i < n && (s[i] == '+' || s[i] == '-')) i++;
    /* no leading zero unless the whole integer part is "0" */
    if (i + 1 < n && s[i] == '0' && s[i + 1] >= '0' && s[i + 1] <= '9') return 0;
    for (; i < n && s[i] != 'e' && s[i] != 'E'; i++) {
        if (s[i] < '0' || s[i] > '9') continue;
        if (leading && s[i] == '0') continue;
        leading = 0;
        significant++;
    }
    if (significant > 15) return 0;
    return number_in(s, n, out);
}

LC_API int xlx_sheet_write_grid(int sheet, int row, int column, const char *text, const char *mode, int format)
{
    static const xlx_choice modes[] = {{"text", 0}, {"numbers", 1}, {"formulas", 2}, {NULL, 0}};
    int how = 0, written = 0;
    CELL_OR_RETURN(0)
    if (!choose(mode, modes, &how)) { fail("not a mode: text, numbers, formulas"); return refuse(b); }
    if (!text) text = "";
    size_t total = strlen(text);
    if (total > XLX_MAX_GRID_TEXT) { fail("the text is larger than %u MB", XLX_MAX_GRID_TEXT >> 20); return refuse(b); }
    if (!utf8_ok(text, total)) { fail("the text is not valid UTF-8"); return refuse(b); }

    char *cell = NULL;
    size_t cell_cap = 0;
    int r = row, c = column, problems = 0;
    char first_problem[sizeof s_error] = "";
    const char *p = text;
    for (;;) {
        const char *start = p;
        while (*p && *p != '\t' && *p != '\n') p++;
        size_t n = (size_t)(p - start);
        if (n > 0 && start[n - 1] == '\r' && (*p == '\n' || *p == '\0')) n--;   /* CRLF */
        if (n > 0) {
            int ok = 1;
            double number;
            if (!cell_in(r, c)) {
                ok = fail("the table runs past the edge of the sheet (row %d, column %d)", r, c);
            } else if (how >= 1 && grid_number(start, n, &number)) {
                ok = lxw_ok(worksheet_write_number(s->ws, (lxw_row_t)(r - 1), (lxw_col_t)(c - 1), number, fmt));
            } else {
                if (n + 1 > cell_cap) {
                    size_t cap = cell_cap ? cell_cap : 256;
                    while (cap < n + 1) cap *= 2;
                    char *grown = (char *)realloc(cell, cap);
                    if (!grown) { free(cell); fail("out of memory"); return refuse(b); }
                    cell = grown;
                    cell_cap = cap;
                }
                for (size_t i = 0; i < n; i++) cell[i] = (start[i] == '\v') ? '\n' : start[i];
                cell[n] = '\0';
                if (how == 2 && cell[0] == '=' && n > 1) {
                    ok = formula_ok(cell)
                         && lxw_ok(worksheet_write_formula(s->ws, (lxw_row_t)(r - 1), (lxw_col_t)(c - 1), cell, fmt));
                } else {
                    ok = cell_text_ok(cell) && write_string(s, r, c, cell, fmt);
                }
            }
            if (ok) {
                written++;
            } else {
                if (!problems) snprintf(first_problem, sizeof first_problem, "%.250s (row %d, column %d)", s_error, r, c);
                problems++;
                refuse(b);
            }
        }
        if (*p == '\t') { c++; p++; }
        else if (*p == '\n') { r++; c = column; p++; }
        else break;
    }
    free(cell);
    if (problems) memcpy(s_error, first_problem, sizeof s_error); else ok_clear();
    return written;
}

/* ------------------------------------------------------------------ */
/* Sheets: layout                                                      */
/* ------------------------------------------------------------------ */
/* Width in Excel's column units (about one digit of the default font each;
 * the default is 8.43), 0 to 255. `format` (or 0) becomes the columns'
 * default format. */
LC_API void xlx_sheet_set_columns(int sheet, int first_column, int last_column, double width, int format)
{
    SHEET_OR_RETURN()
    lxw_format *fmt = NULL;
    if (first_column < 1 || last_column > XLX_MAX_COL || first_column > last_column) {
        fail("not a run of columns: 1 to %d, first before last", XLX_MAX_COL);
        refuse(b);
        return;
    }
    if (!(width >= 0 && width <= 255)) { fail("a column width is 0 to 255"); refuse(b); return; }
    if (!cell_format(format, s->book, &fmt)) { refuse(b); return; }
    if (!lxw_ok(worksheet_set_column(s->ws, (lxw_col_t)(first_column - 1), (lxw_col_t)(last_column - 1), width, fmt)))
        refuse(b);
}

LC_API void xlx_sheet_hide_columns(int sheet, int first_column, int last_column)
{
    lxw_row_col_options options;
    SHEET_OR_RETURN()
    if (first_column < 1 || last_column > XLX_MAX_COL || first_column > last_column) {
        fail("not a run of columns: 1 to %d, first before last", XLX_MAX_COL);
        refuse(b);
        return;
    }
    memset(&options, 0, sizeof options);
    options.hidden = LXW_TRUE;
    if (!lxw_ok(worksheet_set_column_opt(s->ws, (lxw_col_t)(first_column - 1), (lxw_col_t)(last_column - 1),
                                         LXW_DEF_COL_WIDTH, NULL, &options)))
        refuse(b);
}

/* Height in points (the default is 15), 0 to 409. */
LC_API void xlx_sheet_set_row(int sheet, int row, double height, int format)
{
    SHEET_OR_RETURN()
    lxw_format *fmt = NULL;
    if (row < 1 || row > XLX_MAX_ROW) { fail("a row is 1 to %d", XLX_MAX_ROW); refuse(b); return; }
    if (!(height >= 0 && height <= 409)) { fail("a row height is 0 to 409 points"); refuse(b); return; }
    if (!cell_format(format, s->book, &fmt)) { refuse(b); return; }
    if (!lxw_ok(worksheet_set_row(s->ws, ROW0, height, fmt))) refuse(b);
}

LC_API void xlx_sheet_hide_row(int sheet, int row)
{
    lxw_row_col_options options;
    SHEET_OR_RETURN()
    if (row < 1 || row > XLX_MAX_ROW) { fail("a row is 1 to %d", XLX_MAX_ROW); refuse(b); return; }
    memset(&options, 0, sizeof options);
    options.hidden = LXW_TRUE;
    if (!lxw_ok(worksheet_set_row_opt(s->ws, ROW0, LXW_DEF_ROW_HEIGHT, NULL, &options))) refuse(b);
}

/* One cell out of a block of at least two, holding `text`. */
LC_API void xlx_sheet_merge(int sheet, int first_row, int first_column, int last_row, int last_column,
                            const char *text, int format)
{
    SHEET_OR_RETURN()
    lxw_format *fmt = NULL;
    if (!range_in(first_row, first_column, last_row, last_column)
        || (first_row == last_row && first_column == last_column)) {
        fail("not a block of two or more cells inside the grid");
        refuse(b);
        return;
    }
    if (!text) text = "";
    if (!cell_text_ok(text)) { refuse(b); return; }
    if (!cell_format(format, s->book, &fmt)) { refuse(b); return; }
    char *owned = NULL;
    const char *literal = literal_text(text, &owned);
    if (!literal) { refuse(b); return; }
    if (!lxw_ok(worksheet_merge_range(s->ws, (lxw_row_t)(first_row - 1), (lxw_col_t)(first_column - 1),
                                      (lxw_row_t)(last_row - 1), (lxw_col_t)(last_column - 1), literal, fmt)))
        refuse(b);
    free(owned);
}

/* Keeps the first `rows` rows and the first `columns` columns in view while
 * the rest scrolls. 1, 0 freezes a header row. */
LC_API void xlx_sheet_freeze(int sheet, int rows, int columns)
{
    SHEET_OR_RETURN()
    if (rows < 0 || rows >= XLX_MAX_ROW || columns < 0 || columns >= XLX_MAX_COL) {
        fail("rows and columns to freeze are counts from 0");
        refuse(b);
        return;
    }
    worksheet_freeze_panes(s->ws, (lxw_row_t)rows, (lxw_col_t)columns);
}

LC_API void xlx_sheet_autofilter(int sheet, int first_row, int first_column, int last_row, int last_column)
{
    SHEET_OR_RETURN()
    if (!range_in(first_row, first_column, last_row, last_column)) { fail("not a range inside the grid"); refuse(b); return; }
    if (!lxw_ok(worksheet_autofilter(s->ws, (lxw_row_t)(first_row - 1), (lxw_col_t)(first_column - 1),
                                     (lxw_row_t)(last_row - 1), (lxw_col_t)(last_column - 1))))
        refuse(b);
}

/* A drop-down list in every cell of the range. `items` is comma-separated,
 * as Excel itself stores it, at most 255 characters in all. */
LC_API void xlx_sheet_validate_list(int sheet, int first_row, int first_column, int last_row, int last_column,
                                    const char *items)
{
    SHEET_OR_RETURN()
    if (!range_in(first_row, first_column, last_row, last_column)) { fail("not a range inside the grid"); refuse(b); return; }
    if (!name_ok(items, 255) || !*items) { fail("the list is empty, longer than 255 bytes or not valid text"); refuse(b); return; }
    char *copy = copy_text(items);
    size_t count = 1;
    for (const char *p = items; *p; p++) if (*p == ',') count++;
    const char **list = (const char **)calloc(count + 1, sizeof *list);
    if (!copy || !list) { free(copy); free((void *)list); fail("out of memory"); refuse(b); return; }
    size_t n = 0;
    char *item = copy;
    for (char *p = copy;; p++) {
        if (*p == ',' || *p == '\0') {
            int last = *p == '\0';
            *p = '\0';
            while (*item == ' ') item++;
            if (*item) list[n++] = item;
            item = p + 1;
            if (last) break;
        }
    }
    if (n == 0) {
        fail("the list has no items");
        refuse(b);
    } else {
        lxw_data_validation validation;
        memset(&validation, 0, sizeof validation);
        validation.validate = LXW_VALIDATION_TYPE_LIST;
        validation.value_list = list;
        if (!lxw_ok(worksheet_data_validation_range(s->ws, (lxw_row_t)(first_row - 1), (lxw_col_t)(first_column - 1),
                                                    (lxw_row_t)(last_row - 1), (lxw_col_t)(last_column - 1),
                                                    &validation)))
            refuse(b);
    }
    free((void *)list);
    free(copy);
}

/* A picture file (PNG, JPEG, GIF or BMP) with its top left corner on a
 * cell. The file is read again when the workbook is closed, so it must
 * still be there then. */
LC_API void xlx_sheet_insert_image(int sheet, int row, int column, const char *path, double x_scale, double y_scale)
{
    lxw_image_options options;
    SHEET_OR_RETURN()
    if (!cell_in(row, column)) { fail("no such cell: a row is 1 to %d and a column 1 to %d", XLX_MAX_ROW, XLX_MAX_COL); refuse(b); return; }
    if (!name_ok(path, XLX_MAX_PATH) || !*path) { fail("the picture path is empty, too long or not valid text"); refuse(b); return; }
    if (!(x_scale > 0 && x_scale <= 100) || !(y_scale > 0 && y_scale <= 100)) { fail("a scale is above 0, up to 100 (1 is full size)"); refuse(b); return; }
    FILE *probe = open_utf8(path, "rb");
    if (!probe) { fail("the picture file cannot be opened"); refuse(b); return; }
    fclose(probe);
    memset(&options, 0, sizeof options);
    options.x_scale = x_scale;
    options.y_scale = y_scale;
    if (!lxw_ok(worksheet_insert_image_opt(s->ws, ROW0, COL0, path, &options))) refuse(b);
}

/* ------------------------------------------------------------------ */
/* Sheets: the page and the view                                       */
/* ------------------------------------------------------------------ */
LC_API void xlx_sheet_set_landscape(int sheet, int flag)
{
    SHEET_OR_RETURN()
    if (flag) worksheet_set_landscape(s->ws); else worksheet_set_portrait(s->ws);
}

/* Excel's paper index: 1 Letter, 5 Legal, 8 A3, 9 A4, 11 A5 (0 = the
 * printer's default). */
LC_API void xlx_sheet_set_paper(int sheet, int paper)
{
    SHEET_OR_RETURN()
    if (paper < 0 || paper > 118) { fail("a paper index is 0 to 118 (1 Letter, 9 A4)"); refuse(b); return; }
    worksheet_set_paper(s->ws, (uint8_t)paper);
}

/* Inches. */
LC_API void xlx_sheet_set_margins(int sheet, double left, double right, double top, double bottom)
{
    SHEET_OR_RETURN()
    if (!(left >= 0 && left <= 50) || !(right >= 0 && right <= 50) || !(top >= 0 && top <= 50)
        || !(bottom >= 0 && bottom <= 50)) {
        fail("a margin is 0 to 50 inches");
        refuse(b);
        return;
    }
    worksheet_set_margins(s->ws, left, right, top, bottom);
}

/* Shrinks the print to this many pages across and down; 0 for "as many as
 * it takes" in that direction. */
LC_API void xlx_sheet_fit_to_pages(int sheet, int wide, int tall)
{
    SHEET_OR_RETURN()
    if (wide < 0 || wide > 32767 || tall < 0 || tall > 32767) { fail("a page count is 0 to 32767"); refuse(b); return; }
    worksheet_fit_to_pages(s->ws, (uint16_t)wide, (uint16_t)tall);
}

/* Excel's header codes: &L &C &R for the three parts, &P the page number,
 * &N the page count, &D the date, &F the file name, &A the sheet name. */
LC_API void xlx_sheet_set_header(int sheet, const char *text)
{
    SHEET_OR_RETURN()
    if (!body_ok(text, LXW_HEADER_FOOTER_MAX)) { fail("the header is longer than %d bytes or not valid text", LXW_HEADER_FOOTER_MAX); refuse(b); return; }
    if (!lxw_ok(worksheet_set_header(s->ws, text))) refuse(b);
}

LC_API void xlx_sheet_set_footer(int sheet, const char *text)
{
    SHEET_OR_RETURN()
    if (!body_ok(text, LXW_HEADER_FOOTER_MAX)) { fail("the footer is longer than %d bytes or not valid text", LXW_HEADER_FOOTER_MAX); refuse(b); return; }
    if (!lxw_ok(worksheet_set_footer(s->ws, text))) refuse(b);
}

LC_API void xlx_sheet_repeat_rows(int sheet, int first_row, int last_row)
{
    SHEET_OR_RETURN()
    if (first_row < 1 || last_row > XLX_MAX_ROW || first_row > last_row) { fail("not a run of rows: 1 to %d, first before last", XLX_MAX_ROW); refuse(b); return; }
    if (!lxw_ok(worksheet_repeat_rows(s->ws, (lxw_row_t)(first_row - 1), (lxw_row_t)(last_row - 1)))) refuse(b);
}

LC_API void xlx_sheet_print_area(int sheet, int first_row, int first_column, int last_row, int last_column)
{
    SHEET_OR_RETURN()
    if (!range_in(first_row, first_column, last_row, last_column)) { fail("not a range inside the grid"); refuse(b); return; }
    if (!lxw_ok(worksheet_print_area(s->ws, (lxw_row_t)(first_row - 1), (lxw_col_t)(first_column - 1),
                                     (lxw_row_t)(last_row - 1), (lxw_col_t)(last_column - 1))))
        refuse(b);
}

LC_API void xlx_sheet_set_zoom(int sheet, int percent)
{
    SHEET_OR_RETURN()
    if (percent < 10 || percent > 400) { fail("a zoom is 10 to 400 percent"); refuse(b); return; }
    worksheet_set_zoom(s->ws, (uint16_t)percent);
}

LC_API void xlx_sheet_show_gridlines(int sheet, int screen_flag, int print_flag)
{
    SHEET_OR_RETURN()
    worksheet_gridlines(s->ws, (uint8_t)((screen_flag ? LXW_SHOW_SCREEN_GRIDLINES : 0)
                                         | (print_flag ? LXW_SHOW_PRINT_GRIDLINES : 0)));
}

LC_API void xlx_sheet_set_tab_color(int sheet, const char *color)
{
    lxw_color_t value;
    SHEET_OR_RETURN()
    if (!color_in(color, &value)) { fail("not a colour: #RRGGBB, r,g,b or a basic colour name"); refuse(b); return; }
    worksheet_set_tab_color(s->ws, value);
}

/* The sheet shown when the file opens. */
LC_API void xlx_sheet_activate(int sheet)
{
    SHEET_OR_RETURN()
    worksheet_activate(s->ws);
}

LC_API void xlx_sheet_hide(int sheet)
{
    SHEET_OR_RETURN()
    worksheet_hide(s->ws);
}

/* Stops edits to locked cells (every cell, unless its format says
 * otherwise). The password, if any, keeps honest people honest and nothing
 * more: Excel's sheet protection is not encryption. */
LC_API void xlx_sheet_protect(int sheet, const char *password)
{
    SHEET_OR_RETURN()
    if (!password) password = "";
    if (!name_ok(password, XLX_MAX_NAME)) { fail("the password is longer than %d bytes or not valid text", XLX_MAX_NAME); refuse(b); return; }
    worksheet_protect(s->ws, *password ? password : NULL, NULL);
}

/* ------------------------------------------------------------------ */
/* Charts                                                              */
/* ------------------------------------------------------------------ */
#define CHART_OR_RETURN(RET)                                                  \
    xlx_book *b = NULL;                                                       \
    ok_clear();                                                               \
    xlx_chart *c = chart_in(chart, &b);                                       \
    if (!c) return RET;

#define SERIES_OR_RETURN                                                      \
    CHART_OR_RETURN()                                                         \
    if (series < 1 || series > c->series_count) {                             \
        fail("no such series: this chart has %d", c->series_count);           \
        refuse(b);                                                            \
        return;                                                               \
    }                                                                         \
    lxw_chart_series *ser = c->series[series - 1];

LC_API int xlx_chart_is_valid(int chart)
{
    int slot = charts_slot_of(chart);
    return slot >= 0 && book_of(charts_arr[slot]->book) != NULL;
}

LC_API int xlx_chart_series_count(int chart)
{
    int slot = charts_slot_of(chart);
    return slot >= 0 && book_of(charts_arr[slot]->book) ? charts_arr[slot]->series_count : 0;
}

/* A range formula such as "=Sheet1!$B$2:$B$7" (xlx_range_formula writes
 * one): an = sign, a sheet name, an exclamation mark and a range of cells.
 * libxlsxwriter reads these apart again when the workbook is closed and
 * trusts their shape, so the shape is checked here. */
static int range_formula_ok(const char *formula)
{
    const char *p = formula, *end = NULL;
    int row, col, row2, col2;
    if (!name_ok(formula, XLX_MAX_FORMULA) || *p != '=') return 0;
    p++;
    if (*p == '\'') {
        p++;
        for (;;) {
            if (*p == '\0') return 0;
            if (*p == '\'') {
                if (p[1] == '\'') { p += 2; continue; }
                p++;
                break;
            }
            p++;
        }
    } else {
        const char *start = p;
        while (*p && *p != '!' && *p != '\'' && *p != ':' && *p != ',' && *p != ' ') p++;
        if (p == start) return 0;
    }
    if (*p != '!') return 0;
    p++;
    if (!cell_ref(p, &row, &col, &end)) return 0;
    if (*end == '\0') return 1;
    if (*end != ':') return 0;
    if (!cell_ref(end + 1, &row2, &col2, &end) || *end != '\0') return 0;
    return row <= row2 && col <= col2;
}

/* `categories` may be "" (a pie or column chart then numbers its points);
 * `values` is required. Returns the number of the series, from 1. */
LC_API int xlx_chart_add_series(int chart, const char *categories, const char *values)
{
    CHART_OR_RETURN(0)
    if (!categories) categories = "";
    if (*categories && !range_formula_ok(categories)) {
        fail("the categories are not a range formula such as =Sheet1!$A$2:$A$7");
        return refuse(b);
    }
    if (!values || !range_formula_ok(values)) {
        fail("the values are not a range formula such as =Sheet1!$B$2:$B$7");
        return refuse(b);
    }
    if (c->series_count >= 255) { fail("a chart holds at most 255 series"); return refuse(b); }
    if (!*categories && c->chart->chart_group == LXW_CHART_SCATTER) {
        fail("a scatter chart needs categories too: they are its x values");
        return refuse(b);
    }
    if (c->series_count >= c->series_cap) {
        int cap = c->series_cap ? c->series_cap * 2 : 8;
        lxw_chart_series **grown = (lxw_chart_series **)realloc(c->series, (size_t)cap * sizeof *grown);
        if (!grown) { fail("out of memory"); return refuse(b); }
        c->series = grown;
        c->series_cap = cap;
    }
    lxw_chart_series *ser = chart_add_series(c->chart, *categories ? categories : NULL, values);
    if (!ser) { fail("the series could not be added"); return refuse(b); }
    c->series[c->series_count++] = ser;
    return c->series_count;
}

/* libxlsxwriter's three title setters (chart, series, axis) store a copy of
 * the text and never let go of the one before, so setting a title twice
 * leaks the first (LeakSanitizer, in this member's first fuzz run). Each
 * call here clears the title first. A title is a plain text OR a cell
 * formula, and setting one kind drops the other. */
static void title_clear(lxw_chart_title *title)
{
    free(title->name);
    title->name = NULL;
    if (title->range) {
        free(title->range->formula);
        title->range->formula = NULL;
    }
}

LC_API void xlx_chart_series_set_name(int chart, int series, const char *name)
{
    SERIES_OR_RETURN
    if (!name_ok(name, XLX_MAX_NAME) || !*name) { fail("the name is empty, too long or not valid text"); refuse(b); return; }
    /* A name that begins with = is read by libxlsxwriter as a cell
     * reference, with the same trust as a range formula. */
    if (*name == '=' && !range_formula_ok(name)) { fail("a name that begins with = must be a cell formula such as =Sheet1!$B$1"); refuse(b); return; }
    title_clear(&ser->title);
    chart_series_set_name(ser, name);
}

/* The colour of the series: its bars' fill, or its line. */
LC_API void xlx_chart_series_set_color(int chart, int series, const char *color)
{
    lxw_color_t value;
    lxw_chart_fill fill;
    lxw_chart_line line;
    SERIES_OR_RETURN
    if (!color_in(color, &value)) { fail("not a colour: #RRGGBB, r,g,b or a basic colour name"); refuse(b); return; }
    memset(&fill, 0, sizeof fill);
    memset(&line, 0, sizeof line);
    fill.color = value;
    line.color = value;
    chart_series_set_fill(ser, &fill);
    chart_series_set_line(ser, &line);
}

/* Shows each point's value beside it. */
LC_API void xlx_chart_series_set_labels(int chart, int series, int flag)
{
    SERIES_OR_RETURN
    ser->has_labels = flag ? LXW_TRUE : LXW_FALSE;
    ser->show_labels_value = flag ? LXW_TRUE : LXW_FALSE;
}

LC_API void xlx_chart_series_set_smooth(int chart, int series, int flag)
{
    SERIES_OR_RETURN
    chart_series_set_smooth(ser, flag ? LXW_TRUE : LXW_FALSE);
}

LC_API void xlx_chart_series_set_marker(int chart, int series, const char *kind)
{
    static const xlx_choice kinds[] = {
        {"automatic", LXW_CHART_MARKER_AUTOMATIC}, {"none", LXW_CHART_MARKER_NONE},
        {"square", LXW_CHART_MARKER_SQUARE}, {"diamond", LXW_CHART_MARKER_DIAMOND},
        {"triangle", LXW_CHART_MARKER_TRIANGLE}, {"x", LXW_CHART_MARKER_X},
        {"star", LXW_CHART_MARKER_STAR}, {"circle", LXW_CHART_MARKER_CIRCLE},
        {"short dash", LXW_CHART_MARKER_SHORT_DASH}, {"long dash", LXW_CHART_MARKER_LONG_DASH},
        {NULL, 0}};
    int value = 0;
    SERIES_OR_RETURN
    if (!choose(kind, kinds, &value)) {
        fail("not a marker: automatic, none, square, diamond, triangle, x, star, circle, short dash, long dash");
        refuse(b);
        return;
    }
    chart_series_set_marker_type(ser, (uint8_t)value);
}

LC_API void xlx_chart_set_title(int chart, const char *title)
{
    CHART_OR_RETURN()
    if (!name_ok(title, XLX_MAX_NAME)) { fail("the title is too long or not valid text"); refuse(b); return; }
    if (*title == '=' && !range_formula_ok(title)) { fail("a title that begins with = must be a cell formula such as =Sheet1!$A$1"); refuse(b); return; }
    title_clear(&c->chart->title);
    /* "off" is a switch libxlsxwriter never turns back: a title set after
     * an empty one would otherwise stay hidden. */
    c->chart->title.off = *title ? LXW_FALSE : LXW_TRUE;
    if (*title) chart_title_set_name(c->chart, title);
}

/* "x" is the category axis (along the bottom of a column chart), "y" the
 * value axis. A pie chart has neither. */
static lxw_chart_axis *axis_in(xlx_chart *c, const char *axis)
{
    static const xlx_choice axes[] = {{"x", 0}, {"y", 1}, {NULL, 0}};
    int which = 0;
    if (!choose(axis, axes, &which)) { fail("not an axis: x or y"); return NULL; }
    return which == 0 ? c->chart->x_axis : c->chart->y_axis;
}

LC_API void xlx_chart_set_axis_title(int chart, const char *axis, const char *title)
{
    CHART_OR_RETURN()
    lxw_chart_axis *a = axis_in(c, axis);
    if (!a) { refuse(b); return; }
    if (!name_ok(title, XLX_MAX_NAME) || !*title) { fail("the title is empty, too long or not valid text"); refuse(b); return; }
    if (*title == '=' && !range_formula_ok(title)) { fail("a title that begins with = must be a cell formula such as =Sheet1!$A$1"); refuse(b); return; }
    title_clear(&a->title);
    chart_axis_set_name(a, title);
}

/* The lowest and highest value an axis shows. Only a value axis has them:
 * the y axis, and both axes of a scatter chart. */
LC_API void xlx_chart_set_axis_range(int chart, const char *axis, double minimum, double maximum)
{
    CHART_OR_RETURN()
    lxw_chart_axis *a = axis_in(c, axis);
    if (!a) { refuse(b); return; }
    if (!fin(minimum) || !fin(maximum) || !(minimum < maximum)) { fail("the minimum must be below the maximum"); refuse(b); return; }
    if (!a->is_value) { fail("that axis holds categories, not values, in this kind of chart"); refuse(b); return; }
    chart_axis_set_min(a, minimum);
    chart_axis_set_max(a, maximum);
}

LC_API void xlx_chart_set_axis_number_format(int chart, const char *axis, const char *code)
{
    CHART_OR_RETURN()
    lxw_chart_axis *a = axis_in(c, axis);
    if (!a) { refuse(b); return; }
    if (!name_ok(code, XLX_MAX_NAME) || !*code) { fail("the number format is empty, too long or not valid text"); refuse(b); return; }
    chart_axis_set_num_format(a, code);
}

LC_API void xlx_chart_set_axis_gridlines(int chart, const char *axis, int flag)
{
    CHART_OR_RETURN()
    lxw_chart_axis *a = axis_in(c, axis);
    if (!a) { refuse(b); return; }
    chart_axis_major_gridlines_set_visible(a, flag ? LXW_TRUE : LXW_FALSE);
}

LC_API void xlx_chart_set_legend(int chart, const char *position)
{
    static const xlx_choice positions[] = {
        {"none", LXW_CHART_LEGEND_NONE}, {"right", LXW_CHART_LEGEND_RIGHT}, {"left", LXW_CHART_LEGEND_LEFT},
        {"top", LXW_CHART_LEGEND_TOP}, {"bottom", LXW_CHART_LEGEND_BOTTOM},
        {"top right", LXW_CHART_LEGEND_TOP_RIGHT}, {NULL, 0}};
    int value = 0;
    CHART_OR_RETURN()
    if (!choose(position, positions, &value)) { fail("not a legend position: none, right, left, top, bottom, top right"); refuse(b); return; }
    chart_legend_set_position(c->chart, (uint8_t)value);
}

/* One of Excel's 48 built-in chart styles. */
LC_API void xlx_chart_set_style(int chart, int style)
{
    CHART_OR_RETURN()
    if (style < 1 || style > 48) { fail("a chart style is 1 to 48"); refuse(b); return; }
    chart_set_style(c->chart, (uint8_t)style);
}

/* Puts the chart on a sheet, its top left corner on a cell. A chart goes on
 * one sheet, once, and needs at least one series first. */
LC_API void xlx_sheet_insert_chart(int sheet, int row, int column, int chart, double x_scale, double y_scale)
{
    lxw_chart_options options;
    SHEET_OR_RETURN()
    if (!cell_in(row, column)) { fail("no such cell: a row is 1 to %d and a column 1 to %d", XLX_MAX_ROW, XLX_MAX_COL); refuse(b); return; }
    int slot = charts_slot_of(chart);
    if (slot < 0) { fail("not a chart (handle %d)", chart); refuse(b); return; }
    xlx_chart *c = charts_arr[slot];
    if (c->book != s->book) { fail("that chart belongs to another workbook"); refuse(b); return; }
    if (c->inserted) { fail("that chart is already on a sheet; make another for a second copy"); refuse(b); return; }
    if (c->series_count == 0) { fail("the chart has no series yet"); refuse(b); return; }
    if (!(x_scale > 0 && x_scale <= 100) || !(y_scale > 0 && y_scale <= 100)) { fail("a scale is above 0, up to 100 (1 is full size)"); refuse(b); return; }
    memset(&options, 0, sizeof options);
    options.x_scale = x_scale;
    options.y_scale = y_scale;
    if (!lxw_ok(worksheet_insert_chart_opt(s->ws, ROW0, COL0, c->chart, &options))) { refuse(b); return; }
    c->inserted = 1;
}

/* ================================================================== */
/*                               READING                              */
/* ================================================================== */
/*
 * A .xlsx is a zip. Inside, "_rels/.rels" names the workbook part (nearly
 * always xl/workbook.xml), the workbook lists its sheets by name and by a
 * relationship id, and the workbook's own .rels file turns each id into the
 * part that holds the sheet. Text that many cells share lives once in the
 * shared-strings part; whether a number is a DATE is a property of the
 * cell's style, in the styles part.
 *
 * Opening a file reads the workbook and its relationships: enough to list
 * the sheets. A sheet's cells are read when first asked for, and ONE sheet
 * is held at a time (asking for another lets the first go), so a workbook
 * of fifty sheets costs the memory of its largest.
 */

enum { XR_EMPTY = 0, XR_NUMBER, XR_TEXT, XR_SHARED, XR_BOOL, XR_ERROR };

typedef struct {
    uint32_t style;                       /* index into the file's cell formats   */
    uint16_t col;                         /* 1-based                              */
    uint8_t  kind;
    uint8_t  unused;
    uint32_t formula;                     /* offset in the sheet pool, 0 = none   */
    union { double number; uint32_t text; } v;   /* pool offset or string index  */
} xr_cell;

typedef struct { xr_cell *cells; uint32_t count, cap; } xr_row;
typedef struct { char *name; char *part; int hidden; } xr_sheet;
typedef struct { uint32_t id; char *code; } xr_numfmt;

typedef struct xlx_reader {
    FILE *fp;
    unzFile zip;
    xr_sheet *sheets;
    int sheet_count;
    char *strings_part, *styles_part;
    int date1904;

    int strings_state;                    /* 0 not read, 1 read, -1 unreadable    */
    char *sst_pool;
    size_t sst_len, sst_cap;
    uint32_t *sst_off;
    uint32_t sst_count, sst_offcap;

    int styles_state;
    uint32_t *xf_numfmt;
    uint32_t xf_count, xf_cap;
    xr_numfmt *numfmts;
    uint32_t numfmt_count, numfmt_cap;

    int loaded;                           /* the sheet held, 0 = none             */
    int failed;                           /* the sheet that would not load, 0 = none */
    char failed_error[sizeof s_error];    /* and why                              */
    xr_row *rows;
    uint32_t row_cap, max_row, max_col, cell_total;
    char *pool;
    size_t pool_len, pool_cap;
    char *merged;
    size_t merged_len, merged_cap;
} xlx_reader;

DEFINE_TABLE(readers, xlx_reader *, 5)

/* ---- small growable things -------------------------------------- */
static int buf_add(char **buf, size_t *len, size_t *cap, const char *bytes, size_t n, size_t limit)
{
    if (n > limit || *len > limit - n) return 0;
    if (*len + n + 1 > *cap) {
        size_t grown_cap = *cap ? *cap : 256;
        while (grown_cap < *len + n + 1) grown_cap *= 2;
        char *grown = (char *)realloc(*buf, grown_cap);
        if (!grown) return 0;
        *buf = grown;
        *cap = grown_cap;
    }
    if (n) memcpy(*buf + *len, bytes, n);
    *len += n;
    (*buf)[*len] = '\0';
    return 1;
}

/* ---- the zip, through our own file callbacks --------------------- */
/* minizip is handed a FILE this file opened (so the path can be UTF-8 on
 * Windows) and never opens or closes one itself. */
static voidpf ZCALLBACK xr_zopen(voidpf opaque, const void *filename, int mode)
{
    (void)filename; (void)mode;
    return opaque;
}
static uLong ZCALLBACK xr_zread(voidpf opaque, voidpf stream, void *buf, uLong size)
{
    (void)opaque;
    return (uLong)fread(buf, 1, (size_t)size, (FILE *)stream);
}
static uLong ZCALLBACK xr_zwrite(voidpf opaque, voidpf stream, const void *buf, uLong size)
{
    (void)opaque; (void)stream; (void)buf; (void)size;
    return 0;
}
static ZPOS64_T ZCALLBACK xr_ztell(voidpf opaque, voidpf stream)
{
    (void)opaque;
#if defined(_WIN32)
    return (ZPOS64_T)_ftelli64((FILE *)stream);
#else
    return (ZPOS64_T)ftello((FILE *)stream);
#endif
}
static long ZCALLBACK xr_zseek(voidpf opaque, voidpf stream, ZPOS64_T offset, int origin)
{
    int whence = origin == ZLIB_FILEFUNC_SEEK_CUR ? SEEK_CUR : origin == ZLIB_FILEFUNC_SEEK_END ? SEEK_END : SEEK_SET;
    (void)opaque;
#if defined(_WIN32)
    return _fseeki64((FILE *)stream, (__int64)offset, whence) == 0 ? 0 : -1;
#else
    if (offset > (ZPOS64_T)(((uint64_t)1 << (sizeof(off_t) * 8 - 1)) - 1)) return -1;
    return fseeko((FILE *)stream, (off_t)offset, whence) == 0 ? 0 : -1;
#endif
}
static int ZCALLBACK xr_zclose(voidpf opaque, voidpf stream)
{
    (void)opaque; (void)stream;
    return 0;
}
static int ZCALLBACK xr_zerror(voidpf opaque, voidpf stream)
{
    (void)opaque;
    return ferror((FILE *)stream);
}

/* ---- parsing one part -------------------------------------------- */
typedef struct { char *id, *type, *target; } xr_rel;

typedef struct xr_ctx {
    xlx_reader *R;
    XML_Parser parser;
    int failed;

    char *acc;                            /* a cell's value, a string's text      */
    size_t acc_len, acc_cap;
    char *facc;                           /* a cell's formula                     */
    size_t facc_len, facc_cap;
    int collect;                          /* 0 no, 1 into acc, 2 into facc        */

    /* relationships */
    xr_rel *rels;
    int rel_count, rel_cap;

    /* workbook */
    char **rids;                          /* one per sheet, beside R->sheets      */

    /* shared strings, styles, sheet */
    int in_si, in_rph, in_cellxfs;
    int in_c, in_is, have_v, have_f;
    uint32_t cur_row, cur_col, cur_style;
    char cur_type[12];
} xr_ctx;

static void xr_stop(xr_ctx *ctx, const char *format, ...)
{
    if (!ctx->failed) {
        va_list ap;
        va_start(ap, format);
        vsnprintf(s_error, sizeof s_error, format, ap);
        va_end(ap);
        ctx->failed = 1;
    }
    XML_StopParser(ctx->parser, XML_FALSE);
}

static void xr_ctx_free(xr_ctx *ctx)
{
    free(ctx->acc);
    free(ctx->facc);
    for (int i = 0; i < ctx->rel_count; i++) {
        free(ctx->rels[i].id);
        free(ctx->rels[i].type);
        free(ctx->rels[i].target);
    }
    free(ctx->rels);
    if (ctx->rids) {
        for (int i = 0; i < ctx->R->sheet_count; i++) free(ctx->rids[i]);
        free(ctx->rids);
    }
}

/* An element or attribute name without its namespace prefix: files written
 * by some tools say <x:row> where Excel says <row>. */
static const char *local_name(const char *name)
{
    const char *colon = strrchr(name, ':');
    return colon ? colon + 1 : name;
}

static const char *attr(const char **atts, const char *name)
{
    for (; atts && atts[0]; atts += 2)
        if (strcmp(atts[0], name) == 0) return atts[1];
    return NULL;
}

/* The relationship id of a <sheet>: an attribute "id" WITH a prefix
 * (r:id), as distinct from a plain "id". */
static const char *attr_rid(const char **atts)
{
    for (; atts && atts[0]; atts += 2) {
        const char *colon = strrchr(atts[0], ':');
        if (colon && strcmp(colon + 1, "id") == 0) return atts[1];
    }
    return NULL;
}

static int truthy(const char *v)
{
    return v && (strcmp(v, "1") == 0 || strcmp(v, "true") == 0 || strcmp(v, "on") == 0);
}

static int uint_in(const char *s, uint32_t limit, uint32_t *out)
{
    uint64_t v = 0;
    if (!s || !*s) return 0;
    for (; *s; s++) {
        if (*s < '0' || *s > '9') return 0;
        v = v * 10 + (uint64_t)(*s - '0');
        if (v > limit) return 0;
    }
    *out = (uint32_t)v;
    return 1;
}

static void XMLCALL xr_chars(void *ud, const XML_Char *s, int len)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    if (ctx->collect == 1) {
        if (!buf_add(&ctx->acc, &ctx->acc_len, &ctx->acc_cap, s, (size_t)len, XLX_MAX_VALUE_TEXT))
            xr_stop(ctx, "a cell or string holds more text than this library reads (%u MB), or memory ran out",
                    (unsigned)(XLX_MAX_VALUE_TEXT >> 20));
    } else if (ctx->collect == 2) {
        if (!buf_add(&ctx->facc, &ctx->facc_len, &ctx->facc_cap, s, (size_t)len, XLX_MAX_VALUE_TEXT))
            xr_stop(ctx, "a formula is larger than this library reads, or memory ran out");
    }
}

static void XMLCALL xr_doctype(void *ud, const XML_Char *name, const XML_Char *sysid, const XML_Char *pubid,
                               int has_internal_subset)
{
    (void)name; (void)sysid; (void)pubid; (void)has_internal_subset;
    xr_stop((xr_ctx *)ud, "a part of the file declares a DOCTYPE, which a spreadsheet may not");
}

/* 1 parsed, 0 refused (the error is set), -1 the part is not in the file. */
static int xr_parse(xlx_reader *R, const char *part, xr_ctx *ctx, XML_StartElementHandler start,
                    XML_EndElementHandler end)
{
    unz_file_info64 info;
    if (unzLocateFile(R->zip, part, 2) != UNZ_OK) return -1;
    if (unzGetCurrentFileInfo64(R->zip, &info, NULL, 0, NULL, 0, NULL, 0) != UNZ_OK)
        return fail("the file's zip directory is damaged (%s)", part);
    if (info.uncompressed_size > XLX_MAX_PART_BYTES)
        return fail("%.200s is larger than this library reads (%u MB)", part, (unsigned)(XLX_MAX_PART_BYTES >> 20));
    if (unzOpenCurrentFile(R->zip) != UNZ_OK)
        return fail("%.200s cannot be decompressed (encrypted, or a method other than deflate)", part);

    ctx->R = R;
    ctx->parser = XML_ParserCreate(NULL);
    if (!ctx->parser) { unzCloseCurrentFile(R->zip); return fail("out of memory"); }
    XML_SetUserData(ctx->parser, ctx);
    XML_SetElementHandler(ctx->parser, start, end);
    XML_SetCharacterDataHandler(ctx->parser, xr_chars);
    XML_SetStartDoctypeDeclHandler(ctx->parser, xr_doctype);

    uint64_t total = 0;
    int ok = 1;
    for (;;) {
        void *buffer = XML_GetBuffer(ctx->parser, 65536);
        if (!buffer) { ok = fail("out of memory"); break; }
        int n = unzReadCurrentFile(R->zip, buffer, 65536);
        if (n < 0) { ok = fail("%.200s is damaged (its compressed data does not decode)", part); break; }
        total += (uint64_t)n;
        if (total > XLX_MAX_PART_BYTES) {
            ok = fail("%.200s is larger than this library reads (%u MB)", part, (unsigned)(XLX_MAX_PART_BYTES >> 20));
            break;
        }
        if (XML_ParseBuffer(ctx->parser, n, n == 0) != XML_STATUS_OK) {
            if (!ctx->failed)
                fail("%.160s is not well-formed XML (line %lu: %.60s)", part,
                     (unsigned long)XML_GetCurrentLineNumber64(ctx->parser),
                     XML_ErrorString(XML_GetErrorCode(ctx->parser)));
            ok = 0;
            break;
        }
        if (n == 0) break;
    }
    XML_ParserFree(ctx->parser);
    ctx->parser = NULL;
    int closed = unzCloseCurrentFile(R->zip);
    if (ok && closed == UNZ_CRCERROR) ok = fail("%.200s is damaged (its checksum does not match)", part);
    return ok;
}

/* ---- relationships ------------------------------------------------ */
static void XMLCALL rels_start(void *ud, const XML_Char *name, const XML_Char **atts)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    if (strcmp(local_name(name), "Relationship") != 0) return;
    const char *id = attr(atts, "Id"), *type = attr(atts, "Type"), *target = attr(atts, "Target");
    const char *mode = attr(atts, "TargetMode");
    if (!id || !type || !target || (mode && strcmp(mode, "External") == 0)) return;
    if (strlen(target) > XLX_MAX_PATH || strlen(id) > XLX_MAX_NAME) return;
    if (ctx->rel_count >= 100000) { xr_stop(ctx, "the file lists too many relationships"); return; }
    if (ctx->rel_count >= ctx->rel_cap) {
        int cap = ctx->rel_cap ? ctx->rel_cap * 2 : 16;
        xr_rel *grown = (xr_rel *)realloc(ctx->rels, (size_t)cap * sizeof *grown);
        if (!grown) { xr_stop(ctx, "out of memory"); return; }
        ctx->rels = grown;
        ctx->rel_cap = cap;
    }
    xr_rel *rel = &ctx->rels[ctx->rel_count];
    rel->id = copy_text(id);
    rel->type = copy_text(type);
    rel->target = copy_text(target);
    ctx->rel_count++;
    if (!rel->id || !rel->type || !rel->target) xr_stop(ctx, "out of memory");
}

static void XMLCALL no_end(void *ud, const XML_Char *name)
{
    (void)ud; (void)name;
}

static int ends_with(const char *s, const char *tail)
{
    size_t n = strlen(s), m = strlen(tail);
    return n >= m && strcmp(s + n - m, tail) == 0;
}

/* The part a relationship target names, from the folder of the part that
 * holds the relationship: "worksheets/sheet1.xml" from "xl/" is
 * "xl/worksheets/sheet1.xml"; a leading "/" starts from the root; "../"
 * climbs. NULL if it would climb out of the file. */
static char *resolve_part(const char *base_dir, const char *target)
{
    size_t n = strlen(base_dir) + strlen(target) + 2;
    char *joined = (char *)malloc(n), *out = (char *)malloc(n);
    if (!joined || !out) { free(joined); free(out); return NULL; }
    if (target[0] == '/') snprintf(joined, n, "%s", target + 1);
    else snprintf(joined, n, "%s%s", base_dir, target);
    size_t len = 0;
    const char *p = joined;
    while (*p) {
        const char *slash = strchr(p, '/');
        size_t seg = slash ? (size_t)(slash - p) : strlen(p);
        if (seg == 2 && p[0] == '.' && p[1] == '.') {
            if (len == 0) { free(joined); free(out); return NULL; }
            len--;                                        /* the trailing '/' */
            while (len > 0 && out[len - 1] != '/') len--;
        } else if (!(seg == 1 && p[0] == '.') && seg > 0) {
            memcpy(out + len, p, seg);
            len += seg;
            if (slash) out[len++] = '/';
        }
        p += seg + (slash ? 1 : 0);
    }
    out[len] = '\0';
    free(joined);
    return out;
}

/* "xl/workbook.xml" -> folder "xl/" and rels part "xl/_rels/workbook.xml.rels". */
static int part_neighbours(const char *part, char **dir, char **rels)
{
    const char *slash = strrchr(part, '/');
    size_t dir_len = slash ? (size_t)(slash - part) + 1 : 0;
    const char *base = part + dir_len;
    size_t n = strlen(part) + 16;
    *dir = (char *)malloc(dir_len + 1);
    *rels = (char *)malloc(n);
    if (!*dir || !*rels) { free(*dir); free(*rels); *dir = *rels = NULL; return 0; }
    memcpy(*dir, part, dir_len);
    (*dir)[dir_len] = '\0';
    snprintf(*rels, n, "%s_rels/%s.rels", *dir, base);
    return 1;
}

/* ---- the workbook -------------------------------------------------- */
static void XMLCALL workbook_start(void *ud, const XML_Char *name, const XML_Char **atts)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    xlx_reader *R = ctx->R;
    const char *element = local_name(name);
    if (strcmp(element, "workbookPr") == 0) {
        R->date1904 = truthy(attr(atts, "date1904"));
    } else if (strcmp(element, "sheet") == 0) {
        const char *sheet_name = attr(atts, "name"), *rid = attr_rid(atts), *state = attr(atts, "state");
        if (!sheet_name || !rid || strlen(rid) > XLX_MAX_NAME) return;
        if (strlen(sheet_name) > XLX_MAX_NAME) { xr_stop(ctx, "a sheet name is longer than a sheet name can be"); return; }
        if (R->sheet_count >= XLX_MAX_SHEETS) { xr_stop(ctx, "the file has more than %d sheets", XLX_MAX_SHEETS); return; }
        xr_sheet *sheets = (xr_sheet *)realloc(R->sheets, (size_t)(R->sheet_count + 1) * sizeof *sheets);
        if (sheets) R->sheets = sheets;
        char **rids = (char **)realloc(ctx->rids, (size_t)(R->sheet_count + 1) * sizeof *rids);
        if (rids) ctx->rids = rids;
        if (!sheets || !rids) { xr_stop(ctx, "out of memory"); return; }
        xr_sheet *sheet = &R->sheets[R->sheet_count];
        sheet->name = copy_text(sheet_name);
        sheet->part = NULL;
        sheet->hidden = state && strcmp(state, "visible") != 0;
        ctx->rids[R->sheet_count] = copy_text(rid);
        R->sheet_count++;
        if (!sheet->name || !ctx->rids[R->sheet_count - 1]) xr_stop(ctx, "out of memory");
    }
}

/* ---- "_xHHHH_": how a file writes a character XML cannot hold ----- */
static int hex4(const char *p, unsigned *out)
{
    unsigned v = 0;
    for (int i = 0; i < 4; i++) {
        int c = tolower((unsigned char)p[i]);
        int digit = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
        if (digit < 0) return 0;
        v = v * 16 + (unsigned)digit;
    }
    *out = v;
    return 1;
}

/* In place; the result is never longer. "_x000D_" is a carriage return and
 * "_x005F_" an underscore that is NOT the start of another escape. */
static size_t unescape(char *s, size_t n)
{
    size_t out = 0;
    for (size_t i = 0; i < n;) {
        unsigned code;
        if (s[i] == '_' && i + 6 < n && s[i + 1] == 'x' && s[i + 6] == '_' && hex4(s + i + 2, &code)) {
            i += 7;
            if (code == 0 || (code >= 0xD800 && code <= 0xDFFF) || code >= 0xFFFE) continue;
            if (code < 0x80) {
                s[out++] = (char)code;
            } else if (code < 0x800) {
                s[out++] = (char)(0xC0 | (code >> 6));
                s[out++] = (char)(0x80 | (code & 0x3F));
            } else {
                s[out++] = (char)(0xE0 | (code >> 12));
                s[out++] = (char)(0x80 | ((code >> 6) & 0x3F));
                s[out++] = (char)(0x80 | (code & 0x3F));
            }
            continue;
        }
        s[out++] = s[i++];
    }
    s[out] = '\0';
    return out;
}

/* ---- shared strings ------------------------------------------------ */
static void XMLCALL sst_start(void *ud, const XML_Char *name, const XML_Char **atts)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    const char *element = local_name(name);
    (void)atts;
    if (strcmp(element, "si") == 0) {
        ctx->in_si = 1;
        ctx->in_rph = 0;
        ctx->acc_len = 0;
        if (ctx->acc) ctx->acc[0] = '\0';
    } else if (strcmp(element, "rPh") == 0) {
        ctx->in_rph++;                    /* phonetic guide text: not the cell's */
    } else if (strcmp(element, "t") == 0 && ctx->in_si && !ctx->in_rph) {
        ctx->collect = 1;
    }
}

static void XMLCALL sst_end(void *ud, const XML_Char *name)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    xlx_reader *R = ctx->R;
    const char *element = local_name(name);
    if (strcmp(element, "t") == 0) {
        ctx->collect = 0;
    } else if (strcmp(element, "rPh") == 0) {
        if (ctx->in_rph) ctx->in_rph--;
    } else if (strcmp(element, "si") == 0 && ctx->in_si) {
        ctx->in_si = 0;
        if (R->sst_count >= XLX_MAX_STRINGS) { xr_stop(ctx, "the file holds more shared strings than this library reads"); return; }
        if (R->sst_count >= R->sst_offcap) {
            uint32_t cap = R->sst_offcap ? R->sst_offcap * 2 : 1024;
            uint32_t *grown = (uint32_t *)realloc(R->sst_off, (size_t)cap * sizeof *grown);
            if (!grown) { xr_stop(ctx, "out of memory"); return; }
            R->sst_off = grown;
            R->sst_offcap = cap;
        }
        size_t n = ctx->acc ? unescape(ctx->acc, ctx->acc_len) : 0;
        size_t at = R->sst_len;
        if (!buf_add(&R->sst_pool, &R->sst_len, &R->sst_cap, ctx->acc ? ctx->acc : "", n + 1, XLX_MAX_POOL)) {
            xr_stop(ctx, "the file's text is larger than this library reads (%u MB), or memory ran out",
                    (unsigned)(XLX_MAX_POOL >> 20));
            return;
        }
        R->sst_off[R->sst_count++] = (uint32_t)at;
    }
}

/* ---- styles: which cell formats show a number as a date ----------- */
static void XMLCALL styles_start(void *ud, const XML_Char *name, const XML_Char **atts)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    xlx_reader *R = ctx->R;
    const char *element = local_name(name);
    if (strcmp(element, "cellXfs") == 0) {
        ctx->in_cellxfs = 1;
    } else if (strcmp(element, "numFmt") == 0) {
        uint32_t id;
        const char *code = attr(atts, "formatCode");
        if (!code || !uint_in(attr(atts, "numFmtId"), 0x7FFFFFFF, &id) || strlen(code) > 4096) return;
        if (R->numfmt_count >= XLX_MAX_STYLES) { xr_stop(ctx, "the file defines too many number formats"); return; }
        if (R->numfmt_count >= R->numfmt_cap) {
            uint32_t cap = R->numfmt_cap ? R->numfmt_cap * 2 : 32;
            xr_numfmt *grown = (xr_numfmt *)realloc(R->numfmts, (size_t)cap * sizeof *grown);
            if (!grown) { xr_stop(ctx, "out of memory"); return; }
            R->numfmts = grown;
            R->numfmt_cap = cap;
        }
        R->numfmts[R->numfmt_count].id = id;
        R->numfmts[R->numfmt_count].code = copy_text(code);
        if (!R->numfmts[R->numfmt_count].code) { xr_stop(ctx, "out of memory"); return; }
        R->numfmt_count++;
    } else if (strcmp(element, "xf") == 0 && ctx->in_cellxfs) {
        uint32_t id = 0;
        (void)uint_in(attr(atts, "numFmtId"), 0x7FFFFFFF, &id);
        if (R->xf_count >= XLX_MAX_STYLES) { xr_stop(ctx, "the file defines too many cell formats"); return; }
        if (R->xf_count >= R->xf_cap) {
            uint32_t cap = R->xf_cap ? R->xf_cap * 2 : 64;
            uint32_t *grown = (uint32_t *)realloc(R->xf_numfmt, (size_t)cap * sizeof *grown);
            if (!grown) { xr_stop(ctx, "out of memory"); return; }
            R->xf_numfmt = grown;
            R->xf_cap = cap;
        }
        R->xf_numfmt[R->xf_count++] = id;
    }
}

static void XMLCALL styles_end(void *ud, const XML_Char *name)
{
    if (strcmp(local_name(name), "cellXfs") == 0) ((xr_ctx *)ud)->in_cellxfs = 0;
}

/* Excel's built-in number formats (the ones a file may use without
 * defining): id -> code. */
static const char *builtin_format(uint32_t id)
{
    switch (id) {
        case 0: return "General";
        case 1: return "0";
        case 2: return "0.00";
        case 3: return "#,##0";
        case 4: return "#,##0.00";
        case 9: return "0%";
        case 10: return "0.00%";
        case 11: return "0.00E+00";
        case 12: return "# ?/?";
        case 13: return "# \?\?/\?\?";
        case 14: return "mm-dd-yy";
        case 15: return "d-mmm-yy";
        case 16: return "d-mmm";
        case 17: return "mmm-yy";
        case 18: return "h:mm AM/PM";
        case 19: return "h:mm:ss AM/PM";
        case 20: return "h:mm";
        case 21: return "h:mm:ss";
        case 22: return "m/d/yy h:mm";
        case 37: return "#,##0 ;(#,##0)";
        case 38: return "#,##0 ;[Red](#,##0)";
        case 39: return "#,##0.00;(#,##0.00)";
        case 40: return "#,##0.00;[Red](#,##0.00)";
        case 45: return "mm:ss";
        case 46: return "[h]:mm:ss";
        case 47: return "mmss.0";
        case 48: return "##0.0E+0";
        case 49: return "@";
        default: return NULL;
    }
}

static const char *format_code(const xlx_reader *R, uint32_t style)
{
    if (style >= R->xf_count) return "General";
    uint32_t id = R->xf_numfmt[style];
    for (uint32_t i = R->numfmt_count; i > 0; i--)
        if (R->numfmts[i - 1].id == id) return R->numfmts[i - 1].code;
    const char *code = builtin_format(id);
    return code ? code : "General";
}

/* Does this format code show a date or a time? It does if, outside quoted
 * text, bracketed colour and condition tags and escaped characters, it
 * names a day, month, year, hour or second. ("m" alone is month or minute:
 * a date either way.) Elapsed-time tags [h] [m] [s] count. */
static int code_is_date(const char *code)
{
    for (const char *p = code; *p; p++) {
        if (*p == '"') {
            p++;
            while (*p && *p != '"') p++;
            if (!*p) break;
        } else if (*p == '\\' || *p == '_' || *p == '*') {
            if (p[1]) p++;
        } else if (*p == '[') {
            const char *close = strchr(p, ']');
            if (!close) break;
            if (close - p >= 2) {
                int elapsed = 1;
                char unit = (char)tolower((unsigned char)p[1]);
                for (const char *q = p + 1; q < close; q++)
                    if (tolower((unsigned char)*q) != unit) elapsed = 0;
                if (elapsed && (unit == 'h' || unit == 'm' || unit == 's')) return 1;
            }
            p = close;
        } else {
            char c = (char)tolower((unsigned char)*p);
            if (c == 'd' || c == 'm' || c == 'y' || c == 'h' || c == 's') return 1;
            /* "General", "Red" and the like are not built from those letters
             * alone, but "General" has none of them and E/e is scientific. */
        }
    }
    return 0;
}

static int style_is_date(const xlx_reader *R, uint32_t style)
{
    if (style >= R->xf_count) return 0;
    uint32_t id = R->xf_numfmt[style];
    if ((id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47) || (id >= 50 && id <= 58))
        return 1;
    for (uint32_t i = R->numfmt_count; i > 0; i--)
        if (R->numfmts[i - 1].id == id) return code_is_date(R->numfmts[i - 1].code);
    return 0;
}

/* ---- one sheet ------------------------------------------------------ */
static void sheet_drop(xlx_reader *R)
{
    for (uint32_t i = 0; i < R->row_cap; i++) free(R->rows[i].cells);
    free(R->rows);
    free(R->pool);
    free(R->merged);
    R->rows = NULL;
    R->row_cap = R->max_row = R->max_col = R->cell_total = 0;
    R->pool = NULL;
    R->pool_len = R->pool_cap = 0;
    R->merged = NULL;
    R->merged_len = R->merged_cap = 0;
    R->loaded = 0;
}

static int pool_put(xr_ctx *ctx, const char *text, size_t n, uint32_t *offset)
{
    xlx_reader *R = ctx->R;
    if (R->pool_len == 0 && !buf_add(&R->pool, &R->pool_len, &R->pool_cap, "", 1, XLX_MAX_POOL)) {
        xr_stop(ctx, "out of memory");
        return 0;
    }
    size_t at = R->pool_len;
    if (!buf_add(&R->pool, &R->pool_len, &R->pool_cap, text, n, XLX_MAX_POOL)
        || !buf_add(&R->pool, &R->pool_len, &R->pool_cap, "", 1, XLX_MAX_POOL)) {
        xr_stop(ctx, "the sheet's text is larger than this library reads (%u MB), or memory ran out",
                (unsigned)(XLX_MAX_POOL >> 20));
        return 0;
    }
    *offset = (uint32_t)at;
    return 1;
}

static void cell_store(xr_ctx *ctx, const xr_cell *cell, uint32_t row_number)
{
    xlx_reader *R = ctx->R;
    if (row_number > R->row_cap) {
        uint32_t cap = R->row_cap ? R->row_cap : 256;
        while (cap < row_number) cap *= 2;
        if (cap > XLX_MAX_ROW) cap = XLX_MAX_ROW;
        xr_row *grown = (xr_row *)realloc(R->rows, (size_t)cap * sizeof *grown);
        if (!grown) { xr_stop(ctx, "out of memory"); return; }
        memset(grown + R->row_cap, 0, (size_t)(cap - R->row_cap) * sizeof *grown);
        R->rows = grown;
        R->row_cap = cap;
    }
    xr_row *row = &R->rows[row_number - 1];
    /* where it goes: cells arrive left to right in every file a spreadsheet
     * program wrote, so the common case is "at the end" */
    uint32_t at = row->count;
    if (row->count > 0 && row->cells[row->count - 1].col >= cell->col) {
        uint32_t lo = 0, hi = row->count;
        while (lo < hi) {
            uint32_t mid = lo + (hi - lo) / 2;
            if (row->cells[mid].col < cell->col) lo = mid + 1; else hi = mid;
        }
        at = lo;
        if (at < row->count && row->cells[at].col == cell->col) {
            row->cells[at] = *cell;       /* named twice: the later one stands */
            return;
        }
    }
    if (R->cell_total >= XLX_MAX_CELLS) {
        xr_stop(ctx, "the sheet has more cells than this library reads (%u)", XLX_MAX_CELLS);
        return;
    }
    if (row->count >= row->cap) {
        uint32_t cap = row->cap ? row->cap * 2 : 8;
        xr_cell *grown = (xr_cell *)realloc(row->cells, (size_t)cap * sizeof *grown);
        if (!grown) { xr_stop(ctx, "out of memory"); return; }
        row->cells = grown;
        row->cap = cap;
    }
    if (at < row->count) memmove(row->cells + at + 1, row->cells + at, (size_t)(row->count - at) * sizeof *row->cells);
    row->cells[at] = *cell;
    row->count++;
    R->cell_total++;
    if (row_number > R->max_row) R->max_row = row_number;
    if (cell->col > R->max_col) R->max_col = cell->col;
}

static void XMLCALL sheet_start(void *ud, const XML_Char *name, const XML_Char **atts)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    const char *element = local_name(name);
    if (strcmp(element, "row") == 0) {
        uint32_t r;
        const char *rv = attr(atts, "r");
        if (rv) {
            if (!uint_in(rv, XLX_MAX_ROW, &r) || r < 1) { xr_stop(ctx, "a row is numbered outside the grid (\"%.20s\")", rv); return; }
            ctx->cur_row = r;
        } else {
            if (ctx->cur_row >= XLX_MAX_ROW) { xr_stop(ctx, "the sheet has more rows than the grid"); return; }
            ctx->cur_row++;
        }
        ctx->cur_col = 0;
    } else if (strcmp(element, "c") == 0) {
        const char *ref = attr(atts, "r"), *type = attr(atts, "t");
        if (ref) {
            int row, col;
            if (!cell_ref(ref, &row, &col, NULL)) { xr_stop(ctx, "a cell is named outside the grid (\"%.20s\")", ref); return; }
            ctx->cur_row = (uint32_t)row;
            ctx->cur_col = (uint32_t)col;
        } else {
            if (ctx->cur_row == 0) ctx->cur_row = 1;
            if (ctx->cur_col >= XLX_MAX_COL) { xr_stop(ctx, "a row has more cells than the grid has columns"); return; }
            ctx->cur_col++;
        }
        ctx->cur_style = 0;
        (void)uint_in(attr(atts, "s"), 0x7FFFFFFF, &ctx->cur_style);
        snprintf(ctx->cur_type, sizeof ctx->cur_type, "%s", type ? type : "n");
        ctx->in_c = 1;
        ctx->in_is = ctx->in_rph = ctx->have_v = ctx->have_f = 0;
        ctx->collect = 0;
        ctx->acc_len = ctx->facc_len = 0;
        if (ctx->acc) ctx->acc[0] = '\0';
        if (ctx->facc) ctx->facc[0] = '\0';
    } else if (ctx->in_c && strcmp(element, "v") == 0) {
        ctx->acc_len = 0;
        if (ctx->acc) ctx->acc[0] = '\0';
        ctx->collect = 1;
    } else if (ctx->in_c && strcmp(element, "f") == 0) {
        ctx->collect = 2;
    } else if (ctx->in_c && strcmp(element, "is") == 0) {
        ctx->in_is = 1;
        ctx->acc_len = 0;
        if (ctx->acc) ctx->acc[0] = '\0';
    } else if (ctx->in_is && strcmp(element, "rPh") == 0) {
        ctx->in_rph++;
    } else if (ctx->in_is && !ctx->in_rph && strcmp(element, "t") == 0) {
        ctx->collect = 1;
    } else if (strcmp(element, "mergeCell") == 0) {
        const char *ref = attr(atts, "ref"), *end = NULL;
        int r1, c1, r2, c2;
        xlx_reader *R = ctx->R;
        if (!ref || !cell_ref(ref, &r1, &c1, &end) || *end != ':' || !cell_ref(end + 1, &r2, &c2, NULL)) return;
        if (!buf_add(&R->merged, &R->merged_len, &R->merged_cap, ref, strlen(ref), 64u << 20)
            || !buf_add(&R->merged, &R->merged_len, &R->merged_cap, "\n", 1, 64u << 20))
            xr_stop(ctx, "the sheet lists more merged cells than this library reads, or memory ran out");
    }
}

static void XMLCALL sheet_end(void *ud, const XML_Char *name)
{
    xr_ctx *ctx = (xr_ctx *)ud;
    const char *element = local_name(name);
    if (!ctx->in_c) return;
    if (strcmp(element, "v") == 0) {
        ctx->collect = 0;
        ctx->have_v = 1;
    } else if (strcmp(element, "f") == 0) {
        ctx->collect = 0;
        ctx->have_f = 1;
    } else if (strcmp(element, "t") == 0) {
        ctx->collect = 0;
    } else if (strcmp(element, "rPh") == 0) {
        if (ctx->in_rph) ctx->in_rph--;
    } else if (strcmp(element, "is") == 0) {
        if (ctx->in_is) ctx->have_v = 1;
        ctx->in_is = 0;
    } else if (strcmp(element, "c") == 0) {
        xr_cell cell;
        const char *type = ctx->cur_type;
        const char *value = ctx->acc ? ctx->acc : "";
        size_t n = ctx->acc_len;
        memset(&cell, 0, sizeof cell);
        ctx->in_c = 0;
        ctx->collect = 0;
        cell.col = (uint16_t)ctx->cur_col;
        cell.style = ctx->cur_style;
        if (ctx->have_v) {
            if (strcmp(type, "s") == 0) {
                uint32_t index;
                if (uint_in(value, XLX_MAX_STRINGS, &index)) { cell.kind = XR_SHARED; cell.v.text = index; }
            } else if (strcmp(type, "b") == 0) {
                cell.kind = XR_BOOL;
                cell.v.number = truthy(value) ? 1 : 0;
            } else if (strcmp(type, "e") == 0) {
                cell.kind = XR_ERROR;
                if (!pool_put(ctx, value, n, &cell.v.text)) return;
            } else if (strcmp(type, "str") == 0 || strcmp(type, "inlineStr") == 0 || strcmp(type, "d") == 0) {
                cell.kind = XR_TEXT;
                if (ctx->acc) n = unescape(ctx->acc, n);
                if (!pool_put(ctx, value, n, &cell.v.text)) return;
            } else if (n > 0) {
                /* a number; anything else in a number cell is kept as the
                 * text it is rather than turned into a 0 nobody wrote */
                if (number_in(value, n, &cell.v.number)) {
                    cell.kind = XR_NUMBER;
                } else {
                    cell.kind = XR_TEXT;
                    if (!pool_put(ctx, value, n, &cell.v.text)) return;
                }
            }
        }
        if (ctx->have_f && ctx->facc_len > 0) {
            /* kept with its = sign, the way a script writes one */
            uint32_t at;
            if (!pool_put(ctx, "=", 1, &at)) return;
            ctx->R->pool_len--;                           /* join the two */
            if (!pool_put(ctx, ctx->facc, ctx->facc_len, &cell.formula)) return;
            cell.formula = at;
        }
        if (cell.kind == XR_EMPTY && cell.formula == 0) return;   /* a format with nothing in it */
        cell_store(ctx, &cell, ctx->cur_row);
    }
}

/* ---- opening, loading, closing -------------------------------------- */
static void reader_free(xlx_reader *R)
{
    if (!R) return;
    sheet_drop(R);
    if (R->zip) unzClose(R->zip);
    if (R->fp) fclose(R->fp);
    for (int i = 0; i < R->sheet_count; i++) { free(R->sheets[i].name); free(R->sheets[i].part); }
    free(R->sheets);
    free(R->strings_part);
    free(R->styles_part);
    free(R->sst_pool);
    free(R->sst_off);
    free(R->xf_numfmt);
    for (uint32_t i = 0; i < R->numfmt_count; i++) free(R->numfmts[i].code);
    free(R->numfmts);
    free(R);
}

static int reader_open(xlx_reader *R, const char *path)
{
    unsigned char magic[8] = {0};
    R->fp = open_utf8(path, "rb");
    if (!R->fp) return fail("the file cannot be opened");
    size_t got = fread(magic, 1, sizeof magic, R->fp);
    if (got >= 8 && memcmp(magic, "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1", 8) == 0)
        return fail("not a .xlsx file: this is the older .xls format, or a workbook encrypted with a password");
    if (got < 4 || memcmp(magic, "PK", 2) != 0)
        return fail("not a .xlsx file (a .xlsx is a zip archive, and this is not one)");

    zlib_filefunc64_def io;
    io.zopen64_file = xr_zopen;
    io.zread_file = xr_zread;
    io.zwrite_file = xr_zwrite;
    io.ztell64_file = xr_ztell;
    io.zseek64_file = xr_zseek;
    io.zclose_file = xr_zclose;
    io.zerror_file = xr_zerror;
    io.opaque = R->fp;
    R->zip = unzOpen2_64(path, &io);
    if (!R->zip) return fail("not a .xlsx file (its zip directory cannot be read)");

    /* 1. which part is the workbook */
    char *workbook_part = NULL;
    int ok = 1;
    {
        xr_ctx ctx;
        memset(&ctx, 0, sizeof ctx);
        int found = xr_parse(R, "_rels/.rels", &ctx, rels_start, no_end);
        if (found == 0) ok = 0;
        for (int i = 0; ok && i < ctx.rel_count && !workbook_part; i++)
            if (ends_with(ctx.rels[i].type, "/officeDocument")) workbook_part = resolve_part("", ctx.rels[i].target);
        xr_ctx_free(&ctx);
    }
    if (ok && !workbook_part) workbook_part = copy_text("xl/workbook.xml");
    if (!ok || !workbook_part) { free(workbook_part); return ok ? fail("out of memory") : 0; }

    /* 2. the workbook: sheet names and relationship ids */
    char *dir = NULL, *rels_part = NULL;
    xr_ctx book_ctx, rels_ctx;
    memset(&book_ctx, 0, sizeof book_ctx);
    memset(&rels_ctx, 0, sizeof rels_ctx);
    book_ctx.R = rels_ctx.R = R;
    int found = xr_parse(R, workbook_part, &book_ctx, workbook_start, no_end);
    if (found < 0) ok = fail("not a .xlsx workbook (the zip holds no %.200s)", workbook_part);
    else if (found == 0) ok = 0;
    if (ok && !part_neighbours(workbook_part, &dir, &rels_part)) ok = fail("out of memory");

    /* 3. its relationships: ids -> parts */
    if (ok) {
        found = xr_parse(R, rels_part, &rels_ctx, rels_start, no_end);
        if (found == 0) ok = 0;
    }
    for (int i = 0; ok && i < R->sheet_count; i++) {
        for (int k = 0; k < rels_ctx.rel_count; k++) {
            if (strcmp(rels_ctx.rels[k].id, book_ctx.rids[i]) == 0) {
                R->sheets[i].part = resolve_part(dir, rels_ctx.rels[k].target);
                break;
            }
        }
        /* a sheet whose part cannot be named stays in the list: asking for
         * its cells says so */
    }
    for (int k = 0; ok && k < rels_ctx.rel_count; k++) {
        if (!R->strings_part && ends_with(rels_ctx.rels[k].type, "/sharedStrings"))
            R->strings_part = resolve_part(dir, rels_ctx.rels[k].target);
        if (!R->styles_part && ends_with(rels_ctx.rels[k].type, "/styles"))
            R->styles_part = resolve_part(dir, rels_ctx.rels[k].target);
    }
    if (ok && R->sheet_count == 0) ok = fail("the workbook lists no sheets");
    xr_ctx_free(&book_ctx);
    xr_ctx_free(&rels_ctx);
    free(dir);
    free(rels_part);
    free(workbook_part);
    return ok;
}

/* The parts every sheet leans on, read once, on the first sheet asked for. */
static int reader_shared(xlx_reader *R)
{
    if (R->strings_state == 0) {
        R->strings_state = 1;
        if (R->strings_part) {
            xr_ctx ctx;
            memset(&ctx, 0, sizeof ctx);
            if (xr_parse(R, R->strings_part, &ctx, sst_start, sst_end) == 0) R->strings_state = -1;
            xr_ctx_free(&ctx);
        }
    }
    if (R->strings_state < 0) {
        if (!s_error[0]) fail("the file's shared text could not be read");
        return 0;
    }
    if (R->styles_state == 0) {
        R->styles_state = 1;
        if (R->styles_part) {
            xr_ctx ctx;
            memset(&ctx, 0, sizeof ctx);
            if (xr_parse(R, R->styles_part, &ctx, styles_start, styles_end) == 0) R->styles_state = -1;
            xr_ctx_free(&ctx);
        }
    }
    if (R->styles_state < 0) {
        if (!s_error[0]) fail("the file's cell formats could not be read");
        return 0;
    }
    return 1;
}

static xlx_reader *reader_in(int h)
{
    int slot = readers_slot_of(h);
    if (slot < 0) { fail("not an open file (handle %d)", h); return NULL; }
    return readers_arr[slot];
}

/* The reader with `sheet` loaded, or NULL (the error is set). */
static xlx_reader *sheet_ready(int reader, int sheet)
{
    xlx_reader *R = reader_in(reader);
    if (!R) return NULL;
    if (sheet < 1 || sheet > R->sheet_count) { fail("no such sheet: this file has %d", R->sheet_count); return NULL; }
    if (R->loaded == sheet) return R;
    /* A sheet that would not load is not tried again: a script that reads a
     * damaged sheet cell by cell would otherwise parse the whole part once
     * per cell, to be told the same thing each time. */
    if (R->failed == sheet) { memcpy(s_error, R->failed_error, sizeof s_error); return NULL; }
    sheet_drop(R);
    R->failed = 0;
    int found = 0;
    if (!reader_shared(R)) {
        found = 0;
    } else if (!R->sheets[sheet - 1].part) {
        fail("the file does not say where sheet %d is kept", sheet);
    } else {
        xr_ctx ctx;
        memset(&ctx, 0, sizeof ctx);
        found = xr_parse(R, R->sheets[sheet - 1].part, &ctx, sheet_start, sheet_end);
        xr_ctx_free(&ctx);
        if (found < 0) fail("the file lists sheet %d but does not hold it", sheet);
    }
    if (found != 1) {
        sheet_drop(R);
        R->failed = sheet;
        memcpy(R->failed_error, s_error, sizeof s_error);
        return NULL;
    }
    R->loaded = sheet;
    return R;
}

static const xr_cell *cell_at(const xlx_reader *R, int row, int col)
{
    if (row < 1 || col < 1 || (uint32_t)row > R->max_row || (uint32_t)col > R->max_col) return NULL;
    const xr_row *r = &R->rows[row - 1];
    uint32_t lo = 0, hi = r->count;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        if (r->cells[mid].col < (uint32_t)col) lo = mid + 1; else hi = mid;
    }
    return (lo < r->count && r->cells[lo].col == (uint32_t)col) ? &r->cells[lo] : NULL;
}

static const char *cell_string(const xlx_reader *R, const xr_cell *cell)
{
    if (cell->kind == XR_SHARED)
        return cell->v.text < R->sst_count ? R->sst_pool + R->sst_off[cell->v.text] : "";
    return (cell->v.text < R->pool_len) ? R->pool + cell->v.text : "";
}

/* What a cell holds, as text. shown = 1: a date as a date; 0: as its serial. */
static const char *cell_text(const xlx_reader *R, const xr_cell *cell, int shown, char *scratch, size_t size)
{
    switch (cell->kind) {
        case XR_NUMBER:
            if (shown && style_is_date(R, cell->style)
                && serial_text(cell->v.number, R->date1904, 1, scratch, size))
                return scratch;
            number_out(cell->v.number, scratch, size);
            return scratch;
        case XR_BOOL:
            return cell->v.number != 0 ? "true" : "false";
        case XR_TEXT:
        case XR_SHARED:
        case XR_ERROR:
            return cell_string(R, cell);
        default:
            return "";
    }
}

LC_API int xlx_read_count(void)
{
    return readers_live;
}

LC_API int xlx_read_open(const char *path)
{
    ok_clear();
    if (!name_ok(path, XLX_MAX_PATH) || !*path) return fail("the file path is empty, too long or not valid text");
    xlx_reader *R = (xlx_reader *)calloc(1, sizeof *R);
    if (!R) return fail("out of memory");
    if (!reader_open(R, path)) { reader_free(R); return 0; }
    int h = readers_add(R);
    if (!h) { reader_free(R); return fail("too many open files"); }
    return h;
}

LC_API void xlx_read_close(int reader)
{
    ok_clear();
    int slot = readers_slot_of(reader);
    if (slot < 0) { fail("not an open file (handle %d)", reader); return; }
    reader_free(readers_arr[slot]);
    readers_free_slot(slot);
}

LC_API int xlx_read_is_valid(int reader)
{
    return readers_slot_of(reader) >= 0;
}

LC_API int xlx_read_sheet_count(int reader)
{
    ok_clear();
    xlx_reader *R = reader_in(reader);
    return R ? R->sheet_count : 0;
}

LC_API const char *xlx_read_sheet_name(int reader, int sheet)
{
    ok_clear();
    xlx_reader *R = reader_in(reader);
    if (!R) return "";
    if (sheet < 1 || sheet > R->sheet_count) { fail("no such sheet: this file has %d", R->sheet_count); return ""; }
    return text_of(R->sheets[sheet - 1].name);
}

/* The number of the sheet with this name (as Excel compares names: without
 * regard to letter case, for ASCII letters), or 0. */
LC_API int xlx_read_sheet_number(int reader, const char *name)
{
    ok_clear();
    xlx_reader *R = reader_in(reader);
    if (!R) return 0;
    if (!name) name = "";
    for (int i = 0; i < R->sheet_count; i++)
        if (same_word(R->sheets[i].name, name)) return i + 1;
    return fail("the file has no sheet of that name");
}

LC_API int xlx_read_sheet_is_hidden(int reader, int sheet)
{
    ok_clear();
    xlx_reader *R = reader_in(reader);
    if (!R) return 0;
    if (sheet < 1 || sheet > R->sheet_count) return fail("no such sheet: this file has %d", R->sheet_count);
    return R->sheets[sheet - 1].hidden;
}

LC_API int xlx_read_uses_1904(int reader)
{
    ok_clear();
    xlx_reader *R = reader_in(reader);
    return R ? R->date1904 : 0;
}

/* Reads a sheet's cells now, and says whether that worked. Every other read
 * call does this itself when it has to; calling it first separates "the
 * sheet is damaged" from "the cell is empty". */
LC_API int xlx_read_load(int reader, int sheet)
{
    ok_clear();
    return sheet_ready(reader, sheet) != NULL;
}

/* The last row and the last column that hold anything. */
LC_API int xlx_read_row_count(int reader, int sheet)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    return R ? (int)R->max_row : 0;
}

LC_API int xlx_read_column_count(int reader, int sheet)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    return R ? (int)R->max_col : 0;
}

LC_API const char *xlx_read_cell(int reader, int sheet, int row, int column)
{
    char scratch[64];
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    return cell ? text_of(cell_text(R, cell, 1, scratch, sizeof scratch)) : "";
}

LC_API const char *xlx_read_cell_value(int reader, int sheet, int row, int column)
{
    char scratch[64];
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    return cell ? text_of(cell_text(R, cell, 0, scratch, sizeof scratch)) : "";
}

LC_API double xlx_read_cell_number(int reader, int sheet, int row, int column)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    return (cell && (cell->kind == XR_NUMBER || cell->kind == XR_BOOL)) ? cell->v.number : 0;
}

/* "empty", "number", "date", "text", "boolean" or "error". A date is a
 * number whose format shows it as a date or a time. */
LC_API const char *xlx_read_cell_kind(int reader, int sheet, int row, int column)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    if (!cell) return text_of(R ? "empty" : "");
    switch (cell->kind) {
        case XR_NUMBER: {
            char scratch[64];
            int date = style_is_date(R, cell->style) && serial_text(cell->v.number, R->date1904, 1, scratch, sizeof scratch);
            return text_of(date ? "date" : "number");
        }
        case XR_BOOL:  return text_of("boolean");
        case XR_ERROR: return text_of("error");
        case XR_TEXT:
        case XR_SHARED: return text_of("text");
        default: return text_of("empty");
    }
}

/* The formula with its = sign, or "" for a cell that has none. Where Excel
 * shares one formula between a run of cells, only the first holds the text. */
LC_API const char *xlx_read_cell_formula(int reader, int sheet, int row, int column)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    return (cell && cell->formula && cell->formula < R->pool_len) ? text_of(R->pool + cell->formula) : "";
}

/* The cell's number format code: "General", "0.00", "yyyy-mm-dd". */
LC_API const char *xlx_read_cell_format(int reader, int sheet, int row, int column)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    const xr_cell *cell = R ? cell_at(R, row, column) : NULL;
    return cell ? text_of(format_code(R, cell->style)) : "";
}

/* A block of cells as one text, rows separated by newlines and cells by
 * tabs: what xlx_sheet_write_grid takes, and what xTalk's `split` and a
 * field with tab stops want. last_row or last_column 0 means "to the end".
 * Each row stops at its own last cell (no run of trailing tabs), and a row
 * with nothing in it is an empty line. Inside a cell, a tab becomes a space
 * and a line break a vertical tab (ASCII 11). */
LC_API const char *xlx_read_grid(int reader, int sheet, int first_row, int first_column, int last_row, int last_column)
{
    char scratch[64];
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    if (!R) return "";
    if (last_row == 0) last_row = XLX_MAX_ROW;
    if (last_column == 0) last_column = XLX_MAX_COL;
    if (!range_in(first_row, first_column, last_row, last_column)) { fail("not a range: the first cell must be above and left of the last, inside the grid"); return ""; }
    if ((uint32_t)last_row > R->max_row) last_row = (int)R->max_row;
    text_begin();
    for (int row = first_row; row <= last_row; row++) {
        const xr_row *r = &R->rows[row - 1];
        int at = first_column;
        if (row > first_row && !text_addc('\n')) goto too_large;
        for (uint32_t i = 0; i < r->count; i++) {
            const xr_cell *cell = &r->cells[i];
            if (cell->col < (uint32_t)first_column) continue;
            if (cell->col > (uint32_t)last_column) break;
            if (cell->kind == XR_EMPTY) continue;
            for (; at < (int)cell->col; at++) if (!text_addc('\t')) goto too_large;
            const char *text = cell_text(R, cell, 1, scratch, sizeof scratch);
            size_t n = strlen(text);
            if (!text_reserve(n)) goto too_large;
            for (size_t k = 0; k < n; k++) {
                char ch = text[k];
                if (ch == '\r') continue;
                s_text[s_text_len++] = (ch == '\t') ? ' ' : (ch == '\n') ? '\v' : ch;
            }
            s_text[s_text_len] = '\0';
        }
    }
    return text_done();
too_large:
    text_begin();
    fail("the block is too large to return as one text (%u MB); ask for fewer rows at a time",
         (unsigned)(XLX_MAX_TEXT_OUT >> 20));
    return "";
}

/* The sheet's merged blocks, one range such as "A1:C1" per line. */
LC_API const char *xlx_read_merged(int reader, int sheet)
{
    ok_clear();
    xlx_reader *R = sheet_ready(reader, sheet);
    if (!R || !R->merged) return "";
    text_begin();
    if (!text_add(R->merged, R->merged_len ? R->merged_len - 1 : 0)) return "";
    return text_done();
}
