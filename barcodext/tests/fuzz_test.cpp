/*
 * fuzz_test.cpp - noise, damaged symbols and random calls against the
 * barcodext shim.
 *
 * A picture is whatever a camera saw or a stranger sent, and the text a
 * script asks to encode is whatever a user typed. This test draws real
 * barcodes of every kind with the library's own writer, damages the
 * pictures (noise, blocks painted over, rows cut, sizes misreported), reads
 * each with formats and options drawn at random, and between pictures asks
 * the writer for barcodes of random content, kind, options and scale. What
 * it holds:
 *
 *   - nothing crashes, reads out of bounds or leaks (the lane runs it under
 *     ASan/UBSan, where each of those ends the run);
 *   - a read answers -1 or a count from 0 to 255, and every field of every
 *     barcode it counted is readable for the length the shim reports;
 *   - a render that says 1 left a picture whose buffer is exactly the size
 *     its width and height mean, within the cap;
 *   - a refused call left an explanation;
 *   - an undamaged picture is still read correctly between the damaged ones
 *     (the state one call leaves does not poison the next).
 *
 *     barcodext_fuzz [seed [iterations]]      one seed
 *     barcodext_fuzz                          seeds 1 to 3, 400 iterations each
 *
 * The same seed gives the same run on every platform (its own generator, no
 * rand()).
 */
#include "bcx_exports.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int s_failed = 0;
static std::uint64_t s_state = 1;

#define HOLD(cond, ...)                                                       \
    do {                                                                      \
        if (!(cond)) {                                                        \
            s_failed++;                                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__);                  \
            std::printf(__VA_ARGS__);                                         \
            std::printf(" [last error: %s]\n", bcx_last_error());             \
        }                                                                     \
    } while (0)

