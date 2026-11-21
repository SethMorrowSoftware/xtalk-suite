/*
 * smoke_test.c - every export of src/pdfium_shim.c, driven through the real
 * PDFium that the build placed beside the library.
 *
 * The PDF files are the ones tools/build-test-pdfs.py writes (carried here
 * as tests/fixtures.h and written to temporary files), so every number
 * asserted below is a number written in that script: read its header beside
 * this file.
 *
 * What is held:
 *   - with PDFium absent, nothing crashes: every call answers 0 or empty and
 *     the error says where it looked (asked first, before PDFium is loaded);
 *   - opening by path and from memory, a password, the refusals (a missing
 *     file, an empty one, a file that is not a PDF, a truncated one);
 *   - sizes, rotation, labels, the information entries (UTF-16 to UTF-8);
 *   - drawing: imageData byte order, a region equal to the same window of a
 *     full drawing, the BMP file, the limits;
 *   - a filled-in form: its field drawn with flag 1 only, by PDFium's form
 *     module over the page, in all three drawings;
 *   - text: all of it, a range, a rectangle, a character's box, the
 *     character at a point, searching, the rectangles of a run;
 *   - the outline and the links, on a plain page and a rotated one;
 *   - handles: a closed handle stays dead through thousands of reuses, the
 *     document limit is a refusal, shutdown and start again.
 *
 * Prints one line a failure and a last line "pdfxt smoke: N passed, M
 * failed"; exits with the number of failures.
 *
 * Android. PDFium's builders target Android 6.0 (API 23), and the suite's
 * emulator is Android 5.0. On a device BELOW API 23 where PDFium does not
 * load, the checks that need it are skipped, said out loud, and only then:
 * on any other system a PDFium that does not load is a failure.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
#endif
#if defined(__ANDROID__)
    #include <sys/system_properties.h>
#endif

#include "fixtures.h"

/* >>> BEGIN DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
int pdx_abi_version(void);
const char *pdx_library_version(void);
int pdx_text_length(const char *text);
int pdx_data_length(void);
void pdx_data_release(void);
const char *pdx_last_error(void);
int pdx_load(const char *folder);
int pdx_is_loaded(void);
void pdx_shutdown(void);
int pdx_open(const char *path, const char *password);
int pdx_open_data(const unsigned char *bytes, int length, const char *password);
void pdx_close(int doc);
int pdx_close_all(void);
int pdx_open_count(void);
int pdx_is_open(int doc);
int pdx_page_count(int doc);
int pdx_file_version(int doc);
double pdx_permissions(int doc);
const char *pdx_metadata(int doc, const char *tag);
const char *pdx_page_label(int doc, int pageNo);
const char *pdx_page_size(int doc, int pageNo);
double pdx_page_width(int doc, int pageNo);
double pdx_page_height(int doc, int pageNo);
int pdx_page_rotation(int doc, int pageNo);
const unsigned char *pdx_render_page(int doc, int pageNo, int width, int height, int flags);
const unsigned char *pdx_render_page_region(int doc, int pageNo, int zoomWidth, int zoomHeight, int left, int top, int width, int height, int flags);
const unsigned char *pdx_render_page_bmp(int doc, int pageNo, int width, int height, int flags);
int pdx_page_char_count(int doc, int pageNo);
const char *pdx_page_text(int doc, int pageNo);
const char *pdx_page_text_range(int doc, int pageNo, int start, int count);
const char *pdx_page_text_in_rect(int doc, int pageNo, double left, double top, double right, double bottom);
const char *pdx_page_char_box(int doc, int pageNo, int index);
int pdx_page_char_at(int doc, int pageNo, double x, double y, double tolerance);
const char *pdx_page_search(int doc, int pageNo, const char *needle, int flags);
const char *pdx_page_text_rects(int doc, int pageNo, int start, int count);
const char *pdx_outline(int doc);
const char *pdx_page_links(int doc, int pageNo);
/* <<< END DECLARATIONS <<< */

static int s_passed = 0, s_failed = 0;

static void check_at(int line, int ok, const char *what, const char *detail)
{
    if (ok) { s_passed++; return; }
    s_failed++;
    printf("FAIL (line %d) %s [%s]\n", line, what, detail ? detail : "");
}
#define CHECK(cond, what) check_at(__LINE__, (cond) != 0, what, pdx_last_error())
#define CHECK_TEXT(got, want, what) do {                                    \
        const char *g_ = (got);                                             \
        char copy_[512];                                                    \
        snprintf(copy_, sizeof copy_, "%s", g_);                            \
        check_at(__LINE__, strcmp(copy_, (want)) == 0, what, copy_);        \
    } while (0)

/* A text result's length must be what strlen says (the binding measures
 * with pdx_text_length and copies that many bytes). */
static int length_agrees(const char *t)
{
    return pdx_text_length(t) == (int)strlen(t);
}

static char s_dir[1024];
static char s_basic[1200], s_locked[1200], s_unicode[1200], s_scratch[1200];

static FILE *open_utf8(const char *path, const char *mode)
{
#if defined(_WIN32)
    wchar_t wpath[1200], wmode[8];
    if (!MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1200)) return NULL;
    if (!MultiByteToWideChar(CP_UTF8, 0, mode, -1, wmode, 8)) return NULL;
    return _wfopen(wpath, wmode);
#else
    return fopen(path, mode);
#endif
}

