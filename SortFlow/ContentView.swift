import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var manager: FolderManager
    @AppStorage("appLanguage") private var language: AppLanguage = .pl
    @AppStorage("lowMemory") private var lowMemory = true
    @AppStorage("showListThumbnails") private var thumbnails = true
    @State private var mode: AppMode = .files
    @State private var focused = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var showInfo = false
    @State private var showFilters = false
    @State private var showHistory = false
    @State private var showReport = false
    @State private var showSummary = false
    @State private var showRules = false
    @State private var showRename = false
    @State private var showCompare = false
    @State private var newProfile = false
    @State private var profileName = ""
    @State private var editedTarget: MappedFolder?
    @State private var planned: [PlannedTransfer] = []
    @State private var showPlan = false
    @State private var hoveringTarget: UUID?
    @State private var targetAvailability: [UUID: Bool] = [:]
    private var group: DuplicateGroup? { manager.duplicateGroups.first { $0.id == manager.selectedGroupID } }
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar.navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 400)
        } detail: {
            HSplitView {
                previewArea.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                if mode == .files { targetPanel.frame(minWidth: 210, idealWidth: 250, maxWidth: 340) }
            }
        }
        .navigationTitle("SortFlow")
        .navigationSubtitle(manager.currentFolder?.lastPathComponent ?? tr("Uporządkuj swoje pliki", "Make room for what matters"))
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .background(KeyboardBridge { handleKey($0) }.frame(width: 0, height: 0))
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: focused) { _, value in columns = value ? .detailOnly : .all }
        .onChange(of: mode) { _, _ in focused = false }
        .onChange(of: manager.filter) { _, _ in ensureSelection() }
        .onChange(of: manager.displayFiles) { _, _ in ensureSelection() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first, manager.canAct else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in manager.openFolder(url) } } }; return true
        }
        .sheet(item: $manager.activeConflict) { conflict in ConflictView(conflict: conflict).environmentObject(manager).interactiveDismissDisabled() }
        .sheet(item: $editedTarget) { folder in TargetEditor(folder: folder) { manager.updateTarget($0) } }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(manager) }
        .sheet(isPresented: $showReport) { reportView }
        .sheet(isPresented: $showSummary) { summaryView }
        .sheet(isPresented: $showRules) { RulesView().environmentObject(manager) }
        .sheet(isPresented: $showRename) { RenameView(files: manager.displayFiles.filter { manager.selectedFiles.contains($0.url) }) { plan in manager.runTransfers(plan, mode: .move) } }
        .sheet(isPresented: $showPlan) { TransferPlanView(plans: planned, mode: manager.transferMode) { manager.runTransfers(planned, mode: manager.transferMode) } }
        .sheet(isPresented: $showCompare) { CompareImagesView(files: manager.displayFiles.filter { manager.selectedFiles.contains($0.url) }) }
        .alert(tr("Nowy profil", "New workspace"), isPresented: $newProfile) {
            TextField(tr("Nazwa", "Name"), text: $profileName)
            Button(tr("Utwórz", "Create")) { manager.createWorkspace(profileName); profileName = "" }
            Button(tr("Anuluj", "Cancel"), role: .cancel) { profileName = "" }
        }
        .task(id: manager.targets) { await refreshTargets() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in Task { await refreshTargets() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await refreshTargets() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in Task { await refreshTargets() } }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .files ? tr("PLIKI", "FILES") : tr("DUPLIKATY", "DUPLICATES")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if mode == .files {
                    Toggle(isOn: $thumbnails) { Image(systemName: "photo.on.rectangle") }.toggleStyle(.button).help(tr("Miniatury", "Thumbnails"))
                    Text("\(manager.displayFiles.count)").monospacedDigit().foregroundStyle(.secondary)
                }
            }.padding(12)
            Divider()
            if mode == .files {
                if manager.isLoading { Spacer(); ProgressView(tr("Wczytywanie plików…", "Loading files…")); Spacer() }
                else {
                    List(selection: $manager.selectedFiles) {
                        ForEach(manager.displayFiles) { file in
                            HStack(spacing: 10) {
                                if thumbnails { FileThumbnail(file: file) } else { Image(systemName: file.kind.symbol).frame(width: 24).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).lineLimit(1)
                                    HStack { Text(file.size.byteLabel); if manager.recursive { Text("· " + file.url.deletingLastPathComponent().lastPathComponent).lineLimit(1) } }.font(.caption2).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 3).tag(file.url).help(file.url.path)
                                .onDrag { NSItemProvider(object: file.url as NSURL) }
                                .contextMenu {
                                    Button(tr("Pokaż w Finderze", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                    Button(tr("Otwórz", "Open")) { NSWorkspace.shared.open(file.url) }
                                    Button(tr("Skopiuj ścieżkę", "Copy path")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.url.path, forType: .string) }
                                }
                        }
                    }.overlay {
                        if manager.displayFiles.isEmpty { ContentUnavailableView(tr("Brak plików", "No files"), systemImage: "tray", description: Text(tr("Wybierz folder lub zmień filtry", "Choose a folder or adjust filters"))) }
                    }
                }
            } else if manager.isScanning {
                Spacer(); ProgressView(); Text(manager.progress.stage).padding(.top, 8); Text("\(manager.progress.files) " + tr("plików", "files")).font(.caption).foregroundStyle(.secondary)
                if manager.progress.total > 0 {
                    ProgressView(value: Double(manager.progress.done), total: Double(manager.progress.total)).padding(.horizontal)
                    Text("\(manager.progress.done.byteLabel) / \(manager.progress.total.byteLabel)").font(.caption)
                }
                Button(tr("Anuluj skanowanie", "Cancel scan")) { manager.cancelScan() }.padding(); Spacer()
            } else {
                List(selection: $manager.selectedGroupID) {
                    ForEach(manager.duplicateGroups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(group.files.first?.name ?? "", systemImage: "doc.on.doc").lineLimit(1)
                            Text("\(group.files.count) " + tr("kopie", "copies") + " · " + group.recoverable.byteLabel).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(group.id)
                    }
                }.overlay { if manager.duplicateGroups.isEmpty { ContentUnavailableView(tr("Znajdź zbędne kopie", "Find redundant copies"), systemImage: "doc.on.doc", description: Text(tr("Uruchom skanowanie wybranego folderu", "Scan the selected folder"))) } }
            }
        }
    }
    @ViewBuilder private var previewArea: some View {
        if mode == .duplicates {
            if let group { DuplicateView(group: group).environmentObject(manager) }
            else { welcome }
        } else if manager.selectedFiles.count > 1 {
            VStack(spacing: 18) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 60)).foregroundStyle(.tint)
                Text(tr("Wybrano", "Selected") + " \(manager.selectedFiles.count) " + tr("plików", "files")).font(.title2)
                Text(tr("Wybierz folder docelowy lub wykonaj operację z paska narzędzi", "Choose a destination or an action in the toolbar")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(tr("Porównaj dwa zdjęcia", "Compare two photos")) { showCompare = true }.disabled(!canCompare)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let file = manager.selectedEntry {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: file.kind.symbol).foregroundStyle(.secondary)
                    Text(file.name).font(.headline).lineLimit(1).help(file.url.path)
                    Spacer()
                    Button { NSWorkspace.shared.open(file.url) } label: { Image(systemName: "arrow.up.forward.app") }.help(tr("Otwórz w aplikacji", "Open in app"))
                    Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help(tr("Pełny ekran", "Full screen"))
                    Button { showInfo.toggle() } label: { Image(systemName: showInfo ? "info.circle.fill" : "info.circle") }.help(tr("Informacje o pliku", "File information"))
                }.buttonStyle(.borderless).padding(14)
                Divider()
                FilePreview(file: file).frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInfo { metadata(file) }
            }
        } else { welcome }
    }
    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray.2.fill").font(.system(size: 64)).foregroundStyle(.purple)
            Text("SortFlow").font(.largeTitle.bold())
            Text(tr("Mniej chaosu. Więcej miejsca.", "Less clutter. More room.")).font(.title3).foregroundStyle(.secondary)
            Button(tr("Wybierz folder", "Choose folder")) { manager.chooseFolder() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!manager.canAct)
            Text(tr("Możesz też przeciągnąć folder na okno", "You can also drop a folder onto this window")).font(.caption).foregroundStyle(.secondary)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var targetPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(manager.transferMode.title + tr(" do", " to")).font(.headline)
                Spacer()
                Menu {
                    ForEach(manager.workspaces) { ws in Button(ws.name) { manager.switchWorkspace(ws.id) } }
                    Divider(); Button(tr("Nowy profil…", "New workspace…")) { newProfile = true }
                    Button(tr("Usuń profil", "Delete workspace"), role: .destructive) { manager.deleteWorkspace() }.disabled(manager.workspaces.count < 2)
                } label: { Label(manager.activeWorkspaceName, systemImage: "person.crop.rectangle") }.menuStyle(.borderlessButton).fixedSize()
            }
            Picker(tr("Operacja", "Operation"), selection: $manager.transferMode) { ForEach(TransferMode.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            List {
                ForEach(Array(manager.targets.enumerated()), id: \.element.id) { index, folder in
                    destinationRow(index: index, folder: folder)
                }.onMove { manager.moveTargets($0, $1) }
            }.listStyle(.plain)
            Button { manager.addTargets() } label: { Label(tr("Dodaj folder docelowy", "Add destination folder"), systemImage: "folder.badge.plus") }.buttonStyle(.borderless)
            Divider()
            Button { manager.deferSelected() } label: { Label(manager.deferredOnly ? tr("Przywróć do kolejki", "Return to queue") : tr("Do decyzji później", "Decide later"), systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity) }.disabled(manager.selectedFiles.isEmpty)
            Button(role: .destructive) { manager.trashSelected() } label: { Label(tr("Do Kosza", "To Trash"), systemImage: "trash").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(.red).disabled(manager.selectedFiles.isEmpty)
            Text(tr("1–9: folder · ← →: nawigacja · L: później", "1–9: folder · ← →: navigate · L: later")).font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor)).disabled(manager.isBusy || manager.isScanning)
    }

    private func destinationRow(index: Int, folder: MappedFolder) -> some View {
        let available = targetAvailability[folder.id] ?? false
        return Button { manager.transferSelected(to: folder.url) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: available ? "folder.fill" : "externaldrive.badge.exclamationmark").font(.title3).foregroundStyle(available ? Color(hex: folder.colorHex) : .secondary)
                            VStack(alignment: .leading) {
                                Text(folder.title).fontWeight(.medium).lineLimit(2)
                                if !available { Text(tr("Folder niedostępny", "Folder unavailable")).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if index < 9 { Text("\(index + 1)").font(.caption.monospaced()).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4)) }
                        }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!manager.canAct || !available)
                        .listRowBackground(hoveringTarget == folder.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .help(folder.url.path)
                        .contextMenu {
                            Button(tr("Nazwa i kolor…", "Name and color…")) { editedTarget = folder }
                            Button(tr("Pokaż w Finderze", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                            Button(tr("Usuń z listy", "Remove from list"), role: .destructive) { manager.removeTarget(folder.id) }
                        }
                        .onDrop(of: [.fileURL], isTargeted: Binding(get: { hoveringTarget == folder.id }, set: { hoveringTarget = $0 ? folder.id : nil })) { providers in
                            guard available, manager.canAct else { return false }
                            loadDroppedURLs(providers) { manager.transferSelected(to: folder.url, external: $0) }; return true
                        }
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { manager.chooseFolder() } label: { Label(tr("Otwórz folder", "Open folder"), systemImage: "folder") }.disabled(!manager.canAct)
            Button { manager.loadFiles() } label: { Image(systemName: "arrow.clockwise") }.help(tr("Odśwież", "Refresh")).disabled(!manager.canAct)
        }
        ToolbarItem(placement: .principal) {
            Picker("", selection: $mode) { Text(tr("Pliki", "Files")).tag(AppMode.files); Text(tr("Duplikaty", "Duplicates")).tag(AppMode.duplicates) }.pickerStyle(.segmented).frame(width: 190)
        }
        ToolbarItemGroup(placement: .automatic) {
            if mode == .files {
                TextField(tr("Szukaj pliku…", "Search files…"), text: $manager.searchText).textFieldStyle(.roundedBorder).frame(width: 160)
                Menu { Picker(tr("Typ", "Type"), selection: $manager.filter) { ForEach(FileKind.allCases, id: \.self) { Text($0.title).tag($0) } } } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                Menu { Picker(tr("Sortuj", "Sort"), selection: $manager.sort) { ForEach(SortOrder.allCases, id: \.self) { Text($0.title).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") }
                Button { showFilters.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help(tr("Dodatkowe filtry", "More filters")).popover(isPresented: $showFilters) { filters }
                Button { manager.showDeferred() } label: { Label("\(manager.deferred.count)", systemImage: manager.deferredOnly ? "clock.fill" : "clock") }.help(tr("Odłożone pliki", "Deferred files"))
                Button { focused.toggle() } label: { Image(systemName: focused ? "rectangle.compress.vertical" : "viewfinder") }.help(tr("Tryb skupienia", "Focus mode"))
            } else {
                Toggle(tr("Podfoldery", "Subfolders"), isOn: $manager.recursive).toggleStyle(.checkbox).disabled(!manager.canAct)
                Button { manager.findDuplicates() } label: { Label(tr("Skanuj", "Scan"), systemImage: "magnifyingglass") }.disabled(!manager.canAct || manager.currentFolder == nil)
            }
            Toggle(isOn: $lowMemory) { Image(systemName: lowMemory ? "leaf.fill" : "leaf") }.toggleStyle(.button).help(tr("Tryb oszczędny RAM", "Low memory mode"))
            Menu {
                Button(tr("Reguły segregowania…", "Sorting rules…")) { showRules = true }
                Button(tr("Podgląd zastosowania reguł…", "Preview rule actions…")) { planned = manager.rulePlan(); showPlan = true }.disabled(!manager.canAct)
                Button(tr("Zmień nazwy zaznaczonych…", "Rename selected…")) { showRename = true }.disabled(manager.selectedFiles.isEmpty || !manager.canAct)
                Button(tr("Porównaj dwa zdjęcia…", "Compare two photos…")) { showCompare = true }.disabled(!canCompare)
                Divider()
                Button(tr("Historia operacji…", "Operation history…")) { showHistory = true }
                Button(tr("Podsumowanie sesji…", "Session summary…")) { showSummary = true }
                Button(tr("Raport błędów…", "Error report…")) { showReport = true }
                SettingsLink { Text(tr("Ustawienia…", "Settings…")) }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if manager.isScanning {
                ProgressView().controlSize(.small); Text(manager.progress.stage)
                Button(tr("Anuluj skanowanie", "Cancel scan")) { manager.cancelScan() }
            } else if manager.isBusy {
                ProgressView(value: Double(manager.operationDone), total: Double(max(1, manager.operationTotal))).frame(width: 100)
                Text("\(manager.operationDone)/\(manager.operationTotal)").monospacedDigit()
                Button(tr("Anuluj pozostałe", "Cancel remaining")) { manager.cancelOperation() }
            } else {
                Text(manager.notice.isEmpty ? tr("Gotowe do pracy", "Ready") : manager.notice).lineLimit(1)
                if !manager.history.isEmpty { Button(tr("Cofnij", "Undo")) { manager.undo() }.disabled(!manager.canAct) }
            }
            Spacer()
            if !manager.errors.isEmpty { Button { showReport = true } label: { Label("\(manager.errors.count)", systemImage: "exclamationmark.triangle") }.foregroundStyle(.orange) }
            if mode == .duplicates { Text(tr("Zbędne kopie: ", "Redundant copies: ") + manager.recoverable.byteLabel) }
            else {
                Text("\(manager.stats.moved + manager.stats.copied + manager.stats.trashed) " + tr("uporządkowano", "organized"))
                if !manager.displayFiles.isEmpty, let index = manager.displayFiles.firstIndex(where: { manager.selectedFiles.contains($0.url) }) { Text("\(index + 1)/\(manager.displayFiles.count)").monospacedDigit() }
            }
        }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
    }
    private var filters: some View {
        Form {
            Toggle(tr("Uwzględnij podfoldery", "Include subfolders"), isOn: $manager.recursive).disabled(!manager.canAct)
            TextField(tr("Minimum MB", "Minimum MB"), value: $manager.minSizeMB, format: .number)
            TextField(tr("Maksimum MB (0 = bez limitu)", "Maximum MB (0 = unlimited)"), value: $manager.maxSizeMB, format: .number)
            Toggle(tr("Filtruj po dacie modyfikacji", "Filter by modification date"), isOn: $manager.dateFilterEnabled)
            if manager.dateFilterEnabled { DatePicker(tr("Od", "Since"), selection: $manager.modifiedAfter, displayedComponents: .date) }
        }.padding(20).frame(width: 320)
    }
    private func metadata(_ file: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack { Text(file.kind.title); ImageDimensions(url: file.url); Spacer(); Text(file.size.byteLabel) }.font(.caption.bold())
            Text(tr("Utworzono: ", "Created: ") + file.created.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            Text(tr("Zmieniono: ", "Modified: ") + file.modified.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            Text(file.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(12)
    }
    private var reportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Raport błędów i pominiętych plików", "Errors and skipped files")).font(.title2.bold())
            Text(tr("Raport zawiera maksymalnie 1000 wpisów na skan. Niepełny skan nie potwierdza braku duplikatów.", "The report contains up to 1000 entries per scan. An incomplete scan cannot confirm that no duplicates exist.")).font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(manager.errors.isEmpty ? tr("Brak błędów", "No errors") : manager.errors.joined(separator: "\n\n")).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            HStack { Button(tr("Skopiuj raport", "Copy report")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(manager.errors.joined(separator: "\n"), forType: .string) }; Spacer(); Button(tr("Zamknij", "Close")) { showReport = false } }
        }.padding(24).frame(width: 640, height: 450)
    }
    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Podsumowanie sesji", "Session summary")).font(.title.bold())
            LabeledContent(tr("Przeniesiono", "Moved"), value: "\(manager.stats.moved)")
            LabeledContent(tr("Skopiowano", "Copied"), value: "\(manager.stats.copied)")
            LabeledContent(tr("Do Kosza", "Trashed"), value: "\(manager.stats.trashed) · \(manager.stats.bytes.byteLabel)")
            Text(tr("Miejsce odzyskasz po opróżnieniu Kosza. Klony APFS mogą współdzielić dane.", "Space is reclaimed after emptying Trash. APFS clones may share storage.")).font(.caption).foregroundStyle(.secondary)
            List(manager.stats.destinations.keys.sorted(), id: \.self) { key in LabeledContent(key, value: "\(manager.stats.destinations[key] ?? 0)") }.frame(height: 160)
            Text(tr("Liczniki obejmują wykonane operacje; cofnięcia nie zmniejszają liczników.", "Counters include completed operations; undo does not reduce them.")).font(.caption2).foregroundStyle(.secondary)
            HStack { Spacer(); Button(tr("Zamknij", "Close")) { showSummary = false } }
        }.padding(24).frame(width: 550)
    }
    private var canCompare: Bool { let chosen = manager.files.filter { manager.selectedFiles.contains($0.url) }; return chosen.count == 2 && chosen.allSatisfy { $0.kind == .image || $0.kind == .raw } }
    private func ensureSelection() { let visible = Set(manager.displayFiles.map(\.url)); let selection = manager.selectedFiles.intersection(visible); if selection.isEmpty, let first = manager.displayFiles.first { manager.selectedFiles = [first.url] } else if selection != manager.selectedFiles { manager.selectedFiles = selection } }
    private func handleKey(_ key: String) -> Bool {
        guard manager.canAct else { return false }
        if key == "undo" { manager.undo(); return true }
        guard mode == .files else { return false }
        if let number = Int(key), number >= 1, number <= min(9, manager.targets.count) { manager.transferSelected(to: manager.targets[number - 1].url); return true }
        switch key {
        case "left": manager.navigate(-1)
        case "right": manager.navigate(1)
        case "l": manager.deferSelected()
        case "f": focused.toggle()
        default: return false
        }; return true
    }
    private func refreshTargets() async {
        let folders = manager.targets
        let result = await Task.detached { Dictionary(uniqueKeysWithValues: folders.map { ($0.id, (try? $0.url.checkResourceIsReachable()) ?? false) }) }.value
        if !Task.isCancelled { targetAvailability = result }
    }
}

@MainActor
private func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    // Zbieramy całą partię przed startem, zamiast uruchamiać konkurujące przeniesienia.
    Task {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { value, _ in continuation.resume(returning: value) }
            }
            if let url { urls.append(url) }
        }
        completion(urls)
    }
}
struct KeyboardBridge: NSViewRepresentable {
    var action: (String) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSView { let view = NSView(); context.coordinator.view = view; return view }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.action = action }
    class Coordinator {
        var action: (String) -> Bool
        var monitor: Any?
        weak var view: NSView?
        init(action: @escaping (String) -> Bool) {
            self.action = action
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.view?.window, window === NSApp.keyWindow, NSApp.keyWindow?.sheetParent == nil,
                      !(NSApp.keyWindow?.firstResponder is NSTextView), NSApp.modalWindow == nil else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "z" { return self.action("undo") ? nil : event }
                guard modifiers.isEmpty else { return event }
                let key = event.keyCode == 123 ? "left" : event.keyCode == 124 ? "right" : event.charactersIgnoringModifiers?.lowercased() ?? ""
                return self.action(key) ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