/* splitmix64: small, good enough, and the same everywhere. */
static std::uint64_t next()
{
    std::uint64_t z = (s_state += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

static int below(int n)
{
    return n <= 0 ? 0 : static_cast<int>(next() % static_cast<std::uint64_t>(n));
}

struct Picture
{
    int width = 0, height = 0;
    std::vector<std::uint8_t> pixels;
};

static std::vector<std::string> s_kinds;

static const char *const k_options[] = {
    "", "fast", "noRotate", "noInvert", "noDownscale", "pure", "errors", "checksum", "max=1", "max=255", "lines=1",
    "lines=20", "text=plain", "text=eci", "text=escaped", "text=hex", "text=hri", "addon=read", "addon=require",
    "addon=ignore", "binarizer=global", "binarizer=fixed", "binarizer=bool", "binarizer=local",
    /* refused ones */
    "max=0", "lines=0", "text=", "nonsense", "=", "max=99999999999999999999", "binarizer", ",=,", "gray=2",
};

static const char *const k_creator_options[] = {
    "", "ecLevel=L", "ecLevel=H", "ecLevel=30%", "version=1", "version=40", "version=999", "forceSquare", "gs1",
    "readerInit", "columns=3", "rows=4", "columns=0", "dataMask=3", "dataMask=77", "eci=UTF-8", "eci=26", "eci=bogus",
    "nonsense=1", "=", ",,,", "ecLevel=", "version=-1", "rows=99999999999", "{\"a\":1}", "vertical", "ecLevel=\\",
    "eci=\\u00", "ecLevel=Z", "eci=899", "eci=3", "version=0", "dataMask=999",
};

static const char *const k_contents[] = {
    "Hello, xTalk", "12345", "5901234123457", "96385074", "036000291452", "01234565", "1234567890", "A12345B",
    "0950110153000", "(01)09501101530003", "127-15", "123", "9780306406157", "[)>\x1e" "01\x1d" "96", "+12", "12",
    "a", "0", "-", "(", "(01)", "(99)", "\xff\xfe", "\xC3\xBC", "%", "*", "5901234123457+12345",
};

static std::string random_options(const char *const *table, int count)
{
    std::string out;
    int words = below(4);
    for (int i = 0; i < words; i++) {
        if (!out.empty()) out += below(8) == 0 ? " , " : ",";
        out += table[below(count)];
    }
    return out;
}

static std::string random_formats()
{
    std::string out;
    int n = below(4) == 0 ? below(4) : 0;
    for (int i = 0; i < n; i++) {
        if (!out.empty()) out += ",";
        out += s_kinds[static_cast<std::size_t>(below(static_cast<int>(s_kinds.size())))];
    }
    if (below(40) == 0) out += ",NotABarcode";
    return out;
}

static std::string random_content()
{
    if (below(3) != 0) return k_contents[below(static_cast<int>(sizeof k_contents / sizeof k_contents[0]))];
    std::string out;
    int n = below(below(6) == 0 ? 3000 : 40);
    int mode = below(3);
    for (int i = 0; i < n; i++) {
        out += mode == 0 ? static_cast<char>('0' + below(10))
                         : mode == 1 ? static_cast<char>(32 + below(95)) : static_cast<char>(below(256));
    }
    return out;
}

/* Every field of every barcode the last read counted, read the way the
 * binding reads them. */
static void touch_results(int count)
{
    HOLD(count == bcx_result_count(), "read said %d, the count says %d", count, bcx_result_count());
    unsigned sum = 0;
    for (int index = 0; index <= count + 1; index++) {
        const char *text;
        const char *const facts[] = {"", "ECLevel", "Version", "DataMask", "EanAddOn", "UPCE", "UEC", "ReaderInit", "x"};
        text = bcx_result_text(index);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        text = bcx_result_format(index);
        HOLD((index >= 1 && index <= count) == (bcx_text_length(text) > 0), "format at %d of %d: '%s'", index, count, text);
        text = bcx_result_content_type(index);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        text = bcx_result_symbology_id(index);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        text = bcx_result_position(index);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        text = bcx_result_error(index);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        text = bcx_result_extra(index, facts[below(9)]);
        for (int i = bcx_text_length(text); i-- > 0;) sum += static_cast<unsigned char>(text[i]);
        int n = bcx_result_bytes(index);
        HOLD(n >= 0, "bytes length %d", n);
        for (int i = 0; i < n; i++) sum += bcx_bytes_pointer()[i];
        sum += static_cast<unsigned>(bcx_result_orientation(index) + bcx_result_is_valid(index)
                                     + bcx_result_is_mirrored(index) + bcx_result_is_inverted(index));
    }
    (void)sum;
}

/* Ask the writer for a barcode; when it makes one, draw it. Returns the
 * picture (empty when refused). */
static Picture create_random(bool wild)
{
    Picture p;
    std::string kind = s_kinds[static_cast<std::size_t>(below(static_cast<int>(s_kinds.size())))];
    std::string content = random_content();
    std::string options = wild ? random_options(k_creator_options, sizeof k_creator_options / sizeof k_creator_options[0])
                               : std::string();
    if (wild && below(30) == 0) kind = "NotABarcode";
    int made = bcx_create_symbol(reinterpret_cast<const std::uint8_t *>(content.data()), static_cast<int>(content.size()),
                                 below(5) != 0, kind.c_str(), options.c_str());
    HOLD(made == 0 || made == 1, "create answered %d", made);
    if (made != 1) {
        HOLD(bcx_text_length(bcx_last_error()) > 0, "a refused create of '%s' left no reason", kind.c_str());
        HOLD(bcx_render_image(2, 1, 0) == 0, "a refused create left something to draw");
        return p;
    }
    int scale = wild && below(6) == 0 ? below(70) - 2 : 1 + below(5);
    int drawn = bcx_render_image(scale, below(2), below(2));
    if (drawn != 1) {
        HOLD(bcx_text_length(bcx_last_error()) > 0, "a refused render left no reason");
        HOLD(bcx_render_pixels_length() == 0, "a refused render left a picture");
        return p;
    }
    p.width = bcx_render_width();
    p.height = bcx_render_height();
    HOLD(p.width >= 1 && p.height >= 1 && static_cast<long long>(p.width) * p.height <= (1 << 24)
             && bcx_render_pixels_length() == p.width * p.height * 4,
         "render: %d x %d in %d bytes", p.width, p.height, bcx_render_pixels_length());
    p.pixels.assign(bcx_render_pixels(), bcx_render_pixels() + bcx_render_pixels_length());
    if (below(4) == 0) {
        const char *svg = bcx_svg_text(1 + below(4), below(2), below(2));
        HOLD(bcx_text_length(svg) > 20, "no SVG for a created '%s'", kind.c_str());
        const char *modules = bcx_modules_text();
        HOLD(bcx_text_length(modules) > 1, "no modules for a created '%s'", kind.c_str());
    }
    return p;
}

static void damage(Picture &p)
{
    std::size_t size = p.pixels.size();
    if (size == 0) return;
    switch (below(7)) {
    case 0: /* salt and pepper */
        for (int i = below(2000); i-- > 0;) p.pixels[next() % size] = static_cast<std::uint8_t>(below(256));
        break;
    case 1: { /* a block painted over */
        int x0 = below(p.width), y0 = below(p.height), w = 1 + below(p.width / 2 + 1), h = 1 + below(p.height / 2 + 1);
        std::uint8_t level = static_cast<std::uint8_t>(below(2) * 255);
        for (int y = y0; y < p.height && y < y0 + h; y++) {
            for (int x = x0; x < p.width && x < x0 + w; x++) {
                std::memset(&p.pixels[(static_cast<std::size_t>(y) * p.width + x) * 4], level, 4);
            }
        }
        break;
    }
    case 2: /* rows cut off the bottom */
        p.height = 1 + below(p.height);
        p.pixels.resize(static_cast<std::size_t>(p.width) * p.height * 4);
        break;
    case 3: /* the same bytes called another shape */
        if (p.width % 2 == 0) {
            p.width /= 2;
            p.height *= 2;
        }
        break;
    case 4: /* every pixel noise */
        for (std::size_t i = 0; i < size; i++) p.pixels[i] = static_cast<std::uint8_t>(next());
        break;
    case 5: /* a run of rows shifted sideways */
        for (int y = below(p.height); y < p.height; y += 1 + below(3)) {
            std::uint8_t *row = &p.pixels[static_cast<std::size_t>(y) * p.width * 4];
            std::memmove(row, row + 4, static_cast<std::size_t>(p.width - 1) * 4);
        }
        break;
    default: /* untouched */
        break;
    }
}

static void read_random(const Picture &p)
{
    std::string formats = random_formats();
    std::string options = random_options(k_options, sizeof k_options / sizeof k_options[0]);
    int width = p.width, height = p.height;
    int length = static_cast<int>(p.pixels.size());
    const std::uint8_t *pixels = p.pixels.data();
    std::vector<std::uint8_t> grey;
    if (below(6) == 0) {
        for (std::size_t i = 1; i < p.pixels.size(); i += 4) grey.push_back(p.pixels[i]);
        pixels = grey.data();
        length = static_cast<int>(grey.size());
        options += options.empty() ? "gray" : ",gray";
    }
    /* Sometimes the sizes lie; the buffer the shim may read stays `length`. */
    if (below(12) == 0) width += below(5) - 2;
    if (below(12) == 0) height = below(3) == 0 ? -height : height + below(5) - 2;
    int count = bcx_read_image(pixels, length, width, height, below(20) == 0 ? nullptr : formats.c_str(),
                               below(20) == 0 ? nullptr : options.c_str());
    HOLD(count >= -1 && count <= 255, "read answered %d", count);
    if (count < 0) {
        HOLD(bcx_text_length(bcx_last_error()) > 0, "a refused read left no reason (formats '%s', options '%s')",
             formats.c_str(), options.c_str());
        HOLD(bcx_result_count() == 0, "a refused read left results");
        touch_results(0);
    } else {
        touch_results(count);
    }
    if (below(3) == 0) bcx_results_release();
}

static void control()
{
    static const char content[] = "the control";
    HOLD(bcx_create_symbol(reinterpret_cast<const std::uint8_t *>(content), 11, 1, "QR Code", "") == 1, "control: create");
    HOLD(bcx_render_image(3, 1, 0) == 1, "control: draw");
    int n = bcx_read_image(bcx_render_pixels(), bcx_render_pixels_length(), bcx_render_width(), bcx_render_height(), "", "");
    const char *text = bcx_result_text(1);
    HOLD(n == 1 && bcx_text_length(text) == 11 && std::memcmp(text, content, 11) == 0, "control: read %d", n);
}

static void run(std::uint64_t seed, int iterations)
{
    s_state = seed;
    for (int i = 0; i < iterations; i++) {
        Picture p = create_random(below(3) == 0);
        if (p.width > 0) {
            int rounds = 1 + below(3);
            for (int r = 0; r < rounds; r++) {
                Picture q = p;
                damage(q);
                read_random(q);
            }
        } else if (below(4) == 0) {
            /* No barcode at all: a random picture of a random small size. */
            Picture noise;
            noise.width = 1 + below(200);
            noise.height = 1 + below(200);
            noise.pixels.resize(static_cast<std::size_t>(noise.width) * noise.height * 4);
            int fill = below(3);
            for (std::uint8_t &b : noise.pixels) b = fill == 0 ? static_cast<std::uint8_t>(next()) : fill == 1 ? 0 : 255;
            read_random(noise);
        }
        if (i % 25 == 0) control();
        if (below(10) == 0) bcx_created_release();
    }
    control();
}

int main(int argc, char **argv)
{
    std::string kinds = bcx_format_names(1);
    for (std::size_t from = 0; from <= kinds.size();) {
        std::size_t to = kinds.find(',', from);
        if (to == std::string::npos) to = kinds.size();
        s_kinds.push_back(kinds.substr(from, to - from));
        from = to + 1;
    }
    if (s_kinds.size() < 30) {
        std::printf("FAIL: only %d writable kinds\n", static_cast<int>(s_kinds.size()));
        return 1;
    }
    if (argc > 1) {
        run(std::strtoull(argv[1], nullptr, 10), argc > 2 ? std::atoi(argv[2]) : 400);
    } else {
        for (std::uint64_t seed = 1; seed <= 3; seed++) run(seed, 400);
    }
    bcx_results_release();
    bcx_created_release();
    HOLD(bcx_result_count() == 0 && bcx_render_pixels_length() == 0, "something survived the releases");
    std::printf("barcodext fuzz: %d failed (%s)\n", s_failed, bcx_library_version());
    return s_failed == 0 ? 0 : 1;
}
