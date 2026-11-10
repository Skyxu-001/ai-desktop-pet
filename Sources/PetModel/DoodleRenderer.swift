// The model selects a subject, expression and ornament; these primitives compose the pixels.
enum DoodleDrawing: String, CaseIterable, Sendable { case puppy, ball, box, trail }
enum DoodleAccent: String, CaseIterable, Sendable { case sparkle, heart, dots }
enum DoodleMood: String, CaseIterable, Sendable { case happy, curious, sleepy }

enum DoodleRenderer {
    static func render(drawing: DoodleDrawing, accent: DoodleAccent, mood: DoodleMood) -> String {
        let face: String
        switch mood {
        case .happy: face = "^.^"
        case .curious: face = "o.o"
        case .sleepy: face = "-.-"
        }
        let subject: [String]
        switch drawing {
        case .puppy: subject = ["/ \\_/ \\", "( \(face) )", " /   \\ "]
        case .ball: subject = [" .---. ", "( \(face) )", " '---' "]
        case .box: subject = [" .---. ", "| \(face) |", " '---' "]
        case .trail: subject = ["o . . >", "  \(face)  ", " < . o "]
        }
        let ornament: [String]
        switch accent {
        case .sparkle: ornament = [" . ", "-*-", " ' "]
        case .heart: ornament = [" _ ", "<3 ", "   "]
        case .dots: ornament = [" . ", " . ", " . "]
        }
        return zip(subject, ornament).map { $0 + " " + $1 }.joined(separator: "\n")
    }
}
