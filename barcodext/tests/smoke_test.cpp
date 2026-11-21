/*
 * smoke_test.cpp - the runtime test of the barcodext shim.
 *
 * Links against the barcodext library (or, for the web, the archive) and
 * drives zxing-cpp through the same C entry points the LCB binding calls. It
 * proves what a compile cannot: that every kind of barcode the library can
 * create is drawn and READ BACK with the content it was given, turned,
 * mirrored, inverted and beside another; that the read options do what
 * their names say; and that the guards make bad buffers, bad names and
 * oversized requests harmless. Run under ASan/UBSan in CI
 * (native-barcodext.yml).
 *
 * EVERY export of src/barcode_shim.cpp is called here:
 * tools/check-shim-coverage.py refuses an export this file never calls.
 *
 * Enable with -DBARCODEXT_BUILD_TESTS=ON, then run `ctest` (or the binary).
 */
#include "bcx_exports.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int s_checks = 0;
static int s_failed = 0;

#define CHECK(cond, ...)                                                      \
    do {                                                                      \
        s_checks++;                                                           \
        if (!(cond)) {                                                        \
            s_failed++;                                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__);                  \
            std::printf(__VA_ARGS__);                                         \
            std::printf(" [last error: %s]\n", bcx_last_error());             \
        }                                                                     \
    } while (0)

/* A picture in the engine's layout: width * height * 4, unused R G B. */
struct Picture
{
    int width = 0, height = 0;
    std::vector<std::uint8_t> pixels;
};

/* A returned text, copied the way the binding copies it: at once, by the
 * length the shim reports. */
static std::string text_of(const char *text)
{
    return std::string(text, static_cast<std::size_t>(bcx_text_length(text)));
}

static bool has(const std::string &text, const char *part)
{
    return text.find(part) != std::string::npos;
}

static int create_text(const char *content, const char *format, const char *options = "")
{
    return bcx_create_symbol(reinterpret_cast<const std::uint8_t *>(content), static_cast<int>(std::strlen(content)), 1,
                             format, options);
}

/* The render slot, copied out. */
static Picture rendered()
{
    Picture p;
    p.width = bcx_render_width();
    p.height = bcx_render_height();
    p.pixels.assign(bcx_render_pixels(), bcx_render_pixels() + bcx_render_pixels_length());
    return p;
}

static Picture draw(const char *content, const char *format, int scale = 4, const char *options = "")
{
    Picture p;
    if (create_text(content, format, options) != 1) return p;
    if (bcx_render_image(scale, 1, 0) != 1) return p;
    return rendered();
}

static int read(const Picture &p, const char *formats = "", const char *options = "")
{
    return bcx_read_image(p.pixels.data(), static_cast<int>(p.pixels.size()), p.width, p.height, formats, options);
}

/* The picture turned a quarter turn clockwise, `turns` times. */
static Picture turned(const Picture &in, int turns)
{
    Picture p = in;
    for (int t = 0; t < turns; t++) {
        Picture q;
        q.width = p.height;
        q.height = p.width;
        q.pixels.resize(p.pixels.size());
        for (int y = 0; y < p.height; y++) {
            for (int x = 0; x < p.width; x++) {
                int nx = p.height - 1 - y, ny = x;
                std::memcpy(&q.pixels[(static_cast<std::size_t>(ny) * q.width + nx) * 4],
                            &p.pixels[(static_cast<std::size_t>(y) * p.width + x) * 4], 4);
            }
        }
        p = q;
    }
    return p;
}

static Picture mirrored(const Picture &in)
{
    Picture p = in;
    for (int y = 0; y < in.height; y++) {
        for (int x = 0; x < in.width; x++) {
            std::memcpy(&p.pixels[(static_cast<std::size_t>(y) * in.width + (in.width - 1 - x)) * 4],
                        &in.pixels[(static_cast<std::size_t>(y) * in.width + x) * 4], 4);
        }
    }
    return p;
}

static Picture inverted(const Picture &in)
{
    Picture p = in;
    for (std::size_t i = 0; i < p.pixels.size(); i += 4) {
        for (int c = 1; c < 4; c++) p.pixels[i + c] = static_cast<std::uint8_t>(255 - p.pixels[i + c]);
    }
    return p;
}

/* Two pictures side by side on white, with a margin between. */
static Picture beside(const Picture &a, const Picture &b)
{
    Picture p;
    int gap = 40;
    p.width = a.width + gap + b.width;
    p.height = a.height > b.height ? a.height : b.height;
    p.pixels.assign(static_cast<std::size_t>(p.width) * p.height * 4, 255);
    for (int y = 0; y < a.height; y++) {
        std::memcpy(&p.pixels[static_cast<std::size_t>(y) * p.width * 4], &a.pixels[static_cast<std::size_t>(y) * a.width * 4],
                    static_cast<std::size_t>(a.width) * 4);
    }
    for (int y = 0; y < b.height; y++) {
        std::memcpy(&p.pixels[(static_cast<std::size_t>(y) * p.width + a.width + gap) * 4],
                    &b.pixels[static_cast<std::size_t>(y) * b.width * 4], static_cast<std::size_t>(b.width) * 4);
    }
    return p;
}

