import SwiftUI

// MARK: - Places within ~1 mile of the UMich Diag (walking distances are approximate)

struct NearPlace: Equatable {
    let name: String
    let emoji: String
    var verb = "get"              // "Let's get Kang's", "Let's study at Hatcher Library"
    var aliases: [String] = []    // other ways people type it ("the dude", "duderstadt")
    var address = ""              // goes in the calendar event's location
    var phrase: String { "\(verb) \(name)" }
}

enum Near {
    // Restaurants on State Street and South University only (a few minutes' walk from the Diag), plus campus hangouts.
    static let all: [NearPlace] = [
        // State Street
        .init(name: "Sava's", emoji: "🍝", aliases: ["savas"]), .init(name: "Mister Spots", emoji: "🥪", aliases: ["mr spots", "mr. spots"]),
        .init(name: "sweetgreen", emoji: "🥗"),
        // South University
        .init(name: "Kang's", emoji: "🍲", aliases: ["kangs"]), .init(name: "No Thai", emoji: "🍜", aliases: ["no thai!"]),
        .init(name: "South U Pizza", emoji: "🍕"), .init(name: "BTB Burrito", emoji: "🌯", aliases: ["btb"]),
        .init(name: "Good Time Charley's", emoji: "🍔", aliases: ["charley's", "charleys"]), .init(name: "Raising Cane's", emoji: "🍗", aliases: ["canes", "cane's"]),
        // hangouts
        .init(name: "Hatcher Library", emoji: "📚", verb: "study at", aliases: ["hatcher", "the grad", "grad library"]),
        .init(name: "the Dude", emoji: "💻", verb: "lock in at", aliases: ["duderstadt", "dude"]),
        .init(name: "the Arb", emoji: "🌳", verb: "walk", aliases: ["arboretum", "nichols arb", "arb"]),
        .init(name: "the Diag", emoji: "☀️", verb: "hang on", aliases: ["diag"]),
        .init(name: "Michigan Theater", emoji: "🎬", verb: "catch a movie at", aliases: ["michigan theater", "state theatre"]),
        .init(name: "M-36 Coffee", emoji: "☕️", verb: "grab coffee at", aliases: ["m36", "m-36"]),
    ]
    static func named(_ n: String) -> NearPlace? { all.first { $0.name == n } }

    /// Street addresses for the calendar event's location (Ann Arbor, MI 48104 area).
    static let addresses: [String: String] = [
        "Sava's": "216 S State St",
        "Mister Spots": "808 S State St",
        "sweetgreen": "311 S State St",
        "Kang's": "1327 S University Ave",
        "No Thai": "1300 S University Ave",
        "South U Pizza": "1106 S University Ave",
        "BTB Burrito": "1140 S University Ave",
        "Good Time Charley's": "1140 S University Ave",
        "Raising Cane's": "1116 S University Ave",
        "Hatcher Library": "913 S University Ave",
        "the Dude": "2281 Bonisteel Blvd",
        "the Arb": "1610 Washington Heights",
        "the Diag": "The Diag, University of Michigan",
        "Michigan Theater": "603 E Liberty St",
        "M-36 Coffee": "1101 S University Ave",
    ]
    /// "Kang's, 1327 S University Ave, Ann Arbor, MI"
    static func location(for place: String) -> String {
        guard let a = addresses[place] else { return place + ", Ann Arbor, MI" }
        return a.contains("University of Michigan") ? a + ", Ann Arbor, MI" : "\(place), \(a), Ann Arbor, MI"
    }
    /// More emojis per place for the confetti.
    static let confetti: [String: String] = [
        "Sava's": "🍝🍷🥗", "Mister Spots": "🥪🍗🍟", "sweetgreen": "🥗🥑", "Kang's": "🍲🥢🍚", "No Thai": "🍜🥢🌶️",
        "South U Pizza": "🍕🥤", "BTB Burrito": "🌯🌮", "Good Time Charley's": "🍔🍻🍟", "Raising Cane's": "🍗🍟🥤",
        "Hatcher Library": "📚✏️📖", "the Dude": "💻☕️🎧", "the Arb": "🌳🍂🌿", "the Diag": "☀️🐿️🌳", "Michigan Theater": "🎬🍿🎟️",
        "M-36 Coffee": "☕️🥐",
    ]

