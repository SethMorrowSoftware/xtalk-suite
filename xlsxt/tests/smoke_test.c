/*
 * smoke_test.c - the runtime test of the xlsxt shim.
 *
 * Links against the xlsxt library (or, for the web, the archive) and drives
 * it through the same C entry points the LCB binding calls. It proves what a
 * compile cannot: that a workbook written here is a file the reader here
 * reads back cell for cell; that the reader copes with files libxlsxwriter
 * did NOT write (built part by part with tests/test_zip.h: inline strings,
 * rich text, 1904 dates, prefixed element names, cells without references);
 * that dates survive Excel's 1900 leap-year bug in both directions; and that
 * a stale handle, a bad argument or a damaged file is a refusal with a
 * reason, never a fault. Run under ASan/UBSan in CI (native-xlsxt.yml).
 *
 * EVERY export of src/xlsx_shim.c is entered here: tools/check-smoke-coverage.py
 * holds the declaration block below to the shim's signatures and refuses an
 * export this file never calls.
 *
 * The test writes its files into the current directory (xlsxt-smoke-*) and
 * removes them when it passes; after a failure they stay, to be looked at.
 *
 * Enable with -DXLSXT_BUILD_TESTS=ON, then run `ctest` (or the binary).
 */
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "test_zip.h"

/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
/* 122 exports, in the shim's order. Plain declarations: the test is a client of
 * the built library, exactly as the engine's FFI is. */
extern int xlx_abi_version(void);
extern const char*xlx_library_version(void);
extern const char*xlx_last_error(void);
extern int xlx_text_length(const char*text);
extern void xlx_set_temp_folder(const char*folder);
extern const char*xlx_temp_folder(void);
extern const char*xlx_column_name(int column);
extern const char*xlx_cell_name(int row, int column);
extern const char*xlx_range_name(int first_row, int first_column, int last_row, int last_column);
extern const char*xlx_range_formula(const char*sheet_name, int first_row, int first_column, int last_row, int last_column);
extern int xlx_cell_row(const char*name);
extern int xlx_cell_column(const char*name);
extern double xlx_date_to_serial(int year, int month, int day, int hour, int minute, double second);
extern const char*xlx_serial_to_date(double serial);
extern double xlx_seconds_to_serial(double seconds);
extern double xlx_serial_to_seconds(double serial);
extern int xlx_workbook_count(void);
extern int xlx_workbook_new(const char*path);
extern int xlx_workbook_is_valid(int book);
extern int xlx_workbook_close(int book);
extern void xlx_workbook_discard(int book);
extern int xlx_workbook_error_count(int book);
extern const char*xlx_workbook_first_error(int book);
extern int xlx_workbook_sheet_count(int book);
extern int xlx_workbook_add_sheet(int book, const char*name);
extern int xlx_workbook_add_format(int book);
extern int xlx_workbook_add_chart(int book, const char*kind);
extern void xlx_workbook_set_property(int book, const char*name, const char*value);
extern void xlx_workbook_define_name(int book, const char*name, const char*formula);
extern int xlx_format_is_valid(int format);
extern void xlx_format_set_bold(int format, int flag);
extern void xlx_format_set_italic(int format, int flag);
extern void xlx_format_set_strikeout(int format, int flag);
extern void xlx_format_set_underline(int format, const char*style);
extern void xlx_format_set_script(int format, const char*style);
extern void xlx_format_set_font_name(int format, const char*name);
extern void xlx_format_set_font_size(int format, double size);
extern void xlx_format_set_font_color(int format, const char*color);
extern void xlx_format_set_background_color(int format, const char*color);
extern void xlx_format_set_number_format(int format, const char*code);
extern void xlx_format_set_align(int format, const char*alignment);
extern void xlx_format_set_vertical_align(int format, const char*alignment);
extern void xlx_format_set_text_wrap(int format, int flag);
extern void xlx_format_set_shrink(int format, int flag);
extern void xlx_format_set_rotation(int format, int degrees);
extern void xlx_format_set_indent(int format, int level);
extern void xlx_format_set_border(int format, const char*style);
extern void xlx_format_set_border_side(int format, const char*side, const char*style);
extern void xlx_format_set_border_color(int format, const char*color);
extern void xlx_format_set_locked(int format, int flag);
extern void xlx_format_set_formula_hidden(int format, int flag);
extern int xlx_sheet_is_valid(int sheet);
extern const char*xlx_sheet_name(int sheet);
extern void xlx_sheet_write_number(int sheet, int row, int column, double number, int format);
extern void xlx_sheet_write_text(int sheet, int row, int column, const char*text, int format);
extern void xlx_sheet_write_formula(int sheet, int row, int column, const char*formula, int format);
extern void xlx_sheet_write_formula_value(int sheet, int row, int column, const char*formula, double value, int format);
extern void xlx_sheet_write_boolean(int sheet, int row, int column, int flag, int format);
extern void xlx_sheet_write_blank(int sheet, int row, int column, int format);
extern void xlx_sheet_write_date(int sheet, int row, int column, double serial, int format);
extern void xlx_sheet_write_link(int sheet, int row, int column, const char*url, const char*text, int format);
extern void xlx_sheet_write_comment(int sheet, int row, int column, const char*text);
extern int xlx_sheet_write_grid(int sheet, int row, int column, const char*text, const char*mode, int format);
extern void xlx_sheet_set_columns(int sheet, int first_column, int last_column, double width, int format);
extern void xlx_sheet_hide_columns(int sheet, int first_column, int last_column);
extern void xlx_sheet_set_row(int sheet, int row, double height, int format);
extern void xlx_sheet_hide_row(int sheet, int row);
extern void xlx_sheet_merge(int sheet, int first_row, int first_column, int last_row, int last_column, const char*text, int format);
extern void xlx_sheet_freeze(int sheet, int rows, int columns);
extern void xlx_sheet_autofilter(int sheet, int first_row, int first_column, int last_row, int last_column);
extern void xlx_sheet_validate_list(int sheet, int first_row, int first_column, int last_row, int last_column, const char*items);
extern void xlx_sheet_insert_image(int sheet, int row, int column, const char*path, double x_scale, double y_scale);
extern void xlx_sheet_set_landscape(int sheet, int flag);
extern void xlx_sheet_set_paper(int sheet, int paper);
extern void xlx_sheet_set_margins(int sheet, double left, double right, double top, double bottom);
extern void xlx_sheet_fit_to_pages(int sheet, int wide, int tall);
extern void xlx_sheet_set_header(int sheet, const char*text);
extern void xlx_sheet_set_footer(int sheet, const char*text);
extern void xlx_sheet_repeat_rows(int sheet, int first_row, int last_row);
extern void xlx_sheet_print_area(int sheet, int first_row, int first_column, int last_row, int last_column);
extern void xlx_sheet_set_zoom(int sheet, int percent);
extern void xlx_sheet_show_gridlines(int sheet, int screen_flag, int print_flag);
extern void xlx_sheet_set_tab_color(int sheet, const char*color);
extern void xlx_sheet_activate(int sheet);
extern void xlx_sheet_hide(int sheet);
extern void xlx_sheet_protect(int sheet, const char*password);
extern int xlx_chart_is_valid(int chart);
extern int xlx_chart_series_count(int chart);
extern int xlx_chart_add_series(int chart, const char*categories, const char*values);
extern void xlx_chart_series_set_name(int chart, int series, const char*name);
extern void xlx_chart_series_set_color(int chart, int series, const char*color);
extern void xlx_chart_series_set_labels(int chart, int series, int flag);
extern void xlx_chart_series_set_smooth(int chart, int series, int flag);
extern void xlx_chart_series_set_marker(int chart, int series, const char*kind);
extern void xlx_chart_set_title(int chart, const char*title);
extern void xlx_chart_set_axis_title(int chart, const char*axis, const char*title);
extern void xlx_chart_set_axis_range(int chart, const char*axis, double minimum, double maximum);
extern void xlx_chart_set_axis_number_format(int chart, const char*axis, const char*code);
extern void xlx_chart_set_axis_gridlines(int chart, const char*axis, int flag);
extern void xlx_chart_set_legend(int chart, const char*position);
extern void xlx_chart_set_style(int chart, int style);
extern void xlx_sheet_insert_chart(int sheet, int row, int column, int chart, double x_scale, double y_scale);
extern int xlx_read_count(void);
extern int xlx_read_open(const char*path);
extern void xlx_read_close(int reader);
extern int xlx_read_is_valid(int reader);
extern int xlx_read_sheet_count(int reader);
extern const char*xlx_read_sheet_name(int reader, int sheet);
extern int xlx_read_sheet_number(int reader, const char*name);
extern int xlx_read_sheet_is_hidden(int reader, int sheet);
extern int xlx_read_uses_1904(int reader);
extern int xlx_read_load(int reader, int sheet);
extern int xlx_read_row_count(int reader, int sheet);
extern int xlx_read_column_count(int reader, int sheet);
extern const char*xlx_read_cell(int reader, int sheet, int row, int column);
extern const char*xlx_read_cell_value(int reader, int sheet, int row, int column);
extern double xlx_read_cell_number(int reader, int sheet, int row, int column);
extern const char*xlx_read_cell_kind(int reader, int sheet, int row, int column);
extern const char*xlx_read_cell_formula(int reader, int sheet, int row, int column);
extern const char*xlx_read_cell_format(int reader, int sheet, int row, int column);
extern const char*xlx_read_grid(int reader, int sheet, int first_row, int first_column, int last_row, int last_column);
extern const char*xlx_read_merged(int reader, int sheet);
/* <<< END SHIM DECLARATIONS <<< */

static int s_pass = 0, s_fail = 0;
#define CHECK(cond, ...)                                                      \
    do {                                                                      \
        if (cond) { s_pass++; }                                               \
        else {                                                                \
            s_fail++;                                                         \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                       \
            printf(__VA_ARGS__);                                              \
            printf("\n");                                                     \
        }                                                                     \
    } while (0)

/* A text result against what it should be. The result is copied first: the
 * library's text buffer is one, and printing two results needs two copies. */
