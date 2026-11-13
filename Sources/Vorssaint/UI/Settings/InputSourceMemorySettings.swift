// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The page of per-application input source memory: the one switch, what it does,
/// how much it has learned, and the honest word about the system's own document
/// switching.
///
/// There is no list of applications to manage, on purpose. The feature's whole
/// promise is that a person switches their input source in an application and
/// never tends a table afterwards, and a management screen would be the tending.
/// The count is shown because an empty count explains a silent feature, and a
/// number that grows says the switching is being remembered.
struct InputSourceMemorySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = InputSourceMemoryService.shared
    @AppStorage(DefaultsKey.inputSourceMemoryEnabled) private var enabled = false

    private var text: InputSourceMemoryFeatureStrings {
        FeatureStrings.inputSourceMemory(l10n.language)
    }

    var body: some View {
        Form {
            Section(text.name) {
                Toggle(text.name, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        InputSourceMemoryService.shared.syncWithPreferences()
                    }
                Text(text.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(text.watchingNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                // One line, and it says the same thing whether the feature has
                // learned one application or three hundred.
                if enabled {
                    Text(service.rememberedCount == 0
                         ? text.nothingRemembered
                         : String(format: text.applicationsRememberedFormat, service.rememberedCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // The system's own per-document switching is named, not touched:
                // Sadoyo neither reads that setting nor offers to change it here.
                Text(text.systemSwitchingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
    }
}
