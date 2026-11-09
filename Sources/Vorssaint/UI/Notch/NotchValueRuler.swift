// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A native number ruler, including mouse dragging on desktop, the wheel, the
/// keyboard, and the haptic tick at every value it settles on.
///
/// The island has more than one ruler — the timer's minutes, a Pomodoro's
/// focus, a monitoring interval in seconds — and they are one control. A
/// `NotchRulerScale` carries the range and the labelling, and the tint and the
/// two text closures carry what each ruler is called and how its reading is
/// spoken, so the dragging, the wheel, the pointer and the haptics are never
/// written twice.
struct NotchValueRuler: NSViewRepresentable {
    @Binding var value: Int
    let scale: NotchRulerScale
    let label: String
    /// The ruler's own colour: the timer is orange, a monitor's interval is not.
    var tint: NSColor = .systemOrange
    /// How the reading is spoken to a screen reader, the value in its unit.
    var valueText: (Int) -> String = { String($0) }
    /// The number written under a tick.
    var labelText: (Int) -> String = { String($0) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchValueRulerControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? NotchLayout.timerRulerHeight)
    }

    func makeNSView(context: Context) -> NotchValueRulerControl {
        let control = NotchValueRulerControl()
        control.focusRingType = .none
        control.minValue = Double(context.coordinator.parent.scale.minimum)
        control.maxValue = Double(context.coordinator.parent.scale.maximum)
        control.altIncrementValue = 1
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NotchValueRulerControl, context: Context) {
        context.coordinator.parent = self
        let parent = context.coordinator.parent
        control.scale = parent.scale
        control.tint = parent.tint
        control.valueText = parent.valueText
        control.labelText = parent.labelText
        control.synchronize(value: parent.value)
        control.isEnabled = context.environment.isEnabled
        control.increasedContrast = context.environment.colorSchemeContrast == .increased
        control.setAccessibilityLabel(label)
        control.setAccessibilityValueDescription(parent.valueText(parent.value))
        control.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: NotchValueRuler
        init(_ parent: NotchValueRuler) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            guard parent.value != sender.integerValue else { return }
            parent.value = sender.integerValue
            NotchService.shared.provideHapticFeedback()
        }
    }
}

final class NotchValueRulerControl: NSSlider {
    var increasedContrast = false
    var scale = NotchRulerScale.minutes
    var tint: NSColor = .systemOrange
    var valueText: (Int) -> String = { String($0) }
    var labelText: (Int) -> String = { String($0) }
    private var drag: (x: CGFloat, value: Double)?
    private var didDrag = false
    private var showsKeyboardFocus = false
    private var scrollValue: Double?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    private var selectionX: CGFloat {
        bounds.minX + CGFloat(scale.selectionX(selected: integerValue, width: Double(bounds.width)))
    }

    func synchronize(value: Int) {
        let bounded = scale.value(Double(value))
        guard integerValue != bounded else { return }
        integerValue = bounded
        drag = nil
        scrollValue = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        showsKeyboardFocus = false
        needsDisplay = true
        drag = (convert(event.locationInWindow, from: nil).x, doubleValue)
        scrollValue = nil
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let previous = drag else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let value = scale.moving(previous.value, by: Double(x - previous.x), width: bounds.width)
        drag = (x, value)
        didDrag = true
        select(value)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, drag != nil else { drag = nil; return }
        if !didDrag {
            let offset = convert(event.locationInWindow, from: nil).x - selectionX
            select(scale.moving(doubleValue, by: -Double(offset), width: bounds.width))
        }
        drag = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, drag == nil else { return }
        if event.phase.contains(.began) { scrollValue = nil }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        // A precise wheel travels by points; a notched wheel travels by whole
        // ticks, whichever pitch the ruler is drawn at.
        let pitch = scale.spacing(width: bounds.width)
        let points = Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : pitch)
        let value = scale.moving(scrollValue ?? doubleValue, by: points, width: bounds.width)
        scrollValue = value
        select(value)
        if !event.hasPreciseScrollingDeltas || event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) { scrollValue = nil }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection([.command, .control]).isEmpty else {
            super.keyDown(with: event); return
        }
        scrollValue = nil
        showsKeyboardFocus = true
        needsDisplay = true
        switch event.keyCode {
        case 123, 125: select(doubleValue - 1)
        case 124, 126: select(doubleValue + 1)
        case 115: select(Double(scale.minimum))
        case 119: select(Double(scale.maximum))
        default: super.keyDown(with: event)
        }
    }

    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return }
        scrollValue = nil
        select(number.doubleValue)
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        scrollValue = nil
        select(doubleValue + 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        scrollValue = nil
        select(doubleValue - 1)
        return true
    }

    private func select(_ value: Double) {
        guard isEnabled else { return }
        let chosen = scale.value(value)
        guard integerValue != chosen else { return }
        integerValue = chosen
        setAccessibilityValueDescription(valueText(chosen))
        needsDisplay = true
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let edgeFade = max(1, bounds.width * 0.12)
        // A ruler whose whole range stands in the row needs no edge fade: its
        // first and last ticks are set in from the ends on purpose. A range
        // that slides is faded, so the eye reads the ticks near the pointer.
        let fixed = scale.fitsEntireScale(width: bounds.width)
        // Drawn for the full ruler height; a shorter island compresses the
        // ticks and pointer below the labels instead of cutting them off.
        let factor = bounds.height / NotchLayout.timerRulerHeight
        let selectionX = self.selectionX
        for value in scale.minimum...scale.maximum {
            let x = selectionX + CGFloat(scale.offset(of: value, selected: integerValue, width: bounds.width))
            guard x >= bounds.minX - 16, x <= bounds.maxX + 16 else { continue }
            let fade = fixed || value == integerValue
                ? 1 : min(1, max(0, min(x - bounds.minX, bounds.maxX - x) / edgeFade))
            let strength = value <= integerValue ? 1.0 : increasedContrast ? 0.65 : 0.35
            let color = tint.withAlphaComponent(fade * strength * (isEnabled ? 1 : 0.4))
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 2, y: 26 * factor, width: 4, height: 38 * factor),
                         xRadius: 2, yRadius: 2).fill()
            if scale.showsLabel(value) {
                let title = NSAttributedString(string: labelText(value), attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: color
                ])
                title.draw(at: NSPoint(x: x - title.size().width / 2, y: 0))
            }
        }
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: selectionX, y: 70 * factor))
        pointer.line(to: NSPoint(x: selectionX + 6, y: 80 * factor))
        pointer.line(to: NSPoint(x: selectionX - 6, y: 80 * factor))
        pointer.close()
        tint.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        pointer.fill()
        if window?.firstResponder === self, showsKeyboardFocus {
            tint.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            focus.lineWidth = 1
            focus.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        showsKeyboardFocus = accepted
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }
}