static char s_got[1 << 16];
static const char *got(const char *text)
{
    snprintf(s_got, sizeof s_got, "%s", text ? text : "(NULL)");
    return s_got;
}
#define EQ(expr, want)                                                        \
    do {                                                                      \
        const char *g_ = got(expr);                                           \
        CHECK(strcmp(g_, (want)) == 0, "%s gave \"%s\", not \"%s\"", #expr, g_, (want)); \
    } while (0)
#define REFUSED(what) CHECK(xlx_last_error()[0] != 0, "%s was not refused with a reason", what)
#define ACCEPTED(what) CHECK(xlx_last_error()[0] == 0, "%s was refused: %s", what, xlx_last_error())

static int near(double a, double b, double tol) { return fabs(a - b) <= tol; }

/* Is this name in the file's bytes? A zip keeps its member names uncompressed
 * (in each local header and again in the directory), so a part the reader
 * half never opens (a chart, a picture, the document properties) can still
 * be shown to have been written. */
static int file_names(const char *path, const char *name)
{
    FILE *f = fopen(path, "rb");
    size_t n = strlen(name), have = 0;
    int c, found = 0;
    static char window[512];
    if (!f || n >= sizeof window) { if (f) fclose(f); return 0; }
    while (!found && (c = fgetc(f)) != EOF) {
        if (have == n) { memmove(window, window + 1, n - 1); have--; }
        window[have++] = (char)c;
        if (have == n && memcmp(window, name, n) == 0) found = 1;
    }
    fclose(f);
    return found;
}

static int file_exists(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (f) fclose(f);
    return f != NULL;
}

static void write_bytes(const char *path, const char *bytes, size_t n)
{
    FILE *f = fopen(path, "wb");
    if (f) { fwrite(bytes, 1, n, f); fclose(f); }
}

#define F_BASIC   "xlsxt-smoke-basic.xlsx"
#define F_STYLE   "xlsxt-smoke-style.xlsx"
#define F_GRID    "xlsxt-smoke-grid.xlsx"
#define F_FOREIGN "xlsxt-smoke-foreign.xlsx"
#define F_BAD     "xlsxt-smoke-bad.xlsx"
#define F_PNG     "xlsxt-smoke-pixel.png"
#define F_UTF8    "xlsxt-smoke-\xC3\xA9t\xC3\xA9.xlsx"       /* "ete" with two acute accents */

/* ------------------------------------------------------------------ */
static void test_library(void)
{
    CHECK(xlx_abi_version() == 1, "ABI %d", xlx_abi_version());
    const char *v = got(xlx_library_version());
    CHECK(strstr(v, "xlsxt ABI 1") && strstr(v, "libxlsxwriter 1.2.4") && strstr(v, "zlib 1.4") && strstr(v, "Expat 2.10.0"),
          "the version names the three pinned libraries: %s", v);
    CHECK(xlx_text_length("") == 0 && xlx_text_length(NULL) == 0 && xlx_text_length("abc") == 3
          && xlx_text_length(xlx_library_version()) == (int)strlen(xlx_library_version()),
          "the text length the binding copies by");
    CHECK(xlx_workbook_count() == 0 && xlx_read_count() == 0, "nothing is open at the start");

    xlx_set_temp_folder(".");
    EQ(xlx_temp_folder(), ".");
    xlx_set_temp_folder("bad\x01" "folder");
    REFUSED("a folder path with a control character");
    EQ(xlx_temp_folder(), ".");
    xlx_set_temp_folder("");
    EQ(xlx_temp_folder(), "");
    xlx_set_temp_folder(NULL);
    ACCEPTED("clearing the temp folder with no text at all");
}

/* ------------------------------------------------------------------ */
static void test_names(void)
{
    EQ(xlx_column_name(1), "A");
    EQ(xlx_column_name(26), "Z");
    EQ(xlx_column_name(27), "AA");
    EQ(xlx_column_name(702), "ZZ");
    EQ(xlx_column_name(703), "AAA");
    EQ(xlx_column_name(16384), "XFD");
    EQ(xlx_column_name(0), "");
    REFUSED("column 0");
    EQ(xlx_column_name(16385), "");
    EQ(xlx_cell_name(3, 2), "B3");
    EQ(xlx_cell_name(1048576, 16384), "XFD1048576");
    EQ(xlx_cell_name(0, 1), "");
    REFUSED("row 0");
    EQ(xlx_cell_name(1048577, 1), "");
    EQ(xlx_range_name(1, 1, 3, 2), "A1:B3");
    EQ(xlx_range_name(3, 2, 1, 1), "");
    REFUSED("a range written backwards");
    EQ(xlx_range_formula("Sheet1", 2, 1, 7, 1), "=Sheet1!$A$2:$A$7");
    EQ(xlx_range_formula("My Sheet", 1, 1, 2, 2), "='My Sheet'!$A$1:$B$2");
    EQ(xlx_range_formula("It's", 1, 1, 1, 1), "='It''s'!$A$1:$A$1");
    EQ(xlx_range_formula("2024", 1, 1, 1, 1), "='2024'!$A$1:$A$1");
    EQ(xlx_range_formula("", 1, 1, 1, 1), "");
    REFUSED("a range formula with no sheet name");
    EQ(xlx_range_formula(NULL, 1, 1, 1, 1), "");
    EQ(xlx_range_formula("Sheet1", 0, 1, 1, 1), "");
    CHECK(xlx_cell_row("B3") == 3 && xlx_cell_column("B3") == 2, "B3 is row 3, column 2");
    CHECK(xlx_cell_row("$AB$12") == 12 && xlx_cell_column("$AB$12") == 28, "$AB$12 is row 12, column 28");
    CHECK(xlx_cell_row("xfd1048576") == 1048576 && xlx_cell_column("xfd1048576") == 16384, "the last cell, in lower case");
    CHECK(xlx_cell_row("XFE1") == 0 && xlx_cell_column("XFE1") == 0, "a column past XFD is no cell");
    REFUSED("XFE1");
    CHECK(xlx_cell_row("A0") == 0 && xlx_cell_row("A1048577") == 0 && xlx_cell_row("") == 0 && xlx_cell_row(NULL) == 0
          && xlx_cell_row("A1:B2") == 0 && xlx_cell_row("12") == 0 && xlx_cell_row("ABCD1") == 0 && xlx_cell_row("A1 ") == 0,
          "what is not a cell name is 0");
    CHECK(xlx_cell_column("B") == 0 && xlx_cell_column(NULL) == 0, "nor is a letter alone");
    for (int column = 1; column <= 16384; column += 37) {
        char name[16];
        snprintf(name, sizeof name, "%s", xlx_cell_name(77, column));
        if (xlx_cell_column(name) != column || xlx_cell_row(name) != 77) {
            CHECK(0, "cell name %s does not read back as row 77, column %d", name, column);
            break;
        }
    }
}

/* ------------------------------------------------------------------ */
static void test_dates(void)
{
    CHECK(xlx_date_to_serial(1900, 1, 1, 0, 0, 0) == 1, "1900-01-01 is serial 1");
    CHECK(xlx_date_to_serial(1900, 2, 28, 0, 0, 0) == 59, "1900-02-28 is 59");
    CHECK(xlx_date_to_serial(1900, 3, 1, 0, 0, 0) == 61, "1900-03-01 is 61: serial 60 is the day that never was");
    CHECK(xlx_date_to_serial(1900, 2, 29, 0, 0, 0) == -1, "1900 was not a leap year, and the library does not pretend");
    REFUSED("1900-02-29");
    CHECK(xlx_date_to_serial(1970, 1, 1, 0, 0, 0) == 25569, "1970-01-01 is 25569");
    CHECK(xlx_date_to_serial(2024, 1, 1, 0, 0, 0) == 45292, "2024-01-01 is 45292");
    CHECK(xlx_date_to_serial(2024, 2, 29, 12, 0, 0) == 45351.5, "a leap day at noon");
    CHECK(xlx_date_to_serial(9999, 12, 31, 0, 0, 0) == 2958465, "the last date Excel has");
    CHECK(near(xlx_date_to_serial(0, 0, 0, 6, 30, 15), (6 * 3600 + 30 * 60 + 15) / 86400.0, 1e-12), "a time of day alone");
    CHECK(xlx_date_to_serial(1899, 12, 31, 0, 0, 0) == -1 && xlx_date_to_serial(10000, 1, 1, 0, 0, 0) == -1
          && xlx_date_to_serial(2024, 13, 1, 0, 0, 0) == -1 && xlx_date_to_serial(2024, 4, 31, 0, 0, 0) == -1
          && xlx_date_to_serial(2023, 2, 29, 0, 0, 0) == -1 && xlx_date_to_serial(2024, 1, 1, 24, 0, 0) == -1
          && xlx_date_to_serial(2024, 1, 1, 0, 60, 0) == -1 && xlx_date_to_serial(2024, 1, 1, 0, 0, 60) == -1
          && xlx_date_to_serial(2024, 1, 1, 0, 0, NAN) == -1 && xlx_date_to_serial(2024, 0, 0, 0, 0, 0) == -1,
          "what is not a date is -1");
    EQ(xlx_serial_to_date(45292), "2024-01-01 00:00:00");
    EQ(xlx_serial_to_date(45351.5), "2024-02-29 12:00:00");
    EQ(xlx_serial_to_date(1), "1900-01-01 00:00:00");
    EQ(xlx_serial_to_date(59), "1900-02-28 00:00:00");
    EQ(xlx_serial_to_date(60), "1900-02-29 00:00:00");      /* as Excel shows it */
    EQ(xlx_serial_to_date(61), "1900-03-01 00:00:00");
    EQ(xlx_serial_to_date(2958465), "9999-12-31 00:00:00");
    EQ(xlx_serial_to_date(0.75), "1899-12-31 18:00:00");
    /* half a second short of midnight rounds to the next day, not to 24:00:00 */
    EQ(xlx_serial_to_date(45292.999999), "2024-01-02 00:00:00");
    EQ(xlx_serial_to_date(-1), "");
    REFUSED("a negative serial");
    EQ(xlx_serial_to_date(2958466), "");
    EQ(xlx_serial_to_date(NAN), "");
    EQ(xlx_serial_to_date(INFINITY), "");
    /* every day of four centuries, both ways */
    int bad = 0;
    for (double serial = 61; serial < 61 + 146097 && !bad; serial += 1) {
        int y, m, d;
        if (sscanf(xlx_serial_to_date(serial), "%d-%d-%d", &y, &m, &d) != 3 || xlx_date_to_serial(y, m, d, 0, 0, 0) != serial) bad = (int)serial;
    }
    CHECK(!bad, "serial %d does not survive the round trip to a date and back", bad);

    CHECK(xlx_seconds_to_serial(0) == 25569 && xlx_seconds_to_serial(86400) == 25570, "the seconds start at 1970");
    CHECK(xlx_seconds_to_serial(1704110400.0) == 45292.5, "2024-01-01 12:00 UTC in seconds");
    CHECK(xlx_serial_to_seconds(25569) == 0 && xlx_serial_to_seconds(45292.5) == 1704110400.0, "and back");
    CHECK(xlx_seconds_to_serial(NAN) == -1 && xlx_seconds_to_serial(1e18) == -1 && xlx_seconds_to_serial(-1e18) == -1, "seconds outside Excel's dates are -1");
    REFUSED("seconds outside Excel's dates");
    CHECK(xlx_serial_to_seconds(-1) == 0 && xlx_serial_to_seconds(NAN) == 0 && xlx_serial_to_seconds(3e6) == 0, "a serial that is no date is 0 seconds");
    REFUSED("a serial that is no date");
}

/* ------------------------------------------------------------------ */
/* One workbook with every kind of cell, written, closed, read back.   */
/* ------------------------------------------------------------------ */
static void test_round_trip(void)
{
    int book = xlx_workbook_new(F_BASIC);
    CHECK(book > 0 && xlx_workbook_is_valid(book) && xlx_workbook_count() == 1, "a workbook is made: %s", xlx_last_error());
    int data = xlx_workbook_add_sheet(book, "Data");
    int second = xlx_workbook_add_sheet(book, "");
    int hidden = xlx_workbook_add_sheet(book, "Caf\xC3\xA9 notes");
    CHECK(data > 0 && second > 0 && hidden > 0 && xlx_workbook_sheet_count(book) == 3, "three sheets");
    CHECK(xlx_sheet_is_valid(data) && !xlx_sheet_is_valid(book) && !xlx_sheet_is_valid(0), "a sheet handle is a sheet handle");
    EQ(xlx_sheet_name(data), "Data");
    EQ(xlx_sheet_name(second), "Sheet2");
    EQ(xlx_sheet_name(hidden), "Caf\xC3\xA9 notes");
    EQ(xlx_sheet_name(book), "");
    REFUSED("the name of a handle that is not a sheet");

    int bold = xlx_workbook_add_format(book);
    int money = xlx_workbook_add_format(book);
    int day = xlx_workbook_add_format(book);
    CHECK(bold > 0 && money > 0 && day > 0 && xlx_format_is_valid(bold) && !xlx_format_is_valid(data), "three formats");
    xlx_format_set_bold(bold, 1);
    xlx_format_set_number_format(money, "#,##0.00");
    xlx_format_set_number_format(day, "d mmm yyyy");

    xlx_sheet_write_text(data, 1, 1, "Item", bold);
    xlx_sheet_write_text(data, 1, 2, "Price", bold);
    xlx_sheet_write_text(data, 2, 1, "Tea", 0);
    xlx_sheet_write_number(data, 2, 2, 3.5, money);
    xlx_sheet_write_text(data, 3, 1, "Caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80", 0);       /* 2, 3 and 4 byte UTF-8 */
    xlx_sheet_write_number(data, 3, 2, 0.1, 0);
    xlx_sheet_write_number(data, 4, 2, -1234567.891, 0);
    xlx_sheet_write_number(data, 5, 2, 1e-7, 0);
    xlx_sheet_write_number(data, 6, 2, 123456789012345.0, 0);
    xlx_sheet_write_formula(data, 7, 2, "=SUM(B2:B6)", 0);
    xlx_sheet_write_formula_value(data, 8, 2, "=B2*2", 7, money);
    xlx_sheet_write_boolean(data, 9, 1, 1, 0);
    xlx_sheet_write_boolean(data, 9, 2, 0, 0);
    xlx_sheet_write_blank(data, 10, 1, bold);
    xlx_sheet_write_date(data, 11, 1, 45292, 0);
    xlx_sheet_write_date(data, 11, 2, 45292.75, 0);
    xlx_sheet_write_date(data, 11, 3, 0.25, 0);
    xlx_sheet_write_date(data, 11, 4, 45351, day);
    xlx_sheet_write_date(data, 11, 5, 60, 0);
    xlx_sheet_write_link(data, 12, 1, "https://example.org/a?b=1&c=2", "the site", 0);
    xlx_sheet_write_link(data, 12, 2, "mailto:nobody@example.org", "", 0);
    xlx_sheet_write_link(data, 12, 3, "internal:Sheet2!A1", "over there", bold);
    xlx_sheet_write_comment(data, 2, 1, "a note on Tea");
    xlx_sheet_write_text(data, 13, 1, "two\nlines", 0);
    xlx_sheet_write_text(data, 13, 2, "a\ttab", 0);
    xlx_sheet_write_text(data, 13, 3, "  spaces kept  ", 0);
    xlx_sheet_write_text(data, 13, 4, "<&>\"'", 0);
    xlx_sheet_write_text(data, 13, 5, "_x0041_", 0);
    xlx_sheet_write_text(data, 13, 6, "cr\r\nlf", 0);
    xlx_sheet_write_text(data, 14, 1, "", 0);
    xlx_sheet_write_text(data, 20, 30, "far", 0);
    xlx_sheet_merge(data, 16, 1, 16, 3, "merged", bold);
    xlx_sheet_merge(data, 17, 1, 18, 2, "", 0);
    ACCEPTED("the last of the writes");
    xlx_sheet_write_number(second, 1048576, 16384, 42, 0);
    xlx_sheet_hide(hidden);
    xlx_sheet_write_text(hidden, 1, 1, "unseen", 0);
    CHECK(xlx_workbook_error_count(book) == 0, "no call was refused: %s", got(xlx_workbook_first_error(book)));
    EQ(xlx_workbook_first_error(book), "");

    CHECK(xlx_workbook_close(book) == 1, "the workbook is written: %s", xlx_last_error());
    CHECK(!xlx_workbook_is_valid(book) && !xlx_sheet_is_valid(data) && !xlx_format_is_valid(bold) && xlx_workbook_count() == 0,
          "closing kills the workbook and everything of it");
    CHECK(xlx_workbook_close(book) == 0, "closing twice is refused");
    REFUSED("closing twice");
    CHECK(xlx_workbook_error_count(book) == 0 && xlx_workbook_sheet_count(book) == 0, "a dead workbook counts nothing");

    /* ---- and back ---- */
    int r = xlx_read_open(F_BASIC);
    CHECK(r > 0 && xlx_read_is_valid(r) && xlx_read_count() == 1, "the file opens for reading: %s", xlx_last_error());
    CHECK(xlx_read_sheet_count(r) == 3, "three sheets: %d", xlx_read_sheet_count(r));
    EQ(xlx_read_sheet_name(r, 1), "Data");
    EQ(xlx_read_sheet_name(r, 2), "Sheet2");
    EQ(xlx_read_sheet_name(r, 3), "Caf\xC3\xA9 notes");
    EQ(xlx_read_sheet_name(r, 0), "");
    REFUSED("sheet 0");
    EQ(xlx_read_sheet_name(r, 4), "");
    CHECK(xlx_read_sheet_number(r, "Sheet2") == 2 && xlx_read_sheet_number(r, "DATA") == 1, "a sheet by name, in any letter case");
    CHECK(xlx_read_sheet_number(r, "Nope") == 0 && xlx_read_sheet_number(r, NULL) == 0, "no such sheet is 0");
    REFUSED("a sheet name the file does not have");
    CHECK(!xlx_read_sheet_is_hidden(r, 1) && xlx_read_sheet_is_hidden(r, 3) && !xlx_read_sheet_is_hidden(r, 9), "the third sheet is hidden");
    CHECK(!xlx_read_uses_1904(r), "libxlsxwriter counts from 1900");
    CHECK(xlx_read_load(r, 1) == 1, "sheet 1 loads: %s", xlx_last_error());
    CHECK(xlx_read_row_count(r, 1) == 20 && xlx_read_column_count(r, 1) == 30, "the sheet ends at row %d, column %d",
          xlx_read_row_count(r, 1), xlx_read_column_count(r, 1));

    EQ(xlx_read_cell(r, 1, 1, 1), "Item");
    EQ(xlx_read_cell_kind(r, 1, 1, 1), "text");
    EQ(xlx_read_cell(r, 1, 2, 2), "3.5");
    EQ(xlx_read_cell_kind(r, 1, 2, 2), "number");
    EQ(xlx_read_cell_format(r, 1, 2, 2), "#,##0.00");
    EQ(xlx_read_cell_format(r, 1, 2, 1), "General");
    CHECK(xlx_read_cell_number(r, 1, 2, 2) == 3.5, "3.5 as a number");
    EQ(xlx_read_cell(r, 1, 3, 1), "Caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80");
    EQ(xlx_read_cell(r, 1, 3, 2), "0.1");
    EQ(xlx_read_cell(r, 1, 4, 2), "-1234567.891");
    EQ(xlx_read_cell(r, 1, 5, 2), "1e-07");
    EQ(xlx_read_cell(r, 1, 6, 2), "123456789012345");
    CHECK(xlx_read_cell_number(r, 1, 4, 2) == -1234567.891 && xlx_read_cell_number(r, 1, 5, 2) == 1e-7, "no digit of a number is lost");
    EQ(xlx_read_cell_formula(r, 1, 7, 2), "=SUM(B2:B6)");
    EQ(xlx_read_cell(r, 1, 7, 2), "0");                       /* libxlsxwriter does not calculate */
    EQ(xlx_read_cell_formula(r, 1, 8, 2), "=B2*2");
    EQ(xlx_read_cell(r, 1, 8, 2), "7");
    EQ(xlx_read_cell_formula(r, 1, 2, 2), "");
    EQ(xlx_read_cell(r, 1, 9, 1), "true");
    EQ(xlx_read_cell(r, 1, 9, 2), "false");
    EQ(xlx_read_cell_kind(r, 1, 9, 1), "boolean");
    CHECK(xlx_read_cell_number(r, 1, 9, 1) == 1 && xlx_read_cell_number(r, 1, 9, 2) == 0, "a boolean as a number");
    EQ(xlx_read_cell_kind(r, 1, 10, 1), "empty");             /* a format with nothing in it */
    EQ(xlx_read_cell(r, 1, 10, 1), "");
    EQ(xlx_read_cell(r, 1, 11, 1), "2024-01-01");
    EQ(xlx_read_cell_kind(r, 1, 11, 1), "date");
    EQ(xlx_read_cell_value(r, 1, 11, 1), "45292");
    EQ(xlx_read_cell_format(r, 1, 11, 1), "yyyy-mm-dd");
    EQ(xlx_read_cell(r, 1, 11, 2), "2024-01-01 18:00:00");
    EQ(xlx_read_cell_value(r, 1, 11, 2), "45292.75");
    EQ(xlx_read_cell(r, 1, 11, 3), "06:00:00");
    EQ(xlx_read_cell(r, 1, 11, 4), "2024-02-29");
    EQ(xlx_read_cell_format(r, 1, 11, 4), "d mmm yyyy");
    EQ(xlx_read_cell(r, 1, 11, 5), "1900-02-29");
    CHECK(xlx_read_cell_number(r, 1, 11, 2) == 45292.75, "a date as its serial");
    EQ(xlx_read_cell(r, 1, 12, 1), "the site");
    EQ(xlx_read_cell(r, 1, 12, 2), "nobody@example.org");       /* as Excel shows a mailto: link */
    EQ(xlx_read_cell(r, 1, 12, 3), "over there");
    EQ(xlx_read_cell(r, 1, 13, 1), "two\nlines");
    EQ(xlx_read_cell(r, 1, 13, 2), "a\ttab");
    EQ(xlx_read_cell(r, 1, 13, 3), "  spaces kept  ");
    EQ(xlx_read_cell(r, 1, 13, 4), "<&>\"'");
    EQ(xlx_read_cell(r, 1, 13, 5), "_x0041_");
    EQ(xlx_read_cell(r, 1, 13, 6), "cr\r\nlf");
    EQ(xlx_read_cell_kind(r, 1, 14, 1), "empty");             /* "" writes nothing */
    EQ(xlx_read_cell(r, 1, 20, 30), "far");
    EQ(xlx_read_cell(r, 1, 16, 1), "merged");
    EQ(xlx_read_merged(r, 1), "A16:C16\nA17:B18");
    /* outside what the sheet holds, and outside the grid: empty, not refused */
    EQ(xlx_read_cell(r, 1, 21, 1), "");
    EQ(xlx_read_cell(r, 1, 0, 0), "");
    EQ(xlx_read_cell(r, 1, -5, 99999), "");
    EQ(xlx_read_cell_kind(r, 1, 999, 999), "empty");
    EQ(xlx_read_cell_value(r, 1, 999, 999), "");
    EQ(xlx_read_cell_formula(r, 1, 999, 999), "");
    EQ(xlx_read_cell_format(r, 1, 999, 999), "");
    CHECK(xlx_read_cell_number(r, 1, 999, 999) == 0 && xlx_read_cell_number(r, 1, 1, 1) == 0, "no number is 0");
    ACCEPTED("reading an empty cell");

    /* the grid: rows of tabs, each row stopping at its own last cell */
    EQ(xlx_read_grid(r, 1, 1, 1, 3, 2), "Item\tPrice\nTea\t3.5\nCaf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80\t0.1");
    EQ(xlx_read_grid(r, 1, 9, 1, 11, 3), "true\tfalse\n\n2024-01-01\t2024-01-01 18:00:00\t06:00:00");
    EQ(xlx_read_grid(r, 1, 13, 1, 13, 2), "two\vlines\ta tab");
    EQ(xlx_read_grid(r, 1, 4, 1, 5, 0), "\t-1234567.891\n\t1e-07");
    EQ(xlx_read_grid(r, 1, 19, 1, 0, 0), "\n\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tfar");
    EQ(xlx_read_grid(r, 1, 21, 1, 0, 0), "");
    ACCEPTED("a grid that starts below the last row");
    EQ(xlx_read_grid(r, 1, 0, 1, 2, 2), "");
    REFUSED("a grid from row 0");
    EQ(xlx_read_grid(r, 1, 3, 1, 2, 2), "");
    REFUSED("a grid written backwards");

    /* the other sheets: asking for one lets the first go */
    CHECK(xlx_read_row_count(r, 2) == 1048576 && xlx_read_column_count(r, 2) == 16384, "the last cell of the grid");
    EQ(xlx_read_cell(r, 2, 1048576, 16384), "42");
    EQ(xlx_read_grid(r, 2, 1048576, 16384, 0, 0), "42");
    EQ(xlx_read_cell(r, 3, 1, 1), "unseen");
    EQ(xlx_read_cell(r, 1, 1, 1), "Item");
    CHECK(xlx_read_load(r, 4) == 0 && xlx_read_load(r, 0) == 0 && xlx_read_load(r, -1) == 0, "no such sheet does not load");
    REFUSED("loading a sheet the file does not have");
    CHECK(xlx_read_row_count(r, 9) == 0 && xlx_read_column_count(r, 9) == 0, "and counts nothing");
    EQ(xlx_read_cell(r, 9, 1, 1), "");
    EQ(xlx_read_cell_kind(r, 9, 1, 1), "");
    EQ(xlx_read_merged(r, 9), "");
    EQ(xlx_read_merged(r, 2), "");

    xlx_read_close(r);
    CHECK(!xlx_read_is_valid(r) && xlx_read_count() == 0, "the reader closes");
    xlx_read_close(r);
    REFUSED("closing a reader twice");
    CHECK(xlx_read_sheet_count(r) == 0 && xlx_read_load(r, 1) == 0 && !xlx_read_uses_1904(r) && !xlx_read_sheet_is_hidden(r, 1)
          && xlx_read_sheet_number(r, "Data") == 0 && xlx_read_cell_number(r, 1, 1, 1) == 0, "a closed reader answers nothing");
    EQ(xlx_read_sheet_name(r, 1), "");
    EQ(xlx_read_cell(r, 1, 1, 1), "");
    EQ(xlx_read_grid(r, 1, 1, 1, 0, 0), "");
    REFUSED("a grid from a closed reader");
}

/* ------------------------------------------------------------------ */
/* Formats, layout, pictures, charts: everything that changes how the  */
/* file LOOKS. The reader cannot see most of it, so what is proven     */
/* here is that every call is accepted or refused as documented, that  */
/* the file still closes, that the parts were written, and that the    */
/* cells still read back.                                              */
/* ------------------------------------------------------------------ */
static void test_look(void)
{
    static const char *const borders[] = {"none", "thin", "medium", "thick", "dashed", "dotted", "double", "hair",
        "medium dashed", "dash dot", "medium dash dot", "dash dot dot", "medium dash dot dot", "slant dash dot"};
    static const char *const kinds[] = {"column", "column stacked", "column percent", "bar", "bar stacked", "bar percent",
        "line", "line stacked", "line percent", "area", "area stacked", "area percent", "pie", "doughnut", "scatter",
        "scatter lines", "scatter smooth", "radar", "radar markers"};
    static const char *const markers[] = {"automatic", "none", "square", "diamond", "triangle", "x", "star", "circle",
        "short dash", "long dash"};
    int book = xlx_workbook_new(F_STYLE);
    int sheet = xlx_workbook_add_sheet(book, "Report");
    int f = xlx_workbook_add_format(book);
    int errors = 0;
    CHECK(tz_png(F_PNG), "the test picture is written");

    /* ---- every format setter, with a good value and a bad one ---- */
    xlx_format_set_bold(f, 1); xlx_format_set_italic(f, 1); xlx_format_set_strikeout(f, 1);
    xlx_format_set_bold(f, 0); xlx_format_set_italic(f, 0); xlx_format_set_strikeout(f, 0);
    xlx_format_set_underline(f, "single"); xlx_format_set_underline(f, "Double Accounting");
    xlx_format_set_script(f, "superscript"); xlx_format_set_script(f, "none");
    xlx_format_set_font_name(f, "Courier New"); xlx_format_set_font_size(f, 14);
    xlx_format_set_font_color(f, "#FF0000"); xlx_format_set_font_color(f, "black"); xlx_format_set_font_color(f, "0,128,255");
    xlx_format_set_background_color(f, "FFFF00"); xlx_format_set_background_color(f, "Yellow");
    xlx_format_set_number_format(f, "0.00%");
    xlx_format_set_align(f, "center"); xlx_format_set_align(f, "CENTRE"); xlx_format_set_vertical_align(f, "middle");
    xlx_format_set_text_wrap(f, 1); xlx_format_set_shrink(f, 0);
    xlx_format_set_rotation(f, 45); xlx_format_set_rotation(f, 270); xlx_format_set_rotation(f, -90);
    xlx_format_set_indent(f, 2);
    for (size_t i = 0; i < sizeof borders / sizeof borders[0]; i++) {
        xlx_format_set_border(f, borders[i]);
        xlx_format_set_border_side(f, i % 4 == 0 ? "left" : i % 4 == 1 ? "right" : i % 4 == 2 ? "top" : "bottom", borders[i]);
    }
    xlx_format_set_border_color(f, "navy");
    xlx_format_set_locked(f, 0); xlx_format_set_formula_hidden(f, 1);
    CHECK(xlx_workbook_error_count(book) == 0, "every good format value is accepted: %s", got(xlx_workbook_first_error(book)));

#define BAD(call, what)                                                       \
    do {                                                                      \
        call;                                                                 \
        errors++;                                                             \
        CHECK(xlx_last_error()[0] != 0 && xlx_workbook_error_count(book) == errors, \
              "%s: refused with a reason and counted (count %d, want %d, reason \"%s\")", \
              what, xlx_workbook_error_count(book), errors, xlx_last_error()); \
    } while (0)

    BAD(xlx_format_set_underline(f, "wavy"), "an underline that does not exist");
    EQ(xlx_workbook_first_error(book), "not an underline: none, single, double, single accounting, double accounting");
    BAD(xlx_format_set_underline(f, NULL), "no underline text at all");
    BAD(xlx_format_set_script(f, "sideways"), "a script that does not exist");
    BAD(xlx_format_set_font_name(f, ""), "an empty font name");
    BAD(xlx_format_set_font_name(f, NULL), "no font name");
    BAD(xlx_format_set_font_name(f, "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"), "a font name longer than libxlsxwriter keeps");
    BAD(xlx_format_set_font_size(f, 0), "a font size of 0");
    BAD(xlx_format_set_font_size(f, NAN), "a font size that is not a number");
    BAD(xlx_format_set_font_size(f, 410), "a font size of 410");
    BAD(xlx_format_set_font_color(f, "#12345"), "a colour of five digits");
    BAD(xlx_format_set_font_color(f, "#GGGGGG"), "a colour that is not hex");
    BAD(xlx_format_set_font_color(f, "1,2"), "a colour of two parts");
    BAD(xlx_format_set_font_color(f, "256,0,0"), "a colour above 255");
    BAD(xlx_format_set_font_color(f, "1,2,3,4"), "a colour of four parts");
    BAD(xlx_format_set_font_color(f, ""), "an empty colour");
    BAD(xlx_format_set_font_color(f, NULL), "no colour");
    BAD(xlx_format_set_background_color(f, "mauve-ish"), "a colour name the library does not know");
    BAD(xlx_format_set_number_format(f, ""), "an empty number format");
    BAD(xlx_format_set_number_format(f, "0.0\n0"), "a number format with a line break");
    BAD(xlx_format_set_align(f, "middle"), "a horizontal alignment that is a vertical one");
    BAD(xlx_format_set_vertical_align(f, "left"), "a vertical alignment that is a horizontal one");
    BAD(xlx_format_set_rotation(f, 91), "a rotation of 91");
    BAD(xlx_format_set_rotation(f, -91), "a rotation of -91");
    BAD(xlx_format_set_indent(f, -1), "an indent of -1");
    BAD(xlx_format_set_indent(f, 251), "an indent of 251");
    BAD(xlx_format_set_border(f, "wiggly"), "a border that does not exist");
    BAD(xlx_format_set_border_side(f, "front", "thin"), "a side that does not exist");
    BAD(xlx_format_set_border_side(f, "left", "wiggly"), "a border that does not exist, on a side");
    BAD(xlx_format_set_border_color(f, "\xFF\xFE"), "a colour that is not text");

    /* ---- cells with the format, and every layout call ---- */
    xlx_sheet_write_text(sheet, 1, 1, "Month", f);
    xlx_sheet_write_text(sheet, 1, 2, "Sales", f);
    xlx_sheet_write_text(sheet, 1, 3, "Costs", f);
    for (int i = 0; i < 6; i++) {
        static const char *const months[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun"};
        xlx_sheet_write_text(sheet, i + 2, 1, months[i], 0);
        xlx_sheet_write_number(sheet, i + 2, 2, 100 + i * 15, 0);
        xlx_sheet_write_number(sheet, i + 2, 3, 80 + i * 5, 0);
    }
    xlx_sheet_set_columns(sheet, 1, 1, 12, 0);
    xlx_sheet_set_columns(sheet, 2, 3, 9.5, f);
    xlx_sheet_set_columns(sheet, 16384, 16384, 0, 0);
    xlx_sheet_hide_columns(sheet, 10, 11);
    xlx_sheet_set_row(sheet, 1, 24, f);
    xlx_sheet_set_row(sheet, 1048576, 0, 0);
    xlx_sheet_hide_row(sheet, 30);
    xlx_sheet_freeze(sheet, 1, 0);
    xlx_sheet_autofilter(sheet, 1, 1, 7, 3);
    xlx_sheet_validate_list(sheet, 2, 5, 7, 5, "open, closed,,pending");
    xlx_sheet_insert_image(sheet, 10, 1, F_PNG, 1, 1);
    xlx_sheet_insert_image(sheet, 10, 3, F_PNG, 20, 0.5);
    xlx_sheet_set_landscape(sheet, 1); xlx_sheet_set_landscape(sheet, 0);
    xlx_sheet_set_paper(sheet, 9);
    xlx_sheet_set_margins(sheet, 0.5, 0.5, 0.75, 0.75);
    xlx_sheet_fit_to_pages(sheet, 1, 0);
    xlx_sheet_set_header(sheet, "&LReport&RPage &P of &N");
    xlx_sheet_set_footer(sheet, "&C&D");
    xlx_sheet_set_header(sheet, "");
    xlx_sheet_repeat_rows(sheet, 1, 1);
    xlx_sheet_print_area(sheet, 1, 1, 30, 8);
    xlx_sheet_set_zoom(sheet, 120);
    xlx_sheet_show_gridlines(sheet, 0, 1);
    xlx_sheet_set_tab_color(sheet, "orange");
    xlx_sheet_activate(sheet);
    xlx_sheet_protect(sheet, "");
    xlx_sheet_protect(sheet, "s3cret");
    xlx_workbook_set_property(book, "title", "Half-year report");
    xlx_workbook_set_property(book, "Author", "A. Tester");
    xlx_workbook_set_property(book, "comments", "two\nlines");
    xlx_workbook_set_property(book, "company", "");
    xlx_workbook_define_name(book, "Sales", "=Report!$B$2:$B$7");
    xlx_workbook_define_name(book, "Report!Local", "=Report!$A$1");
    CHECK(xlx_workbook_error_count(book) == errors, "every good layout call is accepted: %s", xlx_last_error());

    BAD(xlx_sheet_write_number(sheet, 0, 1, 1, 0), "row 0");
    BAD(xlx_sheet_write_number(sheet, 1, 16385, 1, 0), "a column past the grid");
    BAD(xlx_sheet_write_number(sheet, 1, 1, NAN, 0), "a number that is not one");
    BAD(xlx_sheet_write_number(sheet, 1, 1, INFINITY, 0), "infinity");
    BAD(xlx_sheet_write_number(sheet, 1, 1, 1, sheet), "a sheet handle where a format belongs");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "bad \xC3\x28 bytes", 0), "text that is not UTF-8");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "\xED\xA0\x80", 0), "a UTF-8 surrogate");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "\xC0\xAF", 0), "an overlong UTF-8 form");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "\xF4\x90\x80\x80", 0), "a code point above U+10FFFF");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "bell\x07", 0), "a control character XML cannot hold");
    BAD(xlx_sheet_write_text(sheet, 1, 1, "truncated \xE2\x82", 0), "a UTF-8 sequence cut short");
    BAD(xlx_sheet_write_text(sheet, 1, 1, NULL, 0), "no text at all");
    BAD(xlx_sheet_write_formula(sheet, 1, 1, "", 0), "an empty formula");
    BAD(xlx_sheet_write_formula(sheet, 1, 1, NULL, 0), "no formula");
    BAD(xlx_sheet_write_formula_value(sheet, 1, 1, "=1+1", NAN, 0), "a formula result that is not a number");
    BAD(xlx_sheet_write_formula_value(sheet, 1, 1, "", 2, 0), "an empty formula with a result");
    BAD(xlx_sheet_write_boolean(sheet, 1, 0, 1, 0), "a boolean in column 0");
    BAD(xlx_sheet_write_blank(sheet, -1, 1, 0), "a blank in row -1");
    BAD(xlx_sheet_write_date(sheet, 1, 1, -1, 0), "a date before Excel's dates");
    BAD(xlx_sheet_write_date(sheet, 1, 1, 2958466, 0), "a date after them");
    BAD(xlx_sheet_write_date(sheet, 1, 1, NAN, 0), "a date that is not a number");
    BAD(xlx_sheet_write_link(sheet, 1, 1, "", "x", 0), "an empty link");
    BAD(xlx_sheet_write_link(sheet, 1, 1, "just words", "x", 0), "a link that is no link");
    BAD(xlx_sheet_write_link(sheet, 1, 1, "https://example.org", "bad \xFF", 0), "link text that is not UTF-8");
    BAD(xlx_sheet_write_comment(sheet, 1, 1, ""), "an empty comment");
    BAD(xlx_sheet_write_comment(sheet, 0, 1, "x"), "a comment in row 0");
    BAD(xlx_sheet_write_comment(sheet, 1, 1, NULL), "no comment text");
    BAD(xlx_sheet_set_columns(sheet, 0, 1, 10, 0), "column 0");
    BAD(xlx_sheet_set_columns(sheet, 3, 2, 10, 0), "columns written backwards");
    BAD(xlx_sheet_set_columns(sheet, 1, 1, 256, 0), "a width of 256");
    BAD(xlx_sheet_set_columns(sheet, 1, 1, NAN, 0), "a width that is not a number");
    BAD(xlx_sheet_set_columns(sheet, 1, 1, 10, 12345), "a format that never was");
    BAD(xlx_sheet_hide_columns(sheet, 1, 16385), "hiding past the grid");
    BAD(xlx_sheet_set_row(sheet, 0, 15, 0), "row 0");
    BAD(xlx_sheet_set_row(sheet, 1, 410, 0), "a height of 410");
    BAD(xlx_sheet_set_row(sheet, 1, 15, sheet), "a sheet handle as a row's format");
    BAD(xlx_sheet_hide_row(sheet, 1048577), "hiding a row past the grid");
    BAD(xlx_sheet_merge(sheet, 1, 1, 1, 1, "x", 0), "merging one cell");
    BAD(xlx_sheet_merge(sheet, 2, 2, 1, 1, "x", 0), "merging backwards");
    BAD(xlx_sheet_merge(sheet, 40, 1, 41, 1, "bad \xFF", 0), "merging with text that is not UTF-8");
    BAD(xlx_sheet_freeze(sheet, -1, 0), "freezing -1 rows");
    BAD(xlx_sheet_freeze(sheet, 0, 16384), "freezing every column");
    BAD(xlx_sheet_autofilter(sheet, 0, 1, 2, 2), "a filter from row 0");
    BAD(xlx_sheet_validate_list(sheet, 1, 1, 1, 1, ""), "an empty list");
    BAD(xlx_sheet_validate_list(sheet, 1, 1, 1, 1, " , ,"), "a list of nothing but commas");
    BAD(xlx_sheet_validate_list(sheet, 1, 1, 0, 1, "a,b"), "a list on a range that is none");
    BAD(xlx_sheet_validate_list(sheet, 1, 1, 1, 1, NULL), "no list");
    BAD(xlx_sheet_insert_image(sheet, 1, 1, "xlsxt-smoke-no-such.png", 1, 1), "a picture that is not there");
    BAD(xlx_sheet_insert_image(sheet, 1, 1, F_BASIC, 1, 1), "a picture that is a spreadsheet");
    BAD(xlx_sheet_insert_image(sheet, 1, 1, F_PNG, 0, 1), "a scale of 0");
    BAD(xlx_sheet_insert_image(sheet, 1, 1, F_PNG, 1, NAN), "a scale that is not a number");
    BAD(xlx_sheet_insert_image(sheet, 0, 1, F_PNG, 1, 1), "a picture in row 0");
    BAD(xlx_sheet_insert_image(sheet, 1, 1, "", 1, 1), "a picture with no path");
    BAD(xlx_sheet_set_paper(sheet, -1), "paper -1");
    BAD(xlx_sheet_set_paper(sheet, 119), "paper 119");
    BAD(xlx_sheet_set_margins(sheet, -0.1, 1, 1, 1), "a negative margin");
    BAD(xlx_sheet_set_margins(sheet, 1, 1, 1, NAN), "a margin that is not a number");
    BAD(xlx_sheet_fit_to_pages(sheet, -1, 1), "fitting to -1 pages");
    BAD(xlx_sheet_fit_to_pages(sheet, 1, 40000), "fitting to 40000 pages");
    BAD(xlx_sheet_set_header(sheet, NULL), "no header text");
    BAD(xlx_sheet_set_footer(sheet, "bad \xFF"), "a footer that is not UTF-8");
    BAD(xlx_sheet_repeat_rows(sheet, 2, 1), "repeating rows backwards");
    BAD(xlx_sheet_print_area(sheet, 1, 1, 1, 16385), "a print area past the grid");
    BAD(xlx_sheet_set_zoom(sheet, 9), "a zoom of 9");
    BAD(xlx_sheet_set_zoom(sheet, 401), "a zoom of 401");
    BAD(xlx_sheet_set_tab_color(sheet, "#12"), "a tab colour that is none");
    BAD(xlx_sheet_protect(sheet, "bad\x01"), "a password with a control character");
    BAD(xlx_workbook_set_property(book, "flavour", "x"), "a property that does not exist");
    BAD(xlx_workbook_set_property(book, "title", NULL), "a property with no value");
    BAD(xlx_workbook_set_property(book, NULL, "x"), "a property with no name");
    BAD(xlx_workbook_define_name(book, "", "=Report!$A$1"), "a defined name that is empty");
    BAD(xlx_workbook_define_name(book, "Rate", ""), "a defined name with no formula");
    BAD(xlx_workbook_define_name(book, "1 bad name", "=Report!$A$1"), "a defined name Excel does not allow");
    BAD(xlx_workbook_define_name(book, "B3", "=Report!$A$1"), "a defined name that is a cell");
    BAD(xlx_workbook_define_name(book, "!Total", "=Report!$A$1"), "a local name with no sheet");
    BAD(xlx_workbook_define_name(book, "Report!", "=Report!$A$1"), "a local name with no name");
    BAD(xlx_workbook_define_name(book, "a_name_that_is_far_longer_than_the_one_hundred_and_twenty_seven_bytes_libxlsxwriter_keeps_for_a_defined_name_before_it_cuts_it_short", "=Report!$A$1"), "a defined name that would be cut short");
    BAD((void)xlx_workbook_add_sheet(book, "Report"), "a sheet name used twice");
    BAD((void)xlx_workbook_add_sheet(book, "report"), "a sheet name used twice in another letter case");
    BAD((void)xlx_workbook_add_sheet(book, "a/b"), "a sheet name with a slash");
    BAD((void)xlx_workbook_add_sheet(book, "this sheet name is far too long for Excel"), "a sheet name of 41 characters");
    BAD((void)xlx_workbook_add_sheet(book, "'quoted'"), "a sheet name that starts with an apostrophe");
    BAD((void)xlx_workbook_add_sheet(book, "bad \xFF"), "a sheet name that is not UTF-8");
    BAD((void)xlx_workbook_add_chart(book, "bubble"), "a chart kind the library does not have");
    BAD((void)xlx_workbook_add_chart(book, NULL), "no chart kind");

    /* ---- charts: one of every kind on a second sheet ---- */
    int charts = xlx_workbook_add_sheet(book, "Charts");
    char categories[64], values[64];
    snprintf(categories, sizeof categories, "%s", xlx_range_formula("Report", 2, 1, 7, 1));
    snprintf(values, sizeof values, "%s", xlx_range_formula("Report", 2, 2, 7, 2));
    for (size_t i = 0; i < sizeof kinds / sizeof kinds[0]; i++) {
        int chart = xlx_workbook_add_chart(book, kinds[i]);
        CHECK(chart > 0 && xlx_chart_is_valid(chart) && xlx_chart_series_count(chart) == 0, "a %s chart: %s", kinds[i], xlx_last_error());
        CHECK(xlx_chart_add_series(chart, categories, values) == 1, "its first series: %s", xlx_last_error());
        if (strncmp(kinds[i], "scatter", 7) == 0) {
            /* a scatter chart's categories are its x values: it has no series without them */
            BAD((void)xlx_chart_add_series(chart, "", "=Report!$C$2:$C$7"), "a scatter series with no x values");
            CHECK(xlx_chart_add_series(chart, values, "=Report!$C$2:$C$7") == 2 && xlx_chart_series_count(chart) == 2, "its second: %s", xlx_last_error());
        } else {
            CHECK(xlx_chart_add_series(chart, "", "=Report!$C$2:$C$7") == 2 && xlx_chart_series_count(chart) == 2, "its second, with no categories");
        }
        xlx_chart_series_set_name(chart, 1, "Sales");
        xlx_chart_series_set_name(chart, 2, "=Report!$C$1");
        xlx_chart_series_set_color(chart, 1, "#3366CC");
        xlx_chart_series_set_labels(chart, 1, 1);
        xlx_chart_series_set_labels(chart, 2, 0);
        xlx_chart_series_set_smooth(chart, 1, 1);
        xlx_chart_series_set_marker(chart, 1, markers[i % (sizeof markers / sizeof markers[0])]);
        xlx_chart_set_title(chart, kinds[i]);
        xlx_chart_set_legend(chart, i % 2 ? "bottom" : "top right");
        xlx_chart_set_style(chart, 1 + (int)i);
        if (strcmp(kinds[i], "pie") != 0 && strcmp(kinds[i], "doughnut") != 0) {
            xlx_chart_set_axis_title(chart, "x", "Month");
            xlx_chart_set_axis_title(chart, "y", "=Report!$B$1");
            xlx_chart_set_axis_number_format(chart, "y", "#,##0");
            xlx_chart_set_axis_gridlines(chart, "x", 1);
            xlx_chart_set_axis_gridlines(chart, "y", 0);
        }
        CHECK(xlx_workbook_error_count(book) == errors, "every good call on a %s chart is accepted: %s", kinds[i], xlx_last_error());
        xlx_sheet_insert_chart(charts, 1 + (int)i * 16, 1, chart, 1, 1);
        ACCEPTED("putting the chart on the sheet");
        BAD(xlx_sheet_insert_chart(charts, 1, 10, chart, 1, 1), "putting one chart on a sheet twice");
    }
    {
        int chart = xlx_workbook_add_chart(book, "Column");
        int scatter = xlx_workbook_add_chart(book, "scatter");
        xlx_chart_set_axis_range(chart, "y", 0, 200);
        ACCEPTED("a value axis takes a range");
        BAD(xlx_chart_set_axis_range(chart, "x", 0, 10), "a range on an axis of categories");
        xlx_chart_set_axis_range(scatter, "x", 0, 10);
        ACCEPTED("both axes of a scatter chart take a range");
        BAD(xlx_chart_set_axis_range(chart, "y", 5, 5), "a range with no width");
        BAD(xlx_chart_set_axis_range(chart, "y", NAN, 5), "a range that is not numbers");
        BAD(xlx_chart_set_axis_range(chart, "z", 0, 1), "an axis that does not exist");
        BAD(xlx_sheet_insert_chart(charts, 1, 12, chart, 1, 1), "a chart with no series");
        BAD((void)xlx_chart_add_series(chart, "", ""), "a series with no values");
        BAD((void)xlx_chart_add_series(scatter, "", "=Report!$B$2:$B$7"), "a scatter series with no x values, again");
        BAD((void)xlx_chart_add_series(chart, "", NULL), "a series with no values text");
        BAD((void)xlx_chart_add_series(chart, "", "Report!$B$2:$B$7"), "values without the = sign");
        BAD((void)xlx_chart_add_series(chart, "", "=Report!B2:"), "values that end at the colon");
        BAD((void)xlx_chart_add_series(chart, "", "=$B$2:$B$7"), "values with no sheet");
        BAD((void)xlx_chart_add_series(chart, "", "='Report!$B$2:$B$7"), "values with a quote left open");
        BAD((void)xlx_chart_add_series(chart, "", "=Report!$B$7:$B$2"), "values written backwards");
        BAD((void)xlx_chart_add_series(chart, "=Report!A2:A7,Report!C2:C7", values), "categories in two pieces");
        BAD((void)xlx_chart_add_series(chart, "", "=Report!$ZZZZ$2"), "values in a column that does not exist");
        CHECK(xlx_chart_add_series(chart, "", "='Report'!B2") == 1, "a single cell, quoted sheet, no dollars: %s", xlx_last_error());
        BAD(xlx_chart_series_set_name(chart, 2, "x"), "a series that does not exist");
        BAD(xlx_chart_series_set_name(chart, 0, "x"), "series 0");
        BAD(xlx_chart_series_set_name(chart, 1, ""), "an empty series name");
        BAD(xlx_chart_series_set_name(chart, 1, "=not a cell"), "a series name that begins with = and is no cell");
        BAD(xlx_chart_series_set_color(chart, 1, "nope"), "a series colour that is none");
        BAD(xlx_chart_series_set_color(chart, 5, "red"), "a colour on a series that does not exist");
        BAD(xlx_chart_series_set_labels(chart, 5, 1), "labels on a series that does not exist");
        BAD(xlx_chart_series_set_smooth(chart, -1, 1), "smoothing series -1");
        BAD(xlx_chart_series_set_marker(chart, 1, "heart"), "a marker that does not exist");
        BAD(xlx_chart_series_set_marker(chart, 9, "circle"), "a marker on a series that does not exist");
        BAD(xlx_chart_set_title(chart, NULL), "no title");
        BAD(xlx_chart_set_title(chart, "=Sheet1"), "a title that begins with = and is no cell");
        xlx_chart_set_title(chart, "");
        ACCEPTED("an empty title turns the title off");
        BAD(xlx_chart_set_axis_title(chart, "x", ""), "an empty axis title");
        BAD(xlx_chart_set_axis_title(chart, "w", "x"), "a title on an axis that does not exist");
        BAD(xlx_chart_set_axis_title(chart, "y", "=1+1"), "an axis title that begins with = and is no cell");
        BAD(xlx_chart_set_axis_number_format(chart, "y", ""), "an empty axis number format");
        BAD(xlx_chart_set_axis_number_format(chart, NULL, "0"), "a number format on no axis");
        BAD(xlx_chart_set_axis_gridlines(chart, "", 1), "gridlines on no axis");
        BAD(xlx_chart_set_legend(chart, "middle"), "a legend position that does not exist");
        BAD(xlx_chart_set_style(chart, 0), "chart style 0");
        BAD(xlx_chart_set_style(chart, 49), "chart style 49");
        BAD(xlx_sheet_insert_chart(charts, 1, 12, chart, 0, 1), "a chart at scale 0");
        BAD(xlx_sheet_insert_chart(charts, 0, 12, chart, 1, 1), "a chart in row 0");
        BAD(xlx_sheet_insert_chart(charts, 1, 12, sheet, 1, 1), "a sheet handle where a chart belongs");
        /* `chart` and `scatter` are never put on a sheet: closing must cope */
    }

    /* ---- a second workbook: nothing of one may be used in the other ---- */
    {
        int other = xlx_workbook_new("xlsxt-smoke-other.xlsx");
        int otherSheet = xlx_workbook_add_sheet(other, "S");
        int otherFormat = xlx_workbook_add_format(other);
        int otherChart = xlx_workbook_add_chart(other, "line");
        CHECK(xlx_workbook_count() == 2, "two workbooks open");
        xlx_chart_add_series(otherChart, "", "=S!$A$1:$A$2");
        xlx_sheet_write_number(otherSheet, 1, 1, 1, f);
        REFUSED("a format of another workbook");
        CHECK(xlx_workbook_error_count(other) == 1 && xlx_workbook_error_count(book) == errors, "counted on the workbook written to");
        BAD(xlx_sheet_write_number(sheet, 1, 1, 1, otherFormat), "the same the other way");
        BAD(xlx_sheet_insert_chart(sheet, 1, 1, otherChart, 1, 1), "a chart of another workbook");
        xlx_workbook_discard(other);
        ACCEPTED("discarding a workbook");
        CHECK(!xlx_workbook_is_valid(other) && !xlx_sheet_is_valid(otherSheet) && !xlx_format_is_valid(otherFormat)
              && !xlx_chart_is_valid(otherChart) && xlx_chart_series_count(otherChart) == 0 && xlx_workbook_count() == 1,
              "discarding kills everything of it");
        CHECK(!file_exists("xlsxt-smoke-other.xlsx"), "and writes no file");
        xlx_workbook_discard(other);
        REFUSED("discarding twice");
        BAD(xlx_sheet_write_number(sheet, 1, 1, 1, otherFormat), "a format of a workbook that is gone");
        BAD(xlx_sheet_insert_chart(sheet, 1, 1, otherChart, 1, 1), "a chart of a workbook that is gone");
    }
