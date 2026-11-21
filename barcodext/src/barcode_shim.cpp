/*
 * barcode_shim.cpp
 * ----------------------------------------------------------------------------
 * The shim of barcodext: zxing-cpp (the C++ "zebra crossing" barcode library)
 * behind a flat C ABI that the xTalk Builder (LCB) foreign function interface
 * can call, so OpenXTalk and LiveCode-compatible engines can READ QR codes and
 * barcodes out of a picture, and write them. webpxt/src/webp_shim.c is this
 * file's sibling and its conventions are kept:
 *
 *   - A PICTURE COMES IN THE ENGINE'S OWN LAYOUT: an image's `imageData`,
 *     four bytes a pixel (one unused byte, then red, green, blue), rows top
 *     to bottom. A created barcode goes back the same way, so a script moves
 *     pictures with `the imageData of image ...` and reorders nothing. A
 *     camera's grey frame (one byte a pixel) is taken too.
 *   - A RESULT IS HELD HERE AND READ BACK. A read leaves its barcodes in one
 *     static list; the binding asks for each one's fields by a 1-based index,
 *     builds engine values and releases the list. A create leaves its symbol
 *     in a second slot, which the render calls draw from.
 *   - Text crosses as a pointer to a static buffer that the binding copies at
 *     once (as a Pointer through its textOf(), never as ZStringNative: the
 *     engine FREES a returned C string). A barcode's text may hold a zero
 *     byte, so bcx_text_length answers from the buffer's own length, never
 *     from strlen.
 *   - THE EXCEPTION FIREWALL (suite rule 2). zxing-cpp throws (a format name
 *     it does not know, an option it cannot parse, std::bad_alloc), and a
 *     throw that crossed `extern "C"` would take the engine down. Every
 *     export runs inside guarded(), which turns any exception into a refused
 *     call: 0, empty or -1 back, and bcx_last_error() saying why.
 *
 * Safety. A picture is untrusted input and so is the text a script asks to
 * encode. Every buffer has a length that is checked against the stated size
 * before a byte is read; sizes are capped (BCX_MAX_PIXELS in, BCX_MAX_RENDER
 * out); zxing-cpp is given a bounds-checked view of the pixels. Nothing here
 * runs off the caller's thread, and no callback exists to reach script
 * (suite rule 1). tests/fuzz_test.cpp feeds it noise and damaged symbols
 * under ASan/UBSan.
 *
 * Build: compiled with zxing-cpp into ONE shared library named "barcodext"
 * (barcodext.so / barcodext.dll / barcodext.dylib), or for the web into a
 * static archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include "ZXingCpp.h"
#include "Version.h"

#include <algorithm>
#include <cctype>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <new>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#if defined(_WIN32)
    #define BCX_API __declspec(dllexport)
#else
    #define BCX_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/barcodext.lcb's checkABI() names
 * the same number and refuses a library that answers another. */
#define BCX_ABI_VERSION 1

/* The most pixels one read takes: 2^26, an 8192 x 8192 picture. A phone
 * photograph is a fifth of that. */
#define BCX_MAX_PIXELS (1 << 26)
#define BCX_MAX_SIDE 32767

/* The largest picture one render makes: 2^24 pixels (4096 x 4096), 64 MB of
 * imageData. A QR code at 20 pixels a module is under a tenth of that. */
#define BCX_MAX_RENDER (1 << 24)
#define BCX_MAX_SCALE 64

/* The most content one barcode is asked to hold. The largest symbol there is
 * (a version 40 QR code) holds under 3000 bytes; anything longer is refused
 * here, before it reaches the encoder. */
#define BCX_MAX_CONTENT 8192

/* The longest formats or options text a call may pass. */
#define BCX_MAX_ARGUMENT 1024

