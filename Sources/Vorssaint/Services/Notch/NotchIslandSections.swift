// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// A part of the open island's stacked surface. The island shows the parts it
/// has rather than one page at a time, so a song and a timer keep their place
/// when either starts, and a monitoring detail opened from the menu bar adds
/// itself to the stack instead of replacing what is in it.
///
/// The detail carries no kind: the island shows one at a time, and its kind
/// stays the island's own state, so switching to another detail updates the
/// same part instead of rebuilding it.
enum NotchStackedSection: Hashable {
    case music
    case timer
    case detail
    case explore
}

extension NotchStackedSection: Identifiable {
    var id: String {
        switch self {
        case .music: return "music"
        case .timer: return "timer"
        case .detail: return "detail"
        case .explore: return "explore"
        }
    }
}

/// One part of the stack with the height the island keeps for it, so the
/// island and its page agree on the height before either is drawn.
struct NotchStackedPart: Hashable, Identifiable {
    let section: NotchStackedSection
    let height: CGFloat
    var id: String { section.id }
}

enum NotchStackedSections {
    /// Only Explore or a monitoring detail stacks. A page of its own keeps the
    /// island's whole area, as it did before the stack, and the Command Bar
    /// and the app panel still cover the island end to end.
    static func stacks(gallery: Bool, detail: Bool, appPanel: Bool, commandBar: Bool) -> Bool {
        !commandBar && (gallery || (detail && !appPanel))
    }

    /// The parts in the order the island draws them. Explore closes the stack
    /// whatever else is in it, so an activity or a detail never takes the way
    /// to the sections away, and a stack with nothing running is the gallery
    /// alone.
    static func visible(stacks: Bool, music: Bool, timer: Bool, detail: Bool) -> [NotchStackedSection] {
        guard stacks else { return [] }
        var sections: [NotchStackedSection] = []
        if music { sections.append(.music) }
        if timer { sections.append(.timer) }
        if detail { sections.append(.detail) }
        sections.append(.explore)
        return sections
    }

    /// Each part at the height its own page measures, in the same order.
    static func parts(_ sections: [NotchStackedSection], music: CGFloat, timer: CGFloat,
                      detail: CGFloat, gallery: CGFloat) -> [NotchStackedPart] {
        sections.map { section in
            let height: CGFloat
            switch section {
            case .music: height = music
            case .timer: height = timer
            case .detail: height = detail
            case .explore: height = gallery
            }
            return NotchStackedPart(section: section, height: max(0, height))
        }
    }

    /// The whole stack: every part, with the island's row spacing between two.
    static func contentHeight(parts: [NotchStackedPart]) -> CGFloat {
        let heights = parts.reduce(0) { $0 + $1.height }
        return heights + (parts.isEmpty ? 0 : NotchLayout.spacing * CGFloat(parts.count - 1))
    }
}