#undef BAD

    CHECK(xlx_workbook_error_count(book) == errors, "the count is the refusals made: %d against %d", xlx_workbook_error_count(book), errors);
    CHECK(xlx_workbook_close(book) == 1, "the styled workbook is written: %s", xlx_last_error());
    CHECK(file_names(F_STYLE, "xl/charts/chart19.xml") && !file_names(F_STYLE, "xl/charts/chart20.xml"), "nineteen charts are in the file, and the two never placed are not");
    CHECK(file_names(F_STYLE, "xl/media/image1.png"), "the picture is in the file");
    CHECK(file_names(F_STYLE, "docProps/core.xml") && file_names(F_STYLE, "xl/styles.xml"), "and the properties and the styles");

    int r = xlx_read_open(F_STYLE);
    CHECK(r > 0 && xlx_read_sheet_count(r) == 2, "it reads back: %s", xlx_last_error());
    EQ(xlx_read_grid(r, 1, 1, 1, 3, 3), "Month\tSales\tCosts\nJan\t100\t80\nFeb\t115\t85");
    EQ(xlx_read_cell_format(r, 1, 1, 1), "0.00%");
    CHECK(xlx_read_row_count(r, 2) == 0 && xlx_read_column_count(r, 2) == 0, "a sheet of charts has no cells");
    EQ(xlx_read_grid(r, 2, 1, 1, 0, 0), "");
    xlx_read_close(r);
}

