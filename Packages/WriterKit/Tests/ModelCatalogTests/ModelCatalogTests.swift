import XCTest
@testable import ModelCatalog

final class ModelCatalogTests: XCTestCase {
    func testEveryModelHasALicence() {
        for m in ModelCatalog.all {
            XCTAssertFalse(m.license.isEmpty, m.id)
            XCTAssertFalse(m.obligations.isEmpty, m.id)
        }
    }

    func testNothingDownloadsWithoutAPinnedChecksum() {
        for m in ModelCatalog.all where m.sha256 == nil {
            XCTAssertFalse(m.isDownloadable, m.id)
        }
    }

    final class Fake: ResidentModel, @unchecked Sendable {
        let footprintBytes: Int64
        var unloaded = false
        init(_ b: Int64) { footprintBytes = b }
        func unload() async { unloaded = true }
    }

    func testResidencyEvictsLeastRecentlyUsedOverBudget() async throws {
        let r = ModelResidency(budgetBytes: 100)
        let a = Fake(60), b = Fake(60)
        _ = try await r.use("a") { a }
        _ = try await r.use("b") { b }
        let ids = await r.residentIDs
        XCTAssertEqual(ids, ["b"])
        XCTAssertTrue(a.unloaded)
    }
}
