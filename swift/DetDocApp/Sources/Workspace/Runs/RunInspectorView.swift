import SwiftUI
import DetDocCore

struct RunInspectorView: View {
    @Bindable var panel: RunPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("DetDoc").font(.headline)
            Spacer()
            if panel.stage == .running || panel.stage == .planPending || panel.stage == .patchPending {
                Button("Cancel", role: .cancel) { panel.cancel() }.controlSize(.small)
            }
        }
        if let phase = panel.currentPhase {
            Label(phase.rawValue.replacingOccurrences(of: "_", with: " "), systemImage: "circle.dotted")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch panel.stage {
        case .idle:
            ContentUnavailableView("Ready", systemImage: "play.circle", description: Text("Run docs or start a fix to begin."))
        case .running:
            ProgressView().controlSize(.small)
        case .planPending:
            if let plan = panel.planReview {
                PlanReviewView(plan: plan, onApprove: { panel.approvePlan() }, onReject: { panel.rejectPlan() })
            }
        case .patchPending:
            if let patch = panel.patchReview {
                PatchReviewView(patch: patch, onApply: { panel.applyPatch() }, onDiscard: { panel.discardPatch() })
            }
        case .completed:
            Label(panel.result?.applied == true ? "Applied" : "Saved (not applied)",
                  systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            if let error = panel.error {
                Label(error.code, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                Text(error.message).font(.callout).textSelection(.enabled)
            }
        }
    }
}