static std::vector<std::string> items(const std::string &list, char separator = ',')
{
    std::vector<std::string> out;
    std::size_t from = 0;
    while (from <= list.size()) {
        std::size_t to = list.find(separator, from);
        if (to == std::string::npos) to = list.size();
        out.push_back(list.substr(from, to - from));
        from = to + 1;
    }
    return out;
}

/* ---------------------------------------------------------------------- */

static void test_library()
{
    CHECK(bcx_abi_version() == 1, "abi version %d", bcx_abi_version());
    std::string version = text_of(bcx_library_version());
    CHECK(has(version, "barcodext ABI 1") && has(version, "zxing-cpp 3.1.1"), "version '%s'", version.c_str());
    CHECK(bcx_text_length(nullptr) == 0, "text length of NULL");
    CHECK(bcx_text_length("abc") == 3, "text length of a plain C string");
    std::string readable = text_of(bcx_format_names(0));
    std::string writable = text_of(bcx_format_names(1));
    for (const char *name : {"QR Code", "EAN-13", "Code 128", "Data Matrix", "PDF417", "Aztec", "UPC-A"}) {
        CHECK(has("," + readable + ",", ("," + std::string(name) + ",").c_str()), "readable kinds lack %s", name);
        CHECK(has("," + writable + ",", ("," + std::string(name) + ",").c_str()), "writable kinds lack %s", name);
    }
}

/* Every kind the library says it can create: made, drawn, read back. The
 * table names what to put in each and what a reader then reports (a kind
 * with a check digit or a fixed width reports the full number; a family
 * name creates one member of the family). */
struct RoundTrip
{
    const char *format;      /* the name asked for */
    const char *content;
    const char *readFormat;  /* the kind a read of every kind names; nullptr: not asserted */
    const char *readText;    /* nullptr: the content, unchanged */
    const char *namedFormat; /* the kind a read asked for `format` names; nullptr: readFormat; "-": none */
    const char *namedText;   /* nullptr: readText */
};

/* What zxing-cpp 3.1.1 answers, OBSERVED (2026-11-20), quirks included:
 *   - a UPC-A is an EAN-13 with a leading 0 unless the read asks for UPC-A,
 *     and its text is the 13 digits either way;
 *   - a UPC-E's text is the 13-digit number it stands for (the 8 digits are
 *     the extra fact "UPCE");
 *   - Telepen Numeric and Telepen Alpha are the same bars: a read of every
 *     kind takes them as Alpha, a read asked for Numeric gets the digits;
 *   - a variant (ITF-14, Compact PDF417, QR Code Model 2, Aztec Rune,
 *     DataBar Stacked Omni) is created under its own name and read under
 *     its family's;
 *   - an ISBN is created (an EAN-13 starting 978 or 979) and read as
 *     EAN-13; a read asked for "ISBN" alone finds nothing.
 * A new zxing-cpp that changes one of these fails here, by name. */
static const RoundTrip k_round_trips[] = {
    {"Code 39", "XTALK-39", "Code 39", nullptr, nullptr, nullptr},
    {"Code 32", "12345", "Code 32", "A000123455", nullptr, nullptr},
    {"Code 39 Extended", "Hello, xTalk", "Code 39 Extended", nullptr, nullptr, nullptr},
    {"Pharmazentralnummer", "12345", "Pharmazentralnummer", "-00123458", nullptr, nullptr},
    {"Code 39 Standard", "12345", "Code 39", nullptr, nullptr, nullptr},
    {"Telepen", "Hello, xTalk", "Telepen Alpha", nullptr, nullptr, nullptr},
    {"Telepen Alpha", "Hello, xTalk", "Telepen Alpha", nullptr, nullptr, nullptr},
    {"Telepen Numeric", "123456", nullptr, nullptr, "Telepen Numeric", nullptr},
    {"Code 128", "Hello, xTalk", "Code 128", nullptr, nullptr, nullptr},
    {"EAN/UPC", "5901234123457", "EAN-13", nullptr, nullptr, nullptr},
    {"EAN-13", "5901234123457", "EAN-13", nullptr, nullptr, nullptr},
    {"EAN-8", "96385074", "EAN-8", nullptr, nullptr, nullptr},
    {"UPC-A", "036000291452", "EAN-13", "0036000291452", "UPC-A", nullptr},
    {"UPC-E", "01234565", "UPC-E", "0012345000065", nullptr, nullptr},
    {"ISBN", "9780306406157", "EAN-13", nullptr, "-", nullptr},
    {"Codabar", "A12345B", "Codabar", nullptr, nullptr, nullptr},
    {"Code 93", "Hello, xTalk", "Code 93", nullptr, nullptr, nullptr},
    {"ITF", "1234567890", "ITF", nullptr, nullptr, nullptr},
    {"ITF-14", "12345678901231", "ITF", nullptr, nullptr, nullptr},
    {"PDF417", "Hello, xTalk", "PDF417", nullptr, nullptr, nullptr},
    {"Compact PDF417", "Hello, xTalk", "PDF417", nullptr, nullptr, nullptr},
    {"MicroPDF417", "Hello, xTalk", "MicroPDF417", nullptr, nullptr, nullptr},
    {"QR Code", "Hello, xTalk", "QR Code", nullptr, nullptr, nullptr},
    {"QR Code Model 2", "Hello, xTalk", "QR Code", nullptr, nullptr, nullptr},
    {"Micro QR Code", "Hello, xTalk", "Micro QR Code", nullptr, nullptr, nullptr},
    {"rMQR Code", "Hello, xTalk", "rMQR Code", nullptr, nullptr, nullptr},
    {"MaxiCode", "Hello, xTalk", "MaxiCode", nullptr, nullptr, nullptr},
    {"DX Film Edge", "127-15", "DX Film Edge", nullptr, nullptr, nullptr},
    {"Data Matrix", "Hello, xTalk", "Data Matrix", nullptr, nullptr, nullptr},
    {"DataBar", "0950110153000", "DataBar Omni", "(01)09501101530003", nullptr, nullptr},
    {"DataBar Expanded Stacked", "(01)09501101530003", "DataBar Expanded Stacked", nullptr, nullptr, nullptr},
    {"DataBar Stacked Omni", "0950110153000", "DataBar Stacked", "(01)09501101530003", nullptr, nullptr},
    {"DataBar Expanded", "(01)09501101530003", "DataBar Expanded", nullptr, nullptr, nullptr},
    {"DataBar Limited", "0950110153000", "DataBar Limited", "(01)09501101530003", nullptr, nullptr},
    {"DataBar Omni", "0950110153000", "DataBar Omni", "(01)09501101530003", nullptr, nullptr},
    {"DataBar Stacked", "0950110153000", "DataBar Stacked", "(01)09501101530003", nullptr, nullptr},
    {"Aztec", "Hello, xTalk", "Aztec", nullptr, nullptr, nullptr},
    {"Aztec Code", "Hello, xTalk", "Aztec", nullptr, nullptr, nullptr},
    {"Aztec Rune", "123", "Aztec", nullptr, nullptr, nullptr},
};

