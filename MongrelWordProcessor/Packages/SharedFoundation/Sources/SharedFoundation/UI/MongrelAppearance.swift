import SwiftUI

public enum MongrelContrastPolarity: String, CaseIterable, Identifiable {
    case black, white
    public var id: String { rawValue }
    public var title: String { self == .black ? "Black" : "White" }
    public var background: NSColor { self == .black ? .black : .white }
    public var foreground: NSColor { self == .black ? .white : .black }
    public var colorScheme: ColorScheme { self == .black ? .dark : .light }
}

public enum MongrelAppearanceMode: String, CaseIterable, Identifiable {
    case standard
    case contrast
    case graphite
    case pine
    case oxblood
    case daylight
    case parchment
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Mongrel Night"
        case .contrast: return "Contrast"
        case .graphite: return "Graphite"
        case .pine: return "Pine"
        case .oxblood: return "Oxblood"
        case .daylight: return "Daylight"
        case .parchment: return "Parchment"
        case .custom: return "Custom"
        }
    }
}

public final class MongrelAppearancePreferences: ObservableObject, @unchecked Sendable {
    public static let shared = MongrelAppearancePreferences()

    public static let modeKey = "mongrelAppearanceMode"
    public static let contrastPolarityKey = "mongrelContrastPolarity"
    public static let backgroundHueKey = "mongrelCustomBackgroundHue"
    public static let backgroundSaturationKey = "mongrelCustomBackgroundSaturation"
    public static let backgroundBrightnessKey = "mongrelCustomBackgroundBrightness"
    public static let textHueKey = "mongrelCustomTextHue"
    public static let textSaturationKey = "mongrelCustomTextSaturation"
    public static let textBrightnessKey = "mongrelCustomTextBrightness"

    @Published public var mode: MongrelAppearanceMode { didSet { save(mode.rawValue, key: Self.modeKey) } }
    @Published public var contrastPolarity: MongrelContrastPolarity { didSet { save(contrastPolarity.rawValue, key: Self.contrastPolarityKey) } }
    @Published public var backgroundHue: Double { didSet { save(backgroundHue, key: Self.backgroundHueKey) } }
    @Published public var backgroundSaturation: Double { didSet { save(backgroundSaturation, key: Self.backgroundSaturationKey) } }
    @Published public var backgroundBrightness: Double { didSet { save(backgroundBrightness, key: Self.backgroundBrightnessKey) } }
    @Published public var textHue: Double { didSet { save(textHue, key: Self.textHueKey) } }
    @Published public var textSaturation: Double { didSet { save(textSaturation, key: Self.textSaturationKey) } }
    @Published public var textBrightness: Double { didSet { save(textBrightness, key: Self.textBrightnessKey) } }

    public var background: Color {
        let value = effectiveBackgroundHSV
        return Color(hue: value.h, saturation: value.s, brightness: value.v)
    }

    public var text: Color {
        let value = effectiveTextHSV
        return Color(hue: value.h, saturation: value.s, brightness: value.v)
    }

