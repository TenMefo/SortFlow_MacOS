import Foundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class FolderManager: ObservableObject {
    @Published var currentFolder: URL?
    @Published private(set) var files: [FileEntry] = []
    @Published private(set) var displayFiles: [FileEntry] = []
    @Published var selectedFiles: Set<URL> = [] { didSet { persistSession() } }
    @Published var searchText = "" { didSet { rebuild() } }
    @Published var filter: FileKind = .all { didSet { rebuild(); persistSession() } }
    @Published var sort: SortOrder = .nameAZ { didSet { rebuild(); persistSession() } }
    @Published var recursive = false { didSet { if recursive != oldValue { persistSession(); loadFiles() } } }
    @Published var minSizeMB: Double = 0 { didSet { rebuild() } }
    @Published var maxSizeMB: Double = 0 { didSet { rebuild() } }
    @Published var dateFilterEnabled = false { didSet { rebuild() } }
    @Published var modifiedAfter = Calendar.current.date(byAdding: .month, value: -1, to: Date())! { didSet { rebuild() } }
    @Published var deferredOnly = false { didSet { rebuild() } }
    @Published var transferMode: TransferMode = .move { didSet { persistSession() } }
    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceID: UUID?
    @Published var targets: [MappedFolder] = []
    @Published var rules: [Rule] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var selectedGroupID: String?
    @Published var protectedCopies: [String: URL] = [:]
    @Published var deferred: Set<URL> = []
    @Published var history: [HistoryRecord] = []
    @Published var stats = SessionStats()
    @Published var isLoading = false
    @Published var isScanning = false
    @Published var isBusy = false
    @Published var progress = ScanProgress()
    @Published var operationDone = 0
    @Published var operationTotal = 0
    @Published var notice = ""
    @Published var errors: [String] = []
    @Published var activeConflict: FileConflict?
    @Published var applyToRemaining = false
    @Published var preferredFolder: URL? { didSet { persistSession() } }
    private var completed: Set<URL> = []
    private var restoring = true
    private var listFlag = CancellationFlag()
    private var scanFlag = CancellationFlag()
    private var operationFlag = CancellationFlag()
    private var listGeneration = UUID(), scanGeneration = UUID()
    private var conflictContinuation: CheckedContinuation<ConflictChoice, Never>?
    private var cachedChoice: ConflictChoice?
    private var historyLimit = 100
    private var searchWork: Task<Void, Never>?
    private var searchFlag = CancellationFlag()
    let support: URL
    var backupRoot: URL { support.appendingPathComponent("Backups", isDirectory: true) }
    var canAct: Bool { !isBusy && !isLoading && !isScanning }
    var selectedEntry: FileEntry? { selectedFiles.count == 1 ? files.first { selectedFiles.contains($0.url) } : nil }
    var activeWorkspaceName: String { workspaces.first { $0.id == activeWorkspaceID }?.name ?? "" }
    var recoverable: Int64 { duplicateGroups.reduce(0) { $0 + $1.recoverable } }

    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SortFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "savedWorkspaces"), let decoded = try? JSONDecoder().decode([Workspace].self, from: data), !decoded.isEmpty { workspaces = decoded }
        else {
            let folders = defaults.data(forKey: "mappedFolders").flatMap { try? JSONDecoder().decode([MappedFolder].self, from: $0) } ?? []
            workspaces = [Workspace(name: tr("Domyślny", "Default"), folders: folders)]
        }
        if let data = defaults.data(forKey: "sortflowRules"), let decoded = try? JSONDecoder().decode([Rule].self, from: data) { rules = decoded }
        loadHistory()
        let id = defaults.string(forKey: "activeWorkspaceId").flatMap(UUID.init(uuidString:)) ?? workspaces[0].id
        restoreWorkspace(workspaces.first { $0.id == id } ?? workspaces[0])
        restoring = false
        if currentFolder != nil { loadFiles() }
    }
    func persistSession() {
        guard !restoring, let index = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        workspaces[index].folders = targets
        workspaces[index].source = currentFolder
        workspaces[index].selected = selectedFiles.first
        workspaces[index].recursive = recursive
        workspaces[index].filter = filter
        workspaces[index].sort = sort
        workspaces[index].transfer = transferMode
        workspaces[index].deferred = Array(deferred)
        workspaces[index].preferredFolder = preferredFolder
        saveWorkspaces()
    }
    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(data, forKey: "savedWorkspaces") }
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: "activeWorkspaceId")
    }
    private func restoreWorkspace(_ workspace: Workspace) {
        restoring = true
        activeWorkspaceID = workspace.id; targets = workspace.folders; currentFolder = workspace.source
        filter = workspace.filter ?? .all; sort = workspace.sort ?? .nameAZ; recursive = workspace.recursive ?? false
        transferMode = workspace.transfer ?? .move; deferred = Set(workspace.deferred ?? [])
        selectedFiles = workspace.selected.map { [$0] } ?? []; preferredFolder = workspace.preferredFolder
        completed = []; searchText = ""; deferredOnly = false
        restoring = false
    }
    func switchWorkspace(_ id: UUID) {
        guard canAct, let workspace = workspaces.first(where: { $0.id == id }) else { return }
        persistSession(); cancelScan(); restoreWorkspace(workspace); duplicateGroups = []; selectedGroupID = nil; loadFiles(); saveWorkspaces()
    }
    func createWorkspace(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        persistSession()
        let workspace = Workspace(name: name, folders: [])
        workspaces.append(workspace); restoreWorkspace(workspace); files = []; rebuild(); saveWorkspaces()
    }
    func deleteWorkspace() {
        guard canAct, workspaces.count > 1 else { return }
        workspaces.removeAll { $0.id == activeWorkspaceID }; restoreWorkspace(workspaces[0]); saveWorkspaces(); loadFiles()
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }
    func openFolder(_ url: URL) {
        guard canAct else { return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { notice = tr("Upuść folder, aby go otworzyć", "Drop a folder to open it"); return }
        cancelScan(); currentFolder = url.standardizedFileURL; selectedFiles = []; completed = []; deferred = []
        duplicateGroups = []; selectedGroupID = nil; stats = SessionStats(); persistSession(); loadFiles()
    }
    func loadFiles() {
        guard !restoring else { return }
        listFlag.cancel(); listFlag = CancellationFlag()
        let flag = listFlag, generation = UUID(); listGeneration = generation
        guard let folder = currentFolder else { files = []; rebuild(); return }
        let recurse = recursive
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try ScanService.list(folder, recursive: recurse, flag: flag) } }.value
            guard generation == listGeneration else { return }
            isLoading = false
            switch result {
            case .success(let value):
                files = value.0; rebuild(); selectedFiles.formIntersection(Set(files.map(\.url)))
                if selectedFiles.isEmpty, let first = displayFiles.first { selectedFiles = [first.url] }
                if !value.1.isEmpty { errors = value.1; notice = tr("Niektóre pliki pominięto — zobacz raport", "Some files were skipped — see report") }
            case .failure(let error): if !(error is CancellationError) { errors = [error.localizedDescription]; notice = error.localizedDescription }
            }
        }
    }
    private func rebuild() {
        guard !restoring else { return }
        searchWork?.cancel(); searchFlag.cancel(); searchFlag = CancellationFlag(); let flag = searchFlag
        // Dane są już w pamięci: filtrowanie nie wykonuje żadnych odczytów dysku.
        let input = files, query = searchText, kind = filter, order = sort, deferredSet = deferred, completedSet = completed
        let onlyDeferred = deferredOnly, minimum = minSizeMB, maximum = maxSizeMB, after = modifiedAfter, useDate = dateFilterEnabled
        searchWork = Task {
            if !query.isEmpty { try? await Task.sleep(nanoseconds: 120_000_000) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                input.filter { file in
                    !flag.isCancelled && !completedSet.contains(file.url) && (onlyDeferred ? deferredSet.contains(file.url) : !deferredSet.contains(file.url)) &&
                    (kind == .all || file.kind == kind) && (query.isEmpty || file.name.localizedCaseInsensitiveContains(query)) &&
                    (minimum <= 0 || Double(file.size) >= minimum * 1_000_000) && (maximum <= 0 || Double(file.size) <= maximum * 1_000_000) &&
                    (!useDate || file.modified >= after)
                }.sorted { a, b in
                    switch order {
                    case .nameAZ: return a.name.localizedStandardCompare(b.name) == .orderedAscending
                    case .nameZA: return a.name.localizedStandardCompare(b.name) == .orderedDescending
                    case .sizeDesc: return a.size == b.size ? a.url.path < b.url.path : a.size > b.size
                    case .sizeAsc: return a.size == b.size ? a.url.path < b.url.path : a.size < b.size
                    case .newest: return a.modified == b.modified ? a.url.path < b.url.path : a.modified > b.modified
                    case .oldest: return a.modified == b.modified ? a.url.path < b.url.path : a.modified < b.modified
                    case .type: return a.kind == b.kind ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.kind.rawValue < b.kind.rawValue
                    }
                }
            }.value
            guard !Task.isCancelled else { return }; displayFiles = result
        }
    }
    func navigate(_ delta: Int) {
        guard !displayFiles.isEmpty else { return }
        let index = displayFiles.firstIndex { selectedFiles.contains($0.url) } ?? 0
        selectedFiles = [displayFiles[min(max(index + delta, 0), displayFiles.count - 1)].url]
    }
    func deferSelected() {
        guard canAct, !selectedFiles.isEmpty else { return }
        let selection = selectedFiles
        let next = nextSelection(removing: selection)
        if deferredOnly { deferred.subtract(selection) } else { deferred.formUnion(selection) }
        selectedFiles = next.map { [$0] } ?? []; persistSession(); rebuild()
        notice = deferredOnly ? tr("Przywrócono do kolejki", "Returned to queue") : tr("Odłożono do decyzji później", "Saved for later")
    }
    func showDeferred() { deferredOnly.toggle(); selectedFiles = []; rebuild() }
    private func nextSelection(removing urls: Set<URL>) -> URL? {
        guard let index = displayFiles.firstIndex(where: { urls.contains($0.url) }) else { return displayFiles.first?.url }
        return displayFiles.dropFirst(index + 1).first { !urls.contains($0.url) }?.url ?? displayFiles.reversed().first { !urls.contains($0.url) }?.url
    }
    func addTargets() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !targets.contains(where: { $0.url == url }) { targets.append(MappedFolder(url: url)) }
            persistSession()
        }
    }
    func updateTarget(_ folder: MappedFolder) { if let index = targets.firstIndex(where: { $0.id == folder.id }) { targets[index] = folder; persistSession() } }
    func removeTarget(_ id: UUID) { targets.removeAll { $0.id == id }; persistSession() }
    func moveTargets(_ source: IndexSet, _ destination: Int) { targets.move(fromOffsets: source, toOffset: destination); persistSession() }
    func saveRules() { if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "sortflowRules") } }
    func rulePlan() -> [PlannedTransfer] {
        let entries = selectedFiles.isEmpty ? displayFiles : displayFiles.filter { selectedFiles.contains($0.url) }
        return entries.compactMap { file in
            guard let rule = rules.first(where: { $0.matches(file) }) else { return nil }
            let destination = rule.target.appendingPathComponent(file.name)
            return destination.standardizedFileURL == file.url ? nil : PlannedTransfer(source: file.url, destination: destination)
        }
    }
    func transferSelected(to folder: URL, external: [URL]? = nil) {
        let urls = external ?? displayFiles.filter { selectedFiles.contains($0.url) }.map(\.url)
        guard !urls.isEmpty, canAct else { return }
        let linked = UserDefaults.standard.bool(forKey: "linkedFiles")
        isBusy = true
        Task {
            let expanded = await Task.detached { linked ? FileService.linkedFiles(urls) : urls }.value
            isBusy = false
            runTransfers(expanded.map { PlannedTransfer(source: $0, destination: folder.appendingPathComponent($0.lastPathComponent)) }, mode: transferMode)
        }
    }
    func resolveConflict(_ choice: ConflictChoice) {
        if applyToRemaining { cachedChoice = choice }
        let continuation = conflictContinuation; conflictContinuation = nil; activeConflict = nil
        continuation?.resume(returning: choice)
    }
    private func askConflict(_ plan: PlannedTransfer) async -> ConflictChoice {
        if let choice = cachedChoice { return choice }
        return await withCheckedContinuation { continuation in conflictContinuation = continuation; activeConflict = FileConflict(plan: plan) }
    }
    func cancelOperation() { operationFlag.cancel(); if conflictContinuation != nil { resolveConflict(.skip) } }
    func runTransfers(_ plans: [PlannedTransfer], mode: TransferMode) {
        guard canAct, !plans.isEmpty else { return }
        isBusy = true; operationFlag = CancellationFlag(); let flag = operationFlag
        operationDone = 0; operationTotal = plans.count; errors = []; cachedChoice = nil; applyToRemaining = false
        let next = nextSelection(removing: Set(plans.map(\.source))), backups = backupRoot
        Task {
            var record = HistoryRecord(title: mode.title, items: [])
            for plan in plans {
                if flag.isCancelled { break }
                let exists = await Task.detached { FileManager.default.fileExists(atPath: plan.destination.path) }.value
                let choice: ConflictChoice = exists ? await askConflict(plan) : .keepBoth
                if flag.isCancelled { break }
                let result = await Task.detached { Result { try FileService.transfer(plan, mode: mode, choice: choice, backupRoot: backups) } }.value
                switch result {
                case .success(let item):
                    if let item {
                        record.items.append(item); persistRecord(record)
                        completed.insert(plan.source); deferred.remove(plan.source)
                        if mode == .move { stats.moved += 1 } else { stats.copied += 1 }
                        stats.destinations[plan.destination.deletingLastPathComponent().path, default: 0] += 1
                    }
                case .failure(let error): errors.append("\(plan.source.lastPathComponent): \(error.localizedDescription)")
                }
                operationDone += 1
            }
            finishRecord(record)
            if UserDefaults.standard.object(forKey: "advanceAfterAction") as? Bool ?? true { selectedFiles = next.map { [$0] } ?? [] }
            else if mode == .copy { for item in record.items { completed.remove(item.original) } }
            notice = "\(mode.title): \(record.items.count)/\(plans.count)" + (flag.isCancelled ? tr(" · Anulowano", " · Cancelled") : "")
            isBusy = false; rebuild(); persistSession(); if mode == .move { invalidateDuplicates() }
        }
    }
    func trashSelected() { trashFiles(Array(selectedFiles)) }
    func trashFiles(_ urls: [URL], group: DuplicateGroup? = nil, keep: URL? = nil) {
        guard canAct, !urls.isEmpty else { return }
        isBusy = true; operationFlag = CancellationFlag(); let flag = operationFlag
        operationDone = 0; operationTotal = urls.count; errors = []
        let next = nextSelection(removing: Set(urls))
        Task {
            var record = HistoryRecord(title: tr("Do Kosza", "To Trash"), items: [])
            for url in urls {
                if flag.isCancelled { break }
                let result = await Task.detached { () -> Result<UndoItem, Error> in
                    Result {
                        if let group {
                            guard let scanned = group.files.first(where: { $0.url == url }), let now = try? FileEntry.read(url), now.size == scanned.size, now.modified == scanned.modified, now.identity == scanned.identity else { throw CocoaError(.fileReadUnknown) }
                            if let keep {
                                guard url != keep, try FileService.hash(keep, flag: flag) == group.id,
                                      try FileService.identical(keep, url, flag: flag) else { throw CocoaError(.fileReadCorruptFile) }
                            } else if try FileService.hash(url, flag: flag) != group.id { throw CocoaError(.fileReadCorruptFile) }
                        }
                        try flag.check()
                        return try FileService.trash(url)
                    }
                }.value
                switch result {
                case .success(let item):
                    record.items.append(item); persistRecord(record); completed.insert(url); deferred.remove(url); stats.trashed += 1
                    if let entry = files.first(where: { $0.url == url }) { stats.bytes += entry.size }
                    for index in duplicateGroups.indices { duplicateGroups[index].files.removeAll { $0.url == url } }
                case .failure(let error): if !(error is CancellationError) { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                operationDone += 1
            }
            duplicateGroups.removeAll { $0.files.count < 2 }
            finishRecord(record); selectedFiles = next.map { [$0] } ?? []
            notice = "\(tr("Do Kosza", "To Trash")): \(record.items.count)/\(urls.count)"; isBusy = false; rebuild(); persistSession()
        }
    }
    func keepURL(for group: DuplicateGroup) -> URL? {
        if let protected = protectedCopies[group.id], group.files.contains(where: { $0.url == protected }) { return protected }
        if let preferredFolder, let entry = group.files.first(where: { $0.url.path.hasPrefix(preferredFolder.path + "/") }) { return entry.url }
        return group.files.min { $0.created < $1.created }?.url
    }
    func findDuplicates() {
        guard let folder = currentFolder, canAct else { return }
        scanFlag.cancel(); scanFlag = CancellationFlag(); let flag = scanFlag, generation = UUID(), recurse = recursive
        scanGeneration = generation; isScanning = true; duplicateGroups = []; selectedGroupID = nil; errors = []; progress = ScanProgress()
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try ScanService.duplicates(folder, recursive: recurse, flag: flag) { status in
                    Task { @MainActor in if self.scanGeneration == generation { self.progress = status } }
                } }
            }.value
            guard scanGeneration == generation else { return }
            isScanning = false
            switch result {
            case .success(let value): duplicateGroups = value.groups; errors = value.errors; selectedGroupID = value.groups.first?.id; notice = tr("Skanowanie zakończone", "Scan completed")
            case .failure(let error): if !(error is CancellationError) { errors = [error.localizedDescription] }; notice = error is CancellationError ? tr("Skanowanie anulowane", "Scan cancelled") : error.localizedDescription
            }
        }
    }
    func cancelScan() { scanFlag.cancel(); listFlag.cancel() }
    private func invalidateDuplicates() { duplicateGroups = []; selectedGroupID = nil }
    private var historyDirectory: URL { support.appendingPathComponent("History", isDirectory: true) }
    private func persistRecord(_ record: HistoryRecord) {
        do {
            try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: historyDirectory.appendingPathComponent(record.id.uuidString + ".json"), options: .atomic)
        } catch { if errors.count < 1000 { errors.append(tr("Nie zapisano historii: ", "History could not be saved: ") + error.localizedDescription) } }
    }
    private func finishRecord(_ record: HistoryRecord) {
        guard !record.items.isEmpty else { return }
        history.insert(record, at: 0); if history.count > historyLimit { history = Array(history.prefix(historyLimit)) }
    }
    func loadHistory(more: Bool = false) {
        if more { historyLimit += 100 }
        let urls = (try? FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // Wczytujemy tylko widoczną stronę historii; starsze rekordy pozostają na dysku.
        let recent = urls.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }.prefix(historyLimit)
        history = recent.compactMap { try? JSONDecoder().decode(HistoryRecord.self, from: Data(contentsOf: $0)) }.sorted { $0.date > $1.date }
    }
    func undo(_ record: HistoryRecord? = nil) {
        guard canAct, let record = record ?? history.first else { return }
        isBusy = true; errors = []; operationFlag = CancellationFlag(); let flag = operationFlag
        Task {
            var remaining = record.items
            for item in record.items.reversed() {
                if flag.isCancelled { break }
                let result = await Task.detached { Result { try FileService.undo(item) } }.value
                switch result {
                case .success: remaining.removeAll { $0.original == item.original && $0.current == item.current }; completed.remove(item.original)
                case .failure(let error): errors.append("\(item.original.lastPathComponent): \(error.localizedDescription)")
                }
                var updated = record; updated.items = remaining
                if remaining.isEmpty { try? FileManager.default.removeItem(at: historyDirectory.appendingPathComponent(record.id.uuidString + ".json")) }
                else { persistRecord(updated) }
            }
            loadHistory(); isBusy = false; invalidateDuplicates(); loadFiles()
            notice = remaining.isEmpty ? tr("Cofnięto operację", "Operation undone") : tr("Nie cofnięto wszystkich plików — możesz ponowić", "Some files were not restored — you can retry")
        }
    }
}