static int write_file(const char *path, const unsigned char *bytes, size_t n)
{
    FILE *f = open_utf8(path, "wb");
    if (!f) return 0;
    size_t w = n ? fwrite(bytes, 1, n, f) : 0;
    fclose(f);
    return w == n;
}

static void remove_utf8(const char *path)
{
#if defined(_WIN32)
    wchar_t wpath[1200];
    if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1200)) _wremove(wpath);
#else
    remove(path);
#endif
}

/* four numbers out of "a,b,c,d" */
static int four(const char *t, double *v)
{
    return sscanf(t, "%lf,%lf,%lf,%lf", &v[0], &v[1], &v[2], &v[3]) == 4;
}
static int between(double v, double lo, double hi) { return v >= lo && v <= hi; }

/* one pixel of an imageData result: 0, red, green, blue */
static int pixel_is(const unsigned char *data, int width, int x, int y, int r, int g, int b)
{
    const unsigned char *p = data + ((size_t)y * (size_t)width + (size_t)x) * 4u;
    return p[0] == 0 && p[1] == r && p[2] == g && p[3] == b;
}

/* ------------------------------------------------------------------ */
static void test_without_pdfium(void)
{
    /* Nothing has loaded PDFium yet: these answer from the shim alone. */
    CHECK(pdx_abi_version() == 1, "ABI is 1");
    CHECK(strncmp(pdx_library_version(), "pdfxt ABI 1; PDFium chromium/", 29) == 0, "version text");
    CHECK(length_agrees(pdx_library_version()), "the version text is measured");
    CHECK(pdx_text_length(NULL) == 0 && pdx_text_length("a stranger") == 0, "a pointer that is not the buffer measures 0");
    CHECK(pdx_is_loaded() == 0, "PDFium is not loaded before first use");
    CHECK(pdx_open_count() == 0 && pdx_is_open(1) == 0 && pdx_page_count(1) == 0, "no document yet");

    /* A folder with no PDFium in it: a refusal that names the folder. */
    CHECK(pdx_load(s_dir[0] ? "/no/such/folder/for-pdfxt" : "/no/such/folder/for-pdfxt") == 0, "loading from an empty folder fails");
    CHECK(strstr(pdx_last_error(), "for-pdfxt") != NULL, "and the error names the folder");
    CHECK(length_agrees(pdx_last_error()) && pdx_text_length(pdx_last_error()) > 20, "the error text is measured too");
    CHECK(pdx_is_loaded() == 0, "a failed load loads nothing");
    char huge[5000];
    memset(huge, 'a', sizeof huge - 1);
    huge[sizeof huge - 1] = 0;
    CHECK(pdx_load(huge) == 0 && pdx_last_error()[0] != 0, "a folder path too long to be one is refused");
    pdx_shutdown();                       /* nothing loaded: a no-op */
    pdx_data_release();
    CHECK(pdx_data_length() == 0, "no data yet");
}

static void test_refusals(void)
{
    CHECK(pdx_open("", "") == 0 && pdx_last_error()[0] != 0, "an empty path is refused");
    CHECK(pdx_open(NULL, NULL) == 0, "a null path is refused");
    snprintf(s_scratch, sizeof s_scratch, "%s/pdfxt-no-such-file.pdf", s_dir);
    CHECK(pdx_open(s_scratch, "") == 0 && strstr(pdx_last_error(), "could not be opened") != NULL, "a missing file is refused");

    snprintf(s_scratch, sizeof s_scratch, "%s/pdfxt-smoke-scratch.pdf", s_dir);
    CHECK(write_file(s_scratch, (const unsigned char *)"", 0), "scratch file written");
    CHECK(pdx_open(s_scratch, "") == 0 && strstr(pdx_last_error(), "empty") != NULL, "an empty file is refused");

    unsigned char junk[2048];
    for (size_t i = 0; i < sizeof junk; i++) junk[i] = (unsigned char)(i * 7 + 3);
    CHECK(write_file(s_scratch, junk, sizeof junk), "scratch file written");
    CHECK(pdx_open(s_scratch, "") == 0 && strstr(pdx_last_error(), "not a PDF") != NULL, "a file that is not a PDF is refused");
    CHECK(pdx_open_data(junk, (int)sizeof junk, "") == 0, "bytes that are not a PDF are refused");
    CHECK(pdx_open_data(NULL, 10, "") == 0 && pdx_open_data(junk, 0, "") == 0 && pdx_open_data(junk, -5, "") == 0,
          "no bytes, or a length that is not one, is refused");

    /* Truncated at every hundredth byte: PDFium may refuse it or repair
     * what is left; either way nothing crashes and a handle, if one comes
     * back, works and closes. */
    for (size_t cut = 100; cut < sizeof k_basic_pdf; cut += 100) {
        int h = pdx_open_data(k_basic_pdf, (int)cut, "");
        if (h) {
            int pages = pdx_page_count(h);
            for (int p = 1; p <= pages && p <= 3; p++) {
                (void)pdx_page_text(h, p);
                (void)pdx_render_page(h, p, 40, 40, 0);
            }
            (void)pdx_outline(h);
            pdx_close(h);
        }
    }
    CHECK(pdx_open_count() == 0, "nothing left open by the truncated files");
    remove_utf8(s_scratch);
}

