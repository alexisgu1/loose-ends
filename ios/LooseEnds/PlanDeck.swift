import SwiftUI

// MARK: - Places within ~1 mile of the UMich Diag (walking distances are approximate)

struct NearPlace: Equatable {
    let name: String
    let emoji: String
}

enum Near {
    // Sit-down restaurants (no coffee/boba/dessert spots), downtown, State St, South U and Kerrytown.
    static let all: [NearPlace] = [
        .init(name: "Miss Kim", emoji: "🥢"), .init(name: "Sava's", emoji: "🍝"), .init(name: "Tomukun", emoji: "🍜"),
        .init(name: "Slurping Turtle", emoji: "🍜"), .init(name: "Frita Batidos", emoji: "🍔"), .init(name: "Mani Osteria", emoji: "🍕"),
        .init(name: "Jerusalem Garden", emoji: "🧆"), .init(name: "Zingerman's Deli", emoji: "🥪"), .init(name: "Pizza House", emoji: "🍕"),
        .init(name: "Madras Masala", emoji: "🍛"), .init(name: "Ahmo's", emoji: "🥙"), .init(name: "Isalita", emoji: "🌮"),
        .init(name: "Jolly Pumpkin", emoji: "🍺"), .init(name: "Aventura", emoji: "🥘"), .init(name: "Spiedo", emoji: "🍝"),
    ]
    /// More emojis per place for the confetti.
    static let confetti: [String: String] = [
        "Miss Kim": "🥢🍜🍚🥟", "Sava's": "🍝🍷🥗", "Tomukun": "🍜🥢🍥", "Bubble Island": "🧋🍡", "Comet Coffee": "☕️🥐",
        "Frita Batidos": "🍔🥤🍟", "Jerusalem Garden": "🧆🥙🫓", "Slurping Turtle": "🍜🥢🍣", "Blank Slate": "🍦🍨", "Zingerman's Deli": "🥪🥯🧀",
        "Pizza House": "🍕🥤", "Mani Osteria": "🍕🍷", "Madras Masala": "🍛🫓", "Ahmo's": "🥙🧆",
        "Isalita": "🌮🌯", "Jolly Pumpkin": "🍺🍕", "Aventura": "🥘🍷🫒", "Spiedo": "🍝🍷",
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
        return all
            .compactMap { p -> (NearPlace, String.Index)? in
                guard let r = low.range(of: p.name.lowercased()) else { return nil }
                return (p, r.lowerBound)
            }
            .min { $0.1 < $1.1 }?.0
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

    /// Swap the place, in the text too (any case). If the text never named it, the text stays.
    mutating func swapPlace(to new: String) {
        for variant in [place, place.replacingOccurrences(of: "'", with: "’")] {
            if let r = text.range(of: variant, options: .caseInsensitive) {
                text.replaceSubrange(r, with: new)
                break
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
        return "Hi! Let's get \(place) \(when)!"
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
            Task { await store.addPlanToCalendar(p); store.sendPlanText(p) }
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
