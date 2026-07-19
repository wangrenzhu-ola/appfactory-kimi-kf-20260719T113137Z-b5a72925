import SwiftUI

/// CarbLens design tokens. One coherent direction: clinical calm meets plate
/// warmth — deep teal for trust and action, a warm paper background, and a
/// single amber reserved for high glucose impact. No gradients, no glow,
/// no medical-red imagery.
public enum Theme {

    public static let canvas = Color(red: 0.980, green: 0.969, blue: 0.949)      // #FAF7F2 warm paper
    public static let surface = Color.white
    public static let ink = Color(red: 0.11, green: 0.14, blue: 0.15)
    public static let inkSoft = Color(red: 0.38, green: 0.42, blue: 0.43)
    public static let teal = Color(red: 0.055, green: 0.486, blue: 0.482)        // #0E7C7B
    public static let tealSoft = Color(red: 0.87, green: 0.94, blue: 0.94)
    public static let amber = Color(red: 0.878, green: 0.478, blue: 0.247)       // #E07A3F
    public static let amberSoft = Color(red: 0.99, green: 0.92, blue: 0.87)
    public static let leaf = Color(red: 0.243, green: 0.557, blue: 0.353)        // #3E8E5A
    public static let leafSoft = Color(red: 0.89, green: 0.95, blue: 0.90)

    public static let cardRadius: CGFloat = 14
    public static let chipRadius: CGFloat = 10

    public static func impactColor(_ level: GlucoseImpactLevel) -> Color {
        switch level {
        case .low: return leaf
        case .medium: return teal
        case .high: return amber
        }
    }

    public static func impactBackground(_ level: GlucoseImpactLevel) -> Color {
        switch level {
        case .low: return leafSoft
        case .medium: return tealSoft
        case .high: return amberSoft
        }
    }
}

/// Numeric emphasis for carb grams: monospaced digits read as data, not decoration.
public struct GramsText: View {
    let value: Double
    let unit: String

    public init(_ value: Double, unit: String = "g") {
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(unit)
                .font(.caption)
                .foregroundColor(Theme.inkSoft)
        }
    }
}

public struct Card<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .cornerRadius(Theme.cardRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}