static void test_document(void)
{
    int d = pdx_open(s_basic, "");
    CHECK(d > 0, "basic.pdf opens");
    CHECK(pdx_last_error()[0] == 0, "and leaves no error");
    CHECK(pdx_is_loaded() == 1, "opening loaded PDFium");
    CHECK(pdx_is_open(d) == 1 && pdx_open_count() == 1, "it is open");
    CHECK(pdx_page_count(d) == 3, "three pages");
    CHECK(pdx_file_version(d) == 14, "PDF 1.4");
    CHECK(pdx_permissions(d) == 4294967295.0, "no security handler: every permission");

    CHECK_TEXT(pdx_metadata(d, "Title"), "pdfxt test file", "Title");
    CHECK(length_agrees(pdx_metadata(d, "Title")), "a text result is measured");
    CHECK_TEXT(pdx_metadata(d, "Author"), "xTalk Suite", "Author");
    CHECK_TEXT(pdx_metadata(d, "Subject"), "Subject with \xCE\xA9", "a UTF-16 Subject comes back as UTF-8");
    CHECK_TEXT(pdx_metadata(d, "Keywords"), "", "an entry the file lacks is empty");
    CHECK_TEXT(pdx_metadata(d, ""), "", "an empty tag is empty");
    CHECK_TEXT(pdx_metadata(d, NULL), "", "a null tag is empty");

    CHECK_TEXT(pdx_page_label(d, 1), "i", "page 1 is labelled i");
    CHECK_TEXT(pdx_page_label(d, 2), "1", "page 2 is labelled 1");
    CHECK_TEXT(pdx_page_label(d, 3), "2", "page 3 is labelled 2");
    CHECK_TEXT(pdx_page_label(d, 4), "", "no page 4, no label");

    CHECK_TEXT(pdx_page_size(d, 1), "612,792", "page 1 is US Letter");
    CHECK_TEXT(pdx_page_size(d, 2), "842,595", "page 2 is A4 turned a quarter: its DISPLAYED size");
    CHECK_TEXT(pdx_page_size(d, 3), "200,100", "page 3");
    CHECK_TEXT(pdx_page_size(d, 0), "", "no page 0");
    CHECK_TEXT(pdx_page_size(d, 4), "", "no page 4");
    CHECK(pdx_page_width(d, 1) == 612.0 && pdx_page_height(d, 1) == 792.0, "width and height as numbers");
    CHECK(pdx_page_width(d, 2) == 842.0 && pdx_page_height(d, 2) == 595.0, "of the rotated page too");
    CHECK(pdx_page_width(d, 9) == 0.0 && pdx_page_height(d, -1) == 0.0, "0 for a page that is not there");
    CHECK(pdx_page_rotation(d, 1) == 0 && pdx_page_rotation(d, 2) == 90 && pdx_page_rotation(d, 3) == 0, "rotation in degrees");
    CHECK(pdx_page_rotation(d, 7) == 0 && pdx_last_error()[0] != 0, "a page that is not there says so");

    /* the same file from memory, and with a path that is not ASCII */
    int m = pdx_open_data(k_basic_pdf, (int)sizeof k_basic_pdf, "");
    CHECK(m > 0 && m != d && pdx_page_count(m) == 3 && pdx_open_count() == 2, "the same bytes open from memory");
    CHECK_TEXT(pdx_metadata(m, "Title"), "pdfxt test file", "and read the same");
    int u = pdx_open(s_unicode, "");
    CHECK(u > 0 && pdx_page_count(u) == 3, "a path with letters outside ASCII opens (UTF-8)");
    pdx_close(u);
    pdx_close(m);
    CHECK(pdx_is_open(m) == 0 && pdx_is_open(d) == 1 && pdx_open_count() == 1, "closing one leaves the other");
    pdx_close(m);                          /* twice: harmless */
    CHECK(pdx_page_count(m) == 0 && pdx_page_text(m, 1)[0] == 0, "a closed handle reads as nothing");
    pdx_close(d);
    CHECK(pdx_open_count() == 0, "all closed");
}

static void test_password(void)
{
    CHECK(pdx_open(s_locked, "") == 0 && strstr(pdx_last_error(), "password") != NULL, "a locked file needs its password");
    CHECK(pdx_open(s_locked, "wrong") == 0 && strstr(pdx_last_error(), "password") != NULL, "a wrong password is refused");
    CHECK(pdx_open_data(k_locked_pdf, (int)sizeof k_locked_pdf, NULL) == 0, "from memory too");
    int d = pdx_open(s_locked, "secret");
    CHECK(d > 0 && pdx_page_count(d) == 1, "the user password opens it");
    CHECK_TEXT(pdx_page_text(d, 1), "Hello pdfxt\nsecond line of page one", "and its text is decrypted");
    CHECK_TEXT(pdx_metadata(d, "Title"), "locked pdfxt test file", "and its information");
    CHECK(pdx_permissions(d) == 4294967288.0, "printing is not allowed: bit 3 is clear");
    pdx_close(d);
    d = pdx_open_data(k_locked_pdf, (int)sizeof k_locked_pdf, "owner");
    CHECK(d > 0, "the owner password opens it");
    CHECK(pdx_permissions(d) == 4294967295.0 || pdx_permissions(d) == 4294967292.0, "and grants everything");
    pdx_close(d);
}

