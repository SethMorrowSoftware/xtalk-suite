/*
 * pdfium_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of pdfxt: PDFium (the PDF engine of Chromium) behind a flat C
 * ABI that the xTalk Builder (LCB) foreign function interface can call, so
 * OpenXTalk and LiveCode-compatible engines can open a PDF, draw its pages,
 * and read its text, outline and links. box3dxt/src/box3d_shim.c is this
 * file's ancestor and its conventions are kept:
 *
 *   - A document is a positive 32-bit int handle (0 = invalid), generation
 *     tagged: a closed handle stays dead after its slot is reused.
 *   - A page is a NUMBER, 1 for the first, as script counts. So is a
 *     character of a page's text.
 *   - Every real crosses as `double`, every boolean as `int`.
 *   - A result that is text crosses as a pointer to a buffer this file owns
 *     (UTF-8), measured by pdx_text_length; a result that is bytes (a drawn
 *     page) the same way, measured by pdx_data_length. The binding copies at
 *     once and script is single-threaded. NEVER a string the engine would
 *     free: that killed box3dxt's first engine run.
 *   - A point or a rectangle of a page is in POINTS (1/72 inch) from the TOP
 *     LEFT of the page as it is displayed, y growing downwards: left, top,
 *     right, bottom, the order of an xTalk rect. A page drawn at one pixel
 *     per point has its text exactly where these say; multiply by the zoom.
 *     (PDF's own space starts bottom left and ignores the page's rotation;
 *     PDFium converts, see to_view.)
 *
 * PDFIUM IS NOT LINKED. IT IS LOADED. PDFium has no build but Google's own
 * (gn and a multi-gigabyte checkout), so pdfxt ships the pinned prebuilt
 * shared library of bblanchon/pdfium-binaries as a SECOND file beside this
 * one: pdfium.dll, pdfium.so or pdfium.dylib. This shim finds its own folder
 * and loads that file from there on first use, by full path, and resolves
 * each function by name. Three things follow:
 *   - if the file is missing, nothing crashes and nothing fails to load: every
 *     call returns 0 or empty and pdx_last_error says where it looked;
 *   - on Linux the load is RTLD_DEEPBIND. PDFium carries its own FreeType
 *     and exports it, and calls it through the PLT, so without that flag
 *     its calls would bind to the FreeType the host engine already loaded
 *     (another version, another layout). Measured on the pinned file:
 *     218 jump slots, FT_* among them, no -Bsymbolic;
 *   - the headers of the SAME pinned archive are compiled against, and each
 *     pointer is declared with typeof the header's own declaration, so a
 *     changed signature in a new pin is a compile error here.
 *
 * Safety. A PDF is a stranger's file. PDFium parses it; this build has no
 * JavaScript engine (V8) and no XFA, so a document cannot run code. What this
 * file adds: every handle and every number is validated before PDFium sees
 * it, a page drawing is bounded (PDX_MAX_SIDE, PDX_MAX_PIXELS), text results
 * are bounded, the outline walk is bounded against a cyclic file, and no
 * callback reaches script: the one callback (the file reader) runs inside
 * the call that asked, on the caller's thread (suite rule 1).
 *
 * PDFium is NOT thread-safe and neither is this file: one thread, the
 * script's.
 * ----------------------------------------------------------------------------
 */

#if !defined(_WIN32)
    #define _GNU_SOURCE 1          /* dladdr, RTLD_DEEPBIND, fseeko */
    #define _FILE_OFFSET_BITS 64
#endif

#include "fpdfview.h"
#include "fpdf_doc.h"
#include "fpdf_edit.h"
#include "fpdf_text.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #define LC_API __declspec(dllexport)
#else
    #include <dlfcn.h>
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/pdfxt.lcb's checkABI() names the
 * same number and refuses a library that answers another. */
#define PDX_ABI_VERSION 1

/* The PDFium this was compiled against, as bblanchon/pdfium-binaries names
 * its release. CMakeLists.txt passes the pin it fetched. */
#ifndef PDX_PDFIUM_PIN
    #define PDX_PDFIUM_PIN "unknown"
#endif

/* THE LIMITS. Each is far above what a viewer asks for and is named in the
 * API page; a request outside one is refused like any other bad argument.
 *
 *   one side of a drawing           1 .. 16384 pixels
 *   a whole drawing                 40 000 000 pixels (160 MB as imageData)
 *   the page a region is cut from   1 .. 1 000 000 pixels a side
 *   a file                          2 GB less a byte (PDFium's reader takes
 *                                   an unsigned long, 32 bits on Windows)
 *   a text result                   64 MB
 *   an outline                      100 000 entries, 64 levels deep
 *   open documents                  4095
 */
#define PDX_MAX_SIDE      16384
#define PDX_MAX_PIXELS    40000000
#define PDX_MAX_ZOOMED    1000000
#define PDX_MAX_FILE      2147483647L
#define PDX_MAX_TEXT      (64u * 1024u * 1024u)
#define PDX_MAX_OUTLINE   100000
#define PDX_MAX_DEPTH     64
#define PDX_MAX_DOCS      4095   /* slot + 1 must fit PDX_H_SLOT_BITS */

/* ------------------------------------------------------------------ */
/* The last refusal, for pdfLastError(). A short text, or "".          */
/* ------------------------------------------------------------------ */
static char s_error[512] = "";
static int fail(const char *why)
{
    snprintf(s_error, sizeof s_error, "%s", why);
    return 0;
}
static void ok_clear(void) { s_error[0] = 0; }

/* ------------------------------------------------------------------ */
/* PDFium, loaded by name.                                             */
/* ------------------------------------------------------------------ */
#define PDX_SYMBOLS(X)                \
    X(FPDF_InitLibraryWithConfig)     \
    X(FPDF_DestroyLibrary)            \
    X(FPDF_GetLastError)              \
    X(FPDF_LoadCustomDocument)        \
    X(FPDF_LoadMemDocument64)         \
    X(FPDF_CloseDocument)             \
    X(FPDF_GetPageCount)              \
    X(FPDF_GetFileVersion)            \
    X(FPDF_GetDocPermissions)         \
    X(FPDF_GetMetaText)               \
    X(FPDF_GetPageLabel)              \
    X(FPDF_GetPageSizeByIndexF)       \
    X(FPDF_LoadPage)                  \
    X(FPDF_ClosePage)                 \
    X(FPDF_GetPageWidthF)             \
    X(FPDF_GetPageHeightF)            \
    X(FPDFPage_GetRotation)           \
    X(FPDF_PageToDevice)              \
    X(FPDF_DeviceToPage)              \
    X(FPDFBitmap_CreateEx)            \
    X(FPDFBitmap_FillRect)            \
    X(FPDFBitmap_Destroy)             \
    X(FPDF_RenderPageBitmap)          \
    X(FPDFText_LoadPage)              \
    X(FPDFText_ClosePage)             \
    X(FPDFText_CountChars)            \
    X(FPDFText_GetText)               \
    X(FPDFText_GetBoundedText)        \
    X(FPDFText_GetCharBox)            \
    X(FPDFText_GetCharIndexAtPos)     \
    X(FPDFText_CountRects)            \
    X(FPDFText_GetRect)               \
    X(FPDFText_FindStart)             \
    X(FPDFText_FindNext)              \
    X(FPDFText_GetSchResultIndex)     \
    X(FPDFText_GetSchCount)           \
    X(FPDFText_FindClose)             \
    X(FPDFBookmark_GetFirstChild)     \
    X(FPDFBookmark_GetNextSibling)    \
    X(FPDFBookmark_GetTitle)          \
    X(FPDFBookmark_GetDest)           \
    X(FPDFBookmark_GetAction)         \
    X(FPDFAction_GetType)             \
    X(FPDFAction_GetDest)             \
    X(FPDFAction_GetURIPath)          \
    X(FPDFDest_GetDestPageIndex)      \
    X(FPDFLink_Enumerate)             \
    X(FPDFLink_GetAnnotRect)          \
    X(FPDFLink_GetDest)               \
    X(FPDFLink_GetAction)

