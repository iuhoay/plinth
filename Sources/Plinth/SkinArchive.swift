import Foundation
import UniformTypeIdentifiers

/// A `.plinthskin` file: a skin folder in a zip archive, to share a skin as
/// one file. Plinth installs one when it is opened, dropped on the fish, or
/// added with Add Skins…, and exports a skin of your own as one.
enum SkinArchive {
    static let type = UTType(exportedAs: "dev.rubycat.plinth.skin", conformingTo: .zip)

    enum Failure: Error {
        case unreadable, noSkin, link
    }

    /// Unpack `archive` into `scratch`, a new empty folder, and return the
    /// skin folder in it: the archive's top level, or its one folder (as
    /// `ditto -c -k --keepParent` and Finder's Compress make it).
    static func unpack(_ archive: URL, into scratch: URL) throws -> URL {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        guard ditto(["-x", "-k", archive.path, scratch.path]) else { throw Failure.unreadable }
        // A skin is pictures and a little JSON. A link could point anywhere on
        // the Mac, so an archive with one is refused.
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        let all = FileManager.default.enumerator(at: scratch, includingPropertiesForKeys: keys)?.allObjects as? [URL] ?? []
        if all.contains(where: { (try? $0.resourceValues(forKeys: Set(keys)).isSymbolicLink) == true }) {
            throw Failure.link
        }
        if hasIdle(scratch) { return scratch }
        let folders = ((try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" && $0.hasDirectoryPath }
        guard folders.count == 1, hasIdle(folders[0]) else { throw Failure.noSkin }
        return folders[0]
    }

    /// Write the skin folder `skin` to `archive`.
    static func pack(_ skin: URL, to archive: URL) -> Bool {
        try? FileManager.default.removeItem(at: archive)
        return ditto(["-c", "-k", "--keepParent", "--norsrc", "--noextattr", skin.path, archive.path])
    }

    private static func hasIdle(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "idle.png").path)
    }

    /// ditto ships with every Mac and reads and writes the zip archives Finder makes.
    private static func ditto(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = arguments
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
