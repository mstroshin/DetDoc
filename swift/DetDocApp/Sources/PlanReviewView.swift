import SwiftUI
import DetDocViewModels
import DetDocCore

struct PlanReviewView: View {
    let plan: PlanReviewViewModel
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proposed plan").font(.headline)
            Text(plan.summary).font(.callout)
            Label("Risk: \(plan.risk)", systemImage: "exclamationmark.shield").font(.caption)
            if !plan.questions.isEmpty {
                VStack(alignment: .leading) {
                    Text("Questions").font(.caption).bold()
                    ForEach(plan.questions, id: \.self) { Text("• \($0)").font(.caption) }
                }
            }
            Text("Target files").font(.caption).bold()
            ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                ForEach(change.targetFiles, id: \.self) { file in
                    Label(file, systemImage: "doc.badge.gearshape").font(.caption)
                }
            }
            HStack {
                Button("Approve", action: onApprove).buttonStyle(.borderedProminent)
                Button("Reject", role: .destructive, action: onReject)
            }.padding(.top, 4)
        }
    }
}
