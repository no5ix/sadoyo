// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The timer's duration ruler: the island's shared ruler at minutes, in the
/// timer's orange, read as a duration in the app's language. Dragging it,
/// spinning it on a trackpad, and the haptic at each stop are the shared
/// ruler's; the timer only says what a value means.
struct NotchTimerRuler: NSViewRepresentable {
    @Binding var minutes: Int
    let label: String
    let locale: Locale

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchValueRulerControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? NotchLayout.timerRulerHeight)
    }

    func makeNSView(context: Context) -> NotchValueRulerControl {
        let control = NotchValueRulerControl()
        control.focusRingType = .none
        control.scale = NotchRulerScale.minutes
        control.minValue = Double(NotchRulerScale.minutes.minimum)
        control.maxValue = Double(NotchRulerScale.minutes.maximum)
        control.altIncrementValue = 1
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NotchValueRulerControl, context: Context) {
        context.coordinator.parent = self
        control.scale = NotchRulerScale.minutes
        control.tint = .systemOrange
        control.valueText = { NotchTimerSupport.compactText(Double($0) * 60, locale: locale) }
        control.labelText = { NotchTimerRulerScale.label(for: $0) }
        control.synchronize(value: minutes)
        control.isEnabled = context.environment.isEnabled
        control.increasedContrast = context.environment.colorSchemeContrast == .increased
        control.setAccessibilityLabel(label)
        control.setAccessibilityValueDescription(NotchTimerSupport.compactText(Double(minutes) * 60, locale: locale))
        control.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: NotchTimerRuler
        init(_ parent: NotchTimerRuler) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            guard parent.minutes != sender.integerValue else { return }
            parent.minutes = sender.integerValue
            NotchService.shared.provideHapticFeedback()
        }
    }
}
