// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// The island's one height rule, shared by every page and every display.
///
/// A page is as tall as the content it draws - its own heading, its cards, the
/// spacing between them, and the margins the island keeps around the page - and
/// never taller than 80% of the display that hosts the island. The limit is
/// applied to the height a page asks for, and that height is read from what the
/// page has to show, never from the island's own height, so the limit cannot
/// inflate the measurement it is applied to. A short page therefore stays
/// short, a long one stops at the limit and scrolls, and a page that loses
/// content shrinks with it.
///
/// Every page goes through `resolve`: no section keeps a height of its own, and
/// a preset's height is only a floor beneath a page, never a ceiling over it.
enum NotchHeightPolicy {
    /// The tallest island, as a fraction of the height of the display that
    /// hosts it. An absolute maximum, never a default height.
    static let maximumFraction: CGFloat = 0.8

    /// The tallest island a display this tall allows. An unknown display
    /// allows nothing, so the caller's own floor decides.
    static func maximumHeight(displayHeight: CGFloat) -> CGFloat {
        guard displayHeight.isFinite, displayHeight > 0 else { return 0 }
        return (displayHeight * maximumFraction).rounded(.down)
    }

    /// Resolve a page against the tallest island the caller allows.
    ///
    /// - Parameter natural: what the page's content measures, before any limit.
    /// - Parameter chromeHeight: the island's own row, its gaps and its bottom
    ///   margin, which the page's height is measured inside.
    /// - Parameter maximumSurfaceHeight: the tallest island, which the caller
    ///   reads from the display that hosts it. A limit, never a height.
    /// - Parameter minimumContentHeight: the shortest page that stays usable,
    ///   kept below the limit rather than past it.
    static func resolve(contentHeight natural: CGFloat, chromeHeight: CGFloat,
                        maximumSurfaceHeight limit: CGFloat,
                        minimumContentHeight: CGFloat = 0) -> NotchSurfaceHeight {
        let page = natural.isFinite ? max(0, natural) : 0
        let chrome = chromeHeight.isFinite ? max(0, chromeHeight) : 0
        let ceiling = max(0, (limit.isFinite ? max(0, limit) : 0) - chrome)
        let floor = min(max(0, minimumContentHeight.isFinite ? minimumContentHeight : 0), ceiling)
        let content = min(max(page, floor), ceiling)
        return NotchSurfaceHeight(surfaceHeight: chrome + content, contentHeight: content,
                                  naturalContentHeight: page, ceiling: ceiling,
                                  scrolls: page > ceiling + 0.5,
                                  atMaximum: content >= ceiling - 0.5 && page > ceiling - 0.5)
    }

    /// Resolve a page on a display of `displayHeight`, whose height gives the
    /// rule its 80%, less the `clearance` the display's edge and the floating
    /// controls keep below the island. This is the rule as such: a page, a
    /// display, and nothing else.
    static func resolve(contentHeight natural: CGFloat, chromeHeight: CGFloat, displayHeight: CGFloat,
                        minimumContentHeight: CGFloat = 0, clearance: CGFloat = 0) -> NotchSurfaceHeight {
        let cap = maximumHeight(displayHeight: displayHeight)
        // The island hangs from the top of the display, so the display's own
        // height bounds it, less what the edge and the floating controls keep.
        let limit = displayHeight.isFinite && displayHeight > 0
            ? max(0, min(cap, displayHeight - max(0, clearance))) : cap
        return resolve(contentHeight: natural, chromeHeight: chromeHeight, maximumSurfaceHeight: limit,
                       minimumContentHeight: minimumContentHeight)
    }
}

/// The height one island page resolves to on one display.
struct NotchSurfaceHeight: Equatable {
    /// The island on screen: its chrome and the page inside it.
    var surfaceHeight: CGFloat
    /// The page's height inside that chrome, which the page is laid out at.
    var contentHeight: CGFloat
    /// What the page asked for, before the display's limit.
    var naturalContentHeight: CGFloat
    /// The tallest page the display allows, which the page is measured against.
    var ceiling: CGFloat
    /// The page is taller than the island, so it scrolls to its last row.
    var scrolls: Bool
    /// The limit is what the island shows.
    var atMaximum: Bool
}

