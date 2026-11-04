import Foundation

/// Strict POSIX tar importer: no shell extraction, links, devices, PAX extensions,
/// absolute paths, traversal, duplicate entries or unlisted files. Published package
/// formats requiring links/extensions need a reviewed importer before becoming approved.
struct ApprovedPayload {
    let artifact: ApprovedArtifact
    let files: [String: Data]
    let modes: [String: Int]
    init(archive: URL, approved: ApprovedArtifact) throws {
        try approved.validate()
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard bytes.count <= 512 * 1_048_576, CoreHash.sha256(bytes) == approved.archiveSHA256 else { throw CoreError("ARTIFACT_HASH") }
        var offset = 0, payload: [String: Data] = [:], permissions: [String: Int] = [:], names = Set<String>()
        func text(_ range: Range<Int>) -> String { String(bytes: bytes[range].prefix { $0 != 0 }, encoding: .utf8) ?? "" }
        while offset + 512 <= bytes.count {
            let h = offset; offset += 512
            if bytes[h..<offset].allSatisfy({ $0 == 0 }) {
                guard bytes[h...].allSatisfy({ $0 == 0 }) else { throw CoreError("ARTIFACT_FORMAT") }; break
            }
            let expected = Int(text((h+148)..<(h+156)).trimmingCharacters(in: .whitespacesAndNewlines), radix: 8)
            let sum = (h..<(h+512)).reduce(0) { $0 + ((h+148..<h+156).contains($1) ? 32 : Int(bytes[$1])) }
            guard expected == sum, let size = Int(text((h+124)..<(h+136)).trimmingCharacters(in: .whitespacesAndNewlines), radix: 8),
                  size >= 0, size <= bytes.count - offset,
                  let mode = Int(text((h+100)..<(h+108)).trimmingCharacters(in: .whitespacesAndNewlines), radix: 8), mode & 0o7000 == 0 else { throw CoreError("ARTIFACT_FORMAT") }
            let prefix = text((h+345)..<(h+500)), name = text(h..<(h+100))
            var path = prefix.isEmpty ? name : prefix + "/" + name
            let type = bytes[h+156]
            if type == 53 && path.hasSuffix("/") { path.removeLast() }
            guard ApprovedArtifact.safe(path), names.insert(path).inserted, [UInt8(0), 48, 53].contains(type),
                  text((h+157)..<(h+257)).isEmpty else { throw CoreError("UNSAFE_PATH") }
            if type != 53 {
                guard approved.files[path] != nil else { throw CoreError("ARTIFACT_HASH") }
                let data = bytes.subdata(in: offset..<(offset+size))
                guard CoreHash.sha256(data) == approved.files[path] else { throw CoreError("ARTIFACT_HASH") }
                payload[path] = data; permissions[path] = mode & 0o777
            } else { guard size == 0 else { throw CoreError("ARTIFACT_FORMAT") } }
            offset += ((size + 511) / 512) * 512
        }
        guard Set(payload.keys) == Set(approved.files.keys), offset <= bytes.count else { throw CoreError("ARTIFACT_HASH") }
        artifact = approved; files = payload; modes = permissions
    }
}
struct ComponentInstallReceipt: Codable {
    let id: UUID, target: String, boot: String, component: String, version: String
    let manifest: [String: String], originalManifest: [String: String]?, backup: String
    var state: DeploymentState
}

