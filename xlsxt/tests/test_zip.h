/*
 * test_zip.h - the tests' own zip WRITER, shared by smoke_test.c and
 * fuzz_test.c.
 *
 * The reader half of the shim must cope with .xlsx files that libxlsxwriter
 * did not write: Excel's, LibreOffice's, a web service's, a stranger's. The
 * tests therefore need to build a file part by part, say exactly what is in
 * each part, and get some of it wrong on purpose. This writes a zip whose
 * members are STORED (no compression), which every zip reader accepts, so an
 * XML part can be given byte for byte - and damaged byte for byte - and
 * still reach the parser. Files compressed with deflate are covered by the
 * round trips through libxlsxwriter, which deflates everything.
 *
 * Nothing here is part of the library, and nothing here uses the library.
 */
#ifndef XLSXT_TEST_ZIP_H
#define XLSXT_TEST_ZIP_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    const char *name;                     /* the path inside the zip          */
    const char *data;
    size_t size;
} TzPart;

static uint32_t tz_crc(const unsigned char *data, size_t n)
{
    static uint32_t table[256];
    static int ready = 0;
    if (!ready) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            table[i] = c;
        }
        ready = 1;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

static void tz_u16(FILE *f, unsigned v) { fputc((int)(v & 0xFF), f); fputc((int)((v >> 8) & 0xFF), f); }
static void tz_u32(FILE *f, uint32_t v) { tz_u16(f, v & 0xFFFF); tz_u16(f, (v >> 16) & 0xFFFF); }

/* Writes `count` parts to `path`. `bad_crc` is the index of a part whose
 * recorded checksum is to be WRONG, or -1 for none. Returns 1 on success. */
static int tz_write(const char *path, const TzPart *parts, int count, int bad_crc)
{
    uint32_t offsets[64], crcs[64];
    FILE *f = fopen(path, "wb");
    if (!f || count > 64) { if (f) fclose(f); return 0; }
    for (int i = 0; i < count; i++) {
        size_t name_len = strlen(parts[i].name);
        offsets[i] = (uint32_t)ftell(f);
        crcs[i] = tz_crc((const unsigned char *)parts[i].data, parts[i].size) ^ (i == bad_crc ? 0x5A5A5A5Au : 0);
        tz_u32(f, 0x04034b50u); tz_u16(f, 20); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0x21);
        tz_u32(f, crcs[i]); tz_u32(f, (uint32_t)parts[i].size); tz_u32(f, (uint32_t)parts[i].size);
        tz_u16(f, (unsigned)name_len); tz_u16(f, 0);
        fwrite(parts[i].name, 1, name_len, f);
        fwrite(parts[i].data, 1, parts[i].size, f);
    }
    uint32_t directory = (uint32_t)ftell(f);
    for (int i = 0; i < count; i++) {
        size_t name_len = strlen(parts[i].name);
        tz_u32(f, 0x02014b50u); tz_u16(f, 20); tz_u16(f, 20); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0x21);
        tz_u32(f, crcs[i]); tz_u32(f, (uint32_t)parts[i].size); tz_u32(f, (uint32_t)parts[i].size);
        tz_u16(f, (unsigned)name_len); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, 0); tz_u32(f, 0);
        tz_u32(f, offsets[i]);
        fwrite(parts[i].name, 1, name_len, f);
    }
    uint32_t end = (uint32_t)ftell(f);
    tz_u32(f, 0x06054b50u); tz_u16(f, 0); tz_u16(f, 0); tz_u16(f, (unsigned)count); tz_u16(f, (unsigned)count);
    tz_u32(f, end - directory); tz_u32(f, directory); tz_u16(f, 0);
    return fclose(f) == 0;
}

/* The three parts every workbook has, for a file with ONE sheet at the usual
 * place. A test adds the sheet itself and whatever else it is about. */
#define TZ_RELS                                                                                     \
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"                              \
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"      \
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/"     \
    "relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
#define TZ_WORKBOOK                                                                                 \
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"                              \
    "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "              \
    "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"            \
    "<sheets><sheet name=\"Data\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
#define TZ_WORKBOOK_RELS                                                                            \
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"                              \
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"      \
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/"     \
    "relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>"                                \
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/"     \
    "relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"                                \
    "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/"     \
    "relationships/styles\" Target=\"styles.xml\"/></Relationships>"
#define TZ_SHEET_OPEN                                                                               \
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"                              \
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
#define TZ_SHEET_CLOSE "</sheetData></worksheet>"

/* A one-sheet workbook around the given sheet XML (and, when not NULL, a
 * shared-strings and a styles part). */
static int tz_workbook(const char *path, const char *sheet_xml, const char *strings_xml, const char *styles_xml)
{
    TzPart parts[6];
    int n = 0;
    parts[n].name = "_rels/.rels"; parts[n].data = TZ_RELS; parts[n].size = strlen(TZ_RELS); n++;
    parts[n].name = "xl/workbook.xml"; parts[n].data = TZ_WORKBOOK; parts[n].size = strlen(TZ_WORKBOOK); n++;
    parts[n].name = "xl/_rels/workbook.xml.rels"; parts[n].data = TZ_WORKBOOK_RELS; parts[n].size = strlen(TZ_WORKBOOK_RELS); n++;
    parts[n].name = "xl/worksheets/sheet1.xml"; parts[n].data = sheet_xml; parts[n].size = strlen(sheet_xml); n++;
    if (strings_xml) { parts[n].name = "xl/sharedStrings.xml"; parts[n].data = strings_xml; parts[n].size = strlen(strings_xml); n++; }
    if (styles_xml) { parts[n].name = "xl/styles.xml"; parts[n].data = styles_xml; parts[n].size = strlen(styles_xml); n++; }
    return tz_write(path, parts, n, -1);
}

/* The smallest PNG there is: one transparent pixel. */
static const unsigned char k_tz_png[] = {
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82};

static int tz_png(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    fwrite(k_tz_png, 1, sizeof k_tz_png, f);
    return fclose(f) == 0;
}

#endif
