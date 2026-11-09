import Foundation
import FourDFileKit

struct FormPreviewRenderer {
    /// Platform whose fonts and families measure text; matches the rendered themes.
    var platform: FormPlatform = .macOS

    static let supported: Set<String> = ["text", "input", "button", "checkbox", "radio", "dropdown", "combo", "groupBox", "tab",
                                          "line", "rectangle", "oval", "picture", "listbox", "splitter", "progress", "ruler",
                                          "spinner", "stepper", "list", "buttonGrid", "pictureButton", "picturePopup"]

    static func diagnostics(_ form: FormFileInfo) -> [String] {
        var objects = form.appearances.flatMap(\.pages).flatMap(\.objects)
        var cursor = 0
        while cursor < objects.count && objects.count < 4_000 {
            objects.append(contentsOf: objects[cursor].children.prefix(4_000 - objects.count))
            cursor += 1
        }
        var notices: [String] = []
        let placeholders = Set(objects.filter {
            !supported.contains($0.type) && !($0.type == "subform" && $0.embeddedProperties != nil)
        }.map(\.type)).sorted()
        if !placeholders.isEmpty { notices.append("Placeholder only: \(placeholders.joined(separator: ", ")). Dynamic or unavailable subforms, web content, plug-ins, Write Pro and View Pro are not executed.") }
        if objects.contains(where: { !validGeometry($0.properties) }) { notices.append("Objects with invalid or out-of-range coordinates are omitted (coordinate limit: 32,768 points).") }
        if objects.contains(where: { object in
            ["text", "dataSource"].contains { (object.properties[$0]?.string?.utf16.count ?? 0) > 4_096 }
        }) {
            notices.append("Long form text is clipped to 4,096 UTF-16 units without splitting composed characters.")
        }
        if objects.contains(where: { object in
            guard ["text", "input"].contains(object.type) else { return false }
            let p = object.properties
            let theme: FormTheme = form.platform == .windows ? .windowsClassic : .glassLight
            let size = Self(platform: form.platform).font(p, height: bounds(p, theme: theme).h, theme: theme)
            return ["paddingLeft", "paddingRight", "paddingTop", "paddingBottom"].contains { key in
                guard let value = p[key] else { return false }
                guard let length = Self.length(value, size: size) else { return true }
                return length < 0 || length > 8_192
            }
        }) {
            notices.append("Invalid text padding is ignored; padding outside 0-8,192 points is limited to that range.")
        }
        if form.appearances.contains(where: { canvas($0, properties: form.properties).clipped }) { notices.append("Large form canvas cropped to 8,192 × 8,192 points.") }
        return notices
    }

    func render(_ preview: FormPreview) -> String {
        let platforms = Self.platforms(preview)
        if platforms.count > 1 { return renderPlatforms(preview, platforms: platforms) }
        return render(preview, themeGroup: "form-theme", images: true)
    }

    static func platforms(_ preview: FormPreview) -> [FormPlatform] {
        preview.appearances.reduce(into: []) { if !$0.contains($1.theme.platform) { $0.append($1.theme.platform) } }
    }

    /// Whether the preview embeds the Segoe UI substitute (and needs `font-src data:`).
    static func embedsSubstituteFont(_ preview: FormPreview) -> Bool {
        FormSubstituteFont.isNeeded && preview.appearances.contains { $0.theme.platform == .windows }
    }

    /// One preview per platform behind a CSS-only platform switch; each keeps
    /// its own theme radio group and the images are defined once.
    private func renderPlatforms(_ preview: FormPreview, platforms: [FormPlatform]) -> String {
        let selected = preview.initialTheme?.platform ?? preview.platform
        var html = "<style>\(Self.platformCSS)</style><div class=\"form-platforms\">" + imageDefinitions(preview.images)
        for platform in platforms {
            html += "<input class=\"platform-choice\" type=\"radio\" name=\"form-platform\" id=\"platform-\(platform.rawValue)\"\(platform == selected ? " checked" : "")>"
        }
        html += "<div class=\"form-platform-tabs\" role=\"group\" aria-label=\"Platform\">"
        html += platforms.map { "<label for=\"platform-\($0.rawValue)\">\(esc($0.label))</label>" }.joined()
        html += "</div>"
        var selectors = ""
        for platform in platforms {
            var single = preview
            single.platform = platform
            single.appearances = preview.appearances.filter { $0.theme.platform == platform }
            if single.initialTheme?.platform != platform { single.initialTheme = nil }
            html += "<div class=\"form-platform\" data-platform=\"\(platform.rawValue)\">"
            html += Self(platform: platform).render(single, themeGroup: "form-theme-\(platform.rawValue)", images: false)
            html += "</div>"
            selectors += "#platform-\(platform.rawValue):checked ~ .form-platform[data-platform=\"\(platform.rawValue)\"]{display:block}"
            selectors += "#platform-\(platform.rawValue):checked ~ .form-platform-tabs label[for=\"platform-\(platform.rawValue)\"]{background:var(--accent);border-color:var(--accent);color:white}"
        }
        return html + "</div><style>\(selectors)</style>"
    }

    private func imageDefinitions(_ images: [FormImage]) -> String {
        var html = "<svg width=\"0\" height=\"0\" aria-hidden=\"true\" style=\"position:absolute\"><defs>"
        for image in images {
            html += "<image id=\"\(image.id)\" width=\"\(n(image.width))\" height=\"\(n(image.height))\" href=\"\(image.dataURI)\"/>"
        }
        return html + "</defs></svg>"
    }