namespace {

std::string s_error;
std::string s_text;                 // the text last returned

std::vector<ZXing::Barcode> s_results;      // what the last read found
ZXing::Barcode s_created;                   // what the last create made
bool s_haveCreated = false;
std::vector<std::uint8_t> s_bytes;          // the bytes last returned
std::vector<std::uint8_t> s_render;         // the picture last rendered
int s_renderWidth = 0;
int s_renderHeight = 0;

void set_error(std::string message) noexcept
{
    try {
        s_error = std::move(message);
    } catch (...) {
        s_error.clear();
    }
}

void clear_error() noexcept
{
    s_error.clear();
}

/* THE FIREWALL. Every export's body runs in here. `fallback` is what a
 * refused call returns. A lambda, not a macro, so a comma in the body is
 * just a comma (playbook section 9, the macro-comma trap). */
template <typename R, typename F>
R guarded(R fallback, F &&body) noexcept
{
    try {
        return body();
    } catch (const std::bad_alloc &) {
        set_error("out of memory");
    } catch (const std::exception &e) {
        try {
            set_error(e.what());
        } catch (...) {
            set_error("the barcode library reported an error");
        }
    } catch (...) {
        set_error("the barcode library reported an error it did not name");
    }
    return fallback;
}

/* A text result: kept in the one static buffer, its pointer handed out. */
const char *keep_text(std::string text)
{
    s_text = std::move(text);
    return s_text.c_str();
}

const char *no_text() noexcept
{
    s_text.clear();
    return s_text.c_str();
}

/* A C string argument: never NULL past here, and of a sane length. */
std::string_view argument(const char *text)
{
    if (text == nullptr) return {};
    std::size_t n = std::strlen(text);
    if (n > BCX_MAX_ARGUMENT) throw std::invalid_argument("a formats or options text is too long");
    return std::string_view(text, n);
}

std::string lower(std::string_view text)
{
    std::string out(text);
    for (char &c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return out;
}

std::string_view trim(std::string_view text)
{
    while (!text.empty() && std::isspace(static_cast<unsigned char>(text.front()))) text.remove_prefix(1);
    while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back()))) text.remove_suffix(1);
    return text;
}

/* The barcode kinds a formats text names: "" is every kind the library
 * reads. A name the library does not know is an exception with the name in
 * it, which the firewall turns into the refusal. */
ZXing::BarcodeFormats formats_of(std::string_view text)
{
    text = trim(text);
    if (text.empty()) return {};
    return ZXing::BarcodeFormats(text);
}

/* The read options text: words separated by commas, in any case. */
struct ReadSettings
{
    ZXing::ReaderOptions options;
    bool gray = false;
};

int number_of(std::string_view word, std::string_view value, int low, int high)
{
    int n = 0;
    bool any = false;
    for (char c : value) {
        if (c < '0' || c > '9' || n > 100000) {
            any = false;
            break;
        }
        n = n * 10 + (c - '0');
        any = true;
    }
    if (!any || n < low || n > high) {
        throw std::invalid_argument("the option '" + std::string(word) + "' takes a whole number from "
                                    + std::to_string(low) + " to " + std::to_string(high));
    }
    return n;
}

