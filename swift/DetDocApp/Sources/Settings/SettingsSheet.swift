import SwiftUI
import DetDocViewModels
import DetDocCore

struct SettingsSheet: View {
    @Bindable var settings: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Apply") {
                    Toggle("Auto-commit on apply", isOn: $settings.config.apply.autoCommit)
                    Toggle("Keep worktree on failure", isOn: $settings.config.worktree.keepOnFailure)
                }
                Section("Agent") {
                    LabeledContent("Provider", value: settings.config.agent.provider)
                    LabeledContent("Thinking", value: settings.config.agent.thinking)
                    LabeledContent("pi", value: settings.piAvailable ? "available" : "missing")
                }
                Section("Validation commands") {
                    ForEach(Array(settings.config.validation.commands.enumerated()), id: \.offset) { _, cmd in
                        VStack(alignment: .leading) {
                            Text(cmd.name).font(.caption).bold()
                            Text(cmd.run).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    if settings.config.validation.commands.isEmpty {
                        Text("None configured").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { settings.save(); dismiss() } }
            }
            .task { settings.load(); await settings.refreshPiHealth() }
            if let error = settings.error {
                Text("\(error.code): \(error.message)").font(.caption).foregroundStyle(.red).padding()
            }
        }
    }
}
