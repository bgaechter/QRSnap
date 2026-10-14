import Foundation

/// Session identity gates late completions. The UI owns this value on the main actor.
public struct SessionLifecycle: Sendable {
    public enum Phase: Sendable { case idle, selecting, capturing, decoding, reviewing, opening }
    public private(set) var id: UUID?
    public private(set) var phase: Phase = .idle
    public init() {}

    public mutating func begin() -> UUID? {
        guard phase == .idle else { return nil }
        let token = UUID()
        id = token
        phase = .selecting
        return token
    }

    public func contains(_ token: UUID) -> Bool { id == token && phase != .idle }

    @discardableResult
    public mutating func advance(_ token: UUID, from: Phase, to: Phase) -> Bool {
        guard contains(token), phase == from, to != .idle else { return false }
        let allowed: Bool
        switch (from, to) {
        case (.selecting, .capturing), (.capturing, .decoding),
             (.decoding, .reviewing), (.reviewing, .opening): allowed = true
        default: allowed = false
        }
        guard allowed else { return false }
        phase = to
        return true
    }

    @discardableResult
    public mutating func finish(_ token: UUID) -> Bool {
        guard contains(token) else { return false }
        id = nil
        phase = .idle
        return true
    }
}
