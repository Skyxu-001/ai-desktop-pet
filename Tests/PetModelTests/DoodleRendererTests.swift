import XCTest
@testable import PetModel

final class DoodleRendererTests: XCTestCase {
    func testCompositionsStayInsideThreeRowsAndSixteenASCIIColumns() {
        var drawings: Set<String> = []
        for drawing in DoodleDrawing.allCases {
            for accent in DoodleAccent.allCases {
                for mood in DoodleMood.allCases {
                    let result = DoodleRenderer.render(drawing: drawing, accent: accent, mood: mood)
                    let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
                    XCTAssertEqual(lines.count, 3)
                    XCTAssertTrue(lines.allSatisfy { (1...16).contains($0.count) })
                    XCTAssertTrue(result.unicodeScalars.allSatisfy { $0.value == 10 || (32...126).contains($0.value) })
                    drawings.insert(result)
                }
            }
        }
        XCTAssertEqual(drawings.count, 36)
    }
    func testChosenSubjectMoodAndAccentAppearInComposition() {
        XCTAssertEqual(
            DoodleRenderer.render(drawing: .puppy, accent: .sparkle, mood: .happy),
            "/ \\_/ \\  . \n( ^.^ ) -*-\n /   \\   ' "
        )
        XCTAssertEqual(
            DoodleRenderer.render(drawing: .box, accent: .heart, mood: .sleepy),
            " .---.   _ \n| -.- | <3 \n '---'     "
        )
    }
}
