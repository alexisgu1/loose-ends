import Foundation
import UserNotifications

/// The nightly lock-screen nudge ("3 people worth a text tonight").
enum Nudge {
    static let tonightID = "loose-ends.tonight"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func content(for cards: [Card]) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        let names = cards.map(\.firstName)
        switch cards.count {
        case 0:
            c.title = "Who's worth a text tonight?"
            c.body = "Open Loose Ends to see who you might be letting slip."
        case 1:
            c.title = "\(names[0]) is worth a text tonight"
            c.body = cards[0].loop.why
        default:
            c.title = "\(cards.count) people worth a text tonight"
            let rest = names.dropFirst()
            let others = rest.count == 1 ? rest.first! : rest.dropLast().joined(separator: ", ") + " and " + rest.last!
            c.body = "\(cards[0].loop.why) Plus \(others)."
        }
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        return c
    }

    /// Tonight's nudge with real names, plus a generic one for each of the next 6 nights
    /// in case the app isn't opened (each open replaces them with fresh content).
    static func scheduleTonight(cards: [Card], hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        let ids = [tonightID] + (1...6).map { "loose-ends.night\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let cal = Calendar.current
        var next = cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        if next <= Date() { next = cal.date(byAdding: .day, value: 1, to: next)! }

        for (i, id) in ids.enumerated() {
            let date = cal.date(byAdding: .day, value: i, to: next)!
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let body = i == 0 && !cards.isEmpty ? content(for: cards) : content(for: [])
            center.add(UNNotificationRequest(identifier: id, content: body, trigger: trigger))
        }
    }

    /// For demos: fire tonight's nudge a few seconds from now.
    static func preview(cards: [Card], in seconds: TimeInterval = 5) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "loose-ends.preview", content: content(for: cards), trigger: trigger)
        )
    }
}
