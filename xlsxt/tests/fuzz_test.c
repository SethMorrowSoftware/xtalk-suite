/*
 * fuzz_test.c - random calls into every export of the xlsxt shim, and
 * damaged files into its reader.
 *
 * The smoke test asks "does each call do what the page says". This one asks
 * the two questions a script author and a stranger answer by accident:
 *
 *   1. What happens when ANY call is given ANY value, in any order - a dead
 *      handle, a format of another workbook, row 2 billion, NaN, text that
 *      is not UTF-8, a 40,000 character sheet name, a workbook closed
 *      between two halves of a chart?
 *   2. What happens when the reader is handed a file that is ALMOST a
 *      spreadsheet - real parts with bytes changed, cut short, repeated,
 *      nested a thousand deep, or overwritten while it is open?
 *
 * The contract of the binding is that none of it can crash the host:
 *
 *   - no call faults (the run is built with ASan/UBSan in CI);
 *   - no text result is NULL, and every one is valid UTF-8 (what the engine
 *     is about to copy into a String);
 *   - no number result is NaN or infinite;
 *   - the counts of open workbooks and readers never go wrong, and every
 *     one of them can be let go at the end.
 *
 * The call list is GENERATED from the shim's signatures (tools/check-smoke-
 * coverage.py --write fills the block below and the gate holds it), so a new
 * export is fuzzed the day it is written. Arguments are drawn by PARAMETER
 * NAME: `book` is usually a live workbook, sometimes a dead one, a handle of
 * another kind, 0 or noise; a `color` is usually a colour and sometimes any
 * string in the table, hostile ones included.
 *
 * Deterministic: the generator is a fixed xorshift, so a seed that fails
 * here fails the same way everywhere.
 *
 *     xlsxt_fuzz [seed [calls]]      default: seeds 1..3, 30000 calls each,
 *                                    then the damaged-file rounds
 *     xlsxt_fuzz --replay FILE       make the calls of a trace again
 *     FUZZ_TRACE=1  print each call before it is made
 *
 * The test writes its files into the current directory (xlsxt-fuzz-*) and
 * removes them when it finds nothing.
 */
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
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

/* ------------------------------------------------------------------ */
/* The generator                                                       */
/* ------------------------------------------------------------------ */
static uint64_t s_rng = 1;
static uint32_t rnd(void)
{
    s_rng ^= s_rng << 13;
    s_rng ^= s_rng >> 7;
    s_rng ^= s_rng << 17;
    return (uint32_t)(s_rng >> 16);
}
static int below(int n) { return n > 0 ? (int)(rnd() % (uint32_t)n) : 0; }
static double unit(void) { return (double)(rnd() & 0xFFFFFF) / (double)0x1000000; }

/* ------------------------------------------------------------------ */
/* Handle pools: what the creators returned, dead handles included (a  */
/* closed workbook's handle stays in the pool, and that is the point). */
/* ------------------------------------------------------------------ */
#define POOL_CAP 2048
typedef struct { int items[POOL_CAP]; int count; } Pool;
static Pool s_books, s_sheets, s_formats, s_charts, s_readers;

static void keep(Pool *p, int h)
{
    if (h <= 0) return;
    if (p->count < POOL_CAP) p->items[p->count++] = h;
    else p->items[below(POOL_CAP)] = h;
}
static int draw(Pool *own)
{
    int roll = below(100);
    if (roll < 84 && own->count > 0) {
        /* lean towards the newest handles: they are the live ones */
        int span = own->count < 12 || below(3) == 0 ? own->count : 12;
        return own->items[own->count - 1 - below(span)];
    }
    if (roll < 88) return 0;
    if (roll < 94) {
        Pool *others[5] = { &s_books, &s_sheets, &s_formats, &s_charts, &s_readers };
        Pool *o = others[below(5)];
        return o->count ? o->items[below(o->count)] : -1;
    }
    if (roll < 97) return (int)rnd();               /* any bit pattern   */
    return below(2) ? -below(1000) : below(1 << 20); /* small or negative */
}
static int HB(void) { return draw(&s_books); }
static int HS(void) { return draw(&s_sheets); }
static int HF(void) { return below(4) == 0 ? 0 : draw(&s_formats); }   /* 0 is "no format": common, and legal */
static int HC(void) { return draw(&s_charts); }
static int HR(void) { return draw(&s_readers); }

static int flag(void) { int r = below(20); return r < 9 ? 0 : r < 18 ? 1 : r == 18 ? -7 : 255; }
static int small(int lo, int hi)
{
    if (below(25) == 0) return below(2) ? -2147483647 - 1 : 2147483647;
    return lo + below(hi - lo + 1);
}
/* A row or a column: usually near the top left, where cells meet each other
 * (merges overlap, a chart lands on data), sometimes the far edge of the
 * grid, one past it, zero, or anything. */
static int ROW(void)
{
    int r = below(100);
    if (r < 80) return 1 + below(40);
    if (r < 86) return 1048576 - below(3);
    if (r < 90) return 1048577;
    if (r < 94) return 0;
    return small(-5, 5);
}
static int COL(void)
{
    int r = below(100);
    if (r < 80) return 1 + below(12);
    if (r < 86) return 16384 - below(3);
    if (r < 90) return 16385;
    if (r < 94) return 0;
    return small(-5, 5);
}

/* ------------------------------------------------------------------ */
/* Doubles: mostly numbers a sheet would hold, sometimes hostile ones. */
/* ------------------------------------------------------------------ */
static double nasty(void)
{
    static const double k[] = { 1e38, -1e38, 1.7976931348623157e308, -1.7976931348623157e308, 1e-300, 4.9e-324,
                                1e15, -1e15, 9007199254740993.0, 0.1, 1e-7, 123456789012345678.0 };
    int r = below(15);
    if (r == 0) return NAN;
    if (r == 1) return INFINITY;
    if (r == 2) return -INFINITY;
    if (r == 3) return -0.0;
    return k[below((int)(sizeof(k) / sizeof(k[0])))];
}
static double D(void)
{
    int r = below(100);
    if (r < 55) return (unit() - 0.5) * 2000.0;
    if (r < 75) return (double)(below(2000) - 1000);
    if (r < 85) return 0.0;
    return nasty();
}
/* a width, a height, a scale, a margin: usually small and positive */
static double DP(void)
{
    int r = below(100);
    if (r < 75) return 0.05 + unit() * 20.0;
    if (r < 83) return 0.0;
    if (r < 90) return -unit();
    if (r < 95) return 1 + below(500);
    return nasty();
}
static double SERIAL(void)
{
    int r = below(100);
    if (r < 60) return (double)below(60000) + (below(2) ? unit() : 0.0);
    if (r < 70) return unit();
    if (r < 78) return 59 + below(3);
    if (r < 86) return 2958465.0 + below(3) - 1;
    return nasty();
}
static double SECONDS(void)
{
    int r = below(100);
    if (r < 70) return (double)below(2000000000);
    if (r < 85) return -(double)below(2000000000) * 2.0;
    return nasty();
}

/* ------------------------------------------------------------------ */
/* Texts. An argument that is a text rides in the trace as its INDEX   */
/* in this table, so a replay hands the call the same bytes. The table */
/* is fixed but for a few long entries built at start-up.              */
/* ------------------------------------------------------------------ */
#define F_A   "xlsxt-fuzz-a.xlsx"
#define F_B   "xlsxt-fuzz-b.xlsx"
#define F_C   "xlsxt-fuzz-c.xlsx"
#define F_BAD "xlsxt-fuzz-bad.xlsx"
#define F_PNG "xlsxt-fuzz-pixel.png"

static char s_long_a[40001], s_long_name[300], s_long_path[5001], s_grid[6000], s_wide_grid[70000], s_deep[9000];

static const char *const k_strings[] = {
    /* 0..7: paths (the test's own files, and places a file cannot be) */
    F_A, F_B, F_C, F_BAD, F_PNG, "xlsxt-fuzz-no-such-folder/x.xlsx", "xlsxt-fuzz-no-such-file.xlsx" /* until a workbook is closed onto it */, ".",
    /* 8..23: names, titles, words a call might mean */
    "Data", "Sheet1", "Report", "Caf\xC3\xA9 \xE2\x82\xAC", "It's", "a b", "title", "author", "Total", "Report!Local",
    "x", "y", "X", "A1", "$B$3", "xfd1048576",
    /* 24..47: the words of every enumeration, and near misses */
    "text", "numbers", "formulas", "column", "bar stacked", "line", "pie", "scatter", "radar markers", "doughnut",
    "left", "right", "top", "bottom", "center", "middle", "thin", "double", "none", "single",
    "superscript", "circle", "top right", "CENTER",
    /* 48..59: colours */
    "#FF0000", "00ff00", "0,0,255", "black", "Navy", "255,255,255", "#000000", "#12345", "256,0,0", "1,2", "#GGGGGG", "red ",
    /* 60..69: number format codes */
    "0.00", "#,##0", "0%", "yyyy-mm-dd", "hh:mm:ss", "@", "[Red]0.0\" days\"", "General", "d mmm yyyy", "0.0E+00",
    /* 70..83: formulas and ranges */
    "=SUM(A1:A9)", "=A1*2", "=Data!$A$1:$A$9", "=Data!$B$1:$B$9", "='It''s'!$A$1", "=Sheet1!A1", "=", "==",
    "=Data!$B$9:$B$1", "='Data!$A$1", "=Data!", "=!A1", "=Data!$A$1:", "=Data!$ZZZZ$1",
    /* 84..91: links */
    "https://example.org/", "http://example.org/a?b=1&c=2", "mailto:nobody@example.org", "internal:Data!A1",
    "external:other.xlsx", "ftp://", "just words", "javascript:alert(1)",
    /* 92..103: cell text of every awkward kind */
    "", " ", "plain", "two\nlines", "a\ttab", "<&>\"'", "_x0041_ and _x000D_", "cr\r\nlf", "42", "-0.5", "1e3", "007",
    /* 104..115: text that must be refused */
    "bad \xC3\x28", "\xED\xA0\x80", "\xC0\xAF", "\xF4\x90\x80\x80", "cut \xE2\x82", "\xFF\xFE", "bell\x07", "\x01",
    "\xEF\xBF\xBF", "esc\x1B[0m", "\x7F", "nul-ish\x0B",
    /* 116..123: lists, headers, odd shapes */
    "open,closed,pending", " , ,", ",", "&LLeft&CPage &P of &N&RRight", "&&&&", "%s%s%s%n", "a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p", "[]:*?/\\",
    /* 124..129: built at start-up */
    s_long_a, s_long_name, s_long_path, s_grid, s_wide_grid, s_deep,
};
#define STRING_COUNT ((int)(sizeof(k_strings) / sizeof(k_strings[0])))
#define STRING_NULL  STRING_COUNT          /* one past the table: no text at all */

