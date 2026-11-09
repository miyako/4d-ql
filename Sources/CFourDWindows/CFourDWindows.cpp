#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <wincodec.h>
#include <dwrite.h>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#include "CFourDWindows.h"

namespace {

template <class T> struct Ref {
    T *p = nullptr;
    Ref() = default;
    Ref(const Ref &) = delete;
    Ref &operator=(const Ref &) = delete;
    ~Ref() { if (p) p->Release(); }
    T **out() { if (p) { p->Release(); p = nullptr; } return &p; }
    T *operator->() const { return p; }
    explicit operator bool() const { return p != nullptr; }
};

struct ComScope {
    bool owned;
    ComScope() {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        // RPC_E_CHANGED_MODE: the caller's apartment is already usable for WIC.
        owned = SUCCEEDED(hr);
    }
    ~ComScope() { if (owned) CoUninitialize(); }
};

IDWriteFactory *writeFactory() {
    static IDWriteFactory *factory = nullptr;
    static std::once_flag once;
    std::call_once(once, [] {
        DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                            reinterpret_cast<IUnknown **>(&factory));
    });
    return factory;
}

IDWriteFontCollection *systemFonts() {
    static IDWriteFontCollection *collection = nullptr;
    static std::once_flag once;
    std::call_once(once, [] {
        if (IDWriteFactory *factory = writeFactory()) factory->GetSystemFontCollection(&collection, FALSE);
    });
    return collection;
}

bool orientation(IWICBitmapFrameDecode *frame, WICBitmapTransformOptions *transform) {
    Ref<IWICMetadataQueryReader> reader;
    if (FAILED(frame->GetMetadataQueryReader(reader.out()))) return false;
    const wchar_t *queries[] = { L"/app1/ifd/{ushort=274}", L"/ifd/{ushort=274}" };
    for (const wchar_t *query : queries) {
        PROPVARIANT value;
        PropVariantInit(&value);
        if (SUCCEEDED(reader->GetMetadataByName(query, &value)) && value.vt == VT_UI2) {
            USHORT code = value.uiVal;
            PropVariantClear(&value);
            switch (code) {
            case 2: *transform = WICBitmapTransformFlipHorizontal; return true;
            case 3: *transform = WICBitmapTransformRotate180; return true;
            case 4: *transform = WICBitmapTransformFlipVertical; return true;
            case 5: *transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal); return true;
            case 6: *transform = WICBitmapTransformRotate90; return true;
            case 7: *transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal); return true;
            case 8: *transform = WICBitmapTransformRotate270; return true;
            default: return false;
            }
        }
        PropVariantClear(&value);
    }
    return false;
}

} // namespace

struct FDWFont {
    IDWriteTextFormat *format;
    FDWFontMetrics metrics;
};

extern "C" {

int32_t fdw_image_to_png(const uint8_t *bytes, size_t length, uint32_t maxPixelSize, double maxSourcePixels,
                         uint8_t **png, size_t *pngLength, uint32_t *sourceWidth, uint32_t *sourceHeight) {
    *png = nullptr;
    *pngLength = 0;
    if (!bytes || length == 0 || length > 0xFFFFFFFFu || maxPixelSize == 0) return 1;
    ComScope com;
    Ref<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(factory.out())))) return 1;
    Ref<IWICStream> input;
    if (FAILED(factory->CreateStream(input.out()))
        || FAILED(input->InitializeFromMemory(const_cast<BYTE *>(bytes), static_cast<DWORD>(length)))) return 1;
    Ref<IWICBitmapDecoder> decoder;
    if (FAILED(factory->CreateDecoderFromStream(input.p, nullptr, WICDecodeMetadataCacheOnDemand, decoder.out()))) return 1;
    Ref<IWICBitmapFrameDecode> frame;
    if (FAILED(decoder->GetFrame(0, frame.out()))) return 1;
    UINT width = 0, height = 0;
    if (FAILED(frame->GetSize(&width, &height)) || width == 0 || height == 0) return 1;
    *sourceWidth = width;
    *sourceHeight = height;
    if (static_cast<double>(width) * static_cast<double>(height) > maxSourcePixels) return 2;

    Ref<IWICFormatConverter> converted;
    if (FAILED(factory->CreateFormatConverter(converted.out()))
        || FAILED(converted->Initialize(frame.p, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
                                        nullptr, 0, WICBitmapPaletteTypeMedianCut))) return 1;
    IWICBitmapSource *current = converted.p;

    Ref<IWICBitmapScaler> scaler;
    UINT longest = width > height ? width : height;
    if (longest > maxPixelSize) {
        double scale = static_cast<double>(maxPixelSize) / static_cast<double>(longest);
        UINT scaledWidth = static_cast<UINT>(std::lround(width * scale));
        UINT scaledHeight = static_cast<UINT>(std::lround(height * scale));
        if (scaledWidth == 0) scaledWidth = 1;
        if (scaledHeight == 0) scaledHeight = 1;
        if (FAILED(factory->CreateBitmapScaler(scaler.out()))
            || FAILED(scaler->Initialize(current, scaledWidth, scaledHeight, WICBitmapInterpolationModeHighQualityCubic))) return 1;
        current = scaler.p;
    }

    Ref<IWICBitmapFlipRotator> rotator;
    WICBitmapTransformOptions transform = WICBitmapTransformRotate0;
    if (orientation(frame.p, &transform)) {
        if (FAILED(factory->CreateBitmapFlipRotator(rotator.out()))
            || FAILED(rotator->Initialize(current, transform))) return 1;
        current = rotator.p;
    }

    // Materialize once: the flip rotator cannot stream rows to the encoder.
    Ref<IWICBitmap> bitmap;
    if (FAILED(factory->CreateBitmapFromSource(current, WICBitmapCacheOnLoad, bitmap.out()))) return 3;
    UINT outWidth = 0, outHeight = 0;
    if (FAILED(bitmap->GetSize(&outWidth, &outHeight))) return 3;

    Ref<IStream> output;
    if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, output.out()))) return 3;
    Ref<IWICBitmapEncoder> encoder;
    if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.out()))
        || FAILED(encoder->Initialize(output.p, WICBitmapEncoderNoCache))) return 3;
    Ref<IWICBitmapFrameEncode> target;
    if (FAILED(encoder->CreateNewFrame(target.out(), nullptr)) || FAILED(target->Initialize(nullptr))
        || FAILED(target->SetSize(outWidth, outHeight))) return 3;
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    if (FAILED(target->SetPixelFormat(&format)) || !IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA)
        || FAILED(target->WriteSource(bitmap.p, nullptr)) || FAILED(target->Commit()) || FAILED(encoder->Commit())) return 3;

    STATSTG stat = {};
    if (FAILED(output->Stat(&stat, STATFLAG_NONAME)) || stat.cbSize.QuadPart > 0x7FFFFFFF) return 3;
    size_t size = static_cast<size_t>(stat.cbSize.QuadPart);
    uint8_t *buffer = static_cast<uint8_t *>(std::malloc(size ? size : 1));
    if (!buffer) return 3;
    LARGE_INTEGER zero = {};
    ULONG read = 0;
    if (FAILED(output->Seek(zero, STREAM_SEEK_SET, nullptr))
        || FAILED(output->Read(buffer, static_cast<ULONG>(size), &read)) || read != size) {
        std::free(buffer);
        return 3;
    }
    *png = buffer;
    *pngLength = size;
    return 0;
}