static void test_drawing(void)
{
    int d = pdx_open(s_basic, "");
    const unsigned char *px = pdx_render_page(d, 1, 612, 792, 0);
    CHECK(pdx_data_length() == 612 * 792 * 4, "a page at one pixel a point is width x height x 4 bytes");
    /* the red square is 100..200 from the left and 100..200 from the BOTTOM */
    CHECK(pixel_is(px, 612, 150, 642, 255, 0, 0), "red where the square is, in imageData order (0,R,G,B)");
    CHECK(pixel_is(px, 612, 105, 597, 255, 0, 0) && pixel_is(px, 612, 195, 687, 255, 0, 0), "to its corners");
    CHECK(pixel_is(px, 612, 95, 642, 255, 255, 255) && pixel_is(px, 612, 150, 700, 255, 255, 255), "white paper beside it");
    CHECK(pixel_is(px, 612, 10, 10, 255, 255, 255), "white paper in the corner");

    /* Twice the size, and a window of it: byte for byte the same pixels. */
    size_t fullBytes = (size_t)1224 * 1584 * 4;
    unsigned char *full = (unsigned char *)malloc(fullBytes);
    px = pdx_render_page(d, 1, 1224, 1584, 0);
    CHECK(pdx_data_length() == (int)fullBytes && full != NULL, "twice the size");
    if (full && pdx_data_length() == (int)fullBytes) {
        memcpy(full, px, fullBytes);
        const unsigned char *part = pdx_render_page_region(d, 1, 1224, 1584, 150, 1150, 300, 280, 0);
        CHECK(pdx_data_length() == 300 * 280 * 4, "a region is its own width x height x 4");
        int same = pdx_data_length() == 300 * 280 * 4;
        for (int y = 0; same && y < 280; y++) {
            if (memcmp(part + (size_t)y * 300 * 4, full + ((size_t)(1150 + y) * 1224 + 150) * 4, 300 * 4) != 0) same = 0;
        }
        CHECK(same, "a region is the same pixels as that window of the whole page");
        CHECK(pixel_is(part, 300, 150, 140, 255, 0, 0) && pixel_is(part, 300, 10, 10, 255, 255, 255), "red square, white margin");
    }
    free(full);

    /* The rotated page displays 842 wide; its blue square (0..50 of PDF
     * space) is at the TOP left of what is displayed. */
    px = pdx_render_page(d, 2, 842, 595, 0);
    CHECK(pdx_data_length() == 842 * 595 * 4, "the rotated page");
    CHECK(pixel_is(px, 842, 25, 25, 0, 0, 255), "its blue square is top left once rotated");
    CHECK(pixel_is(px, 842, 800, 25, 255, 255, 255) && pixel_is(px, 842, 25, 560, 255, 255, 255), "and nowhere else");

    /* grayscale: the red square is some gray */
    px = pdx_render_page(d, 1, 306, 396, 8);
    {
        const unsigned char *p = px + ((size_t)321 * 306 + 75) * 4u;
        CHECK(pdx_data_length() == 306 * 396 * 4 && p[1] == p[2] && p[2] == p[3] && p[1] > 20 && p[1] < 235, "flag 8 draws in gray");
    }
    /* a flag this file does not pass on (reverse byte order) changes nothing */
    px = pdx_render_page(d, 1, 306, 396, 0x10);
    CHECK(pixel_is(px, 306, 75, 321, 255, 0, 0), "an unknown flag is dropped, the byte order stays");

    /* the BMP file */
    const unsigned char *bmp = pdx_render_page_bmp(d, 1, 613, 792, 0);
    size_t row = (613u * 3u + 3u) & ~3u;
    CHECK(pdx_data_length() == (int)(54 + row * 792), "a BMP is a 54-byte header and padded rows");
    CHECK(bmp[0] == 'B' && bmp[1] == 'M' && bmp[10] == 54 && bmp[14] == 40 && bmp[28] == 24, "its header");
    CHECK((bmp[18] | (bmp[19] << 8)) == 613 && (bmp[22] | (bmp[23] << 8)) == 792, "its size");
    CHECK(((unsigned)bmp[2] | ((unsigned)bmp[3] << 8) | ((unsigned)bmp[4] << 16)) == (unsigned)(54 + row * 792), "its length");
    {
        /* bottom row first, blue green red: the pixel 150 across, 642 down */
        const unsigned char *p = bmp + 54 + (size_t)(792 - 1 - 642) * row + 150 * 3;
        CHECK(p[0] == 0 && p[1] == 0 && p[2] == 255, "red where the square is, as B G R from the bottom up");
        p = bmp + 54 + (size_t)(792 - 1 - 10) * row + 10 * 3;
        CHECK(p[0] == 255 && p[1] == 255 && p[2] == 255, "white paper");
    }
    pdx_data_release();
    CHECK(pdx_data_length() == 0, "released");

    /* the limits: each a refusal with a reason and an empty result */
    (void)pdx_render_page(d, 1, 0, 100, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "a width of 0 is refused");
    (void)pdx_render_page(d, 1, 100, -3, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "a negative height is refused");
    (void)pdx_render_page(d, 1, 16385, 10, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "a side above 16384 is refused");
    (void)pdx_render_page(d, 1, 10000, 10000, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "more than 40 million pixels is refused");
    (void)pdx_render_page_bmp(d, 1, 10000, 10000, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "as a BMP too");
    (void)pdx_render_page_bmp(d, 1, 0, 0, 0);
    CHECK(pdx_data_length() == 0, "a BMP of no size is refused");
    (void)pdx_render_page(d, 4, 100, 100, 0);
    CHECK(pdx_data_length() == 0 && strstr(pdx_last_error(), "no such page") != NULL, "a page that is not there");
    (void)pdx_render_page(0, 1, 100, 100, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "a handle that is not one");
    (void)pdx_render_page_region(d, 1, 1000, 1000, 1000, 0, 10, 10, 0);
    CHECK(pdx_data_length() == 0 && pdx_last_error()[0] != 0, "a region that starts off the page is refused");
    (void)pdx_render_page_region(d, 1, 1000, 1000, -1, 0, 10, 10, 0);
    CHECK(pdx_data_length() == 0, "a negative left is refused");
    (void)pdx_render_page_region(d, 1, 2000000, 1000, 0, 0, 10, 10, 0);
    CHECK(pdx_data_length() == 0, "a zoom above a million pixels is refused");
    (void)pdx_render_page_region(d, 1, 0, 0, 0, 0, 10, 10, 0);
    CHECK(pdx_data_length() == 0, "a zoom of nothing is refused");
    /* a region that runs off the far edge is drawn: the rest is paper */
    px = pdx_render_page_region(d, 1, 612, 792, 600, 780, 50, 50, 0);
    CHECK(pdx_data_length() == 50 * 50 * 4 && pixel_is(px, 50, 40, 40, 255, 255, 255), "a region past the far edge is paper");
    /* a far zoom of a small window, the kind a viewer asks for */
    px = pdx_render_page_region(d, 1, 612000, 792000, 150000, 642000, 64, 64, 0);
    CHECK(pdx_data_length() == 64 * 64 * 4 && pixel_is(px, 64, 32, 32, 255, 0, 0), "a thousandfold zoom into the square is red");
    /* flag 1 on a document with no form: the page as before */
    px = pdx_render_page(d, 1, 612, 792, 1);
    CHECK(pixel_is(px, 612, 150, 642, 255, 0, 0) && pixel_is(px, 612, 10, 10, 255, 255, 255), "flag 1 with no form draws the page as before");
    pdx_close(d);
}

