import AppKit

/// FolderPicking backed by NSOpenPanel (the only AppKit dependency).
struct SystemFolderPicker: FolderPicking {
    @MainActor
    func pickFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select project folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