/* One pointer per function, typed by the pinned header's own declaration. */
#define PDX_DECLARE(name) static __typeof__(name) *p_##name = NULL;
PDX_SYMBOLS(PDX_DECLARE)

#if defined(_WIN32)
    typedef HMODULE pdx_lib;
#else
    typedef void *pdx_lib;
#endif
static pdx_lib s_lib = NULL;      /* the loaded PDFium, never unloaded     */
static int s_inited = 0;          /* FPDF_InitLibraryWithConfig has run    */

#define PDX_PATH_MAX 4096

#if defined(_WIN32)
static wchar_t *widen(const char *utf8)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (!w) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n) <= 0) { free(w); return NULL; }
    return w;
}
#endif

/* The folder this library was loaded from, UTF-8, no trailing separator. */
static int own_folder(char *out, size_t cap)
{
#if defined(_WIN32)
    HMODULE self = NULL;
    wchar_t wide[PDX_PATH_MAX];
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void *)&own_folder, &self))
        return 0;
    DWORD n = GetModuleFileNameW(self, wide, PDX_PATH_MAX);
    if (n == 0 || n >= PDX_PATH_MAX) return 0;
    while (n > 0 && wide[n - 1] != L'\\' && wide[n - 1] != L'/') n--;
    if (n == 0) return 0;
    wide[n - 1] = 0;
    return WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, (int)cap, NULL, NULL) > 0;
#else
    Dl_info info;
    if (!dladdr((void *)&own_folder, &info) || !info.dli_fname) return 0;
    const char *slash = strrchr(info.dli_fname, '/');
    if (!slash) return 0;
    size_t n = (size_t)(slash - info.dli_fname);
    if (n == 0) n = 1;                       /* "/lib.so" lives in "/" */
    if (n >= cap) return 0;
    memcpy(out, info.dli_fname, n);
    out[n] = 0;
    return 1;
#endif
}

