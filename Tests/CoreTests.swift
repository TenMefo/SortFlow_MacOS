import Foundation

@main
struct CoreTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SortFlowTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target"), backups = root.appendingPathComponent("backups")
        for url in [source, target, backups] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        func write(_ name: String, _ text: String, in folder: URL) throws -> URL { let url = folder.appendingPathComponent(name); try Data(text.utf8).write(to: url); return url }
        func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws { guard try condition() else { fatalError(message) }; print("PASS: \(message)") }
        let a = try write("a.txt", "original", in: source)
        let old = try write("a.txt", "old destination", in: target)
        let before = try FileEntry.read(a)
        try check(before.size == 8 && before.kind == .document, "Metadata and type")
        do { _ = try FileService.transfer(PlannedTransfer(source: a, destination: a), mode: .move, choice: .replace, backupRoot: backups); fatalError("Self transfer accepted") }
        catch { try check(try text(a) == "original", "Self transfer cannot delete source") }
        let replacement = try FileService.transfer(PlannedTransfer(source: a, destination: old), mode: .move, choice: .replace, backupRoot: backups)!
        try check(!fm.fileExists(atPath: a.path) && (try text(old)) == "original", "Replace installs source")
        try check(try text(replacement.backup!) == "old destination", "Replace retains old destination")
        try FileService.undo(replacement)
        try check(try text(a) == "original" && text(old) == "old destination", "Undo restores both files")
        let copy = try FileService.transfer(PlannedTransfer(source: a, destination: old), mode: .copy, choice: .keepBoth, backupRoot: backups)!
        try check(copy.current.lastPathComponent == "a 1.txt" && fm.fileExists(atPath: a.path), "Keep both uses unique name")
        try FileService.undo(copy)
        try check(!fm.fileExists(atPath: copy.current.path) && fm.fileExists(atPath: a.path), "Undo copy preserves source")
        let copyReplace = try FileService.transfer(PlannedTransfer(source: a, destination: old), mode: .copy, choice: .replace, backupRoot: backups)!
        try FileService.undo(copyReplace)
        try check(try text(old) == "old destination" && text(a) == "original", "Copy replacement undo")
        let moved = source.appendingPathComponent("renamed.txt")
        let rename = try FileService.transfer(PlannedTransfer(source: a, destination: moved), mode: .move, choice: .keepBoth, backupRoot: backups)!
        _ = try write("a.txt", "new user file", in: source)
        do { try FileService.undo(rename); fatalError("Undo overwrote user file") }
        catch { try check(try text(a) == "new user file" && text(moved) == "original", "Undo collision preserves both files") }
        try fm.removeItem(at: a); try FileService.undo(rename)
        let flag = CancellationFlag()
        try check(try FileService.hash(a, flag: flag) == "0682c5f2076f099c34cfdd15a9e063849ed437a49677e6fcc5b4198c76575be5", "SHA-256 expected digest")
        flag.cancel()
        do { _ = try FileService.hash(a, flag: flag); fatalError("Cancellation ignored") } catch is CancellationError { print("PASS: Hash cancellation") }
        do { _ = try FileService.hash(source.appendingPathComponent("missing"), flag: CancellationFlag()); fatalError("Missing file hashed") } catch { print("PASS: Missing file never produces a digest") }
        let duplicateRoot = root.appendingPathComponent("duplicates")
        try fm.createDirectory(at: duplicateRoot, withIntermediateDirectories: true)
        let first = try write("one.bin", "same bytes", in: duplicateRoot)
        _ = try write("two.bin", "same bytes", in: duplicateRoot)
        _ = try write("different.bin", "other byte", in: duplicateRoot)
        _ = try write("unique.bin", "a unique longer file", in: duplicateRoot)
        try fm.linkItem(at: first, to: duplicateRoot.appendingPathComponent("hardlink.bin"))
        let result = try ScanService.duplicates(duplicateRoot, recursive: true, flag: CancellationFlag(), progress: { _ in })
        try check(result.groups.count == 1 && result.groups[0].files.count == 2 && result.errors.isEmpty, "Disk index finds exact duplicates and excludes hardlinks")
        try check(result.groups[0].recoverable == 10, "Recoverable bytes leave one copy")
        try check(try FileService.identical(first, duplicateRoot.appendingPathComponent("two.bin"), flag: CancellationFlag()), "Byte verification")
        try check(try !FileService.identical(first, duplicateRoot.appendingPathComponent("different.bin"), flag: CancellationFlag()), "Equal size different content rejected")
        let nested = duplicateRoot.appendingPathComponent("nested"); try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try write("nested.bin", "nested", in: nested)
        let flat = try ScanService.list(duplicateRoot, recursive: false, flag: CancellationFlag()).0
        let recursive = try ScanService.list(duplicateRoot, recursive: true, flag: CancellationFlag()).0
        try check(recursive.count == flat.count + 1, "Recursion option respected")
        let image = try write("photo.JPG", "image", in: source)
        let raw = try write("photo.NEF", "raw", in: source)
        _ = try write("photo.xmp", "metadata", in: source)
        try check(FileService.linkedFiles([image]).count == 3 && FileService.linkedFiles([raw]).contains(image), "Linked companions include uppercase extensions")
        let plan = FileService.renamePlan([image], prefix: "test_", start: 7, includeDate: false)
        try check(plan[0].destination.lastPathComponent == "test_0007.JPG", "Rename preserves extension")
        // Starsze profile (1.x) nie mają nowych kluczy: muszą nadal się dekodować.
        let legacy = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"folders\":[]}"
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(legacy.utf8))
        try check(workspace.source == nil && workspace.folders.isEmpty, "Legacy workspace migration")
        print("ALL CORE TESTS PASSED")
    }
}
