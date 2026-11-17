import SwiftUI
import UIKit

public enum Ink {
    public static let canvas = dynamic(light: 0xF6F6F4, dark: 0x0A0A0B)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x151517)
    public static let raised = dynamic(light: 0xF1F1EE, dark: 0x1D1D20)
    public static let well = dynamic(light: 0xEFEFEC, dark: 0x1A1A1D)
    public static let hairline = dynamic(light: 0x0B0B0C, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.08)
    public static let primary = dynamic(light: 0x0B0B0C, dark: 0xF4F4F2)
    public static let secondary = dynamic(light: 0x6C6C70, dark: 0x9C9CA2)
    public static let tertiary = dynamic(light: 0xA3A3A8, dark: 0x5F5F65)
    public static let inverse = dynamic(light: 0xFFFFFF, dark: 0x0B0B0C)
    public static let accent = dynamic(light: 0x4F46E5, dark: 0x8B85FF)
    public static let positive = dynamic(light: 0x13985A, dark: 0x3DD68C)
    public static let negative = dynamic(light: 0xD23F3F, dark: 0xFF6B6B)
    public static let claim = dynamic(light: 0xA86412, dark: 0xF2B252)
    public static let claimWash = dynamic(light: 0xA86412, dark: 0xF2B252, lightAlpha: 0.07, darkAlpha: 0.10)
    public static let positiveWash = dynamic(light: 0x13985A, dark: 0x3DD68C, lightAlpha: 0.10, darkAlpha: 0.14)
    public static let negativeWash = dynamic(light: 0xD23F3F, dark: 0xFF6B6B, lightAlpha: 0.09, darkAlpha: 0.14)
    public static let shadow = dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.0)

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

public enum Space {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let huge: CGFloat = 48
    public static let gutter: CGFloat = 20
}

public enum Radius {
    public static let card: CGFloat = 26
    public static let inner: CGFloat = 18
    public static let tile: CGFloat = 12
    public static let control: CGFloat = 32
}

public enum TypeRole {
    case display, title, title2, headline, body, callout, label, caption, eyebrow, mono

    var size: CGFloat {
        switch self {
        case .display: return 54
        case .title: return 30
        case .title2: return 22
        case .headline: return 17
        case .body: return 17
        case .callout: return 15
        case .label: return 14
        case .caption: return 12.5
        case .eyebrow: return 12
        case .mono: return 14
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display: return .semibold
        case .title: return .semibold
        case .title2: return .semibold
        case .headline: return .semibold
        case .body: return .regular
        case .callout: return .regular
        case .label: return .medium
        case .caption: return .regular
        case .eyebrow: return .semibold
        case .mono: return .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: return -2.2
        case .title: return -0.9
        case .title2: return -0.5
        case .headline: return -0.25
        case .body: return -0.2
        case .callout: return -0.1
        case .label: return -0.05
        case .caption: return 0
        case .eyebrow: return 0.7
        case .mono: return 0
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .label: return .subheadline
        case .caption: return .caption1
        case .eyebrow: return .caption1
        case .mono: return .subheadline
        }
    }
}

struct Typeset: ViewModifier {
    let role: TypeRole
    var weight: Font.Weight?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let size = UIFontMetrics(forTextStyle: role.textStyle).scaledValue(for: role.size, compatibleWith: traits)
        let design: Font.Design = role == .mono ? .monospaced : .default
        content
            .font(.system(size: size, weight: weight ?? role.weight, design: design))
            .tracking(role.tracking * size / role.size)
            .textCase(role == .eyebrow ? .uppercase : nil)
    }
}

extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}

extension View {
    public func type(_ role: TypeRole, weight: Font.Weight? = nil) -> some View {
        modifier(Typeset(role: role, weight: weight))
    }

    public func card(padding: CGFloat = Space.l, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.75))
            .shadow(color: Ink.shadow, radius: 18, x: 0, y: 8)
    }

    public func canvas() -> some View {
        background(Ink.canvas.ignoresSafeArea())
    }

    public func bogoList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Ink.canvas.ignoresSafeArea())
            .tint(Ink.primary)
    }
}

public enum Motion {
    public static let standard = Animation.spring(response: 0.48, dampingFraction: 0.86)
    public static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    public static let gentle = Animation.spring(response: 0.7, dampingFraction: 0.9)
    public static let fade = Animation.easeInOut(duration: 0.25)

    public static func respecting(_ reduce: Bool, _ animation: Animation) -> Animation {
        reduce ? fade : animation
    }
}

@MainActor
public enum Haptics {
    public static func tick(_ intensity: CGFloat = 0.5) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
    }

    public static func thud() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
    }

    public static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .type(.headline)
                .foregroundStyle(Ink.inverse)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Ink.primary.opacity(enabled ? 1 : 0.25), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(Motion.snappy, value: configuration.isPressed)
        }
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.headline)
            .foregroundStyle(Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Ink.raised, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

public struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Ink.secondary

    public init(tint: Color = Ink.secondary) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.headline, weight: .medium)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

public struct PressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

public struct Eyebrow: View {
    let text: String
    var trailing: AnyView?

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .type(.eyebrow)
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct Tile: View {
    let symbol: String
    var size: CGFloat = 40
    var tint: Color = Ink.primary
    var wash: Color = Ink.raised

    public init(symbol: String, size: CGFloat = 40, tint: Color = Ink.primary, wash: Color = Ink.raised) {
        self.symbol = symbol
        self.size = size
        self.tint = tint
        self.wash = wash
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(wash, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

public struct Monogram: View {
    let name: String
    var size: CGFloat = 22

    public init(_ name: String, size: CGFloat = 22) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
            .foregroundStyle(Ink.inverse)
            .frame(width: size, height: size)
            .background(Ink.primary, in: Circle())
            .accessibilityHidden(true)
    }
}

public struct DetailRow<Value: View>: View {
    let label: Text
    let value: Value

    public init(_ label: Text, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                label.type(.callout).foregroundStyle(Ink.secondary)
                Spacer(minLength: Space.s)
                value.type(.callout, weight: .medium).foregroundStyle(Ink.primary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                label.type(.callout).foregroundStyle(Ink.secondary)
                value.type(.callout, weight: .medium).foregroundStyle(Ink.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }
}

public struct Hairline: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(Ink.hairline).frame(height: 0.75)
    }
}

public struct StatusDot: View {
    let color: Color
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(Circle().fill(color.opacity(0.35)).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width * 1.4)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

public struct BogoMark: View {
    var size: CGFloat = 28

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(Ink.primary)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Ink.inverse)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