static pdx_lib open_library(const char *path)
{
#if defined(_WIN32)
    wchar_t *w = widen(path);
    if (!w) return NULL;
    /* The altered search path looks for PDFium's own imports beside IT; it
     * has none but system DLLs, and a full path names exactly one file. */
    HMODULE h = LoadLibraryExW(w, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    free(w);
    return h;
#else
    int flags = RTLD_NOW | RTLD_LOCAL;
    /* See the header: PDFium must bind to its OWN FreeType. The sanitizers'
     * runtime refuses RTLD_DEEPBIND (it would hide their malloc), and a test
     * process has loaded no other FreeType, so a sanitized build goes
     * without. bionic and macOS have no such flag and no such problem: both
     * resolve a library's own symbols first. */
    #if defined(RTLD_DEEPBIND) && !defined(__SANITIZE_ADDRESS__) && !defined(PDX_NO_DEEPBIND)
    flags |= RTLD_DEEPBIND;
    #endif
    return dlopen(path, flags);
#endif
}

static void *find_symbol(pdx_lib lib, const char *name)
{
#if defined(_WIN32)
    return (void *)GetProcAddress(lib, name);
#else
    return dlsym(lib, name);
#endif
}

/* The names PDFium's file may have, most likely first. The suite's tree
 * holds every library under its bare name ("pdfium.so"); the upstream
 * archive and Android's packager (which adds "lib") spell it "libpdfium". */
#if defined(_WIN32)
    static const char *const k_names[] = { "pdfium.dll", NULL };
    #define PDX_SEP "\\"
#elif defined(__APPLE__)
    static const char *const k_names[] = { "pdfium.dylib", "libpdfium.dylib", NULL };
    #define PDX_SEP "/"
#else
    static const char *const k_names[] = { "pdfium.so", "libpdfium.so", NULL };
    #define PDX_SEP "/"
#endif

static int resolve_all(pdx_lib lib, const char **missing)
{
#define PDX_RESOLVE(name)                                            \
    p_##name = (__typeof__(name) *)find_symbol(lib, #name);          \
    if (!p_##name) { *missing = #name; return 0; }
    PDX_SYMBOLS(PDX_RESOLVE)
    return 1;
}

static void forget_all(void)
{
#define PDX_FORGET(name) p_##name = NULL;
    PDX_SYMBOLS(PDX_FORGET)
}

static int init_library(void)
{
    if (s_inited) return 1;
    FPDF_LIBRARY_CONFIG config;
    memset(&config, 0, sizeof config);
    config.version = 2;               /* no V8 in this build: the rest is 0 */
    p_FPDF_InitLibraryWithConfig(&config);
    s_inited = 1;
    return 1;
}

/* Load PDFium from `folder` ("" or NULL: this library's own folder). */
static int load_from(const char *folder)
{
    char own[PDX_PATH_MAX];
    char path[PDX_PATH_MAX + 32];
    if (s_lib) return init_library();
    if (!folder || !folder[0]) {
        if (!own_folder(own, sizeof own)) {
            own[0] = 0;
        }
        folder = own;
    }
    if (strlen(folder) >= PDX_PATH_MAX) return fail("the folder path is too long");
    pdx_lib lib = NULL;
    if (folder[0]) {
        for (int i = 0; k_names[i] && !lib; i++) {
            snprintf(path, sizeof path, "%s%s%s", folder, PDX_SEP, k_names[i]);
            lib = open_library(path);
        }
    }
#if defined(__ANDROID__)
    /* An app's libraries may never leave the APK, so there is no folder to
     * build a path in; the linker finds a packaged library by its name. */
    if (!lib) lib = open_library("libpdfium.so");
#endif
    if (!lib) {
        snprintf(s_error, sizeof s_error,
                 "the PDFium library (%s) was not found or could not be loaded in: %.300s",
                 k_names[0], folder[0] ? folder : "(the folder of pdfxt could not be found)");
        return 0;
    }
    const char *missing = NULL;
    if (!resolve_all(lib, &missing)) {
        /* Not the pinned PDFium. Leave it loaded (unloading a library that
         * ran initialisers is the riskier act) but use none of it. */
        forget_all();
        snprintf(s_error, sizeof s_error,
                 "the PDFium library found has no %s: it is not the build pdfxt was made for (%s)",
                 missing, PDX_PDFIUM_PIN);
        return 0;
    }
    s_lib = lib;
    return init_library();
}

/* Every export that needs PDFium starts here. */
static int ready(void)
{
    if (s_lib && s_inited) return 1;
    return load_from(NULL);
}

/* ------------------------------------------------------------------ */
/* Documents: the handle table.                                        */
/* A handle packs an 11-bit generation above a 12-bit slot number      */
/* (slot + 1). A slot whose generation would wrap is retired, never    */
/* reused (box3dxt's change: the 2048th reuse would hand out the bits  */
/* of the first handle again).                                         */
/* ------------------------------------------------------------------ */
#define PDX_H_SLOT_BITS 12
#define PDX_H_SLOT_MASK 0xFFF
#define PDX_H_GEN_MASK  0x7FF

typedef struct pdx_doc {
    FPDF_DOCUMENT doc;
    FILE *fp;                    /* a document opened from a path        */
    unsigned char *mem;          /* a document opened from bytes (ours)  */
    FPDF_FILEACCESS access;      /* must outlive doc: it lives here      */
    int pages;
    /* ONE loaded page, kept between calls: a viewer asks many things of
     * the page it shows, and loading is the expensive part. */
    int pageNo;                  /* 1-based; 0 = none loaded             */
    FPDF_PAGE page;
    FPDF_TEXTPAGE text;          /* loaded on first text call, or NULL   */
} pdx_doc;

static pdx_doc *s_docs[PDX_MAX_DOCS];
static unsigned short s_gen[PDX_MAX_DOCS];
static unsigned char s_retired[PDX_MAX_DOCS];
static int s_slots = 0;          /* slots ever used                      */
static int s_open = 0;           /* documents open now                   */

static pdx_doc *doc_of(int h)
{
    if (h <= 0) return NULL;
    int idx = (h & PDX_H_SLOT_MASK) - 1;
    unsigned gen = ((unsigned)h >> PDX_H_SLOT_BITS) & PDX_H_GEN_MASK;
    if (idx < 0 || idx >= s_slots) return NULL;
    if (!s_docs[idx] || s_gen[idx] != gen) return NULL;
    return s_docs[idx];
}

static int doc_add(pdx_doc *d)
{
    int idx = -1;
    for (int i = 0; i < s_slots; i++) {
        if (!s_docs[i] && !s_retired[i]) { idx = i; break; }
    }
    if (idx < 0) {
        if (s_slots >= PDX_MAX_DOCS) return 0;
        idx = s_slots++;
    }
    s_docs[idx] = d;
    s_open++;
    return (int)(((unsigned)s_gen[idx] << PDX_H_SLOT_BITS) | (unsigned)(idx + 1));
}

static void drop_page(pdx_doc *d)
{
    if (d->text) { p_FPDFText_ClosePage(d->text); d->text = NULL; }
    if (d->page) { p_FPDF_ClosePage(d->page); d->page = NULL; }
    d->pageNo = 0;
}

static void doc_destroy(pdx_doc *d)
{
    drop_page(d);
    if (d->doc) p_FPDF_CloseDocument(d->doc);
    if (d->fp) fclose(d->fp);
    free(d->mem);
    free(d);
}

static void doc_free_slot(int idx)
{
    doc_destroy(s_docs[idx]);
    s_docs[idx] = NULL;
    s_open--;
    if (s_gen[idx] >= PDX_H_GEN_MASK) s_retired[idx] = 1;
    else s_gen[idx] = (unsigned short)(s_gen[idx] + 1);
}

/* The document and one of its pages, loaded. */
static pdx_doc *page_of(int h, int pageNo)
{
    pdx_doc *d = doc_of(h);
    if (!d) { fail("not an open document"); return NULL; }
    if (pageNo < 1 || pageNo > d->pages) { fail("no such page"); return NULL; }
    if (d->pageNo != pageNo) {
        drop_page(d);
        d->page = p_FPDF_LoadPage(d->doc, pageNo - 1);
        if (!d->page) { fail("the page could not be loaded"); return NULL; }
        d->pageNo = pageNo;
    }
    return d;
}

static pdx_doc *text_of(int h, int pageNo)
{
    pdx_doc *d = page_of(h, pageNo);
    if (!d) return NULL;
    if (!d->text) {
        d->text = p_FPDFText_LoadPage(d->page);
        if (!d->text) { fail("the page's text could not be read"); return NULL; }
    }
    return d;
}

/* ------------------------------------------------------------------ */
/* Results: one text buffer, one byte buffer.                          */
/* ------------------------------------------------------------------ */
static char *s_text = NULL;
static size_t s_textLen = 0, s_textCap = 0;
static int s_textFull = 0;        /* a result hit PDX_MAX_TEXT            */
static char s_empty[1] = "";

static void tb_reset(void) { s_textLen = 0; s_textFull = 0; if (s_text) s_text[0] = 0; }

static int tb_room(size_t more)
{
    if (s_textFull) return 0;
    if (s_textLen + more + 1 > PDX_MAX_TEXT) { s_textFull = 1; return 0; }
    if (s_textLen + more + 1 > s_textCap) {
        size_t nc = s_textCap ? s_textCap : 4096;
        while (nc < s_textLen + more + 1) nc *= 2;
        char *nt = (char *)realloc(s_text, nc);
        if (!nt) { s_textFull = 1; return 0; }
        s_text = nt; s_textCap = nc;
    }
    return 1;
}

static void tb_bytes(const char *p, size_t n)
{
    if (!tb_room(n)) return;
    memcpy(s_text + s_textLen, p, n);
    s_textLen += n;
    s_text[s_textLen] = 0;
}
static void tb_str(const char *p) { tb_bytes(p, strlen(p)); }
static void tb_char(char c) { tb_bytes(&c, 1); }

static void tb_int(long v)
{
    char b[32];
    snprintf(b, sizeof b, "%ld", v);
    tb_str(b);
}

/* A number with at most two decimals and a "." in every locale (an engine
 * built on GTK calls setlocale, and "1,5" would be two items): made from
 * integers, so no locale is ever asked. */
static void tb_num(double v)
{
    char b[48];
    if (!isfinite(v)) { tb_char('0'); return; }
    if (v > 1.0e12) v = 1.0e12;
    if (v < -1.0e12) v = -1.0e12;
    long long h = llround(v * 100.0);
    const char *sign = h < 0 ? "-" : "";
    if (h < 0) h = -h;
    long long whole = h / 100;
    int frac = (int)(h % 100);
    if (frac == 0) snprintf(b, sizeof b, "%s%lld", sign, whole);
    else if (frac % 10 == 0) snprintf(b, sizeof b, "%s%lld.%d", sign, whole, frac / 10);
    else snprintf(b, sizeof b, "%s%lld.%02d", sign, whole, frac);
    tb_str(b);
}

static void tb_codepoint(unsigned cp)
{
    char b[4];
    if (cp < 0x80) { b[0] = (char)cp; tb_bytes(b, 1); }
    else if (cp < 0x800) {
        b[0] = (char)(0xC0 | (cp >> 6)); b[1] = (char)(0x80 | (cp & 0x3F));
        tb_bytes(b, 2);
    } else if (cp < 0x10000) {
        b[0] = (char)(0xE0 | (cp >> 12)); b[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        b[2] = (char)(0x80 | (cp & 0x3F));
        tb_bytes(b, 3);
    } else {
        b[0] = (char)(0xF0 | (cp >> 18)); b[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        b[2] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[3] = (char)(0x80 | (cp & 0x3F));
        tb_bytes(b, 4);
    }
}

/* UTF-16 (PDFium's text, host byte order as unsigned short) to UTF-8.
 * A lone surrogate becomes U+FFFD; a NUL ends nothing and becomes a space.
 * oneLine: the text is one FIELD of a line of a list, so a return, a line
 * feed or a tab in it becomes a space. Otherwise CR LF and a lone CR become
 * the one line end script splits on, LF. */
static void tb_utf16(const unsigned short *p, size_t n, int oneLine)
{
    for (size_t i = 0; i < n; i++) {
        unsigned cp = p[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n && p[i + 1] >= 0xDC00 && p[i + 1] <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (p[i + 1] - 0xDC00);
            i++;
        } else if (cp >= 0xD800 && cp <= 0xDFFF) {
            cp = 0xFFFD;
        }
        if (cp == 0) cp = ' ';
        if (cp == '\r') {
            if (i + 1 < n && p[i + 1] == '\n') continue;
            cp = '\n';
        }
        if (oneLine && (cp == '\n' || cp == '\t')) cp = ' ';
        tb_codepoint(cp);
    }
}

/* UTF-16LE BYTES (what the metadata calls fill) to UTF-8, the same way. */
static void tb_utf16le_bytes(const unsigned char *p, size_t bytes, int oneLine)
{
    size_t n = bytes / 2;
    while (n > 0 && p[2 * n - 2] == 0 && p[2 * n - 1] == 0) n--;   /* the NUL */
    unsigned short *w = (unsigned short *)malloc((n ? n : 1) * sizeof(unsigned short));
    if (!w) return;
    for (size_t i = 0; i < n; i++) w[i] = (unsigned short)(p[2 * i] | (p[2 * i + 1] << 8));
    tb_utf16(w, n, oneLine);
    free(w);
}

static const char *tb_result(void)
{
    if (!s_text) return s_empty;
    return s_text;
}

/* UTF-8 (script's text) to NUL-terminated UTF-16, for a search. malloc'd.
 * A malformed byte becomes U+FFFD. */
static unsigned short *utf8_to_utf16(const char *s, size_t *count)
{
    size_t n = strlen(s);
    unsigned short *w = (unsigned short *)malloc((n + 1) * 2 * sizeof(unsigned short));
    if (!w) return NULL;
    size_t o = 0;
    const unsigned char *p = (const unsigned char *)s;
    for (size_t i = 0; i < n;) {
        unsigned cp = 0xFFFD;
        int len = 1;
        unsigned char c = p[i];
        if (c < 0x80) { cp = c; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < n && (p[i + 1] & 0xC0) == 0x80) {
            cp = ((c & 0x1Fu) << 6) | (p[i + 1] & 0x3Fu); len = 2;
            if (cp < 0x80) cp = 0xFFFD;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < n && (p[i + 1] & 0xC0) == 0x80 && (p[i + 2] & 0xC0) == 0x80) {
            cp = ((c & 0x0Fu) << 12) | ((p[i + 1] & 0x3Fu) << 6) | (p[i + 2] & 0x3Fu); len = 3;
            if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) cp = 0xFFFD;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < n && (p[i + 1] & 0xC0) == 0x80 && (p[i + 2] & 0xC0) == 0x80
                   && (p[i + 3] & 0xC0) == 0x80) {
            cp = ((c & 0x07u) << 18) | ((p[i + 1] & 0x3Fu) << 12) | ((p[i + 2] & 0x3Fu) << 6) | (p[i + 3] & 0x3Fu);
            len = 4;
            if (cp < 0x10000 || cp > 0x10FFFF) cp = 0xFFFD;
        }
        i += (size_t)len;
        if (cp >= 0x10000) {
            cp -= 0x10000;
            w[o++] = (unsigned short)(0xD800 + (cp >> 10));
            w[o++] = (unsigned short)(0xDC00 + (cp & 0x3FF));
        } else {
            w[o++] = (unsigned short)cp;
        }
    }
    w[o] = 0;
    *count = o;
    return w;
}

static unsigned char *s_data = NULL;
static size_t s_dataLen = 0, s_dataCap = 0;
static unsigned char s_noData[1] = { 0 };

static unsigned char *data_take(size_t n)
{
    s_dataLen = 0;
    if (n > s_dataCap) {
        unsigned char *nd = (unsigned char *)realloc(s_data, n);
        if (!nd) return NULL;
        s_data = nd; s_dataCap = n;
    }
    return s_data;
}

/* ------------------------------------------------------------------ */
/* Page space to view space (see the header).                          */
/* PDFium's FPDF_PageToDevice applies the page's rotation and its crop  */
/* box, and answers in whole device pixels. Asked for a device of 100   */
/* pixels a point, it answers in hundredths of a point.                 */
/* ------------------------------------------------------------------ */
typedef struct { int w100, h100; } pdx_view;

static pdx_view view_of(pdx_doc *d)
{
    pdx_view v;
    double w = (double)p_FPDF_GetPageWidthF(d->page);
    double h = (double)p_FPDF_GetPageHeightF(d->page);
    if (!(w >= 0.01) || w > 1.0e6) w = 1.0;
    if (!(h >= 0.01) || h > 1.0e6) h = 1.0;
    v.w100 = (int)lround(w * 100.0);
    v.h100 = (int)lround(h * 100.0);
    return v;
}

static void to_view(pdx_doc *d, pdx_view v, double px, double py, double *x, double *y)
{
    int dx = 0, dy = 0;
    if (!isfinite(px) || !isfinite(py)
        || !p_FPDF_PageToDevice(d->page, 0, 0, v.w100, v.h100, 0, px, py, &dx, &dy)) {
        *x = 0; *y = 0;
        return;
    }
    *x = dx / 100.0;
    *y = dy / 100.0;
}

static int to_page(pdx_doc *d, pdx_view v, double x, double y, double *px, double *py)
{
    if (!isfinite(x) || !isfinite(y) || fabs(x) > 1.0e6 || fabs(y) > 1.0e6) return 0;
    return p_FPDF_DeviceToPage(d->page, 0, 0, v.w100, v.h100, 0,
                               (int)lround(x * 100.0), (int)lround(y * 100.0), px, py) != 0;
}

/* A rectangle given by two opposite corners in page space, appended as
 * "left,top,right,bottom" in view space. */
static void tb_rect(pdx_doc *d, pdx_view v, double x1, double y1, double x2, double y2)
{
    double ax, ay, bx, by;
    to_view(d, v, x1, y1, &ax, &ay);
    to_view(d, v, x2, y2, &bx, &by);
    tb_num(ax < bx ? ax : bx); tb_char(',');
    tb_num(ay < by ? ay : by); tb_char(',');
    tb_num(ax < bx ? bx : ax); tb_char(',');
    tb_num(ay < by ? by : ay);
}

/* ------------------------------------------------------------------ */
/* The library                                                         */
/* ------------------------------------------------------------------ */
LC_API int pdx_abi_version(void) { return PDX_ABI_VERSION; }

/* "pdfxt ABI 1; PDFium chromium/NNNN". Says what this was BUILT for; whether
 * PDFium is loaded is pdx_is_loaded. */
LC_API const char *pdx_library_version(void)
{
    tb_reset();
    tb_str("pdfxt ABI ");
    tb_int(PDX_ABI_VERSION);
    tb_str("; PDFium ");
    tb_str(PDX_PDFIUM_PIN);
    return tb_result();
}

/* The length in bytes of a text result. There are two texts this file hands
 * out, the result buffer and the error, and the binding measures at once;
 * any other pointer measures 0, never a walk through a stranger's memory. */
LC_API int pdx_text_length(const char *text)
{
    if (!text) return 0;
    if (text == s_error) return (int)strlen(s_error);
    if (text != s_text) return 0;
    return (int)s_textLen;
}

/* The length in bytes of the last bytes result. */
LC_API int pdx_data_length(void) { return (int)s_dataLen; }

/* The binding calls this once it has copied a bytes result: a drawn page is
 * megabytes, and holding the last one for the life of the process is waste.
 * A small buffer is kept for the next call. */
LC_API void pdx_data_release(void)
{
    s_dataLen = 0;
    if (s_dataCap > (1u << 20)) {
        free(s_data);
        s_data = NULL;
        s_dataCap = 0;
    }
}

LC_API const char *pdx_last_error(void)
{
    /* Its own small buffer: reading the error must not disturb a result. */
    return s_error;
}

/* Load PDFium from a folder ("" = the folder pdfxt itself is in, which is
 * what every other call does on first use). 1 when PDFium is ready. */
LC_API int pdx_load(const char *folder)
{
    ok_clear();
    return load_from(folder) ? 1 : 0;
}

LC_API int pdx_is_loaded(void) { return (s_lib && s_inited) ? 1 : 0; }

/* Close every document and shut PDFium down. Idempotent; the next call that
 * needs PDFium starts it again. The library file stays loaded. */
LC_API void pdx_shutdown(void)
{
    ok_clear();
    if (!s_lib) return;
    for (int i = 0; i < s_slots; i++) {
        if (s_docs[i]) doc_free_slot(i);
    }
    if (s_inited) {
        p_FPDF_DestroyLibrary();
        s_inited = 0;
    }
    tb_reset();
    free(s_text); s_text = NULL; s_textCap = 0; s_textLen = 0;
    free(s_data); s_data = NULL; s_dataCap = 0; s_dataLen = 0;
}

/* ------------------------------------------------------------------ */
/* Opening and closing                                                 */
/* ------------------------------------------------------------------ */
static int open_failed(pdx_doc *d)
{
    unsigned long e = p_FPDF_GetLastError();
    free(d->mem);
    if (d->fp) fclose(d->fp);
    free(d);
    switch (e) {
        case FPDF_ERR_FILE:     return fail("the file could not be read");
        case FPDF_ERR_FORMAT:   return fail("not a PDF, or the file is damaged");
        case FPDF_ERR_PASSWORD: return fail("a password is needed, or the one given is wrong");
        case FPDF_ERR_SECURITY: return fail("the document uses a security scheme PDFium does not support");
        default:                return fail("the document could not be opened");
    }
}

static int open_finish(pdx_doc *d)
{
    d->pages = p_FPDF_GetPageCount(d->doc);
    if (d->pages < 0) d->pages = 0;
    int h = doc_add(d);
    if (!h) {
        doc_destroy(d);
        return fail("too many open documents");
    }
    return h;
}

/* PDFium's reader: `size` bytes at `position`, all of them or failure. */
static int read_block(void *param, unsigned long position, unsigned char *buf, unsigned long size)
{
    pdx_doc *d = (pdx_doc *)param;
    if (!d || !d->fp) return 0;
    if (size == 0) return 1;
    if (position > d->access.m_FileLen || size > d->access.m_FileLen - position) return 0;
#if defined(_WIN32)
    if (_fseeki64(d->fp, (__int64)position, SEEK_SET) != 0) return 0;
#else
    if (fseeko(d->fp, (off_t)position, SEEK_SET) != 0) return 0;
#endif
    return fread(buf, 1, (size_t)size, d->fp) == (size_t)size;
}

/* Open a PDF file. path is UTF-8; password may be "". Returns a document
 * handle, or 0 (pdx_last_error says why). The file stays open, and is read
 * as pages are asked for, until pdx_close. */
LC_API int pdx_open(const char *path, const char *password)
{
    ok_clear();
    if (!path || !path[0]) return fail("no file path");
    if (!ready()) return 0;
    FILE *fp;
#if defined(_WIN32)
    wchar_t *w = widen(path);
    if (!w) return fail("the file path is not valid text");
    fp = _wfopen(w, L"rb");
    free(w);
#else
    fp = fopen(path, "rb");
#endif
    if (!fp) return fail("the file could not be opened");
    long long size;
#if defined(_WIN32)
    if (_fseeki64(fp, 0, SEEK_END) != 0) { fclose(fp); return fail("the file could not be read"); }
    size = _ftelli64(fp);
#else
    if (fseeko(fp, 0, SEEK_END) != 0) { fclose(fp); return fail("the file could not be read"); }
    size = (long long)ftello(fp);
#endif
    if (size <= 0) { fclose(fp); return fail("the file is empty or could not be read"); }
    if (size > PDX_MAX_FILE) { fclose(fp); return fail("the file is larger than 2 GB"); }
    pdx_doc *d = (pdx_doc *)calloc(1, sizeof *d);
    if (!d) { fclose(fp); return fail("out of memory"); }
    d->fp = fp;
    d->access.m_FileLen = (unsigned long)size;
    d->access.m_GetBlock = read_block;
    d->access.m_Param = d;
    d->doc = p_FPDF_LoadCustomDocument(&d->access, password ? password : "");
    if (!d->doc) return open_failed(d);
    return open_finish(d);
}

/* Open a PDF held in memory. The bytes are COPIED: the caller's may go. */
LC_API int pdx_open_data(const unsigned char *bytes, int length, const char *password)
{
    ok_clear();
    if (!bytes || length <= 0) return fail("no data");
    if (!ready()) return 0;
    pdx_doc *d = (pdx_doc *)calloc(1, sizeof *d);
    if (!d) return fail("out of memory");
    d->mem = (unsigned char *)malloc((size_t)length);
    if (!d->mem) { free(d); return fail("out of memory"); }
    memcpy(d->mem, bytes, (size_t)length);
    d->doc = p_FPDF_LoadMemDocument64(d->mem, (size_t)length, password ? password : "");
    if (!d->doc) return open_failed(d);
    return open_finish(d);
}

LC_API void pdx_close(int doc)
{
    ok_clear();
    if (!doc_of(doc)) return;
    doc_free_slot((doc & PDX_H_SLOT_MASK) - 1);
}

/* Close every open document; returns how many were open. */
LC_API int pdx_close_all(void)
{
    ok_clear();
    int n = 0;
    for (int i = 0; i < s_slots; i++) {
        if (s_docs[i]) { doc_free_slot(i); n++; }
    }
    return n;
}

LC_API int pdx_open_count(void) { return s_open; }

LC_API int pdx_is_open(int doc) { return doc_of(doc) ? 1 : 0; }

/* ------------------------------------------------------------------ */
/* The document                                                        */
/* ------------------------------------------------------------------ */
LC_API int pdx_page_count(int doc)
{
    pdx_doc *d = doc_of(doc);
    return d ? d->pages : 0;
}

/* The PDF version the file declares, times ten: 17 for PDF 1.7. 0 unknown. */
LC_API int pdx_file_version(int doc)
{
    pdx_doc *d = doc_of(doc);
    int v = 0;
    if (!d || !p_FPDF_GetFileVersion(d->doc, &v)) return 0;
    return v;
}

/* The permission bits of the PDF specification (table 22), as a number:
 * 32 unsigned bits do not fit an int the boundary carries. A document with
 * no security handler answers 4294967295 (everything allowed). */
LC_API double pdx_permissions(int doc)
{
    pdx_doc *d = doc_of(doc);
    if (!d) return 0.0;
    return (double)(p_FPDF_GetDocPermissions(d->doc) & 0xFFFFFFFFul);
}

/* One entry of the document information: Title, Author, Subject, Keywords,
 * Creator, Producer, CreationDate or ModDate. */
LC_API const char *pdx_metadata(int doc, const char *tag)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = doc_of(doc);
    if (!d || !tag || !tag[0] || strlen(tag) > 64) return tb_result();
    unsigned long need = p_FPDF_GetMetaText(d->doc, tag, NULL, 0);
    if (need < 2 || need > PDX_MAX_TEXT) return tb_result();
    unsigned char *buf = (unsigned char *)malloc(need);
    if (!buf) return tb_result();
    unsigned long got = p_FPDF_GetMetaText(d->doc, tag, buf, need);
    if (got >= 2 && got <= need) tb_utf16le_bytes(buf, got, 0);
    free(buf);
    return tb_result();
}

/* The label a page is known by ("iv", "A-3"), or empty when the document
 * gives it none. */
LC_API const char *pdx_page_label(int doc, int pageNo)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = doc_of(doc);
    if (!d || pageNo < 1 || pageNo > d->pages) return tb_result();
    unsigned long need = p_FPDF_GetPageLabel(d->doc, pageNo - 1, NULL, 0);
    if (need < 2 || need > 65536) return tb_result();
    unsigned char *buf = (unsigned char *)malloc(need);
    if (!buf) return tb_result();
    unsigned long got = p_FPDF_GetPageLabel(d->doc, pageNo - 1, buf, need);
    if (got >= 2 && got <= need) tb_utf16le_bytes(buf, got, 1);
    free(buf);
    return tb_result();
}

static int page_size(int doc, int pageNo, double *w, double *h)
{
    pdx_doc *d = doc_of(doc);
    FS_SIZEF size;
    *w = 0; *h = 0;
    if (!d || pageNo < 1 || pageNo > d->pages) return 0;
    if (!p_FPDF_GetPageSizeByIndexF(d->doc, pageNo - 1, &size)) return 0;
    if (!isfinite(size.width) || !isfinite(size.height)) return 0;
    *w = (double)size.width;
    *h = (double)size.height;
    return 1;
}

/* "width,height" in points, as the page is displayed (its rotation applied).
 * Does not load the page, so it is cheap to ask of every page. */
LC_API const char *pdx_page_size(int doc, int pageNo)
{
    double w, h;
    ok_clear();
    tb_reset();
    if (!page_size(doc, pageNo, &w, &h)) return tb_result();
    tb_num(w); tb_char(','); tb_num(h);
    return tb_result();
}

LC_API double pdx_page_width(int doc, int pageNo)
{
    double w, h;
    page_size(doc, pageNo, &w, &h);
    return w;
}

LC_API double pdx_page_height(int doc, int pageNo)
{
    double w, h;
    page_size(doc, pageNo, &w, &h);
    return h;
}

/* The page's own rotation in degrees: 0, 90, 180 or 270. Every other call
 * here already accounts for it; this is for a viewer that wants to say so. */
LC_API int pdx_page_rotation(int doc, int pageNo)
{
    ok_clear();
    pdx_doc *d = page_of(doc, pageNo);
    if (!d) return 0;
    int r = p_FPDFPage_GetRotation(d->page);
    return (r >= 1 && r <= 3) ? r * 90 : 0;
}

/* ------------------------------------------------------------------ */
/* Drawing                                                             */
/* ------------------------------------------------------------------ */
/* The flags a script may pass, PDFium's own values: 1 draw annotations
 * (form fields included), 2 LCD-optimised text, 8 grayscale, 2048 draw for
 * print, 4096 / 8192 / 16384 no smoothing of text / images / paths. Any
 * other bit is dropped: FPDF_REVERSE_BYTE_ORDER would change the bytes this
 * file reorders itself. */
#define PDX_RENDER_FLAGS (0x01 | 0x02 | 0x08 | 0x800 | 0x1000 | 0x2000 | 0x4000)

/* Draw into s_data as BGRx rows, top row first. The page is scaled to
 * zoomW x zoomH and the window width x height is cut from it at left, top. */
static unsigned char *draw(int doc, int pageNo, int zoomW, int zoomH, int left, int top,
                           int width, int height, int flags, size_t extra)
{
    if (!ready()) return NULL;
    if (width < 1 || height < 1 || width > PDX_MAX_SIDE || height > PDX_MAX_SIDE
        || (long long)width * height > PDX_MAX_PIXELS) {
        fail("the size asked for is outside 1 to 16384 pixels a side, 40 million in all");
        return NULL;
    }
    if (zoomW < 1 || zoomH < 1 || zoomW > PDX_MAX_ZOOMED || zoomH > PDX_MAX_ZOOMED
        || left < 0 || top < 0 || left >= zoomW || top >= zoomH) {
        fail("the region asked for is outside the page");
        return NULL;
    }
    pdx_doc *d = page_of(doc, pageNo);
    if (!d) return NULL;
    size_t bytes = (size_t)width * (size_t)height * 4u;
    unsigned char *buf = data_take(bytes + extra);
    if (!buf) { fail("out of memory"); return NULL; }
    FPDF_BITMAP bmp = p_FPDFBitmap_CreateEx(width, height, FPDFBitmap_BGRx, buf, width * 4);
    if (!bmp) { fail("the bitmap could not be made"); return NULL; }
    p_FPDFBitmap_FillRect(bmp, 0, 0, width, height, 0xFFFFFFFFu);      /* white paper */
    p_FPDF_RenderPageBitmap(bmp, d->page, -left, -top, zoomW, zoomH, 0, flags & PDX_RENDER_FLAGS);
    p_FPDFBitmap_Destroy(bmp);                                  /* not our buffer */
    return buf;
}

/* BGRx to the engine's imageData order, in place: 0, red, green, blue. */
static void to_image_data(unsigned char *p, size_t pixels)
{
    for (size_t i = 0; i < pixels; i++, p += 4) {
        unsigned char b = p[0], g = p[1], r = p[2];
        p[0] = 0; p[1] = r; p[2] = g; p[3] = b;
    }
}

/* Draw a whole page into width x height pixels. The result is width *
 * height * 4 bytes in the engine's imageData order, ready for
 * `set the imageData of image`; its length is pdx_data_length. Empty (a
 * length of 0) on failure. */
LC_API const unsigned char *pdx_render_page(int doc, int pageNo, int width, int height, int flags)
{
    ok_clear();
    s_dataLen = 0;
    unsigned char *buf = draw(doc, pageNo, width, height, 0, 0, width, height, flags, 0);
    if (!buf) return s_noData;
    to_image_data(buf, (size_t)width * (size_t)height);
    s_dataLen = (size_t)width * (size_t)height * 4u;
    return buf;
}

/* Draw PART of a page: the page is scaled to zoomWidth x zoomHeight pixels
 * and the window of width x height at left, top is what comes back. A viewer
 * zoomed far in draws only what its window shows. */
LC_API const unsigned char *pdx_render_page_region(int doc, int pageNo, int zoomWidth, int zoomHeight,
                                                   int left, int top, int width, int height, int flags)
{
    ok_clear();
    s_dataLen = 0;
    unsigned char *buf = draw(doc, pageNo, zoomWidth, zoomHeight, left, top, width, height, flags, 0);
    if (!buf) return s_noData;
    to_image_data(buf, (size_t)width * (size_t)height);
    s_dataLen = (size_t)width * (size_t)height * 4u;
    return buf;
}

static void put_le32(unsigned char *p, unsigned v)
{
    p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16); p[3] = (unsigned char)(v >> 24);
}

