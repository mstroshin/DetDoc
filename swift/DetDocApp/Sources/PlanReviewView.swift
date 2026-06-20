import SwiftUI
import DetDocViewModels

struct PlanReviewView: View {
    let plan: PlanReviewViewModel
    let onApprove: () -> Void
    let onReject: () -> Void
    var body: some View { Text("Plan: \(plan.summary)") }
}
