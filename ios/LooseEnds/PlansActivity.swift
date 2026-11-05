import ActivityKit
import Foundation

/// Starts / ends the weekly "make plans" Live Activity. Tapping it opens the app (looseends://deck).
enum PlansActivity {
    static func start(names: [String]) {
        endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !names.isEmpty else { return }
        _ = try? Activity.request(attributes: PlansAttributes(),
                                  content: .init(state: .init(names: names), staleDate: nil),
                                  pushType: nil)
    }

    /// Today's plans, as a reminder on the lock screen and in the Dynamic Island. Goes stale at midnight.
    static func remind(_ plans: [PlansAttributes.Reminder]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !plans.isEmpty else { return }
        let sorted = plans.sorted { $0.start < $1.start }
        let state = PlansAttributes.ContentState(names: sorted.map(\.name), today: sorted)
        let content = ActivityContent(state: state, staleDate: sorted.last?.end ?? nil)
        Task {
            // update the reminder that's already up (no flicker); otherwise start one
            if let a = Activity<PlansAttributes>.activities.first(where: { !$0.content.state.today.isEmpty }) {
                await a.update(content)
            } else {
                for a in Activity<PlansAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                _ = try? Activity.request(attributes: PlansAttributes(), content: content, pushType: nil)
            }
        }
    }

    /// Demo: two plans later today, for seeing the reminder.
    static func demoToday() {
        let now = Date.now, cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now)! }
        var first = at(13, 30), second = at(19, 0)
        if first < now { first = max(now.addingTimeInterval(3600), first) }   // keep both in the future
        if second <= first { second = first.addingTimeInterval(4 * 3600) }
        remind([.init(name: "Ruby", place: "Kang's", start: first),
                .init(name: "Omar", place: "Sava's", start: second)])
    }

    static func endAll() {
        Task {
            for a in Activity<PlansAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