void read_settings_parse(ReadSettings &settings, std::string_view text)
{
    while (!text.empty()) {
        std::size_t comma = text.find(',');
        std::string_view raw = trim(text.substr(0, comma));
        text = comma == std::string_view::npos ? std::string_view() : text.substr(comma + 1);
        if (raw.empty()) continue;
        std::string word = lower(raw);
        std::string value;
        if (std::size_t equals = word.find('='); equals != std::string::npos) {
            value = std::string(trim(std::string_view(word).substr(equals + 1)));
            word = std::string(trim(std::string_view(word).substr(0, equals)));
        }
        if (word == "fast" && value.empty()) {
            settings.options.tryHarder(false);
        } else if (word == "norotate" && value.empty()) {
            settings.options.tryRotate(false);
        } else if (word == "noinvert" && value.empty()) {
            settings.options.tryInvert(false);
        } else if (word == "nodownscale" && value.empty()) {
            settings.options.tryDownscale(false);
        } else if (word == "pure" && value.empty()) {
            settings.options.isPure(true);
        } else if (word == "errors" && value.empty()) {
            settings.options.returnErrors(true);
        } else if (word == "checksum" && value.empty()) {
            settings.options.validateOptionalChecksum(true);
        } else if (word == "gray" || word == "grey") {
            if (!value.empty()) throw std::invalid_argument("the option 'gray' takes no value");
            settings.gray = true;
        } else if (word == "max") {
            settings.options.maxNumberOfSymbols(static_cast<std::uint8_t>(number_of(word, value, 1, 255)));
        } else if (word == "lines") {
            settings.options.minLineCount(static_cast<std::uint8_t>(number_of(word, value, 1, 20)));
        } else if (word == "text") {
            if (value == "hri") settings.options.textMode(ZXing::TextMode::HRI);
            else if (value == "plain") settings.options.textMode(ZXing::TextMode::Plain);
            else if (value == "eci") settings.options.textMode(ZXing::TextMode::ECI);
            else if (value == "escaped") settings.options.textMode(ZXing::TextMode::Escaped);
            else if (value == "hex") settings.options.textMode(ZXing::TextMode::Hex);
            else throw std::invalid_argument("the option 'text' is one of hri, plain, eci, escaped, hex");
        } else if (word == "addon") {
            if (value == "ignore") settings.options.eanAddOnSymbol(ZXing::EanAddOnSymbol::Ignore);
            else if (value == "read") settings.options.eanAddOnSymbol(ZXing::EanAddOnSymbol::Read);
            else if (value == "require") settings.options.eanAddOnSymbol(ZXing::EanAddOnSymbol::Require);
            else throw std::invalid_argument("the option 'addon' is one of ignore, read, require");
        } else if (word == "binarizer") {
            if (value == "local") settings.options.binarizer(ZXing::Binarizer::LocalAverage);
            else if (value == "global") settings.options.binarizer(ZXing::Binarizer::GlobalHistogram);
            else if (value == "fixed") settings.options.binarizer(ZXing::Binarizer::FixedThreshold);
            else if (value == "bool") settings.options.binarizer(ZXing::Binarizer::BoolCast);
            else throw std::invalid_argument("the option 'binarizer' is one of local, global, fixed, bool");
        } else {
            throw std::invalid_argument("'" + std::string(raw) + "' is not a read option (fast, noRotate, noInvert, "
                                        "noDownscale, pure, errors, checksum, gray, max=N, lines=N, text=..., "
                                        "addon=..., binarizer=...)");
        }
    }
}

/* The creator options text, checked HERE and rebuilt before zxing-cpp sees
 * it: words separated by commas, in any case.
 *
 *     ecLevel=H   eci=UTF-8   version=5   dataMask=3   columns=3   rows=4
 *     gs1   readerInit   forceSquare
 *
 * Why not hand the text over: zxing-cpp 3.1.1 reads these through accessors
 * declared noexcept that parse on every call, so a number it cannot parse
 * ("rows=99999999999") or a backslash in a value does not throw to the
 * firewall, it calls std::terminate and takes the engine with it (found by
 * tests/fuzz_test.cpp on its first run, 2026-11-20). What leaves here is
 * only text those accessors parse. */
std::string creator_options_clean(std::string_view text)
{
    std::string out;
    while (!text.empty()) {
        std::size_t comma = text.find(',');
        std::string_view raw = trim(text.substr(0, comma));
        text = comma == std::string_view::npos ? std::string_view() : text.substr(comma + 1);
        if (raw.empty()) continue;
        std::string word = lower(raw);
        std::string value;
        bool hasValue = false;
        if (std::size_t equals = raw.find('='); equals != std::string_view::npos) {
            value = std::string(trim(raw.substr(equals + 1)));      /* its case kept: "eci=UTF-8" */
            word = lower(trim(raw.substr(0, equals)));
            hasValue = true;
        }
        const char *name = nullptr;
        if (word == "gs1" || word == "readerinit" || word == "forcesquare") {
            if (hasValue) throw std::invalid_argument("the create option '" + word + "' takes no value");
            name = word == "gs1" ? "gs1" : word == "readerinit" ? "readerInit" : "forceSquare";
        } else if (word == "columns" || word == "rows" || word == "version" || word == "datamask") {
            value = std::to_string(number_of(word, value, 0, 999));
            name = word == "columns" ? "columns" : word == "rows" ? "rows" : word == "version" ? "version" : "dataMask";
        } else if (word == "eclevel" || word == "eci") {
            bool good = !value.empty() && value.size() <= 32;
            for (char c : value) {
                good = good && (std::isalnum(static_cast<unsigned char>(c)) || c == '%' || c == '-' || c == '_'
                                || c == ' ');
            }
            if (!good) {
                throw std::invalid_argument("the create option '" + word + "' takes a short value of letters, digits, "
                                            "'%', '-' or '_' (ecLevel=H, ecLevel=30%, eci=UTF-8)");
            }
            name = word == "eclevel" ? "ecLevel" : "eci";
        } else {
            throw std::invalid_argument("'" + std::string(raw) + "' is not a create option (ecLevel=..., eci=..., "
                                        "version=N, dataMask=N, columns=N, rows=N, gs1, readerInit, forceSquare)");
        }
        if (!out.empty()) out += ',';
        out += name;
        if (!value.empty()) out += "=" + value;
    }
    return out;
}

