import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Budget ring (Today)

struct BudgetRingView: View {
    let summary: DailySummary

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.tealSoft, lineWidth: 14)
            Circle()
                .trim(from: 0, to: summary.budgetFraction)
                .stroke(summary.isOverBudget ? Theme.amber : Theme.teal,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: summary.budgetFraction)
            VStack(spacing: 2) {
                Text(summary.isOverBudget
                     ? String(format: "%.0f", abs(summary.remaining))
                     : String(format: "%.0f", summary.remaining))
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundColor(summary.isOverBudget ? Theme.amber : Theme.ink)
                Text(summary.isOverBudget ? Copy.Home.budgetOver : Copy.Home.budgetRemaining)
                    .font(.caption)
                    .foregroundColor(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Copy.Accessibility.budgetRing))
        .accessibilityValue(Text(Copy.Accessibility.budgetRingValue(
            remaining: Int(summary.remaining), budget: Int(summary.budgetCarbs))))
    }
}

// MARK: - Impact badge

struct ImpactBadge: View {
    let level: GlucoseImpactLevel

    var body: some View {
        Text(level.displayName)
            .font(.caption.weight(.semibold))
            .foregroundColor(Theme.impactColor(level))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.impactBackground(level))
            .cornerRadius(Theme.chipRadius)
            .accessibilityLabel(Text("\(Copy.Accessibility.impactBadge): \(level.displayName)"))
    }
}

// MARK: - Empty state

struct EmptyStateView<Illustration: View>: View {
    let title: String
    let message: String
    let ctaTitle: String
    let ctaAction: () -> Void
    let illustration: Illustration

    init(title: String, message: String, ctaTitle: String,
         ctaAction: @escaping () -> Void,
         @ViewBuilder illustration: () -> Illustration) {
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.ctaAction = ctaAction
        self.illustration = illustration()
    }

    var body: some View {
        VStack(spacing: 18) {
            illustration
                .frame(height: 160)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: ctaAction) {
                Label(ctaTitle, systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.teal)
                    .cornerRadius(Theme.cardRadius)
            }
            .accessibilityLabel(Text(ctaTitle))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Error banner (recoverable, keeps user content)

struct ErrorBanner: View {
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.amber)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onRetry) {
                Text(retryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.teal)
            }
            .accessibilityLabel(Text(retryTitle))
        }
        .padding(12)
        .background(Theme.amberSoft)
        .cornerRadius(Theme.chipRadius)
    }
}

// MARK: - Scanning overlay (slot_analysis_scan_overlay)

/// Analysis in-progress surface: a sweep line over the plate silhouette and
/// the mandated progress copy.
struct ScanOverlayView: View {
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                PlateIllustration()
                    .frame(height: 180)
                    .opacity(0.9)
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Theme.teal.opacity(0.35))
                        .frame(height: 3)
                        .offset(y: sweep ? proxy.size.height - 3 : 0)
                        .animation(Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: sweep)
                }
                .frame(height: 180)
            }
            Text(Copy.Capture.analyzing)
                .font(.headline)
                .foregroundColor(Theme.ink)
                .accessibilityLabel(Text(Copy.Capture.analyzing))
        }
        .onAppear { sweep = true }
    }
}

// MARK: - Illustration slots (product-specific, drawn in code, replaceable)

/// slot_hero_empty_log: overhead empty plate with a viewfinder frame.
struct PlateIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            Circle()
                .stroke(Theme.tealSoft, lineWidth: 10)
                .padding(18)
            ViewfinderCorners()
                .stroke(Theme.teal, lineWidth: 3)
                .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 22
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // top-right
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // bottom-left
        path.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return path
    }
}

/// slot_onboarding_glucose_curve: steady vs. spiky curve explaining levels.
struct GlucoseCurveIllustration: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                curve(in: rect.insetBy(dx: 20, dy: 24), spiky: true)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
                curve(in: rect.insetBy(dx: 20, dy: 24), spiky: false)
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    private func curve(in rect: CGRect, spiky: Bool) -> Path {
        var path = Path()
        let steps = 24
        for step in 0...steps {
            let x = rect.minX + rect.width * CGFloat(step) / CGFloat(steps)
            let t = CGFloat(step) / CGFloat(steps)
            let base = rect.midY
            let amplitude = spiky ? rect.height * 0.42 : rect.height * 0.14
            let y: CGFloat
            if spiky {
                y = base - amplitude * abs(sin(t * .pi * 3))
            } else {
                y = base - amplitude * sin(t * .pi * 2)
            }
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

/// slot_insights_weekly_card: plate-and-trend composition, 16:9.
struct WeeklyInsightIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.tealSoft)
            HStack(spacing: 16) {
                Circle()
                    .fill(Theme.surface)
                    .overlay(Circle().stroke(Theme.teal, lineWidth: 3))
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.teal).frame(width: 90, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.teal.opacity(0.5)).frame(width: 130, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.amber.opacity(0.6)).frame(width: 60, height: 8)
                }
                Spacer()
            }
            .padding(16)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}

// MARK: - Thumbnail (compressed photo kept for log context)

struct MealThumbnail: View {
    @EnvironmentObject private var mealStore: MealStore
    let ref: String?
    var size: CGFloat = 44

    var body: some View {
        #if canImport(UIKit)
        if let ref = ref,
           let data = mealStore.thumbnailData(named: ref),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .cornerRadius(8)
                .clipped()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.tealSoft)
            Image(systemName: "fork.knife")
                .foregroundColor(Theme.teal)
        }
        .frame(width: size, height: size)
    }
}