/// What one page has to show, read apart from the island's own size.
///
/// The island reads these counts, not a page's height: the page's height
/// follows from them, so the panel measures its content without measuring the
/// height the panel is already showing.
struct NotchPageContent: Equatable {
    /// Cards on the clipboard page.
    var clipboardEntries = 0
    /// The clipboard page's search field, which takes a row of its own.
    var clipboardSearch = false
    /// The clipboard page's comfortable cards, rather than its compact ones.
    var clipboardComfortable = false
    /// Cards on the notifications page.
    var notificationCards = 0
    /// Cards on the Downloads page.
    var downloadCards = 0
    /// Tiles on the Files page's shelf.
    var shelfTiles = 0
    /// Cards of the recent captures grid.
    var captureTiles = 0
    /// Reading cards on the System page.
    var systemCards = 0
    /// Marks on the launcher's rail.
    var tools = 0
    /// The mixer's microphone fader, beside the output's.
    var mixerMicrophone = false
    /// The calendar page draws the month, not only the week and its agenda.
    var calendarMonth = false
    /// The Splash page has a dashboard to draw: a reading running, a task
    /// frozen at the end of one, or a last reading kept after the way out.
    /// Without one, the page is its ruler and the words of what to do next.
    var splashDashboard = false

    static let empty = NotchPageContent()
}

/// What a page's content measures at the width the island offers it.
///
/// Each function is the page's own arithmetic with the page's own constants, so
/// the island never reserves a row the page cannot draw, nor a shorter one than
/// the page fills. Nothing here is capped: `NotchHeightPolicy` applies the
/// display's limit to what these return.
enum NotchNaturalContent {
    /// Rails of cards: every item drawn, not only the rows a height allows.
    static func rail(count: Int, itemWidth: CGFloat, itemHeight: CGFloat, spacing: CGFloat, width: CGFloat,
                     insets: CGFloat = 0) -> CGFloat {
        guard count > 0 else { return NotchLayout.emptyHeight }
        let capacity = NotchLayout.railCapacity(width: max(0, width - insets * 2), itemWidth: itemWidth, spacing: spacing)
        let rows = (count + capacity - 1) / capacity
        return NotchLayout.railHeight(rows: rows, rowHeight: itemHeight, spacing: spacing) + insets * 2
    }