/* The barcode a 1-based index names, or nullptr. */
const ZXing::Barcode *result_at(int index) noexcept
{
    if (index < 1 || static_cast<std::size_t>(index) > s_results.size()) return nullptr;
    return &s_results[static_cast<std::size_t>(index) - 1];
}

} // namespace

extern "C" {

/* ------------------------------------------------------------------ */
/* The library                                                          */
/* ------------------------------------------------------------------ */
BCX_API int bcx_abi_version(void)
{
    return BCX_ABI_VERSION;
}

/* "barcodext ABI 1; zxing-cpp 3.1.1". */
BCX_API const char *bcx_library_version(void)
{
    return guarded(static_cast<const char *>(""), [] {
        return keep_text("barcodext ABI " + std::to_string(BCX_ABI_VERSION) + "; zxing-cpp " ZXING_VERSION_STR);
    });
}

/* Why the last refused call was refused; empty after a call that worked. */
BCX_API const char *bcx_last_error(void)
{
    return s_error.c_str();
}

/* The length of a text this library returned, for the binding's copy. For
 * the text last returned it is the buffer's own length, so a barcode whose
 * text holds a zero byte is not cut short. */
BCX_API int bcx_text_length(const char *text)
{
    std::size_t n;
    if (text == nullptr) return 0;
    if (text == s_text.c_str()) n = s_text.size();
    else if (text == s_error.c_str()) n = s_error.size();
    else n = std::strlen(text);
    return n > static_cast<std::size_t>(INT_MAX) ? INT_MAX : static_cast<int>(n);
}

/* The names of the barcode kinds, comma-separated: `writable` 0 lists what
 * can be read, anything else what can be created. */
BCX_API const char *bcx_format_names(int writable)
{
    return guarded(static_cast<const char *>(""), [=] {
        std::string out;
        auto all = ZXing::BarcodeFormats::list(writable ? ZXing::BarcodeFormat::AllCreatable
                                                        : ZXing::BarcodeFormat::AllReadable);
        for (ZXing::BarcodeFormat format : all) {
            if (!out.empty()) out += ',';
            out += ZXing::ToString(format);
        }
        return keep_text(std::move(out));
    });
}

/* ------------------------------------------------------------------ */
/* Reading                                                              */
/* ------------------------------------------------------------------ */

/* Find the barcodes in a picture. `pixels` is `length` bytes: an image's
 * imageData (4 bytes a pixel) of width x height, or with the option "gray"
 * one byte a pixel. `formats` names the kinds to look for, comma-separated
 * ("" = every kind); `options` is the read options text ("" = the thorough
 * defaults). Returns how many were found (0 is a good answer: none), or -1
 * when the call was refused. The bcx_result_* calls read them, 1-based. */
BCX_API int bcx_read_image(const unsigned char *pixels, int length, int width, int height, const char *formats,
                     const char *options)
{
    s_results.clear();
    return guarded(-1, [=] {
        ReadSettings settings;
        read_settings_parse(settings, argument(options));
        settings.options.formats(formats_of(argument(formats)));
        if (width < 1 || height < 1 || width > BCX_MAX_SIDE || height > BCX_MAX_SIDE) {
            set_error("a picture is from 1 x 1 to " + std::to_string(BCX_MAX_SIDE) + " pixels a side; this one is "
                      + std::to_string(width) + " x " + std::to_string(height));
            return -1;
        }
        std::int64_t count = static_cast<std::int64_t>(width) * height;
        if (count > BCX_MAX_PIXELS) {
            set_error("the picture is " + std::to_string(width) + " x " + std::to_string(height) + ", over the limit of "
                      + std::to_string(BCX_MAX_PIXELS) + " pixels for one read; scale it down first");
            return -1;
        }
        std::int64_t need = settings.gray ? count : count * 4;
        if (pixels == nullptr || static_cast<std::int64_t>(length) != need) {
            set_error(std::string(settings.gray ? "the grey data is " : "the imageData is ")
                      + std::to_string(length < 0 ? 0 : length) + " bytes; a " + std::to_string(width) + " x "
                      + std::to_string(height) + " picture is " + std::to_string(need)
                      + (settings.gray ? " (1 a pixel)" : " (4 a pixel)"));
            return -1;
        }
        /* imageData is unused, R, G, B: zxing-cpp's ARGB with an alpha it
         * never reads. The view carries the length, and checks it. */
        ZXing::ImageView view(pixels, length, width, height,
                              settings.gray ? ZXing::ImageFormat::Lum : ZXing::ImageFormat::ARGB);
        s_results = ZXing::ReadBarcodes(view, settings.options);
        if (s_results.size() > 255) s_results.resize(255);
        clear_error();
        return static_cast<int>(s_results.size());
    });
}

BCX_API int bcx_result_count(void)
{
    return static_cast<int>(s_results.size());
}

/* The barcode's content as text (UTF-8), in the text mode the read asked
 * for: by default what a person would read under the bars. */
BCX_API const char *bcx_result_text(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr ? keep_text(barcode->text()) : no_text();
    });
}

