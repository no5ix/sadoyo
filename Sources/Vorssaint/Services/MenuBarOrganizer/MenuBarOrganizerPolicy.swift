// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

extension MenuBarOrganizerCapabilities {
    static let unavailable = Self(canEnumerate: false, canMove: false,
                                  hasPrivateWindowList: false, unresolvedItemCount: 0)
}

enum MenuBarOrganizerPolicy {
    /// A divider belongs to the display containing its right edge, even when
    /// its expanded spacer extends offscreen. Never classify another display's
    /// icons against it. Offscreen ownership is ambiguous for aligned displays;
    /// omit those records rather than guess and send input to the wrong bar.
    static func recordsOnDividerDisplay(_ records: [MenuBarOrganizerWindowRecord],
                                        divider: CGRect, displays: [CGRect]) -> [MenuBarOrganizerWindowRecord]? {
        let point = CGPoint(x: divider.maxX - 1, y: divider.midY)
        let matches = displays.filter { $0.contains(point) }
        guard matches.count == 1, let display = matches.first else { return nil }
        let alignedDisplays = displays.filter { $0.minY <= divider.midY && divider.midY < $0.minY + 64 }
        return records.filter { record in
            guard abs(record.frame.midY - divider.midY) < 8 else { return false }
            if display.contains(record.frame) { return alignedDisplays.count == 1 || record.isOnScreen }
            return alignedDisplays.count == 1 && !record.isOnScreen
                && record.frame.maxX <= display.minX
                && !displays.contains(where: { $0.intersects(record.frame) })
        }
    }

    /// The main-menu level is the persistent bar itself, including hosted
    /// status items on recent macOS. Only a visible popup blocks arrangement.
    static func isOpenMenuWindow(level: Int, popupLevel: Int, isStatusItem: Bool, alpha: Double) -> Bool {
        level == popupLevel && !isStatusItem && alpha > 0
    }

    static var supportsAdvancedBackend: Bool {
        supportsAdvancedBackend(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    static func supportsAdvancedBackend(majorVersion: Int) -> Bool { (14...26).contains(majorVersion) }

    static func validFrame(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.width < 2_048 && frame.height > 0 && frame.height <= 64
    }

    /// Our own spacers deliberately span the display; ordinary item bounds
    /// remain limited separately so a malformed app window cannot become a tile.
    static func validSpacerFrame(_ frame: CGRect, maximumWidth: CGFloat) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height, maximumWidth].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.width <= maximumWidth
            && frame.height > 0 && frame.height <= 64
    }

    static func insertionFrame(_ frame: CGRect, after: Bool) -> CGRect {
        CGRect(x: after ? frame.maxX - 1 : frame.minX, y: frame.minY,
               width: 1, height: frame.height)
    }

    /// Our own separator controls report AppKit's logical frame through
    /// Accessibility. With system-hosted status items an expanded spacer's
    /// logical frame can begin left of its own menu bar and span two displays,
    /// so route destinations and exclusions must use the window actually
    /// rendered inside one display. A window qualifies only when it sits in
    /// the logical frame's band and mostly fits inside it; no qualifying
    /// window is a fail-closed nil, never a guessed rectangle.
    static func physicalSeparatorRecord(matching logical: CGRect,
                                        in records: [MenuBarOrganizerWindowRecord],
                                        maximumWidthSlack: CGFloat = 0,
                                        minimumWidthFraction: CGFloat = 0) -> MenuBarOrganizerWindowRecord? {
        guard logical.width > 0, logical.height > 0,
              [logical.minX, logical.minY, logical.midY].allSatisfy(\.isFinite) else { return nil }
        var best: (record: MenuBarOrganizerWindowRecord, score: CGFloat)?
        for record in records where record.isOnScreen && record.alpha > 0 {
            guard [record.frame.minX, record.frame.midY].allSatisfy(\.isFinite),
                  record.frame.width > 0, record.frame.height > 0 else { continue }
            // A resting separator is a narrow control; a spacer is a wide
            // strip. A window of the other class covering the same logical
            // frame is a neighbour, never the control itself.
            let isNarrowControl = maximumWidthSlack > 0
            if isNarrowControl, record.frame.width > logical.width + maximumWidthSlack { continue }
            if minimumWidthFraction > 0, record.frame.width < logical.width * minimumWidthFraction { continue }
            guard abs(record.frame.midY - logical.midY)
                    <= max(record.frame.height, logical.height) / 2 + 4 else { continue }
            var score: CGFloat
            if isNarrowControl {
                // AppKit's slot math and the host's rendered window differ by
                // the spacer clamping, so a narrow control is matched by
                // horizontal proximity, not by frame overlap.
                let xGap = max(record.frame.minX, logical.minX) - min(record.frame.maxX, logical.maxX)
                guard xGap <= 64 else { continue }
                score = -max(xGap, 0)
            } else {
                let overlap = record.frame.intersection(logical)
                guard !overlap.isNull else { continue }
                guard overlap.width >= min(record.frame.width, logical.width) * 0.6,
                      overlap.height >= min(record.frame.height, logical.height) * 0.6 else { continue }
                score = overlap.width * overlap.height
            }
            if best == nil || score > best!.score { best = (record, score) }
        }
        return best?.record
    }

