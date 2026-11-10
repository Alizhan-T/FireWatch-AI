import XCTest
@testable import FireWatchNative

final class AIFireAssessmentTests: XCTestCase {
    func testMeaningfulClassifications() {
        XCTAssertEqual(AIFireAssessment.headline(for: "fire"), "Возможные признаки огня")
        XCTAssertEqual(AIFireAssessment.headline(for: "smoke"), "Возможные признаки дыма")
        XCTAssertEqual(AIFireAssessment.headline(for: "fire_smoke"), "Возможные признаки огня и дыма")
        XCTAssertEqual(AIFireAssessment.headline(for: "none"), "Признаки огня и дыма не обнаружены")
        XCTAssertEqual(AIFireAssessment.headline(for: "unknown"), "Результат не распознан")
    }

    func testDemoIsNeverRepresentedAsRealModel() {
        let status = AIFireAssessment.status(mode: "demo_heuristic")
        XCTAssertTrue(status.contains("DEMO"))
        XCTAssertTrue(AIFireAssessment.score(0.99, mode: "demo_heuristic", classification: "fire")
            .contains("не является вероятностью"))
        XCTAssertTrue(AIFireAssessment.action(for: "fire", mode: "demo_heuristic")
            .contains("не предназначена для оповещения"))
    }

    func testNoDetectionIsNotSafetyGuarantee() {
        XCTAssertTrue(AIFireAssessment.evidence(for: "none").contains("не означает"))
        XCTAssertTrue(AIFireAssessment.action(for: "none", mode: "real_model")
            .contains("Одного кадра недостаточно"))
    }

    func testModelScoreDoesNotClaimToBeFireProbability() {
        let explanation = AIFireAssessment.score(0.874, mode: "real_model", classification: "smoke")
        XCTAssertTrue(explanation.contains("87%"))
        XCTAssertTrue(explanation.contains("не вероятность"))
        XCTAssertTrue(AIFireAssessment.status(mode: "real_model").contains("реальная модель"))
    }

    func testOutOfRangeScoresAreClamped() {
        XCTAssertTrue(AIFireAssessment.score(1.5, mode: "real_model", classification: "fire")
            .contains("100%"))
        XCTAssertTrue(AIFireAssessment.score(-2, mode: "real_model", classification: "fire")
            .contains("0%"))
    }
}
