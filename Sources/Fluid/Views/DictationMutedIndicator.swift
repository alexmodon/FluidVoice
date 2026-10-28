import SwiftUI

struct DictationMutedIndicator: View {
    var compact = false
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "mic.slash.fill")
            if !self.compact {
                Text("Muted")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.orange)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation muted. \(self.settings.spaceMuteMode.resumeInstruction).")
        .help(self.settings.spaceMuteMode.resumeInstruction)
    }
}