    static func height(module: NotchModule, items: NotchPageContent, width: CGFloat) -> CGFloat {
        let width = max(0, width)
        switch module {
        case .clipboard:
            let search = items.clipboardSearch ? NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing : 0
            guard items.clipboardEntries > 0 else { return NotchLayout.emptyHeight }
            let card = items.clipboardComfortable ? NotchLayout.clipboardCardHeight
                : NotchLayout.clipboardCompactCardHeight
            return search + rail(count: items.clipboardEntries, itemWidth: width, itemHeight: card,
                                 spacing: NotchLayout.clipboardCardSpacing, width: width)
        case .notifications:
            return rail(count: items.notificationCards, itemWidth: NotchLayout.notificationCardWidth,
                        itemHeight: NotchLayout.notificationCardHeight, spacing: NotchLayout.cardSpacing, width: width)
        case .downloads:
            return rail(count: items.downloadCards, itemWidth: width, itemHeight: NotchLayout.downloadCardHeight,
                        spacing: NotchLayout.cardSpacing, width: width)
        case .captures:
            return rail(count: items.captureTiles, itemWidth: NotchLayout.captureCardWidth,
                        itemHeight: NotchLayout.captureCardHeight, spacing: NotchLayout.cardSpacing, width: width)
        case .files:
            return rail(count: items.shelfTiles, itemWidth: NotchLayout.shelfTileWidth,
                        itemHeight: NotchLayout.shelfTileHeight, spacing: NotchLayout.shelfTileSpacing,
                        width: width, insets: NotchLayout.shelfTileInset)
        case .system:
            guard items.systemCards > 0 else { return NotchLayout.emptyHeight }
            let insets = NotchLayout.systemHoverInset(width: width)
            // The grid balances its rows across the width, as the page draws them.
            let rows = NotchLayout.systemRowRanges(count: items.systemCards, width: width - insets * 2).count
            return NotchLayout.railHeight(rows: rows, rowHeight: NotchLayout.systemCardHeight,
                                          spacing: NotchLayout.rowSpacing) + insets * 2
        case .tools:
            return rail(count: items.tools, itemWidth: NotchLayout.toolWidth, itemHeight: NotchLayout.toolHeight,
                        spacing: NotchLayout.toolSpacing, width: width)
        case .mixer:
            // The whole page below the top row: the fader at its full length,
            // and its caption, mute and level rows under it.
            return NotchLayout.mixerFaderHeight + NotchLayout.mixerCaptionRowHeight
                + (items.mixerMicrophone ? NotchLayout.mixerCaptionRowHeight : 0)
        case .calendar:
            // The month grid with the week's agenda beside it, at the height
            // the grid needs, or the week strip and its agenda below the row.
            return items.calendarMonth ? NotchLayout.calendarMonthPageHeight
                : NotchLayout.calendarWeekPageHeight
        case .camera:
            // The preview at its own ratio, at the island's width, is the page.
            return NotchLayout.cameraPreviewHeight(width: width)
        case .watch:
            return NotchLayout.watchPageHeight
        case .splash:
            // The interval's ruler, and the dashboard under it: four charts,
            // the memory, the trend. Before a session there is nothing of
            // those to show, so the page is its ruler and the words below it.
            return items.splashDashboard ? NotchSplashLayout.pageHeight
                : NotchSplashLayout.pageSetupHeight
        case .scratchpad:
            // A page of text: the editor, its rule and its actions.
            return NotchLayout.scratchpadPageHeight
        // The home page, the player, the timer and the AI page measure
        // themselves where the island is sized, with the controls, cards and
        // readings they draw; these are their pages' shortest complete layouts.
        case .controls, .music, .timer, .agents:
            return NotchPageFloor.contentHeight(module: module, items: items)
        }
    }
}

/// The shortest page a section stays usable at, whatever the display allows.
///
/// These are the page's own complete pieces - one card with its actions, a
/// fader's full travel, a permission message - and nothing else. They are
/// floors beneath a page, never heights imposed on it: a page shorter than its
/// floor is drawn at the floor, and a page taller than the display's limit
/// scrolls at the limit.
enum NotchPageFloor {
    static func contentHeight(module: NotchModule, items: NotchPageContent = .empty) -> CGFloat {
        switch module {
        case .clipboard: NotchLayout.clipboardCardHeight
        case .notifications: NotchLayout.notificationCardHeight
        case .captures: NotchLayout.captureCardHeight
        case .downloads: NotchLayout.downloadCardHeight
        case .files: NotchLayout.shelfTileHeight + NotchLayout.shelfTileInset * 2
        case .system: NotchLayout.systemCardHeight + NotchLayout.systemHoverInset(width: 0) * 2
        case .tools: NotchLayout.toolHeight
        case .mixer: NotchLayout.mixerFaderHeight
        case .calendar: NotchLayout.calendarMonthMinimumHeight
        case .camera: NotchLayout.cameraMinimumHeight
        case .watch: NotchLayout.watchPageHeight
        case .splash: NotchSplashLayout.pageMinimumHeight
        case .scratchpad: NotchLayout.scratchpadPageHeight
        case .music: NotchLayout.musicPlayerHeight(band: 0, playing: false)
        case .controls, .timer, .agents: 0
        }
    }
}