/* Draw a whole page as a BMP FILE (24 bits, uncompressed): bytes an engine
 * takes as `set the text of image`, or a script writes to disk, with no
 * image of the right size made first. */
LC_API const unsigned char *pdx_render_page_bmp(int doc, int pageNo, int width, int height, int flags)
{
    ok_clear();
    s_dataLen = 0;
    if (width < 1 || height < 1 || width > PDX_MAX_SIDE || height > PDX_MAX_SIDE) {
        fail("the size asked for is outside 1 to 16384 pixels a side, 40 million in all");
        return s_noData;
    }
    size_t row = ((size_t)width * 3u + 3u) & ~(size_t)3u;
    size_t fileBytes = 54u + row * (size_t)height;
    /* The pixels are drawn at the front of the buffer and the file is built
     * behind them, then moved down: one allocation holds both. */
    size_t pixelBytes = (size_t)width * (size_t)height * 4u;
    unsigned char *buf = draw(doc, pageNo, width, height, 0, 0, width, height, flags, fileBytes);
    if (!buf) return s_noData;
    unsigned char *file = buf + pixelBytes;
    memset(file, 0, 54);
    file[0] = 'B'; file[1] = 'M';
    put_le32(file + 2, (unsigned)fileBytes);
    put_le32(file + 10, 54);
    put_le32(file + 14, 40);
    put_le32(file + 18, (unsigned)width);
    put_le32(file + 22, (unsigned)height);          /* positive: bottom row first */
    file[26] = 1; file[28] = 24;
    put_le32(file + 34, (unsigned)(row * (size_t)height));
    put_le32(file + 38, 2835); put_le32(file + 42, 2835);     /* 72 dpi */
    for (int y = 0; y < height; y++) {
        const unsigned char *src = buf + (size_t)(height - 1 - y) * (size_t)width * 4u;
        unsigned char *dst = file + 54 + (size_t)y * row;
        for (int x = 0; x < width; x++) {
            dst[3 * x] = src[4 * x]; dst[3 * x + 1] = src[4 * x + 1]; dst[3 * x + 2] = src[4 * x + 2];
        }
        for (size_t pad = (size_t)width * 3u; pad < row; pad++) dst[pad] = 0;
    }
    memmove(buf, file, fileBytes);
    s_dataLen = fileBytes;
    return buf;
}