/* ------------------------------------------------------------------ */
static void test_grid(void)
{
    int book = xlx_workbook_new(F_GRID);
    int text = xlx_workbook_add_sheet(book, "text");
    int numbers = xlx_workbook_add_sheet(book, "numbers");
    int formulas = xlx_workbook_add_sheet(book, "formulas");
    static const char table[] =
        "name\tqty\tprice\r\n"
        "tea\t2\t3.50\n"
        "\t\t\n"
        "007\t+5\t-0.25\n"
        "1e3\t1234567890123456\t0x10\n"
        "=B2*C2\tline one\vline two\t  padded  \n"
        ".5\t5.\t1,5\n"
        "inf\tnan\t-\n"
        "last";
    CHECK(xlx_sheet_write_grid(text, 1, 1, table, "text", 0) == 22, "22 cells as text");
    CHECK(xlx_sheet_write_grid(numbers, 1, 1, table, "numbers", 0) == 22, "22 cells, numbers where they are numbers");
    CHECK(xlx_sheet_write_grid(formulas, 2, 3, table, "Formulas", 0) == 22, "22 cells, formulas too, from C2");
    ACCEPTED("the grids");
    CHECK(xlx_sheet_write_grid(text, 30, 1, "", "text", 0) == 0 && xlx_sheet_write_grid(text, 30, 1, NULL, "text", 0) == 0, "no text writes nothing");
    ACCEPTED("an empty grid");
    CHECK(xlx_sheet_write_grid(text, 30, 1, "a\tb", "sideways", 0) == 0, "a mode that does not exist writes nothing");
    REFUSED("a mode that does not exist");
    CHECK(xlx_sheet_write_grid(text, 0, 1, "a", "text", 0) == 0, "nor does row 0");
    CHECK(xlx_sheet_write_grid(text, 30, 1, "a\tb\xFF", "text", 0) == 0, "nor text that is not UTF-8");
    CHECK(xlx_sheet_write_grid(text, 30, 1, "a", "text", book) == 0, "nor a format that is none");
    CHECK(xlx_sheet_write_grid(book, 30, 1, "a", "text", 0) == 0, "nor a sheet that is none");
    /* a table that runs off the grid: what fits is written, the rest counted */
    int before = xlx_workbook_error_count(book);
    CHECK(xlx_sheet_write_grid(text, 1048576, 16383, "a\tb\tc\nd", "text", 0) == 2, "two cells fit at the corner of the grid");
    REFUSED("the cells past the edge");
    CHECK(strstr(xlx_last_error(), "row 1048576, column 16385") != NULL, "the reason names the first cell that did not fit: %s", xlx_last_error());
    CHECK(xlx_workbook_error_count(book) == before + 2, "and both are counted");
    CHECK(xlx_sheet_write_grid(text, 40, 1, "ok\tbell\x07\tok", "text", 0) == 2, "a cell with a control character is skipped, its neighbours written");
    CHECK(xlx_workbook_close(book) == 1, "the grid workbook is written: %s", xlx_last_error());

    int r = xlx_read_open(F_GRID);
    CHECK(r > 0, "and opens: %s", xlx_last_error());
    /* as text everything comes back as it went, bar the CR of the CRLF */
    EQ(xlx_read_grid(r, 1, 1, 1, 9, 0),
       "name\tqty\tprice\ntea\t2\t3.50\n\n007\t+5\t-0.25\n1e3\t1234567890123456\t0x10\n"
       "=B2*C2\tline one\vline two\t  padded  \n.5\t5.\t1,5\ninf\tnan\t-\nlast");
    EQ(xlx_read_cell_kind(r, 1, 2, 2), "text");
    EQ(xlx_read_cell(r, 1, 6, 2), "line one\nline two");
    EQ(xlx_read_cell(r, 1, 40, 1), "ok");
    EQ(xlx_read_cell(r, 1, 40, 2), "");
    EQ(xlx_read_cell(r, 1, 40, 3), "ok");
    EQ(xlx_read_cell(r, 1, 1048576, 16384), "b");
    /* as numbers: what a person would call a number, and nothing else */
    EQ(xlx_read_grid(r, 2, 1, 1, 9, 0),
       "name\tqty\tprice\ntea\t2\t3.5\n\n007\t5\t-0.25\n1000\t1234567890123456\t0x10\n"
       "=B2*C2\tline one\vline two\t  padded  \n0.5\t5\t1,5\ninf\tnan\t-\nlast");
    EQ(xlx_read_cell_kind(r, 2, 2, 2), "number");
    EQ(xlx_read_cell_kind(r, 2, 4, 1), "text");                /* 007 keeps its zeros   */
    EQ(xlx_read_cell_kind(r, 2, 5, 2), "text");                /* 16 digits: a card no. */
    EQ(xlx_read_cell_kind(r, 2, 5, 1), "number");
    EQ(xlx_read_cell_kind(r, 2, 8, 1), "text");                /* "inf" is a word       */
    EQ(xlx_read_cell_kind(r, 2, 6, 1), "text");                /* a formula is text here */
    EQ(xlx_read_cell_formula(r, 2, 6, 1), "");
    /* as formulas */
    EQ(xlx_read_cell_formula(r, 3, 7, 3), "=B2*C2");
    EQ(xlx_read_cell(r, 3, 3, 4), "2");
    EQ(xlx_read_cell(r, 3, 2, 3), "name");
    CHECK(xlx_read_column_count(r, 3) == 5 && xlx_read_row_count(r, 3) == 10, "the block landed at C2");
    xlx_read_close(r);
}

