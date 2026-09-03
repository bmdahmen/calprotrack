import WidgetKit
import SwiftUI

/// Reads the shared snapshot written by CalProTrackAPI (see
/// `SharedTotals.swift`) — no network calls or session token in this
/// target, it just displays whatever the main app last pushed.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TotalsEntry {
        TotalsEntry(date: Date(), totals: TodayTotals(cal: 1850, pro: 92, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (TotalsEntry) -> Void) {
        completion(TotalsEntry(date: Date(), totals: SharedTotals.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TotalsEntry>) -> Void) {
        let entry = TotalsEntry(date: Date(), totals: SharedTotals.load())
        // The main app pokes WidgetCenter.reloadAllTimelines() directly
        // after every load/log, so this periodic refresh is just a
        // fallback for whenever the app hasn't been opened in a while.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct TotalsEntry: TimelineEntry {
    let date: Date
    let totals: TodayTotals?
}

struct CalProTrackWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    private var cal: Int { entry.totals?.cal ?? 0 }
    private var pro: Int { entry.totals?.pro ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(cal)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("\(pro)g")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.purple)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(cal) kcal")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("\(pro)g protein")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        case .accessoryCorner:
            // .accessoryCorner only curves the .widgetLabel text along the
            // bezel — the main content next to it is meant to stay small
            // (an icon), not a full number, or it renders flat instead of
            // hugging the arc. It renders as a monochrome silhouette using
            // the image's alpha channel, so this needs a Logo asset with a
            // real transparent background (Logo-transparent.png) rather
            // than the opaque app-icon PNG — that one just showed up as a
            // solid blob. The curved label text is forced to uppercase by
            // the system regardless of the string's own case (confirmed —
            // even .textCase(.lowercase) doesn't override it), so the
            // wording is picked to read fine in caps instead of fighting
            // that.
            // Must be explicitly sized — .scaledToFit() alone doesn't
            // shrink anything, it just preserves aspect ratio within
            // whatever frame it's given, so without this it rendered at
            // the source PNG's native 1024x1024 and blew way past
            // WidgetKit's ~91x91pt archival limit for this slot, which
            // silently failed the whole complication (the blank bars).
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .widgetLabel {
                    Text("\(cal) • \(pro)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
        default:
            Text("\(cal) kcal · \(pro)g")
        }
    }
}

@main
struct CalProTrackWidget: Widget {
    let kind: String = "CalProTrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CalProTrackWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calories & Protein")
        .description("Today's totals from CalProTrack.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview(as: .accessoryRectangular) {
    CalProTrackWidget()
} timeline: {
    TotalsEntry(date: .now, totals: TodayTotals(cal: 1850, pro: 92, updatedAt: .now))
}