/* ------------------------------------------------------------------ */
/* Text                                                                */
/* ------------------------------------------------------------------ */
LC_API int pdx_page_char_count(int doc, int pageNo)
{
    ok_clear();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return 0;
    int n = p_FPDFText_CountChars(d->text);
    return n > 0 ? n : 0;
}

static const char *text_range(int doc, int pageNo, int start, int count, int whole)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return tb_result();
    int total = p_FPDFText_CountChars(d->text);
    if (total <= 0) return tb_result();
    if (whole) { start = 1; count = total; }
    if (start < 1 || start > total || count < 1) return tb_result();
    if (count > total - (start - 1)) count = total - (start - 1);
    unsigned short *w = (unsigned short *)malloc(((size_t)count + 1) * sizeof(unsigned short));
    if (!w) { fail("out of memory"); return tb_result(); }
    int got = p_FPDFText_GetText(d->text, start - 1, count, w);     /* counts the NUL */
    if (got > 1 && got <= count + 1) tb_utf16(w, (size_t)(got - 1), 0);
    free(w);
    return tb_result();
}

/* All the text of a page, lines ended by a line feed. */
LC_API const char *pdx_page_text(int doc, int pageNo)
{
    return text_range(doc, pageNo, 0, 0, 1);
}

/* `count` characters of a page's text from character `start` (1-based). */
LC_API const char *pdx_page_text_range(int doc, int pageNo, int start, int count)
{
    return text_range(doc, pageNo, start, count, 0);
}

