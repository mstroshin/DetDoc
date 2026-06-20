import SwiftUI
import DetDocViewModels

struct RunsSheet: View {
    @Bindable var runs: RunsViewModel
    var body: some View { Text("\(runs.runs.count) runs") }
}
