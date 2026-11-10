// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while a Splash reading is being watched: on the right the
/// decode speed the engine is measuring, and on the left the section's mark -
/// or, when an activity began before this reading did, that activity's own
/// mark, opening its page. The wings are as wide as the wider side needs, and
/// the reading is measured by its widest shape, so the island keeps its size as
/// the figure gains or loses a digit.
///
/// The speed is a whole number and the page's short unit, written against the
/// figure with no space in it: the strip is a glance, and the card of four
/// readings is the page's answer to anyone who wants the figures to two decimals.
struct NotchSplashStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var splash = NotchSplashService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: NotchSplashStrings { FeatureStrings.notchSplash(l10n.language) }
    /// The activity that became active before this reading did, drawn at the
    /// strip's leading end so the island reads in the order its activities
    /// started. Without one, the strip leads with the section's own mark.
    private var companion: NotchCompactActivity? { service.compactCompanion }

    var body: some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let speed = NotchSplashSupport.stripSpeedText(splash.stripDecodeSpeed, language: l10n.language)
            ?? NotchSplashSupport.placeholder
        return Button {
            // The mark at the strip's leading end is an activity of its own, and a
            // click on the strip goes to it, as it does on the timer's strip; the
            // reading's page is reached by opening the island.
            if let companion { service.openActivity(companion.module) }
            else { service.openActivity(NotchCompactActivity.splash.module) }
        } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        if let companion {
                            NotchCompanionMark(companion: companion, geometry: geometry)
                        } else {
                            Image(systemName: NotchModule.splash.symbol)
                                .font(.system(size: iconSize, weight: .medium))
                        }
                    }
                }
                .padding(.leading, companion == nil
                          ? geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
                          : NotchCompanionMark.inset(companion!, geometry: geometry))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 42 {
                        Text(speed)
                            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                            // A reading that gains or loses a character, as 9t/s
                            // becomes 10t/s, resizes the wings; the service
                            // measures the same reading.
                            .onChange(of: NotchAgentSupport.readingShape(speed)) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
                // Digits carry no descenders, so their ink is about the cap height.
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(NotchSplashPalette.purple)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(companion.map { NotchCompanionMark.label($0, language: l10n.language) } ?? text.title)
        .accessibilityValue(text.decode + " " + speed)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.splash.strip")
    }
}