/* ------------------------------------------------------------------ */
/* A file libxlsxwriter did not write.                                 */
/* ------------------------------------------------------------------ */
#define X_HEAD "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
#define X_MAIN "xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""
#define X_REL  "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

static void test_foreign(void)
{
    /* A workbook whose parts are NOT where libxlsxwriter puts them: the
     * workbook under another name, an absolute target, a climbing one, a
     * prefix on every element, a 1904 date system, a hidden sheet, a sheet
     * with no part and a sheet whose part is missing from the zip. */
    static const char rels[] = X_HEAD
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId9\" Type=\"http://example.org/other\" Target=\"docProps/app.xml\"/>"
        "<Relationship Id=\"rId1\" Type=\"" X_REL "/officeDocument\" Target=\"/book/wb.xml\"/></Relationships>";
    static const char workbook[] = X_HEAD
        "<x:workbook xmlns:x=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"" X_REL "\">"
        "<x:workbookPr date1904=\"1\"/><x:sheets>"
        "<x:sheet name=\"First &amp; foremost\" sheetId=\"7\" r:id=\"rIdA\"/>"
        "<x:sheet name=\"Hidden\" sheetId=\"2\" state=\"hidden\" r:id=\"rIdB\"/>"
        "<x:sheet name=\"Very\" sheetId=\"3\" state=\"veryHidden\" r:id=\"rIdC\"/>"
        "<x:sheet name=\"NoPart\" sheetId=\"4\" r:id=\"rIdNone\"/>"
        "<x:sheet name=\"Missing\" sheetId=\"5\" r:id=\"rIdD\"/>"
        "<x:sheet name=\"Outside\" sheetId=\"6\" r:id=\"rIdE\"/>"
        "</x:sheets></x:workbook>";
    static const char workbook_rels[] = X_HEAD
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rIdA\" Type=\"" X_REL "/worksheet\" Target=\"/sheets/one.xml\"/>"
        "<Relationship Id=\"rIdB\" Type=\"" X_REL "/worksheet\" Target=\"../book/./two.xml\"/>"
        "<Relationship Id=\"rIdC\" Type=\"" X_REL "/worksheet\" Target=\"three.xml\"/>"
        "<Relationship Id=\"rIdD\" Type=\"" X_REL "/worksheet\" Target=\"gone.xml\"/>"
        "<Relationship Id=\"rIdE\" Type=\"" X_REL "/worksheet\" Target=\"../../etc/passwd\"/>"
        "<Relationship Id=\"rIdX\" Type=\"" X_REL "/hyperlink\" Target=\"http://example.org\" TargetMode=\"External\"/>"
        "<Relationship Id=\"rIdS\" Type=\"" X_REL "/sharedStrings\" Target=\"text/strings.xml\"/>"
        "<Relationship Id=\"rIdT\" Type=\"" X_REL "/styles\" Target=\"look.xml\"/></Relationships>";
    static const char strings[] = X_HEAD
        "<sst " X_MAIN " count=\"6\" uniqueCount=\"6\">"
        "<si><t>plain</t></si>"
        "<si><r><rPr><b/></rPr><t>rich </t></r><r><t xml:space=\"preserve\">text </t></r><r><t>joined</t></r></si>"
        "<si><t>kanji</t><rPh sb=\"0\" eb=\"1\"><t>READING</t></rPh><phoneticPr fontId=\"1\"/></si>"
        "<si><t>line_x000D__x000A_break and _x005F_x0041_ kept and _x00e9_ and _xZZZZ_ left</t></si>"
        "<si/>"
        "<si><t>caf&#233; &lt;&amp;&gt; &#x20AC;</t></si>"
        "</sst>";
    /* cell formats: 0 General, 1 built-in date 14, 2 custom date, 3 custom
     * NOT a date (the word in quotes, the colour tag), 4 built-in time 20,
     * 5 elapsed time, 6 a format id nobody defined, 7 percent */
    static const char styles[] = X_HEAD
        "<styleSheet " X_MAIN "><numFmts count=\"3\">"
        "<numFmt numFmtId=\"164\" formatCode=\"dd/mm/yyyy\\ hh:mm\"/>"
        "<numFmt numFmtId=\"165\" formatCode=\"[Red]0.0&quot; days&quot;\"/>"
        "<numFmt numFmtId=\"166\" formatCode=\"[h]:mm\"/></numFmts>"
        "<cellStyleXfs count=\"1\"><xf numFmtId=\"14\"/></cellStyleXfs>"
        "<cellXfs count=\"8\"><xf numFmtId=\"0\"/><xf numFmtId=\"14\"/><xf numFmtId=\"164\"/><xf numFmtId=\"165\"/>"
        "<xf numFmtId=\"20\"/><xf numFmtId=\"166\"/><xf numFmtId=\"999\"/><xf numFmtId=\"9\"/></cellXfs></styleSheet>";
    static const char one[] = X_HEAD
        "<x:worksheet xmlns:x=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><x:dimension ref=\"A1:Z99\"/><x:sheetData>"
        "<x:row r=\"1\">"
          "<x:c r=\"A1\" t=\"s\"><x:v>0</x:v></x:c><x:c r=\"B1\" t=\"s\"><x:v>1</x:v></x:c><x:c r=\"C1\" t=\"s\"><x:v>2</x:v></x:c>"
          "<x:c r=\"D1\" t=\"s\"><x:v>3</x:v></x:c><x:c r=\"E1\" t=\"s\"><x:v>4</x:v></x:c><x:c r=\"F1\" t=\"s\"><x:v>5</x:v></x:c>"
          "<x:c r=\"G1\" t=\"s\"><x:v>6</x:v></x:c><x:c r=\"H1\" t=\"s\"><x:v>nonsense</x:v></x:c></x:row>"
        "<x:row r=\"2\">"
          "<x:c r=\"A2\" t=\"inlineStr\"><x:is><x:t>inline</x:t></x:is></x:c>"
          "<x:c r=\"B2\" t=\"inlineStr\"><x:is><x:r><x:t>in</x:t></x:r><x:r><x:t>line rich</x:t></x:r><x:rPh><x:t>NO</x:t></x:rPh></x:is></x:c>"
          "<x:c r=\"C2\" t=\"str\"><x:f>A2&amp;\"!\"</x:f><x:v>inline!</x:v></x:c>"
          "<x:c r=\"D2\" t=\"b\"><x:v>1</x:v></x:c><x:c r=\"E2\" t=\"b\"><x:v>0</x:v></x:c>"
          "<x:c r=\"F2\" t=\"e\"><x:v>#DIV/0!</x:v></x:c>"
          "<x:c r=\"G2\" t=\"d\"><x:v>2024-03-05T10:00:00Z</x:v></x:c></x:row>"
        "<x:row r=\"3\">"
          "<x:c r=\"A3\" s=\"1\"><x:v>43831</x:v></x:c><x:c r=\"B3\" s=\"2\"><x:v>43831.5</x:v></x:c>"
          "<x:c r=\"C3\" s=\"3\"><x:v>2.5</x:v></x:c><x:c r=\"D3\" s=\"4\"><x:v>0.75</x:v></x:c>"
          "<x:c r=\"E3\" s=\"5\"><x:v>1.5</x:v></x:c><x:c r=\"F3\" s=\"6\"><x:v>12</x:v></x:c>"
          "<x:c r=\"G3\" s=\"7\"><x:v>0.25</x:v></x:c><x:c r=\"H3\" s=\"99\"><x:v>7</x:v></x:c>"
          "<x:c r=\"I3\" s=\"1\"><x:v>-3</x:v></x:c><x:c r=\"J3\" s=\"1\"><x:v>0</x:v></x:c></x:row>"
        /* a row and cells with no references: they follow on */
        "<x:row><x:c><x:v>1</x:v></x:c><x:c><x:v>2.50</x:v></x:c><x:c t=\"n\"><x:v>1.0E-3</x:v></x:c><x:c><x:v>oops</x:v></x:c><x:c><x:v></x:v></x:c><x:c/></x:row>"
        /* cells out of order, and one named twice: the later stands */
        "<x:row r=\"9\"><x:c r=\"C9\"><x:v>3</x:v></x:c><x:c r=\"A9\"><x:v>1</x:v></x:c><x:c r=\"B9\"><x:v>2</x:v></x:c><x:c r=\"A9\"><x:v>11</x:v></x:c></x:row>"
        /* a row that says 7 holding a cell that says row 8: the cell is believed */
        "<x:row r=\"7\"><x:c r=\"B8\"><x:v>88</x:v></x:c><x:c r=\"A7\"><x:f>1+1</x:f></x:c><x:c r=\"C7\"><x:f t=\"shared\" si=\"0\"/><x:v>5</x:v></x:c></x:row>"
        "</x:sheetData><x:mergeCells count=\"3\"><x:mergeCell ref=\"A1:B2\"/><x:mergeCell ref=\"nonsense\"/><x:mergeCell ref=\"C3:D4\"/></x:mergeCells>"
        "</x:worksheet>";
    static const char two[] = X_HEAD "<worksheet " X_MAIN "><sheetData><row r=\"1\"><c r=\"A1\"><v>2</v></c></row></sheetData></worksheet>";
    static const char three[] = X_HEAD "<worksheet " X_MAIN "><sheetData/></worksheet>";
    TzPart parts[] = {
        {"_rels/.rels", rels, sizeof rels - 1}, {"book/wb.xml", workbook, sizeof workbook - 1},
        {"book/_rels/wb.xml.rels", workbook_rels, sizeof workbook_rels - 1},
        {"book/text/strings.xml", strings, sizeof strings - 1}, {"book/look.xml", styles, sizeof styles - 1},
        {"sheets/one.xml", one, sizeof one - 1}, {"book/two.xml", two, sizeof two - 1},
        {"book/three.xml", three, sizeof three - 1}};
    CHECK(tz_write(F_FOREIGN, parts, 8, -1), "the foreign file is written");

    int r = xlx_read_open(F_FOREIGN);
    CHECK(r > 0, "a file with its parts in other places opens: %s", xlx_last_error());
    CHECK(xlx_read_sheet_count(r) == 6, "six sheets: %d", xlx_read_sheet_count(r));
    EQ(xlx_read_sheet_name(r, 1), "First & foremost");
    CHECK(xlx_read_uses_1904(r), "it counts from 1904");
    CHECK(!xlx_read_sheet_is_hidden(r, 1) && xlx_read_sheet_is_hidden(r, 2) && xlx_read_sheet_is_hidden(r, 3), "hidden and very hidden");
    CHECK(xlx_read_load(r, 1), "the first sheet loads: %s", xlx_last_error());

    EQ(xlx_read_cell(r, 1, 1, 1), "plain");
    EQ(xlx_read_cell(r, 1, 1, 2), "rich text joined");
    EQ(xlx_read_cell(r, 1, 1, 3), "kanji");                   /* not its phonetic guide */
    EQ(xlx_read_cell(r, 1, 1, 4), "line\r\nbreak and _x0041_ kept and \xC3\xA9 and _xZZZZ_ left");
    EQ(xlx_read_cell(r, 1, 1, 5), "");
    EQ(xlx_read_cell_kind(r, 1, 1, 5), "text");
    EQ(xlx_read_cell(r, 1, 1, 6), "caf\xC3\xA9 <&> \xE2\x82\xAC");
    EQ(xlx_read_cell(r, 1, 1, 7), "");                        /* string 6 of 6 does not exist */
    EQ(xlx_read_cell_kind(r, 1, 1, 8), "empty");              /* an index that is no number   */
    EQ(xlx_read_cell(r, 1, 2, 1), "inline");
    EQ(xlx_read_cell(r, 1, 2, 2), "inline rich");
    EQ(xlx_read_cell(r, 1, 2, 3), "inline!");
    EQ(xlx_read_cell_formula(r, 1, 2, 3), "=A2&\"!\"");
    EQ(xlx_read_cell(r, 1, 2, 4), "true");
    EQ(xlx_read_cell(r, 1, 2, 5), "false");
    EQ(xlx_read_cell(r, 1, 2, 6), "#DIV/0!");
    EQ(xlx_read_cell_kind(r, 1, 2, 6), "error");
    EQ(xlx_read_cell(r, 1, 2, 7), "2024-03-05T10:00:00Z");
    EQ(xlx_read_cell_kind(r, 1, 2, 7), "text");
    /* 1904: serial 43831 is 2024-01-02 (it would be 2020-01-01 from 1900) */
    EQ(xlx_read_cell(r, 1, 3, 1), "2024-01-02");
    EQ(xlx_read_cell_kind(r, 1, 3, 1), "date");
    EQ(xlx_read_cell_format(r, 1, 3, 1), "mm-dd-yy");
    EQ(xlx_read_cell(r, 1, 3, 2), "2024-01-02 12:00:00");
    EQ(xlx_read_cell_format(r, 1, 3, 2), "dd/mm/yyyy\\ hh:mm");
    EQ(xlx_read_cell(r, 1, 3, 3), "2.5");                     /* "days" in quotes is no date */
    EQ(xlx_read_cell_kind(r, 1, 3, 3), "number");
    EQ(xlx_read_cell(r, 1, 3, 4), "1904-01-01 18:00:00");
    EQ(xlx_read_cell_kind(r, 1, 3, 5), "date");               /* [h]:mm */
    EQ(xlx_read_cell_kind(r, 1, 3, 6), "number");             /* an id nobody defined */
    EQ(xlx_read_cell_format(r, 1, 3, 6), "General");
    EQ(xlx_read_cell(r, 1, 3, 7), "0.25");
    EQ(xlx_read_cell_format(r, 1, 3, 7), "0%");
    EQ(xlx_read_cell_format(r, 1, 3, 8), "General");          /* a style index past the list */
    EQ(xlx_read_cell(r, 1, 3, 9), "-3");                      /* a date format on what is no date */
    EQ(xlx_read_cell_kind(r, 1, 3, 9), "number");
    EQ(xlx_read_cell(r, 1, 3, 10), "1904-01-01");
    /* the row with no references is row 4, its cells A to F */
    EQ(xlx_read_grid(r, 1, 4, 1, 4, 0), "1\t2.5\t0.001\toops");
    EQ(xlx_read_cell_kind(r, 1, 4, 4), "text");
    EQ(xlx_read_cell_kind(r, 1, 4, 5), "empty");
    EQ(xlx_read_grid(r, 1, 9, 1, 9, 0), "11\t2\t3");
    EQ(xlx_read_cell(r, 1, 8, 2), "88");
    EQ(xlx_read_cell_formula(r, 1, 7, 1), "=1+1");
    EQ(xlx_read_cell(r, 1, 7, 1), "");
    EQ(xlx_read_cell_kind(r, 1, 7, 1), "empty");
    EQ(xlx_read_cell(r, 1, 7, 3), "5");
    EQ(xlx_read_cell_formula(r, 1, 7, 3), "");                /* shared: only the first holds the text */
    EQ(xlx_read_merged(r, 1), "A1:B2\nC3:D4");
    CHECK(xlx_read_row_count(r, 1) == 9 && xlx_read_column_count(r, 1) == 10, "what the cells say, not what <dimension> says");

    EQ(xlx_read_cell(r, 2, 1, 1), "2");
    CHECK(xlx_read_load(r, 3) && xlx_read_row_count(r, 3) == 0, "an empty sheet loads and is empty");
    CHECK(!xlx_read_load(r, 4), "a sheet with no part does not load");
    CHECK(strstr(xlx_last_error(), "does not say where sheet 4") != NULL, "and says why: %s", xlx_last_error());
    CHECK(!xlx_read_load(r, 5), "a sheet whose part is not in the zip does not load");
    CHECK(strstr(xlx_last_error(), "lists sheet 5 but does not hold it") != NULL, "and says why: %s", xlx_last_error());
    CHECK(!xlx_read_load(r, 6), "a sheet whose part climbs out of the file does not load: %s", xlx_last_error());
    EQ(xlx_read_cell(r, 1, 1, 1), "plain");                   /* and the reader is still good */
    xlx_read_close(r);

    /* A file with no shared strings and no styles at all, and no workbook
     * relationship in _rels/.rels: xl/workbook.xml is assumed. */
    {
        static const char sheet[] = TZ_SHEET_OPEN "<row r=\"2\"><c r=\"B2\" t=\"s\"><v>0</v></c><c r=\"C2\" s=\"3\"><v>44000</v></c></row>" TZ_SHEET_CLOSE;
        static const char bare_rels[] = X_HEAD "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>";
        TzPart bare[] = {{"_rels/.rels", bare_rels, sizeof bare_rels - 1}, {"xl/workbook.xml", TZ_WORKBOOK, sizeof TZ_WORKBOOK - 1},
                         {"xl/_rels/workbook.xml.rels", TZ_WORKBOOK_RELS, sizeof TZ_WORKBOOK_RELS - 1},
                         {"xl/worksheets/sheet1.xml", sheet, sizeof sheet - 1}};
        CHECK(tz_write(F_FOREIGN, bare, 4, -1), "a bare file is written");
        r = xlx_read_open(F_FOREIGN);
        CHECK(r > 0 && xlx_read_load(r, 1), "a file without strings or styles loads: %s", xlx_last_error());
        EQ(xlx_read_cell(r, 1, 2, 2), "");
        EQ(xlx_read_cell(r, 1, 2, 3), "44000");
        EQ(xlx_read_cell_kind(r, 1, 2, 3), "number");
        xlx_read_close(r);
        /* and with no _rels/.rels at all */
        CHECK(tz_write(F_FOREIGN, bare + 1, 3, -1), "a file with no root relationships is written");
        r = xlx_read_open(F_FOREIGN);
        CHECK(r > 0 && xlx_read_cell_number(r, 1, 2, 3) == 44000, "and reads: %s", xlx_last_error());
        xlx_read_close(r);
    }
}