    static func random(excluding current: String) -> NearPlace {
        all.filter { $0.name != current }.randomElement()!
    }
    /// A stable first suggestion per person, so the deck doesn't reshuffle every launch.
    static func first(for name: String) -> NearPlace {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return all[abs(h) % all.count]
    }
    static func find(in text: String) -> NearPlace? {
        let low = text.lowercased().replacingOccurrences(of: "’", with: "'")
        var best: (NearPlace, Int)?
        for p in all {
            for key in [p.name.lowercased()] + p.aliases {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
                guard let r = low.range(of: pat, options: .regularExpression) else { continue }
                let at = low.distance(from: low.startIndex, to: r.lowerBound)
                if best == nil || at < best!.1 { best = (p, at) }
            }
        }
        return best?.0
    }
    /// A place that isn't on the list: the words after "get / at / to / try / grab", up to the day or the
    /// end of the sentence. "Let's get Chipotle this Friday!" → "Chipotle", "lock in at the UGLi tonight" → "the UGLi".
    static func guess(in text: String) -> String? {
        let pattern = #"(?i)\b(?:get|at|to|try|grab|hit|visit|walk|browse|on|see|explore)\s+(.+?)(?=\s+(?:this|tonight|tomorrow|today|on|next|at|for|sometime|soon)\b|[!?.,]|$)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let skip: Set<String> = ["dinner", "lunch", "food", "coffee", "drinks", "boba", "brunch", "breakfast", "together", "a bite", "it", "you", "me", "us"]
        // "get dinner at Sava's": skip "dinner", take the next one
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let place = text[r].trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...32).contains(place.count), !skip.contains(place.lowercased()) else { continue }
            // "chipotle" → "Chipotle"; anything already capitalized ("the UGLi") stays as typed
            return place == place.lowercased() && !place.hasPrefix("the ") ? place.prefix(1).uppercased() + place.dropFirst() : place
        }
        return nil
    }

    static func emojis(for place: String) -> [String] {
        let s = confetti[place] ?? all.first { $0.name == place }?.emoji ?? "🎉✨🥳"
        return s.map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - One plan in the deck

struct DeckPlan: Identifiable, Equatable {
    let id: String          // personId
    let name: String        // first name
    var text: String
    var place: String
    var start: Date
    var end: Date
    var busy: [ClosedRange<Double>]  // hours of the plan's day, merged
    var email: String?

    var startHour: Double { start.hourOfDay }
    var duration: Double { end.timeIntervalSince(start) / 3600 }

    mutating func move(toHour h: Double) {
        let d = duration
        start = start.atHour(h)
        end = start.addingTimeInterval(d * 3600)
    }

    /// Swap the place. If the text is still the drafted one, redraft it (so "get" becomes "study at");
    /// if you've written your own, just swap the place's name in it.
    mutating func swapPlace(to new: String) {
        if text == DeckPlan.message(place: place, start: start) {
            text = DeckPlan.message(place: new, start: start)
        } else {
            let old = Near.named(place)
            for variant in [place, place.replacingOccurrences(of: "'", with: "’")] + (old?.aliases ?? []) {
                if let r = text.range(of: variant, options: .caseInsensitive) { text.replaceSubrange(r, with: new); break }
            }
        }
        place = new
    }

    static func message(place: String, start: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: start)).day ?? 0
        let when: String
        switch days {
        case ..<1: when = "tonight"
        case 1: when = "tomorrow"
        default: when = "this " + start.formatted(.dateTime.weekday(.wide))
        }
        return "Hi! Let's \(Near.named(place)?.phrase ?? "get " + place) \(when)!"
    }
}

extension Date {
    var hourOfDay: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
    func atHour(_ h: Double) -> Date {
        let H = Int(h), M = Int(((h - Double(H)) * 60).rounded())
        return Calendar.current.date(bySettingHour: min(H, 23), minute: M, second: 0, of: self) ?? self
    }
}

enum Fmt {
    /// "7 pm"
    static func hourLabel(_ h: Int) -> String {
        let hh = h % 24
        return "\(hh % 12 == 0 ? 12 : hh % 12) \(hh < 12 ? "am" : "pm")"
    }
    /// "7:00"
    static func clock(_ h: Double) -> String {
        let H = Int(h), M = Int(((h - Double(H)) * 60).rounded())
        return "\(H % 12 == 0 ? 12 : H % 12):" + String(format: "%02d", M)
    }
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static func date(_ s: String) -> Date? { iso.date(from: s) ?? isoFrac.date(from: s) }
}

// MARK: - The deck's state

@MainActor
final class DeckModel: ObservableObject {
    enum Phase: Equatable { case loading, deck, end, pick, saved, failed(String) }

    @Published var phase: Phase = .loading
    @Published var plans: [DeckPlan] = []          // still to decide, top card first
    @Published var all: [DeckPlan] = []            // this week's deck, in order
    @Published var sent: [String] = []             // ids
    @Published var skipped: [String] = []
    @Published var candidates: [QuietPerson] = []  // for next week's picker
    @Published var picked: [String] = []           // personIds, in tap order
    @Published var bursts: [ConfettiBurst] = []
    @Published var leaving = false
    @Published var eventLinks: [String: URL] = [:]   // plan id → its Google Calendar event
    var eventIds: [String: String] = [:]             // plan id → event id, for deleting it
    /// On the last card the faces row is frozen as it was, so it fades out with everything else.
    @Published var frozenRail: (sent: [String], skipped: [String], current: String?)? = nil

    @AppStorage("nextWeekPicks") private var savedPicks = ""   // comma-separated personIds

    var current: DeckPlan? { plans.first }

