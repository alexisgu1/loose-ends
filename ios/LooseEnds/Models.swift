import Foundation

struct Digest: Decodable {
    let engine: String
    let model: String?
    let generatedAt: String
    var stats: Stats
    var cards: [Card]
    let errors: [ThreadError]
    var quiet: [QuietPerson]? = nil
}

/// Someone you used to text a lot but haven't in a while.
struct QuietPerson: Decodable, Identifiable, Equatable {
    let id: String
    let personId: String
    let name: String
    let handle: String
    let daysQuiet: Int
    let draft: String

    var firstName: String { (name.split(separator: " ").first.map(String.init) ?? name).capitalized }
    var quietFor: String {
        switch daysQuiet {
        case ..<14: "\(daysQuiet) days"
        case ..<60: "\(daysQuiet / 7) weeks"
        default: "\(daysQuiet / 30) months"
        }
    }
}

struct Stats: Decodable {
    let people: Int
    let messages: Int
    let looseEnds: Int
    let overflow: Int
    var snoozed: Int
    var handled: Int
}

struct ThreadError: Decodable {
    let name: String
    let message: String
}

struct Card: Decodable, Identifiable, Equatable {
    let id: String
    let personId: String
    let name: String
    let handle: String
    let relationship: String
    let lastTalked: String
    let loop: Loop
    let also: [String]
    let score: Double
    let factors: Factors

    static func == (a: Card, b: Card) -> Bool { a.id == b.id }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct Loop: Decodable {
    let type: String
    let label: String
    let why: String
    let quote: String
    let quoteFrom: String
    let quoteDate: String
    let dueDate: String?
    let draft: String
}

struct Factors: Decodable {
    let type: Double
    let closeness: Double
    let relationship: Double
    let timing: Double
    let timingNote: String
}

enum LoopKind: String {
    case event, reply_owed, promise, plan, drift

    var title: String {
        switch self {
        case .event: "Check in"
        case .reply_owed: "Reply owed"
        case .promise: "You promised"
        case .plan: "Make the plan"
        case .drift: "Been a while"
        }
    }
}

/// A free evening with someone, from Google Calendar via the Mac.
struct PlanInfo: Decodable {
    struct Slot: Decodable { let start: String; let end: String }
    let connected: Bool
    var email: String? = nil
    var slot: Slot? = nil
    var label: String? = nil
    var bothFree: Bool? = nil
    var draft: String? = nil
    var title: String? = nil
    struct Busy: Decodable { let mine: [Slot]; let theirs: [Slot] }
    var busy: Busy? = nil
}