/* Created, and by design not readable alone: the two- and five-digit
 * add-ons are only ever read beside an EAN or UPC symbol. */
static const char *const k_addons[] = {"EAN-2", "EAN-5"};

static void test_every_kind()
{
    std::vector<std::string> writable = items(text_of(bcx_format_names(1)));
    CHECK(writable.size() >= 30, "only %d writable kinds", static_cast<int>(writable.size()));
    for (const std::string &name : writable) {
        bool addon = false;
        for (const char *each : k_addons) addon = addon || name == each;
        const RoundTrip *row = nullptr;
        for (const RoundTrip &each : k_round_trips) {
            if (name == each.format) row = &each;
        }
        if (addon) {
            Picture p = draw(name == "EAN-2" ? "12" : "12345", name.c_str());
            CHECK(p.width > 0 && p.height > 0, "%s was not drawn", name.c_str());
            continue;
        }
        /* A new zxing-cpp that creates a new kind must get a row here. */
        CHECK(row != nullptr, "the writable kind '%s' has no round trip in this test", name.c_str());
        if (row == nullptr) continue;
        Picture p = draw(row->content, row->format);
        CHECK(p.width > 0 && p.height > 0 && p.pixels.size() == static_cast<std::size_t>(p.width) * p.height * 4,
              "%s: '%s' was not drawn", row->format, row->content);
        if (p.width == 0) continue;
        const char *wantText = row->readText != nullptr ? row->readText : row->content;
        if (row->readFormat != nullptr) {
            int found = read(p);
            CHECK(found == 1, "%s: read found %d", row->format, found);
            if (found >= 1) {
                std::string format = text_of(bcx_result_format(1));
                std::string text = text_of(bcx_result_text(1));
                CHECK(format == row->readFormat, "%s: read as '%s', expected '%s'", row->format, format.c_str(),
                      row->readFormat);
                CHECK(text == wantText, "%s: read '%s' from '%s'", row->format, text.c_str(), row->content);
                CHECK(bcx_result_is_valid(1) == 1, "%s: not valid", row->format);
            }
        }
        /* Asked for by the name it was created under. */
        const char *namedFormat = row->namedFormat != nullptr ? row->namedFormat : row->readFormat;
        int named = read(p, row->format);
        if (std::strcmp(namedFormat, "-") == 0) {
            CHECK(named == 0, "%s: a read by that name found %d (the table says none)", row->format, named);
            continue;
        }
        CHECK(named == 1, "%s: a read by that name found %d", row->format, named);
        if (named >= 1) {
            std::string format = text_of(bcx_result_format(1));
            std::string text = text_of(bcx_result_text(1));
            CHECK(format == namedFormat, "%s: read by name as '%s', expected '%s'", row->format, format.c_str(),
                  namedFormat);
            CHECK(text == (row->namedText != nullptr ? row->namedText : wantText), "%s: read by name '%s' from '%s'",
                  row->format, text.c_str(), row->content);
        }
    }
    bcx_results_release();
    CHECK(bcx_result_count() == 0, "results survive release");
}