/// Actual Guest installer, callable only with an artifact from the bundled profile.
/// It stages all files, verifies the complete tree, retains an existing known tree as a
/// unique backup, and never overwrites an unknown installation or an existing backup.
final class ComponentDeploymentAdapter {
    let backend: SSHEnvironmentBackend, store: URL
    init(backend: SSHEnvironmentBackend, store: URL) { self.backend = backend; self.store = store }
    func install(archive: URL, component: String, profile: EnvironmentProfile,
                 knownCurrent: [String: String]?, expected: DeploymentSnapshot, confirmed: Bool) throws -> ComponentInstallReceipt {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        guard let artifact = profile.artifacts.first(where: { $0.component == component }) else { throw CoreError("ARTIFACT_UNAPPROVED") }
        let payload = try ApprovedPayload(archive: archive, approved: artifact)
        let live = try backend.snapshot()
        guard EnvironmentDeploymentService.identity(live, expected), live.revision == expected.revision else { throw CoreError("TARGET_CHANGED") }
        try EnvironmentDeploymentService.idle(live)
        let size = payload.files.values.reduce(Int64(0)) { $0 + Int64($1.count) }
        guard live.freeBytes > size * 3 + 16 * 1_048_576 else { throw CoreError("INSUFFICIENT_SPACE") }
        let id = UUID(), suffix = id.uuidString
        let relative: String
        if component == "fex" { relative = "steamapps/common/FEX-Emu" }
        else if component == "proton", artifact.version.range(of: "^proton-je-[a-z0-9.-]+$", options: .regularExpression) != nil { relative = "compatibilitytools.d/" + artifact.version }
        else { throw CoreError("ARTIFACT_UNAPPROVED") }
        var receipt = ComponentInstallReceipt(id: id, target: live.target, boot: live.boot, component: component,
            version: artifact.version, manifest: artifact.files, originalManifest: knownCurrent,
            backup: relative + ".hd2-backup-" + suffix, state: .Deploying)
        try CoreFS.ensurePrivateDirectory(store)
        let lock = try CoreFileLock.acquire(store.appendingPathComponent(".package.lock")); defer { lock.release() }
        let receiptFile = store.appendingPathComponent(suffix + ".json")
        try CoreFS.atomicWrite(try JSONEncoder().encode(receipt), to: receiptFile)
        let script = try Self.installScript(payload: payload, knownCurrent: knownCurrent, live: live, relative: relative, suffix: suffix)
        do {
            _ = try backend.hostIdentity()
            let result = try backend.transport.run(script, timeout: 180, context: backend.context)
            guard result.status == 0 else { throw CoreError("COMPONENT_INSTALL_FAILED") }
            receipt.state = .Completed
        } catch {
            receipt.state = .RecoveryRequired
            try CoreFS.atomicWrite(try JSONEncoder().encode(receipt), to: receiptFile)
            throw CoreError("RECOVERY_REQUIRED")
        }
        try CoreFS.atomicWrite(try JSONEncoder().encode(receipt), to: receiptFile)
        return receipt
    }
    static func installScript(payload: ApprovedPayload, knownCurrent: [String: String]?, live: DeploymentSnapshot, relative: String, suffix: String) throws -> String {
        let artifact = payload.artifact
        func verify(_ manifest: [String: String], variable: String) -> String {
            var script = "[ \"$(find \"$\(variable)\" -type f | wc -l | tr -d ' ')\" = '\(manifest.count)' ] || exit 82\n"
            script += "[ -z \"$(find \"$\(variable)\" ! -type d ! -type f -print -quit)\" ] || exit 82\n"
            for (path, hash) in manifest.sorted(by: { $0.key < $1.key }) {
                script += "[ \"$(sha256sum \"$\(variable)/\"\(SSHEnvironmentBackend.quote(path)) | cut -d' ' -f1)\" = '\(hash)' ] || exit 82\n"
            }
            return script
        }
        let target = "$HOME/.local/share/Steam/" + relative
        var script = """
        set -eu
        umask 077
        p="\(target)"
        stage="$p.hd2-stage-\(suffix)"
        backup="$p.hd2-backup-\(suffix)"
        lock="$HOME/.hd2-native-deployment-lock"
        mkdir "$lock" || exit 80
        trap 'rmdir "$lock"' EXIT
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(live.boot)' ] || exit 81
        for n in steam reaper helldivers2.exe; do if pgrep -x "$n" >/dev/null; then exit 81; else [ "$?" -eq 1 ] || exit 81; fi; done
        walk="$p"; while [ "$walk" != / ]; do [ ! -L "$walk" ] || exit 81; walk=$(dirname "$walk"); done
        [ ! -e "$stage" ] && [ ! -e "$backup" ] || exit 81
        """ + "\n"
        if let knownCurrent {
            guard knownCurrent.allSatisfy({ ApprovedArtifact.safe($0.key) && ApprovedArtifact.hash($0.value) }) else { throw CoreError("ARTIFACT_UNAPPROVED") }
            script += "[ -d \"$p\" ] || exit 82\n" + verify(knownCurrent, variable: "p")
        } else { script += "[ ! -e \"$p\" ] || exit 82\n" }
        if knownCurrent == artifact.files { script += "exit 0\n" }
        script += "mkdir -p \"$(dirname \"$p\")\"\nmkdir \"$stage\"\n"
        for (path, data) in payload.files.sorted(by: { $0.key < $1.key }) {
            script += "f=\"$stage/\"" + SSHEnvironmentBackend.quote(path) + "\nmkdir -p \"$(dirname \"$f\")\"\nprintf '%s' '" + data.base64EncodedString() + "' | base64 -d > \"$f\"\nchmod " + String(payload.modes[path] ?? 0o644, radix: 8) + " \"$f\"\n"
        }
        script += verify(artifact.files, variable: "stage")
        script += "[ \"$(cat /proc/sys/kernel/random/boot_id)\" = '\(live.boot)' ] || exit 81\n"
        script += "for n in steam reaper helldivers2.exe; do if pgrep -x \"$n\" >/dev/null; then exit 81; else [ \"$?\" -eq 1 ] || exit 81; fi; done\n"
        if let knownCurrent { script += verify(knownCurrent, variable: "p") + "mv \"$p\" \"$backup\"\n" }
        else { script += "[ ! -e \"$p\" ] || exit 82\n" }
        script += "mv \"$stage\" \"$p\"\n" + verify(artifact.files, variable: "p")
        return script
    }

}

