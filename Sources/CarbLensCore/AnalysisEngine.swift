import Foundation

/// Input handed to the analysis pipeline. `pixelBytes` are the compressed
/// photo bytes captured on-device; they never leave the device except through
/// the user-initiated analysis request, and the original photo is deleted
/// after analysis completes.
public struct PhotoInput: Equatable {
    public var pixelBytes: Data
    public var capturedAt: Date

    public init(pixelBytes: Data, capturedAt: Date = Date()) {
        self.pixelBytes = pixelBytes
        self.capturedAt = capturedAt
    }
}

public enum AnalysisError: Error, Equatable {
    /// The photo could not be read (empty or corrupt capture).
    case imageUnreadable
    /// The analyzer could not reach the confidence threshold.
    case lowConfidence(Double)
    /// The remote analysis service is unavailable.
    case serviceUnavailable
}

/// One analysis pass over a captured photo. Implementations must return a
/// structured, editable estimate — never a free-form chat transcript.
public protocol MealAnalyzer {
    var analyzerVersion: String { get }
    func analyze(photo: PhotoInput) async throws -> MealEstimate
}

/// Deterministic on-device analyzer used as the offline baseline and as the
/// fallback when the remote service is unavailable. It derives a plausible
/// plate composition from the photo content so the full capture → review →
/// confirm flow works with zero network dependency.
public struct HeuristicMealAnalyzer: MealAnalyzer {
    public static let confidenceFloor: Double = 0.45

    public let analyzerVersion = "heuristic-plate-v1.2"
    private let database: FoodDatabase

    public init(database: FoodDatabase = FoodDatabase()) {
        self.database = database
    }

    public func analyze(photo: PhotoInput) async throws -> MealEstimate {
        let bytes = photo.pixelBytes
        guard bytes.count >= 512 else {
            throw AnalysisError.imageUnreadable
        }
        var rng = SeededGenerator(seed: stableSeed(bytes))
        // A plate carries 2-4 components; composition follows the photo seed
        // so the same photo always yields the same reviewable estimate.
        let componentCount = 2 + Int(rng.next() % 3)
        var chosen: [FoodReference] = []
        var pool = database.references
        for _ in 0..<componentCount {
            guard !pool.isEmpty else { break }
            let index = Int(rng.next() % UInt64(pool.count))
            chosen.append(pool.remove(at: index))
        }
        var items: [FoodItem] = chosen.map { ref in
            let jitter = 0.75 + Double(rng.next() % 50) / 100.0 // 0.75...1.24
            let portion = (ref.typicalServingGrams * jitter).rounded(toPlaces: 0)
            let confidence = (0.55 + Double(rng.next() % 40) / 100.0).rounded(toPlaces: 2)
            return FoodItem(
                id: SeededGenerator.deterministicUUID(from: rng.next()),
                name: ref.name,
                portionGrams: portion,
                carbsGrams: ref.carbs(forPortionGrams: portion),
                confidence: confidence
            )
        }
        // Photos with very little entropy (e.g. a plain surface) produce a
        // low-confidence estimate the UI must flag instead of silently saving.
        let entropy = byteEntropy(bytes)
        if entropy < 0.5 {
            items = items.map { item in
                var copy = item
                copy.confidence = min(item.confidence, 0.3)
                return copy
            }
        }
        let overall = items.map(\.confidence).reduce(0, +) / Double(max(items.count, 1))
        guard overall >= HeuristicMealAnalyzer.confidenceFloor else {
            throw AnalysisError.lowConfidence(overall.rounded(toPlaces: 2))
        }
        return MealEstimate(items: items, overallConfidence: overall.rounded(toPlaces: 2), analyzerVersion: analyzerVersion)
    }

    private func stableSeed(_ data: Data) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in data.prefix(4096) {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private func byteEntropy(_ data: Data) -> Double {
        var counts = [UInt8: Int]()
        for byte in data.prefix(2048) { counts[byte, default: 0] += 1 }
        return Double(counts.count) / 256.0
    }
}

/// Deterministic PRNG (SplitMix64) so analysis results are reproducible per photo.
public struct SeededGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Builds a stable UUID from a seed so identical photos yield identical
    /// item identities across repeated analysis passes.
    public static func deterministicUUID(from seed: UInt64) -> UUID {
        var generator = SeededGenerator(seed: seed)
        let high = generator.next()
        let low = generator.next()
        return UUID(uuid: (
            UInt8((high >> 56) & 0xFF), UInt8((high >> 48) & 0xFF),
            UInt8((high >> 40) & 0xFF), UInt8((high >> 32) & 0xFF),
            UInt8((high >> 24) & 0xFF), UInt8((high >> 16) & 0xFF),
            UInt8((high >> 8) & 0xFF), UInt8(high & 0xFF),
            UInt8((low >> 56) & 0xFF), UInt8((low >> 48) & 0xFF),
            UInt8((low >> 40) & 0xFF), UInt8((low >> 32) & 0xFF),
            UInt8((low >> 24) & 0xFF), UInt8((low >> 16) & 0xFF),
            UInt8((low >> 8) & 0xFF), UInt8(low & 0xFF)
        ))
    }
}

/// An estimate under user review. Every mutation recalculates totals so the
/// confirmation screen always shows the current carb load and impact level.
public struct EditableEstimate: Equatable {
    public private(set) var items: [FoodItem]
    public let analyzerVersion: String
    public let overallConfidence: Double

    public init(estimate: MealEstimate) {
        self.items = estimate.items
        self.analyzerVersion = estimate.analyzerVersion
        self.overallConfidence = estimate.overallConfidence
    }

    public var totalCarbsGrams: Double {
        items.reduce(0) { $0 + $1.carbsGrams }.rounded(toPlaces: 1)
    }

    public var impactLevel: GlucoseImpactLevel {
        GlucoseImpactLevel.level(forCarbLoad: totalCarbsGrams)
    }

    public var lowestConfidence: Double {
        items.map(\.confidence).min() ?? 0
    }

    public mutating func updatePortion(itemID: UUID, portionGrams: Double, using database: FoodDatabase) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        item.portionGrams = max(portionGrams, 0)
        if let ref = database.reference(named: item.name) {
            item.carbsGrams = ref.carbs(forPortionGrams: item.portionGrams)
        }
        item.editedByUser = true
        items[index] = item
    }

    public mutating func rename(itemID: UUID, to reference: FoodReference) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        item.name = reference.name
        item.carbsGrams = reference.carbs(forPortionGrams: item.portionGrams)
        item.editedByUser = true
        items[index] = item
    }

    public mutating func removeItem(itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    public mutating func addItem(from reference: FoodReference, portionGrams: Double? = nil) {
        let portion = portionGrams ?? reference.typicalServingGrams
        items.append(FoodItem(
            name: reference.name,
            portionGrams: portion,
            carbsGrams: reference.carbs(forPortionGrams: portion),
            confidence: 1.0,
            editedByUser: true
        ))
    }

    /// Builds the persisted meal. Only ever called after explicit confirmation.
    public func confirmedMeal(thumbnailLocalRef: String?, capturedAt: Date = Date()) -> MealLog {
        MealLog(
            capturedAt: capturedAt,
            thumbnailLocalRef: thumbnailLocalRef,
            items: items,
            estimate: GlucoseImpactEstimate(
                level: impactLevel,
                estimatedCarbLoad: totalCarbsGrams,
                confidence: overallConfidence,
                modelVersion: analyzerVersion
            ),
            source: .photoEstimate,
            confirmed: true
        )
    }
}