void fdw_free(void *pointer) { std::free(pointer); }

int32_t fdw_font_family_exists(const uint16_t *family) {
    IDWriteFontCollection *collection = systemFonts();
    if (!collection || !family) return 0;
    UINT32 index = 0;
    BOOL exists = FALSE;
    return SUCCEEDED(collection->FindFamilyName(reinterpret_cast<const wchar_t *>(family), &index, &exists)) && exists ? 1 : 0;
}

FDWFont *fdw_font_create(const uint16_t *family, double size, int32_t bold, int32_t italic) {
    IDWriteFactory *factory = writeFactory();
    IDWriteFontCollection *collection = systemFonts();
    if (!factory || !collection || !family || !(size > 0)) return nullptr;
    const wchar_t *name = reinterpret_cast<const wchar_t *>(family);
    UINT32 index = 0;
    BOOL exists = FALSE;
    if (FAILED(collection->FindFamilyName(name, &index, &exists)) || !exists) return nullptr;
    Ref<IDWriteFontFamily> fontFamily;
    if (FAILED(collection->GetFontFamily(index, fontFamily.out()))) return nullptr;
    DWRITE_FONT_WEIGHT weight = bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL;
    DWRITE_FONT_STYLE style = italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL;
    Ref<IDWriteFont> font;
    if (FAILED(fontFamily->GetFirstMatchingFont(weight, DWRITE_FONT_STRETCH_NORMAL, style, font.out()))) return nullptr;
    DWRITE_FONT_METRICS design = {};
    font->GetMetrics(&design);
    if (design.designUnitsPerEm == 0) return nullptr;
    IDWriteTextFormat *format = nullptr;
    if (FAILED(factory->CreateTextFormat(name, collection, weight, style, DWRITE_FONT_STRETCH_NORMAL,
                                         static_cast<FLOAT>(size), L"en-us", &format))) return nullptr;
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    FDWFont *result = new FDWFont();
    result->format = format;
    double scale = size / design.designUnitsPerEm;
    result->metrics.ascent = design.ascent * scale;
    result->metrics.descent = design.descent * scale;
    result->metrics.lineGap = design.lineGap * scale;
    result->metrics.capHeight = design.capHeight * scale;
    result->metrics.xHeight = design.xHeight * scale;
    return result;
}

void fdw_font_release(FDWFont *font) {
    if (!font) return;
    font->format->Release();
    delete font;
}

void fdw_font_metrics(const FDWFont *font, FDWFontMetrics *metrics) { *metrics = font->metrics; }

double fdw_text_width(const FDWFont *font, const uint16_t *text, uint32_t length) {
    if (!font || length == 0) return 0;
    Ref<IDWriteTextLayout> layout;
    if (FAILED(writeFactory()->CreateTextLayout(reinterpret_cast<const wchar_t *>(text), length, font->format,
                                                1.0e7f, 1.0e7f, layout.out()))) return 0;
    layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    DWRITE_TEXT_METRICS metrics = {};
    if (FAILED(layout->GetMetrics(&metrics))) return 0;
    return metrics.widthIncludingTrailingWhitespace;
}

uint32_t fdw_suggest_line_break(const FDWFont *font, const uint16_t *text, uint32_t length, double width) {
    if (!font || length == 0) return 0;
    Ref<IDWriteTextLayout> layout;
    FLOAT limit = static_cast<FLOAT>(width > 0 ? width : 0);
    if (FAILED(writeFactory()->CreateTextLayout(reinterpret_cast<const wchar_t *>(text), length, font->format,
                                                limit, 1.0e7f, layout.out()))) return length;
    UINT32 count = 0;
    layout->GetLineMetrics(nullptr, 0, &count);
    if (count == 0) return length;
    std::vector<DWRITE_LINE_METRICS> lines(count);
    if (FAILED(layout->GetLineMetrics(lines.data(), count, &count)) || count == 0) return length;
    UINT32 first = lines[0].length;
    return first == 0 ? 1 : first;
}

} // extern "C"

#endif
