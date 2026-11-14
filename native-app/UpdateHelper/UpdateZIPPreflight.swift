import Foundation

/// Validate both ZIP directory and local names before any installer can extract it.
enum UpdateZIPPreflight {
    @discardableResult
    static func validate(_ archive: URL) throws -> Int {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        func reject() throws -> Never { throw NativeUpdateFailure.integrity }
        func integer(_ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - size else { try reject() }
            return (0..<size).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        guard data.count >= 22, data.count <= 536_870_912 else { try reject() }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try integer(offset, 4) == 0x06054b50,
               try offset + 22 + integer(offset + 20, 2) == data.count {
                end = offset
                break
            }
        }
        guard let end, try integer(end + 4, 2) == 0, try integer(end + 6, 2) == 0 else { try reject() }
        let count = try integer(end + 10, 2)
        let directorySize = try integer(end + 12, 4)
        let directoryOffset = try integer(end + 16, 4)
        guard count > 0, count < 20000, try integer(end + 8, 2) == count,
              directoryOffset + directorySize == end else { try reject() }
        var cursor = directoryOffset
        var expanded = 0
        var entries: [UpdateArchiveEntry] = []
        var ranges: [Range<Int>] = []
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try integer(cursor, 4) == 0x02014b50 else { try reject() }
            let flags = try integer(cursor + 8, 2)
            let method = try integer(cursor + 10, 2)
            let compressed = try integer(cursor + 20, 4)
            let uncompressed = try integer(cursor + 24, 4)
            let nameLength = try integer(cursor + 28, 2)
            let extraLength = try integer(cursor + 30, 2)
            let commentLength = try integer(cursor + 32, 2)
            let mode = try integer(cursor + 38, 4) >> 16
            let local = try integer(cursor + 42, 4)
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard flags & ~0x0808 == 0, [0, 8].contains(method), nameLength > 0,
                  next <= end, compressed < 536_870_912, uncompressed < 2_147_483_648 else { try reject() }
            let nameBytes = data[(cursor + 46)..<(cursor + 46 + nameLength)]
            guard let name = String(data: nameBytes, encoding: .utf8),
                  !name.contains("*"), !name.contains("?"), !name.contains("[") else { try reject() }
            guard try integer(local, 4) == 0x04034b50,
                  try integer(local + 6, 2) == flags, try integer(local + 8, 2) == method,
                  try integer(local + 26, 2) == nameLength else { try reject() }
            let localExtra = try integer(local + 28, 2)
            let payload = local + 30 + nameLength + localExtra
            guard local + 30 + nameLength <= directoryOffset,
                  data[(local + 30)..<(local + 30 + nameLength)] == nameBytes,
                  payload + compressed <= directoryOffset else { try reject() }
            let range = local..<(payload + compressed)
            ranges.append(range)
            expanded += uncompressed
            guard expanded <= 2_147_483_648 else { try reject() }
            let kind: UpdateArchiveEntry.Kind
            switch mode & 0xf000 {
            case 0xa000:
                guard !name.hasSuffix("/"), uncompressed > 0, uncompressed <= 4096 else { try reject() }
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-p", archive.path, name]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try process.run()
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
                defer { watchdog.cancel() }
                var destination = Data()
                while destination.count <= 4096 {
                    let chunk = try output.fileHandleForReading.read(upToCount: 4097 - destination.count) ?? Data()
                    if chunk.isEmpty { break }
                    destination.append(chunk)
                }
                if destination.count > 4096 { process.terminate() }
                process.waitUntilExit()
                guard process.terminationStatus == 0, destination.count == uncompressed,
                      let target = String(data: destination, encoding: .utf8) else { try reject() }
                kind = .symbolicLink(target)
            case 0x4000: kind = .directory
            case 0, 0x8000: kind = name.hasSuffix("/") ? .directory : .file
            default: try reject()
            }
            entries.append(UpdateArchiveEntry(path: name.hasSuffix("/") ? String(name.dropLast()) : name, kind: kind))
            cursor = next
        }
        guard cursor == end else { try reject() }
        let ordered = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            guard previous.upperBound <= next.lowerBound else { try reject() }
        }
        try UpdateArchivePathPolicy.validate(entries, expectedRoot: "HD2FXNative.app")
        return expanded
    }
}
