import XCTest
@testable import CarbLensCore

/// Covers the structured AI refinement pipeline: parsing hardening, transport
/// failure semantics, on-device fallback, and the editable/confirm chain that
/// keeps an unconfirmed AI result out of the log (REQ-AI-01, REQ-AI-02,
/// REQ-AI-03, REQ-LOG-01).
final class EstimateRefinerTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("carblens-refiner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePhoto(byteCount: Int = 4096) -> PhotoInput {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices {
            bytes[index] = UInt8((index * 31 + index / 7) % 256)
        }
        return PhotoInput(pixelBytes: Data(bytes))
    }

    private struct StubTransport: EstimateRefinementTransport {
        let response: Result<String, Error>

        func complete(_ prompt: String) async throws -> String {
            try response.get()
        }

        struct StubError: Error {}
    }

    private func refinedJSON(items: [[String: Any]], overall: Double = 0.82) -> String {
        let payload: [String: Any] = ["items": items, "overall_confidence": overall]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Parser hardening (REQ-AI-01)

    func testParserAcceptsFencedJSONWithProse() throws {
        let raw = "Here is the refined estimate:\n```json\n" + refinedJSON(items: [
            ["name": "White rice, cooked", "portion_grams": 180, "carbs_grams": 50.8, "confidence": 0.9],
        ]) + "\n```\nHope this helps."
        let estimate = try StructuredEstimateParser().parse(raw, database: FoodDatabase())
        XCTAssertEqual(estimate.items.count, 1)
        XCTAssertEqual(estimate.items[0].name, "White rice, cooked")
        XCTAssertEqual(estimate.items[0].portionGrams, 180)
        XCTAssertEqual(estimate.analyzerVersion, RefiningMealAnalyzer.refinerVersion)
    }

    func testParserToleratesSmartQuotesAndTrailingComma() throws {
        // Smart quotes everywhere plus trailing commas before } and ].
        let raw = "{\u{201C}items\u{201D}:[{\u{201C}name\u{201D}:\u{201C}Grilled chicken breast\u{201D},\u{201C}portion_grams\u{201D}:140,\u{201C}carbs_grams\u{201D}:0,\u{201C}confidence\u{201D}:0.7,}],\u{201C}overall_confidence\u{201D}:0.82,}"
        let estimate = try StructuredEstimateParser().parse(raw, database: FoodDatabase())
        XCTAssertEqual(estimate.items.count, 1)
        XCTAssertEqual(estimate.items[0].confidence, 0.7)
    }

    func testParserRejectsNonJSON() {
        XCTAssertThrowsError(try StructuredEstimateParser().parse("no estimate available", database: FoodDatabase())) { error in
            XCTAssertEqual(error as? EstimateRefinementError, .responseUnparseable)
        }
    }

    func testParserDropsUnknownFoodsAndFailsWhenNothingKnown() {
        let raw = refinedJSON(items: [
            ["name": "Unobtainium stew", "portion_grams": 100, "carbs_grams": 10, "confidence": 0.5],
        ])
        XCTAssertThrowsError(try StructuredEstimateParser().parse(raw, database: FoodDatabase())) { error in
            XCTAssertEqual(error as? EstimateRefinementError, .responseIncomplete)
        }
    }

    func testParserClampsOutOfRangeValues() throws {
        let raw = refinedJSON(items: [
            ["name": "Banana", "portion_grams": 99999, "carbs_grams": 900, "confidence": 7.5],
        ], overall: 42)
        let estimate = try StructuredEstimateParser().parse(raw, database: FoodDatabase())
        XCTAssertLessThanOrEqual(estimate.items[0].portionGrams, 2000)
        XCTAssertLessThanOrEqual(estimate.items[0].confidence, 1)
        XCTAssertLessThanOrEqual(estimate.overallConfidence, 1)
    }

    // MARK: - Refining analyzer (REQ-AI-01)

    func testRefiningAnalyzerConsumesStructuredModelOutput() async throws {
        let transport = StubTransport(response: .success(refinedJSON(items: [
            ["name": "White rice, cooked", "portion_grams": 200, "carbs_grams": 56.4, "confidence": 0.88],
            ["name": "Black beans, cooked", "portion_grams": 150, "carbs_grams": 35.6, "confidence": 0.81],
        ])))
        let analyzer = RefiningMealAnalyzer(transport: transport)
        let estimate = try await analyzer.analyze(photo: makePhoto())
        XCTAssertEqual(estimate.analyzerVersion, RefiningMealAnalyzer.refinerVersion)
        XCTAssertEqual(estimate.items.count, 2)
        XCTAssertEqual(estimate.overallConfidence, 0.82)
        XCTAssertGreaterThan(estimate.totalCarbsGrams, 0)
    }

    func testRefiningAnalyzerMapsTransportFailureToServiceUnavailable() async {
        let transport = StubTransport(response: .failure(StubTransport.StubError()))
        let analyzer = RefiningMealAnalyzer(transport: transport)
        do {
            _ = try await analyzer.analyze(photo: makePhoto())
            XCTFail("expected serviceUnavailable")
        } catch let error as AnalysisError {
            XCTAssertEqual(error, .serviceUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRefiningAnalyzerMapsMalformedResponseToServiceUnavailable() async {
        let transport = StubTransport(response: .success("I cannot help with that."))
        let analyzer = RefiningMealAnalyzer(transport: transport)
        do {
            _ = try await analyzer.analyze(photo: makePhoto())
            XCTFail("expected serviceUnavailable")
        } catch let error as AnalysisError {
            XCTAssertEqual(error, .serviceUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Unavailable AI recovery (REQ-AI-03)

    func testFallbackAnalyzerPreservesServiceUnavailableForManualRecovery() async {
        let transport = StubTransport(response: .failure(StubTransport.StubError()))
        let analyzer = FallbackMealAnalyzer(
            primary: RefiningMealAnalyzer(transport: transport),
            fallback: HeuristicMealAnalyzer()
        )
        do {
            _ = try await analyzer.analyze(photo: makePhoto())
            XCTFail("expected serviceUnavailable")
        } catch let error as AnalysisError {
            XCTAssertEqual(error, .serviceUnavailable)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Editable + confirm chain with AI output (REQ-AI-02, REQ-LOG-01)

    func testRefinedEstimateStaysEditableAndSavesOnlyAfterConfirm() async throws {
        let transport = StubTransport(response: .success(refinedJSON(items: [
            ["name": "White rice, cooked", "portion_grams": 200, "carbs_grams": 56.4, "confidence": 0.88],
        ])))
        let analyzer = FallbackMealAnalyzer(
            primary: RefiningMealAnalyzer(transport: transport),
            fallback: HeuristicMealAnalyzer()
        )
        let store = MealStore(storage: JSONMealStorage(directory: directory))
        let estimate = try await analyzer.analyze(photo: makePhoto())
        var editable = EditableEstimate(estimate: estimate)

        // Nothing is persisted before explicit confirmation.
        XCTAssertTrue(store.meals.isEmpty)

        let itemID = try XCTUnwrap(editable.items.first?.id)
        editable.updatePortion(itemID: itemID, portionGrams: 100, using: FoodDatabase())
        XCTAssertEqual(editable.totalCarbsGrams, 28.2, accuracy: 0.2)
        XCTAssertTrue(editable.items[0].editedByUser)

        let meal = editable.confirmedMeal(thumbnailLocalRef: nil)
        XCTAssertTrue(meal.confirmed)
        _ = try store.save(meal)
        XCTAssertEqual(store.meals.count, 1)
        let summary = store.dailySummary(for: Date(), budget: 140)
        XCTAssertEqual(summary.totalCarbs, editable.totalCarbsGrams, accuracy: 0.2)
    }
}
