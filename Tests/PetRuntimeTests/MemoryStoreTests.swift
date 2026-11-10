import Foundation
import XCTest
@testable import PetRuntime

final class MemoryStoreTests: XCTestCase {
    func testSaveReloadKeepsOnlyRecentRealActivities() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoryStore(url: directory.appendingPathComponent("memory.json"))
        try store.save(PetMemory(completedActivities: (0..<15).map { "活动\($0)" }, petCount: 7))
        let recovered = store.load()
        XCTAssertEqual(recovered.completedActivities.count, 12)
        XCTAssertEqual(recovered.completedActivities.first, "活动3")
        XCTAssertEqual(recovered.completedActivities.last, "活动14")
        XCTAssertEqual(recovered.petCount, 7)
        try store.save(PetMemory(completedActivities: ["玩球"], petCount: 8))
        XCTAssertEqual(store.load().completedActivities, ["玩球"])
        XCTAssertEqual(store.load().petCount, 8)
    }

    func testCorruptMemoryFallsBackAndValidatesDecodedValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = MemoryStore(url: directory.appendingPathComponent("memory.json"))
        try Data("{broken".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), PetMemory())
        try Data(#"{"completedActivities":["","   ","玩球"],"petCount":-5}"#.utf8).write(to: store.url)
        XCTAssertEqual(store.load(), PetMemory(completedActivities: ["玩球"], petCount: 0))
    }
}