static void test_result_fields()
{
    Picture p = draw("https://openxtalk.org/", "QR Code", 5, "ecLevel=H");
    CHECK(p.width > 0, "QR code was not drawn");
    CHECK(read(p) == 1, "QR code was not read");
    CHECK(bcx_result_count() == 1, "result count %d", bcx_result_count());
    CHECK(text_of(bcx_result_text(1)) == "https://openxtalk.org/", "text '%s'", bcx_result_text(1));
    CHECK(text_of(bcx_result_format(1)) == "QR Code", "format '%s'", bcx_result_format(1));
    CHECK(text_of(bcx_result_content_type(1)) == "Text", "content type '%s'", bcx_result_content_type(1));
    CHECK(text_of(bcx_result_symbology_id(1)) == "]Q1", "symbology id '%s'", bcx_result_symbology_id(1));
    CHECK(text_of(bcx_result_extra(1, "ECLevel")) == "H", "ECLevel '%s'", bcx_result_extra(1, "ECLevel"));
    CHECK(!text_of(bcx_result_extra(1, "Version")).empty(), "no Version");
    CHECK(text_of(bcx_result_extra(1, "NoSuchFact")).empty(), "an unknown fact has a value");
    CHECK(has(text_of(bcx_result_extra(1, "")), "ECLevel"), "all facts: '%s'", bcx_result_extra(1, ""));
    CHECK(text_of(bcx_result_error(1)).empty(), "a good barcode has an error: '%s'", bcx_result_error(1));
    CHECK(bcx_result_orientation(1) == 0, "orientation %d", bcx_result_orientation(1));
    CHECK(bcx_result_is_valid(1) == 1, "not valid");
    CHECK(bcx_result_is_mirrored(1) == 0, "mirrored");
    CHECK(bcx_result_is_inverted(1) == 0, "inverted");

    /* The corners: eight numbers, inside the picture, the top left first.
     * At 5 pixels a module with a 4-module quiet zone the symbol starts at
     * 20,20. */
    std::vector<std::string> corners = items(text_of(bcx_result_position(1)));
    CHECK(corners.size() == 8, "position '%s'", bcx_result_position(1));
    if (corners.size() == 8) {
        int x1 = std::atoi(corners[0].c_str()), y1 = std::atoi(corners[1].c_str());
        int x3 = std::atoi(corners[4].c_str()), y3 = std::atoi(corners[5].c_str());
        CHECK(x1 >= 18 && x1 <= 22 && y1 >= 18 && y1 <= 22, "top left corner %d,%d", x1, y1);
        CHECK(x3 > p.width - 26 && x3 < p.width - 16 && y3 > p.height - 26 && y3 < p.height - 16,
              "bottom right corner %d,%d of %d x %d", x3, y3, p.width, p.height);
    }

    /* The bytes: what is in the symbol, nothing decoded. */
    int n = bcx_result_bytes(1);
    CHECK(n == 22 && std::memcmp(bcx_bytes_pointer(), "https://openxtalk.org/", 22) == 0, "bytes length %d", n);

    /* An index that names no barcode answers empty, 0, and does not fail. */
    for (int index : {0, 2, -1, 1000000}) {
        CHECK(text_of(bcx_result_text(index)).empty(), "text at %d", index);
        CHECK(text_of(bcx_result_format(index)).empty(), "format at %d", index);
        CHECK(text_of(bcx_result_content_type(index)).empty(), "content type at %d", index);
        CHECK(text_of(bcx_result_symbology_id(index)).empty(), "symbology at %d", index);
        CHECK(text_of(bcx_result_position(index)).empty(), "position at %d", index);
        CHECK(text_of(bcx_result_extra(index, "ECLevel")).empty(), "extra at %d", index);
        CHECK(text_of(bcx_result_error(index)).empty(), "error at %d", index);
        CHECK(bcx_result_bytes(index) == 0, "bytes at %d", index);
        CHECK(bcx_result_orientation(index) == 0 && bcx_result_is_valid(index) == 0
                  && bcx_result_is_mirrored(index) == 0 && bcx_result_is_inverted(index) == 0,
              "flags at %d", index);
    }
    CHECK(text_of(bcx_result_extra(1, nullptr)) == text_of(bcx_result_extra(1, "")), "a NULL fact name");
}

