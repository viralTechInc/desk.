import Foundation
import CoreGraphics

/// Maps minutes-from-midnight to vertical points and back. Shared by Day and Week.
struct TimelineGeometry: Equatable, Sendable {
    /// First rendered hour (inclusive).
    var startHour: Int
    /// Last rendered hour (exclusive end boundary, e.g. 22 renders through 22:00).
    var endHour: Int
    var hourHeight: CGFloat

    init(startHour: Int = 6, endHour: Int = 22, hourHeight: CGFloat = 64) {
        let s = min(max(startHour, 0), 23)
        let e = min(max(endHour, s + 1), 24)
        self.startHour = s
        self.endHour = e
        self.hourHeight = hourHeight
    }

    var startMinutes: Int { startHour * 60 }
    var endMinutes: Int { endHour * 60 }
    var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }
    var hours: [Int] { Array(startHour...endHour) }
    var minuteHeight: CGFloat { hourHeight / 60 }

    func y(forMinutes minutes: Int) -> CGFloat {
        CGFloat(minutes - startMinutes) * minuteHeight
    }

    func minutes(forY y: CGFloat) -> Int {
        let raw = Int((y / minuteHeight).rounded(.down)) + startMinutes
        return min(max(raw, 0), TimeRules.dayMinutes)
    }

    func snappedMinutes(forY y: CGFloat) -> Int {
        min(max(TimeRules.snap(minutes(forY: y)), startMinutes), endMinutes)
    }

    func height(forDuration minutes: Int) -> CGFloat {
        CGFloat(minutes) * minuteHeight
    }

    /// Expands the rendered range so the given events are never hidden.
    func expanded<Item: TimelineItem>(toInclude events: [Item]) -> TimelineGeometry {
        var g = self
        for e in events {
            g.startHour = min(g.startHour, e.startMinutes / 60)
            g.endHour = max(g.endHour, Int((Double(e.endMinutes) / 60).rounded(.up)))
        }
        g.startHour = max(0, g.startHour)
        g.endHour = min(24, max(g.endHour, g.startHour + 1))
        return g
    }
}

/// Side-by-side layout for overlapping items within a single day column.
struct LaidOutItem<Item: TimelineItem>: Identifiable, Equatable {
    let item: Item
    /// Zero-based column index within the overlap cluster.
    let column: Int
    /// Number of columns in the cluster.
    let columnCount: Int
    var id: String { item.id }

    /// Horizontal fraction of the column this item occupies.
    var xFraction: CGFloat { CGFloat(column) / CGFloat(columnCount) }
    var widthFraction: CGFloat { 1 / CGFloat(columnCount) }
}

typealias LaidOutEvent = LaidOutItem<EventOccurrence>

extension LaidOutItem where Item == EventOccurrence {
    var event: EventOccurrence { item }
}

enum OverlapLayout {
    /// Visual height for an item. Very short items are given `floor` so their label stays
    /// readable, but never so much that they cover the next item in the same lane: a
    /// 12:00–12:15 block followed by one at 12:15 keeps its true (thin) height instead.
    static func visualHeight<Item: TimelineItem>(
        of item: LaidOutItem<Item>, among items: [LaidOutItem<Item>],
        geometry: TimelineGeometry, floor: CGFloat, inset: CGFloat = 2
    ) -> CGFloat {
        let natural = geometry.height(forDuration: item.item.endMinutes - item.item.startMinutes) - inset
        guard natural < floor else { return natural }
        let nextStart = items.lazy
            .filter { other in
                other.id != item.id
                    && other.item.startMinutes >= item.item.endMinutes
                    && other.xFraction < item.xFraction + item.widthFraction
                    && item.xFraction < other.xFraction + other.widthFraction
            }
            .map(\.item.startMinutes)
            .min()
        guard let nextStart else { return max(natural, floor) }
        let room = geometry.y(forMinutes: nextStart) - geometry.y(forMinutes: item.item.startMinutes) - inset
        return max(natural, min(floor, room))
    }

    /// Classic interval-graph column packing. Items that transitively overlap form a
    /// cluster; each cluster is split into the minimum number of columns greedily.
    static func layout<Item: TimelineItem>(_ items: [Item]) -> [LaidOutItem<Item>] {
        let sorted = items.sorted { a, b in
            if a.startMinutes != b.startMinutes { return a.startMinutes < b.startMinutes }
            if a.endMinutes != b.endMinutes { return a.endMinutes > b.endMinutes }
            return a.id < b.id
        }
        var result: [LaidOutItem<Item>] = []
        var cluster: [(Item, Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = Int.min

        func flush() {
            let count = max(columnEnds.count, 1)
            for (e, col) in cluster {
                result.append(LaidOutItem(item: e, column: col, columnCount: count))
            }
            cluster.removeAll()
            columnEnds.removeAll()
            clusterEnd = Int.min
        }

        for e in sorted {
            if !cluster.isEmpty && e.startMinutes >= clusterEnd { flush() }
            var placed = false
            for (i, end) in columnEnds.enumerated() where e.startMinutes >= end {
                columnEnds[i] = e.endMinutes
                cluster.append((e, i))
                placed = true
                break
            }
            if !placed {
                columnEnds.append(e.endMinutes)
                cluster.append((e, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, e.endMinutes)
        }
        flush()
        return result
    }
}
