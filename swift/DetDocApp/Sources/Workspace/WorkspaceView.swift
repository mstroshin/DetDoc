import SwiftUI
import DetDocCore

struct WorkspaceView: View {
    let root: URL
    private let config: DetDocConfig

    @State private var workspace: WorkspaceViewModel
    @State private var editor: DocEditorViewModel
    @State private var panel: RunPanelViewModel
    @State private var runs: RunsViewModel
    @State private var settings: SettingsViewModel
    @State private var tree: DocsTreeViewModel
    @State private var docSearch: DocSearchViewModel
    @State private var selectedDoc: String?
    @State private var showInspector = true
    @State private var showRuns = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var fixMessage = ""
    @State private var showFixPrompt = false

    init(root: URL) {
        self.root = root
        let config = (try? ConfigStore().load(root: root)) ?? .default
        self.config = config
        let agent = AgentRunnerFactory.make(config: config)
        _workspace = State(initialValue: WorkspaceViewModel(root: root))
        _editor = State(initialValue: DocEditorViewModel(root: root, config: config))
        _panel = State(initialValue: RunPanelViewModel(root: root, agent: agent))
        _runs = State(initialValue: RunsViewModel(root: root))
        _settings = State(initialValue: SettingsViewModel(root: root))
        _tree = State(initialValue: DocsTreeViewModel(root: root, config: config))
        _docSearch = State(initialValue: DocSearchViewModel(root: root, config: config))
    }

    private var linkResolver: DocLinkResolver {
        let svc = DocsService(root: root, config: config)
        return DocLinkResolver(candidates: Set(svc.candidates().map(\.docsRelativePath)))
    }

    private var imageImporter: DocImageImporter { DocImageImporter(root: root) }

    var body: some View {
        NavigationSplitView {
            DocsExplorerView(tree: tree, selection: $selectedDoc,
                             dirtyPath: editor.isDirty ? editor.selectedPath : nil)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
                .navigationTitle("Docs")
        } detail: {
            DocEditorScreen(editor: editor, resolver: linkResolver,
                            imageImporter: imageImporter,
                            candidatesProvider: {
                                let svc = DocsService(root: root, config: self.config)
                                return svc.candidates()
                            }) { docPath in
                if !tree.isDirectory(docPath) { selectedDoc = docPath }
            }
        }
        .inspector(isPresented: $showInspector) {
            RunInspectorView(panel: panel)
                .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { panel.start(mode: .run) } label: { Label("Run docs", systemImage: "play.fill") }
                Button { showFixPrompt = true } label: { Label("Fix…", systemImage: "wrench.and.screwdriver") }
                Button { showRuns = true } label: { Label("Runs", systemImage: "clock.arrow.circlepath") }
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            }
            ToolbarItem(placement: .status) {
                Button { showSearch = true } label: {
                    Label("Search docs", systemImage: "magnifyingglass")
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 220, alignment: .leading)
                }
                .keyboardShortcut("p", modifiers: .command)
                .help("Search docs (⌘P)")
                .accessibilityIdentifier("toolbar.searchDocs")
            }
        }
        .task {
            await workspace.refresh()
            tree.refresh()
            // Dev/automation affordance: auto-start a run on open.
            if ProcessInfo.processInfo.environment["DETDOC_AUTORUN"] == "1" {
                panel.start(mode: .run)
            }
        }
        .onChange(of: selectedDoc) { _, new in
            if let new, !tree.isDirectory(new) { editor.open(new) }
            else if new == nil { editor.clear() }
        }
        .onChange(of: tree.nodes) { _, _ in
            // The tree just rebuilt (watcher fired). If the open document's file was
            // deleted/renamed outside DetDoc, close it — clearing selection cascades
            // to editor.clear() above.
            if let open = selectedDoc,
               !FileManager.default.fileExists(atPath: root.appendingPathComponent(open).path) {
                selectedDoc = nil
            }
        }
        .onChange(of: panel.stage) { _, stage in if stage == .completed { Task { await workspace.refresh(); tree.refresh(); runs.refresh() } } }
        .sheet(isPresented: $showRuns) { RunsSheet(runs: runs).frame(minWidth: 480, minHeight: 360) }
        .sheet(isPresented: $showSettings) { SettingsSheet(settings: settings).frame(minWidth: 520, minHeight: 420) }
        .alert("Fix intent", isPresented: $showFixPrompt) {
            TextField("Describe the bug and expected behavior", text: $fixMessage)
            Button("Run fix") { panel.start(mode: .fix, message: fixMessage) }
            Button("Cancel", role: .cancel) { }
        }
        .navigationTitle(root.lastPathComponent)
        .overlay {
            if showSearch {
                DocSearchOverlay(
                    model: docSearch,
                    onOpen: { path in
                        selectedDoc = path
                        showSearch = false
                    },
                    onClose: { showSearch = false }
                )
            }
        }
        .onChange(of: showSearch) { _, shown in if shown { docSearch.present() } }
        .animation(.easeOut(duration: 0.12), value: showSearch)
    }
}
