import SwiftUI

public enum MongrelAppearanceMode: String, CaseIterable, Identifiable {
    case standard
    case contrast
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .contrast: return "Contrast"
        case .custom: return "Custom"
        }
    }
}

public final class MongrelAppearancePreferences: ObservableObject, @unchecked Sendable {
    public static let shared = MongrelAppearancePreferences()

    public static let modeKey = "mongrelAppearanceMode"
    public static let backgroundHueKey = "mongrelCustomBackgroundHue"
    public static let backgroundSaturationKey = "mongrelCustomBackgroundSaturation"
    public static let backgroundBrightnessKey = "mongrelCustomBackgroundBrightness"
    public static let textHueKey = "mongrelCustomTextHue"
    public static let textSaturationKey = "mongrelCustomTextSaturation"
    public static let textBrightnessKey = "mongrelCustomTextBrightness"

    @Published public var mode: MongrelAppearanceMode { didSet { save(mode.rawValue, key: Self.modeKey) } }
    @Published public var backgroundHue: Double { didSet { save(backgroundHue, key: Self.backgroundHueKey) } }
    @Published public var backgroundSaturation: Double { didSet { save(backgroundSaturation, key: Self.backgroundSaturationKey) } }
    @Published public var backgroundBrightness: Double { didSet { save(backgroundBrightness, key: Self.backgroundBrightnessKey) } }
    @Published public var textHue: Double { didSet { save(textHue, key: Self.textHueKey) } }
    @Published public var textSaturation: Double { didSet { save(textSaturation, key: Self.textSaturationKey) } }
    @Published public var textBrightness: Double { didSet { save(textBrightness, key: Self.textBrightnessKey) } }

    public var background: Color {
        switch mode {
        case .standard:
            return Color(hue: 222 / 360, saturation: 0.42, brightness: 0.05)
        case .contrast:
            return Color(red: 0, green: 0, blue: 0)
        case .custom:
            return Color(hue: backgroundHue, saturation: backgroundSaturation, brightness: backgroundBrightness)
        }
    }

    public var text: Color {
        switch mode {
        case .standard:
            return Color(hue: 222 / 360, saturation: 0.10, brightness: 0.88)
        case .contrast:
            return .white
        case .custom:
            return Color(hue: textHue, saturation: textSaturation, brightness: textBrightness)
        }
    }

    public var contrastRatio: Double {
        let backgroundRGB = Self.hsvToRGB(h: mode == .contrast ? 0 : backgroundHue,
                                          s: mode == .contrast ? 0 : backgroundSaturation,
                                          v: mode == .contrast ? 0 : backgroundBrightness)
        let textRGB = Self.hsvToRGB(h: mode == .contrast ? 0 : textHue,
                                    s: mode == .contrast ? 0 : textSaturation,
                                    v: mode == .contrast ? 1 : textBrightness)
        let a = Self.relativeLuminance(backgroundRGB)
        let b = Self.relativeLuminance(textRGB)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private init(defaults: UserDefaults = .standard) {
        mode = MongrelAppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .standard
        backgroundHue = defaults.object(forKey: Self.backgroundHueKey) as? Double ?? 222 / 360
        backgroundSaturation = defaults.object(forKey: Self.backgroundSaturationKey) as? Double ?? 0.42
        backgroundBrightness = defaults.object(forKey: Self.backgroundBrightnessKey) as? Double ?? 0.05
        textHue = defaults.object(forKey: Self.textHueKey) as? Double ?? 222 / 360
        textSaturation = defaults.object(forKey: Self.textSaturationKey) as? Double ?? 0.04
        textBrightness = defaults.object(forKey: Self.textBrightnessKey) as? Double ?? 1.0
    }

    private func save(_ value: Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
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
            Section("Viewing mode") {
                Picker("Viewing mode", selection: $appearance.mode) {
                    ForEach(MongrelAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.72))
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
                .shadow(color: appearance.mode == .contrast ? .white.opacity(0.48) : .clear, radius: 3)

                LabeledContent("Contrast ratio", value: String(format: "%.1f:1", appearance.contrastRatio))
                Text(appearance.contrastRatio >= 7 ? "Meets enhanced text contrast." : "Try increasing the distance between background and text brightness.")
                    .font(.caption)
                    .foregroundStyle(appearance.contrastRatio >= 7 ? DesignTokens.accent : .orange)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 460, minHeight: 520)
        .background(DesignTokens.glassDeep.ignoresSafeArea())
        .foregroundStyle(DesignTokens.chromeText)
        .tint(DesignTokens.accent)
    }

    private var modeDescription: String {
        switch appearance.mode {
        case .standard: return "The app's original deep-glass palette."
        case .contrast: return "Pure black surfaces with blooming white text, borders, and active cues."
        case .custom: return "Build a personal palette with independent background and text controls."
        }
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
            .preferredColorScheme(.dark)
            .shadow(color: appearance.mode == .contrast ? .white.opacity(0.18) : .clear, radius: 2)
    }
}

public extension View {
    func mongrelAppearance() -> some View {
        modifier(MongrelAppearanceModifier())
    }
}