    /// The frontmost on-screen window covering an insertion point. Synthetic
    /// events route by "window under the pointer", and the app's own
    /// WindowServer connection cannot name a system-hosted divider, so the
    /// public list resolves it. Records arrive front-to-back.
    static func windowRecord(under point: CGPoint,
                             in records: [MenuBarOrganizerWindowRecord]) -> MenuBarOrganizerWindowRecord? {
        records.first { $0.isOnScreen && $0.alpha > 0 && $0.frame.contains(point) }
    }

    /// Search all words in order within the name, then prefer contiguous matches.
    static func searchScore(query: String, name: String) -> Int? {
        let query = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return 0 }
        if name.hasPrefix(query) { return 0 }
        if name.contains(query) { return 1 }
        var remaining = name[...]
        var score = 2
        for character in query where !character.isWhitespace {
            guard let index = remaining.firstIndex(of: character) else { return nil }
            score += remaining.distance(from: remaining.startIndex, to: index)
            remaining = remaining[remaining.index(after: index)...]
        }
        return score
    }

    static func uniquelyIdentified(_ id: MenuBarItemIdentity, in items: [ManagedMenuBarItem], allowProtected: Bool = false) -> ManagedMenuBarItem? {
        let matches = items.filter { $0.id.bundleIdentifier == id.bundleIdentifier && $0.id.title == id.title }
        guard matches.count == 1, let item = matches.first, item.id == id,
              item.identityState == .stable, (allowProtected || !item.isProtected),
              validFrame(item.frame) else { return nil }
        return item
    }

    static func canActivate(_ item: ManagedMenuBarItem) -> Bool {
        item.section != .alwaysHidden && !item.isProtected && item.identityState == .stable
    }

    static func verifiedMove(windowID: CGWindowID, before targetID: CGWindowID?,
                             section: MenuBarOrganizerSection, items: [ManagedMenuBarItem]) -> Bool {
        let matches = items.filter { $0.windowID == windowID }
        guard matches.count == 1, let item = matches.first, item.section == section else { return false }
        let targetIdentity: MenuBarItemIdentity? = targetID.flatMap { target in
            items.first { $0.windowID == target }.map(\.id)
        }
        return verifiedPlacement(of: item.id, before: targetIdentity, section: section, items: items)
    }

    /// A system host may re-wrap a moved item in a fresh window, so placement
    /// is verified by stable identity, not by window number.
    static func verifiedPlacement(of movedID: MenuBarItemIdentity, before targetID: MenuBarItemIdentity?,
                                  section: MenuBarOrganizerSection, items: [ManagedMenuBarItem]) -> Bool {
        let matches = items.filter { $0.id == movedID }
        guard matches.count == 1, let item = matches.first, item.section == section else { return false }
        let ordered = MenuBarOrganizerSupport.orderedItems(items, in: section)
        guard let targetID else { return ordered.last?.id == movedID }
        guard let index = ordered.firstIndex(where: { $0.id == movedID }),
              index + 1 < ordered.count else { return false }
        return ordered[index + 1].id == targetID
    }

    /// Inserting before an item leaves that item's right-anchored position
    /// unchanged. Reserve the selected item's whole width plus a drag margin,
    /// avoiding the notch, another display, and ambiguous destination identities.
    static func activationTarget(for item: ManagedMenuBarItem, in items: [ManagedMenuBarItem],
                                 strip: CGRect) -> ManagedMenuBarItem? {
        orderedActivationCandidates(items).first { candidate in
            guard candidate.id != item.id,
                  uniquelyIdentified(candidate.id, in: items, allowProtected: true) != nil,
                  abs(candidate.frame.midY - item.frame.midY) < 8 else { return false }
            let space = CGRect(x: candidate.frame.minX - item.frame.width - 2,
                               y: candidate.frame.minY, width: item.frame.width + 2,
                               height: item.frame.height)
            return strip.contains(candidate.frame) && strip.contains(space)
        }
    }

    private static func orderedActivationCandidates(_ items: [ManagedMenuBarItem]) -> [ManagedMenuBarItem] {
        Array(MenuBarOrganizerSupport.orderedItems(items, in: .visible).reversed())
    }

    static func isOwnItem(ownerPID: pid_t, sourcePID: pid_t?, bundleIdentifier: String,
                          currentPID: pid_t, currentBundleIdentifier: String?) -> Bool {
        ownerPID == currentPID || sourcePID == currentPID
            || (currentBundleIdentifier.map { $0 == bundleIdentifier } ?? false)
    }

    static let conflictingBundleIDs: Set<String> = [
        "com.jordanbaird.Ice", "com.surteesstudios.Bartender", "com.surteesstudios.Bartender5",
        "com.surteesstudios.Bartender6", "com.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar",
        "com.stonerl.Thaw"
    ]

    static func conflictingManagers() -> [String] {
        NSWorkspace.shared.runningApplications.filter {
            conflictingBundleIDs.contains($0.bundleIdentifier ?? "") && !$0.isTerminated
        }.compactMap(\.localizedName).sorted()
    }
}

/// A pending synthetic button and hidden cursor must be released synchronously
/// on disable/quit, even if the suspended task cannot resume its defer yet.
final class MenuBarInputCleanup {
    var release: (() -> Void)?
    var restoreCursor: (() -> Void)?
    func finish() {
        let release = self.release
        let restore = restoreCursor
        self.release = nil
        restoreCursor = nil
        release?()
        restore?()
    }
}
