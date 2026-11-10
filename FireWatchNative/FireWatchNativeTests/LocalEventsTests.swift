import Foundation
import XCTest
@testable import FireWatchNative

final class FireWatchLocalFeaturesTests: XCTestCase {
    func testCitiesIncludeSemeyAndNeverRequireRawCoordinates() {
        let semey = KazakhstanCities.find("semey")
        XCTAssertEqual(semey.name, "Семей")
        XCTAssertTrue((42...56).contains(semey.lat))
        XCTAssertTrue((46...88).contains(semey.lon))
        XCTAssertEqual(Set(KazakhstanCities.all.map(\.id)).count, KazakhstanCities.all.count)
    }

    func testManualAndDemoIncidentsRemainDistinctAndPersist() async throws {
        await MainActor.run {
            let suite = "firewatch-events-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let store = LocalEventStore(defaults: defaults)
            store.create(title: "", details: "Тест", cityID: "semey",
                         kind: "Огонь", severity: "Средняя", simulation: true)
            store.create(title: "От оператора", details: "", cityID: "almaty",
                         kind: "Дым", severity: "Высокая", simulation: false)

            XCTAssertEqual(store.events.count, 2)
            XCTAssertFalse(store.events[0].isSimulation)
            XCTAssertTrue(store.events[1].isSimulation)
            let restored = LocalEventStore(defaults: defaults)
            XCTAssertEqual(restored.events.count, 2)
            XCTAssertEqual(restored.events[1].city.name, "Семей")

            store.setResolved(store.events[0], true)
            XCTAssertTrue(store.events[0].resolved)
            store.delete(store.events[1])
            XCTAssertEqual(LocalEventStore(defaults: defaults).events.count, 1)
        }
    }

    func testSemeyIsNotPresentedAsConfirmedDirectHLS() {
        XCTAssertFalse(PublicCameraCatalog.candidates.contains(where: { $0.name.contains("Семей") }))
        XCTAssertTrue(KazakhstanPublisherCameras.candidates.contains(where: {
            $0.cityID == "semey" && $0.reliabilityNote.contains("нестабильный")
        }) == false ? KazakhstanPublisherCameras.candidates.contains(where: {
            $0.cityID == "semey" && $0.reliabilityNote.contains("нестабиль")
        }) : true)
    }
}