/* ------------------------------------------------------------------ */
/* Files that are not spreadsheets, or are damaged ones.               */
/* ------------------------------------------------------------------ */
static void bad_sheet(const char *what, const char *sheet_xml, const char *reason)
{
    CHECK(tz_workbook(F_BAD, sheet_xml, NULL, NULL), "%s: the file is written", what);
    int r = xlx_read_open(F_BAD);
    CHECK(r > 0, "%s: the workbook itself opens: %s", what, xlx_last_error());
    CHECK(xlx_read_load(r, 1) == 0, "%s: the sheet does not load", what);
    CHECK(strstr(xlx_last_error(), reason) != NULL, "%s: the reason is \"%s\", wanted one naming \"%s\"", what, xlx_last_error(), reason);
    CHECK(xlx_read_row_count(r, 1) == 0, "%s: and it holds nothing", what);
    EQ(xlx_read_cell(r, 1, 1, 1), "");
    EQ(xlx_read_grid(r, 1, 1, 1, 0, 0), "");
    xlx_read_close(r);
}

static void bad_file(const char *what, const char *bytes, size_t n, const char *reason)
{
    write_bytes(F_BAD, bytes, n);
    int r = xlx_read_open(F_BAD);
    CHECK(r == 0, "%s: does not open", what);
    CHECK(strstr(xlx_last_error(), reason) != NULL, "%s: the reason is \"%s\", wanted one naming \"%s\"", what, xlx_last_error(), reason);
    if (r) xlx_read_close(r);
}

