import Foundation

/// Safety lock while the UI is being polished.
/// While `liveSending` is false, every Send opens Messages addressed to YOU,
/// with a note saying who it was meant for. Real friends never get anything.
/// Flip to true only when you're ready to text real people.
enum SendSafety {
    static let liveSending = false
    static let testRecipient = Secrets.myNumber   // ios/LooseEnds/Secrets.swift (not in git); see ios/Secrets.example.swift

    static func recipient(for card: Card) -> String {
        liveSending ? card.handle.filter { !" ()-".contains($0) } : testRecipient
    }

    static func body(for card: Card, draft: String) -> String {
        liveSending ? draft : "[TEST → \(card.name)] \(draft)"
    }
}
