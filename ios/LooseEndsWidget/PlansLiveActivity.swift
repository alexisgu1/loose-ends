import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LooseEndsWidgets: WidgetBundle {
    var body: some Widget { PlansLiveActivity() }
}

/// Live Activity rules: no custom swipes (swipe left is the system's Clear), tap opens the app.
struct PlansLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlansAttributes.self) { ctx in
            // Lock screen: faces, then one line naming them. White, hugs its content.
            // Reminder: the same card, one row per plan today.
            Group {
                if ctx.state.today.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ActivityFaces(names: ctx.state.names)
                        Text("Make plans with \(ctx.state.list) this week")
                            .font(.system(size: 17))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Reminder: same card, faces then one line with where and when
                    VStack(alignment: .leading, spacing: 12) {
                        ActivityFaces(names: ctx.state.names)
                        Text(ctx.state.reminderLine)
                            .font(.system(size: 17))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(.white)
            .activitySystemActionForegroundColor(.black)
            .widgetURL(URL(string: "looseends://deck"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if ctx.state.today.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ActivityFaces(names: ctx.state.names, ring: .black)
                                Text("Make plans with \(ctx.state.list) this week").font(.system(size: 17)).lineLimit(2)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ActivityFaces(names: ctx.state.names, ring: .black)
                                Text(ctx.state.reminderLine).font(.system(size: 17)).lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                // reminder: just the next person; nudge: everyone you picked
                if let next = ctx.state.today.first {
                    ActivityFaces(names: [next.name], size: 22)
                } else {
                    ActivityFaces(names: ctx.state.names, size: 22, ring: .black)
                }
            } compactTrailing: {
                // reminder: when that plan is ("Sat 7:00"); nudge: how many to make
                if let next = ctx.state.today.first {
                    Text(next.shortWhen).font(.system(size: 15, weight: .medium))
                } else {
                    Text("\(ctx.state.names.count) plans").font(.system(size: 15, weight: .medium))
                }
            } minimal: {
                ActivityFaces(names: Array(ctx.state.names.prefix(1)), size: 22, ring: .black)
            }
            .widgetURL(URL(string: "looseends://deck"))
        }
    }
}
