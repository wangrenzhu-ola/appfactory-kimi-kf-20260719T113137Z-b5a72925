import SwiftUI

/// /trends — weekly carb and glucose-impact charts with week/month toggle.
struct TrendsView: View {
    @EnvironmentObject private var mealStore: MealStore
    let onSnap: () -> Void
    @State private var range: TrendRange = .week

    enum TrendRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if mealStore.meals.isEmpty {
                    EmptyStateView(
                        title: Copy.Trends.emptyTitle,
                        message: Copy.Trends.emptyBody,
                        ctaTitle: Copy.Trends.emptyCTA,
                        ctaAction: onSnap
                    ) {
                        GlucoseCurveIllustration()
                    }
                } else {
                    Picker("", selection: $range) {
                        ForEach(TrendRange.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    let points = TrendAggregator().dailyPoints(
                        meals: mealStore.meals, endingAt: Date(), days: range.days)
                    carbsChart(points: points)
                    impactChart(points: points)
                }
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Trends.title, displayMode: .large)
    }

    private func carbsChart(points: [DailyTrendPoint]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(Copy.Trends.carbsHeading)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                BarChart(
                    values: points.map(\.totalCarbs),
                    labels: points.map { point in shortDate(point.date) },
                    color: Theme.teal,
                    valueSuffix: Copy.Trends.gramsShort
                )
            }
        }
    }

    private func impactChart(points: [DailyTrendPoint]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(Copy.Trends.impactHeading)
                    .font(.headline)
                    .foregroundColor(Theme.ink)
                BarChart(
                    values: points.map { Double($0.highImpactMeals) },
                    labels: points.map { point in shortDate(point.date) },
                    color: Theme.amber,
                    valueSuffix: ""
                )
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = range == .week ? "EEE" : "M/d"
        return formatter.string(from: date)
    }
}

/// Simple, honest bar chart — no decoration, labeled values.
struct BarChart: View {
    let values: [Double]
    let labels: [String]
    let color: Color
    let valueSuffix: String

    var body: some View {
        let maxValue = values.max() ?? 1
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    Text(value.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(value))\(valueSuffix)"
                         : String(format: "%.1f%@", value, valueSuffix))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(value > 0 ? 1 : 0.2))
                        .frame(height: max(CGFloat(value / (maxValue > 0 ? maxValue : 1)) * 120, 4))
                    Text(labels[index])
                        .font(.caption2)
                        .foregroundColor(Theme.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("\(labels[index]): \(Int(value))\(valueSuffix)"))
            }
        }
        .frame(height: 170)
    }
}

/// /insights — weekly generated insight card from the user's own log.
struct InsightsView: View {
    @EnvironmentObject private var mealStore: MealStore
    let onSnap: () -> Void
    @State private var markedHelpfulIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let insight = InsightsEngine().weeklyInsight(meals: mealStore.meals, endingAt: Date())
                if let insight = insight {
                    VStack(alignment: .leading, spacing: 12) {
                        WeeklyInsightIllustration()
                        Text(Copy.Insights.weeklyHeading)
                            .font(.caption)
                            .foregroundColor(Theme.inkSoft)
                        Text(insight.title)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(Theme.ink)
                        Text(insight.body)
                            .font(.subheadline)
                            .foregroundColor(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        if !insight.relatedMealIDs.isEmpty {
                            Text(Copy.Insights.relatedMeals)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.inkSoft)
                            ForEach(insight.relatedMealIDs, id: \.self) { id in
                                if let meal = mealStore.meal(id: id) {
                                    NavigationLink(destination: MealDetailView(mealID: meal.id)) {
                                        MealRow(meal: meal)
                                    }
                                }
                            }
                        }
                        Button(action: { markedHelpfulIDs.insert(insight.id) }) {
                            Label(
                                markedHelpfulIDs.contains(insight.id) ? "Marked" : Copy.Insights.helpful,
                                systemImage: markedHelpfulIDs.contains(insight.id) ? "hand.thumbsup.fill" : "hand.thumbsup"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(markedHelpfulIDs.contains(insight.id) ? .white : Theme.teal)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(markedHelpfulIDs.contains(insight.id) ? Theme.teal : Theme.tealSoft)
                            .cornerRadius(Theme.chipRadius)
                        }
                        .accessibilityLabel(Text(Copy.Insights.helpful))
                    }
                    .padding()
                    .background(Theme.surface)
                    .cornerRadius(Theme.cardRadius)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                } else {
                    EmptyStateView(
                        title: Copy.Insights.emptyTitle,
                        message: Copy.Insights.emptyBody,
                        ctaTitle: Copy.Insights.emptyCTA,
                        ctaAction: onSnap
                    ) {
                        WeeklyInsightIllustration()
                    }
                }
            }
            .padding()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitle(Copy.Insights.title, displayMode: .large)
    }
}
