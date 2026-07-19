import Foundation

/// Glucose impact level assigned to a meal or a single food item.
/// This is an informational estimate, never a medical diagnosis.
public enum GlucoseImpactLevel: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: GlucoseImpactLevel, rhs: GlucoseImpactLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .low: return "Low impact"
        case .medium: return "Medium impact"
        case .high: return "High impact"
        }
    }
}

/// One recognized or manually entered food entry inside a meal.
public struct FoodItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var portionGrams: Double
    public var carbsGrams: Double
    public var confidence: Double
    public var editedByUser: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        portionGrams: Double,
        carbsGrams: Double,
        confidence: Double,
        editedByUser: Bool = false
    ) {
        self.id = id
        self.name = name
        self.portionGrams = portionGrams
        self.carbsGrams = carbsGrams
        self.confidence = confidence
        self.editedByUser = editedByUser
    }
}

/// Structured estimate produced by the analysis pipeline for one photo.
/// Never written to the log until the user explicitly confirms it.
public struct MealEstimate: Equatable {
    public var items: [FoodItem]
    public var overallConfidence: Double
    public var analyzerVersion: String

    public init(items: [FoodItem], overallConfidence: Double, analyzerVersion: String) {
        self.items = items
        self.overallConfidence = overallConfidence
        self.analyzerVersion = analyzerVersion
    }

    public var totalCarbsGrams: Double {
        items.reduce(0) { $0 + $1.carbsGrams }
    }

    /// Impact is derived from the carb load so edits stay consistent.
    public var impactLevel: GlucoseImpactLevel {
        GlucoseImpactLevel.level(forCarbLoad: totalCarbsGrams)
    }
}

public extension GlucoseImpactLevel {
    /// Carb-load thresholds shared by analysis, editing and summaries so every
    /// surface agrees on the level for the same meal.
    static func level(forCarbLoad grams: Double) -> GlucoseImpactLevel {
        switch grams {
        case ..<25: return .low
        case 25..<60: return .medium
        default: return .high
        }
    }
}

/// Persisted estimate metadata attached to a saved meal.
public struct GlucoseImpactEstimate: Codable, Equatable, Identifiable {
    public var id: UUID
    public var level: GlucoseImpactLevel
    public var estimatedCarbLoad: Double
    public var confidence: Double
    public var modelVersion: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        level: GlucoseImpactLevel,
        estimatedCarbLoad: Double,
        confidence: Double,
        modelVersion: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.level = level
        self.estimatedCarbLoad = estimatedCarbLoad
        self.confidence = confidence
        self.modelVersion = modelVersion
        self.createdAt = createdAt
    }
}

/// A confirmed, persisted meal record.
public struct MealLog: Codable, Equatable, Identifiable {
    public var id: UUID
    public var capturedAt: Date
    /// Compressed thumbnail kept for log display. The original photo is
    /// deleted right after analysis and is never persisted.
    public var thumbnailLocalRef: String?
    public var items: [FoodItem]
    public var estimate: GlucoseImpactEstimate?
    public var source: Source
    public var confirmed: Bool

    public enum Source: String, Codable {
        case photoEstimate
        case manual
    }

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        thumbnailLocalRef: String? = nil,
        items: [FoodItem],
        estimate: GlucoseImpactEstimate? = nil,
        source: Source,
        confirmed: Bool
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.thumbnailLocalRef = thumbnailLocalRef
        self.items = items
        self.estimate = estimate
        self.source = source
        self.confirmed = confirmed
    }

    public var totalCarbsGrams: Double {
        items.reduce(0) { $0 + $1.carbsGrams }
    }

    public var impactLevel: GlucoseImpactLevel {
        estimate?.level ?? GlucoseImpactLevel.level(forCarbLoad: totalCarbsGrams)
    }
}

/// Aggregated view of one day used by the budget ring and trends.
public struct DailySummary: Equatable {
    public var date: Date
    public var totalCarbs: Double
    public var budgetCarbs: Double
    public var highImpactMeals: Int
    public var mealCount: Int

    public init(date: Date, totalCarbs: Double, budgetCarbs: Double, highImpactMeals: Int, mealCount: Int) {
        self.date = date
        self.totalCarbs = totalCarbs
        self.budgetCarbs = budgetCarbs
        self.highImpactMeals = highImpactMeals
        self.mealCount = mealCount
    }

    public var remaining: Double { budgetCarbs - totalCarbs }
    public var isOverBudget: Bool { remaining < 0 }
    /// 0...1 fraction for the budget ring.
    public var budgetFraction: Double {
        guard budgetCarbs > 0 else { return 0 }
        return min(max(totalCarbs / budgetCarbs, 0), 1)
    }
}

public enum GlucoseGoalType: String, Codable, CaseIterable {
    case prediabetesSteady
    case reduceSpikes
    case generalAwareness

    public var displayName: String {
        switch self {
        case .prediabetesSteady: return "Keep levels steady"
        case .reduceSpikes: return "Avoid spikes"
        case .generalAwareness: return "Build awareness"
        }
    }
}

public struct UserProfile: Codable, Equatable {
    public var id: UUID
    public var goalType: GlucoseGoalType
    public var dailyCarbBudget: Double
    public var units: String
    public var onboardingCompleted: Bool

    public init(
        id: UUID = UUID(),
        goalType: GlucoseGoalType = .prediabetesSteady,
        dailyCarbBudget: Double = 130,
        units: String = "grams",
        onboardingCompleted: Bool = false
    ) {
        self.id = id
        self.goalType = goalType
        self.dailyCarbBudget = dailyCarbBudget
        self.units = units
        self.onboardingCompleted = onboardingCompleted
    }
}

public enum SubscriptionTier: String, Codable {
    case free
    case premiumMonthly
    case premiumYearly
}

public struct SubscriptionEntitlement: Codable, Equatable {
    public var tier: SubscriptionTier
    public var expiresAt: Date?
    public var willRenew: Bool
    public var originalTransactionID: String?

    public init(
        tier: SubscriptionTier = .free,
        expiresAt: Date? = nil,
        willRenew: Bool = false,
        originalTransactionID: String? = nil
    ) {
        self.tier = tier
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.originalTransactionID = originalTransactionID
    }

    public var isPremium: Bool { tier != .free }
}

/// Weekly generated insight card.
public struct InsightCard: Equatable, Identifiable {
    public var id: UUID
    public var weekStart: Date
    public var title: String
    public var body: String
    public var relatedMealIDs: [UUID]
    public var markedHelpful: Bool

    public init(id: UUID = UUID(), weekStart: Date, title: String, body: String, relatedMealIDs: [UUID], markedHelpful: Bool = false) {
        self.id = id
        self.weekStart = weekStart
        self.title = title
        self.body = body
        self.relatedMealIDs = relatedMealIDs
        self.markedHelpful = markedHelpful
    }
}
