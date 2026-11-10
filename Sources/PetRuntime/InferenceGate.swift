import Foundation

public struct InferenceTicket: Equatable, Sendable {
    public let id: UUID
    public let revision: Int
    public let started: Double
}

public struct InferenceGate: Sendable {
    public private(set) var active: InferenceTicket?
    public private(set) var nextAllowed: Double = 0
    public private(set) var expired = false
    public private(set) var suspended = false
    private var invalidated = false
    public init() {}
    public mutating func begin(now: Double, revision: Int) -> InferenceTicket? {
        guard now.isFinite, active == nil, !suspended, now >= nextAllowed else { return nil }
        let ticket = InferenceTicket(id: UUID(), revision: revision, started: now)
        active = ticket
        expired = false
        invalidated = false
        nextAllowed = now + 12
        return ticket
    }
    public mutating func expire(now: Double) -> Bool {
        guard let active, now.isFinite, !expired, now - active.started >= 20 else { return false }
        expired = true
        return true
    }
    public mutating func invalidate() { invalidated = true }
    public mutating func setSuspended(_ value: Bool) {
        suspended = value
        if value { invalidate() }
    }
    public mutating func finish(_ ticket: InferenceTicket, currentRevision: Int, now: Double, succeeded: Bool) -> Bool {
        guard active == ticket else { return false }
        let accepted = succeeded && !expired && !invalidated && !suspended && currentRevision == ticket.revision
        if !succeeded || expired { nextAllowed = max(nextAllowed, now + 30) }
        active = nil
        expired = false
        invalidated = false
        return accepted
    }
}