/* The text inside a rectangle of the page (view space, see the header). */
LC_API const char *pdx_page_text_in_rect(int doc, int pageNo, double left, double top, double right, double bottom)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return tb_result();
    pdx_view v = view_of(d);
    double ax, ay, bx, by;
    if (!to_page(d, v, left, top, &ax, &ay) || !to_page(d, v, right, bottom, &bx, &by)) {
        fail("the rectangle is not numbers a page can hold");
        return tb_result();
    }
    double l = ax < bx ? ax : bx, r = ax < bx ? bx : ax;
    double b = ay < by ? ay : by, t = ay < by ? by : ay;
    int need = p_FPDFText_GetBoundedText(d->text, l, t, r, b, NULL, 0);
    if (need <= 0 || (unsigned)need > PDX_MAX_TEXT / 4) return tb_result();
    unsigned short *w = (unsigned short *)malloc(((size_t)need + 1) * sizeof(unsigned short));
    if (!w) { fail("out of memory"); return tb_result(); }
    int got = p_FPDFText_GetBoundedText(d->text, l, t, r, b, w, need);
    if (got > 0 && got <= need) {
        while (got > 0 && w[got - 1] == 0) got--;
        tb_utf16(w, (size_t)got, 0);
    }
    free(w);
    return tb_result();
}