static const char *str(double index)
{
    int i = (int)index;
    return (i >= 0 && i < STRING_COUNT) ? k_strings[i] : NULL;
}
static double anything(void) { return below(40) == 0 ? STRING_NULL : below(STRING_COUNT); }
/* One of a run of the table most of the time; anything in it otherwise. */
static double from(int first, int last, int percent)
{
    return below(100) < percent ? first + below(last - first + 1) : anything();
}
/* A path is one of the test's own, or a text no file can be named by: the
 * random calls must not scatter files named after colours and formulas. */
static double SPATH(void)
{
    static const int unusable[] = { STRING_COUNT, 92, 104, 110, 126 };   /* none, "", not UTF-8, a bell, 5000 bytes */
    return below(100) < 93 ? below(8) : unusable[below(5)];
}
static double SFOLDER(void)  { return below(3) ? 7 : SPATH(); }
static double SNAME(void)    { return from(8, 23, 85); }
static double SWORD(void)    { return below(8) == 0 ? from(8, 23, 100) : from(24, 47, 92); }
static double SCOLOR(void)   { return from(48, 59, 90); }
static double SCODE(void)    { return from(60, 69, 88); }
static double SFORMULA(void) { return from(70, 83, 88); }
static double SRANGE(void)   { return below(6) == 0 ? 92 : from(70, 83, 90); }
static double SURL(void)     { return from(84, 91, 88); }
static double STEXT(void)    { return below(12) == 0 ? 124 + below(6) : from(92, 123, 88); }

static void build_strings(void)
{
    memset(s_long_a, 'a', sizeof s_long_a - 1);
    memset(s_long_name, 'n', sizeof s_long_name - 1);
    memset(s_long_path, 'p', sizeof s_long_path - 1);
    memcpy(s_long_path + sizeof s_long_path - 6, ".xlsx", 5);
    /* a table of 60 rows by 8 columns, numbers, words, formulas and blanks */
    size_t n = 0;
    for (int r = 0; r < 60; r++)
        for (int c = 0; c < 8; c++)
            n += (size_t)snprintf(s_grid + n, sizeof s_grid - n, "%s%s",
                                  (r + c) % 7 == 0 ? "" : c == 0 ? "label" : (r + c) % 5 == 0 ? "=A1+1" : "12.5",
                                  c == 7 ? "\n" : "\t");
    /* one row of twenty thousand cells: it runs off the edge of the grid */
    n = 0;
    for (int c = 0; c < 20000; c++) { s_wide_grid[n++] = 'w'; s_wide_grid[n++] = '\t'; }
    s_wide_grid[n] = '\0';
    /* XML-ish text, nested deep: harmless as a cell's text */
    n = 0;
    for (int i = 0; i < 1000; i++) n += (size_t)snprintf(s_deep + n, sizeof s_deep - n, "<a b=\"");
}

/* ------------------------------------------------------------------ */
/* What every result must satisfy                                      */
/* ------------------------------------------------------------------ */
static int s_findings = 0;
static const char *s_current = "";
static void finding(const char *what, const char *detail)
{
    if (s_findings < 40) printf("FINDING %s: %s%s%.200s\n", s_current, what, detail ? ": " : "", detail ? detail : "");
    s_findings++;
}
/* RFC 3629, as the shim checks what comes IN: what goes out is copied into
 * an engine String as UTF-8, so it must be UTF-8. */
static int utf8_valid(const unsigned char *s, size_t n)
{
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        if (c < 0x80) { i++; continue; }
        if (c >= 0xC2 && c <= 0xDF) {
            if (i + 1 >= n || (s[i + 1] & 0xC0) != 0x80) return 0;
            i += 2;
        } else if (c >= 0xE0 && c <= 0xEF) {
            if (i + 2 >= n || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80) return 0;
            if ((c == 0xE0 && s[i + 1] < 0xA0) || (c == 0xED && s[i + 1] > 0x9F)) return 0;
            i += 3;
        } else if (c >= 0xF0 && c <= 0xF4) {
            if (i + 3 >= n || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80 || (s[i + 3] & 0xC0) != 0x80) return 0;
            if ((c == 0xF0 && s[i + 1] < 0x90) || (c == 0xF4 && s[i + 1] > 0x8F)) return 0;
            i += 4;
        } else {
            return 0;
        }
    }
    return 1;
}
static void text(const char *r)
{
    if (!r) { finding("a text result is NULL", NULL); return; }
    size_t n = strlen(r);                      /* ASan reads every byte */
    if (xlx_text_length(r) != (int)n) finding("xlx_text_length disagrees with the text", r);
    if (!utf8_valid((const unsigned char *)r, n)) finding("a text result is not valid UTF-8", r);
}
static void number(double r)
{
    if (!isfinite(r)) finding("a number result is not finite", NULL);
}

/* FUZZ_TRACE=1 in the environment prints every call with its arguments
 * before it is made, so the last line of a run that died is the call that
 * killed it and the lines above are how the workbooks got there. The trace
 * is also a program: `xlsxt_fuzz --replay FILE` makes the same calls again,
 * which is how a failure found on one machine is carried to another and how
 * a long one is cut down to the few calls that matter. */
static int s_trace = 0;
static int s_lastInt = 0;
static void tr(const char *name, int n, const double *a)
{
    if (!s_trace) return;
    printf("%s(", name);
    for (int i = 0; i < n; i++) printf("%s%.17g", i ? ", " : "", a[i]);
    printf(")\n");
    fflush(stdout);
}

/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */
/* Two thunks per export. fz_N draws the arguments, in order (C leaves the
 * order of argument evaluation open, and a run must be the same
 * everywhere), and hands them to rp_N, which traces and makes the call;
 * a replayed trace enters at rp_N with the numbers it read. Every
 * argument rides as a double: an int fits one exactly, and a text is
 * its index in the table of strings. */