/* A filled-in form (form.pdf): PDFium leaves a form's fields out of a page
 * drawing, so they are drawn by its form module over the page, with flag 1
 * only, in each of the three drawings. The field's box is 20..180 across
 * and 40..80 down at one pixel a point, all pure green. */
static void test_forms(void)
{
    int d = pdx_open_data(k_form_pdf, (int)sizeof k_form_pdf, "");
    CHECK(d > 0, "the form opens");
    const unsigned char *px = pdx_render_page(d, 1, 200, 100, 0);
    CHECK(pdx_data_length() == 200 * 100 * 4 && pixel_is(px, 200, 170, 45, 255, 255, 255),
          "without flag 1 the form field is not drawn: paper where it is");
    px = pdx_render_page(d, 1, 200, 100, 1);
    CHECK(pdx_data_length() == 200 * 100 * 4 && pixel_is(px, 200, 170, 45, 0, 255, 0)
          && pixel_is(px, 200, 23, 77, 0, 255, 0), "flag 1 draws the form field: its box is green");
    CHECK(pixel_is(px, 200, 170, 36, 255, 255, 255) && pixel_is(px, 200, 185, 45, 255, 255, 255)
          && pixel_is(px, 200, 170, 84, 255, 255, 255), "and nothing beyond its box");
    px = pdx_render_page(d, 1, 200, 100, 0);
    CHECK(pixel_is(px, 200, 170, 45, 255, 255, 255), "flag 0 again: not drawn again");

    /* twice the size, a window over the field's right end (the field is
     * 40..360 across and 80..160 down there) */
    px = pdx_render_page_region(d, 1, 400, 200, 300, 60, 80, 60, 1);
    CHECK(pdx_data_length() == 80 * 60 * 4 && pixel_is(px, 80, 30, 40, 0, 255, 0), "a region draws the field too");
    CHECK(pixel_is(px, 80, 70, 40, 255, 255, 255) && pixel_is(px, 80, 30, 10, 255, 255, 255), "where it is and only there");

    /* the BMP file: bottom row first, blue green red */
    const unsigned char *bmp = pdx_render_page_bmp(d, 1, 200, 100, 1);
    CHECK(pdx_data_length() == 54 + 600 * 100, "a BMP of the form");
    if (pdx_data_length() == 54 + 600 * 100) {
        const unsigned char *p = bmp + 54 + (size_t)(100 - 1 - 45) * 600 + 170 * 3;
        CHECK(p[0] == 0 && p[1] == 255 && p[2] == 0, "the BMP has the field");
    }

    /* gray: the green box is some gray */
    px = pdx_render_page(d, 1, 200, 100, 1 | 8);
    {
        const unsigned char *p = px + ((size_t)45 * 200 + 170) * 4u;
        CHECK(p[1] == p[2] && p[2] == p[3] && p[1] > 20 && p[1] < 235, "flag 8 draws the field in gray too");
    }

    /* the value a field holds is not text of the page */
    CHECK_TEXT(pdx_page_text(d, 1), "Name:", "the page's text is its own, not the field's value");

    /* a page told to the form module, then its text, then closed; and a form
     * opened and closed without a drawing (the sanitizers watch both) */
    (void)pdx_render_page(d, 1, 50, 25, 1);
    CHECK(pdx_page_char_count(d, 1) == 5, "text after a drawing with the form");
    pdx_close(d);
    d = pdx_open_data(k_form_pdf, (int)sizeof k_form_pdf, "");
    CHECK(d > 0 && pdx_page_count(d) == 1, "opened again");
    pdx_close(d);
    for (int i = 0; i < 50; i++) {
        d = pdx_open_data(k_form_pdf, (int)sizeof k_form_pdf, "");
        (void)pdx_render_page(d, 1, 20, 10, 1);
        pdx_close(d);
    }
    CHECK(pdx_open_count() == 0, "fifty forms drawn and closed");
}