/* "left,top,right,bottom" of one character (1-based), or empty. */
LC_API const char *pdx_page_char_box(int doc, int pageNo, int index)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return tb_result();
    double l, r, b, t;
    if (index < 1 || index > p_FPDFText_CountChars(d->text)
        || !p_FPDFText_GetCharBox(d->text, index - 1, &l, &r, &b, &t)) return tb_result();
    tb_rect(d, view_of(d), l, t, r, b);
    return tb_result();
}

/* The character (1-based) at or nearest a point of the page, within
 * `tolerance` points; 0 when there is none. */
LC_API int pdx_page_char_at(int doc, int pageNo, double x, double y, double tolerance)
{
    ok_clear();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return 0;
    double px, py;
    if (!isfinite(tolerance) || tolerance < 0.0 || tolerance > 1.0e4
        || !to_page(d, view_of(d), x, y, &px, &py)) return fail("the point is not numbers a page can hold");
    int i = p_FPDFText_GetCharIndexAtPos(d->text, px, py, tolerance, tolerance);
    return i >= 0 ? i + 1 : 0;
}

/* Every place `needle` occurs in a page's text: one line a match,
 * "start,count" (start 1-based), in reading order. flags: 1 match case,
 * 2 whole words only. */
LC_API const char *pdx_page_search(int doc, int pageNo, const char *needle, int flags)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return tb_result();
    if (!needle || !needle[0]) return tb_result();
    if (strlen(needle) > 4096) { fail("the text to find is longer than 4096 bytes"); return tb_result(); }
    size_t n = 0;
    unsigned short *w = utf8_to_utf16(needle, &n);
    if (!w) { fail("out of memory"); return tb_result(); }
    FPDF_SCHHANDLE s = p_FPDFText_FindStart(d->text, w, (unsigned long)(flags & 3), 0);
    if (s) {
        int found = 0;
        while (found < 100000 && p_FPDFText_FindNext(s)) {
            int at = p_FPDFText_GetSchResultIndex(s);
            int count = p_FPDFText_GetSchCount(s);
            if (at < 0 || count < 1) break;
            if (found++) tb_char('\n');
            tb_int(at + 1); tb_char(','); tb_int(count);
        }
        p_FPDFText_FindClose(s);
    }
    free(w);
    return tb_result();
}