/* The kind of barcode: "QRCode", "EAN13", "Code128", ... */
BCX_API const char *bcx_result_format(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr ? keep_text(ZXing::ToString(barcode->format())) : no_text();
    });
}

/* What the content is: "Text", "Binary", "Mixed", "GS1", "ISO15434" or
 * "UnknownECI". */
BCX_API const char *bcx_result_content_type(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr ? keep_text(ZXing::ToString(barcode->contentType())) : no_text();
    });
}

/* The standard's three-character symbology identifier, such as "]Q1". */
BCX_API const char *bcx_result_symbology_id(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr ? keep_text(barcode->symbologyIdentifier()) : no_text();
    });
}

/* Where the barcode is in the picture: "x1,y1,x2,y2,x3,y3,x4,y4", its
 * corners from the top left clockwise, in pixels. */
BCX_API const char *bcx_result_position(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        if (barcode == nullptr) return no_text();
        const ZXing::Position &p = barcode->position();
        std::string out;
        for (int corner = 0; corner < 4; corner++) {
            if (corner != 0) out += ',';
            out += std::to_string(p[corner].x) + "," + std::to_string(p[corner].y);
        }
        return keep_text(std::move(out));
    });
}

/* One of the barcode's extra facts by name ("ECLevel", "Version",
 * "DataMask", "EanAddOn", "UPCE", "UEC", "ReaderInit"), or all of them as a
 * JSON object for the name "". Empty when the kind has no such fact. */
BCX_API const char *bcx_result_extra(int index, const char *key)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        if (barcode == nullptr) return no_text();
        return keep_text(barcode->extra(argument(key)));
    });
}

/* Why a barcode that was found could not be trusted (only with the read
 * option "errors"; otherwise such barcodes are left out): empty when it is
 * good. */
BCX_API const char *bcx_result_error(int index)
{
    return guarded(static_cast<const char *>(""), [=] {
        const ZXing::Barcode *barcode = result_at(index);
        if (barcode == nullptr || !barcode->error()) return no_text();
        return keep_text(ZXing::ToString(barcode->error()));
    });
}

/* The barcode's content as the bytes that are in it, nothing decoded:
 * the length now, the bytes from bcx_bytes_pointer(). */
BCX_API int bcx_result_bytes(int index)
{
    s_bytes.clear();
    return guarded(0, [=] {
        const ZXing::Barcode *barcode = result_at(index);
        if (barcode == nullptr) return 0;
        s_bytes = barcode->bytes();
        return s_bytes.size() > static_cast<std::size_t>(INT_MAX) ? 0 : static_cast<int>(s_bytes.size());
    });
}

/* The bytes the last bcx_result_bytes counted. */
BCX_API const unsigned char *bcx_bytes_pointer(void)
{
    return s_bytes.data();
}