static void test_text(void)
{
    int d = pdx_open(s_basic, "");
    double v[4];
    CHECK(pdx_page_char_count(d, 1) == 36, "page 1 has 36 characters (two lines and the break between)");
    CHECK_TEXT(pdx_page_text(d, 1), "Hello pdfxt\nsecond line of page one", "all the text of page 1, lines ended by a line feed");
    CHECK(length_agrees(pdx_page_text(d, 1)), "measured");
    CHECK_TEXT(pdx_page_text(d, 2), "Rotated page two", "page 2");
    CHECK_TEXT(pdx_page_text(d, 3), "caf\xC3\xA9 na\xC3\xAFve\nneedle Needle needle", "accented letters come back as UTF-8");
    CHECK(length_agrees(pdx_page_text(d, 3)), "and are measured in bytes");
    CHECK_TEXT(pdx_page_text(d, 4), "", "no page 4");
    CHECK(pdx_page_char_count(d, 4) == 0 && pdx_page_char_count(0, 1) == 0, "nor characters on it");

    CHECK_TEXT(pdx_page_text_range(d, 1, 1, 5), "Hello", "a range from the first character");
    CHECK_TEXT(pdx_page_text_range(d, 1, 7, 5), "pdfxt", "a range inside");
    CHECK_TEXT(pdx_page_text_range(d, 1, 30, 1000), "age one", "a range past the end stops at the end (the line break is two characters)");
    CHECK_TEXT(pdx_page_text_range(d, 1, 0, 5), "", "character 0 is not one");
    CHECK_TEXT(pdx_page_text_range(d, 1, 37, 1), "", "nor one past the last");
    CHECK_TEXT(pdx_page_text_range(d, 1, 3, 0), "", "nor a count of 0");
    CHECK_TEXT(pdx_page_text_range(d, 1, 3, -2), "", "nor a negative count");
    CHECK_TEXT(pdx_page_text_range(d, 3, 4, 1), "\xC3\xA9", "one accented character is one character");

    /* "Hello pdfxt" is 24 pt at 72 from the left with its baseline 72 from
     * the top; the H is the first character. */
    CHECK(four(pdx_page_char_box(d, 1, 1), v), "a character's box is four numbers");
    CHECK(between(v[0], 72, 77) && between(v[2], 85, 95) && between(v[1], 50, 60) && between(v[3], 70, 73.5),
          "the H sits on its baseline, 72 points down, left,top,right,bottom");
    CHECK(v[0] < v[2] && v[1] < v[3], "left of right, top above bottom");
    CHECK_TEXT(pdx_page_char_box(d, 1, 0), "", "no box for character 0");
    CHECK_TEXT(pdx_page_char_box(d, 1, 999), "", "nor for one past the end");
    CHECK(pdx_page_char_at(d, 1, (v[0] + v[2]) / 2, (v[1] + v[3]) / 2, 2) == 1, "the character at the middle of the H is 1");
    CHECK(pdx_page_char_at(d, 1, 400, 400, 2) == 0, "nothing in the empty middle of the page");
    CHECK(pdx_page_char_at(d, 1, 1e300, 5, 2) == 0 && pdx_last_error()[0] != 0, "a point no page holds is refused");
    CHECK(pdx_page_char_at(d, 1, 80, 60, -1) == 0, "a negative tolerance is refused");
    CHECK(pdx_page_char_at(d, 1, NAN, 60, 1) == 0, "not-a-number is refused");

    CHECK_TEXT(pdx_page_text_in_rect(d, 1, 0, 0, 612, 80), "Hello pdfxt", "the text in the top band is the first line");
    CHECK(strstr(pdx_page_text_in_rect(d, 1, 0, 85, 612, 792), "second line") != NULL
          && strstr(pdx_page_text_in_rect(d, 1, 0, 85, 612, 792), "Hello") == NULL, "below it, the second");
    CHECK_TEXT(pdx_page_text_in_rect(d, 1, 300, 300, 400, 400), "", "nothing in an empty rectangle");
    CHECK_TEXT(pdx_page_text_in_rect(d, 1, 612, 80, 0, 0), "Hello pdfxt", "the corners in either order");
    CHECK_TEXT(pdx_page_text_in_rect(d, 1, 0, 0, INFINITY, 80), "", "infinity is refused");
    /* on the rotated page: its text runs DOWN the display near x = 400 */
    CHECK_TEXT(pdx_page_text_in_rect(d, 2, 0, 0, 842, 595), "Rotated page two", "the rotated page's text, by its displayed rectangle");
    CHECK(four(pdx_page_char_box(d, 2, 1), v) && between(v[0], 380, 405) && between(v[1], 95, 105),
          "the rotated R is where the display has it");

    CHECK_TEXT(pdx_page_search(d, 1, "pdfxt", 0), "7,5", "a word is found: start,count");
    CHECK_TEXT(pdx_page_search(d, 3, "needle", 0), "13,6\n20,6\n27,6", "three matches without case, a line each");
    CHECK_TEXT(pdx_page_search(d, 3, "needle", 1), "13,6\n27,6", "two with case");
    CHECK_TEXT(pdx_page_search(d, 3, "need", 2), "", "none as a whole word");
    CHECK_TEXT(pdx_page_search(d, 3, "caf\xC3\xA9", 0), "1,4", "an accented word is found from UTF-8");
    CHECK_TEXT(pdx_page_search(d, 1, "absent", 0), "", "a word that is not there");
    CHECK_TEXT(pdx_page_search(d, 1, "", 0), "", "nothing to find");
    CHECK_TEXT(pdx_page_search(d, 1, NULL, 0), "", "null to find");
    CHECK_TEXT(pdx_page_search(d, 1, "\xFF\xFE\xC3", 0), "", "bytes that are not UTF-8 find nothing and break nothing");
    {
        char longNeedle[5000];
        memset(longNeedle, 'x', sizeof longNeedle - 1);
        longNeedle[sizeof longNeedle - 1] = 0;
        CHECK(pdx_page_search(d, 1, longNeedle, 0)[0] == 0 && pdx_last_error()[0] != 0, "a needle over 4096 bytes is refused");
    }

    CHECK(four(pdx_page_text_rects(d, 1, 7, 5), v), "the rectangle of a found word");
    CHECK(between(v[0], 125, 150) && between(v[2], 180, 215) && between(v[1], 48, 62) && between(v[3], 70, 80),
          "is where the word is drawn");
    {
        /* both lines: two rectangles, the second lower */
        char both[256];
        double w[4];
        snprintf(both, sizeof both, "%s", pdx_page_text_rects(d, 1, 1, 36));
        char *second = strchr(both, '\n');
        CHECK(second != NULL && strchr(second + 1, '\n') == NULL, "a run over two lines covers two rectangles");
        CHECK(second && four(both, v) && four(second + 1, w) && w[1] > v[3] - 1, "the second below the first");
    }
    CHECK_TEXT(pdx_page_text_rects(d, 1, 0, 5), "", "no rectangles from character 0");
    CHECK_TEXT(pdx_page_text_rects(d, 1, 5, 0), "", "nor for a count of 0");
    pdx_close(d);
}

