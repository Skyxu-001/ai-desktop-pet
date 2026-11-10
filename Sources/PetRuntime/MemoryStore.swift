import Foundation

public struct PetMemory: Codable, Equatable, Sendable {
    public var completedActivities: [String]
    public var petCount: Int
    public init(completedActivities: [String] = [], petCount: Int = 0) {
        self.completedActivities = completedActivities
        self.petCount = petCount
    }
}

public struct MemoryStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> PetMemory {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536,
              let data = try? Data(contentsOf: url),
              let memory = try? JSONDecoder().decode(PetMemory.self, from: data) else { return PetMemory() }
        return normalized(memory)
    }
    public func save(_ memory: PetMemory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized(memory)).write(to: url, options: .atomic)
    }
    private func normalized(_ memory: PetMemory) -> PetMemory {
        PetMemory(completedActivities: memory.completedActivities.suffix(12).compactMap {
            let text = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(80))
        }, petCount: max(0, min(memory.petCount, 1_000_000)))
    }
}
