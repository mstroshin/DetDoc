import SwiftUI
import DetDocViewModels

struct RunInspectorView: View {
    @Bindable var panel: RunPanelViewModel
    var body: some View { Text("Run panel: \(String(describing: panel.stage))") }
}