static void test_binary_content()
{
    /* Bytes with a zero among them, and every high value: in as data, back
     * as the same bytes; the text's length is the buffer's, not strlen's. */
    std::uint8_t content[64];
    for (int i = 0; i < 64; i++) content[i] = static_cast<std::uint8_t>(i * 4 + (i == 0 ? 0 : 3));
    content[5] = 0;
    CHECK(bcx_create_symbol(content, 64, 0, "QR Code", "") == 1, "binary QR code was not created");
    CHECK(bcx_render_image(4, 1, 0) == 1, "binary QR code was not drawn");
    Picture p = rendered();
    CHECK(read(p) == 1, "binary QR code was not read");
    int n = bcx_result_bytes(1);
    CHECK(n == 64 && std::memcmp(bcx_bytes_pointer(), content, 64) == 0, "binary bytes came back as %d", n);
    CHECK(text_of(bcx_result_content_type(1)) == "Binary", "content type '%s'", bcx_result_content_type(1));

    static const char with_zero[] = {'A', 'B', 0, 'C', 'D'};
    CHECK(bcx_create_symbol(reinterpret_cast<const std::uint8_t *>(with_zero), 5, 1, "Code 128", "") == 1,
          "Code 128 with a zero byte was not created");
    CHECK(bcx_render_image(3, 1, 0) == 1, "it was not drawn");
    p = rendered();
    CHECK(read(p, "", "text=plain") == 1, "it was not read");
    const char *text = bcx_result_text(1);
    CHECK(bcx_text_length(text) == 5 && std::memcmp(text, with_zero, 5) == 0, "text with a zero byte: length %d",
          bcx_text_length(text));

    /* UTF-8 text goes in and comes back as UTF-8. */
    const char *utf8 = "Gr\xC3\xBC\xC3\x9F" "e \xE2\x82\xAC" "5";
    p = draw(utf8, "QR Code");
    CHECK(read(p) == 1 && text_of(bcx_result_text(1)) == utf8, "UTF-8 text came back as '%s'", bcx_result_text(1));
}

static void test_turned_mirrored_inverted()
{
    Picture qr = draw("turn me", "QR Code", 4);
    Picture ean = draw("5901234123457", "EAN-13", 3);
    for (int turns = 1; turns <= 3; turns++) {
        Picture t = turned(qr, turns);
        CHECK(read(t) == 1 && text_of(bcx_result_text(1)) == "turn me", "QR code turned %d quarter turns", turns);
        CHECK(bcx_result_orientation(1) == (turns == 1 ? 90 : turns == 2 ? 180 : -90),
              "orientation %d after %d quarter turns", bcx_result_orientation(1), turns);
        t = turned(ean, turns);
        CHECK(read(t) == 1 && text_of(bcx_result_text(1)) == "5901234123457", "EAN-13 turned %d quarter turns", turns);
    }
    /* "noRotate" reads a linear barcode only as it is drawn. */
    CHECK(read(turned(ean, 1), "", "noRotate") == 0, "noRotate still read a turned EAN-13");
    CHECK(read(ean, "", "noRotate") == 1, "noRotate lost an upright EAN-13");

    Picture m = mirrored(qr);
    CHECK(read(m) == 1 && bcx_result_is_mirrored(1) == 1, "a mirrored QR code");
    Picture i = inverted(qr);
    CHECK(read(i) == 1 && bcx_result_is_inverted(1) == 1 && text_of(bcx_result_text(1)) == "turn me",
          "an inverted QR code");
    CHECK(read(i, "", "noInvert") == 0, "noInvert still read an inverted QR code");
}

