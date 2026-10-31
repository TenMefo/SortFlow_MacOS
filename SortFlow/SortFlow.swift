import SwiftUI

@main
struct SortFlow: App {
    @StateObject private var manager = FolderManager()
    var body: some Scene {
        Window("SortFlow", id: "main") {
            ContentView().environmentObject(manager).tint(.purple)
                .onAppear {
                    // Używane wyłącznie przez automatyczny test uruchomienia na runnerze macOS.
                    if CommandLine.arguments.contains("--smoke-test") {
                        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) { manager.openFolder(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        Task { @MainActor in
                            for _ in 0..<100 {
                                if !manager.isLoading && !manager.files.isEmpty { break }
                                try? await Task.sleep(nanoseconds: 100_000_000)
                            }
                            let images = manager.files.filter { $0.kind == .image }
                            for _ in 0..<2 {
                                for file in images {
                                    manager.selectedFiles = [file.url]
                                    try? await Task.sleep(nanoseconds: 140_000_000)
                                }
                            }
                            if let document = manager.files.first(where: { $0.kind == .document }) { manager.selectedFiles = [document.url] }
                            try? await Task.sleep(nanoseconds: 500_000_000)
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
