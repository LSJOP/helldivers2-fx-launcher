import Foundation

/// Preflight for archive metadata obtained by a trusted ZIP parser. This is not
/// an extractor: callers must bind metadata and extraction to the same open
/// archive and use descriptor-relative, no-follow filesystem operations.
struct UpdateArchiveEntry {
    enum Kind { case directory, file, symbolicLink(String) }
    let path: String
    let kind: Kind
}

enum UpdateArchivePathError: Error { case unsafePath, collision, linkCycle, missingTarget, childOfLink }

enum UpdateArchivePathPolicy {
    private static func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func components(_ value: String, allowParent: Bool = false) throws -> [String] {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.unicodeScalars.contains(where: { $0.value == 0 }) else { throw UpdateArchivePathError.unsafePath }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && (allowParent || $0 != "..") }) else { throw UpdateArchivePathError.unsafePath }
        return parts
    }

    /// Reject escaping, cyclic and dangling links. Archive entries may not be
    /// written through links; valid framework links may point through another
    /// link (for example Versions/Current -> A).
    static func validate(_ entries: [UpdateArchiveEntry], expectedRoot: String) throws {
        guard try components(expectedRoot).count == 1 else { throw UpdateArchivePathError.unsafePath }
        var paths: [String: UpdateArchiveEntry] = [:]
        var implied = Set<String>()
        var spellings: [String: [UInt8]] = [:]
        for entry in entries {
            let parts = try components(entry.path)
            guard let root = parts.first, Array(root.utf8) == Array(expectedRoot.utf8) else { throw UpdateArchivePathError.unsafePath }
            // Include implicit parent directories: case or Unicode aliases on
            // case-insensitive filesystems must not resolve to one destination.
            for n in 1...parts.count {
                let spelling = parts.prefix(n).joined(separator: "/")
                let folded = key(spelling)
                let bytes = Array(spelling.utf8)
                if let existing = spellings[folded], existing != bytes { throw UpdateArchivePathError.collision }
                spellings[folded] = bytes
            }
            let canonical = key(entry.path)
            guard paths[canonical] == nil else { throw UpdateArchivePathError.collision }
            paths[canonical] = entry
            if parts.count == 1 {
                guard case .directory = entry.kind else { throw UpdateArchivePathError.unsafePath }
            }
            if parts.count > 1 {
                for n in 1..<parts.count { implied.insert(key(parts.prefix(n).joined(separator: "/"))) }
            }
        }
        guard !entries.isEmpty else { throw UpdateArchivePathError.unsafePath }
        for entry in entries {
            let parts = try components(entry.path)
            if parts.count > 1 {
                for n in 1..<parts.count {
                    if let parent = paths[key(parts.prefix(n).joined(separator: "/"))] {
                        if case .symbolicLink = parent.kind { throw UpdateArchivePathError.childOfLink }
                        if case .file = parent.kind { throw UpdateArchivePathError.unsafePath }
                    }
                }
            }
            guard case .symbolicLink(let destination) = entry.kind else { continue }
            var pending = try components(destination, allowParent: true)
            var resolved = Array(parts.dropLast())
            var hops = 0
            while !pending.isEmpty {
                let part = pending.removeFirst()
                if part == ".." {
                    guard resolved.count > 1 else { throw UpdateArchivePathError.unsafePath }
                    resolved.removeLast()
                    continue
                }
                resolved.append(part)
                if let link = paths[key(resolved.joined(separator: "/"))], case .symbolicLink(let next) = link.kind {
                    hops += 1
                    guard hops <= 40 else { throw UpdateArchivePathError.linkCycle }
                    resolved.removeLast()
                    pending = try components(next, allowParent: true) + pending
                }
            }
            let target = key(resolved.joined(separator: "/"))
            guard paths[target] != nil || implied.contains(target) else { throw UpdateArchivePathError.missingTarget }
            guard spellings[target] == Array(resolved.joined(separator: "/").utf8) else { throw UpdateArchivePathError.collision }
        }
    }
}