    public var contrastRatio: Double {
        let background = effectiveBackgroundHSV
        let foreground = effectiveTextHSV
        let backgroundRGB = Self.hsvToRGB(h: background.h, s: background.s, v: background.v)
        let textRGB = Self.hsvToRGB(h: foreground.h, s: foreground.s, v: foreground.v)
        let a = Self.relativeLuminance(backgroundRGB)
        let b = Self.relativeLuminance(textRGB)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var effectiveBackgroundHSV: (h: Double, s: Double, v: Double) {
        switch mode {
        case .standard: return (222 / 360, 0.42, 0.05)
        case .contrast: return (0, 0, contrastPolarity == .black ? 0 : 1)
        case .graphite: return (210 / 360, 0.12, 0.10)
        case .pine: return (151 / 360, 0.62, 0.12)
        case .oxblood: return (351 / 360, 0.68, 0.16)
        case .daylight: return (205 / 360, 0.08, 0.96)
        case .parchment: return (39 / 360, 0.18, 0.94)
        case .custom: return (backgroundHue, backgroundSaturation, backgroundBrightness)
        }
    }

    var effectiveTextHSV: (h: Double, s: Double, v: Double) {
        switch mode {
        case .standard: return (222 / 360, 0.10, 0.88)
        case .contrast: return (0, 0, contrastPolarity == .black ? 1 : 0)
        case .graphite: return (205 / 360, 0.06, 0.95)
        case .pine: return (52 / 360, 0.15, 0.96)
        case .oxblood: return (24 / 360, 0.16, 0.98)
        case .daylight: return (215 / 360, 0.28, 0.16)
        case .parchment: return (28 / 360, 0.38, 0.18)
        case .custom: return (textHue, textSaturation, textBrightness)
        }
    }

    var preferredColorScheme: ColorScheme {
        effectiveBackgroundHSV.v > 0.58 ? .light : .dark
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = MongrelAppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .contrast
        contrastPolarity = MongrelContrastPolarity(rawValue: defaults.string(forKey: Self.contrastPolarityKey) ?? "") ?? .black
        backgroundHue = defaults.object(forKey: Self.backgroundHueKey) as? Double ?? 222 / 360
        backgroundSaturation = defaults.object(forKey: Self.backgroundSaturationKey) as? Double ?? 0.42
        backgroundBrightness = defaults.object(forKey: Self.backgroundBrightnessKey) as? Double ?? 0.05
        textHue = defaults.object(forKey: Self.textHueKey) as? Double ?? 222 / 360
        textSaturation = defaults.object(forKey: Self.textSaturationKey) as? Double ?? 0.04
        textBrightness = defaults.object(forKey: Self.textBrightnessKey) as? Double ?? 1.0
    }

    private func save(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
    }

    private static func hsvToRGB(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }
}

public struct MongrelAppearanceSettingsView: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    public init() {}