extension ComponentDeploymentAdapter {
    /// Recover only one receipt-owned directory. Updated or mixed component trees stop here.
    /// Removed/newly installed files are retained under a unique recovery path, never deleted.
    func recover(_ id: UUID, confirmed: Bool) throws -> ComponentInstallReceipt {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        let lock = try CoreFileLock.acquire(store.appendingPathComponent(".package.lock")); defer { lock.release() }
        let file = store.appendingPathComponent(id.uuidString + ".json")
        guard !FileManager.default.isSymbolicLink(atPath: file.path) else { throw CoreError("UNSAFE_PATH") }
        var receipt = try JSONDecoder().decode(ComponentInstallReceipt.self, from: Data(contentsOf: file))
        let live = try backend.snapshot()
        guard live.target == receipt.target, live.boot == receipt.boot else { throw CoreError("TARGET_CHANGED") }
        try EnvironmentDeploymentService.idle(live)
        let relative: String
        if receipt.component == "fex" { relative = "steamapps/common/FEX-Emu" }
        else if receipt.component == "proton", receipt.version.range(of: "^proton-je-[a-z0-9.-]+$", options: .regularExpression) != nil { relative = "compatibilitytools.d/" + receipt.version }
        else { throw CoreError("UNSAFE_PATH") }
        guard receipt.backup == relative + ".hd2-backup-" + id.uuidString else { throw CoreError("UNSAFE_PATH") }
        let script = try Self.recoveryScript(receipt: receipt, live: live, relative: relative)
        do {
            let result = try backend.transport.run(script, timeout: 90, context: backend.context)
            guard result.status == 0 else { throw CoreError("RECOVERY_REQUIRED") }
            receipt.state = .Ready
        } catch { receipt.state = .RecoveryRequired; try CoreFS.atomicWrite(try JSONEncoder().encode(receipt), to: file); throw error }
        try CoreFS.atomicWrite(try JSONEncoder().encode(receipt), to: file)
        return receipt
    }
    static func recoveryScript(receipt: ComponentInstallReceipt, live: DeploymentSnapshot, relative: String) throws -> String {
        func verify(_ manifest: [String: String], variable: String) throws -> String {
            guard !manifest.isEmpty, manifest.allSatisfy({ ApprovedArtifact.safe($0.key) && ApprovedArtifact.hash($0.value) }) else { throw CoreError("ARTIFACT_UNAPPROVED") }
            var script = "[ -d \"$\(variable)\" ] && [ ! -L \"$\(variable)\" ] || return 1\n"
            script += "[ -z \"$(find \"$\(variable)\" ! -type f ! -type d -print -quit)\" ] || return 1\n"
            script += "[ \"$(find \"$\(variable)\" -type f | wc -l | tr -d ' ')\" = '\(manifest.count)' ] || return 1\n"
            for (path, hash) in manifest.sorted(by: { $0.key < $1.key }) {
                script += "[ \"$(sha256sum \"$\(variable)/\"\(SSHEnvironmentBackend.quote(path)) | cut -d' ' -f1)\" = '\(hash)' ] || return 1\n"
            }
            return script
        }
        var script = """
        set -eu
        p="$HOME/.local/share/Steam/\(relative)"
        backup="$HOME/.local/share/Steam/\(receipt.backup)"
        retained="$p.hd2-recovered-\(UUID().uuidString)"
        lock="$HOME/.hd2-native-deployment-lock"
        mkdir "$lock" || exit 80
        trap 'rmdir "$lock"' EXIT
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(live.boot)' ] || exit 81
        for n in steam reaper helldivers2.exe; do if pgrep -x "$n" >/dev/null; then exit 81; else [ "$?" -eq 1 ] || exit 81; fi; done
        walk="$p"; while [ "$walk" != / ]; do [ ! -L "$walk" ] || exit 81; walk=$(dirname "$walk"); done
        installed(){
        """ + "\n" + (try verify(receipt.manifest, variable: "p")) + "}\n"
        if let original = receipt.originalManifest {
            script += "original(){\n" + (try verify(original, variable: "p")) + "}\n"
            script += "if original; then exit 0; fi\n"
            script += "backup_ok(){\n" + (try verify(original, variable: "backup")) + "}\nbackup_ok || exit 82\n"
            script += "if [ -e \"$p\" ]; then installed || exit 82; mv \"$p\" \"$retained\"; fi\nmv \"$backup\" \"$p\"\noriginal || exit 83\n"
        } else {
            script += "if [ -e \"$p\" ]; then installed || exit 82; mv \"$p\" \"$retained\"; fi\n[ ! -e \"$p\" ] || exit 83\n"
        }
        return script
    }

}
