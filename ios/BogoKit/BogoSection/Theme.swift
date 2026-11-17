import SwiftUI
import UIKit

public enum Ink {
    public static let canvas = dynamic(light: 0xFFFFFF, dark: 0x0A0A0B)
    public static let surface = canvas
    public static let raised = dynamic(light: 0xF3F3F4, dark: 0x1C1C1F)
    public static let hairline = dynamic(light: 0x0B0B0C, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.11)
    public static let primary = dynamic(light: 0x0B0B0C, dark: 0xF4F4F2)
    public static let secondary = dynamic(light: 0x6B6B70, dark: 0x9C9CA2)
    public static let tertiary = dynamic(light: 0x9E9EA3, dark: 0x66666C)
    public static let inverse = dynamic(light: 0xFFFFFF, dark: 0x0B0B0C)
    public static let positive = dynamic(light: 0x13985A, dark: 0x3DD68C)
    public static let negative = dynamic(light: 0xD23F3F, dark: 0xFF6B6B)
    public static let warning = dynamic(light: 0xB25E0B, dark: 0xF2B252)

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
    public static let sheet: CGFloat = 32
    public static let picture: CGFloat = 14
    public static let field: CGFloat = 12
}

public enum TypeRole {
    case display, title, title2, headline, body, callout, label, caption, mono

    var size: CGFloat {
        switch self {
        case .display: return 46
        case .title: return 28
        case .title2: return 22
        case .headline: return 17
        case .body: return 17
        case .callout: return 15
        case .label: return 14
        case .caption: return 12.5
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
        case .mono: return .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: return -1.4
        case .title: return -0.7
        case .title2: return -0.5
        case .headline: return -0.25
        case .body: return -0.2
        case .callout: return -0.1
        case .label: return -0.05
        case .caption: return 0
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

    public func canvas() -> some View {
        background(Ink.canvas.ignoresSafeArea())
    }

    public func statusScrim() -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                LinearGradient(stops: [.init(color: Ink.canvas, location: 0), .init(color: Ink.canvas.opacity(0.9), location: 0.55),
                                       .init(color: Ink.canvas.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.safeAreaInsets.top + 16)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    public func bogoList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, Space.xxs, for: .scrollContent)
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
                value.type(.callout).foregroundStyle(Ink.primary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                label.type(.callout).foregroundStyle(Ink.secondary)
                value.type(.callout).foregroundStyle(Ink.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

public struct Hairline: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(Ink.hairline).frame(height: 0.75)
    }
}

public struct SectionHeader: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .type(.headline)
            .foregroundStyle(Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct FieldLabel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .type(.label)
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct RowSection<Content: View>: View {
    let title: String?
    let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SectionHeader(title).padding(.bottom, Space.xs)
                Hairline()
            }
            content
        }
    }
}

public struct Chevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Ink.tertiary)
            .accessibilityHidden(true)
    }
}

public struct DestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.headline)
            .foregroundStyle(Ink.negative)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Ink.raised, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

public struct DoneMark: View {
    var size: CGFloat = 88
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 88) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ring)
                .stroke(Ink.positive, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(Ink.positive, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.36, height: size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                ring = 1
                check = 1
            } else {
                withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
                withAnimation(.easeOut(duration: 0.3).delay(0.3)) { check = 1 }
            }
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