    public var body: some View {
        Form {
            Section("Layout palette") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(MongrelAppearanceMode.allCases) { mode in
                        Button {
                            appearance.mode = mode
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(color(for: mode, foreground: false))
                                    Text("Aa")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(color(for: mode, foreground: true))
                                }
                                .frame(width: 34, height: 34)
                                Text(mode.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Spacer(minLength: 0)
                                if appearance.mode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(9)
                            .background(
                                appearance.mode == mode
                                    ? DesignTokens.hoverBloom
                                    : DesignTokens.glassCard.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(appearance.mode == mode ? DesignTokens.glassBorder : DesignTokens.borderRim)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.72))
            }

            if appearance.mode == .contrast {
                Section("Contrast surface") {
                    Picker("Background", selection: $appearance.contrastPolarity) {
                        ForEach(MongrelContrastPolarity.allCases) { polarity in
                            Text(polarity.title).tag(polarity)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("One appearance for the workspace and every editor. Document colors for print and export stay in Page Layout.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.text(opacity: 0.68))
                }
            }

            if appearance.mode == .custom {
                colorControls(
                    title: "Background",
                    hue: $appearance.backgroundHue,
                    saturation: $appearance.backgroundSaturation,
                    brightness: $appearance.backgroundBrightness,
                    preview: appearance.background
                )
                colorControls(
                    title: "Text and cues",
                    hue: $appearance.textHue,
                    saturation: $appearance.textSaturation,
                    brightness: $appearance.textBrightness,
                    preview: appearance.text
                )
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Readable text and active cues", systemImage: "eye.fill")
                        .font(.headline)
                    Text("Secondary information remains visible without surrendering the app's visual hierarchy.")
                        .font(.caption)
                        .opacity(0.72)
                }
                .foregroundStyle(appearance.text)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appearance.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(appearance.text.opacity(0.55)))

                LabeledContent("Contrast ratio", value: String(format: "%.1f:1", appearance.contrastRatio))
                Text(appearance.contrastRatio >= 7 ? "Meets enhanced text contrast." : "Try increasing the distance between background and text brightness.")
                    .font(.caption)
                    .foregroundStyle(appearance.contrastRatio >= 7 ? DesignTokens.accent : .orange)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 650)
        .background(DesignTokens.glassDeep.ignoresSafeArea())
        .foregroundStyle(DesignTokens.chromeText)
        .tint(DesignTokens.accent)
        .preferredColorScheme(appearance.preferredColorScheme)
    }

    private var modeDescription: String {
        switch appearance.mode {
        case .standard: return "The original deep-navy Mongrel layout."
        case .contrast: return "Black and white, fine rules, and crisp typography. Choose either polarity."
        case .graphite: return "Neutral near-black surfaces with cool, pale lettering."
        case .pine: return "Deep green surfaces with warm cream lettering."
        case .oxblood: return "Near-black red surfaces with restrained rose-white lettering."
        case .daylight: return "Cool light surfaces with dark blue-charcoal lettering."
        case .parchment: return "Warm light surfaces with dark brown lettering."
        case .custom: return "Build a personal palette with independent background and text controls."
        }
    }

    private func color(for mode: MongrelAppearanceMode, foreground: Bool) -> Color {
        if mode == .custom {
            return foreground
                ? Color(hue: appearance.textHue, saturation: appearance.textSaturation, brightness: appearance.textBrightness)
                : Color(hue: appearance.backgroundHue, saturation: appearance.backgroundSaturation, brightness: appearance.backgroundBrightness)
        }
        let values: (h: Double, s: Double, v: Double)
        switch (mode, foreground) {
        case (.standard, false): values = (222 / 360, 0.42, 0.05)
        case (.standard, true): values = (222 / 360, 0.10, 0.88)
        case (.contrast, false): values = (0, 0, appearance.contrastPolarity == .black ? 0 : 1)
        case (.contrast, true): values = (0, 0, appearance.contrastPolarity == .black ? 1 : 0)
        case (.graphite, false): values = (210 / 360, 0.12, 0.10)
        case (.graphite, true): values = (205 / 360, 0.06, 0.95)
        case (.pine, false): values = (151 / 360, 0.62, 0.12)
        case (.pine, true): values = (52 / 360, 0.15, 0.96)
        case (.oxblood, false): values = (351 / 360, 0.68, 0.16)
        case (.oxblood, true): values = (24 / 360, 0.16, 0.98)
        case (.daylight, false): values = (205 / 360, 0.08, 0.96)
        case (.daylight, true): values = (215 / 360, 0.28, 0.16)
        case (.parchment, false): values = (39 / 360, 0.18, 0.94)
        case (.parchment, true): values = (28 / 360, 0.38, 0.18)
        case (.custom, _): values = (0, 0, foreground ? 1 : 0)
        }
        return Color(hue: values.h, saturation: values.s, brightness: values.v)
    }

    private func colorControls(
        title: String,
        hue: Binding<Double>,
        saturation: Binding<Double>,
        brightness: Binding<Double>,
        preview: Color
    ) -> some View {
        Section(title) {
            LabeledContent("Preview") {
                Circle()
                    .fill(preview)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(DesignTokens.borderRim))
            }
            AppearanceSlider(title: "Hue", value: hue, gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]))
            AppearanceSlider(title: "Saturation", value: saturation, gradient: Gradient(colors: [.gray, preview]))
            AppearanceSlider(title: "Brightness", value: brightness, gradient: Gradient(colors: [.black, preview, .white]))
        }
    }
}

private struct AppearanceSlider: View {
    let title: String
    @Binding var value: Double
    let gradient: Gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.68))
            }
            Slider(value: $value, in: 0...1)
                .tint(gradient.stops.last?.color ?? DesignTokens.accent)
                .background(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing), in: Capsule())
        }
    }
}

private struct MongrelAppearanceModifier: ViewModifier {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    func body(content: Content) -> some View {
        content
            .background(DesignTokens.glassDeep.ignoresSafeArea())
            .tint(DesignTokens.accent)
            .preferredColorScheme(appearance.preferredColorScheme)
    }
}

public extension View {
    func mongrelAppearance() -> some View {
        modifier(MongrelAppearanceModifier())
    }
}