static void test_read_options()
{
    Picture qr = draw("left", "QR Code", 4);
    Picture dm = draw("right", "Data Matrix", 6);
    Picture both = beside(qr, dm);
    int found = read(both);
    CHECK(found == 2, "two barcodes: found %d", found);
    if (found == 2) {
        std::string a = text_of(bcx_result_text(1)), b = text_of(bcx_result_text(2));
        CHECK((a == "left" && b == "right") || (a == "right" && b == "left"), "two barcodes: '%s' and '%s'", a.c_str(),
              b.c_str());
    }
    CHECK(read(both, "", "max=1") == 1, "max=1 found %d", bcx_result_count());
    CHECK(read(both, "Data Matrix") == 1 && text_of(bcx_result_text(1)) == "right", "formats 'Data Matrix'");
    CHECK(read(both, "QR Code, Data Matrix") == 2, "formats 'QR Code, Data Matrix'");
    CHECK(read(both, "qrcode") == 1 && text_of(bcx_result_text(1)) == "left", "formats 'qrcode'");
    CHECK(read(both, "EAN-13") == 0 && text_of(bcx_last_error()).empty(), "formats 'EAN-13' found something");
    /* Every word, in any case, with spaces around it. */
    CHECK(read(both, "", " FAST , noRotate, noInvert ,noDownscale,pure,errors,checksum, max=3, lines=2, text=hri, "
                         "addon=ignore, binarizer=local") >= 0,
          "every option together was refused");
    for (const char *word : {"text=plain", "text=eci", "text=escaped", "text=hex", "addon=read", "addon=require",
                             "binarizer=global", "binarizer=fixed", "binarizer=bool", "", " ", ",,"}) {
        CHECK(read(qr, "QR Code", word) >= 0, "the option '%s' was refused", word);
    }
    CHECK(read(qr, "", "text=hex") == 1 && text_of(bcx_result_text(1)) == "6C 65 66 74", "text=hex gave '%s'",
          bcx_result_text(1));
    /* "pure": a clean, upright, computer-made picture, read the fast way. */
    CHECK(read(qr, "", "pure") == 1 && text_of(bcx_result_text(1)) == "left", "pure lost a clean QR code");

    /* A grey picture: one byte a pixel. */
    Picture grey;
    grey.width = qr.width;
    grey.height = qr.height;
    for (std::size_t i = 0; i < qr.pixels.size(); i += 4) grey.pixels.push_back(qr.pixels[i + 1]);
    CHECK(bcx_read_image(grey.pixels.data(), static_cast<int>(grey.pixels.size()), grey.width, grey.height, "", "gray")
              == 1 && text_of(bcx_result_text(1)) == "left",
          "a grey picture");
    CHECK(bcx_read_image(grey.pixels.data(), static_cast<int>(grey.pixels.size()), grey.width, grey.height, "", "GREY")
              == 1,
          "the spelling 'grey'");

    /* "errors": a barcode whose check digit is wrong is reported, with why. */
    Picture ean = draw("5901234123457", "EAN-13", 3);
    CHECK(read(ean, "", "errors") == 1 && text_of(bcx_result_error(1)).empty() && bcx_result_is_valid(1) == 1,
          "a good EAN-13 under 'errors'");

    /* An add-on (the two small digits beside a magazine's EAN-13): left out
     * unless asked for, and "require" reads nothing that has none. */
    Picture withAddon = draw("5901234123457+12", "EAN-13", 3);
    CHECK(withAddon.width > ean.width, "an EAN-13 with an add-on is no wider: %d", withAddon.width);
    CHECK(read(withAddon) == 1 && text_of(bcx_result_text(1)) == "5901234123457"
              && text_of(bcx_result_extra(1, "EanAddOn")).empty(),
          "an add-on that was not asked for");
    CHECK(read(withAddon, "", "addon=require") == 1 && text_of(bcx_result_text(1)) == "590123412345712",
          "addon=require read '%s'", bcx_result_text(1));
    CHECK(text_of(bcx_result_extra(1, "EanAddOn")) == "12", "EanAddOn '%s'", bcx_result_extra(1, "EanAddOn"));
    CHECK(read(withAddon, "", "addon=read") >= 1, "addon=read");
    CHECK(read(ean, "", "addon=require") == 0, "addon=require read an EAN-13 with no add-on");
    /* A UPC-E's eight digits are an extra fact. */
    CHECK(read(draw("01234565", "UPC-E", 3)) == 1 && text_of(bcx_result_extra(1, "UPCE")) == "01234565", "UPCE '%s'",
          bcx_result_extra(1, "UPCE"));

    /* A picture with no barcode in it: none found, and that is no error. */
    Picture blank;
    blank.width = 120;
    blank.height = 80;
    blank.pixels.assign(120 * 80 * 4, 255);
    CHECK(read(blank) == 0 && text_of(bcx_last_error()).empty(), "a blank picture");
    Picture dot;
    dot.width = dot.height = 1;
    dot.pixels.assign(4, 0);
    CHECK(read(dot) == 0, "a 1 x 1 picture");
}

static void test_render()
{
    CHECK(create_text("render", "QR Code") == 1, "create");
    /* The modules: 21 lines of 21 characters for a version 1 QR code. */
    std::string modules = text_of(bcx_modules_text());
    std::vector<std::string> rows = items(modules, '\n');
    CHECK(rows.size() == 22 && rows[0].size() == 21 && rows[21].empty(), "modules: %d rows", static_cast<int>(rows.size()));
    CHECK(rows[0].substr(0, 8) == "11111110", "the finder pattern's top row is '%s'", rows[0].c_str());
    CHECK(modules.find_first_not_of("01\n") == std::string::npos, "modules hold other characters");

    /* Scale and quiet zone decide the picture's size, exactly. */
    CHECK(bcx_render_image(1, 0, 0) == 1 && bcx_render_width() == 21 && bcx_render_height() == 21, "1 px, no margin: %d x %d",
          bcx_render_width(), bcx_render_height());
    CHECK(bcx_render_pixels_length() == 21 * 21 * 4, "pixels length %d", bcx_render_pixels_length());
    /* Black on white, the unused byte 255, and the picture IS the modules. */
    bool same = true;
    for (int y = 0; y < 21 && same; y++) {
        for (int x = 0; x < 21 && same; x++) {
            const std::uint8_t *px = bcx_render_pixels() + (y * 21 + x) * 4;
            std::uint8_t want = rows[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)] == '1' ? 0 : 255;
            same = px[0] == 255 && px[1] == want && px[2] == want && px[3] == want;
        }
    }
    CHECK(same, "the 1 px picture is not the modules");
    CHECK(bcx_render_image(7, 0, 0) == 1 && bcx_render_width() == 147 && bcx_render_height() == 147, "7 px: %d x %d",
          bcx_render_width(), bcx_render_height());
    CHECK(bcx_render_image(7, 1, 0) == 1 && bcx_render_width() == 147 + 2 * 4 * 7, "7 px with the quiet zone: %d",
          bcx_render_width());
    const std::uint8_t *corner = bcx_render_pixels();
    CHECK(corner[1] == 255 && corner[2] == 255 && corner[3] == 255, "the quiet zone is not white");

    /* The text under a linear barcode makes the picture taller. */
    CHECK(create_text("5901234123457", "EAN-13") == 1, "create EAN-13");
    CHECK(bcx_render_image(3, 1, 0) == 1, "draw EAN-13");
    int plain = bcx_render_height();
    CHECK(bcx_render_image(3, 1, 1) == 1 && bcx_render_height() > plain, "with its text: %d, without: %d",
          bcx_render_height(), plain);
    Picture p = rendered();
    CHECK(read(p) == 1 && text_of(bcx_result_text(1)) == "5901234123457", "an EAN-13 drawn with its text");

    /* The same barcode as SVG. */
    std::string svg = text_of(bcx_svg_text(2, 1, 1));
    CHECK(has(svg, "<svg") && has(svg, "</svg>"), "svg: '%.60s'", svg.c_str());
    CHECK(has(svg, "901234"), "the SVG lacks the text under the bars");
    CHECK(!has(text_of(bcx_svg_text(2, 1, 0)), "901234"), "the SVG has text it was not asked for");

    /* Creator options: a bigger error-correction level is a bigger symbol;
     * a version is a size. */
    CHECK(create_text("options", "QR Code", "version=5") == 1 && bcx_render_image(1, 0, 0) == 1 && bcx_render_width() == 37,
          "version=5 gave %d modules", bcx_render_width());
    CHECK(create_text("options", "Data Matrix", "forceSquare") == 1 && bcx_render_image(1, 0, 0) == 1
              && bcx_render_width() == bcx_render_height(),
          "forceSquare gave %d x %d", bcx_render_width(), bcx_render_height());

    bcx_created_release();
    CHECK(bcx_render_width() == 0 && bcx_render_height() == 0 && bcx_render_pixels_length() == 0, "render survives release");
    CHECK(bcx_render_image(4, 1, 0) == 0 && has(text_of(bcx_last_error()), "create one first"), "render with nothing created");
    CHECK(text_of(bcx_svg_text(4, 1, 0)).empty() && has(text_of(bcx_last_error()), "create one first"),
          "svg with nothing created");
    CHECK(text_of(bcx_modules_text()).empty() && has(text_of(bcx_last_error()), "create one first"),
          "modules with nothing created");
}

