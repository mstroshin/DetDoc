import SwiftUI
import DetDocViewModels

struct SettingsSheet: View {
    @Bindable var settings: SettingsViewModel
    var body: some View { Text("Settings") }
}
