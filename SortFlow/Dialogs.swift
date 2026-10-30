import SwiftUI
import AppKit

@MainActor
func chooseDirectory() -> URL? {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    return panel.runModal() == .OK ? panel.url : nil
}
struct TargetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var folder: MappedFolder
    var save: (MappedFolder) -> Void
    private let colors = ["#8A2BE2", "#007AFF", "#28CD41", "#FF9500", "#FF3B30", "#FF2D55", "#8E8E93"]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(tr("Folder docelowy", "Destination folder")).font(.title2.bold())
            TextField(tr("Własna nazwa", "Custom name"), text: Binding(get: { folder.alias ?? "" }, set: { folder.alias = $0 }))
            Text(folder.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { ForEach(colors, id: \.self) { color in Button { folder.colorHex = color } label: { Circle().fill(Color(hex: color)).frame(width: 25, height: 25).overlay { if folder.colorHex == color { Image(systemName: "checkmark").foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel(color) } }
            HStack { Button(tr("Anuluj", "Cancel")) { dismiss() }; Spacer(); Button(tr("Zapisz", "Save")) { save(folder); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 420)
    }
}
struct ConflictView: View {
    let conflict: FileConflict
    @EnvironmentObject private var manager: FolderManager
    @State private var source: FileEntry?
    @State private var destination: FileEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr("Plik już istnieje", "File already exists"), systemImage: "doc.on.doc").font(.title2.bold())
            Text(conflict.plan.source.lastPathComponent).font(.headline)
            HStack(alignment: .top, spacing: 24) {
                details(tr("Źródło", "Source"), file: source, path: conflict.plan.source.path)
                details(tr("Cel", "Destination"), file: destination, path: conflict.plan.destination.path)
            }
            Text(tr("Przy zastąpieniu stary plik zostanie zachowany do cofnięcia operacji.", "When replacing, the previous file is preserved for undo.")).font(.caption).foregroundStyle(.secondary)
            Toggle(tr("Zastosuj do pozostałych konfliktów", "Apply to remaining conflicts"), isOn: $manager.applyToRemaining)
            HStack {
                Button(tr("Anuluj pozostałe", "Cancel remaining")) { manager.cancelOperation() }
                Spacer()
                Button(tr("Pomiń", "Skip")) { manager.resolveConflict(.skip) }
                Button(tr("Zastąp", "Replace")) { manager.resolveConflict(.replace) }
                Button(tr("Zachowaj oba", "Keep both")) { manager.resolveConflict(.keepBoth) }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 680)
            .task(id: conflict.id) {
                let pair = await Task.detached { (try? FileEntry.read(conflict.plan.source), try? FileEntry.read(conflict.plan.destination)) }.value
                if !Task.isCancelled { source = pair.0; destination = pair.1 }
            }
    }
    private func details(_ title: String, file: FileEntry?, path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(path).font(.caption).textSelection(.enabled)
            if let file { Text(file.size.byteLabel); Text(file.modified.formatted(date: .abbreviated, time: .shortened)) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
struct DuplicateView: View {
    let group: DuplicateGroup
    @EnvironmentObject private var manager: FolderManager
    @State private var previewURL: URL?
    @State private var confirmAll = false
    private var kept: URL? { manager.keepURL(for: group) }
    private var nameDiff: Bool { Set(group.files.map(\.name)).count > 1 }
    private var creationDiff: Bool { Set(group.files.map(\.created)).count > 1 }
    private var modificationDiff: Bool { Set(group.files.map(\.modified)).count > 1 }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) { Text(tr("Identyczna zawartość", "Identical content")).font(.headline); Text("\(group.files.count) " + tr("kopie · ", "copies · ") + group.recoverable.byteLabel).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Menu {
                        Button(tr("Preferowany folder…", "Preferred folder…")) { if let url = chooseDirectory() { manager.preferredFolder = url } }
                        Button(tr("Wyczyść preferencję", "Clear preference")) { manager.preferredFolder = nil }
                        Divider()
                        Button(tr("Usuń wszystkie kopie…", "Delete every copy…"), role: .destructive) { confirmAll = true }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                }
                if let preferred = manager.preferredFolder { Text(tr("Preferuj: ", "Prefer: ") + preferred.lastPathComponent).font(.caption).foregroundStyle(.secondary) }
                Button(role: .destructive) {
                    guard let kept else { return }; manager.trashFiles(group.files.map(\.url).filter { $0 != kept }, group: group, keep: kept)
                } label: { Label(tr("Usuń pozostałe", "Remove remaining") + " \(group.files.count - 1)", systemImage: "trash").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(!manager.canAct || kept == nil)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(group.files) { file in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button { manager.protectedCopies[group.id] = file.url } label: { Label(kept == file.url ? tr("Zachowaj", "Keep") : tr("Zachowaj tę kopię", "Keep this copy"), systemImage: kept == file.url ? "checkmark.shield.fill" : "shield") }.buttonStyle(.borderless).tint(kept == file.url ? .green : .secondary)
                                    Spacer(); Button { previewURL = file.url } label: { Image(systemName: "eye") }.help(tr("Pokaż podgląd tej kopii", "Preview this copy"))
                                }
                                Text(file.name).fontWeight(.semibold).foregroundStyle(nameDiff ? .orange : .primary).textSelection(.enabled)
                                Text(file.size.byteLabel).font(.caption)
                                Text(tr("Utworzono: ", "Created: ") + file.created.formatted()).font(.caption2).foregroundStyle(creationDiff ? .orange : .secondary)
                                Text(tr("Zmieniono: ", "Modified: ") + file.modified.formatted()).font(.caption2).foregroundStyle(modificationDiff ? .orange : .secondary)
                                Button(file.url.path) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.font(.caption2).buttonStyle(.link).multilineTextAlignment(.leading)
                                if kept != file.url { Button(tr("Do Kosza", "To Trash"), role: .destructive) { manager.trashFiles([file.url], group: group, keep: kept) }.disabled(!manager.canAct) }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).stroke(kept == file.url ? Color.green.opacity(0.7) : Color.clear, lineWidth: 1) }
                        }
                    }
                }
                Text(tr("To szacowany rozmiar zbędnych kopii. Hardlinki są pomijane; klony APFS mogą współdzielić bloki.", "This is the estimated size of redundant copies. Hard links are excluded; APFS clones may share blocks.")).font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(minWidth: 260, idealWidth: 340, maxWidth: 450)
            if let file = group.files.first(where: { $0.url == previewURL }) ?? group.files.first {
                VStack(spacing: 0) { Text(file.name).font(.headline).padding(); Divider(); FilePreview(file: file) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onChange(of: group.id, initial: true) { _, _ in previewURL = group.files.first?.url }
            .confirmationDialog(tr("Przenieść do Kosza wszystkie kopie, także zachowywaną?", "Move every copy to Trash, including the protected one?"), isPresented: $confirmAll) {
                Button(tr("Usuń wszystkie", "Delete all"), role: .destructive) { manager.trashFiles(group.files.map(\.url), group: group) }
            }
    }
}
struct HistoryView: View {
    @EnvironmentObject private var manager: FolderManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Historia operacji", "Operation history")).font(.title2.bold())
            Text(tr("Historia i kopie zastąpionych plików pozostają dostępne po ponownym uruchomieniu.", "History and backups of replaced files remain available after restarting.")).font(.caption).foregroundStyle(.secondary)
            List(manager.history) { record in
                HStack {
                    VStack(alignment: .leading) { Text(record.title + " · \(record.items.count)"); Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary); if let first = record.items.first { Text(first.original.lastPathComponent).font(.caption).lineLimit(1) } }
                    Spacer(); Button(tr("Cofnij", "Undo")) { manager.undo(record) }.disabled(!manager.canAct)
                }.padding(.vertical, 4)
            }
            HStack { Button(tr("Wczytaj starsze", "Load older")) { manager.loadHistory(more: true) }; Spacer(); Button(tr("Zamknij", "Close")) { dismiss() } }
        }.padding(24).frame(width: 650, height: 500)
    }
}
struct TransferPlanView: View {
    let plans: [PlannedTransfer]
    let mode: TransferMode
    var execute: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Podgląd operacji", "Operation preview")).font(.title2.bold())
            Text("\(mode.title) · \(plans.count) " + tr("plików", "files"))
            Text(tr("Istniejące nazwy zostaną rozstrzygnięte w oknie konfliktów.", "Existing names will be handled in the conflict dialog.")).font(.caption).foregroundStyle(.secondary)
            List(plans) { plan in VStack(alignment: .leading, spacing: 4) { Text(plan.source.path).font(.caption); Label(plan.destination.path, systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary) } }
            HStack { Button(tr("Anuluj", "Cancel")) { dismiss() }; Spacer(); Button(tr("Wykonaj", "Apply")) { dismiss(); execute() }.buttonStyle(.borderedProminent).disabled(plans.isEmpty) }
        }.padding(24).frame(width: 760, height: 480)
    }
}
struct RenameView: View {
    let files: [FileEntry]
    var execute: ([PlannedTransfer]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prefix = "plik_"
    @State private var start = 1
    @State private var withDate = false
    private var plan: [PlannedTransfer] { FileService.renamePlan(files.map(\.url), prefix: prefix, start: max(0, start), includeDate: withDate) }
    private var valid: Bool { !prefix.contains("/") && !prefix.contains(":") && !prefix.isEmpty && start >= 0 && start < 1_000_000_000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Wsadowa zmiana nazw", "Batch rename")).font(.title2.bold())
            Form { TextField(tr("Prefiks", "Prefix"), text: $prefix); TextField(tr("Numer początkowy", "Starting number"), value: $start, format: .number); Toggle(tr("Dodaj dzisiejszą datę", "Add today's date"), isOn: $withDate) }
            Text(tr("Rozszerzenia pozostają zachowane. Zmianę nazw można cofnąć.", "Extensions are preserved. Renaming can be undone.")).font(.caption).foregroundStyle(.secondary)
            List(plan) { item in LabeledContent(item.source.lastPathComponent, value: item.destination.lastPathComponent) }
            HStack { Button(tr("Anuluj", "Cancel")) { dismiss() }; Spacer(); Button(tr("Zmień nazwy", "Rename")) { let value = plan; dismiss(); execute(value) }.buttonStyle(.borderedProminent).disabled(!valid || plan.isEmpty) }
        }.padding(24).frame(width: 650, height: 460)
    }
}
struct RulesView: View {
    @EnvironmentObject private var manager: FolderManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: FileKind = .all
    @State private var contains = ""
    @State private var destination: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Reguły segregowania", "Sorting rules")).font(.title2.bold())
            Text(tr("Pierwsza pasująca reguła wygrywa. Reguły działają dopiero po zatwierdzeniu podglądu operacji.", "The first matching rule wins. Rules run only after you confirm the operation preview.")).font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($manager.rules) { $rule in
                    HStack {
                        Toggle(isOn: $rule.enabled) { VStack(alignment: .leading) { Text(rule.name); Text(rule.kind.title + " · " + rule.contains + " → " + rule.target.path).font(.caption).foregroundStyle(.secondary) } }.onChange(of: rule.enabled) { _, _ in manager.saveRules() }
                        Button(role: .destructive) { manager.rules.removeAll { $0.id == rule.id }; manager.saveRules() } label: { Image(systemName: "minus.circle") }
                    }
                }.onMove { manager.rules.move(fromOffsets: $0, toOffset: $1); manager.saveRules() }
            }
            Form {
                TextField(tr("Nazwa reguły", "Rule name"), text: $name)
                Picker(tr("Typ", "Type"), selection: $kind) { ForEach(FileKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField(tr("Nazwa zawiera (opcjonalnie)", "Name contains (optional)"), text: $contains)
                HStack { Text(destination?.path ?? tr("Wybierz folder docelowy", "Choose destination")); Spacer(); Button(tr("Wybierz…", "Choose…")) { destination = chooseDirectory() } }
            }
            HStack {
                Button(tr("Dodaj regułę", "Add rule")) { if let destination { manager.rules.append(Rule(name: name, kind: kind, contains: contains, target: destination)); manager.saveRules(); name = ""; contains = "" } }.disabled(name.isEmpty || destination == nil)
                Spacer(); Button(tr("Zamknij", "Close")) { dismiss() }
            }
        }.padding(24).frame(width: 700, height: 580)
    }
}
struct CompareImagesView: View {
    let files: [FileEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    var body: some View {
        VStack {
            HStack { Text(tr("Porównanie zdjęć", "Photo comparison")).font(.title2.bold()); Spacer(); Button(tr("Dopasuj oba", "Fit both")) { zoom = 1 }; Button(tr("Zamknij", "Close")) { dismiss() } }.padding()
            HStack(spacing: 1) { ForEach(Array(files.prefix(2))) { file in VStack { Text(file.name).lineLimit(1); Text(file.size.byteLabel).font(.caption).foregroundStyle(.secondary); ImagePreview(url: file.url, sharedZoom: $zoom) } } }
        }.frame(minWidth: 850, minHeight: 580)
    }
}
struct SettingsView: View {
    @AppStorage("appLanguage") private var language: AppLanguage = .pl
    @AppStorage("lowMemory") private var lowMemory = true
    @AppStorage("previewStyle") private var style: PreviewStyle = .fit
    @AppStorage("videoAutoplay") private var autoplay = true
    @AppStorage("videoSound") private var sound = false
    @AppStorage("videoLoop") private var loop = true
    @AppStorage("documentPadded") private var padded = true
    @AppStorage("linkedFiles") private var linked = false
    @AppStorage("advanceAfterAction") private var advance = true
    var body: some View {
        Form {
            Section(tr("Ogólne", "General")) {
                Picker(tr("Język", "Language"), selection: $language) { Text("Polski").tag(AppLanguage.pl); Text("English").tag(AppLanguage.en) }
                Toggle(tr("Następny plik po operacji", "Next file after an action"), isOn: $advance)
                Toggle(tr("Przenoś i kopiuj powiązane pliki razem", "Move and copy related files together"), isOn: $linked)
                Text(tr("Pary RAW/JPG/XMP oraz wideo/napisy z tą samą nazwą w tym samym folderze.", "RAW/JPG/XMP and video/subtitles with the same stem in the same folder.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("Pamięć i podgląd", "Memory and preview")) {
                Toggle(tr("Tryb oszczędny RAM", "Low memory mode"), isOn: $lowMemory)
                Text(tr("Zdjęcia do 1024 px, miniatury 60 px, bez blur i autoplay. Cache miniatur: do 16 MiB; osobno pamięć widocznych podglądów i dekoderów.", "Images up to 1024 px, 60 px thumbnails, no blur or autoplay. Thumbnail cache: up to 16 MiB; visible previews and decoders use additional memory.")).font(.caption).foregroundStyle(.secondary)
                Picker(tr("Zdjęcia", "Photos"), selection: $style) { Text(tr("Dopasuj", "Fit")).tag(PreviewStyle.fit); Text(tr("Wypełnij", "Fill")).tag(PreviewStyle.fill); Text(tr("Tło blur", "Blur background")).tag(PreviewStyle.blur) }
                Toggle(tr("Marginesy dokumentów", "Document margins"), isOn: $padded)
                Button(tr("Wyczyść cache miniatur", "Clear thumbnail cache")) { ImagePipeline.shared.clear() }
            }
            Section(tr("Odtwarzanie", "Playback")) {
                Toggle(tr("Automatycznie odtwarzaj", "Autoplay"), isOn: $autoplay).disabled(lowMemory)
                Toggle(tr("Dźwięk wideo", "Video sound"), isOn: $sound)
                Toggle(tr("Zapętlaj", "Loop"), isOn: $loop)
            }
        }.formStyle(.grouped).frame(width: 540, height: 650)
    }
}
