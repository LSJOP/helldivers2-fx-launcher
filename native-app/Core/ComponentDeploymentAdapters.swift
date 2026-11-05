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

/// Pinned upstream compressed release; full regular-file, mode, link and inventory review.
/// Python is required only inside SteamOS, never on the Mac at App runtime.
enum ProtonJERelease {
    static let version = "proton-je-11.0-20261014-3"
    static let digest = "aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485"
    static func manifest() throws -> Data {
        guard let url = Bundle.main.url(forResource: "proton-je-approved", withExtension: "json") else { throw CoreError("ARTIFACT_UNAPPROVED") }
        let data = try Data(contentsOf: url)
        guard data.count <= CoreLimits.maxResourceFile,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["archiveSHA256"] as? String == digest, object["version"] as? String == version else { throw CoreError("ARTIFACT_UNAPPROVED") }
        return data
    }
    static func script(mode: String, manifest: Data, boot: String = "", suffix: String = UUID().uuidString) throws -> String {
        guard ["probe", "install", "recover"].contains(mode), mode == "probe" || UUID(uuidString: boot) != nil,
              UUID(uuidString: suffix) != nil else { throw CoreError("INVALID_ARGUMENT") }
        let prefix = "MANIFEST=" + CoreJSON.encode(.string(manifest.base64EncodedString())) + "\nMODE=" + CoreJSON.encode(.string(mode)) + "\nBOOT=" + CoreJSON.encode(.string(boot)) + "\nSUFFIX=" + CoreJSON.encode(.string(suffix)) + "\n"
        return "python3 - <<'HD2_PROTON_PY'\n" + prefix + python + "\nHD2_PROTON_PY\n"
    }
    static let python = #"""
import os,sys,json,base64,hashlib,pathlib,stat,subprocess,tempfile,tarfile,shutil,posixpath
m=json.loads(base64.b64decode(MANIFEST))
mode=MODE
root=pathlib.Path.home()/'.local/share/Steam/compatibilitytools.d'
p=root/m['version']
def digest(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def safe_parents(path):
 for part in [path,*path.parents]:
  if part.is_symlink():raise RuntimeError('UNSAFE_PATH')
def verified(path):
 if not path.is_dir() or path.is_symlink():return False
 expected=set(m['files'])|set(m['links'])|set(m['directories'])
 actual=set()
 for d,dirs,files in os.walk(path,followlinks=False):
  for name in dirs+files:actual.add(str((pathlib.Path(d)/name).relative_to(path)))
 if actual!=expected:return False
 for name,(sha,permissions) in m['files'].items():
  f=path/name
  if not stat.S_ISREG(f.lstat().st_mode) or f.is_symlink() or digest(f)!=sha or (f.stat().st_mode&0o111)!=(permissions&0o111):return False
 for name,target in m['links'].items():
  f=path/name
  if not f.is_symlink() or os.readlink(f)!=target:return False
 return all(stat.S_ISDIR((path/name).lstat().st_mode) for name in m['directories'])
def state():
 safe_parents(p)
 if not os.path.lexists(p):return 'missing'
 return m['archiveSHA256'] if verified(p) else 'unknown'
def idle():
 if pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=BOOT:raise RuntimeError('TARGET_CHANGED')
 for name in ['reaper','helldivers2.exe']:
  r=subprocess.run(['pgrep','-x',name],stdout=subprocess.DEVNULL)
  if r.returncode!=1:raise RuntimeError('GAME_RUNNING')
if mode=='probe':
 print('proton_package='+state())
 sys.exit(0)
safe_parents(root)
root.mkdir(parents=True,exist_ok=True)
lock=pathlib.Path.home()/'.hd2-native-deployment-lock'
lock.mkdir(mode=0o700)
try:
 idle()
 if mode=='recover':
  if state()=='missing':sys.exit(0)
  if state()!=m['archiveSHA256']:raise RuntimeError('EXTERNAL_DRIFT')
  retained=root/(m['version']+'.hd2-recovered-'+SUFFIX)
  if os.path.lexists(retained):raise RuntimeError('EXTERNAL_DRIFT')
  idle();p.rename(retained)
  sys.exit(0)
 if state()!='missing':raise RuntimeError('EXTERNAL_DRIFT')
 if shutil.disk_usage(root).free < m['archiveBytes']+m['unpackedBytes']*2+67108864:raise RuntimeError('INSUFFICIENT_SPACE')
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.hd2-proton-stage-',dir=root))
 try:
  archive=stage/'payload.tar.xz'
  subprocess.run(['curl','--fail','--location','--proto','=https','--proto-redir','=https','--connect-timeout','20','--max-time','600','--max-filesize',str(m['archiveBytes']),'--output',str(archive),m['url']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=610)
  if archive.stat().st_size!=m['archiveBytes'] or digest(archive)!=m['archiveSHA256']:raise RuntimeError('ARTIFACT_HASH')
  unpack=stage/'unpack';unpack.mkdir()
  with tarfile.open(archive,'r:xz') as t:
   members=t.getmembers();seen=set()
   for member in members:
    name=member.name.rstrip('/')
    if name in seen or name.startswith('/') or '..' in name.split('/') or member.mode&0o7000:raise RuntimeError('UNSAFE_PATH')
    seen.add(name)
    if name!=m['version'] and not name.startswith(m['version']+'/'):raise RuntimeError('UNSAFE_PATH')
    if not (member.isfile() or member.isdir() or member.issym()):raise RuntimeError('UNSAFE_PATH')
    if member.issym():
     target=posixpath.normpath(posixpath.join(posixpath.dirname(name),member.linkname))
     if member.linkname.startswith('/') or not target.startswith(m['version']+'/'):raise RuntimeError('UNSAFE_PATH')
   # Parents must be real directories, never links, before extracting any file.
   names={x.name.rstrip('/'):x for x in members}
   for member in members:
    for parent in pathlib.PurePosixPath(member.name).parents:
     if str(parent) in names and not names[str(parent)].isdir():raise RuntimeError('UNSAFE_PATH')
   t.extractall(unpack,members=members)
  candidate=unpack/m['version']
  if not verified(candidate):raise RuntimeError('ARTIFACT_HASH')
  idle();safe_parents(p)
  if os.path.lexists(p):raise RuntimeError('EXTERNAL_DRIFT')
  candidate.rename(p)
  if not verified(p):raise RuntimeError('VERIFY_FAILED')
 finally:
  shutil.rmtree(stage)
finally:
 lock.rmdir()
"""#
}