/* How far the barcode is turned, in whole degrees clockwise. */
BCX_API int bcx_result_orientation(int index)
{
    return guarded(0, [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr ? barcode->orientation() : 0;
    });
}

/* 1 when the barcode decoded with no error. */
BCX_API int bcx_result_is_valid(int index)
{
    return guarded(0, [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr && barcode->isValid() ? 1 : 0;
    });
}

/* 1 when the barcode was read as a mirror image. */
BCX_API int bcx_result_is_mirrored(int index)
{
    return guarded(0, [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr && barcode->isMirrored() ? 1 : 0;
    });
}

/* 1 when the barcode was light on dark. */
BCX_API int bcx_result_is_inverted(int index)
{
    return guarded(0, [=] {
        const ZXing::Barcode *barcode = result_at(index);
        return barcode != nullptr && barcode->isInverted() ? 1 : 0;
    });
}

/* Free the list of barcodes. The binding calls this once it has its copies. */
BCX_API void bcx_results_release(void)
{
    s_results.clear();
    s_results.shrink_to_fit();
    s_bytes.clear();
    s_bytes.shrink_to_fit();
}

/* ------------------------------------------------------------------ */
/* Creating                                                             */
/* ------------------------------------------------------------------ */

/* Make a barcode of the kind `format` names, holding `length` bytes of
 * `content`: UTF-8 text when `isText` is not 0, otherwise raw bytes.
 * `options` is the create options text ("" for none), such as "ecLevel=H"
 * for a QR code (creator_options_clean() above lists the words). Returns 1 and keeps the symbol for the render
 * calls, or 0. */
BCX_API int bcx_create_symbol(const unsigned char *content, int length, int isText, const char *format, const char *options)
{
    s_haveCreated = false;
    s_created = ZXing::Barcode();
    return guarded(0, [=] {
        std::string_view name = trim(argument(format));
        std::string extra = creator_options_clean(argument(options));
        if (content == nullptr || length < 1) {
            set_error("nothing to encode: the content is empty");
            return 0;
        }
        if (length > BCX_MAX_CONTENT) {
            set_error("the content is " + std::to_string(length) + " bytes; one barcode holds at most "
                      + std::to_string(BCX_MAX_CONTENT));
            return 0;
        }
        if (name.empty()) {
            set_error("no barcode kind was named (QRCode, EAN13, Code128, ...)");
            return 0;
        }
        ZXing::BarcodeFormat kind = ZXing::BarcodeFormatFromString(name);
        bool creatable = false;
        for (ZXing::BarcodeFormat each : ZXing::BarcodeFormats::list(ZXing::BarcodeFormat::AllCreatable)) {
            if (each == kind) creatable = true;
        }
        if (!creatable) {
            set_error("'" + std::string(name) + "' is not a kind of barcode this library can create");
            return 0;
        }
        ZXing::CreatorOptions creator(kind, extra);
        ZXing::Barcode barcode =
            isText ? ZXing::CreateBarcodeFromText(std::string_view(reinterpret_cast<const char *>(content),
                                                                   static_cast<std::size_t>(length)), creator)
                   : ZXing::CreateBarcodeFromBytes(content, length, creator);
        if (!barcode.isValid()) {
            std::string why = ZXing::ToString(barcode.error());
            set_error(why.empty() ? "that content does not fit a " + std::string(name) + " barcode" : why);
            return 0;
        }
        s_created = std::move(barcode);
        s_haveCreated = true;
        clear_error();
        return 1;
    });
}

/* Draw the created barcode into the render slot as imageData: black on
 * white, `scale` pixels a module, with the quiet zone the standard asks for
 * around it when `quietZone` is not 0, and the human-readable text under a
 * linear barcode when `showText` is not 0. Returns 1, or 0. */
