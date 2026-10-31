import SwiftUI
import Darwin

@main
struct SortFlow: App {
    @StateObject private var manager = FolderManager()
    init() {
        if CommandLine.arguments.contains("--smoke-test") {
            Self.smokeLog("STARTING")
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) {
                Self.smokeLog("SMOKE_TIMEOUT")
                Darwin.exit(2)
            }
        }
    }
    private static func smokeLog(_ value: String) {
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-log"), CommandLine.arguments.indices.contains(index + 1) {
            try? Data(value.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        }
    }
    var body: some Scene {
        Window("SortFlow", id: "main") {
            ContentView().environmentObject(manager).tint(.purple)
                .onAppear {
                    // Używane wyłącznie przez automatyczny test uruchomienia na runnerze macOS.
                    if CommandLine.arguments.contains("--smoke-test") {
                        Self.smokeLog("UI_APPEARED")
                        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) { manager.openFolder(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        Task { @MainActor in
                            for _ in 0..<100 {
                                if !manager.isLoading && !manager.files.isEmpty { break }
                                try? await Task.sleep(nanoseconds: 100_000_000)
                            }
                            guard !manager.files.isEmpty else { Self.smokeLog("SMOKE_NO_FILES"); Darwin.exit(3) }
                            let images = manager.files.filter { $0.kind == .image }
                            for _ in 0..<2 {
                                for file in images {
                                    manager.selectedFiles = [file.url]
                                    try? await Task.sleep(nanoseconds: 140_000_000)
                                }
                            }
                            if let document = manager.files.first(where: { $0.kind == .document }) { manager.selectedFiles = [document.url] }
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            Self.smokeLog("SMOKE_OK files=\(manager.files.count)")
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
        }.defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(tr("Cofnij ostatnią operację", "Undo last operation")) { manager.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!manager.canAct || manager.history.isEmpty)
            }
            CommandGroup(after: .newItem) {
                Button(tr("Otwórz folder…", "Open folder…")) { manager.chooseFolder() }.keyboardShortcut("o", modifiers: .command).disabled(!manager.canAct)
            }
        }
        Settings { SettingsView().tint(.purple) }
    }
}