static void test_outline_and_links(void)
{
    int d = pdx_open(s_basic, "");
    CHECK_TEXT(pdx_outline(d),
               "1\t1\tChapter 1\n2\t2\tSection 1.1\n1\t3\tChapter 2\n1\t0\tElsewhere",
               "the outline: level, page, title, in reading order");
    CHECK(length_agrees(pdx_outline(d)), "measured");
    CHECK_TEXT(pdx_outline(0), "", "no outline for no document");
    CHECK_TEXT(pdx_page_links(d, 1), "72,47,210,77\t0\thttps://example.org/pdfxt", "a web link: its rectangle from the top left, no page, its address");
    CHECK_TEXT(pdx_page_links(d, 2), "395,100,420,260\t1\t", "a link on the rotated page, to page 1");
    CHECK_TEXT(pdx_page_links(d, 3), "", "a page with no links");
    CHECK_TEXT(pdx_page_links(d, 4), "", "a page that is not there");
    pdx_close(d);

    int l = pdx_open(s_locked, "secret");
    CHECK_TEXT(pdx_outline(l), "", "a document with no outline");
    pdx_close(l);
}

static void test_handles(void)
{
    /* A closed handle stays dead while its slot is reused thousands of
     * times (the generation wraps at 2047; the slot is then retired). */
    int first = pdx_open_data(k_basic_pdf, (int)sizeof k_basic_pdf, "");
    pdx_close(first);
    int revived = 0, failed = 0, seenFirst = 0;
    for (int i = 0; i < 5000; i++) {
        int h = pdx_open_data(k_basic_pdf, (int)sizeof k_basic_pdf, "");
        if (!h) { failed++; continue; }
        if (h == first) seenFirst++;
        if (pdx_is_open(first)) revived++;
        pdx_close(h);
        if (pdx_is_open(h)) revived++;
    }
    CHECK(failed == 0, "five thousand opens and closes all succeed");
    CHECK(revived == 0 && seenFirst == 0, "and no closed handle comes back to life");
    CHECK(pdx_open_count() == 0, "none left open");

    /* the document limit is a refusal, not a crash */
    int opened = 0, lastGood = 0;
    for (int i = 0; i < 5000; i++) {
        int h = pdx_open_data(k_locked_pdf, (int)sizeof k_locked_pdf, "secret");
        if (!h) break;
        lastGood = h;
        opened++;
    }
    CHECK(opened >= 4000 && opened <= 4095, "about four thousand documents open at once");
    CHECK(strstr(pdx_last_error(), "too many") != NULL, "and the next is refused, with the reason");
    CHECK(pdx_open_count() == opened && pdx_page_count(lastGood) == 1, "all of them usable");
    CHECK(pdx_close_all() == opened && pdx_open_count() == 0, "close all closes all and says how many");
    CHECK(pdx_close_all() == 0, "twice: nothing left");
    CHECK(pdx_is_open(lastGood) == 0, "their handles are dead");

    /* hostile handles */
    static const int bad[] = { 0, -1, 1, 4095, 4096, 4097, 0x7FFFFFFF, (int)0x80000000u, 123456789 };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        int h = bad[i];
        pdx_close(h);
        (void)pdx_page_count(h); (void)pdx_file_version(h); (void)pdx_permissions(h);
        (void)pdx_metadata(h, "Title"); (void)pdx_page_label(h, 1); (void)pdx_page_size(h, 1);
        (void)pdx_page_rotation(h, 1); (void)pdx_render_page(h, 1, 10, 10, 0);
        (void)pdx_render_page_region(h, 1, 10, 10, 0, 0, 10, 10, 0); (void)pdx_render_page_bmp(h, 1, 10, 10, 0);
        (void)pdx_page_char_count(h, 1); (void)pdx_page_text(h, 1); (void)pdx_page_text_range(h, 1, 1, 1);
        (void)pdx_page_text_in_rect(h, 1, 0, 0, 1, 1); (void)pdx_page_char_box(h, 1, 1);
        (void)pdx_page_char_at(h, 1, 0, 0, 1); (void)pdx_page_search(h, 1, "a", 0);
        (void)pdx_page_text_rects(h, 1, 1, 1); (void)pdx_outline(h); (void)pdx_page_links(h, 1);
        CHECK(pdx_is_open(h) == 0, "a handle that was never given is not open");
    }
    /* hostile page numbers on a real document */
    int d = pdx_open(s_basic, "");
    static const int badPage[] = { 0, -1, 4, 0x7FFFFFFF, (int)0x80000000u };
    for (size_t i = 0; i < sizeof badPage / sizeof badPage[0]; i++) {
        int p = badPage[i];
        (void)pdx_page_label(d, p); (void)pdx_page_size(d, p); (void)pdx_page_rotation(d, p);
        (void)pdx_render_page(d, p, 10, 10, 0); (void)pdx_page_char_count(d, p); (void)pdx_page_text(d, p);
        (void)pdx_page_text_range(d, p, 1, 1); (void)pdx_page_text_in_rect(d, p, 0, 0, 1, 1);
        (void)pdx_page_char_box(d, p, 1); (void)pdx_page_char_at(d, p, 0, 0, 1);
        (void)pdx_page_search(d, p, "a", 0); (void)pdx_page_text_rects(d, p, 1, 1); (void)pdx_page_links(d, p);
    }
    CHECK(pdx_page_count(d) == 3, "the document survives every page number that is not one");

    /* shutdown closes what is open; the next call starts PDFium again */
    pdx_shutdown();
    CHECK(pdx_is_loaded() == 0 && pdx_open_count() == 0 && pdx_is_open(d) == 0, "shutdown closes every document");
    pdx_shutdown();
    CHECK(pdx_is_loaded() == 0, "twice: harmless");
    CHECK_TEXT(pdx_page_text(d, 1), "", "a handle from before the shutdown is dead");
    int again = pdx_open(s_basic, "");
    CHECK(again > 0 && pdx_is_loaded() == 1, "and PDFium starts again on the next open");
    CHECK_TEXT(pdx_page_text_range(again, 1, 1, 5), "Hello", "and works");
    CHECK(pdx_load("") == 1, "loading when loaded is a yes");
    pdx_shutdown();
}