/* The rectangles a run of text covers (a run that wraps covers one a line):
 * one line each, "left,top,right,bottom". What a viewer highlights. */
LC_API const char *pdx_page_text_rects(int doc, int pageNo, int start, int count)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = text_of(doc, pageNo);
    if (!d) return tb_result();
    int total = p_FPDFText_CountChars(d->text);
    if (start < 1 || start > total || count < 1) return tb_result();
    if (count > total - (start - 1)) count = total - (start - 1);
    int rects = p_FPDFText_CountRects(d->text, start - 1, count);
    pdx_view v = view_of(d);
    int out = 0;
    for (int i = 0; i < rects && i < 100000; i++) {
        double l, t, r, b;
        if (!p_FPDFText_GetRect(d->text, i, &l, &t, &r, &b)) continue;
        if (out++) tb_char('\n');
        tb_rect(d, v, l, t, r, b);
    }
    return tb_result();
}

/* ------------------------------------------------------------------ */
/* Outline and links                                                   */
/* ------------------------------------------------------------------ */
/* Where a bookmark or a link leads: a page number (0 none) and, for a web
 * link, its address appended to the text buffer. */
static int target_page(pdx_doc *d, FPDF_DEST dest, FPDF_ACTION action, int wantUri)
{
    int page = 0;
    if (!dest && action && p_FPDFAction_GetType(action) == PDFACTION_GOTO)
        dest = p_FPDFAction_GetDest(d->doc, action);
    if (dest) {
        int i = p_FPDFDest_GetDestPageIndex(d->doc, dest);
        if (i >= 0 && i < d->pages) page = i + 1;
    }
    if (wantUri && action && p_FPDFAction_GetType(action) == PDFACTION_URI) {
        unsigned long need = p_FPDFAction_GetURIPath(d->doc, action, NULL, 0);
        if (need > 1 && need <= 8192) {
            char *buf = (char *)malloc(need);
            if (buf) {
                unsigned long got = p_FPDFAction_GetURIPath(d->doc, action, buf, need);
                if (got > 1 && got <= need) {
                    /* Bytes a file wrote: keep the printable ASCII of a URI
                     * and nothing that could split a line or a field. */
                    for (unsigned long i = 0; i + 1 < got && buf[i]; i++) {
                        unsigned char c = (unsigned char)buf[i];
                        tb_char((c >= 0x21 && c <= 0x7E) ? (char)c : '_');
                    }
                }
                free(buf);
            }
        }
    }
    return page;
}

/* The document's outline (its bookmarks), one line an entry, in reading
 * order: level TAB page TAB title. level is 1 for a top entry; page is 0
 * for an entry that leads nowhere in this document. */
LC_API const char *pdx_outline(int doc)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = doc_of(doc);
    if (!d) return tb_result();
    FPDF_BOOKMARK stack[PDX_MAX_DEPTH];
    int depth = 0, entries = 0;
    FPDF_BOOKMARK cur = p_FPDFBookmark_GetFirstChild(d->doc, NULL);
    while (cur && entries < PDX_MAX_OUTLINE) {
        if (entries++) tb_char('\n');
        tb_int(depth + 1); tb_char('\t');
        tb_int(target_page(d, p_FPDFBookmark_GetDest(d->doc, cur), p_FPDFBookmark_GetAction(cur), 0));
        tb_char('\t');
        unsigned long need = p_FPDFBookmark_GetTitle(cur, NULL, 0);
        if (need >= 2 && need <= 65536) {
            unsigned char *buf = (unsigned char *)malloc(need);
            if (buf) {
                unsigned long got = p_FPDFBookmark_GetTitle(cur, buf, need);
                if (got >= 2 && got <= need) tb_utf16le_bytes(buf, got, 1);
                free(buf);
            }
        }
        /* depth first: a child, else a sibling, else an ancestor's sibling */
        FPDF_BOOKMARK next = (depth < PDX_MAX_DEPTH - 1) ? p_FPDFBookmark_GetFirstChild(d->doc, cur) : NULL;
        if (next) {
            stack[depth++] = cur;
        } else {
            next = p_FPDFBookmark_GetNextSibling(d->doc, cur);
            while (!next && depth > 0) next = p_FPDFBookmark_GetNextSibling(d->doc, stack[--depth]);
        }
        cur = next;
    }
    return tb_result();
}

/* The links of a page, one line each: left,top,right,bottom TAB page TAB
 * address. page is 0 for a link that leaves the document; address is empty
 * for one that stays. */
LC_API const char *pdx_page_links(int doc, int pageNo)
{
    ok_clear();
    tb_reset();
    pdx_doc *d = page_of(doc, pageNo);
    if (!d) return tb_result();
    pdx_view v = view_of(d);
    int pos = 0, out = 0;
    FPDF_LINK link = NULL;
    while (out < 100000 && p_FPDFLink_Enumerate(d->page, &pos, &link)) {
        FS_RECTF r;
        if (!link || !p_FPDFLink_GetAnnotRect(link, &r)) continue;
        if (out++) tb_char('\n');
        tb_rect(d, v, r.left, r.top, r.right, r.bottom);
        tb_char('\t');
        /* The page first, the address after it: the address is appended by
         * target_page, so the page number is written in between. */
        FPDF_DEST dest = p_FPDFLink_GetDest(d->doc, link);
        FPDF_ACTION action = p_FPDFLink_GetAction(link);
        tb_int(target_page(d, dest, action, 0));
        tb_char('\t');
        target_page(d, NULL, action, 1);
    }
    return tb_result();
}