static void rp_0(const double *a) { (void)a; tr("xlx_abi_version", 0, a); s_lastInt = xlx_abi_version(); }
static void fz_0(void) { double a[1];  rp_0(a); }
static void rp_1(const double *a) { (void)a; tr("xlx_library_version", 0, a); text(xlx_library_version()); }
static void fz_1(void) { double a[1];  rp_1(a); }
static void rp_2(const double *a) { (void)a; tr("xlx_last_error", 0, a); text(xlx_last_error()); }
static void fz_2(void) { double a[1];  rp_2(a); }
static void rp_4(const double *a) { tr("xlx_set_temp_folder", 1, a); xlx_set_temp_folder(str(a[0])); }
static void fz_4(void) { double a[1]; a[0] = SFOLDER(); rp_4(a); }
static void rp_5(const double *a) { (void)a; tr("xlx_temp_folder", 0, a); text(xlx_temp_folder()); }
static void fz_5(void) { double a[1];  rp_5(a); }
static void rp_6(const double *a) { tr("xlx_column_name", 1, a); text(xlx_column_name((int)a[0])); }
static void fz_6(void) { double a[1]; a[0] = COL(); rp_6(a); }
static void rp_7(const double *a) { tr("xlx_cell_name", 2, a); text(xlx_cell_name((int)a[0], (int)a[1])); }
static void fz_7(void) { double a[2]; a[0] = ROW(); a[1] = COL(); rp_7(a); }
static void rp_8(const double *a) { tr("xlx_range_name", 4, a); text(xlx_range_name((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_8(void) { double a[4]; a[0] = ROW(); a[1] = COL(); a[2] = ROW(); a[3] = COL(); rp_8(a); }
static void rp_9(const double *a) { tr("xlx_range_formula", 5, a); text(xlx_range_formula(str(a[0]), (int)a[1], (int)a[2], (int)a[3], (int)a[4])); }
static void fz_9(void) { double a[5]; a[0] = SNAME(); a[1] = ROW(); a[2] = COL(); a[3] = ROW(); a[4] = COL(); rp_9(a); }
static void rp_10(const double *a) { tr("xlx_cell_row", 1, a); s_lastInt = xlx_cell_row(str(a[0])); }
static void fz_10(void) { double a[1]; a[0] = SNAME(); rp_10(a); }
static void rp_11(const double *a) { tr("xlx_cell_column", 1, a); s_lastInt = xlx_cell_column(str(a[0])); }
static void fz_11(void) { double a[1]; a[0] = SNAME(); rp_11(a); }
static void rp_12(const double *a) { tr("xlx_date_to_serial", 6, a); number(xlx_date_to_serial((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4], a[5])); }
static void fz_12(void) { double a[6]; a[0] = small(1890, 10010); a[1] = small(-1, 14); a[2] = small(-1, 33); a[3] = small(-1, 25); a[4] = small(-1, 61); a[5] = D(); rp_12(a); }
static void rp_13(const double *a) { tr("xlx_serial_to_date", 1, a); text(xlx_serial_to_date(a[0])); }
static void fz_13(void) { double a[1]; a[0] = SERIAL(); rp_13(a); }
static void rp_14(const double *a) { tr("xlx_seconds_to_serial", 1, a); number(xlx_seconds_to_serial(a[0])); }
static void fz_14(void) { double a[1]; a[0] = SECONDS(); rp_14(a); }
static void rp_15(const double *a) { tr("xlx_serial_to_seconds", 1, a); number(xlx_serial_to_seconds(a[0])); }
static void fz_15(void) { double a[1]; a[0] = SERIAL(); rp_15(a); }
static void rp_16(const double *a) { (void)a; tr("xlx_workbook_count", 0, a); s_lastInt = xlx_workbook_count(); }
static void fz_16(void) { double a[1];  rp_16(a); }
static void rp_17(const double *a) { tr("xlx_workbook_new", 1, a); s_lastInt = xlx_workbook_new(str(a[0])); keep(&s_books, s_lastInt); }
static void fz_17(void) { double a[1]; a[0] = SPATH(); rp_17(a); }
static void rp_18(const double *a) { tr("xlx_workbook_is_valid", 1, a); s_lastInt = xlx_workbook_is_valid((int)a[0]); }
static void fz_18(void) { double a[1]; a[0] = HB(); rp_18(a); }
static void rp_19(const double *a) { tr("xlx_workbook_close", 1, a); s_lastInt = xlx_workbook_close((int)a[0]); }
static void fz_19(void) { double a[1]; a[0] = HB(); rp_19(a); }
static void rp_20(const double *a) { tr("xlx_workbook_discard", 1, a); xlx_workbook_discard((int)a[0]); }
static void fz_20(void) { double a[1]; a[0] = HB(); rp_20(a); }
static void rp_21(const double *a) { tr("xlx_workbook_error_count", 1, a); s_lastInt = xlx_workbook_error_count((int)a[0]); }
static void fz_21(void) { double a[1]; a[0] = HB(); rp_21(a); }
static void rp_22(const double *a) { tr("xlx_workbook_first_error", 1, a); text(xlx_workbook_first_error((int)a[0])); }
static void fz_22(void) { double a[1]; a[0] = HB(); rp_22(a); }
static void rp_23(const double *a) { tr("xlx_workbook_sheet_count", 1, a); s_lastInt = xlx_workbook_sheet_count((int)a[0]); }
static void fz_23(void) { double a[1]; a[0] = HB(); rp_23(a); }
static void rp_24(const double *a) { tr("xlx_workbook_add_sheet", 2, a); s_lastInt = xlx_workbook_add_sheet((int)a[0], str(a[1])); keep(&s_sheets, s_lastInt); }
static void fz_24(void) { double a[2]; a[0] = HB(); a[1] = SNAME(); rp_24(a); }
static void rp_25(const double *a) { tr("xlx_workbook_add_format", 1, a); s_lastInt = xlx_workbook_add_format((int)a[0]); keep(&s_formats, s_lastInt); }
static void fz_25(void) { double a[1]; a[0] = HB(); rp_25(a); }
static void rp_26(const double *a) { tr("xlx_workbook_add_chart", 2, a); s_lastInt = xlx_workbook_add_chart((int)a[0], str(a[1])); keep(&s_charts, s_lastInt); }
static void fz_26(void) { double a[2]; a[0] = HB(); a[1] = SWORD(); rp_26(a); }
static void rp_27(const double *a) { tr("xlx_workbook_set_property", 3, a); xlx_workbook_set_property((int)a[0], str(a[1]), str(a[2])); }
static void fz_27(void) { double a[3]; a[0] = HB(); a[1] = SNAME(); a[2] = STEXT(); rp_27(a); }
static void rp_28(const double *a) { tr("xlx_workbook_define_name", 3, a); xlx_workbook_define_name((int)a[0], str(a[1]), str(a[2])); }
static void fz_28(void) { double a[3]; a[0] = HB(); a[1] = SNAME(); a[2] = SFORMULA(); rp_28(a); }
static void rp_29(const double *a) { tr("xlx_format_is_valid", 1, a); s_lastInt = xlx_format_is_valid((int)a[0]); }
static void fz_29(void) { double a[1]; a[0] = HF(); rp_29(a); }
static void rp_30(const double *a) { tr("xlx_format_set_bold", 2, a); xlx_format_set_bold((int)a[0], (int)a[1]); }
static void fz_30(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_30(a); }
static void rp_31(const double *a) { tr("xlx_format_set_italic", 2, a); xlx_format_set_italic((int)a[0], (int)a[1]); }
static void fz_31(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_31(a); }
static void rp_32(const double *a) { tr("xlx_format_set_strikeout", 2, a); xlx_format_set_strikeout((int)a[0], (int)a[1]); }
static void fz_32(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_32(a); }
static void rp_33(const double *a) { tr("xlx_format_set_underline", 2, a); xlx_format_set_underline((int)a[0], str(a[1])); }
static void fz_33(void) { double a[2]; a[0] = HF(); a[1] = SWORD(); rp_33(a); }
static void rp_34(const double *a) { tr("xlx_format_set_script", 2, a); xlx_format_set_script((int)a[0], str(a[1])); }
static void fz_34(void) { double a[2]; a[0] = HF(); a[1] = SWORD(); rp_34(a); }
static void rp_35(const double *a) { tr("xlx_format_set_font_name", 2, a); xlx_format_set_font_name((int)a[0], str(a[1])); }
static void fz_35(void) { double a[2]; a[0] = HF(); a[1] = SNAME(); rp_35(a); }
static void rp_36(const double *a) { tr("xlx_format_set_font_size", 2, a); xlx_format_set_font_size((int)a[0], a[1]); }
static void fz_36(void) { double a[2]; a[0] = HF(); a[1] = DP(); rp_36(a); }
static void rp_37(const double *a) { tr("xlx_format_set_font_color", 2, a); xlx_format_set_font_color((int)a[0], str(a[1])); }
static void fz_37(void) { double a[2]; a[0] = HF(); a[1] = SCOLOR(); rp_37(a); }
static void rp_38(const double *a) { tr("xlx_format_set_background_color", 2, a); xlx_format_set_background_color((int)a[0], str(a[1])); }
static void fz_38(void) { double a[2]; a[0] = HF(); a[1] = SCOLOR(); rp_38(a); }
static void rp_39(const double *a) { tr("xlx_format_set_number_format", 2, a); xlx_format_set_number_format((int)a[0], str(a[1])); }
static void fz_39(void) { double a[2]; a[0] = HF(); a[1] = SCODE(); rp_39(a); }
static void rp_40(const double *a) { tr("xlx_format_set_align", 2, a); xlx_format_set_align((int)a[0], str(a[1])); }
static void fz_40(void) { double a[2]; a[0] = HF(); a[1] = SWORD(); rp_40(a); }
static void rp_41(const double *a) { tr("xlx_format_set_vertical_align", 2, a); xlx_format_set_vertical_align((int)a[0], str(a[1])); }
static void fz_41(void) { double a[2]; a[0] = HF(); a[1] = SWORD(); rp_41(a); }
static void rp_42(const double *a) { tr("xlx_format_set_text_wrap", 2, a); xlx_format_set_text_wrap((int)a[0], (int)a[1]); }
static void fz_42(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_42(a); }
static void rp_43(const double *a) { tr("xlx_format_set_shrink", 2, a); xlx_format_set_shrink((int)a[0], (int)a[1]); }
static void fz_43(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_43(a); }
static void rp_44(const double *a) { tr("xlx_format_set_rotation", 2, a); xlx_format_set_rotation((int)a[0], (int)a[1]); }
static void fz_44(void) { double a[2]; a[0] = HF(); a[1] = small(-100, 280); rp_44(a); }
static void rp_45(const double *a) { tr("xlx_format_set_indent", 2, a); xlx_format_set_indent((int)a[0], (int)a[1]); }
static void fz_45(void) { double a[2]; a[0] = HF(); a[1] = small(-1, 260); rp_45(a); }
static void rp_46(const double *a) { tr("xlx_format_set_border", 2, a); xlx_format_set_border((int)a[0], str(a[1])); }
static void fz_46(void) { double a[2]; a[0] = HF(); a[1] = SWORD(); rp_46(a); }
static void rp_47(const double *a) { tr("xlx_format_set_border_side", 3, a); xlx_format_set_border_side((int)a[0], str(a[1]), str(a[2])); }
static void fz_47(void) { double a[3]; a[0] = HF(); a[1] = SWORD(); a[2] = SWORD(); rp_47(a); }
static void rp_48(const double *a) { tr("xlx_format_set_border_color", 2, a); xlx_format_set_border_color((int)a[0], str(a[1])); }
static void fz_48(void) { double a[2]; a[0] = HF(); a[1] = SCOLOR(); rp_48(a); }
static void rp_49(const double *a) { tr("xlx_format_set_locked", 2, a); xlx_format_set_locked((int)a[0], (int)a[1]); }
static void fz_49(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_49(a); }
static void rp_50(const double *a) { tr("xlx_format_set_formula_hidden", 2, a); xlx_format_set_formula_hidden((int)a[0], (int)a[1]); }
static void fz_50(void) { double a[2]; a[0] = HF(); a[1] = flag(); rp_50(a); }
static void rp_51(const double *a) { tr("xlx_sheet_is_valid", 1, a); s_lastInt = xlx_sheet_is_valid((int)a[0]); }
static void fz_51(void) { double a[1]; a[0] = HS(); rp_51(a); }
static void rp_52(const double *a) { tr("xlx_sheet_name", 1, a); text(xlx_sheet_name((int)a[0])); }
static void fz_52(void) { double a[1]; a[0] = HS(); rp_52(a); }
static void rp_53(const double *a) { tr("xlx_sheet_write_number", 5, a); xlx_sheet_write_number((int)a[0], (int)a[1], (int)a[2], a[3], (int)a[4]); }
static void fz_53(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = D(); a[4] = HF(); rp_53(a); }
static void rp_54(const double *a) { tr("xlx_sheet_write_text", 5, a); xlx_sheet_write_text((int)a[0], (int)a[1], (int)a[2], str(a[3]), (int)a[4]); }
static void fz_54(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = STEXT(); a[4] = HF(); rp_54(a); }
static void rp_55(const double *a) { tr("xlx_sheet_write_formula", 5, a); xlx_sheet_write_formula((int)a[0], (int)a[1], (int)a[2], str(a[3]), (int)a[4]); }
static void fz_55(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = SFORMULA(); a[4] = HF(); rp_55(a); }
static void rp_56(const double *a) { tr("xlx_sheet_write_formula_value", 6, a); xlx_sheet_write_formula_value((int)a[0], (int)a[1], (int)a[2], str(a[3]), a[4], (int)a[5]); }
static void fz_56(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = SFORMULA(); a[4] = D(); a[5] = HF(); rp_56(a); }
static void rp_57(const double *a) { tr("xlx_sheet_write_boolean", 5, a); xlx_sheet_write_boolean((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4]); }
static void fz_57(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = flag(); a[4] = HF(); rp_57(a); }
static void rp_58(const double *a) { tr("xlx_sheet_write_blank", 4, a); xlx_sheet_write_blank((int)a[0], (int)a[1], (int)a[2], (int)a[3]); }
static void fz_58(void) { double a[4]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = HF(); rp_58(a); }
static void rp_59(const double *a) { tr("xlx_sheet_write_date", 5, a); xlx_sheet_write_date((int)a[0], (int)a[1], (int)a[2], a[3], (int)a[4]); }
static void fz_59(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = SERIAL(); a[4] = HF(); rp_59(a); }
static void rp_60(const double *a) { tr("xlx_sheet_write_link", 6, a); xlx_sheet_write_link((int)a[0], (int)a[1], (int)a[2], str(a[3]), str(a[4]), (int)a[5]); }
static void fz_60(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = SURL(); a[4] = STEXT(); a[5] = HF(); rp_60(a); }
static void rp_61(const double *a) { tr("xlx_sheet_write_comment", 4, a); xlx_sheet_write_comment((int)a[0], (int)a[1], (int)a[2], str(a[3])); }
static void fz_61(void) { double a[4]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = STEXT(); rp_61(a); }
static void rp_62(const double *a) { tr("xlx_sheet_write_grid", 6, a); s_lastInt = xlx_sheet_write_grid((int)a[0], (int)a[1], (int)a[2], str(a[3]), str(a[4]), (int)a[5]); }
static void fz_62(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = STEXT(); a[4] = SWORD(); a[5] = HF(); rp_62(a); }
static void rp_63(const double *a) { tr("xlx_sheet_set_columns", 5, a); xlx_sheet_set_columns((int)a[0], (int)a[1], (int)a[2], a[3], (int)a[4]); }
static void fz_63(void) { double a[5]; a[0] = HS(); a[1] = COL(); a[2] = COL(); a[3] = DP(); a[4] = HF(); rp_63(a); }
static void rp_64(const double *a) { tr("xlx_sheet_hide_columns", 3, a); xlx_sheet_hide_columns((int)a[0], (int)a[1], (int)a[2]); }
static void fz_64(void) { double a[3]; a[0] = HS(); a[1] = COL(); a[2] = COL(); rp_64(a); }
static void rp_65(const double *a) { tr("xlx_sheet_set_row", 4, a); xlx_sheet_set_row((int)a[0], (int)a[1], a[2], (int)a[3]); }
static void fz_65(void) { double a[4]; a[0] = HS(); a[1] = ROW(); a[2] = DP(); a[3] = HF(); rp_65(a); }
static void rp_66(const double *a) { tr("xlx_sheet_hide_row", 2, a); xlx_sheet_hide_row((int)a[0], (int)a[1]); }
static void fz_66(void) { double a[2]; a[0] = HS(); a[1] = ROW(); rp_66(a); }
static void rp_67(const double *a) { tr("xlx_sheet_merge", 7, a); xlx_sheet_merge((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4], str(a[5]), (int)a[6]); }
static void fz_67(void) { double a[7]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = ROW(); a[4] = COL(); a[5] = STEXT(); a[6] = HF(); rp_67(a); }
static void rp_68(const double *a) { tr("xlx_sheet_freeze", 3, a); xlx_sheet_freeze((int)a[0], (int)a[1], (int)a[2]); }
static void fz_68(void) { double a[3]; a[0] = HS(); a[1] = small(-1, 6); a[2] = small(-1, 6); rp_68(a); }
static void rp_69(const double *a) { tr("xlx_sheet_autofilter", 5, a); xlx_sheet_autofilter((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4]); }
static void fz_69(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = ROW(); a[4] = COL(); rp_69(a); }
static void rp_70(const double *a) { tr("xlx_sheet_validate_list", 6, a); xlx_sheet_validate_list((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4], str(a[5])); }
static void fz_70(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = ROW(); a[4] = COL(); a[5] = STEXT(); rp_70(a); }
static void rp_71(const double *a) { tr("xlx_sheet_insert_image", 6, a); xlx_sheet_insert_image((int)a[0], (int)a[1], (int)a[2], str(a[3]), a[4], a[5]); }
static void fz_71(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = SPATH(); a[4] = DP(); a[5] = DP(); rp_71(a); }
static void rp_72(const double *a) { tr("xlx_sheet_set_landscape", 2, a); xlx_sheet_set_landscape((int)a[0], (int)a[1]); }
static void fz_72(void) { double a[2]; a[0] = HS(); a[1] = flag(); rp_72(a); }
static void rp_73(const double *a) { tr("xlx_sheet_set_paper", 2, a); xlx_sheet_set_paper((int)a[0], (int)a[1]); }
static void fz_73(void) { double a[2]; a[0] = HS(); a[1] = small(-1, 120); rp_73(a); }
static void rp_74(const double *a) { tr("xlx_sheet_set_margins", 5, a); xlx_sheet_set_margins((int)a[0], a[1], a[2], a[3], a[4]); }
static void fz_74(void) { double a[5]; a[0] = HS(); a[1] = DP(); a[2] = DP(); a[3] = DP(); a[4] = DP(); rp_74(a); }
static void rp_75(const double *a) { tr("xlx_sheet_fit_to_pages", 3, a); xlx_sheet_fit_to_pages((int)a[0], (int)a[1], (int)a[2]); }
static void fz_75(void) { double a[3]; a[0] = HS(); a[1] = small(-1, 4); a[2] = small(-1, 4); rp_75(a); }
static void rp_76(const double *a) { tr("xlx_sheet_set_header", 2, a); xlx_sheet_set_header((int)a[0], str(a[1])); }
static void fz_76(void) { double a[2]; a[0] = HS(); a[1] = STEXT(); rp_76(a); }
static void rp_77(const double *a) { tr("xlx_sheet_set_footer", 2, a); xlx_sheet_set_footer((int)a[0], str(a[1])); }
static void fz_77(void) { double a[2]; a[0] = HS(); a[1] = STEXT(); rp_77(a); }
static void rp_78(const double *a) { tr("xlx_sheet_repeat_rows", 3, a); xlx_sheet_repeat_rows((int)a[0], (int)a[1], (int)a[2]); }
static void fz_78(void) { double a[3]; a[0] = HS(); a[1] = ROW(); a[2] = ROW(); rp_78(a); }
static void rp_79(const double *a) { tr("xlx_sheet_print_area", 5, a); xlx_sheet_print_area((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4]); }
static void fz_79(void) { double a[5]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = ROW(); a[4] = COL(); rp_79(a); }
static void rp_80(const double *a) { tr("xlx_sheet_set_zoom", 2, a); xlx_sheet_set_zoom((int)a[0], (int)a[1]); }
static void fz_80(void) { double a[2]; a[0] = HS(); a[1] = small(0, 420); rp_80(a); }
static void rp_81(const double *a) { tr("xlx_sheet_show_gridlines", 3, a); xlx_sheet_show_gridlines((int)a[0], (int)a[1], (int)a[2]); }
static void fz_81(void) { double a[3]; a[0] = HS(); a[1] = flag(); a[2] = flag(); rp_81(a); }
static void rp_82(const double *a) { tr("xlx_sheet_set_tab_color", 2, a); xlx_sheet_set_tab_color((int)a[0], str(a[1])); }
static void fz_82(void) { double a[2]; a[0] = HS(); a[1] = SCOLOR(); rp_82(a); }
static void rp_83(const double *a) { tr("xlx_sheet_activate", 1, a); xlx_sheet_activate((int)a[0]); }
static void fz_83(void) { double a[1]; a[0] = HS(); rp_83(a); }
static void rp_84(const double *a) { tr("xlx_sheet_hide", 1, a); xlx_sheet_hide((int)a[0]); }
static void fz_84(void) { double a[1]; a[0] = HS(); rp_84(a); }
static void rp_85(const double *a) { tr("xlx_sheet_protect", 2, a); xlx_sheet_protect((int)a[0], str(a[1])); }
static void fz_85(void) { double a[2]; a[0] = HS(); a[1] = SNAME(); rp_85(a); }
static void rp_86(const double *a) { tr("xlx_chart_is_valid", 1, a); s_lastInt = xlx_chart_is_valid((int)a[0]); }
static void fz_86(void) { double a[1]; a[0] = HC(); rp_86(a); }
static void rp_87(const double *a) { tr("xlx_chart_series_count", 1, a); s_lastInt = xlx_chart_series_count((int)a[0]); }
static void fz_87(void) { double a[1]; a[0] = HC(); rp_87(a); }
static void rp_88(const double *a) { tr("xlx_chart_add_series", 3, a); s_lastInt = xlx_chart_add_series((int)a[0], str(a[1]), str(a[2])); }
static void fz_88(void) { double a[3]; a[0] = HC(); a[1] = SRANGE(); a[2] = SRANGE(); rp_88(a); }
static void rp_89(const double *a) { tr("xlx_chart_series_set_name", 3, a); xlx_chart_series_set_name((int)a[0], (int)a[1], str(a[2])); }
static void fz_89(void) { double a[3]; a[0] = HC(); a[1] = small(-1, 4); a[2] = SNAME(); rp_89(a); }
static void rp_90(const double *a) { tr("xlx_chart_series_set_color", 3, a); xlx_chart_series_set_color((int)a[0], (int)a[1], str(a[2])); }
static void fz_90(void) { double a[3]; a[0] = HC(); a[1] = small(-1, 4); a[2] = SCOLOR(); rp_90(a); }
static void rp_91(const double *a) { tr("xlx_chart_series_set_labels", 3, a); xlx_chart_series_set_labels((int)a[0], (int)a[1], (int)a[2]); }
static void fz_91(void) { double a[3]; a[0] = HC(); a[1] = small(-1, 4); a[2] = flag(); rp_91(a); }
static void rp_92(const double *a) { tr("xlx_chart_series_set_smooth", 3, a); xlx_chart_series_set_smooth((int)a[0], (int)a[1], (int)a[2]); }
static void fz_92(void) { double a[3]; a[0] = HC(); a[1] = small(-1, 4); a[2] = flag(); rp_92(a); }
static void rp_93(const double *a) { tr("xlx_chart_series_set_marker", 3, a); xlx_chart_series_set_marker((int)a[0], (int)a[1], str(a[2])); }
static void fz_93(void) { double a[3]; a[0] = HC(); a[1] = small(-1, 4); a[2] = SWORD(); rp_93(a); }
static void rp_94(const double *a) { tr("xlx_chart_set_title", 2, a); xlx_chart_set_title((int)a[0], str(a[1])); }
static void fz_94(void) { double a[2]; a[0] = HC(); a[1] = SNAME(); rp_94(a); }
static void rp_95(const double *a) { tr("xlx_chart_set_axis_title", 3, a); xlx_chart_set_axis_title((int)a[0], str(a[1]), str(a[2])); }
static void fz_95(void) { double a[3]; a[0] = HC(); a[1] = SWORD(); a[2] = SNAME(); rp_95(a); }
static void rp_96(const double *a) { tr("xlx_chart_set_axis_range", 4, a); xlx_chart_set_axis_range((int)a[0], str(a[1]), a[2], a[3]); }
static void fz_96(void) { double a[4]; a[0] = HC(); a[1] = SWORD(); a[2] = D(); a[3] = D(); rp_96(a); }
static void rp_97(const double *a) { tr("xlx_chart_set_axis_number_format", 3, a); xlx_chart_set_axis_number_format((int)a[0], str(a[1]), str(a[2])); }
static void fz_97(void) { double a[3]; a[0] = HC(); a[1] = SWORD(); a[2] = SCODE(); rp_97(a); }
static void rp_98(const double *a) { tr("xlx_chart_set_axis_gridlines", 3, a); xlx_chart_set_axis_gridlines((int)a[0], str(a[1]), (int)a[2]); }
static void fz_98(void) { double a[3]; a[0] = HC(); a[1] = SWORD(); a[2] = flag(); rp_98(a); }
static void rp_99(const double *a) { tr("xlx_chart_set_legend", 2, a); xlx_chart_set_legend((int)a[0], str(a[1])); }
static void fz_99(void) { double a[2]; a[0] = HC(); a[1] = SWORD(); rp_99(a); }
static void rp_100(const double *a) { tr("xlx_chart_set_style", 2, a); xlx_chart_set_style((int)a[0], (int)a[1]); }
static void fz_100(void) { double a[2]; a[0] = HC(); a[1] = small(-1, 50); rp_100(a); }
static void rp_101(const double *a) { tr("xlx_sheet_insert_chart", 6, a); xlx_sheet_insert_chart((int)a[0], (int)a[1], (int)a[2], (int)a[3], a[4], a[5]); }
static void fz_101(void) { double a[6]; a[0] = HS(); a[1] = ROW(); a[2] = COL(); a[3] = HC(); a[4] = DP(); a[5] = DP(); rp_101(a); }
static void rp_102(const double *a) { (void)a; tr("xlx_read_count", 0, a); s_lastInt = xlx_read_count(); }
static void fz_102(void) { double a[1];  rp_102(a); }
static void rp_103(const double *a) { tr("xlx_read_open", 1, a); s_lastInt = xlx_read_open(str(a[0])); keep(&s_readers, s_lastInt); }
static void fz_103(void) { double a[1]; a[0] = SPATH(); rp_103(a); }
static void rp_104(const double *a) { tr("xlx_read_close", 1, a); xlx_read_close((int)a[0]); }
static void fz_104(void) { double a[1]; a[0] = HR(); rp_104(a); }
static void rp_105(const double *a) { tr("xlx_read_is_valid", 1, a); s_lastInt = xlx_read_is_valid((int)a[0]); }
static void fz_105(void) { double a[1]; a[0] = HR(); rp_105(a); }
static void rp_106(const double *a) { tr("xlx_read_sheet_count", 1, a); s_lastInt = xlx_read_sheet_count((int)a[0]); }
static void fz_106(void) { double a[1]; a[0] = HR(); rp_106(a); }
static void rp_107(const double *a) { tr("xlx_read_sheet_name", 2, a); text(xlx_read_sheet_name((int)a[0], (int)a[1])); }
static void fz_107(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_107(a); }
static void rp_108(const double *a) { tr("xlx_read_sheet_number", 2, a); s_lastInt = xlx_read_sheet_number((int)a[0], str(a[1])); }
static void fz_108(void) { double a[2]; a[0] = HR(); a[1] = SNAME(); rp_108(a); }
static void rp_109(const double *a) { tr("xlx_read_sheet_is_hidden", 2, a); s_lastInt = xlx_read_sheet_is_hidden((int)a[0], (int)a[1]); }
static void fz_109(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_109(a); }
static void rp_110(const double *a) { tr("xlx_read_uses_1904", 1, a); s_lastInt = xlx_read_uses_1904((int)a[0]); }
static void fz_110(void) { double a[1]; a[0] = HR(); rp_110(a); }
static void rp_111(const double *a) { tr("xlx_read_load", 2, a); s_lastInt = xlx_read_load((int)a[0], (int)a[1]); }
static void fz_111(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_111(a); }
static void rp_112(const double *a) { tr("xlx_read_row_count", 2, a); s_lastInt = xlx_read_row_count((int)a[0], (int)a[1]); }
static void fz_112(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_112(a); }
static void rp_113(const double *a) { tr("xlx_read_column_count", 2, a); s_lastInt = xlx_read_column_count((int)a[0], (int)a[1]); }
static void fz_113(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_113(a); }
static void rp_114(const double *a) { tr("xlx_read_cell", 4, a); text(xlx_read_cell((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_114(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_114(a); }
static void rp_115(const double *a) { tr("xlx_read_cell_value", 4, a); text(xlx_read_cell_value((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_115(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_115(a); }
static void rp_116(const double *a) { tr("xlx_read_cell_number", 4, a); number(xlx_read_cell_number((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_116(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_116(a); }
static void rp_117(const double *a) { tr("xlx_read_cell_kind", 4, a); text(xlx_read_cell_kind((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_117(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_117(a); }
static void rp_118(const double *a) { tr("xlx_read_cell_formula", 4, a); text(xlx_read_cell_formula((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_118(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_118(a); }
static void rp_119(const double *a) { tr("xlx_read_cell_format", 4, a); text(xlx_read_cell_format((int)a[0], (int)a[1], (int)a[2], (int)a[3])); }
static void fz_119(void) { double a[4]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); rp_119(a); }
static void rp_120(const double *a) { tr("xlx_read_grid", 6, a); text(xlx_read_grid((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4], (int)a[5])); }
static void fz_120(void) { double a[6]; a[0] = HR(); a[1] = small(-1, 5); a[2] = ROW(); a[3] = COL(); a[4] = ROW(); a[5] = COL(); rp_120(a); }
static void rp_121(const double *a) { tr("xlx_read_merged", 2, a); text(xlx_read_merged((int)a[0], (int)a[1])); }
static void fz_121(void) { double a[2]; a[0] = HR(); a[1] = small(-1, 5); rp_121(a); }
typedef struct { const char *name; int argc; void (*call)(void); void (*replay)(const double *); } FuzzCall;
static const FuzzCall k_fuzz[] = {
    { "xlx_abi_version", 0, fz_0, rp_0 },
    { "xlx_library_version", 0, fz_1, rp_1 },
    { "xlx_last_error", 0, fz_2, rp_2 },
    { "xlx_set_temp_folder", 1, fz_4, rp_4 },
    { "xlx_temp_folder", 0, fz_5, rp_5 },
    { "xlx_column_name", 1, fz_6, rp_6 },
    { "xlx_cell_name", 2, fz_7, rp_7 },
    { "xlx_range_name", 4, fz_8, rp_8 },
    { "xlx_range_formula", 5, fz_9, rp_9 },
    { "xlx_cell_row", 1, fz_10, rp_10 },
    { "xlx_cell_column", 1, fz_11, rp_11 },
    { "xlx_date_to_serial", 6, fz_12, rp_12 },
    { "xlx_serial_to_date", 1, fz_13, rp_13 },
    { "xlx_seconds_to_serial", 1, fz_14, rp_14 },
    { "xlx_serial_to_seconds", 1, fz_15, rp_15 },
    { "xlx_workbook_count", 0, fz_16, rp_16 },
    { "xlx_workbook_new", 1, fz_17, rp_17 },
    { "xlx_workbook_is_valid", 1, fz_18, rp_18 },
    { "xlx_workbook_close", 1, fz_19, rp_19 },
    { "xlx_workbook_discard", 1, fz_20, rp_20 },
    { "xlx_workbook_error_count", 1, fz_21, rp_21 },
    { "xlx_workbook_first_error", 1, fz_22, rp_22 },
    { "xlx_workbook_sheet_count", 1, fz_23, rp_23 },
    { "xlx_workbook_add_sheet", 2, fz_24, rp_24 },
    { "xlx_workbook_add_format", 1, fz_25, rp_25 },
    { "xlx_workbook_add_chart", 2, fz_26, rp_26 },
    { "xlx_workbook_set_property", 3, fz_27, rp_27 },
    { "xlx_workbook_define_name", 3, fz_28, rp_28 },
    { "xlx_format_is_valid", 1, fz_29, rp_29 },
    { "xlx_format_set_bold", 2, fz_30, rp_30 },
    { "xlx_format_set_italic", 2, fz_31, rp_31 },
    { "xlx_format_set_strikeout", 2, fz_32, rp_32 },
    { "xlx_format_set_underline", 2, fz_33, rp_33 },
    { "xlx_format_set_script", 2, fz_34, rp_34 },
    { "xlx_format_set_font_name", 2, fz_35, rp_35 },
    { "xlx_format_set_font_size", 2, fz_36, rp_36 },
    { "xlx_format_set_font_color", 2, fz_37, rp_37 },
    { "xlx_format_set_background_color", 2, fz_38, rp_38 },
    { "xlx_format_set_number_format", 2, fz_39, rp_39 },
    { "xlx_format_set_align", 2, fz_40, rp_40 },
    { "xlx_format_set_vertical_align", 2, fz_41, rp_41 },
    { "xlx_format_set_text_wrap", 2, fz_42, rp_42 },
    { "xlx_format_set_shrink", 2, fz_43, rp_43 },
    { "xlx_format_set_rotation", 2, fz_44, rp_44 },
    { "xlx_format_set_indent", 2, fz_45, rp_45 },
    { "xlx_format_set_border", 2, fz_46, rp_46 },
    { "xlx_format_set_border_side", 3, fz_47, rp_47 },
    { "xlx_format_set_border_color", 2, fz_48, rp_48 },
    { "xlx_format_set_locked", 2, fz_49, rp_49 },
    { "xlx_format_set_formula_hidden", 2, fz_50, rp_50 },
    { "xlx_sheet_is_valid", 1, fz_51, rp_51 },
    { "xlx_sheet_name", 1, fz_52, rp_52 },
    { "xlx_sheet_write_number", 5, fz_53, rp_53 },
    { "xlx_sheet_write_text", 5, fz_54, rp_54 },
    { "xlx_sheet_write_formula", 5, fz_55, rp_55 },
    { "xlx_sheet_write_formula_value", 6, fz_56, rp_56 },
    { "xlx_sheet_write_boolean", 5, fz_57, rp_57 },
    { "xlx_sheet_write_blank", 4, fz_58, rp_58 },
    { "xlx_sheet_write_date", 5, fz_59, rp_59 },
    { "xlx_sheet_write_link", 6, fz_60, rp_60 },
    { "xlx_sheet_write_comment", 4, fz_61, rp_61 },
    { "xlx_sheet_write_grid", 6, fz_62, rp_62 },
    { "xlx_sheet_set_columns", 5, fz_63, rp_63 },
    { "xlx_sheet_hide_columns", 3, fz_64, rp_64 },
    { "xlx_sheet_set_row", 4, fz_65, rp_65 },
    { "xlx_sheet_hide_row", 2, fz_66, rp_66 },
    { "xlx_sheet_merge", 7, fz_67, rp_67 },
    { "xlx_sheet_freeze", 3, fz_68, rp_68 },
    { "xlx_sheet_autofilter", 5, fz_69, rp_69 },
    { "xlx_sheet_validate_list", 6, fz_70, rp_70 },
    { "xlx_sheet_insert_image", 6, fz_71, rp_71 },
    { "xlx_sheet_set_landscape", 2, fz_72, rp_72 },
    { "xlx_sheet_set_paper", 2, fz_73, rp_73 },
    { "xlx_sheet_set_margins", 5, fz_74, rp_74 },
    { "xlx_sheet_fit_to_pages", 3, fz_75, rp_75 },
    { "xlx_sheet_set_header", 2, fz_76, rp_76 },
    { "xlx_sheet_set_footer", 2, fz_77, rp_77 },
    { "xlx_sheet_repeat_rows", 3, fz_78, rp_78 },
    { "xlx_sheet_print_area", 5, fz_79, rp_79 },
    { "xlx_sheet_set_zoom", 2, fz_80, rp_80 },
    { "xlx_sheet_show_gridlines", 3, fz_81, rp_81 },
    { "xlx_sheet_set_tab_color", 2, fz_82, rp_82 },
    { "xlx_sheet_activate", 1, fz_83, rp_83 },
    { "xlx_sheet_hide", 1, fz_84, rp_84 },
    { "xlx_sheet_protect", 2, fz_85, rp_85 },
    { "xlx_chart_is_valid", 1, fz_86, rp_86 },
    { "xlx_chart_series_count", 1, fz_87, rp_87 },
    { "xlx_chart_add_series", 3, fz_88, rp_88 },
    { "xlx_chart_series_set_name", 3, fz_89, rp_89 },
    { "xlx_chart_series_set_color", 3, fz_90, rp_90 },
    { "xlx_chart_series_set_labels", 3, fz_91, rp_91 },
    { "xlx_chart_series_set_smooth", 3, fz_92, rp_92 },
    { "xlx_chart_series_set_marker", 3, fz_93, rp_93 },
    { "xlx_chart_set_title", 2, fz_94, rp_94 },
    { "xlx_chart_set_axis_title", 3, fz_95, rp_95 },
    { "xlx_chart_set_axis_range", 4, fz_96, rp_96 },
    { "xlx_chart_set_axis_number_format", 3, fz_97, rp_97 },
    { "xlx_chart_set_axis_gridlines", 3, fz_98, rp_98 },
    { "xlx_chart_set_legend", 2, fz_99, rp_99 },
    { "xlx_chart_set_style", 2, fz_100, rp_100 },
    { "xlx_sheet_insert_chart", 6, fz_101, rp_101 },
    { "xlx_read_count", 0, fz_102, rp_102 },
    { "xlx_read_open", 1, fz_103, rp_103 },
    { "xlx_read_close", 1, fz_104, rp_104 },
    { "xlx_read_is_valid", 1, fz_105, rp_105 },
    { "xlx_read_sheet_count", 1, fz_106, rp_106 },
    { "xlx_read_sheet_name", 2, fz_107, rp_107 },
    { "xlx_read_sheet_number", 2, fz_108, rp_108 },
    { "xlx_read_sheet_is_hidden", 2, fz_109, rp_109 },
    { "xlx_read_uses_1904", 1, fz_110, rp_110 },
    { "xlx_read_load", 2, fz_111, rp_111 },
    { "xlx_read_row_count", 2, fz_112, rp_112 },
    { "xlx_read_column_count", 2, fz_113, rp_113 },
    { "xlx_read_cell", 4, fz_114, rp_114 },
    { "xlx_read_cell_value", 4, fz_115, rp_115 },
    { "xlx_read_cell_number", 4, fz_116, rp_116 },
    { "xlx_read_cell_kind", 4, fz_117, rp_117 },
    { "xlx_read_cell_formula", 4, fz_118, rp_118 },
    { "xlx_read_cell_format", 4, fz_119, rp_119 },
    { "xlx_read_grid", 6, fz_120, rp_120 },
    { "xlx_read_merged", 2, fz_121, rp_121 },
};
/* <<< END FUZZ CALLS <<< */

static const FuzzCall *find_call(const char *name)
{
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    for (int i = 0; i < n; i++) if (strcmp(k_fuzz[i].name, name) == 0) return &k_fuzz[i];
    return NULL;
}
/* One call BY NAME, through the same thunk a random call uses, so the seed
 * scene is in the trace and a replay rebuilds it. Returns an int result. */
static int C(const char *name, int n, ...)
{
    double a[16] = { 0 };
    const FuzzCall *c = find_call(name);
    va_list ap;
    va_start(ap, n);
    for (int i = 0; i < n && i < 16; i++) a[i] = va_arg(ap, double);
    va_end(ap);
    if (!c || c->argc != n) { finding("the seed scene names a call the shim does not have, or miscounts it", name); return 0; }
    s_current = name;
    s_lastInt = 0;
    c->replay(a);
    return s_lastInt;
}

/* ------------------------------------------------------------------ */
/* A scene to start from, so the random calls land on live things: a   */
/* workbook with data, formats and a chart; a file on disk to read;    */
/* and a reader open on it. String arguments are table indices.        */
/* ------------------------------------------------------------------ */
static void seed_scene(int round)
{
    double path = (double)(round % 3);                        /* F_A, F_B, F_C */
    double book = C("xlx_workbook_new", 1, path);
    double sheet = C("xlx_workbook_add_sheet", 2, book, 8.0);            /* "Data" */
    double other = C("xlx_workbook_add_sheet", 2, book, 92.0);           /* ""     */
    double format = C("xlx_workbook_add_format", 1, book);
    C("xlx_format_set_bold", 2, format, 1.0);
    C("xlx_format_set_number_format", 2, format, 60.0);
    C("xlx_sheet_write_grid", 6, sheet, 1.0, 1.0, 127.0, 26.0, 0.0);     /* the table, as formulas */
    C("xlx_sheet_write_text", 5, sheet, 1.0, 1.0, 94.0, format);
    C("xlx_sheet_write_date", 5, other, 2.0, 2.0, 45292.5, 0.0);
    C("xlx_sheet_merge", 7, other, 4.0, 1.0, 5.0, 3.0, 94.0, 0.0);
    double chart = C("xlx_workbook_add_chart", 2, book, 27.0);           /* "column" */
    C("xlx_chart_add_series", 3, chart, 72.0, 73.0);
    C("xlx_sheet_insert_chart", 6, other, 8.0, 2.0, chart, 1.0, 1.0);
    C("xlx_workbook_add_chart", 2, book, 31.0);                          /* a scatter, never placed */
    if (round % 2 == 0) {
        /* written now, so the readers have a real file from the first call */
        C("xlx_workbook_close", 1, book);
        double reader = C("xlx_read_open", 1, path);
        C("xlx_read_load", 2, reader, 1.0);
        /* and a second workbook left open for the random calls */
        book = C("xlx_workbook_new", 1, (double)((round + 1) % 3));
        C("xlx_workbook_add_sheet", 2, book, 9.0);
        C("xlx_workbook_add_format", 1, book);
    }
}

static void release_all(void)
{
    s_current = "teardown";
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; i < s_books.count; i++) xlx_workbook_discard(s_books.items[i]);
        for (int i = 0; i < s_readers.count; i++) xlx_read_close(s_readers.items[i]);
    }
}

static int run(uint64_t seed, int calls)
{
    int before = s_findings;
    s_rng = seed * 0x9E3779B97F4A7C15ull + 1;
    s_books.count = s_sheets.count = s_formats.count = s_charts.count = s_readers.count = 0;
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    for (int i = 0; i < calls; i++) {
        /* A fresh scene now and then: the random calls close workbooks, and
         * a run over nothing but dead handles tests one path forever. */
        if (i % 1500 == 0) seed_scene(i / 1500);
        const FuzzCall *c = &k_fuzz[below(n)];
        s_current = c->name;
        c->call();
        if (xlx_workbook_count() < 0 || xlx_read_count() < 0) { finding("a count of open things went negative", NULL); break; }
        /* The pools forget handles once they are full; long before that,
         * let everything go, so that no run holds thousands of open files
         * (a process has a limit, and reaching it is not what is tested). */
        if (xlx_read_count() > 200 || xlx_workbook_count() > 200) {
            release_all();
            if (xlx_read_count() > 200 || xlx_workbook_count() > 200) { finding("open things outlive every handle the test was given", NULL); break; }
        }
    }
    release_all();
    printf("seed %llu: %d calls, %d findings; %d workbooks and %d readers were still open beyond the pools\n",
           (unsigned long long)seed, calls, s_findings - before, xlx_workbook_count(), xlx_read_count());
    return s_findings - before;
}

/* ------------------------------------------------------------------ */
/* Damaged files. Every public read call is made on whatever opens.    */
/* ------------------------------------------------------------------ */
static void read_everything(const char *path)
{
    s_current = "xlx_read_open (a damaged file)";
    int r = xlx_read_open(path);
    text(xlx_last_error());
    if (!r) return;
    int sheets = xlx_read_sheet_count(r);
    if (sheets < 1 || sheets > 4096) finding("an opened file has a sheet count outside 1..4096", NULL);
    for (int s = 0; s <= sheets + 1 && s < 8; s++) {
        s_current = "reading a damaged file";
        text(xlx_read_sheet_name(r, s));
        (void)xlx_read_sheet_is_hidden(r, s);
        int loaded = xlx_read_load(r, s);
        text(xlx_last_error());
        int rows = xlx_read_row_count(r, s), cols = xlx_read_column_count(r, s);
        if (rows < 0 || rows > 1048576 || cols < 0 || cols > 16384) finding("a sheet's size is outside the grid", NULL);
        if (!loaded && (rows || cols)) finding("a sheet that did not load has a size", NULL);
        text(xlx_read_grid(r, s, 1, 1, 0, 0));
        text(xlx_read_merged(r, s));
        for (int k = 0; k < 24; k++) {
            int row = k < 12 ? 1 + k % 4 : (rows ? 1 + below(rows) : below(5));
            int col = k < 12 ? 1 + k / 4 : (cols ? 1 + below(cols) : below(5));
            text(xlx_read_cell(r, s, row, col));
            text(xlx_read_cell_value(r, s, row, col));
            text(xlx_read_cell_kind(r, s, row, col));
            text(xlx_read_cell_formula(r, s, row, col));
            text(xlx_read_cell_format(r, s, row, col));
            number(xlx_read_cell_number(r, s, row, col));
        }
    }
    (void)xlx_read_uses_1904(r);
    (void)xlx_read_sheet_number(r, "Data");
    xlx_read_close(r);
    if (xlx_read_is_valid(r)) finding("a reader outlived its close", NULL);
}

static size_t slurp(const char *path, unsigned char *buffer, size_t cap)
{
    FILE *f = fopen(path, "rb");
    size_t n = f ? fread(buffer, 1, cap, f) : 0;
    if (f) fclose(f);
    return n;
}
static void spit(const char *path, const unsigned char *bytes, size_t n)
{
    FILE *f = fopen(path, "wb");
    if (f) { fwrite(bytes, 1, n, f); fclose(f); }
}

/* Round 1: a real workbook (deflated, as every program writes them) with
 * bytes flipped, runs zeroed, and cut short. Most damage lands in compressed
 * data and is caught by inflate or by the checksum; the damage that lands in
 * the zip's own records is the point. */
static void damage_whole_files(int rounds)
{
    static unsigned char good[1 << 18], bad[1 << 18];
    size_t n = slurp(F_A, good, sizeof good);
    if (n < 1000 || n == sizeof good) { finding("the workbook to damage is not there, or is larger than the test allows for", F_A); return; }
    for (int round = 0; round < rounds; round++) {
        memcpy(bad, good, n);
        size_t length = n;
        int kind = below(6);
        if (kind == 0) {
            length = (size_t)below((int)n);
        } else if (kind == 1) {
            for (int k = 1 + below(4); k > 0; k--) bad[below((int)n)] ^= (unsigned char)(1 << below(8));
        } else if (kind == 2) {
            /* the last 400 bytes hold the directory and its end record */
            for (int k = 1 + below(3); k > 0; k--) bad[n - 1 - (size_t)below(400)] = (unsigned char)rnd();
        } else if (kind == 3) {
            size_t at = (size_t)below((int)n), run = (size_t)below(64);
            for (size_t i = at; i < n && i < at + run; i++) bad[i] = below(2) ? 0 : 0xFF;
        } else if (kind == 4) {
            /* the first 120 bytes: the first local header */
            bad[below(120)] = (unsigned char)rnd();
        } else {
            /* a slice moved: sizes and offsets no longer agree */
            size_t from_at = (size_t)below((int)n), to_at = (size_t)below((int)n), run = (size_t)below(200);
            if (from_at + run < n && to_at + run < n) memmove(bad + to_at, good + from_at, run);
        }
        spit(F_BAD, bad, length);
        read_everything(F_BAD);
    }
}

/* Round 2: files built part by part and STORED, so damaged XML reaches the
 * parser with a zip around it that is in order (and a checksum that
 * matches: the damage is the document's, not the archive's). */
static const char *const k_sheet_pieces[] = {
    "<row r=\"1\">", "<row>", "</row>", "<row r=\"1048576\">", "<row r=\"1048577\">", "<row r=\"0\">", "<row r=\"-1\">",
    "<c r=\"A1\"><v>1</v></c>", "<c r=\"B2\" t=\"s\"><v>0</v></c>", "<c r=\"C3\" t=\"s\"><v>999999999</v></c>",
    "<c t=\"s\"><v>-1</v></c>", "<c r=\"XFD1048576\"><v>2</v></c>", "<c r=\"XFE1\"><v>2</v></c>", "<c r=\"A0\"><v>2</v></c>",
    "<c r=\"AAAA1\"><v>2</v></c>", "<c r=\"A1B2\"><v>2</v></c>", "<c r=\"\"><v>2</v></c>", "<c r=\"A99999999999\"/>",
    "<c t=\"inlineStr\"><is><t>inline</t></is></c>", "<c t=\"inlineStr\"><is><r><t>a</t></r><rPh><t>b</t></rPh></is></c>",
    "<c t=\"b\"><v>1</v></c>", "<c t=\"e\"><v>#N/A</v></c>", "<c t=\"str\"><f>A1&amp;\"x\"</f><v>x</v></c>",
    "<c t=\"d\"><v>2024-01-01</v></c>", "<c t=\"zzzzzzzzzzzzzzzzzzzzzzzz\"><v>1</v></c>", "<c s=\"1\"><v>45292.5</v></c>",
    "<c s=\"2\"><v>-5</v></c>", "<c s=\"4294967295\"><v>1</v></c>", "<c s=\"99999999999999\"><v>1</v></c>",
    "<c><v>1e999</v></c>", "<c><v>nan</v></c>", "<c><v>0x10</v></c>", "<c><v>1,5</v></c>", "<c><v> 7 </v></c>",
    "<c><v>1.7976931348623157e308</v></c>", "<c><v>4.9e-324</v></c>", "<c><v></v></c>", "<c><v>", "</v></c>", "<c>", "</c>",
    "<c><f>SUM(A1:A2)</f></c>", "<c><f t=\"shared\" si=\"0\"/><v>3</v></c>", "<c><f></f><f>B1</f><v>1</v><v>2</v></c>",
    "<v>stray</v>", "<f>stray</f>", "<t>stray</t>", "<is><t>stray</t></is>", "<c><c><v>1</v></c></c>",
    "<c><is><is><t>x</t></is></is></c>", "<c><v>_x0041__x000D__xD800__x0000__xFFFF_</v></c>",
    "<c t=\"str\"><v>_x0041__x000D__xD800__x0000__xFFFF__x00e9_</v></c>", "<c t=\"s\"><v>1</v></c>", "<c t=\"s\"><v>2</v></c>",
    "</sheetData>", "<sheetData>", "<mergeCells><mergeCell ref=\"A1:B2\"/><mergeCell ref=\"B2:A1\"/><mergeCell ref=\"A1\"/>"
    "<mergeCell ref=\"A1:XFE9\"/><mergeCell/></mergeCells>", "<x:c xmlns:x=\"urn:x\" r=\"D4\"><x:v>4</x:v></x:c>",
    "<!-- a comment -->", "<![CDATA[<c><v>1</v></c>]]>", "<?pi here?>", "&amp;", "&#x41;", "&#0;", "&bogus;", "\xFF\xFE", "\xEF\xBB\xBF",
    "<c r=\"E5\"><v>5</v></c><c r=\"E5\"><v>55</v></c><c r=\"A5\"><v>0</v></c>", "caf\xC3\xA9", "<c><v>\xC3\x28</v></c>",
    "<a><b><c><d><e>", "</e></d></c></b></a>", "<c r=\"B2\" xmlns=\"\"><v>1</v></c>",
};
#define PIECES ((int)(sizeof(k_sheet_pieces) / sizeof(k_sheet_pieces[0])))

static const char *const k_strings_parts[] = {
    NULL,
    "<sst><si><t>zero</t></si><si><r><t>o</t></r><r><t>ne</t></r></si><si><t>two</t><rPh><t>NO</t></rPh></si></sst>",
    "<sst><si><t>zero</t></si><si><t>cut",
    "<sst><si/><si><t/></si><si><t>_x0041__x000D__xD800__x0000_</t></si></sst>",
    "<sst><si><si><t>nested</t></si></si><t>stray</t><rPh><rPh><t>x</t></rPh></rPh><si><t>after</t></si></sst>",
    "", "<!DOCTYPE sst [<!ENTITY a \"aaaaaaaaaa\">]><sst><si><t>&a;</t></si></sst>",
};
static const char *const k_styles_parts[] = {
    NULL,
    "<styleSheet><numFmts><numFmt numFmtId=\"164\" formatCode=\"yyyy-mm-dd\"/><numFmt numFmtId=\"165\" formatCode=\"[Red\"/>"
    "<numFmt numFmtId=\"166\" formatCode=\"&quot;open\"/></numFmts><cellXfs><xf numFmtId=\"0\"/><xf numFmtId=\"164\"/>"
    "<xf numFmtId=\"14\"/><xf numFmtId=\"165\"/><xf numFmtId=\"166\"/><xf numFmtId=\"4294967295\"/><xf/></cellXfs></styleSheet>",
    "<styleSheet><cellXfs><xf numFmtId=\"14\"/><xf numFmtId=\"14\"", "",
    "<styleSheet><numFmts><numFmt numFmtId=\"x\" formatCode=\"d\"/><numFmt formatCode=\"d\"/><numFmt numFmtId=\"1\"/></numFmts>"
    "<cellXfs><cellXfs><xf numFmtId=\"-1\"/></cellXfs><xf numFmtId=\"22\"/></cellXfs><xf numFmtId=\"14\"/></styleSheet>",
};

static void damage_documents(int rounds)
{
    static char sheet[1 << 16];
    for (int round = 0; round < rounds; round++) {
        size_t n = 0;
        int open_tag = below(12) != 0, pieces = 1 + below(40);
        if (open_tag) n += (size_t)snprintf(sheet + n, sizeof sheet - n, "%s", TZ_SHEET_OPEN);
        for (int k = 0; k < pieces && n < sizeof sheet - 2048; k++) {
            const char *piece = k_sheet_pieces[below(PIECES)];
            int repeats = below(30) == 0 ? 1 + below(200) : 1;
            for (int rep = 0; rep < repeats && n < sizeof sheet - 2048; rep++)
                n += (size_t)snprintf(sheet + n, sizeof sheet - n, "%s", piece);
        }
        if (below(8) != 0) n += (size_t)snprintf(sheet + n, sizeof sheet - n, "%s", TZ_SHEET_CLOSE);
        /* then, sometimes, the bytes themselves */
        if (below(4) == 0)
            for (int k = 1 + below(3); k > 0 && n > 0; k--) sheet[below((int)n)] = (char)(1 + below(255));
        sheet[n] = '\0';
        if (!tz_workbook(F_BAD, sheet, k_strings_parts[below(7)], k_styles_parts[below(5)])) { finding("the test could not write a file", F_BAD); return; }
        read_everything(F_BAD);
    }
}

/* Round 3: the parts AROUND the sheet: relationships that point nowhere,
 * at each other, out of the file; a workbook with thousands of sheets, or
 * with names no sheet may have. */
static void damage_packaging(void)
{
    static const char *const targets[] = {
        "worksheets/sheet1.xml", "/xl/worksheets/sheet1.xml", "../xl/worksheets/sheet1.xml", "../../../../etc/passwd",
        "", "/", "..", "./././worksheets/./sheet1.xml", "worksheets//sheet1.xml", "workbook.xml", "_rels/workbook.xml.rels",
        "C:\\Windows\\win.ini", "http://example.org/sheet.xml", "worksheets/sheet1.xml?x=1", "sheet\xC3\x28.xml",
        "worksheets/../worksheets/../worksheets/sheet1.xml", "/_rels/.rels", "sharedStrings.xml"};
    static char rels[4096], workbook[1 << 18];
    static const char sheet[] = TZ_SHEET_OPEN "<row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\"><v>2</v></c></row>" TZ_SHEET_CLOSE;
    static const char strings[] = "<sst><si><t>zero</t></si></sst>";
    int count = (int)(sizeof targets / sizeof targets[0]);
    for (int a = 0; a < count; a++) {
        for (int b = 0; b < 3; b++) {
            /* a: where the sheet is said to be; b: what else is said */
            snprintf(rels, sizeof rels,
                     "<Relationships>"
                     "<Relationship Id=\"rId1\" Type=\"x/worksheet\" Target=\"%s\"/>"
                     "<Relationship Id=\"rId2\" Type=\"x/sharedStrings\" Target=\"%s\"/>"
                     "<Relationship Id=\"rId3\" Type=\"x/styles\" Target=\"%s\"/>"
                     "<Relationship Id=\"rId1\" Type=\"x/worksheet\" Target=\"second-with-the-same-id.xml\"/>"
                     "<Relationship Type=\"x/worksheet\" Target=\"no-id.xml\"/><Relationship Id=\"rId9\"/>"
                     "</Relationships>",
                     targets[a], b == 0 ? "sharedStrings.xml" : targets[(a + b * 5) % count],
                     b == 2 ? "worksheets/sheet1.xml" : "styles.xml");
            TzPart parts[] = {{"_rels/.rels", TZ_RELS, sizeof TZ_RELS - 1}, {"xl/workbook.xml", TZ_WORKBOOK, sizeof TZ_WORKBOOK - 1},
                              {"xl/_rels/workbook.xml.rels", rels, strlen(rels)}, {"xl/worksheets/sheet1.xml", sheet, sizeof sheet - 1},
                              {"xl/sharedStrings.xml", strings, sizeof strings - 1}};
            if (!tz_write(F_BAD, parts, 5, -1)) { finding("the test could not write a file", F_BAD); return; }
            read_everything(F_BAD);
        }
    }
    /* workbooks: 5000 sheets (more than the reader takes), then sheets with
     * every kind of name and id */
    for (int kind = 0; kind < 4; kind++) {
        size_t n = (size_t)snprintf(workbook, sizeof workbook, "<workbook xmlns:r=\"urn:r\"><workbookPr date1904=\"%s\"/><sheets>",
                                    kind == 0 ? "1" : kind == 1 ? "true" : kind == 2 ? "maybe" : "");
        int sheets = kind == 0 ? 5000 : kind == 1 ? 4096 : 40;
        for (int i = 0; i < sheets && n < sizeof workbook - 1024; i++) {
            if (kind == 3 && i % 4 == 0) n += (size_t)snprintf(workbook + n, sizeof workbook - n, "<sheet r:id=\"rId1\"/><sheet name=\"n\"/><sheet name=\"\" r:id=\"\"/>");
            else if (kind == 3 && i % 4 == 1) n += (size_t)snprintf(workbook + n, sizeof workbook - n, "<sheet name=\"%.*s\" r:id=\"rId1\"/>", 300, s_long_a);
            else n += (size_t)snprintf(workbook + n, sizeof workbook - n, "<sheet name=\"S%d\" state=\"%s\" r:id=\"rId%d\"/>", i, i % 3 ? "visible" : "hidden", 1 + i % 3);
        }
        snprintf(workbook + n, sizeof workbook - n, "</sheets></workbook>");
        TzPart parts[] = {{"xl/workbook.xml", workbook, strlen(workbook)}, {"xl/_rels/workbook.xml.rels", TZ_WORKBOOK_RELS, sizeof TZ_WORKBOOK_RELS - 1},
                          {"xl/worksheets/sheet1.xml", sheet, sizeof sheet - 1}, {"xl/sharedStrings.xml", strings, sizeof strings - 1}};
        if (!tz_write(F_BAD, parts, 4, -1)) { finding("the test could not write a file", F_BAD); return; }
        read_everything(F_BAD);
    }
}

/* Make the calls a trace names. */
static int replay(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[1024];
    int made = 0;
    if (!f) { printf("cannot open %s\n", path); return 2; }
    while (fgets(line, sizeof(line), f)) {
        char *open = strchr(line, '(');
        double a[16] = { 0 };
        int n = 0;
        if (!open || strncmp(line, "xlx_", 4) != 0) continue;
        *open = 0;
        const FuzzCall *c = find_call(line);
        if (!c) continue;
        for (char *p = open + 1; *p && *p != ')' && n < 16; ) {
            char *end = p;
            a[n] = strtod(p, &end);
            if (end == p) break;
            n++;
            p = end;
            while (*p == ',' || *p == ' ') p++;
        }
        if (n != c->argc) continue;
        s_current = c->name;
        c->replay(a);
        made++;
    }
    fclose(f);
    printf("replayed %d calls: %d finding(s)\n", made, s_findings);
    return s_findings ? 1 : 0;
}

int main(int argc, char **argv)
{
    int calls = 30000;
    s_trace = getenv("FUZZ_TRACE") != NULL;
    build_strings();
    /* The seed scene and the draws name texts by their place in the table;
     * a table edited without them would quietly fuzz with the wrong words. */
    if (STRING_COUNT != 130 || strcmp(k_strings[8], "Data") != 0 || strcmp(k_strings[26], "formulas") != 0
        || strcmp(k_strings[27], "column") != 0 || strcmp(k_strings[31], "scatter") != 0 || strcmp(k_strings[48], "#FF0000") != 0
        || strcmp(k_strings[60], "0.00") != 0 || strcmp(k_strings[72], "=Data!$A$1:$A$9") != 0 || strcmp(k_strings[84], "https://example.org/") != 0
        || k_strings[92][0] != 0 || strcmp(k_strings[94], "plain") != 0 || k_strings[127] != s_grid) {
        printf("the table of strings no longer matches the indices the test uses\n");
        return 2;
    }
    if (!tz_png(F_PNG)) { printf("cannot write %s in the current directory\n", F_PNG); return 2; }
    if (argc > 2 && strcmp(argv[1], "--replay") == 0) return replay(argv[2]);
    if (argc > 2) calls = atoi(argv[2]);
    if (argc > 1) {
        run((uint64_t)strtoull(argv[1], NULL, 10), calls);
    } else {
        for (uint64_t seed = 1; seed <= 3; seed++) run(seed, calls);
    }
    /* The damaged-file rounds need one good workbook; the random calls may
     * have left F_A in any state, so it is written afresh. */
    s_rng = 0x2545F4914F6CDD1Dull;
    s_trace = 0;
    {
        int book = xlx_workbook_new(F_A);
        int sheet = xlx_workbook_add_sheet(book, "Data");
        int format = xlx_workbook_add_format(book);
        xlx_format_set_number_format(format, "yyyy-mm-dd");
        xlx_sheet_write_grid(sheet, 1, 1, s_grid, "formulas", 0);
        xlx_sheet_write_date(sheet, 70, 1, 45292, format);
        xlx_sheet_merge(sheet, 72, 1, 73, 2, "merged", 0);
        xlx_sheet_write_text(xlx_workbook_add_sheet(book, "Second"), 1, 1, "two", 0);
        s_current = "writing the workbook to damage";
        if (!xlx_workbook_close(book)) finding("the workbook to damage could not be written", xlx_last_error());
        read_everything(F_A);
    }
    int before = s_findings;
    damage_whole_files(1500);
    printf("damaged whole files: 1500 files, %d findings\n", s_findings - before);
    before = s_findings;
    damage_documents(2500);
    printf("damaged documents: 2500 files, %d findings\n", s_findings - before);
    before = s_findings;
    damage_packaging();
    printf("damaged packaging: %d findings\n", s_findings - before);
    if (xlx_workbook_count() != 0 || xlx_read_count() != 0) {
        s_current = "the end";
        finding("something is still open", NULL);
    }
    if (s_findings == 0) {
        static const char *const files[] = { F_A, F_B, F_C, F_BAD, F_PNG, "xlsxt-fuzz-no-such-file.xlsx" };
        for (size_t i = 0; i < sizeof files / sizeof files[0]; i++) remove(files[i]);
    }
    printf("xlsxt fuzz test: %d finding(s)\n", s_findings);
    return s_findings ? 1 : 0;
}
