#ifndef CFOURDWINDOWS_H
#define CFOURDWINDOWS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Decodes the first frame of a raster image with Windows Imaging Component,
/// applies EXIF orientation, downsamples so neither side exceeds
/// `maxPixelSize`, and encodes 32-bit BGRA PNG. Returns 0 on success, 1 for an
/// undecodable image, 2 when the source exceeds `maxSourcePixels`, and 3 when
/// encoding fails. The caller releases `*png` with `fdw_free`.
int32_t fdw_image_to_png(const uint8_t *bytes, size_t length, uint32_t maxPixelSize, double maxSourcePixels,
                         uint8_t **png, size_t *pngLength, uint32_t *sourceWidth, uint32_t *sourceHeight);
void fdw_free(void *pointer);

/// A DirectWrite text format bound to an installed family, weight and style.
typedef struct FDWFont FDWFont;

typedef struct FDWFontMetrics {
    double ascent;
    double descent;
    double lineGap;
    double capHeight;
    double xHeight;
} FDWFontMetrics;

/// Returns 1 when `family` (UTF-16, NUL-terminated) is an installed family name.
int32_t fdw_font_family_exists(const uint16_t *family);
/// Creates a font for an installed family; returns NULL when it is unavailable.
FDWFont *fdw_font_create(const uint16_t *family, double size, int32_t bold, int32_t italic);
void fdw_font_release(FDWFont *font);
void fdw_font_metrics(const FDWFont *font, FDWFontMetrics *metrics);
/// Natural-mode advance width including trailing whitespace.
double fdw_text_width(const FDWFont *font, const uint16_t *text, uint32_t length);
/// UTF-16 units that fit on the first line of `text` wrapped at `width`,
/// including trailing whitespace and the hard line break. Returns 0 only for empty text.
uint32_t fdw_suggest_line_break(const FDWFont *font, const uint16_t *text, uint32_t length, double width);

#ifdef __cplusplus
}
#endif

#endif