BCX_API int bcx_render_image(int scale, int quietZone, int showText)
{
    s_render.clear();
    s_renderWidth = 0;
    s_renderHeight = 0;
    return guarded(0, [=] {
        if (!s_haveCreated) {
            set_error("there is no barcode to draw: create one first");
            return 0;
        }
        if (scale < 1 || scale > BCX_MAX_SCALE) {
            set_error("the scale is a whole number from 1 to " + std::to_string(BCX_MAX_SCALE) + " pixels a module");
            return 0;
        }
        /* The symbol's own size bounds the picture before one is made: at
         * most the symbol plus a generous margin, times the scale. */
        ZXing::ImageView symbol = s_created.symbol();
        std::int64_t widest = (static_cast<std::int64_t>(symbol.width()) + 64) * scale;
        std::int64_t tallest = (static_cast<std::int64_t>(symbol.height()) + 64) * scale;
        if (symbol.width() < 1 || widest * tallest > static_cast<std::int64_t>(BCX_MAX_RENDER) * 4) {
            set_error("at that scale the barcode would be too large a picture; use a smaller scale");
            return 0;
        }
        ZXing::Image image = ZXing::WriteBarcodeToImage(
            s_created, ZXing::WriterOptions().scale(scale).addQuietZones(quietZone != 0).addHRT(showText != 0));
        int width = image.width();
        int height = image.height();
        if (width < 1 || height < 1 || image.data() == nullptr
            || static_cast<std::int64_t>(width) * height > BCX_MAX_RENDER) {
            set_error("at that scale the barcode would be too large a picture; use a smaller scale");
            return 0;
        }
        s_render.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                std::uint8_t level = *image.data(x, y);
                std::uint8_t *out = &s_render[(static_cast<std::size_t>(y) * static_cast<std::size_t>(width)
                                               + static_cast<std::size_t>(x)) * 4];
                out[0] = 255;
                out[1] = level;
                out[2] = level;
                out[3] = level;
            }
        }
        s_renderWidth = width;
        s_renderHeight = height;
        clear_error();
        return 1;
    });
}

BCX_API int bcx_render_width(void) { return s_renderWidth; }
BCX_API int bcx_render_height(void) { return s_renderHeight; }
BCX_API const unsigned char *bcx_render_pixels(void) { return s_render.data(); }

BCX_API int bcx_render_pixels_length(void)
{
    return static_cast<int>(s_render.size());
}

/* The created barcode as an SVG document (text). Empty when there is none. */
BCX_API const char *bcx_svg_text(int scale, int quietZone, int showText)
{
    return guarded(static_cast<const char *>(""), [=] {
        if (!s_haveCreated) {
            set_error("there is no barcode to draw: create one first");
            return no_text();
        }
        if (scale < 1 || scale > BCX_MAX_SCALE) {
            set_error("the scale is a whole number from 1 to " + std::to_string(BCX_MAX_SCALE) + " pixels a module");
            return no_text();
        }
        std::string svg = ZXing::WriteBarcodeToSVG(
            s_created, ZXing::WriterOptions().scale(scale).addQuietZones(quietZone != 0).addHRT(showText != 0));
        clear_error();
        return keep_text(std::move(svg));
    });
}

/* The created barcode's modules, one character each: "1" dark, "0" light,
 * a line feed after every row, no quiet zone. For a stack that draws its
 * own. Empty when there is none. */
BCX_API const char *bcx_modules_text(void)
{
    return guarded(static_cast<const char *>(""), [] {
        if (!s_haveCreated) {
            set_error("there is no barcode: create one first");
            return no_text();
        }
        ZXing::Image image =
            ZXing::WriteBarcodeToImage(s_created, ZXing::WriterOptions().scale(1).addQuietZones(false).addHRT(false));
        int width = image.width();
        int height = image.height();
        if (width < 1 || height < 1 || image.data() == nullptr
            || static_cast<std::int64_t>(width) * height > BCX_MAX_RENDER) {
            set_error("the barcode has no modules to list");
            return no_text();
        }
        std::string out;
        out.reserve((static_cast<std::size_t>(width) + 1) * static_cast<std::size_t>(height));
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) out += *image.data(x, y) < 128 ? '1' : '0';
            out += '\n';
        }
        clear_error();
        return keep_text(std::move(out));
    });
}

/* Free the created barcode and the render slot. */
BCX_API void bcx_created_release(void)
{
    s_haveCreated = false;
    guarded(0, [] {
        s_created = ZXing::Barcode();
        return 0;
    });
    s_render.clear();
    s_render.shrink_to_fit();
    s_renderWidth = 0;
    s_renderHeight = 0;
}

} // extern "C"
