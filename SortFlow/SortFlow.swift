import SwiftUI
import AppKit
import Combine
import Darwin

// Jawny cykl życia okna: aplikacja zawsze otwiera jedno główne okno, również bez zapisanej sesji systemu.
@MainActor
final class SortFlowDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static weak var shared: SortFlowDelegate?
    let manager = FolderManager()
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var changes: AnyCancellable?
    override init() {
        super.init(); Self.shared = self
        changes = manager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        SmokeHarness.log("DID_FINISH_LAUNCHING")
        let root = ContentView().environmentObject(manager).tint(.purple)
            .onAppear { [weak self] in if let self { SmokeHarness.start(self.manager) } }
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "SortFlow"
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        window.isReleasedWhenClosed = false
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 1000)
        window.setContentSize(CGSize(width: min(1280, available.width - 40), height: min(800, available.height - 60)))
        window.minSize = CGSize(width: 900, height: 600)
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        SmokeHarness.log("WINDOW_CREATED")
    }
    func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().tint(.purple))
            let settings = NSWindow(contentViewController: controller)
            settings.title = tr("Ustawienia SortFlow", "SortFlow Settings")
            settings.styleMask = [.titled, .closable]
            settings.isReleasedWhenClosed = false; settings.center(); settingsWindow = settings
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil); return true
    }
}
@MainActor
private enum SmokeHarness {
    static var active: Bool { CommandLine.arguments.contains("--smoke-test") }
    static var started = false
    static func log(_ value: String) {
        guard active, let index = CommandLine.arguments.firstIndex(of: "--smoke-log"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data((value + "\n").utf8))
        }
    }
    static func start(_ manager: FolderManager) {
        guard active, !started else { return }; started = true; log("UI_APPEARED")
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) { manager.openFolder(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        Task { @MainActor in
            for _ in 0..<100 {
                if !manager.isLoading && !manager.files.isEmpty { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !manager.files.isEmpty else { log("SMOKE_NO_FILES"); Darwin.exit(3) }
            let images = manager.files.filter { $0.kind == .image }
            for _ in 0..<2 {
                for file in images { manager.selectedFiles = [file.url]; try? await Task.sleep(nanoseconds: 140_000_000) }
            }
            if let document = manager.files.first(where: { $0.kind == .document }) { manager.selectedFiles = [document.url] }
            try? await Task.sleep(nanoseconds: 500_000_000)
            log("SMOKE_OK files=\(manager.files.count)"); NSApplication.shared.terminate(nil)
        }
    }
}
@main
struct SortFlow: App {
    @NSApplicationDelegateAdaptor(SortFlowDelegate.self) private var delegate
    init() {
        if SmokeHarness.active {
            SmokeHarness.log("STARTING")
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { SmokeHarness.log("SMOKE_TIMEOUT"); Darwin.exit(2) }
        }
    }
    var body: some Scene {
        Settings { SettingsView().tint(.purple) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(tr("Ustawienia…", "Settings…")) { delegate.showSettings() }.keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .undoRedo) {
                    Button(tr("Cofnij ostatnią operację", "Undo last operation")) { delegate.manager.undo() }.disabled(!delegate.manager.canAct || delegate.manager.history.isEmpty)
                }
                CommandGroup(replacing: .newItem) {
                    Button(tr("Otwórz folder…", "Open folder…")) { delegate.manager.chooseFolder() }.keyboardShortcut("o", modifiers: .command).disabled(!delegate.manager.canAct)
                }
            }
    }
}
