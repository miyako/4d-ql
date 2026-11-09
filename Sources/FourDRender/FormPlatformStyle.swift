import FourDFileKit

/// Platform-specific presentation constants for the static form preview.
///
/// Windows values were measured from live 4D windows (4D 21.0 for Windows
/// Classic, 4D 21 R4 for Fluent UI) on Windows 11 25H2 at 200 % display
/// scale; see docs/WINDOWS-HANDOVER.md. Metrics are selected by the requested
/// theme's platform, never by the host operating system.
struct FormPlatformStyle {
    let platform: FormPlatform

    init(_ platform: FormPlatform) { self.platform = platform }

    /// Family used to measure form text when the form names no installed face.
    var primaryFamily: String { platform == .macOS ? "SF Pro Text" : "Segoe UI" }

    /// CSS family stack emitted with each SVG text run.
    var fallbackFamily: String {
        switch platform {
        case .macOS: return FormTextLayout.fallbackFamily
        case .windows: return FormSubstituteFont.isNeeded
            ? "Segoe UI, Selawik, Tahoma, Arial, sans-serif" : "Segoe UI, Tahoma, Arial, sans-serif"
        }
    }

    var appearanceLabel: String { "\(platform.label) appearance" }

    /// Appearance classes on `.form-appearance` and static subforms.
    static func classes(_ theme: FormTheme) -> String {
        switch theme.platform {
        case .macOS: return "\(theme.dark ? "dark" : "light") \(theme.glass ? "glass" : "classic")"
        case .windows: return "\(theme.dark ? "dark" : "light") \(theme.fluent ? "fluent" : "win-classic")"
        }
    }

    /// The automatic system font size for native control text.
    static func windowsFontSize(_ theme: FormTheme, fontTheme: String?) -> Double {
        let base: Double = theme.fluent ? 14 : 12
        return fontTheme == "additional" ? base - 1 : base
    }

    /// Native height used when a button or popup declares no height.
    static func windowsDefaultControlHeight(_ theme: FormTheme) -> Double { theme.fluent ? 25 : 22 }

    /// Check box and radio button glyph size; Fluent glyphs are clipped by short frames.
    static func windowsToggleSide(_ theme: FormTheme) -> Double { theme.fluent ? 20 : 13 }

    /// Gap between a check box or radio glyph and its label.
    static func windowsToggleGap(_ theme: FormTheme) -> Double { theme.fluent ? 8 : 3 }

    /// Corner radius of buttons, popups and Fluent check boxes.
    static func windowsControlRadius(_ theme: FormTheme) -> Double { theme.fluent ? 4 : 0 }

    static let windowsCSS = """
    .form-appearance.win-classic,.static-subform.win-classic{color-scheme:light;--form-bg:#f0f0f0;--form-ink:#000;--form-muted:#6d6d6d;--form-input:#fff;--form-control:#fdfdfd;--form-control-edge:#bababa;--form-popup:#fdfdfd;--form-toggle:#f3f3f3;--form-toggle-border:#626262;--form-group:transparent;--form-tab:#f9f9f9;--form-tab-selected:#f9f9f9;--form-tab-border:#e5e5e5;--form-border:#d0d0d0;--form-header:#fff;--form-header-divider:#e5e5e5;--form-footer-border:#d0d0d0;--form-alternate:#f7f7f7;--form-grid:#e5e5e5;--form-accent:#0078d4;--form-accent-ink:#000;--form-office:#e5f1fb}
    .form-appearance.fluent.light,.static-subform.fluent.light{color-scheme:light;--form-bg:#f3f3f3;--form-ink:#1a1a1a;--form-muted:#5f5f5f;--form-input:#fbfbfb;--form-control:#fbfbfb;--form-control-edge:#cccccc;--form-popup:#f5f5f5;--form-toggle:#ededed;--form-toggle-border:#868686;--form-group:transparent;--form-tab:#f3f3f3;--form-tab-selected:#f9f9f9;--form-tab-border:#eaeaea;--form-border:#e5e5e5;--form-header:#f9f9f9;--form-header-divider:#e5e5e5;--form-footer-border:#e5e5e5;--form-alternate:#f9f9f9;--form-grid:#eaeaea;--form-accent:#0055a1;--form-accent-ink:#fff;--form-office:#e5f1fb}
    .form-appearance.fluent.dark,.static-subform.fluent.dark{color-scheme:dark;--form-bg:#202020;--form-ink:#fff;--form-muted:#9d9d9d;--form-input:#2d2d2d;--form-control:#2d2d2d;--form-control-edge:#303030;--form-popup:#2a2a2a;--form-toggle:#1d1d1d;--form-toggle-border:#9a9a9a;--form-group:transparent;--form-tab:#202020;--form-tab-selected:#282828;--form-tab-border:#242424;--form-border:#353535;--form-header:#282828;--form-header-divider:#3a3a3a;--form-footer-border:#353535;--form-alternate:#262626;--form-grid:#353535;--form-accent:#40bdff;--form-accent-ink:#000;--form-office:#2b3a48}
    """
}
