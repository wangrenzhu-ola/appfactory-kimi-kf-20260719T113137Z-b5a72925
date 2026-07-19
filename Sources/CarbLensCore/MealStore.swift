import Foundation

public enum MealStoreError: Error, Equatable {
    case mealNotFound
    case persistenceFailed(String)
    case deleteRejectedUnconfirmed
}

/// Storage backend so tests can inject failure paths without touching disk.
public protocol MealStorage {
    func loadMeals() throws -> [MealLog]
    func saveMeals(_ meals: [MealLog]) throws
    func loadThumbnail(named: String) -> Data?
    func saveThumbnail(_ data: Data, named: String) throws
    func deleteThumbnail(named: String)
}

/// JSON file storage in an injected directory (Documents in the app,
/// a temporary directory in tests).
public final class JSONMealStorage: MealStorage {
    private let directory: URL
    private let fileName = "meal_logs.json"
    private let thumbnailsFolder = "thumbnails"

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }
    private var thumbnailsURL: URL { directory.appendingPathComponent(thumbnailsFolder) }

    public func loadMeals() throws -> [MealLog] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: string) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date")
            }
            return try decoder.decode([MealLog].self, from: data)
        } catch {
            throw MealStoreError.persistenceFailed("read")
        }
    }

    public func saveMeals(_ meals: [MealLog]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(formatter.string(from: date))
            }
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(meals)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MealStoreError.persistenceFailed("write")
        }
    }

    public func loadThumbnail(named: String) -> Data? {
        let url = thumbnailsURL.appendingPathComponent(named)
        return try? Data(contentsOf: url)
    }

    public func saveThumbnail(_ data: Data, named: String) throws {
        do {
            try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
            try data.write(to: thumbnailsURL.appendingPathComponent(named), options: .atomic)
        } catch {
            throw MealStoreError.persistenceFailed("thumbnail")
        }
    }

    public func deleteThumbnail(named: String) {
        try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(named))
    }
}

/// Application-facing meal store. Owns the confirmed log; unconfirmed
/// estimates never reach storage.
public final class MealStore: ObservableObject {
    @Published public private(set) var meals: [MealLog] = []
    private let storage: MealStorage

    public init(storage: MealStorage) {
        self.storage = storage
        self.meals = (try? storage.loadMeals()) ?? []
    }

    public var sortedMeals: [MealLog] {
        meals.sorted { $0.capturedAt > $1.capturedAt }
    }

    public func meal(id: UUID) -> MealLog? {
        meals.first { $0.id == id }
    }

    /// Saves a confirmed meal. New and edited meals flow through here; the
    /// caller keeps its editing state so a failure can be retried without
    /// losing user input.
    @discardableResult
    public func save(_ meal: MealLog) throws -> MealLog {
        guard meal.confirmed else { throw MealStoreError.deleteRejectedUnconfirmed }
        var updated = meals
        if let index = updated.firstIndex(where: { $0.id == meal.id }) {
            updated[index] = meal
        } else {
            updated.append(meal)
        }
        try storage.saveMeals(updated)
        meals = updated
        return meal
    }

    @discardableResult
    public func delete(id: UUID) throws -> MealLog {
        guard let index = meals.firstIndex(where: { $0.id == id }) else {
            throw MealStoreError.mealNotFound
        }
        let removed = meals[index]
        var updated = meals
        updated.remove(at: index)
        try storage.saveMeals(updated)
        meals = updated
        if let thumb = removed.thumbnailLocalRef {
            storage.deleteThumbnail(named: thumb)
        }
        return removed
    }

    public func deleteAll() throws {
        try storage.saveMeals([])
        meals = []
    }

    public func thumbnailData(named: String) -> Data? {
        storage.loadThumbnail(named: named)
    }

    public func saveThumbnail(_ data: Data, named: String) throws {
        try storage.saveThumbnail(data, named: named)
    }

    // MARK: - Summaries

    public func meals(on day: Date, calendar: Calendar = .current) -> [MealLog] {
        sortedMeals.filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }
    }

    public func dailySummary(for day: Date, budget: Double, calendar: Calendar = .current) -> DailySummary {
        let dayMeals = meals(on: day, calendar: calendar)
        return DailySummary(
            date: calendar.startOfDay(for: day),
            totalCarbs: dayMeals.reduce(0) { $0 + $1.totalCarbsGrams }.rounded(toPlaces: 1),
            budgetCarbs: budget,
            highImpactMeals: dayMeals.filter { $0.impactLevel == .high }.count,
            mealCount: dayMeals.count
        )
    }
}
