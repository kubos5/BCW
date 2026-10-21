import ActivityKit
import SwiftUI
import WidgetKit

/// Attività in diretta "Orario di oggi" (avviata e aggiornata dall'app, `LiveActivityManager`):
/// schermata di blocco e banner, Dynamic Island compatta, minima ed espansa. Le viste sono in
/// `Shared/LiveActivity`.
struct TimetableLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimetableActivityAttributes.self) { context in
            TimetableActivityLockView(state: context.state, isStale: context.isStale)
                .widgetURL(Self.url(context.attributes))
        } dynamicIsland: { context in
            let island = TimetableActivityIsland(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    island.expandedLeading
                }
                DynamicIslandExpandedRegion(.center) {
                    island.expandedCenter
                }
                DynamicIslandExpandedRegion(.bottom) {
                    island.expandedBottom
                }
            } compactLeading: {
                island.compactLeading
            } compactTrailing: {
                island.compactTrailing
            } minimal: {
                island.minimal
            }
            .keylineTint(island.accent)
            .widgetURL(Self.url(context.attributes))
        }
    }

    /// Tocco: l'Orario sul giorno dell'attività.
    static func url(_ attributes: TimetableActivityAttributes) -> URL {
        DeepLink.timetable(BCWShared.day(fromKey: attributes.dayKey)).url
    }
}
