import XCTest
@testable import CarbLensCore

/// Covers the capture → analyze → review → confirm → log core flow semantics
/// that the UI binds to (REQ-CAP-01, REQ-AI-01..03, REQ-LOG-01, REQ-EDIT-01,
/// REQ-DEL-01, REQ-ERR-01, REQ-TREND-01, REQ-IAP-01, REQ-MD-01).
final class CarbLensCoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("carblens-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePhoto(byteCount: Int = 4096, varied: Bool = true) -> PhotoInput {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices {
            bytes[index] = varied ? UInt8((index * 31 + index / 7) % 256) : UInt8(3)
        }
        return PhotoInput(pixelBytes: Data(bytes))
    }

    // MARK: - Analysis (REQ-AI-01)

    func testAnalysisReturnsStructuredEditableEstimate() async throws {
        let analyzer = HeuristicMealAnalyzer()
        let estimate = try await analyzer.analyze(photo: makePhoto())
        XCTAssertFalse(estimate.items.isEmpty)
        XCTAssertGreaterThan(estimate.totalCarbsGrams, 0)
        XCTAssertGreaterThanOrEqual(estimate.overallConfidence, HeuristicMealAnalyzer.confidenceFloor)
        XCTAssertEqual(estimate.impactLevel, GlucoseImpactLevel.level(forCarbLoad: estimate.totalCarbsGrams))
        XCTAssertFalse(estimate.analyzerVersion.isEmpty)
    }

    func testAnalysisIsDeterministicPerPhoto() async throws {
        let analyzer = HeuristicMealAnalyzer()
        let photo = makePhoto()
        let first = try await analyzer.analyze(photo: photo)
        let second = try await analyzer.analyze(photo: photo)
        XCTAssertEqual(first, second)
    }

    func testAnalysisRejectsUnreadablePhoto() async {
        let analyzer = HeuristicMealAnalyzer()
        do {
            _ = try await analyzer.analyze(photo: makePhoto(byteCount: 64))
            XCTFail("expected imageUnreadable")
        } catch let error as AnalysisError {
            XCTAssertEqual(error, .imageUnreadable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAnalysisFlagsLowConfidencePhoto() async {
        let analyzer = HeuristicMealAnalyzer()
        do {
            _ = try await analyzer.analyze(photo: makePhoto(varied: false))
            XCTFail("expected lowConfidence")
        } catch let error as AnalysisError {
            guard case .lowConfidence(let value) = error else {
                return XCTFail("expected lowConfidence, got \(error)")
            }
            XCTAssertLessThan(value, HeuristicMealAnalyzer.confidenceFloor)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Edit before confirm (REQ-AI-02)

    func testEditingPortionRecalculatesTotals() async throws {
        let analyzer = HeuristicMealAnalyzer()
        let estimate = try await analyzer.analyze(photo: makePhoto())
        var editable = EditableEstimate(estimate: estimate)
        let item = editable.items[0]
        let before = editable.totalCarbsGrams
        editable.updatePortion(itemID: item.id, portionGrams: item.portionGrams * 2, using: FoodDatabase())
        XCTAssertTrue(editable.items[0].editedByUser)
        XCTAssertNotEqual(editable.totalCarbsGrams, before)
        XCTAssertEqual(editable.impactLevel, GlucoseImpactLevel.level(forCarbLoad: editable.totalCarbsGrams))
    }

    func testAddAndRemoveItemsRecalculate() async throws {
        let analyzer = HeuristicMealAnalyzer()
        let estimate = try await analyzer.analyze(photo: makePhoto())
        var editable = EditableEstimate(estimate: estimate)
        let originalCount = editable.items.count
        let ref = FoodDatabase().reference(named: "White rice, cooked")!
        editable.addItem(from: ref)
        XCTAssertEqual(editable.items.count, originalCount + 1)
        editable.removeItem(itemID: editable.items[0].id)
        XCTAssertEqual(editable.items.count, originalCount)
    }

    // MARK: - Confirm gate and log write (REQ-AI-02, REQ-LOG-01)

    func testUnconfirmedEstimateNeverReachesStore() async throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let analyzer = HeuristicMealAnalyzer()
        let estimate = try await analyzer.analyze(photo: makePhoto())
        let editable = EditableEstimate(estimate: estimate)
        // Review without confirmation: store stays empty.
        XCTAssertTrue(store.meals.isEmpty)
        let meal = editable.confirmedMeal(thumbnailLocalRef: nil)
        _ = try store.save(meal)
        XCTAssertEqual(store.meals.count, 1)
        XCTAssertTrue(store.meals[0].confirmed)
    }

    func testStoreRejectsUnconfirmedMeal() throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let meal = MealLog(items: [], source: .manual, confirmed: false)
        XCTAssertThrowsError(try store.save(meal))
    }

    // MARK: - Budget sync (REQ-LOG-01, REQ-DEL-01)

    func testBudgetRingSyncsWithSaveAndDelete() throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let item = FoodItem(name: "White rice, cooked", portionGrams: 150, carbsGrams: 42.3, confidence: 1)
        let meal = MealLog(items: [item], source: .manual, confirmed: true)
        _ = try store.save(meal)
        let summaryAfterSave = store.dailySummary(for: Date(), budget: 130)
        XCTAssertEqual(summaryAfterSave.totalCarbs, 42.3, accuracy: 0.05)
        XCTAssertEqual(summaryAfterSave.remaining, 87.7, accuracy: 0.05)
        _ = try store.delete(id: meal.id)
        let summaryAfterDelete = store.dailySummary(for: Date(), budget: 130)
        XCTAssertEqual(summaryAfterDelete.totalCarbs, 0)
        XCTAssertEqual(summaryAfterDelete.remaining, 130)
    }

    func testOverBudgetFlag() throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let item = FoodItem(name: "Bagel", portionGrams: 210, carbsGrams: 111.3, confidence: 1)
        _ = try store.save(MealLog(items: [item], source: .manual, confirmed: true))
        _ = try store.save(MealLog(items: [item], source: .manual, confirmed: true))
        let summary = store.dailySummary(for: Date(), budget: 130)
        XCTAssertTrue(summary.isOverBudget)
        XCTAssertEqual(summary.budgetFraction, 1.0)
    }

    // MARK: - Edit saved meal (REQ-EDIT-01)

    func testEditingSavedMealUpdatesSummaries() throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let item = FoodItem(name: "Apple", portionGrams: 182, carbsGrams: 25.1, confidence: 1)
        var meal = MealLog(items: [item], source: .manual, confirmed: true)
        _ = try store.save(meal)
        meal.items[0].carbsGrams = 50.2
        meal.items[0].portionGrams = 364
        _ = try store.save(meal)
        XCTAssertEqual(store.meals.count, 1)
        XCTAssertEqual(store.dailySummary(for: Date(), budget: 130).totalCarbs, 50.2, accuracy: 0.05)
    }

    // MARK: - Save failure retry (REQ-ERR-01)

    func testSaveFailureDoesNotMutateStoreAndRetrySucceeds() throws {
        let failing = FlakyStorage(directory: directory, failuresRemaining: 1)
        let store = MealStore(storage: failing)
        let meal = MealLog(
            items: [FoodItem(name: "Apple", portionGrams: 182, carbsGrams: 25.1, confidence: 1)],
            source: .manual,
            confirmed: true
        )
        XCTAssertThrowsError(try store.save(meal)) { error in
            guard case MealStoreError.persistenceFailed = error else {
                return XCTFail("expected persistenceFailed, got \(error)")
            }
        }
        XCTAssertTrue(store.meals.isEmpty, "failed save must not mutate the in-memory log")
        // Caller retains the edited meal object and retries as-is.
        XCTAssertNoThrow(try store.save(meal))
        XCTAssertEqual(store.meals.count, 1)
    }

    // MARK: - Delete confirmation semantics (REQ-DEL-01)

    func testDeleteUnknownMealFails() throws {
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            XCTAssertEqual(error as? MealStoreError, .mealNotFound)
        }
    }

    // MARK: - Persistence roundtrip

    func testPersistenceRoundtrip() throws {
        let storage = JSONMealStorage(directory: directory)
        let store = MealStore(storage: storage)
        let meal = MealLog(
            items: [FoodItem(name: "Oatmeal, cooked", portionGrams: 234, carbsGrams: 28.1, confidence: 0.9)],
            estimate: GlucoseImpactEstimate(level: .medium, estimatedCarbLoad: 28.1, confidence: 0.9, modelVersion: "heuristic-plate-v1.2"),
            source: .photoEstimate,
            confirmed: true
        )
        _ = try store.save(meal)
        let reloaded = MealStore(storage: storage)
        XCTAssertEqual(reloaded.meals.count, 1)
        let restored = reloaded.meals[0]
        XCTAssertEqual(restored.id, meal.id)
        XCTAssertEqual(restored.items, meal.items)
        XCTAssertEqual(restored.estimate?.level, meal.estimate?.level)
        XCTAssertEqual(restored.source, meal.source)
        XCTAssertEqual(restored.capturedAt.timeIntervalSince1970, meal.capturedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Trends (REQ-TREND-01)

    func testTrendAggregationProducesDailyPoints() throws {
        let calendar = Calendar.current
        let today = Date()
        var meals: [MealLog] = []
        for daysBack in [0, 1, 3] {
            let day = calendar.date(byAdding: .day, value: -daysBack, to: today)!
            meals.append(MealLog(
                capturedAt: day,
                items: [FoodItem(name: "Banana", portionGrams: 118, carbsGrams: 26.9, confidence: 1)],
                source: .manual,
                confirmed: true
            ))
        }
        let points = TrendAggregator().dailyPoints(meals: meals, endingAt: today, days: 7)
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.last?.totalCarbs ?? 0, 26.9, accuracy: 0.05)
        let recordedDays = points.filter { $0.mealCount == 1 }.count
        XCTAssertEqual(recordedDays, 3)
    }

    // MARK: - Insights (REQ-TREND-01)

    func testWeeklyInsightNeedsThreeMeals() {
        let engine = InsightsEngine()
        XCTAssertNil(engine.weeklyInsight(meals: [], endingAt: Date()))
        let meal = MealLog(
            items: [FoodItem(name: "Apple", portionGrams: 182, carbsGrams: 25.1, confidence: 1)],
            source: .manual,
            confirmed: true
        )
        XCTAssertNil(engine.weeklyInsight(meals: [meal, meal], endingAt: Date()))
        XCTAssertNotNil(engine.weeklyInsight(meals: [meal, meal, meal], endingAt: Date()))
    }

    func testWeeklyInsightNamesFrequentHighImpactFood() {
        let engine = InsightsEngine()
        let highItem = FoodItem(name: "French fries", portionGrams: 200, carbsGrams: 82, confidence: 1)
        let lowItem = FoodItem(name: "Caesar salad with dressing", portionGrams: 190, carbsGrams: 12.4, confidence: 1)
        var meals: [MealLog] = []
        for _ in 0..<3 {
            meals.append(MealLog(items: [highItem], source: .photoEstimate, confirmed: true))
        }
        meals.append(MealLog(items: [lowItem], source: .manual, confirmed: true))
        let card = engine.weeklyInsight(meals: meals, endingAt: Date())
        XCTAssertNotNil(card)
        XCTAssertTrue(card!.body.contains("French fries"))
        XCTAssertFalse(card!.relatedMealIDs.isEmpty)
    }

    // MARK: - Free quota and paywall trigger (REQ-IAP-01)

    func testFreeQuotaAllowsThreeScansPerDay() {
        let store = SubscriptionStore(storefront: LocalCatalogStorefront(), directory: directory)
        XCTAssertEqual(store.scansRemaining(), ScanQuota.freeDailyLimit)
        XCTAssertTrue(store.consumeScan())
        XCTAssertTrue(store.consumeScan())
        XCTAssertTrue(store.consumeScan())
        XCTAssertEqual(store.scansRemaining(), 0)
        XCTAssertFalse(store.consumeScan(), "fourth scan must trigger the paywall path")
    }

    func testPremiumHasUnlimitedScans() async throws {
        let store = SubscriptionStore(storefront: LocalCatalogStorefront(), directory: directory)
        for _ in 0..<ScanQuota.freeDailyLimit { XCTAssertTrue(store.consumeScan()) }
        let mock = MockStorefront(entitlement: SubscriptionEntitlement(
            tier: .premiumMonthly,
            expiresAt: Date().addingTimeInterval(30 * 86400),
            willRenew: true,
            originalTransactionID: "tx-1"
        ))
        let premiumStore = SubscriptionStore(storefront: mock, directory: directory)
        _ = try await premiumStore.purchase(productID: LocalCatalogStorefront.monthlyProductID)
        XCTAssertTrue(premiumStore.isPremium)
        for _ in 0..<10 { XCTAssertTrue(premiumStore.consumeScan()) }
    }

    func testQuotaResetsOnNewDay() {
        var quota = ScanQuota(date: Date())
        let calendar = Calendar.current
        quota.consume(on: Date(), calendar: calendar)
        quota.consume(on: Date(), calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertEqual(quota.remaining(isPremium: false, on: tomorrow, calendar: calendar), ScanQuota.freeDailyLimit)
    }

    func testLocalCatalogReportsUnavailablePurchase() async {
        let storefront = LocalCatalogStorefront()
        let products = try? await storefront.loadProducts()
        XCTAssertEqual(products?.count, 2)
        XCTAssertTrue(products?.contains { $0.displayPrice == "$4.99" } ?? false)
        XCTAssertTrue(products?.contains { $0.displayPrice == "$39.99" } ?? false)
        do {
            _ = try await storefront.purchase(productID: LocalCatalogStorefront.monthlyProductID)
            XCTFail("expected storefrontUnavailable")
        } catch let error as SubscriptionError {
            XCTAssertEqual(error, .storefrontUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Copy deck (REQ-MD-01, en-US locale)

    func testCopyDeckIsEnglishASCIIAndCarriesDisclaimers() {
        let samples = [
            Copy.Analysis.disclaimer,
            Copy.Privacy.disclaimerBody,
            Copy.Analysis.failureTitle,
            Copy.Errors.saveFailed,
            Copy.Log.deleteTitle,
            Copy.Paywall.freeNote,
        ]
        let cjk = CharacterSet(charactersIn: Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!)
        for string in samples {
            XCTAssertFalse(string.isEmpty)
            XCTAssertNil(string.rangeOfCharacter(from: cjk), "non-English copy found: \(string)")
        }
        XCTAssertTrue(Copy.Analysis.disclaimer.contains("not medical advice"))
        XCTAssertTrue(Copy.Privacy.disclaimerBody.contains("not provide medical advice"))
        XCTAssertEqual(Copy.Analysis.failureTitle, "We couldn't analyze this photo")
    }

    // MARK: - Food search (REQ-AI-03 manual fallback)

    func testFoodSearchSupportsManualFallback() {
        let database = FoodDatabase()
        XCTAssertFalse(database.search("rice").isEmpty)
        XCTAssertFalse(database.search("BREAD").isEmpty)
        XCTAssertTrue(database.search("zzzz-no-such-food").isEmpty)
        XCTAssertTrue(database.search("   ").isEmpty)
    }
}

/// Storage stub that fails a configurable number of writes to exercise the
/// retry path without losing edits.
private final class FlakyStorage: MealStorage {
    private let backing: JSONMealStorage
    private var failuresRemaining: Int

    init(directory: URL, failuresRemaining: Int) {
        self.backing = JSONMealStorage(directory: directory)
        self.failuresRemaining = failuresRemaining
    }

    func loadMeals() throws -> [MealLog] { try backing.loadMeals() }

    func saveMeals(_ meals: [MealLog]) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw MealStoreError.persistenceFailed("injected")
        }
        try backing.saveMeals(meals)
    }

    func loadThumbnail(named: String) -> Data? { backing.loadThumbnail(named: named) }
    func saveThumbnail(_ data: Data, named: String) throws { try backing.saveThumbnail(data, named: named) }
    func deleteThumbnail(named: String) { backing.deleteThumbnail(named: named) }
}

private struct MockStorefront: Storefront {
    let entitlement: SubscriptionEntitlement

    func loadProducts() async throws -> [PremiumProduct] {
        try await LocalCatalogStorefront().loadProducts()
    }

    func purchase(productID: String) async throws -> SubscriptionEntitlement {
        entitlement
    }

    func restorePurchases() async throws -> SubscriptionEntitlement {
        entitlement
    }
}