static void test_damaged(void)
{
    CHECK(xlx_read_open("xlsxt-smoke-no-such-file.xlsx") == 0, "a file that is not there does not open");
    EQ(xlx_last_error(), "the file cannot be opened");
    CHECK(xlx_read_open("") == 0 && xlx_read_open(NULL) == 0 && xlx_read_open("bad\x01path") == 0, "nor does no path");
    REFUSED("no path");
    bad_file("an empty file", "", 0, "not a .xlsx file");
    bad_file("a text file", "name,qty\ntea,2\n", 15, "a zip archive, and this is not one");
    bad_file("an old .xls", "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1" "rest of it", 18, "older .xls format");
    bad_file("a zip signature and nothing else", "PK\x03\x04", 4, "zip directory cannot be read");
    bad_file("a zip cut short", "PK\x03\x04\x14\x00\x00\x00\x08\x00garbage garbage garbage garbage", 41, "zip directory cannot be read");
    {
        TzPart other[] = {{"hello.txt", "hello", 5}};
        CHECK(tz_write(F_BAD, other, 1, -1), "a zip that is no workbook is written");
        CHECK(xlx_read_open(F_BAD) == 0, "a zip that is no workbook does not open");
        CHECK(strstr(xlx_last_error(), "holds no xl/workbook.xml") != NULL, "and says why: %s", xlx_last_error());
    }
    {
        static const char empty[] = X_HEAD "<workbook " X_MAIN "><sheets/></workbook>";
        TzPart parts[] = {{"xl/workbook.xml", empty, sizeof empty - 1}};
        CHECK(tz_write(F_BAD, parts, 1, -1) && xlx_read_open(F_BAD) == 0, "a workbook with no sheets does not open");
        EQ(xlx_last_error(), "the workbook lists no sheets");
    }
    {
        static const char broken[] = X_HEAD "<workbook " X_MAIN "><sheets><sheet name=\"A\" r:id=\"rId1\"/></sheets>";
        TzPart parts[] = {{"xl/workbook.xml", broken, sizeof broken - 1}};
        CHECK(tz_write(F_BAD, parts, 1, -1) && xlx_read_open(F_BAD) == 0, "a workbook that is not well-formed does not open");
        CHECK(strstr(xlx_last_error(), "not well-formed XML") != NULL, "and says why: %s", xlx_last_error());
    }
    {
        /* the billion-laughs shape: refused at the DOCTYPE, before any entity */
        static const char laughs[] = "<?xml version=\"1.0\"?><!DOCTYPE lolz [<!ENTITY lol \"lol\"><!ENTITY lol2 \"&lol;&lol;&lol;&lol;\">]>"
            "<workbook " X_MAIN "><sheets><sheet name=\"&lol2;\" sheetId=\"1\" id=\"x\"/></sheets></workbook>";
        TzPart parts[] = {{"xl/workbook.xml", laughs, sizeof laughs - 1}};
        CHECK(tz_write(F_BAD, parts, 1, -1) && xlx_read_open(F_BAD) == 0, "a part with a DOCTYPE does not open");
        CHECK(strstr(xlx_last_error(), "DOCTYPE") != NULL, "and says why: %s", xlx_last_error());
    }
    {
        /* a checksum that does not match what the part holds */
        TzPart parts[] = {{"_rels/.rels", TZ_RELS, sizeof TZ_RELS - 1}, {"xl/workbook.xml", TZ_WORKBOOK, sizeof TZ_WORKBOOK - 1}};
        CHECK(tz_write(F_BAD, parts, 2, 1) && xlx_read_open(F_BAD) == 0, "a part with a wrong checksum does not open");
        CHECK(strstr(xlx_last_error(), "checksum") != NULL, "and says why: %s", xlx_last_error());
    }
    bad_sheet("a cell outside the grid", TZ_SHEET_OPEN "<row r=\"1\"><c r=\"XFE1\"><v>1</v></c></row>" TZ_SHEET_CLOSE, "outside the grid");
    bad_sheet("a cell in row 0", TZ_SHEET_OPEN "<row r=\"1\"><c r=\"A0\"><v>1</v></c></row>" TZ_SHEET_CLOSE, "outside the grid");
    bad_sheet("a row past the grid", TZ_SHEET_OPEN "<row r=\"1048577\"><c><v>1</v></c></row>" TZ_SHEET_CLOSE, "outside the grid");
    bad_sheet("a row numbered with words", TZ_SHEET_OPEN "<row r=\"one\"><c><v>1</v></c></row>" TZ_SHEET_CLOSE, "outside the grid");
    bad_sheet("a row number that overflows", TZ_SHEET_OPEN "<row r=\"99999999999999999999\"><c><v>1</v></c></row>" TZ_SHEET_CLOSE, "outside the grid");
    bad_sheet("a sheet cut short", TZ_SHEET_OPEN "<row r=\"1\"><c r=\"A1\"><v>1</v></c>", "not well-formed XML");
    bad_sheet("a sheet that is not XML", "this is not XML at all", "not well-formed XML");
    bad_sheet("a sheet with a DOCTYPE", "<?xml version=\"1.0\"?><!DOCTYPE worksheet SYSTEM \"file:///etc/passwd\"><worksheet/>", "DOCTYPE");
    bad_sheet("an empty sheet part", "", "not well-formed XML");
    {
        /* more unreferenced cells in one row than the grid has columns */
        static char wide[16500 * 4 + 512];
        size_t n = (size_t)snprintf(wide, sizeof wide, "%s<row>", TZ_SHEET_OPEN);
        for (int i = 0; i < 16385; i++) { memcpy(wide + n, "<c/>", 4); n += 4; }
        snprintf(wide + n, sizeof wide - n, "</row>%s", TZ_SHEET_CLOSE);
        bad_sheet("a row of 16385 cells", wide, "more cells than the grid has columns");
    }
    {
        /* shared strings that are damaged: the sheet does not load, twice */
        static const char sheet[] = TZ_SHEET_OPEN "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c></row>" TZ_SHEET_CLOSE;
        CHECK(tz_workbook(F_BAD, sheet, "<sst><si><t>cut", NULL), "a file with damaged strings is written");
        int r = xlx_read_open(F_BAD);
        CHECK(r > 0 && !xlx_read_load(r, 1), "damaged shared strings stop the sheet loading");
        CHECK(strstr(xlx_last_error(), "sharedStrings.xml is not well-formed") != NULL, "and say why: %s", xlx_last_error());
        CHECK(!xlx_read_load(r, 1) && xlx_last_error()[0] != 0, "and again the second time, still with a reason: %s", xlx_last_error());
        xlx_read_close(r);
        CHECK(tz_workbook(F_BAD, sheet, NULL, "<styleSheet><cellXfs><xf"), "a file with damaged styles is written");
        r = xlx_read_open(F_BAD);
        CHECK(r > 0 && !xlx_read_load(r, 1) && strstr(xlx_last_error(), "styles.xml") != NULL, "damaged styles too: %s", xlx_last_error());
        CHECK(!xlx_read_load(r, 1) && xlx_last_error()[0] != 0, "and again the second time: %s", xlx_last_error());
        xlx_read_close(r);
    }
    {
        /* a real file, cut at every eighth of its length: never a fault,
         * and never a sheet that claims to have loaded half of itself */
        FILE *f = fopen(F_BASIC, "rb");
        static char bytes[1 << 17];
        size_t n = f ? fread(bytes, 1, sizeof bytes, f) : 0;
        if (f) fclose(f);
        CHECK(n > 2000 && n < sizeof bytes, "the basic workbook is there to be cut (%u bytes)", (unsigned)n);
        for (int eighth = 1; eighth < 8; eighth++) {
            write_bytes(F_BAD, bytes, n * (size_t)eighth / 8);
            int r = xlx_read_open(F_BAD);
            CHECK(r == 0 && xlx_last_error()[0] != 0, "a file cut at %d/8 does not open, with a reason", eighth);
            if (r) xlx_read_close(r);
        }
        /* and with one byte of its compressed data changed, at many places */
        int opened = 0, loaded = 0;
        for (size_t at = 60; at < n - 400; at += n / 97) {
            char keep = bytes[at];
            bytes[at] = (char)(keep ^ 0x55);
            write_bytes(F_BAD, bytes, n);
            bytes[at] = keep;
            int r = xlx_read_open(F_BAD);
            if (r) {
                opened++;
                for (int s = 1; s <= 3; s++) if (xlx_read_load(r, s)) { loaded++; (void)xlx_read_grid(r, s, 1, 1, 0, 0); }
                xlx_read_close(r);
            }
        }
        CHECK(opened >= 0 && loaded >= 0, "flipped bytes are survived (%d opened, %d sheets loaded)", opened, loaded);
        CHECK(xlx_read_count() == 0, "and every reader was closed");
    }
}

