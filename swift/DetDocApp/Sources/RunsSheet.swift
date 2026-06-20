import SwiftUI
import DetDocViewModels

struct RunsSheet: View {
    @Bindable var runs: RunsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(runs.runs, id: \.runId) { run in
                HStack {
                    VStack(alignment: .leading) {
                        Text(run.runId).font(.system(.body, design: .monospaced))
                        Text("\(run.approvedTargets.count) target(s)\(run.hasPatch ? " · patch" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply") { Task { await runs.apply(run.runId) } }
                        .disabled(!run.hasPatch)
                }
            }
            .overlay { if runs.runs.isEmpty { ContentUnavailableView("No saved runs", systemImage: "clock") } }
            .navigationTitle("Saved Runs")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { runs.refresh() }
            if let error = runs.error {
                Text("\(error.code): \(error.message)").font(.caption).foregroundStyle(.red).padding()
            }
        }
    }
}