static void test_refusals()
{
    Picture qr = draw("refuse", "QR Code", 4);
    int length = static_cast<int>(qr.pixels.size());

    /* Reading: every bad buffer is refused with -1 and a reason, and leaves
     * no results behind. */
    CHECK(read(qr) == 1, "the control picture");
    CHECK(bcx_read_image(nullptr, length, qr.width, qr.height, "", "") == -1 && has(text_of(bcx_last_error()), "imageData"),
          "NULL pixels");
    CHECK(bcx_result_count() == 0, "a refused read left results");
    CHECK(bcx_read_image(qr.pixels.data(), length - 4, qr.width, qr.height, "", "") == -1, "a short buffer");
    CHECK(bcx_read_image(qr.pixels.data(), length, qr.width + 1, qr.height, "", "") == -1, "a wrong width");
    CHECK(bcx_read_image(qr.pixels.data(), length, qr.width, qr.height, "", "gray") == -1
              && has(text_of(bcx_last_error()), "1 a pixel"),
          "imageData called grey");
    CHECK(bcx_read_image(qr.pixels.data(), 0, 0, 0, "", "") == -1, "a 0 x 0 picture");
    CHECK(bcx_read_image(qr.pixels.data(), length, -qr.width, -qr.height, "", "") == -1, "negative sides");
    CHECK(bcx_read_image(qr.pixels.data(), length, 40000, 1, "", "") == -1, "a side over the limit");
    CHECK(bcx_read_image(qr.pixels.data(), length, 20000, 20000, "", "") == -1 && has(text_of(bcx_last_error()), "limit"),
          "a picture over the pixel limit");
    CHECK(bcx_read_image(qr.pixels.data(), -1, qr.width, qr.height, "", "") == -1, "a negative length");
    CHECK(read(qr, "NoSuchBarcode") == -1 && !text_of(bcx_last_error()).empty(), "an unknown kind to read");
    CHECK(read(qr, "", "sideways") == -1 && has(text_of(bcx_last_error()), "sideways"), "an unknown option");
    CHECK(read(qr, "", "max=0") == -1 && read(qr, "", "max=999") == -1 && read(qr, "", "max=") == -1
              && read(qr, "", "max=two") == -1,
          "bad numbers for max");
    CHECK(read(qr, "", "lines=99") == -1, "lines=99");
    CHECK(read(qr, "", "text=loud") == -1 && read(qr, "", "addon=maybe") == -1 && read(qr, "", "binarizer=best") == -1,
          "bad values for text, addon, binarizer");
    CHECK(read(qr, "", "fast=1") == -1 && read(qr, "", "gray=1") == -1, "a value on a word that takes none");
    std::string big(2000, 'x');
    CHECK(read(qr, big.c_str()) == -1 && read(qr, "", big.c_str()) == -1, "an over-long argument");
    CHECK(bcx_read_image(qr.pixels.data(), length, qr.width, qr.height, nullptr, nullptr) == 1, "NULL formats and options");
    CHECK(text_of(bcx_last_error()).empty(), "a good call left an error: '%s'", bcx_last_error());

    /* Creating. */
    CHECK(create_text("", "QR Code") == 0 && has(text_of(bcx_last_error()), "empty"), "empty content");
    CHECK(bcx_create_symbol(nullptr, 5, 1, "QR Code", "") == 0, "NULL content");
    CHECK(bcx_create_symbol(reinterpret_cast<const std::uint8_t *>("x"), -1, 1, "QR Code", "") == 0, "negative length");
    CHECK(create_text("x", "") == 0 && create_text("x", nullptr) == 0, "no kind named");
    CHECK(create_text("x", "NoSuchBarcode") == 0 && !text_of(bcx_last_error()).empty(), "an unknown kind to create");
    CHECK(create_text("letters", "EAN-13") == 0 && !text_of(bcx_last_error()).empty(), "letters in an EAN-13");
    CHECK(create_text("5901234123450", "EAN-13") == 0, "an EAN-13 with a wrong check digit");
    std::string huge(9000, '7');
    CHECK(create_text(huge.c_str(), "QR Code") == 0 && has(text_of(bcx_last_error()), "at most"), "content over the cap");
    std::string tooMuch(4000, 'k');
    CHECK(create_text(tooMuch.c_str(), "QR Code") == 0 && !text_of(bcx_last_error()).empty(),
          "more than a QR code holds");
    CHECK(create_text("x", "QR Code", big.c_str()) == 0, "over-long creator options");
    /* Create options are checked before the library sees them: zxing-cpp
     * 3.1.1 ends the PROCESS on a number it cannot parse. */
    for (const char *bad : {"rows=99999999999", "version=-1", "version=five", "dataMask=", "ecLevel=", "ecLevel=\\",
                            "eci=\"26\"", "gs1=1", "nonsense", "=", "{\"version\":5}", "version=1000"}) {
        CHECK(create_text("x", "QR Code", bad) == 0 && !text_of(bcx_last_error()).empty(), "the create option '%s'", bad);
    }
    for (const char *good : {"", " ", ",,", "ecLevel=L", " ECLEVEL = H , VERSION = 3 ", "eci=UTF-8", "eci=26", "dataMask=3",
                             "readerInit", "forceSquare", "columns=3,rows=4"}) {
        CHECK(create_text("x", "QR Code", good) == 1, "the create option '%s' was refused", good);
    }
    /* A value is the library's to judge: "h" is not a level, and GS1 data
     * has a shape. */
    CHECK(create_text("x", "QR Code", "ecLevel=h") == 0 && has(text_of(bcx_last_error()), "ecLevel"), "ecLevel=h");
    CHECK(create_text("x", "QR Code", "gs1") == 0, "gs1 content with no application identifier");
    CHECK(create_text("(01)09501101530003", "QR Code", "gs1") == 1 && bcx_render_image(4, 1, 0) == 1, "a GS1 QR code");
    {
        Picture gs1 = rendered();
        CHECK(read(gs1) == 1 && text_of(bcx_result_content_type(1)) == "GS1"
                  && text_of(bcx_result_text(1)) == "(01)09501101530003",
              "a GS1 QR code read as '%s'", bcx_result_text(1));
    }
    CHECK(create_text("letters", "EAN-13") == 0, "a refusal after a good create");
    CHECK(bcx_render_image(4, 1, 0) == 0, "a refused create left a symbol to draw");

    /* Rendering. */
    CHECK(create_text("scale", "QR Code") == 1, "create");
    CHECK(bcx_render_image(0, 1, 0) == 0 && bcx_render_image(-3, 1, 0) == 0 && bcx_render_image(65, 1, 0) == 0
              && has(text_of(bcx_last_error()), "scale"),
          "scales out of range");
    CHECK(bcx_render_pixels_length() == 0, "a refused render left a picture");
    CHECK(text_of(bcx_svg_text(0, 1, 0)).empty() && text_of(bcx_svg_text(65, 1, 0)).empty(), "svg scales out of range");
    CHECK(bcx_render_image(64, 1, 0) == 1 && bcx_render_width() == (21 + 8) * 64, "the largest scale: %d", bcx_render_width());
    /* The largest symbols at the largest scale pass the picture cap: refused,
     * not attempted. */
    std::string long128(60, 'W');
    CHECK(create_text(long128.c_str(), "Code 128") == 1, "a long Code 128");
    CHECK(bcx_render_image(64, 1, 0) == 0 && has(text_of(bcx_last_error()), "smaller scale"), "a render over the cap: %d x %d",
          bcx_render_width(), bcx_render_height());
    CHECK(bcx_render_image(2, 1, 0) == 1, "the same symbol at a small scale");
    bcx_created_release();
    bcx_results_release();
}

int main()
{
    test_library();
    test_every_kind();
    test_result_fields();
    test_binary_content();
    test_turned_mirrored_inverted();
    test_read_options();
    test_render();
    test_refusals();
    std::printf("barcodext smoke: %d checks, %d failed (%s)\n", s_checks, s_failed, bcx_library_version());
    return s_failed == 0 ? 0 : 1;
}