/* ------------------------------------------------------------------ */
/* Handles: stale ones stay dead, slots are reused, nothing leaks.     */
/* ------------------------------------------------------------------ */
static void test_handles(void)
{
    /* every call on handles that never were */
    static const int dead[] = {0, -1, 1, 7, 0x7FFFFFFF, -2147483647 - 1, 123456789};
    for (size_t i = 0; i < sizeof dead / sizeof dead[0]; i++) {
        int h = dead[i];
        CHECK(!xlx_workbook_is_valid(h) && !xlx_sheet_is_valid(h) && !xlx_format_is_valid(h) && !xlx_chart_is_valid(h)
              && !xlx_read_is_valid(h), "handle %d is nothing", h);
        CHECK(xlx_workbook_add_sheet(h, "x") == 0 && xlx_workbook_add_format(h) == 0 && xlx_workbook_add_chart(h, "line") == 0
              && xlx_workbook_close(h) == 0 && xlx_chart_add_series(h, "", "=S!A1") == 0, "and makes nothing");
        REFUSED("a call on a handle that is nothing");
        xlx_format_set_bold(h, 1);
        REFUSED("a format call on a handle that is nothing");
        xlx_sheet_write_number(h, 1, 1, 1, 0);
        REFUSED("a sheet call on a handle that is nothing");
        xlx_chart_set_title(h, "x");
        REFUSED("a chart call on a handle that is nothing");
        xlx_workbook_set_property(h, "title", "x");
        xlx_workbook_define_name(h, "a", "=b");
        xlx_workbook_discard(h);
        EQ(xlx_workbook_first_error(h), "");
    }
    /* a slot is reused, and the old handle to it stays dead */
    int first = xlx_workbook_new("xlsxt-smoke-handles.xlsx");
    int firstSheet = xlx_workbook_add_sheet(first, "A");
    xlx_workbook_discard(first);
    int again = xlx_workbook_new("xlsxt-smoke-handles.xlsx");
    int againSheet = xlx_workbook_add_sheet(again, "B");
    CHECK(again != first && againSheet != firstSheet, "a reused slot gives a new handle (%d then %d)", first, again);
    CHECK(!xlx_workbook_is_valid(first) && !xlx_sheet_is_valid(firstSheet) && xlx_workbook_is_valid(again) && xlx_sheet_is_valid(againSheet),
          "and the old one stays dead");
    xlx_sheet_write_text(firstSheet, 1, 1, "to a dead sheet", 0);
    REFUSED("a write to a dead sheet");
    CHECK(xlx_workbook_error_count(again) == 0, "which the live workbook does not count");
    xlx_workbook_discard(again);
    /* many at once, then many in turn */
    enum { MANY = 300 };
    static int books[MANY];
    for (int i = 0; i < MANY; i++) {
        books[i] = xlx_workbook_new("xlsxt-smoke-handles.xlsx");
        xlx_workbook_add_sheet(books[i], "");
        xlx_workbook_add_format(books[i]);
    }
    CHECK(xlx_workbook_count() == MANY && books[MANY - 1] > 0, "%d workbooks open at once", MANY);
    for (int i = 0; i < MANY; i++) xlx_workbook_discard(books[i]);
    CHECK(xlx_workbook_count() == 0, "and all discarded");
    for (int i = 0; i < 5000; i++) {
        int b = xlx_workbook_new("xlsxt-smoke-handles.xlsx");
        if (b <= 0 || !xlx_workbook_is_valid(b)) { CHECK(0, "workbook %d of 5000 in turn could not be made: %s", i, xlx_last_error()); break; }
        xlx_workbook_discard(b);
        if (xlx_workbook_is_valid(b)) { CHECK(0, "workbook %d of 5000 outlived its discard", i); break; }
    }
    CHECK(xlx_workbook_count() == 0, "5000 workbooks in turn leave none");
    for (int i = 0; i < 3000; i++) {
        int r = xlx_read_open(F_BASIC);
        if (r <= 0) { CHECK(0, "reader %d of 3000 in turn could not be opened: %s", i, xlx_last_error()); break; }
        xlx_read_close(r);
    }
    CHECK(xlx_read_count() == 0, "3000 readers in turn leave none");
}

/* ------------------------------------------------------------------ */
/* Where the file goes, and where it cannot.                           */
/* ------------------------------------------------------------------ */
static void test_paths(void)
{
    CHECK(xlx_workbook_new("") == 0 && xlx_workbook_new(NULL) == 0 && xlx_workbook_new("bad\npath.xlsx") == 0
          && xlx_workbook_new("bad\xFFpath.xlsx") == 0, "no path, no workbook");
    REFUSED("a path that is not text");
    /* a folder that is not there: found when the file is written */
    int book = xlx_workbook_new("xlsxt-smoke-no-such-folder/out.xlsx");
    CHECK(book > 0, "a workbook for a folder that is not there is still made");
    xlx_sheet_write_number(xlx_workbook_add_sheet(book, ""), 1, 1, 1, 0);
    CHECK(xlx_workbook_close(book) == 0, "and closing it fails");
    REFUSED("writing into a folder that is not there");
    CHECK(xlx_workbook_count() == 0 && !xlx_workbook_is_valid(book), "but the workbook is gone all the same");
    /* a path that is not ASCII, written and read */
    book = xlx_workbook_new(F_UTF8);
    xlx_sheet_write_text(xlx_workbook_add_sheet(book, "\xC3\x89t\xC3\xA9"), 1, 1, "\xE2\x98\x80", 0);
    CHECK(xlx_workbook_close(book) == 1, "a path with accents is written: %s", xlx_last_error());
    int r = xlx_read_open(F_UTF8);
    CHECK(r > 0, "and read: %s", xlx_last_error());
    EQ(xlx_read_sheet_name(r, 1), "\xC3\x89t\xC3\xA9");
    EQ(xlx_read_cell(r, 1, 1, 1), "\xE2\x98\x80");
    xlx_read_close(r);
    /* an empty workbook is a workbook: libxlsxwriter gives it one sheet */
    book = xlx_workbook_new(F_BAD);
    CHECK(xlx_workbook_close(book) == 1, "a workbook with nothing in it is written: %s", xlx_last_error());
    r = xlx_read_open(F_BAD);
    CHECK(r > 0 && xlx_read_sheet_count(r) == 1 && xlx_read_load(r, 1) && xlx_read_row_count(r, 1) == 0, "and read: one empty sheet");
    xlx_read_close(r);
    /* the temp folder: one that works, then one that is not there */
    xlx_set_temp_folder(".");
    book = xlx_workbook_new(F_BAD);
    xlx_sheet_write_text(xlx_workbook_add_sheet(book, ""), 1, 1, "via .", 0);
    CHECK(xlx_workbook_close(book) == 1, "a workbook is written with its temporary files in '.': %s", xlx_last_error());
    xlx_set_temp_folder("xlsxt-smoke-no-such-folder");
    book = xlx_workbook_new(F_BAD);
    xlx_sheet_write_text(xlx_workbook_add_sheet(book, ""), 1, 1, "nowhere", 0);
    /* tmpfileplus tries the folder it was given, then the TMPDIR, TMP and
     * TEMP of the environment, then the system's own: a bad folder costs
     * nothing but the choice */
    CHECK(xlx_workbook_close(book) == 1, "and still is when the temp folder is not there (the system's is used): %s", xlx_last_error());
    xlx_set_temp_folder("");
    r = xlx_read_open(F_BAD);
    if (r) xlx_read_close(r);                 /* whatever was left must not fault */
}

/* ------------------------------------------------------------------ */
/* Numbers are written and read with a "." whatever the locale says.   */
/* ------------------------------------------------------------------ */
static void test_locale(void)
{
    static const char *const names[] = {"de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "fr_FR.utf8", "German_Germany.1252", "de_DE", "fr_FR"};
    const char *set = NULL;
    for (size_t i = 0; i < sizeof names / sizeof names[0] && !set; i++) set = setlocale(LC_ALL, names[i]);
    char probe[32];
    snprintf(probe, sizeof probe, "%.1f", 1.5);
    int comma = strchr(probe, ',') != NULL;
    printf("locale: %s (printf writes %s)\n", set ? set : "no comma locale installed; the C locale is tested", probe);

    int book = xlx_workbook_new(F_BAD);
    int sheet = xlx_workbook_add_sheet(book, "");
    xlx_sheet_write_number(sheet, 1, 1, 1234.5678, 0);
    CHECK(xlx_sheet_write_grid(sheet, 2, 1, "0.25\t1,5\t-2.5e3", "numbers", 0) == 3, "a grid of numbers under this locale");
    xlx_sheet_write_date(sheet, 3, 1, 45292.5, 0);
    xlx_sheet_set_columns(sheet, 1, 1, 12.5, 0);
    CHECK(xlx_workbook_close(book) == 1, "written under this locale: %s", xlx_last_error());
    int r = xlx_read_open(F_BAD);
    EQ(xlx_read_cell(r, 1, 1, 1), "1234.5678");
    CHECK(xlx_read_cell_number(r, 1, 1, 1) == 1234.5678, "the number itself");
    EQ(xlx_read_grid(r, 1, 2, 1, 2, 0), "0.25\t1,5\t-2500");
    EQ(xlx_read_cell_kind(r, 1, 2, 2), "text");               /* "1,5" is not a number in any locale here */
    EQ(xlx_read_cell(r, 1, 3, 1), "2024-01-01 12:00:00");
    EQ(xlx_read_cell_value(r, 1, 3, 1), "45292.5");
    xlx_read_close(r);
    (void)comma;
    setlocale(LC_ALL, "C");
}

/* ------------------------------------------------------------------ */
/* Size: a sheet of a quarter of a million cells, and one long text.   */
/* ------------------------------------------------------------------ */
static void test_size(void)
{
    enum { ROWS = 25000, COLS = 10 };
    int book = xlx_workbook_new(F_BAD);
    int sheet = xlx_workbook_add_sheet(book, "big");
    for (int row = 1; row <= ROWS; row++) {
        for (int col = 1; col <= COLS; col++) {
            if (col == 1) {
                char label[32];
                snprintf(label, sizeof label, "row %d", row);
                xlx_sheet_write_text(sheet, row, col, label, 0);
            } else {
                xlx_sheet_write_number(sheet, row, col, row * 100.0 + col + 0.5, 0);
            }
        }
    }
    /* the longest text a cell may hold, and one character more */
    static char longest[32767 + 2];
    memset(longest, 'x', 32767);
    longest[32767] = '\0';
    xlx_sheet_write_text(sheet, 1, 12, longest, 0);
    ACCEPTED("a text of 32767 characters");
    longest[32767] = 'x';
    longest[32768] = '\0';
    xlx_sheet_write_text(sheet, 2, 12, longest, 0);
    REFUSED("a text of 32768 characters");
    longest[32767] = '\0';
    CHECK(xlx_workbook_error_count(book) == 1, "one refusal in a quarter of a million writes");
    CHECK(xlx_workbook_close(book) == 1, "the big workbook is written: %s", xlx_last_error());

    int r = xlx_read_open(F_BAD);
    CHECK(r > 0 && xlx_read_load(r, 1), "and loads: %s", xlx_last_error());
    CHECK(xlx_read_row_count(r, 1) == ROWS && xlx_read_column_count(r, 1) == 12, "%d rows", xlx_read_row_count(r, 1));
    EQ(xlx_read_cell(r, 1, ROWS, 1), "row 25000");
    CHECK(xlx_read_cell_number(r, 1, ROWS, COLS) == ROWS * 100.0 + COLS + 0.5, "the last number");
    CHECK(strlen(xlx_read_cell(r, 1, 1, 12)) == 32767, "the long text comes back whole");
    const char *all = xlx_read_grid(r, 1, 1, 1, 0, 10);
    size_t lines = 1;
    for (const char *p = all; *p; p++) if (*p == '\n') lines++;
    CHECK(lines == ROWS, "the whole sheet as one text has %u lines", (unsigned)lines);
    CHECK(strncmp(all, "row 1\t102.5\t103.5", 17) == 0, "and starts as it should");
    xlx_read_close(r);
}

int main(void)
{
    test_library();
    test_names();
    test_dates();
    test_round_trip();
    test_look();
    test_grid();
    test_foreign();
    test_damaged();
    test_handles();
    test_paths();
    test_locale();
    test_size();
    CHECK(xlx_workbook_count() == 0 && xlx_read_count() == 0, "nothing is left open: %d workbooks, %d readers",
          xlx_workbook_count(), xlx_read_count());
    if (s_fail == 0) {
        static const char *const files[] = {F_BASIC, F_STYLE, F_GRID, F_FOREIGN, F_BAD, F_PNG, F_UTF8, "xlsxt-smoke-handles.xlsx"};
        for (size_t i = 0; i < sizeof files / sizeof files[0]; i++) remove(files[i]);
    }
    printf("xlsxt smoke test: %d passed, %d failed\n", s_pass, s_fail);
    return s_fail == 0 ? 0 : 1;
}
