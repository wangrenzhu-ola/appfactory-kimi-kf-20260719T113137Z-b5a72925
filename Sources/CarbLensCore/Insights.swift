import Foundation

/// One point on the weekly carb/impact trend chart.
public struct DailyTrendPoint: Equatable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var totalCarbs: Double
    public var highImpactMeals: Int
    public var mealCount: Int

    public init(date: Date, totalCarbs: Double, highImpactMeals: Int, mealCount: Int) {
        self.date = date
        self.totalCarbs = totalCarbs
        self.highImpactMeals = highImpactMeals
        self.mealCount = mealCount
    }
}

/// Aggregates confirmed meals into daily trend points for the trends surface.
public struct TrendAggregator {
    public init() {}

    /// Returns one point per day for the trailing `days` window ending at `end`.
    public func dailyPoints(meals: [MealLog], endingAt end: Date, days: Int, calendar: Calendar = .current) -> [DailyTrendPoint] {
        let endDay = calendar.startOfDay(for: end)
        return (0..<max(days, 1)).compactMap { offset -> DailyTrendPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { return nil }
            let dayMeals = meals.filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }
            return DailyTrendPoint(
                date: day,
                totalCarbs: dayMeals.reduce(0) { $0 + $1.totalCarbsGrams }.rounded(toPlaces: 1),
                highImpactMeals: dayMeals.filter { $0.impactLevel == .high }.count,
                mealCount: dayMeals.count
            )
        }.sorted { $0.date < $1.date }
    }

    public func weeklyTotals(meals: [MealLog], weeks: Int, endingAt end: Date, calendar: Calendar = .current) -> [DailyTrendPoint] {
        var result: [DailyTrendPoint] = []
        let endDay = calendar.startOfDay(for: end)
        for week in (0..<max(weeks, 1)).reversed() {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * (week + 1) + 1, to: endDay) else { continue }
            let weekMeals = meals.filter { $0.capturedAt >= weekStart && $0.capturedAt <= end }
            result.append(DailyTrendPoint(
                date: weekStart,
                totalCarbs: weekMeals.reduce(0) { $0 + $1.totalCarbsGrams }.rounded(toPlaces: 1),
                highImpactMeals: weekMeals.filter { $0.impactLevel == .high }.count,
                mealCount: weekMeals.count
            ))
        }
        return result
    }
}

/// Generates the weekly insight card from the user's own confirmed log.
/// Fully deterministic and on-device.
public struct InsightsEngine {
    public init() {}

    /// Builds the insight card for the trailing 7-day window, or nil when
    /// there is not enough data to say anything useful.
    public func weeklyInsight(meals: [MealLog], endingAt end: Date, calendar: Calendar = .current) -> InsightCard? {
        let endDay = calendar.startOfDay(for: end)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: endDay) else { return nil }
        let weekMeals = meals.filter { $0.capturedAt >= weekStart && $0.capturedAt <= end }
        guard weekMeals.count >= 3 else { return nil }

        let highMeals = weekMeals.filter { $0.impactLevel == .high }
        let totalCarbs = weekMeals.reduce(0) { $0 + $1.totalCarbsGrams }
        let highCarbs = highMeals.reduce(0) { $0 + $1.totalCarbsGrams }
        let highShare = totalCarbs > 0 ? highCarbs / totalCarbs : 0

        // Find the most repeated high-impact food so the card is concrete.
        var frequency: [String: Int] = [:]
        for meal in highMeals {
            for item in meal.items where GlucoseImpactLevel.level(forCarbLoad: item.carbsGrams) != .low {
                frequency[item.name, default: 0] += 1
            }
        }
        let topFood = frequency.max { $0.value < $1.value }?.key

        let percent = Int((highShare * 100).rounded())
        let title: String
        let body: String
        if highShare >= 0.5, let food = topFood {
            title = "High-impact meals drove your week"
            body = "\(percent)% of this week's carbs came from high-impact meals. \(food) showed up most often — try a smaller portion or a lower-impact swap next time it is on the plate."
        } else if highShare >= 0.5 {
            title = "High-impact meals drove your week"
            body = "\(percent)% of this week's carbs came from high-impact meals. Reviewing portions before you eat is the fastest lever you have."
        } else if let food = topFood {
            title = "Your week stayed mostly steady"
            body = "Only \(percent)% of this week's carbs came from high-impact meals. Watch \(food) — it was your most frequent high-impact item."
        } else {
            title = "Your week stayed mostly steady"
            body = "Only \(percent)% of this week's carbs came from high-impact meals. Keep the pattern going."
        }
        return InsightCard(
            weekStart: weekStart,
            title: title,
            body: body,
            relatedMealIDs: highMeals.map(\.id)
        )
    }
}

public enum ProfileStoreError: Error, Equatable {
    case persistenceFailed
}

/// Persists the user profile next to the meal log.
public final class ProfileStore: ObservableObject {
    @Published public private(set) var profile: UserProfile
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("user_profile.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = UserProfile()
        }
    }

    public func update(_ mutate: (inout UserProfile) -> Void) throws {
        var copy = profile
        mutate(&copy)
        try persist(copy)
        profile = copy
    }

    private func persist(_ value: UserProfile) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
        } catch {
            throw ProfileStoreError.persistenceFailed
        }
    }
}