    private func render(_ preview: FormPreview, themeGroup: String, images: Bool) -> String {
        guard platform == preview.platform else {
            return Self(platform: preview.platform).render(preview, themeGroup: themeGroup, images: images)
        }
        let windows = platform == .windows
        let defaultGlass = !windows && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        var css = Self.css
        if windows {
            css += "\n" + FormPlatformStyle.windowsCSS
            if FormSubstituteFont.isNeeded { css += "\n" + FormSubstituteFont.css }
        }
        var html = "<style>\(css)</style><div class=\"form-preview\">"
        if images { html += imageDefinitions(preview.images) }
        let fixedScheme = preview.properties["colorScheme"]?.string
        let variants = preview.appearances.filter { fixedScheme == nil || $0.theme.dark == (fixedScheme == "dark") }
        // Windows selection never depends on prefers-color-scheme: exactly one theme radio is checked.
        let windowsDefault = windows ? (preview.initialTheme ?? Self.windowsDefaultTheme(variants.map(\.theme), properties: preview.properties)) : nil
        for appearance in variants {
            let selected = windows ? appearance.theme == windowsDefault
                : preview.initialTheme.map { $0 == appearance.theme }
                ?? (appearance.theme.glass == defaultGlass && fixedScheme != nil)
            let checked = selected ? " checked" : ""
            // Two checked defaults, one per system color scheme, are selected by CSS.
            let defaultClass = !windows && appearance.theme.glass == defaultGlass ? (appearance.theme.dark ? " default-dark" : " default-light") : ""
            html += "<input class=\"theme-choice\(defaultClass)\" type=\"radio\" name=\"\(themeGroup)\" id=\"theme-\(appearance.theme.rawValue)\"\(checked)>"
        }
        html += "<div class=\"form-themes\" role=\"group\" aria-label=\"\(FormPlatformStyle(platform).appearanceLabel)\">"
        html += variants.map { "<label for=\"theme-\($0.theme.rawValue)\">\(esc($0.theme.label))</label>" }.joined()
        html += "</div>"
        for appearance in variants {
            let theme = appearance.theme
            let size = Self.canvas(appearance, properties: preview.properties)
            html += "<div class=\"form-appearance \(FormPlatformStyle.classes(theme))\" data-theme=\"\(theme.rawValue)\">"
            let initialPage = preview.initialPage
                ?? (appearance.pages.contains { $0.number == 1 } ? 1 : appearance.pages.first?.number ?? 0)
            for page in appearance.pages {
                html += "<input class=\"page-choice\" type=\"radio\" name=\"page-\(theme.rawValue)\" id=\"page-\(theme.rawValue)-\(page.number)\"\(page.number == initialPage ? " checked" : "")>"
            }
            if appearance.pages.count >= 2 {
                html += "<div class=\"form-pages\" role=\"group\" aria-label=\"Form page\">"
                html += appearance.pages.map { "<label for=\"page-\(theme.rawValue)-\($0.number)\">Page \($0.number)</label>" }.joined()
                html += "</div>"
            }
            for page in appearance.pages {
                let common = appearance.pages.first?.objects ?? []
                let objects = page.number == 0 ? page.objects : common + page.objects
                html += "<div class=\"form-page\" data-page=\"\(page.number)\"><div class=\"form-scroll\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(size.width))\" height=\"\(n(size.height))\" viewBox=\"0 0 \(n(size.width)) \(n(size.height))\" role=\"img\" aria-label=\"\(esc(preview.name)), page \(page.number), \(esc(theme.label))\">"
                html += "<rect width=\"100%\" height=\"100%\" fill=\"var(--form-bg)\"/>"
                for (index, object) in objects.enumerated() {
                    html += draw(object, theme: theme, images: preview.images,
                                 id: "\(theme.rawValue)-\(page.number)-\(index)")
                }
                html += "</svg></div><div class=\"form-caption\">Page \(page.number) · \(n(size.width)) × \(n(size.height)) pt"
                if let fixedScheme { html += " · Form forces \(esc(fixedScheme))" }
                html += "</div></div>"
            }
            html += "</div>"
        }
        html += "</div>"
        var selectors = ""
        if fixedScheme == nil && !windows {
            let light = variants.first { $0.theme.glass == defaultGlass && !$0.theme.dark }?.theme.rawValue ?? "classicLight"
            let dark = variants.first { $0.theme.glass == defaultGlass && $0.theme.dark }?.theme.rawValue ?? "classicDark"
            selectors += ".form-appearance[data-theme=\"\(light)\"]{display:block}"
            selectors += ".form-themes label[for=\"theme-\(light)\"]{background:var(--accent);color:white}"
            selectors += "@media(prefers-color-scheme:dark){.form-appearance[data-theme=\"\(light)\"]{display:none}.form-appearance[data-theme=\"\(dark)\"]{display:block}.form-themes label[for=\"theme-\(light)\"]{background:transparent;color:inherit}.form-themes label[for=\"theme-\(dark)\"]{background:var(--accent);color:white}}"
            selectors += ".theme-choice:checked ~ .form-appearance{display:none}.theme-choice:checked ~ .form-themes label{background:transparent;color:inherit}"
        }
        for appearance in variants {
            let theme = appearance.theme.rawValue
            selectors += "#theme-\(theme):checked ~ .form-appearance[data-theme=\"\(theme)\"]{display:block}"
            selectors += "#theme-\(theme):checked ~ .form-themes label[for=\"theme-\(theme)\"]{background:var(--accent);color:white}"
            for page in appearance.pages {
                selectors += "#page-\(theme)-\(page.number):checked ~ .form-page[data-page=\"\(page.number)\"]{display:block}"
                selectors += "#page-\(theme)-\(page.number):checked ~ .form-pages label[for=\"page-\(theme)-\(page.number)\"]{background:var(--accent);color:white}"
            }
        }
        return html + "<style>\(selectors)</style>"
    }

    /// 4D shows Windows Classic unless the form opts into Fluent UI.
    static func windowsDefaultTheme(_ themes: [FormTheme], properties: FormValue) -> FormTheme? {
        let preferred: [FormTheme] = properties["fluentUI"]?.bool == true
            ? [.fluentLight, .fluentDark, .windowsClassic] : [.windowsClassic, .fluentLight, .fluentDark]
        return preferred.first(where: themes.contains) ?? themes.first
    }

    private static func validGeometry(_ properties: FormValue) -> Bool {
        guard let x = properties["left"]?.double, let y = properties["top"]?.double else { return false }
        let keys = ["left", "top", "width", "height", "right", "bottom"]
        if keys.contains(where: { properties[$0] != nil && properties[$0]?.double == nil }) { return false }
        let values = keys.compactMap { properties[$0]?.double }
        return x.isFinite && y.isFinite && values.allSatisfy { $0.isFinite && abs($0) <= 32_768 }
            && (properties["width"]?.double ?? 0) >= 0 && (properties["height"]?.double ?? 0) >= 0
    }

    private static func bounds(_ properties: FormValue, theme: FormTheme) -> (x: Double, y: Double, w: Double, h: Double) {
        let x = properties["left"]?.double ?? 0
        let y = properties["top"]?.double ?? 0
        let w = properties["width"]?.double ?? properties["right"]?.double.map { $0 - x } ?? 100
        let type = properties["type"]?.string ?? ""
        let defaultHeight: Double = theme.platform == .windows
            ? (["button", "dropdown"].contains(type) ? FormPlatformStyle.windowsDefaultControlHeight(theme) : 20)
            : theme.glass && ["checkbox", "radio"].contains(type) ? 16 : 20
        let h = properties["height"]?.double ?? properties["bottom"]?.double.map { $0 - y } ?? defaultHeight
        return (x, y, max(0, w), max(0, h))
    }

    private static func canvas(_ appearance: FormAppearance, properties: FormValue) -> (width: Double, height: Double, clipped: Bool) {
        let objects = appearance.pages.flatMap(\.objects).filter { validGeometry($0.properties) }
        let anchor = properties["formSizeAnchor"]?.string.flatMap { name in objects.first { $0.name == name } }
        let rectangles = (anchor.map { [$0] } ?? objects).map { bounds($0.properties, theme: appearance.theme) }
        let width = properties["width"]?.double ?? (rectangles.map { $0.x + $0.w }.max() ?? 300) + (properties["rightMargin"]?.double ?? 20)
        let height = properties["height"]?.double ?? (rectangles.map { $0.y + $0.h }.max() ?? 200) + (properties["bottomMargin"]?.double ?? 20)
        return (max(1, min(8_192, width)), max(1, min(8_192, height)), width > 8_192 || height > 8_192)
    }

