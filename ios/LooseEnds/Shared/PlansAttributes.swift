import ActivityKit
import SwiftUI

/// The weekly nudge on the lock screen / Dynamic Island: the people you picked last week.
struct PlansAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var names: [String]
        /// When set, it's a reminder of today's plans instead of the weekly "make plans" nudge.
        var today: [Reminder] = []
    }
    struct Reminder: Codable, Hashable {
        var name: String
        var place: String
        var start: Date
    }
}

extension PlansAttributes.ContentState {
    /// "Ruby, Omar and Hana"
    var list: String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

extension PlansAttributes.ContentState {
    /// "Zingerman's Deli with Ruby at 1:30 and Miss Kim with Omar at 7:00"
    var reminderLine: String {
        let parts = today.map { "\($0.place) with \($0.name) \($0.when)" }
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

extension PlansAttributes.Reminder {
    /// "at 1:30" today, "tomorrow at 7:00", "Sat at 7:00"
    var when: String {
        let cal = Calendar.current
        if cal.isDateInToday(start) { return "at \(clock)" }
        if cal.isDateInTomorrow(start) { return "tomorrow at \(clock)" }
        return start.formatted(.dateTime.weekday(.abbreviated)) + " at \(clock)"
    }
    var end: Date { start.addingTimeInterval(3600) }
    /// "1:30"
    var clock: String { let c = Calendar.current.dateComponents([.hour, .minute], from: start); let h = (c.hour ?? 0) % 12; return "\(h == 0 ? 12 : h):" + String(format: "%02d", c.minute ?? 0) }
    /// "7:00 pm"
    var time: String { start.formatted(.dateTime.hour().minute()).lowercased().replacingOccurrences(of: "\u{202F}", with: " ") }
}

/// Today's plans, one row each: face, "Miss Kim with Omar", the time on the right.
struct ReminderRows: View {
    let plans: [PlansAttributes.Reminder]
    var ink: Color = .black
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(plans.prefix(3).enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    ActivityFaces(names: [r.name], ring: .clear)
                    Text("\(r.place) with \(r.name)").font(.system(size: 17)).foregroundStyle(ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(r.time).font(.system(size: 15, weight: .medium)).foregroundStyle(ink.opacity(0.45))
                }
            }
        }
    }
}

/// Gray initial circles, overlapped a little (4pt). Where two overlap, a thin gap is cut out of the
/// one behind, so the card's own glass shows through as the divider (no painted line).
struct ActivityFaces: View {
    let names: [String]
    var size: CGFloat = 24
    var ring: Color = .clear   // kept for call sites; the divider is a cut-out now
    var body: some View {
        let shown = Array(names.prefix(4))
        HStack(spacing: -4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { k, n in
                Text(String(n.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: [Color(red: 0.647, green: 0.663, blue: 0.706), Color(red: 0.490, green: 0.506, blue: 0.549)],
                                               startPoint: .top, endPoint: .bottom), in: Circle())
                    .mask {
                        if k < shown.count - 1 {
                            // the next face sits (size - 4) to the right; cut a slightly bigger circle there
                            Rectangle()
                                .overlay(Circle().frame(width: size + 3, height: size + 3).offset(x: size - 4).blendMode(.destinationOut))
                                .compositingGroup()
                        } else {
                            Rectangle()
                        }
                    }
                    .zIndex(Double(k))
            }
        }
    }
}