#if defined(__ANDROID__)
static int android_api(void)
{
    char v[PROP_VALUE_MAX];
    if (__system_property_get("ro.build.version.sdk", v) <= 0) return 0;
    return atoi(v);
}
#endif

int main(void)
{
    const char *tmp = getenv("TMPDIR");
#if defined(_WIN32)
    if (!tmp || !tmp[0]) tmp = getenv("TEMP");
#endif
    snprintf(s_dir, sizeof s_dir, "%s", (tmp && tmp[0]) ? tmp : ".");
    snprintf(s_basic, sizeof s_basic, "%s/pdfxt-smoke-basic.pdf", s_dir);
    snprintf(s_locked, sizeof s_locked, "%s/pdfxt-smoke-locked.pdf", s_dir);
    snprintf(s_unicode, sizeof s_unicode, "%s/pdfxt-smoke-caf\xC3\xA9-\xCE\xA9.pdf", s_dir);
    if (!write_file(s_basic, k_basic_pdf, sizeof k_basic_pdf)
        || !write_file(s_locked, k_locked_pdf, sizeof k_locked_pdf)
        || !write_file(s_unicode, k_basic_pdf, sizeof k_basic_pdf)) {
        printf("pdfxt smoke: cannot write its PDF files in %s\n", s_dir);
        return 1;
    }

    test_without_pdfium();

    if (!pdx_load("")) {
        printf("PDFium did not load: %s\n", pdx_last_error());
#if defined(__ANDROID__)
        int api = android_api();
        if (api > 0 && api < 23 && s_failed == 0) {
            printf("pdfxt smoke: SKIPPED on Android API %d - the pinned PDFium needs API 23 (Android 6.0). "
                   "%d checks that need no PDFium passed; the rest did NOT run.\n", api, s_passed);
            /* The line tools/build-android.sh carries into its summary, so a
             * run of the refusals alone never reads as a run of the test. */
            printf("XTALK_TEST_PARTIAL: refusals only (%d checks); PDFium needs Android API 23 and "
                   "this device is API %d\n", s_passed, api);
            remove_utf8(s_basic); remove_utf8(s_locked); remove_utf8(s_unicode);
            return 0;
        }
#endif
        printf("pdfxt smoke: %d passed, %d failed (and PDFium did not load)\n", s_passed, s_failed + 1);
        return s_failed + 1;
    }
    CHECK(pdx_is_loaded() == 1, "PDFium loads from the folder pdfxt is in");

    test_refusals();
    test_document();
    test_password();
    test_drawing();
    test_forms();
    test_text();
    test_outline_and_links();
    test_handles();

    remove_utf8(s_basic); remove_utf8(s_locked); remove_utf8(s_unicode);
    printf("pdfxt smoke: %d passed, %d failed\n", s_passed, s_failed);
    return s_failed > 255 ? 255 : s_failed;
}