    /// This week: your reach-out people, or the ones you picked last week once the new week starts.
    func load(store: Store, onlyIds: [String]? = nil) async {
        phase = .loading
        await store.load()
        guard let quiet = store.digest?.quiet, !quiet.isEmpty else {
            if case .failed(let title, let message) = store.phase { phase = .failed("\(title). \(message)") }
            else { phase = .failed("No one to plan with yet.") }
            return
        }
        let people = onlyIds.map { ids in ids.compactMap { id in quiet.first { $0.personId == id || $0.id == id } } } ?? Array(quiet.prefix(4))
        var out: [DeckPlan] = []
        await withTaskGroup(of: (Int, DeckPlan).self) { group in
            for (i, q) in people.enumerated() {
                group.addTask { (i, await Self.plan(for: q, store: store, index: i)) }
            }
            for await (i, p) in group { out.append(p); _ = i }
        }
        let order = people.map(\.personId)
        out.sort { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        all = out; plans = out; sent = []; skipped = []; leaving = false; frozenRail = nil
        candidates = quiet.filter { q in !out.contains { $0.id == q.personId } }
        if candidates.count < 3 { candidates = quiet }
        phase = out.isEmpty ? .end : .deck
    }

    private static func plan(for q: QuietPerson, store: Store, index: Int) async -> DeckPlan {
        let info = await store.fetchPlan(name: q.name, day: index)   // person 1 from today, person 2 from tomorrow, …
        let place = Near.first(for: q.firstName)
        var start = Calendar.current.date(byAdding: .day, value: index + 1, to: .now)!.atHour(19)
        var end = start.addingTimeInterval(3600)
        var busy: [ClosedRange<Double>] = []
        if let s = info?.slot, let a = Fmt.date(s.start), let b = Fmt.date(s.end) {
            start = a; end = b
            let blocks = (info?.busy?.mine ?? []) + (info?.busy?.theirs ?? [])
            let ranges = blocks.compactMap { b -> ClosedRange<Double>? in
                guard let x = Fmt.date(b.start), let y = Fmt.date(b.end), Calendar.current.isDate(x, inSameDayAs: a) else { return nil }
                let lo = x.hourOfDay, hi = Calendar.current.isDate(y, inSameDayAs: a) ? y.hourOfDay : 24
                return hi > lo ? lo...hi : nil
            }
            busy = merge(ranges)
        }
        return DeckPlan(id: q.personId, name: q.firstName, text: DeckPlan.message(place: place.name, start: start),
                        place: place.name, start: start, end: end, busy: busy, email: info?.email)
    }

    static func merge(_ r: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        for x in r.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, x.lowerBound <= last.upperBound + 0.01 {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, x.upperBound)
            } else { out.append(x) }
        }
        return out
    }

    func update(_ p: DeckPlan) {
        if let i = plans.firstIndex(where: { $0.id == p.id }) { plans[i] = p }
        if let i = all.firstIndex(where: { $0.id == p.id }) { all[i] = p }
    }

    /// Swipe right (send) or left (skip). The last one lets the check / fade play before the end screen.
    func decide(_ p: DeckPlan, send: Bool, store: Store) {
        let last = plans.count == 1
        if last { frozenRail = (sent, skipped, p.id) }
        if send {
            bursts.append(ConfettiBurst(emojis: Near.emojis(for: p.place)))
            Task {
                if let ev = await store.addPlanToCalendar(p) { eventLinks[p.id] = ev.link; eventIds[p.id] = ev.id }
                store.sendPlanText(p)
            }
            // the plans you've made show up as the lock-screen / Dynamic Island reminder
            let made = (all.filter { sent.contains($0.id) } + [p]).map { PlansAttributes.Reminder(name: $0.name, place: $0.place, start: $0.start) }
            PlansActivity.remind(made)
        }
        withAnimation(.smooth(duration: 0.5)) { plans.removeAll { $0.id == p.id } }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
            if send { sent.append(p.id) } else { skipped.append(p.id) }
        }
        if last {
            Task {
                try? await Task.sleep(for: .seconds(0.15))
                // one quick crossfade: everything on the deck dissolves together while the end screen fades up
                withAnimation(.easeInOut(duration: 0.45)) { phase = .end }
            }
        }
    }

    /// Trash on the end screen: the card goes, and so does the event on your calendar.
    func deleteMade(_ p: DeckPlan, store: Store) {
        withAnimation(.smooth(duration: 0.35)) { sent.removeAll { $0 == p.id } }
        eventLinks[p.id] = nil
        if let id = eventIds.removeValue(forKey: p.id) { Task { await store.deletePlanEvent(id: id) } }
        if sent.isEmpty { PlansActivity.endAll() }
    }

    func openPicker() {
        picked = Array(candidates.prefix(3).map(\.personId))
        withAnimation(.easeOut(duration: 0.4)) { phase = .pick }
    }
    func savePicks() {
        savedPicks = picked.joined(separator: ",")
        withAnimation(.easeOut(duration: 0.4)) { phase = .saved }
    }
    var savedPickIds: [String] { savedPicks.split(separator: ",").map(String.init) }

    /// Demo: pretend next week started. Your picks become the deck, and the lock screen nudges you.
    func startNextWeek(store: Store) async {
        let ids = savedPickIds
        guard !ids.isEmpty else { return }
        await load(store: store, onlyIds: ids)
        PlansActivity.start(names: all.map(\.name))
    }
}
