import SwiftUI

/// A colored time block: soft fill, strong left bar, legible ink.
struct TimeBlockView: View {
    let occurrence: EventOccurrence
    var isSelected = false
    var isDimmed = false
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = occurrence.category.color
        let ink = scheme == .dark ? Color.white.opacity(0.92) : occurrence.category.inkColor
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(occurrence.displayTitle)
                        .font(compact ? Font.system(size: 11.5, weight: .medium) : Theme.eventLabel)
                        .lineLimit(compact ? 1 : 2)
                    if occurrence.isRecurring {
                        Image(systemName: occurrence.isException ? "arrow.trianglehead.2.clockwise.rotate.90" : "repeat")
                            .font(.system(size: 8.5, weight: .semibold))
                            .opacity(0.55)
                            .accessibilityHidden(true)
                    }
                    if compact {
                        Spacer(minLength: 0)
                        Text(TimeFormat.clock(occurrence.startMinutes, compact: true))
                            .font(Font.system(size: 10.5)).opacity(0.75).lineLimit(1)
                    }
                }
                if !compact {
                    Text(TimeFormat.range(occurrence.startMinutes, occurrence.endMinutes))
                        .font(Theme.eventTime)
                        .opacity(0.78)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.vertical, compact ? 2 : 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(scheme == .dark ? 0.34 : 0.19))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isSelected ? color : color.opacity(0.0), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .opacity(isDimmed ? 0.35 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
