import XCTest
@testable import CarbLens

final class CarbLensAppTests: XCTestCase {
    func testDailyBudgetAndImpactRulesRemainAvailableOnTheSupportedMinimumOS() {
        let profile = UserProfile(dailyCarbBudget: 130)

        XCTAssertEqual(profile.dailyCarbBudget, 130)
        XCTAssertEqual(GlucoseImpactLevel.level(forCarbLoad: 60), .high)
    }
}