    private func draw(_ object: FormObject, theme: FormTheme, images: [FormImage], id: String, depth: Int = 0) -> String {
        let p = object.properties
        guard depth < 64, Self.validGeometry(p), p["visibility"]?.string != "hidden", p["display"]?.bool != false else { return "" }
        let b = Self.bounds(p, theme: theme)
        let nativeStyle = p["style"]?.string ?? "regular"
        let quantized = theme.glass && (object.type == "dropdown" || object.type == "button" && nativeStyle == "regular")
        let w = b.w, h = quantized ? Self.nativeControlHeight(b.h) : b.h
        let label = p["text"]?.string ?? p["dataSource"]?.string ?? "\"\(object.name)\""
        let stroke = color(p["stroke"]?.string, fallback: "var(--form-ink)")
        let fill = color(p["fill"]?.string, fallback: "transparent")
        let border = p["borderStyle"]?.string ?? "system"
        let fontSize = font(p, height: b.h, theme: theme)
        let tip = "\(object.name) · \(object.type)" + (p["dataSource"]?.string.map { "\n\($0)" } ?? "")
        var svg = "<g transform=\"translate(\(n(b.x)) \(n(b.y)))\"><title>\(esc(tip))</title>"
        let clip = "form-clip-\(id)"
        svg += "<defs><clipPath id=\"\(clip)\"><rect width=\"\(n(w))\" height=\"\(n(h))\"/></clipPath></defs>"
        func text(_ value: String, x: Double = 0, y: Double = 0, width: Double? = nil, height: Double? = nil, center: Bool = false, ink: String? = nil) -> String {
            self.text(value, p: p, x: x, y: y, width: width ?? w, height: height ?? h,
                      size: fontSize, center: center, ink: ink ?? stroke)
        }
        func rect(_ background: String, radius: Double = 0, outline: String = "var(--form-border)", inset: Double = 0) -> String {
            "<rect x=\"\(n(inset))\" y=\"\(n(inset))\" width=\"\(n(max(0,w-2*inset)))\" height=\"\(n(max(0,h-2*inset)))\" rx=\"\(n(radius))\" fill=\"\(background)\" stroke=\"\(outline)\" stroke-width=\"1\"/>"
        }
        func image(_ property: String, x: Double = 0, y: Double = 0, width: Double? = nil, height: Double? = nil, format: String = "scaled") -> String {
            guard let key = object.images[property], let asset = images.first(where: { $0.id == key }) else { return "" }
            let columns = property == "picture" && ["pictureButton", "picturePopup"].contains(object.type) ? max(1,min(256,p["columnCount"]?.double ?? 1)) : 1
            let rows = property == "icon" ? max(1,min(256,p["iconFrames"]?.double ?? 1))
                : property == "picture" && ["pictureButton", "picturePopup"].contains(object.type) ? max(1,min(256,p["rowCount"]?.double ?? 1)) : 1
            return self.image(asset, x: x, y: y, w: width ?? w, h: height ?? h, format: format, id: id + property,
                              sourceWidth: asset.width/columns, sourceHeight: asset.height/rows)
        }
        func iconCaption(_ label: String, x: Double = 0, width: Double? = nil, center: Bool = true, ink: String? = nil) -> String {
            let width = width ?? w
            guard let key = object.images["icon"], let asset = images.first(where: { $0.id == key }) else {
                return text(label, x: x, width: width, center: center, ink: ink)
            }
            let frames = max(1,min(256,p["iconFrames"]?.double ?? 1))
            let sourceHeight = asset.height/frames
            let placement = p["textPlacement"]?.string ?? "bottom"
            let lineHeight = FormTextLayout(text: label, width: width, size: fontSize, properties: p, maxLines: 1, platform: platform).lineHeight
            let stacked = placement == "top" || placement == "bottom"
            let gap: Double = label.isEmpty ? 0 : stacked ? 8 : 6
            let availableHeight = stacked ? max(0,h-(label.isEmpty ? 0 : lineHeight)-gap) : h
            let scale = min(1,max(0,width-12)/asset.width,max(0,availableHeight-4)/sourceHeight)
            let iw = asset.width*scale, ih = sourceHeight*scale
            if label.isEmpty {
                return image("icon", x: x+(width-iw)/2, y: (h-ih)/2, width: iw, height: ih, format: "proportionalCenter")
            }
            if stacked {
                let top = max(0,(h-ih-lineHeight-gap)/2)
                let iconY = placement == "bottom" ? top : top+lineHeight+gap
                let textY = placement == "bottom" ? top+ih+gap : top
                return image("icon", x: x+(width-iw)/2, y: iconY, width: iw, height: ih, format: "proportionalCenter")
                    + text(label, x: x, y: textY, width: width, height: lineHeight, center: true, ink: ink)
            }
            if placement == "center" {
                return image("icon", x: x+(width-iw)/2, y: (h-ih)/2, width: iw, height: ih, format: "proportionalCenter")
                    + text(label, x: x, width: width, center: true, ink: ink)
            }
            let captionWidth = min(max(0,width-iw-gap-12),measure(label,size:fontSize,p:p)+4)
            let hugs = p["imageHugsTitle"]?.bool == true
            let alignment = p["textAlign"]?.string ?? "center"
            let blockWidth = iw+gap+captionWidth
            let start = hugs ? (alignment == "left" ? 6 : alignment == "right" ? width-blockWidth-6 : (width-blockWidth)/2) : 6
            let iconX = placement == "left" ? (hugs ? start+captionWidth+gap : width-iw-6) : start
            let textX = hugs ? (placement == "left" ? start : start+iw+gap)
                : alignment == "center" || alignment == "automatic" ? 0 : placement == "left" ? 6 : iw+gap+6
            let textWidth = hugs ? captionWidth : alignment == "center" || alignment == "automatic" ? width : max(0,width-iw-gap-12)
            return image("icon", x: x+iconX, y: (h-ih)/2, width: iw, height: ih, format: "proportionalCenter")
                + text(label, x: x+textX, width: textWidth, center: true, ink: ink)
        }
        switch object.type {
        case _ where ["button", "dropdown"].contains(object.type) && theme.platform == .windows && (object.type == "dropdown" || ["regular", "flat"].contains(nativeStyle)):
            let popup = object.type == "dropdown"
            let defaultButton = !popup && p["defaultButton"]?.bool == true
            let accentFill = defaultButton && theme.fluent
            let radius = min(FormPlatformStyle.windowsControlRadius(theme), h/2)
            let background = accentFill ? "var(--form-accent)" : popup ? "var(--form-popup)"
                : nativeStyle == "flat" ? color(p["fill"]?.string, fallback: "var(--form-control)") : "var(--form-control)"
            let outline = defaultButton ? "var(--form-accent)" : "var(--form-border)"
            svg += "<rect x=\"0.5\" y=\"0.5\" width=\"\(n(max(0,w-1)))\" height=\"\(n(max(0,h-1)))\" rx=\"\(n(radius))\" fill=\"\(background)\" stroke=\"\(outline)\" stroke-width=\"1\"/>"
            if !defaultButton && w > 2*radius+1 {
                svg += "<path d=\"M\(n(radius+0.5)) \(n(h-0.5))H\(n(w-radius-0.5))\" stroke=\"var(--form-control-edge)\"/>"
            }
            let chevronInset: Double = theme.fluent ? 15 : 9
            let captionInset: Double = theme.fluent ? 11 : 4
            svg += "<g clip-path=\"url(#\(clip))\">" + iconCaption(label, x: popup ? captionInset : 0,
                           width: max(0,w-(popup ? captionInset+chevronInset+8 : 0)), center: !popup,
                           ink: accentFill && (p["stroke"] == nil || p["stroke"]?.string == "automatic") ? "var(--form-accent-ink)" : stroke) + "</g>"
            if popup || p["popupPlacement"]?.string.map({ $0 != "none" }) == true {
                svg += chevrons(x: w - chevronInset, y: h/2, both: false, ink: "var(--form-ink)")
            }
        case _ where ["checkbox", "radio"].contains(object.type) && theme.platform == .windows && ["regular", "flat"].contains(nativeStyle):
            let side = FormPlatformStyle.windowsToggleSide(theme)
            let gap = FormPlatformStyle.windowsToggleGap(theme)
            svg += "<g clip-path=\"url(#\(clip))\">"
            if object.type == "radio" {
                svg += "<circle cx=\"\(n(side/2))\" cy=\"\(n(h/2))\" r=\"\(n(side/2-0.5))\" fill=\"var(--form-toggle)\" stroke=\"var(--form-toggle-border)\"/>"
            } else {
                svg += "<rect x=\"0.5\" y=\"\(n((h-side)/2+0.5))\" width=\"\(n(side-1))\" height=\"\(n(side-1))\" rx=\"\(n(FormPlatformStyle.windowsControlRadius(theme)))\" fill=\"var(--form-toggle)\" stroke=\"var(--form-toggle-border)\"/>"
            }
            svg += "</g>" + text(label, x: side + gap, width: max(0,w-side-gap))
        case "tab" where theme.platform == .windows:
            let labels = p["dataSource"]?.string.map { [$0] } ?? listLabels(p["labels"])
            let titles = Array((labels.isEmpty ? ["\"\(object.name)\""] : labels).prefix(32))
            let widths = titles.map { max(theme.fluent ? 40 : 28, measure($0, size: fontSize, p: p) + (theme.fluent ? 32 : 12)) }
            let total = widths.reduce(0, +)
            let scale = total > w ? w / total : 1
            let stripHeight = min(h, theme.fluent ? 32 : 21)
            let bottom = p["labelsPlacement"]?.string == "bottom"
            let y = bottom ? h-stripHeight : 0
            if !theme.fluent && h > stripHeight {
                svg += "<rect x=\"0.5\" y=\"\(n(bottom ? 0.5 : stripHeight-0.5))\" width=\"\(n(max(0,w-1)))\" height=\"\(n(max(0,h-stripHeight)))\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-tab)"))\" stroke=\"var(--form-tab-border)\"/>"
            }
            var x: Double = 0
            for (index, title) in titles.enumerated() {
                let width = widths[index] * scale
                if index == 0 {
                    let raise: Double = theme.fluent ? 0 : 2
                    svg += "<rect x=\"\(n(x+0.5))\" y=\"\(n(y+0.5-(bottom ? 0 : raise)))\" width=\"\(n(max(0,width-1)))\" height=\"\(n(stripHeight+raise))\" rx=\"\(theme.fluent ? "6" : "0")\" fill=\"var(--form-tab-selected)\" stroke=\"var(--form-tab-border)\"/>"
                } else if theme.fluent {
                    svg += "<line x1=\"\(n(x))\" y1=\"\(n(y+8))\" x2=\"\(n(x))\" y2=\"\(n(y+max(8,stripHeight-8)))\" stroke=\"var(--form-tab-border)\"/>"
                } else {
                    svg += "<rect x=\"\(n(x+0.5))\" y=\"\(n(y+0.5))\" width=\"\(n(max(0,width-1)))\" height=\"\(n(max(0,stripHeight-1)))\" fill=\"var(--form-tab)\" stroke=\"var(--form-tab-border)\"/>"
                }
                svg += text(title, x: x, y: y, width: width, height: stripHeight, center: true,
                            ink: index == 0 || theme.fluent == false ? stroke : "var(--form-muted)")
                x += width
            }
        case "groupBox" where theme.platform == .windows:
            let title = p["text"]?.string ?? ""
            let titleHeight = title.isEmpty ? 0 : min(h, fontSize+4)
            svg += "<rect x=\"0.5\" y=\"\(n(titleHeight/2+0.5))\" width=\"\(n(max(0,w-1)))\" height=\"\(n(max(0,h-titleHeight/2-1)))\" rx=\"\(n(FormPlatformStyle.windowsControlRadius(theme)))\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-group)"))\" stroke=\"var(--form-border)\"/>"
            if !title.isEmpty {
                let titleWidth = min(max(0,w-16), measure(title, size: fontSize, p: p)+4)
                let x = p["textAlign"]?.string == "center" ? (w-titleWidth)/2
                    : p["textAlign"]?.string == "right" ? w-titleWidth-8 : 8
                svg += "<rect x=\"\(n(x))\" width=\"\(n(titleWidth))\" height=\"\(n(titleHeight))\" fill=\"var(--form-bg)\"/>"
                svg += text(title, x: x+2, width: max(0,titleWidth-2), height: titleHeight)
            }
        case "text":
            if fill != "transparent" || border != "system" && border != "none" {
                let radius = max(0,min(256,p["borderRadius"]?.double ?? 0))
                let bordered = border == "solid" || border == "dotted"
                let expansionX = bordered ? 1+min(radius,h/2) : 0
                let expansionY: Double = bordered ? 1 : 0
                svg += "<rect x=\"\(n(-expansionX))\" y=\"\(n(-expansionY))\" width=\"\(n(w+2*expansionX))\" height=\"\(n(h+2*expansionY))\" rx=\"\(n(min(radius,h/2)))\" fill=\"\(fill)\" stroke=\"\(border == "none" || border == "system" ? "none" : color(p["borderColor"]?.string, fallback: stroke))\"\(border == "dotted" ? " stroke-dasharray=\"2 2\"" : "")/>"
            }
            svg += "<g clip-path=\"url(#\(clip))\">" + text(label) + "</g>"
        case "rectangle", "oval":
            let outline = border == "none" ? "none" : stroke
            let lineWidth = max(0, min(32, p["strokeWidth"]?.double ?? 1))
            let dash = border == "dotted" ? " stroke-dasharray=\"2 2\"" : dashArray(p["strokeDashArray"])
            if object.type == "oval" {
                svg += "<ellipse cx=\"\(n(w/2))\" cy=\"\(n(h/2))\" rx=\"\(n(w/2))\" ry=\"\(n(h/2))\" fill=\"\(fill)\" stroke=\"\(outline)\" stroke-width=\"\(n(lineWidth))\"\(dash)/>"
            } else {
                svg += "<rect width=\"\(n(w))\" height=\"\(n(h))\" rx=\"\(n(max(0,min(256,p["borderRadius"]?.double ?? 0))))\" fill=\"\(fill)\" stroke=\"\(outline)\" stroke-width=\"\(n(lineWidth))\"\(dash)/>"
            }
        case "line":
            svg += "<line x1=\"0\" y1=\"\(p["startPoint"]?.string == "bottomLeft" ? n(h) : "0")\" x2=\"\(n(w))\" y2=\"\(p["startPoint"]?.string == "bottomLeft" ? "0" : n(h))\" stroke=\"\(stroke)\" stroke-width=\"\(n(max(0,min(32,p["strokeWidth"]?.double ?? 1))))\"\(dashArray(p["strokeDashArray"]))/>"
        case "input", "combo":
            let bordered = border == "solid" || border == "dotted"
            let radius = max(0,min(256,p["borderRadius"]?.double ?? 0))
            let expansionX = bordered ? 1 + min(radius,h/2) : 0
            // Native single-line rounding expands width, but not height by the radius.
            let singleLine = p["multiline"]?.string == "no" || h <= 32 && p["multiline"]?.string != "yes"
            let expansionY = bordered ? 1 + (singleLine ? 0 : min(radius,h/2)) : 0
            let background = color(p["fill"]?.string, fallback: object.type == "combo" && theme.glass ? "var(--form-control)" : "var(--form-input)")
            let outline = bordered && p["stroke"]?.string.map({ $0 != "automatic" }) == true ? stroke : "var(--form-border)"
            if border != "none" {
                svg += "<rect x=\"\(n(-expansionX))\" y=\"\(n(-expansionY))\" width=\"\(n(w+2*expansionX))\" height=\"\(n(h+2*expansionY))\" rx=\"\(n(min(h/2,max(0,p["borderRadius"]?.double ?? (border == "system" ? (theme.platform == .windows ? FormPlatformStyle.windowsControlRadius(theme) : 3) : 0)))))\" fill=\"\(background)\" stroke=\"\(color(p["borderColor"]?.string, fallback: outline))\"\(border == "dotted" ? " stroke-dasharray=\"2 2\"" : "")/>"
            } else { svg += rect(background, outline: "none") }
            svg += "<g clip-path=\"url(#\(clip))\">" + text(p["dataSource"]?.string ?? "\"\(object.name)\"", x: object.type == "combo" ? 3 : 0, width: max(0,w - (object.type == "combo" ? 23 : 0))) + "</g>"
            if object.type == "combo" { svg += chevrons(x: w - 12, y: h / 2, both: false) }
        case "button", "dropdown":
            let style = p["style"]?.string ?? "regular"
            let defaultButton = p["defaultButton"]?.bool == true && (style == "regular" || style == "flat")
            let radius: Double = style == "help" || style == "circular" ? min(w,h)/2
                : style == "regular" || object.type == "dropdown" ? (theme.glass && h >= 27 && (object.type != "dropdown" || h <= 32) ? h/2 : theme.glass ? 2 : 5)
                : ["roundedBevel", "gradientBevel", "texturedBevel", "flat"].contains(style) ? 5 : 0
            if style == "help" {
                svg += "<circle cx=\"\(n(w/2))\" cy=\"\(n(h/2))\" r=\"\(n(min(12,min(w,h)/2)))\" fill=\"var(--form-control)\" stroke=\"\(theme.glass ? "none" : "var(--form-border)")\"/>" + text("?", center: true)
            } else if style == "circular" {
                let diameter = max(0,min(w,h-fontSize-3))
                svg += "<circle cx=\"\(n(w/2))\" cy=\"\(n(diameter/2))\" r=\"\(n(diameter/2))\" fill=\"var(--form-control)\" stroke=\"var(--form-border)\"/>"
                svg += image("icon", x: (w-diameter)/2, width: diameter, height: diameter, format: "proportionalCenter")
                svg += text(label, y: diameter+2, height: max(0,h-diameter-2), center: true)
            } else {
                if style == "custom" { svg += rect(fill, outline: border == "solid" ? stroke : "none") + image("customBackgroundPicture") }
                else if style != "toolbar" {
                    svg += rect(defaultButton && style == "regular" ? "var(--form-accent)" : style == "regular" ? "var(--form-control)" : color(p["fill"]?.string, fallback: style == "office" ? "var(--form-office)" : "var(--form-control)"),
                                radius: radius, outline: defaultButton && style == "regular" ? "var(--form-accent)" : theme.glass && (style == "regular" || object.type == "dropdown") ? "none" : "var(--form-border)", inset: style == "roundedBevel" ? 3 : 0)
                }
                svg += "<g clip-path=\"url(#\(clip))\">" + iconCaption(label, x: object.type == "dropdown" ? 7 : 0,
                               width: max(0,w-(object.type == "dropdown" ? 25 : 0)),
                               center: object.type == "button",
                               ink: defaultButton && style == "regular" ? "white" : stroke) + "</g>"
                if object.type == "dropdown" || p["popupPlacement"]?.string.map({ $0 != "none" }) == true {
                    let classicPopup = object.type == "dropdown" && !theme.glass
                    if classicPopup {
                        let side = max(0,min(17,w-2))
                        svg += "<rect x=\"\(n(w-side-1))\" y=\"1\" width=\"\(n(side))\" height=\"\(n(max(0,h-2)))\" rx=\"4\" fill=\"var(--form-accent)\"/>"
                    }
                    svg += chevrons(x: w - 11, y: h/2, both: object.type == "dropdown", ink: classicPopup ? "white" : "var(--form-ink)")
                }
            }
        case "checkbox", "radio":
            let style = p["style"]?.string ?? "regular"
            let defaultSize = p["height"] == nil && p["bottom"] == nil
            let side: Double = theme.glass ? (defaultSize ? 16 : object.type == "checkbox" ? (h <= 13 ? 12 : h <= 16 ? 14 : 16) : (h <= 13 ? 14 : 16))
                : object.type == "checkbox" ? (h <= 13 ? 10 : h <= 16 ? 12 : 14) : (h <= 13 ? 12 : 14)
            let y = (h-side)/2
            if ["disclosure", "roundedDisclosure"].contains(style) {
                svg += "<path d=\"M3 \(n(h/2-5)) l7 5 -7 5 z\" fill=\"var(--form-muted)\"/>"
                svg += text(label, x: 16, width: max(0,w-16))
            } else if style == "custom" {
                svg += image("customBackgroundPicture") + image("icon", width: min(h,w), height: h, format: "proportionalCenter")
                svg += text(label, center: true)
            } else if style == "toolbar" {
                svg += image("icon", width: min(h,w), height: h, format: "proportionalCenter") + text(label, center: true)
            } else if style != "regular" && style != "flat" {
                svg += rect(color(p["fill"]?.string, fallback: "var(--form-control)"), radius: style == "bevel" ? 0 : 5)
                svg += "<g clip-path=\"url(#\(clip))\">" + iconCaption(label) + "</g>"
            } else if object.type == "radio" {
                svg += "<circle cx=\"\(n(side/2))\" cy=\"\(n(h/2))\" r=\"\(n(max(0,side/2-0.5)))\" fill=\"var(--form-toggle)\" stroke=\"var(--form-border)\"/>"
                svg += text(label, x: side + 5, width: max(0,w-side-5))
            } else {
                svg += "<rect y=\"\(n(y))\" width=\"\(n(side))\" height=\"\(n(side))\" rx=\"3\" fill=\"var(--form-toggle)\" stroke=\"var(--form-border)\"/>"
                svg += text(label, x: side + 5, width: max(0,w-side-5))
            }
        case "groupBox":
            let title = p["text"]?.string ?? ""
            let titleHeight = title.isEmpty ? 0 : min(h, fontSize+2)
            svg += "<rect y=\"\(n(titleHeight))\" width=\"\(n(w))\" height=\"\(n(max(0,h-titleHeight)))\" rx=\"5\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-group)"))\" stroke=\"var(--form-border)\"/>"
            if !title.isEmpty {
                let titleWidth = min(max(0,w-24), measure(title, size: fontSize, p: p)+4)
                let x = p["textAlign"]?.string == "center" ? (w-titleWidth)/2
                    : p["textAlign"]?.string == "right" ? w-titleWidth-12 : 12
                svg += text(title, x: x, width: titleWidth, height: titleHeight)
            }
        case "tab":
            let labels = p["dataSource"]?.string.map { [$0] } ?? listLabels(p["labels"])
            let titles = labels.isEmpty ? ["\"\(object.name)\""] : labels
            let widths = titles.prefix(32).map { max(28, measure($0, size: fontSize, p: p) + (theme.glass ? 12 : 13)) }
            let total = widths.reduce(0, +)
            let scale = total > w ? w / total : 1
            let stripWidth = min(w, total)
            let stripHeight = min(h, theme.glass ? 24 : 21)
            let y = p["labelsPlacement"]?.string == "bottom" ? h-stripHeight : min(theme.glass ? 1 : 2.5, h-stripHeight)
            var x = max(0, (w-stripWidth)/2)
            svg += "<rect x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(stripWidth))\" height=\"\(n(stripHeight))\" rx=\"5\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-tab)"))\" stroke=\"\(theme.glass ? "none" : "var(--form-border)")\"/>"
            for (index, title) in titles.prefix(32).enumerated() {
                let width = widths[index] * scale
                let selected = index == 0
                if selected {
                    svg += "<rect x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(width))\" height=\"\(n(stripHeight))\" rx=\"4\" fill=\"\(theme.glass ? "var(--form-accent)" : "var(--form-tab-selected)")\"/>"
                } else if index > 1 {
                    svg += "<line x1=\"\(n(x))\" y1=\"\(n(y+4))\" x2=\"\(n(x))\" y2=\"\(n(y+max(4,stripHeight-4)))\" stroke=\"var(--form-border)\"/>"
                }
                svg += text(title, x: x, y: p["labelsPlacement"]?.string == "bottom" ? y : theme.glass ? 0 : 1,
                            width: width, height: p["labelsPlacement"]?.string == "bottom" ? stripHeight : h, center: true,
                            ink: selected && theme.glass && (p["stroke"] == nil || p["stroke"]?.string == "automatic") ? "white" : stroke)
                x += width
            }
        case "picture", "pictureButton", "picturePopup", "buttonGrid":
            if object.images["picture"] != nil {
                svg += image("picture", format: p["pictureFormat"]?.string ?? (object.type == "picture" ? "truncatedCenter" : "scaled"))
            } else {
                svg += rect("var(--form-input)") + text(p["picture"]?.string ?? object.type, x: 5, width: max(0,w-10), center: true, ink: "var(--form-muted)")
            }
        case "listbox":
            svg += listbox(p, width: w, height: h, id: id, ink: stroke, theme: theme)
        case "list":
            svg += rect(color(p["fill"]?.string, fallback: "var(--form-input)"))
            let labels = listLabels(p["list"])
            if labels.isEmpty { svg += text(p["dataSource"]?.string ?? "\"\(object.name)\"", x: 5, height: min(h,22)) }
            for (index, label) in labels.prefix(Int(min(50,h/20))).enumerated() {
                svg += "<path d=\"M6 \(n(Double(index)*20+7)) l4 4 -4 4\" fill=\"none\" stroke=\"var(--form-muted)\"/>"
                svg += text(label, x: 16, y: Double(index)*20, width: max(0,w-20), height: 20)
            }
        case "progress":
            svg += "<rect y=\"\(n(max(0,(h-6)/2)))\" width=\"\(n(w))\" height=\"\(n(min(h,6)))\" rx=\"3\" fill=\"var(--form-border)\"/>"
        case "ruler":
            svg += "<line x1=\"0\" y1=\"\(n(h/2))\" x2=\"\(n(w))\" y2=\"\(n(h/2))\" stroke=\"var(--form-border)\" stroke-width=\"4\"/><circle cx=\"\(n(w/2))\" cy=\"\(n(h/2))\" r=\"\(n(min(8,h/2)))\" fill=\"var(--form-control)\" stroke=\"var(--form-border)\"/>"
        case "stepper":
            svg += rect("var(--form-control)", radius: 3) + "<line x1=\"0\" y1=\"\(n(h/2))\" x2=\"\(n(w))\" y2=\"\(n(h/2))\" stroke=\"var(--form-border)\"/>" + chevrons(x: w/2, y: h/2, both: true)
        case "spinner":
            for index in 0..<12 {
                let angle = Double(index)*Double.pi/6
                let r = min(w,h)/2
                svg += "<line x1=\"\(n(w/2+cos(angle)*r*0.5))\" y1=\"\(n(h/2+sin(angle)*r*0.5))\" x2=\"\(n(w/2+cos(angle)*r*0.85))\" y2=\"\(n(h/2+sin(angle)*r*0.85))\" stroke=\"var(--form-muted)\" opacity=\"\(n(Double(index+1)/12))\" stroke-width=\"2\"/>"
            }
        case "splitter":
            svg += rect("var(--form-border)", outline: "none")
        case "subform" where object.embeddedProperties != nil:
            let scheme = object.embeddedProperties?["colorScheme"]?.string
            let childTheme = theme.forcing(scheme)
            svg += "<g class=\"static-subform \(FormPlatformStyle.classes(childTheme))\" clip-path=\"url(#\(clip))\"><rect width=\"\(n(w))\" height=\"\(n(h))\" fill=\"var(--form-bg)\"/>"
            for (index, child) in object.children.enumerated() {
                svg += draw(child, theme: childTheme, images: images, id: "\(id)-child-\(index)", depth: depth + 1)
            }
            svg += "</g>"
            if p["borderStyle"] != nil && border != "none" {
                svg += rect("transparent", outline: color(p["borderColor"]?.string, fallback: "var(--form-border)"))
            }
        default:
            svg += "<rect width=\"\(n(w))\" height=\"\(n(h))\" fill=\"var(--form-input)\" stroke=\"var(--form-border)\" stroke-dasharray=\"4 3\"/>" + text("\(object.type)\n\(label)", x: 6, width: max(0,w-12), center: true, ink: "var(--form-muted)")
        }
        return svg + "</g>"
    }

    private func listbox(_ p: FormValue, width: Double, height: Double, id: String, ink: String, theme: FormTheme) -> String {
        // macOS list boxes always used the Liquid Glass automatic font rules.
        let theme: FormTheme = theme.platform == .windows ? theme : .glassLight
        let fontSize = font(p, height: 22, theme: theme)
        let headerHeight = p["showHeaders"]?.bool == false ? 0 : unit(p["headerHeight"], size: fontSize, fallback: 22)
        let footerHeight = p["showFooters"]?.bool == true ? unit(p["footerHeight"], size: fontSize, fallback: 22) : 0
        let rowHeight = max(1, unit(p["rowHeight"], size: fontSize, fallback: 20))
        let contentWidth = max(0, width - (p["scrollbarVertical"]?.string == "hidden" ? 0 : 16))
        var svg = "<g clip-path=\"url(#form-clip-\(id))\"><rect width=\"\(n(width))\" height=\"\(n(height))\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-input)"))\" stroke=\"var(--form-border)\"/>"
        let columns = p["columns"]?.values ?? []
        let rowCount = min(200, Int(max(0,height-headerHeight-footerHeight)/rowHeight)+1)
        for index in 0..<rowCount {
            let y = headerHeight + Double(index)*rowHeight
            if index % 2 == 1 {
                svg += "<rect y=\"\(n(y))\" width=\"\(n(width))\" height=\"\(n(rowHeight))\" fill=\"\(color(p["alternateFill"]?.string, fallback: "var(--form-alternate)"))\"/>"
            }
            svg += "<line x1=\"0\" y1=\"\(n(y+rowHeight))\" x2=\"\(n(width))\" y2=\"\(n(y+rowHeight))\" stroke=\"\(color(p["horizontalLineStroke"]?.string, fallback: "var(--form-grid)"))\"/>"
        }
        var x: Double = 0
        var headerDividers: [Double] = []
        for (index, column) in columns.prefix(64).enumerated() {
            if column["visibility"]?.string == "hidden" { continue }
            var w = column["width"]?.double ?? 100
            if index == columns.count-1 && p["resizingMode"]?.string != "rightToLeft" { w = max(w,contentWidth-x) }
            w = max(0,min(8_192,w,contentWidth-x))
            if headerHeight > 0 {
                let header = column["header"] ?? .object([])
                svg += "<rect x=\"\(n(x))\" width=\"\(n(w))\" height=\"\(n(headerHeight))\" fill=\"\(color(header["fill"]?.string, fallback: "var(--form-header)"))\"/>"
                if headerHeight > 12 && w > 0 { headerDividers.append(x+w) }
                svg += text(header["text"]?.string ?? column["name"]?.string ?? "", p: header, x: x+2, y: 1,
                            width: max(0,w-4), height: headerHeight, size: font(header, height: headerHeight, theme: theme),
                            center: false, ink: color(header["stroke"]?.string, fallback: ink),
                            singleLine: header["multiline"]?.string != "yes" && header["wordwrap"]?.string != "normal")
            }
            let expression = column["dataSource"]?.string ?? column["name"]?.string ?? ""
            svg += text(expression, p: column, x: x+5, y: headerHeight, width: max(0,w-10),
                        height: rowHeight, size: font(column,height:rowHeight,theme:theme), center: false,
                        ink: color(column["stroke"]?.string, fallback: "var(--form-muted)"),
                        singleLine: column["multiline"]?.string != "yes" && column["wordwrap"]?.string != "normal")
            svg += "<line x1=\"\(n(x+w))\" y1=\"\(n(headerHeight))\" x2=\"\(n(x+w))\" y2=\"\(n(height))\" stroke=\"\(color(p["verticalLineStroke"]?.string, fallback: "var(--form-grid)"))\"/>"
            if footerHeight > 0 {
                let footer = column["footer"] ?? .object([])
                svg += "<rect x=\"\(n(x))\" y=\"\(n(height-footerHeight))\" width=\"\(n(w))\" height=\"\(n(footerHeight))\" fill=\"\(color(footer["fill"]?.string, fallback: "var(--form-input)"))\" stroke=\"var(--form-footer-border)\"/>"
                svg += text(footer["text"]?.string ?? footer["dataSource"]?.string ?? "", p: footer, x: x+2, y: height-footerHeight+1,
                            width: max(0,w-4), height: footerHeight, size: font(footer,height:footerHeight,theme:theme), center: false,
                            ink: color(footer["stroke"]?.string, fallback: ink),
                            singleLine: footer["multiline"]?.string != "yes" && footer["wordwrap"]?.string != "normal")
            }
            x += w
            if x >= contentWidth { break }
        }
        if contentWidth < width {
            svg += "<rect x=\"\(n(contentWidth))\" width=\"\(n(width-contentWidth))\" height=\"\(n(height))\" fill=\"\(color(p["fill"]?.string, fallback: "var(--form-input)"))\"/>"
        }
        for divider in headerDividers {
            svg += "<rect x=\"\(n(divider-1))\" y=\"6\" width=\"2\" height=\"\(n(headerHeight-12))\" rx=\"1\" fill=\"var(--form-header-divider)\"/>"
        }
        if headerHeight > 0 {
            svg += "<line x1=\"0\" y1=\"\(n(headerHeight))\" x2=\"\(n(contentWidth))\" y2=\"\(n(headerHeight))\" stroke=\"var(--form-footer-border)\"/>"
        }
        return svg + "</g>"
    }

    private func text(_ value: String, p: FormValue, x: Double, y: Double, width: Double, height: Double,
                      size: Double, center: Bool, ink: String, singleLine: Bool = false) -> String {
        let padded = ["text", "input"].contains(p["type"]?.string ?? "")
        let left = padded ? unit(p["paddingLeft"], size: size, fallback: 0) : 0
        let right = padded ? unit(p["paddingRight"], size: size, fallback: 0) : 0
        let top = padded ? unit(p["paddingTop"], size: size, fallback: 0) : 0
        let bottom = padded ? unit(p["paddingBottom"], size: size, fallback: 0) : 0
        let width = width-left-right
        let height = height-top-bottom
        guard width > 0, height > 0 else { return "" }
        let alignment = p["textAlign"]?.string ?? (center ? "center" : "left")
        let anchor = alignment == "center" ? "middle" : alignment == "right" ? "end" : "start"
        let origin = anchor == "middle" ? width/2 : anchor == "end" ? width : 0
        let fallbackFamily = FormPlatformStyle(platform).fallbackFamily
        let family = p["fontFamily"]?.string.flatMap {
            !$0.hasPrefix("%") && FormFontFace.installed($0, size: size) ? $0 + ", " + fallbackFamily : nil
        } ?? fallbackFamily
        let weight = p["fontWeight"]?.string == "bold"
            || p["fontWeight"] == nil && p["fontTheme"]?.string == "main" ? "bold" : "normal"
        let italic = p["fontStyle"]?.string == "italic" ? "italic" : "normal"
        let decoration = p["textDecoration"]?.string == "underline" ? "underline" : "none"
        let layout = FormTextLayout(text: value, width: width, size: size, properties: p,
                                    maxLines: singleLine ? 1 : Int(max(1, min(100, ceil(height / max(1, size * 1.2))))),
                                    platform: platform)
        let face = FormTextLayout.font(size: size, properties: p, platform: platform)
        let ascent = layout.lines.first?.ascent ?? size
        let descent = layout.lines.first?.descent ?? 0
        let capHeight = face.capHeight
        var vertical = ["text", "groupBox"].contains(p["type"]?.string ?? "") || layout.lines.count > 1
            ? max(size, ceil(ascent)) : (height-capHeight-descent)/2+capHeight
        if (p["type"] == nil || ["text", "input", "listbox", "listboxColumn", "listboxHeader", "listboxFooter"].contains(p["type"]?.string ?? "")),
           let alignment = p["verticalAlign"]?.string, ["top", "middle", "bottom"].contains(alignment) {
            let baseline = max(ceil(ascent), face.baselineOffset)
            let blockHeight = ceil(baseline + (layout.lines.last?.descent ?? descent)) + (Double(layout.lines.count)-1)*layout.lineHeight + 1
            let space = max(0, height-blockHeight)
            vertical = baseline + (alignment == "middle" ? floor(space/2) : alignment == "bottom" ? space : 0)
        }
        var svg = "<svg x=\"\(n(x+left))\" y=\"\(n(y+top))\" width=\"\(n(width))\" height=\"\(n(height))\" overflow=\"hidden\"><text x=\"\(n(origin))\" y=\"\(n(vertical))\" fill=\"\(ink)\" font-family=\"\(esc(family))\" font-size=\"\(n(size))\" font-weight=\"\(weight)\" font-style=\"\(italic)\" text-decoration=\"\(decoration)\" text-anchor=\"\(anchor)\" xml:space=\"preserve\""
        if let angle = p["textAngle"]?.double, [90.0,180.0,270.0].contains(angle) {
            svg += " transform=\"rotate(\(n(-angle)) \(n(width/2)) \(n(height/2)))\""
        }
        svg += ">"
        for (index,line) in layout.lines.enumerated() {
            var value = line.text
            var spacing = ""
            if alignment == "justify" && !line.endsParagraph {
                while value.last == " " { value.removeLast() }
                let spaces = value.filter { $0 == " " }.count
                if spaces > 0 {
                    let extra = max(0, width-measure(value, size: size, p: p))/Double(spaces)
                    spacing = " word-spacing=\"\(n(extra))\""
                }
            }
            svg += "<tspan x=\"\(n(origin))\" y=\"\(n(vertical+Double(index)*layout.lineHeight))\"\(spacing)>\(esc(value))</tspan>"
        }
        return svg + "</text></svg>"
    }

    private func measure(_ text: String, size: Double, p: FormValue) -> Double {
        FormTextLayout.font(size: size, properties: p, platform: platform).width(FormTextLayout.bounded(text))
    }

    private func font(_ properties: FormValue, height: Double, theme: FormTheme = .glassLight) -> Double {
        if let size = properties["fontSize"]?.double, size > 0, size.isFinite { return max(1,min(256,size)) }
        if theme.platform == .windows {
            return FormPlatformStyle.windowsFontSize(theme, fontTheme: properties["fontTheme"]?.string)
        }
        let glass = theme.glass
        if properties["fontTheme"]?.string == "main" { return 13 }
        if properties["fontTheme"]?.string == "normal",
           !["button", "dropdown", "checkbox", "radio", "groupBox"].contains(properties["type"]?.string ?? "") { return 13 }
        if properties["fontTheme"]?.string == "additional" { return 11 }
        if properties["height"] == nil && properties["bottom"] == nil {
            if ["checkbox", "radio"].contains(properties["type"]?.string ?? "") { return 13 }
            if ["button", "dropdown"].contains(properties["type"]?.string ?? "") { return glass ? 11 : 13 }
        }
        switch properties["type"]?.string {
        case "button", "dropdown": return height <= 16 ? 9 : (glass ? height <= 20 : height < 20) ? 11 : 13
        case "checkbox": return height <= 13 ? 9 : height <= 16 ? 11 : 13
        case "radio": return height <= 13 ? 11 : 13
        case "groupBox": return 10
        default: return height < 18 ? 11 : 13
        }
    }

    private static func nativeControlHeight(_ height: Double) -> Double {
        guard height > 0 else { return 0 }
        if height <= 16 { return 16 }
        if height <= 20 { return 20 }
        if height < 27 { return 24 }
        if height <= 32 { return 28 }
        return height
    }

    private func unit(_ value: FormValue?, size: Double, fallback: Double) -> Double {
        guard let length = Self.length(value, size: size) else { return fallback }
        return max(0,min(8_192,length))
    }

    private static func length(_ value: FormValue?, size: Double) -> Double? {
        let number: Double?
        if let n = value?.double { number = n }
        else if let s = value?.string {
            if s.hasSuffix("em") { number = Double(s.dropLast(2)).map { $0*size } }
            else if s.hasSuffix("px") { number = Double(s.dropLast(2)) }
            else { number = Double(s) }
        } else { return nil }
        return number.flatMap { $0.isFinite ? $0 : nil }
    }

    private func listLabels(_ value: FormValue?) -> [String] {
        let items = value?["items"]?.values ?? value?.values ?? []
        return items.prefix(100).map { $0.string ?? $0["text"]?.string ?? $0.double.map { n($0) } ?? "" }
    }

    private func image(_ asset: FormImage, x: Double, y: Double, w: Double, h: Double, format: String, id: String,
                       sourceWidth: Double, sourceHeight: Double) -> String {
        let sx: Double, sy: Double
        if format == "scaled" { sx = w/sourceWidth; sy = h/sourceHeight }
        else if format.hasPrefix("proportional") { sx = min(w/sourceWidth,h/sourceHeight); sy = sx }
        else { sx = 1; sy = 1 }
        let centered = format == "truncatedCenter" || format == "proportionalCenter"
        let ox = centered ? (w-sourceWidth*sx)/2 : 0
        let oy = centered ? (h-sourceHeight*sy)/2 : 0
        if format == "tiled" {
            return "<defs><pattern id=\"tile-\(id)\" width=\"\(n(asset.width))\" height=\"\(n(asset.height))\" patternUnits=\"userSpaceOnUse\"><use href=\"#\(asset.id)\"/></pattern></defs><rect x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(w))\" height=\"\(n(h))\" fill=\"url(#tile-\(id))\"/>"
        }
        return "<svg x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(w))\" height=\"\(n(h))\" overflow=\"hidden\"><g transform=\"translate(\(n(ox)) \(n(oy))) scale(\(n(sx)) \(n(sy)))\"><svg width=\"\(n(sourceWidth))\" height=\"\(n(sourceHeight))\" overflow=\"hidden\"><use href=\"#\(asset.id)\"/></svg></g></svg>"
    }

    private func chevrons(x: Double, y: Double, both: Bool, ink: String = "var(--form-ink)") -> String {
        "<path d=\"M\(n(x-3)) \(n(y+(both ? 2 : -2))) l3 3 3 -3\(both ? " M\(n(x-3)) \(n(y-2)) l3 -3 3 3" : "")\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"1.3\"/>"
    }

    private func dashArray(_ value: FormValue?) -> String {
        let values = value?.values.compactMap(\.double).filter { $0.isFinite && $0 >= 0 && $0 <= 100 }.prefix(16) ?? []
        return values.isEmpty ? "" : " stroke-dasharray=\"\(values.map(n).joined(separator:" "))\""
    }

    private func color(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        if value == "automatic" { return fallback }
        if value == "automaticAlternate" { return "var(--form-alternate)" }
        guard value.range(of: #"^(?:#[0-9a-fA-F]{3,8}|[A-Za-z]+|rgba?\(\s*[\d.%]+\s*,\s*[\d.%]+\s*,\s*[\d.%]+(?:\s*,\s*[\d.]+)?\s*\))$"#, options: .regularExpression) != nil else { return fallback }
        return value
    }

    private func n(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier:"en_US_POSIX"), value).replacingOccurrences(of: ".00", with: "") }
    private func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let platformCSS = """
    .platform-choice{position:absolute;opacity:0;width:1px;height:1px}.form-platform{display:none}
    .form-platform-tabs{display:flex;gap:4px;margin-bottom:12px}
    .form-platform-tabs label{font-size:12px;font-weight:600;border:1px solid var(--border);border-radius:6px;padding:5px 12px;cursor:pointer}
    .platform-choice:focus-visible ~ .form-platform-tabs{outline:2px solid var(--accent)}
    """

    private static let css = """
    .form-preview{position:relative}.theme-choice,.page-choice{position:absolute;opacity:0;width:1px;height:1px}
    .form-themes,.form-pages{display:flex;gap:3px;flex-wrap:wrap;margin-bottom:12px}
    .form-themes label,.form-pages label{font-size:12px;border-radius:6px;padding:5px 9px;cursor:pointer}
    .theme-choice:focus-visible ~ .form-themes,.page-choice:focus-visible ~ .form-pages{outline:2px solid var(--accent)}
    .form-appearance,.form-page{display:none}.form-scroll{overflow:auto;max-height:680px;border:1px solid var(--border);border-radius:6px}
    .form-scroll>svg{display:block;max-width:none}.form-caption{font-size:11px;color:var(--muted);margin-top:7px}
    .form-appearance.light,.static-subform.light{color-scheme:light;--form-bg:#ececec;--form-ink:#202020;--form-muted:#777;--form-input:#fff;--form-control:#fff;--form-toggle:#fff;--form-group:#e1e1e1;--form-tab:#f2f2f2;--form-tab-selected:#fff;--form-border:#b8b8b8;--form-header:#f6f6f6;--form-header-divider:#d3d3d3;--form-footer-border:#bcbcbc;--form-alternate:#f3f5f7;--form-grid:#ddd;--form-accent:#007aff;--form-office:#e2effc}
    .form-appearance.dark,.static-subform.dark{color-scheme:dark;--form-bg:#323232;--form-ink:#eee;--form-muted:#a0a0a0;--form-input:#1e1e1e;--form-control:#656565;--form-toggle:#535353;--form-group:#3b3b3b;--form-tab:#3c3c3c;--form-tab-selected:#6c6c6c;--form-border:#737373;--form-header:#2e3032;--form-header-divider:#45484a;--form-footer-border:#3f3f3f;--form-alternate:#272a2e;--form-grid:#444;--form-accent:#0a84ff;--form-office:#32455a}
    .form-appearance.glass.light,.static-subform.glass.light{--form-bg:#fff;--form-control:#e1e1e1;--form-group:#f3f3f3;--form-tab:#ebebeb;--form-border:#cecece;--form-accent:#0077f9}
    .form-appearance.glass.dark,.static-subform.glass.dark{--form-bg:#1e1e1e;--form-control:#383838;--form-toggle:#2a2a2a;--form-group:#282828;--form-tab:#303030;--form-border:#777;--form-accent:#067dff}
    """
}
