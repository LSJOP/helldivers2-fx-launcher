import Foundation
import CryptoKit

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
/// The two large archives share the same catalogue, Bundle lookup and SFTP transport.
enum DeploymentArchive {
    struct Entry: Decodable {
        let name: String
        let bundlePath: String
        let bytes: Int
        let sha256: String
    }

    static func verified(_ name: String, context: CoreContext) throws -> URL? {
        guard let root = Bundle.main.resourceURL?.resolvingSymlinksInPath(),
              let catalogue = Bundle.main.url(forResource: "deployment-components-v1", withExtension: "json") else { return nil }
        struct Catalogue: Decodable { let bundleArchives: [Entry] }
        let entries = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: catalogue)).bundleArchives
        guard let entry = entries.first(where: { $0.name == name }),
              ApprovedArtifact.safe(entry.bundlePath), ApprovedArtifact.hash(entry.sha256),
              (1...512 * 1024 * 1024).contains(entry.bytes) else { throw CoreError("ARTIFACT_UNAPPROVED") }
        let file = root.appendingPathComponent(entry.bundlePath)
        guard file.path == file.resolvingSymlinksInPath().path,
              let metadata = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              metadata.isRegularFile == true, metadata.fileSize == entry.bytes else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var sha = SHA256()
        var total = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try context.check()
            total += data.count
            guard total <= entry.bytes else { return nil }
            sha.update(data: data)
        }
        let hash = sha.finalize().map { String(format: "%02x", $0) }.joined()
        return total == entry.bytes && hash == entry.sha256 ? file : nil
    }
}

enum ProtonJERelease {
    static let version = "proton-je-11.0-20261014-3"
    static let digest = "aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485"
    static func manifest() throws -> Data {
        guard let url = Bundle.main.url(forResource: "proton-je-approved", withExtension: "json") else {
            throw CoreError("ARTIFACT_UNAVAILABLE")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= CoreLimits.maxResourceFile,
              CoreHash.sha256(data) == "c2469305cd27a8d613ca97aff2f676f772c037ebbbc0dd56e03512f07080efba" else {
            throw CoreError("ARTIFACT_HASH")
        }
        return data
    }
    static func damagedState(_ state: String?) -> Bool {
        guard let state, state.hasPrefix("damaged:") else { return false }
        return ApprovedArtifact.hash(String(state.dropFirst("damaged:".count)))
    }
    static func script(mode: String, manifest: Data, boot: String = "", suffix: String = UUID().uuidString,
                       useHostProxy: Bool = false, bundled: Bool = false, prior: String = "missing") throws -> String {
        guard ["probe", "install", "recover", "prepare", "cleanup"].contains(mode), mode == "probe" || UUID(uuidString: boot) != nil,
              UUID(uuidString: suffix) != nil else { throw CoreError("INVALID_ARGUMENT") }
        let prefix = "MANIFEST=" + CoreJSON.encode(.string(manifest.base64EncodedString())) + "\nMODE=" + CoreJSON.encode(.string(mode)) + "\nBOOT=" + CoreJSON.encode(.string(boot)) + "\nSUFFIX=" + CoreJSON.encode(.string(suffix)) + "\nPRIOR=" + CoreJSON.encode(.string(prior)) + "\n"
        return "python3 - <<'HD2_PROTON_PY'\n" + prefix + "USE_HOST_PROXY=" + (useHostProxy ? "1" : "0") + "\nBUNDLED=" + (bundled ? "1" : "0") + "\n" + python + "\nHD2_PROTON_PY\n"
    }
    static let python = #"""
import os,sys,json,base64,hashlib,pathlib,stat,subprocess,tempfile,tarfile,shutil,posixpath,re,signal
m=json.loads(base64.b64decode(MANIFEST))
mode=MODE
BUNDLED=globals().get('BUNDLED',0)
curl=['curl'] + (['--proxy','http://192.168.127.254:7890'] if USE_HOST_PROXY else [])
steam=pathlib.Path.home()/'.local/share/Steam'
alias=pathlib.Path.home()/'.steam/root'
if os.path.lexists(alias) and alias.resolve()!=steam.resolve():raise RuntimeError('STEAM_ROOT_CONFLICT')
root=steam/'compatibilitytools.d'
p=root/m['version']
def digest(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def safe_parents(path):
 for part in [path,*path.parents]:
  if part.is_symlink():raise RuntimeError('UNSAFE_PATH')
def verified(path,allow_runtime_cache=True):
 if not path.is_dir() or path.is_symlink():return False
 expected=set(m['files'])|set(m['links'])|set(m['directories'])
 actual=set()
 for d,dirs,files in os.walk(path,followlinks=False):
  for name in dirs+files:actual.add(str((pathlib.Path(d)/name).relative_to(path)))
 if expected-actual:return False
 extras=actual-expected
 if extras and not allow_runtime_cache:return False
 # CPython writes derived caches during ordinary Steam tool discovery.
 # Every distributed file is still hashed below; other additions remain conflicts.
 for name in extras:
  f=path/name
  if f.is_symlink() or f.lstat().st_mode&0o7000:return False
  if f.is_dir() and f.name=='__pycache__':continue
  match=re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]*)\.cpython-[0-9]{2,3}(?:\.opt-[12])?\.pyc',f.name)
  if not match or f.parent.name!='__pycache__' or not f.is_file() or f.stat().st_nlink!=1 or f.stat().st_size>4*1024*1024:return False
  source=f.parent.parent/(match.group(1)+'.py')
  if str(source.relative_to(path)) not in m['files']:return False
  with f.open('rb') as stream:header=stream.read(16)
  source_stat=source.stat()
  if len(header)!=16 or header[2:4]!=b'\r\n' or int.from_bytes(header[4:8],'little')!=0:return False
  if int.from_bytes(header[8:12],'little')!=int(source_stat.st_mtime)&0xffffffff or int.from_bytes(header[12:16],'little')!=source_stat.st_size:return False
 for name,(sha,permissions) in m['files'].items():
  f=path/name
  if not stat.S_ISREG(f.lstat().st_mode) or f.is_symlink() or digest(f)!=sha or stat.S_IMODE(f.stat().st_mode)!=permissions:return False
 for name,target in m['links'].items():
  f=path/name
  if not f.is_symlink() or os.readlink(f)!=target:return False
 return all(stat.S_ISDIR((path/name).lstat().st_mode) for name in m['directories'])
def damaged_tree(path):
 if not path.is_dir() or path.is_symlink() or path.stat().st_uid!=os.getuid():return None
 known=set(m['files'])|set(m['links'])|set(m['directories'])
 # The version directory itself is insufficient evidence of package ownership.
 identity_present=False
 for name in ('proton','version','compatibilitytool.vdf','toolmanifest.vdf'):
  f=path/name
  if name in m['files'] and not f.is_symlink() and f.is_file() and f.stat().st_size<=8*1024**2 and digest(f)==m['files'][name][0]:identity_present=True
 if not identity_present:return None
 tree={};total=0
 for folder,dirs,files in os.walk(path,followlinks=False):
  for name in dirs+files:
   f=pathlib.Path(folder)/name
   relative=f.relative_to(path).as_posix();metadata=f.lstat()
   if relative not in known or metadata.st_uid!=os.getuid() or metadata.st_mode&0o7000:return None
   if f.is_symlink():
    if relative not in m['links'] or os.readlink(f)!=m['links'][relative]:return None
    tree[relative]=['link',os.readlink(f)]
   elif stat.S_ISDIR(metadata.st_mode) and relative in m['directories']:
    tree[relative]=['dir',stat.S_IMODE(metadata.st_mode)]
   elif stat.S_ISREG(metadata.st_mode) and relative in m['files'] and metadata.st_nlink==1:
    total+=metadata.st_size
    if total>m['unpackedBytes'] or metadata.st_size>512*1024**2:return None
    tree[relative]=['file',stat.S_IMODE(metadata.st_mode),digest(f)]
   else:return None
 tree['.']=['dir',stat.S_IMODE(path.stat().st_mode)]
 return 'damaged:'+hashlib.sha256(json.dumps(tree,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def state():
 safe_parents(p)
 if not os.path.lexists(p):return 'missing'
 try:
  if verified(p):return m['archiveSHA256']
  return damaged_tree(p) or 'unknown'
 except OSError:return 'unknown'
def idle():
 if pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=BOOT:raise RuntimeError('TARGET_CHANGED')
 for name in ['reaper','helldivers2.exe']:
  r=subprocess.run(['pgrep','-x',name],stdout=subprocess.DEVNULL)
  if r.returncode!=1:raise RuntimeError('GAME_RUNNING')
if mode=='probe':
 print('proton_package='+state())
 sys.exit(0)
safe_parents(root)
PRIOR=globals().get('PRIOR','missing')
incoming=root/('.hd2-proton-incoming-'+SUFFIX)
safe_parents(incoming)
if mode=='cleanup':
 idle()
 if incoming.is_dir() and incoming.stat().st_uid==os.getuid() and stat.S_IMODE(incoming.stat().st_mode)==0o700:
  (incoming/'payload.tar.xz').unlink(missing_ok=True)
  incoming.rmdir()
 sys.exit(0)
root.mkdir(parents=True,exist_ok=True)
lock=pathlib.Path.home()/'.hd2-native-deployment-lock'
lock.mkdir(mode=0o700)
try:
 def interrupted(signum,frame):raise RuntimeError('CANCELLED')
 for sig in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(sig,interrupted)
 idle()
 before=state()
 backup=None
 if re.fullmatch(r'damaged:[0-9a-f]{64}',PRIOR):
  backup=root/('.hd2-proton-backup-'+PRIOR.split(':',1)[1])
  safe_parents(backup)
 if mode=='recover':
  if before==PRIOR:sys.exit(0)
  if before!=m['archiveSHA256']:raise RuntimeError('EXTERNAL_DRIFT')
  if backup is not None and damaged_tree(backup)!=PRIOR:raise RuntimeError('EXTERNAL_DRIFT')
  retained=root/(m['version']+'.hd2-recovered-'+SUFFIX)
  if os.path.lexists(retained):raise RuntimeError('EXTERNAL_DRIFT')
  idle();p.rename(retained)
  try:
   if backup is not None:backup.rename(p)
  except BaseException:
   retained.rename(p);raise
  sys.exit(0)
 if before!=PRIOR or (PRIOR!='missing' and backup is None):raise RuntimeError('EXTERNAL_DRIFT')
 if backup is not None and os.path.lexists(backup):raise RuntimeError('EXTERNAL_DRIFT')
 needed=m['unpackedBytes']+67108864
 if mode=='prepare' or not BUNDLED:needed+=m['archiveBytes']
 if shutil.disk_usage(root).free < needed:raise RuntimeError('INSUFFICIENT_SPACE')
 if mode=='prepare':
  incoming.mkdir(mode=0o700)
  print(str(incoming/'payload.tar.xz'))
  sys.exit(0)
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.hd2-proton-stage-',dir=root))
 try:
  archive=(incoming if BUNDLED else stage)/'payload.tar.xz'
  safe_parents(archive)
  if not BUNDLED:
   cache=pathlib.Path.home()/'.cache/hd2fx-native/artifacts'/(m['archiveSHA256']+'.tar.xz')
   safe_parents(cache)
   if cache.is_file() and cache.stat().st_nlink==1 and cache.stat().st_size==m['archiveBytes'] and digest(cache)==m['archiveSHA256']:
    shutil.copyfile(cache,archive)
   else:
    subprocess.run(curl+['--fail','--location','--proto','=https','--proto-redir','=https','--connect-timeout','20','--max-time','600','--max-filesize',str(m['archiveBytes']),'--output',str(archive),m['url']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=610)
  metadata=archive.lstat()
  if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink!=1 or metadata.st_size!=m['archiveBytes'] or digest(archive)!=m['archiveSHA256']:raise RuntimeError('ARTIFACT_HASH')
  sha512=hashlib.sha512()
  with open(archive,'rb') as f:
   for b in iter(lambda:f.read(1048576),b''):sha512.update(b)
  if sha512.hexdigest()!=m['archiveSHA512']:raise RuntimeError('ARTIFACT_HASH')
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
  if not verified(candidate,allow_runtime_cache=False):raise RuntimeError('ARTIFACT_HASH')
  idle();safe_parents(p)
  if state()!=PRIOR or (backup is not None and os.path.lexists(backup)):raise RuntimeError('EXTERNAL_DRIFT')
  moved=False
  activated=False
  try:
   if backup is not None:
    p.rename(backup);moved=True
   candidate.rename(p);activated=True
   if not verified(p):raise RuntimeError('VERIFY_FAILED')
  except BaseException:
   if activated:p.rename(candidate)
   if moved:backup.rename(p)
   raise
 finally:
  shutil.rmtree(stage)
finally:
 lock.rmdir()
"""#
}

/// Pinned-source build review and independent installed-runtime compatibility probes.
enum FEXWorkflow {
    // These exact FX releases shipped the same stock FEX binary and failed
    // the recorded Wine launch. A synthetic probe or approval cannot override this.
    static func hasKnownLaunchIncompatibility(fxVersion: String, architecture: String, executableSHA256: String?) -> Bool {
        ["1.9.9", "1.9.12"].contains(fxVersion) && architecture == "aarch64" &&
            executableSHA256 == "f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e"
    }

    static func runtimeProbeInput(boot: String, tree: String, runtimePath: String) -> String {
        let input: JSONValue = .object(["boot": .string(boot), "tree": .string(tree), "runtime_path": .string(runtimePath)])
        return Data(CoreJSON.encode(input).utf8).base64EncodedString()
    }

    /// Recompute the full installed tree before running the compatibility probe.
    static func observe(_ backend: SSHEnvironmentBackend, snapshot: inout DeploymentSnapshot) throws {
        let helpers = SteamRuntime4.evidence + "\n" + pipeline.components(separatedBy: "work=pathlib.Path.home()")[0]
        func probe(_ expected: String = "", runtimePath: String = "") throws -> [String: JSONValue] {
            let input = runtimeProbeInput(boot: snapshot.boot, tree: expected, runtimePath: runtimePath)
            let script = """
            python3 - <<'HD2_FEX_PROBE'
            import base64,json
            request=json.loads(base64.b64decode('\(input)'))
            EXPECTED_BOOT=request['boot']
            EXPECTED_TREE=request['tree']
            RUNTIME_PATH=request['runtime_path']
            \(helpers)
            \(runtimeProbe)
            HD2_FEX_PROBE
            """
            let result = try backend.transport.run(script, timeout: 150, context: backend.context)
            guard result.status == 0, let bytes = result.stdout.data(using: .utf8),
                  let value = try? JSONDecoder().decode([String: JSONValue].self, from: bytes) else { throw CoreError("FEX_RUNTIME_FAILED") }
            return value
        }
        let staticResult = try probe()
        snapshot.facts["fex_status"] = "repair"
        snapshot.facts["fex_reason"] = staticResult["reason"]?.text ?? "FEX_RUNTIME_FAILED"
        for key in ["diagnostic_reason", "source_type", "root", "path", "repair_tree", "managed_emulator"] {
            if let value = staticResult[key]?.text { snapshot.facts["fex_" + key] = value }
        }
        if let present = staticResult["root_present"]?.boolean {
            snapshot.facts["fex_root_present"] = present ? "true" : "false"
        }
        if staticResult["layout"]?.text == "proton-integrated" {
            snapshot.facts["fex_status"] = "unverified"
            snapshot.facts["fex_layout"] = "proton-integrated"
            snapshot.facts["fex_path"] = staticResult["path"]?.text
            snapshot.facts["fex_proton_version"] = staticResult["version"]?.text
            snapshot.facts["fex_config_sha256"] = staticResult["Config.json_sha256"]?.text
            if let hashes = staticResult["library_hashes"] {
                snapshot.facts["fex_library_hashes"] = CoreJSON.encode(hashes)
            }
        }
        guard staticResult["preflight"]?.boolean == true, let tree = staticResult["tree"]?.text else { return }
        if hasKnownLaunchIncompatibility(fxVersion: snapshot.fxVersion, architecture: snapshot.architecture,
                                         executableSHA256: staticResult["executable_sha256"]?.text) {
            snapshot.facts["fex_reason"] = "FEX_KNOWN_LAUNCH_INCOMPATIBILITY"
            snapshot.facts["fex_diagnostic_reason"] = "FEX_KNOWN_LAUNCH_INCOMPATIBILITY"
            return
        }
        let approval = runtimeApproval(tree: tree, snapshot: snapshot)
        snapshot.facts["fex_fingerprint"] = approval
        snapshot.facts["fex_tree"] = tree
        snapshot.facts["fex_executable_sha256"] = staticResult["executable_sha256"]?.text
        snapshot.facts["fex_managed_emulator"] = staticResult["managed_emulator"]?.text
        snapshot.facts["fex_registered_rootfs"] = staticResult["registered_rootfs"]?.text
        let matchesPackage = tree == packagedGuestTree && staticResult["source_type"]?.text == "app-managed"
        let reviewed = matchesPackage || verifyInstalled(tree: tree, snapshot: snapshot)
        snapshot.facts["fex_provenance"] = reviewed ? "verified" : "unverified"
        guard reviewed else {
            snapshot.facts["fex_reason"] = "FEX_CHANGED"
            return
        }
        let dependency = try SteamRuntime4.observe(backend, snapshot: snapshot)
        snapshot.facts["steam_runtime_phase"] = dependency.phase
        snapshot.facts["steam_runtime_build"] = dependency.build
        snapshot.facts["steam_runtime_version"] = dependency.version
        guard let runtimePath = dependency.path else {
            snapshot.facts["fex_reason"] = dependency.phase == "incompatible" ? SteamRuntime4.unverified : SteamRuntime4.missing
            return
        }
        let runtime = try probe(tree, runtimePath: runtimePath)
        guard runtime["runtime"]?.boolean == true else {
            snapshot.facts["fex_reason"] = runtime["reason"]?.text ?? "FEX_RUNTIME_FAILED"
            return
        }
        snapshot.facts["fex_status"] = "normal"
        snapshot.facts["fex_runtime"] = "ready"
        snapshot.facts["fex_probe_rootfs"] = runtime["probe_rootfs"]?.text
        snapshot.facts["fex_loaded_executable"] = runtime["loaded_executable"]?.text
        snapshot.facts["fex_reason"] = ""
    }
    private static func runtimeApproval(tree: String, snapshot: DeploymentSnapshot) -> String {
        let binding = ["fx_path", "machine_id", "fx_executable_sha256", "ssh_connection"].map { snapshot.facts[$0] ?? "UNKNOWN" }
        return CoreHash.sha256(Data((binding.joined(separator: "|") + "|" + tree).utf8))
    }

    static func requireCompatible(_ snapshot: DeploymentSnapshot) throws {
        guard ["normal", "compatible"].contains(snapshot.facts["fex_status"] ?? "") else {
            throw CoreError(snapshot.facts["fex_reason"] ?? "FEX_RUNTIME_FAILED")
        }
    }
    static let runtimeProbe = #"""
import struct,tempfile,platform,os
managed_root=pathlib.Path.home()/'.local/share/HD2FXLauncher/compatibility/FEX-RF'
steam_root=pathlib.Path.home()/'.local/share/Steam/steamapps/common/FEX-Emu'
managed=os.path.lexists(managed_root)
root=managed_root if managed else steam_root
source_type='app-managed' if managed else 'steam-managed'
exe=root/'usr/bin/FEX'
def failure(reason,diagnostic=None,**details):
 result={'reason':reason,'diagnostic_reason':diagnostic or reason,'source_type':source_type,
         'root':str(root),'path':str(exe)}
 try:
  # Only an exact inventory of the App-owned tree may authorize replacement.
  # A symlink, unreadable tree or concurrently changing tree remains blocked.
  if managed and root.is_dir() and not root.is_symlink() and os.access(root,os.R_OK|os.X_OK):
   repair_inventory=inventory(root)
   result['repair_tree']=fingerprint(repair_inventory)
   result['managed_emulator']=str(root/'emulator.json')
 except (OSError,PermissionError):pass
 result.update(details);return result
def check():
 if pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=EXPECTED_BOOT:return {'reason':'TARGET_CHANGED'}
 if os.path.lexists(root) and root.is_symlink():return failure('FEX_INTEGRITY_FAILED','FEX_ROOT_SYMLINK')
 try:
  root_present=root.exists()
  root_directory=root.is_dir() if root_present else False
 except PermissionError:return failure('FEX_PERMISSION_DENIED','FEX_ROOT_PERMISSION_DENIED')
 if root_present and not root_directory:return failure('FEX_INTEGRITY_FAILED','FEX_ROOT_NOT_DIRECTORY')
 if root_present and not os.access(root,os.R_OK|os.X_OK):return failure('FEX_PERMISSION_DENIED','FEX_ROOT_ACCESS_DENIED')
 if not exe.is_file():
  bundled=pathlib.Path.home()/'.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)'
  libraries=[bundled/'files/lib/wine/aarch64-unix'/name for name in ['libarm64ecfex.so','libwow64fex.so']]
  if all(p.is_file() and not p.is_symlink() and elf_arm64(p) for p in libraries):
   version=bundled/'version'
   config=bundled/'files/share/fex-emu/Config.json'
   metadata={'reason':'FEX_PROTON_INTEGRATED_UNVERIFIED','layout':'proton-integrated',
             'diagnostic_reason':'FEX_PROTON_INTEGRATED_ONLY','source_type':'proton-integrated',
             'path':str(bundled),'library_hashes':{p.name:digest(p) for p in libraries}}
   for p in [version,config]:
    safe(p)
    if p.is_file() and p.stat().st_size<=65536:
     metadata[p.name+'_sha256']=digest(p)
     if p==version:metadata['version']=p.read_text().strip()[:256]
   return metadata
  deployment_parent=managed_root.parent
  while not deployment_parent.exists() and deployment_parent!=deployment_parent.parent:
   deployment_parent=deployment_parent.parent
  if not os.access(deployment_parent,os.W_OK|os.X_OK):
   return failure('FEX_PERMISSION_DENIED','FEX_DEPLOYMENT_PARENT_NOT_WRITABLE',root_present=root_present)
  return failure('FEX_MISSING','FEX_BINARY_MISSING' if root_present else 'FEX_COMPONENT_ABSENT',root_present=root_present)
 if not os.access(exe,os.R_OK):return failure('FEX_PERMISSION_DENIED','FEX_READ_PERMISSION_DENIED')
 if not os.access(exe,os.X_OK):return failure('FEX_NOT_EXECUTABLE','FEX_EXECUTE_PERMISSION_DENIED')
 if platform.machine() not in ['aarch64','arm64'] or not elf_arm64(exe):return failure('FEX_ARCHITECTURE','FEX_BINARY_ARCHITECTURE_MISMATCH')
 if not (root/'emulator.json').is_file():return failure('FEX_INTEGRATION_MISSING','FEX_EMULATOR_CONFIG_MISSING')
 try:registration=json.loads((root/'emulator.json').read_text()).get('emulator_v0',{})
 except PermissionError:return failure('FEX_PERMISSION_DENIED','FEX_CONFIG_PERMISSION_DENIED')
 except (OSError,ValueError,TypeError):return failure('FEX_INTEGRATION_MISSING','FEX_EMULATOR_CONFIG_INVALID')
 if registration.get('argv') not in ['./usr/bin/FEX','usr/bin/FEX']:return failure('FEX_INTEGRATION_MISSING','FEX_EMULATOR_ENTRY_INVALID')
 for key in ['main_argv','server_argv']:
  command=registration.get(key)
  if command:
   parts=shlex.split(command)
   if len(parts)!=1:return failure('FEX_INTEGRATION_MISSING','FEX_INTEGRATION_COMMAND_INVALID')
   component=root/parts[0]
   if not component.resolve().is_relative_to(root.resolve()) or not component.is_file() or not os.access(component,os.X_OK):return failure('FEX_INTEGRATION_MISSING','FEX_INTEGRATION_COMPONENT_INVALID')
 # The SteamOS wrapper uses this provider when Steam supplies no override.
 # This is a guest-side prerequisite, not proof of the container's effective configuration.
 provider=pathlib.Path('/usr/share/guestos/fex-mesa')
 if not (provider/'graphics_provider.json').is_file() or not any(
     (provider/path).is_file() for path in (
         'lib64/ld-linux-x86-64.so.2', 'usr/lib/ld-linux-x86-64.so.2',
         'lib/x86_64-linux-gnu/ld-linux-x86-64.so.2')):
  return failure('FEX_ROOTFS_UNAVAILABLE','FEX_ROOTFS_PROVIDER_MISSING')
 files=inventory(root)
 entry=files.get('usr/bin/FEX',[])
 if not entry or entry[0]!='file':return failure('FEX_INTEGRITY_FAILED','FEX_EXECUTABLE_INVENTORY_INVALID')
 tree=fingerprint(files)
 result={'preflight':True,'tree':tree,'executable_sha256':entry[1],
         'source_type':source_type,'root':str(root),'path':str(exe),'diagnostic_reason':'FEX_PREFLIGHT_PASSED'}
 if managed:
  result['managed_emulator']=str(root/'emulator.json')
  registered=registration.get('container_environment',{}).get('FEX_ROOTFS')
  if isinstance(registered,str):result['registered_rootfs']=registered
 if not EXPECTED_TREE:return result
 if tree!=EXPECTED_TREE:return {'reason':'FEX_CHANGED'}
 # Static x86-64 ELF with one load segment and exit(42), requiring no x86 libc.
 code=bytes.fromhex('b83c000000bf2a0000000f05')
 ident=b'\x7fELF\x02\x01\x01'+bytes(9)
 header=struct.pack('<16sHHIQQQIHHHHHH',ident,2,62,1,0x400078,64,0,0,64,56,1,0,0,0)
 segment=struct.pack('<IIQQQQQQ',1,5,0,0x400000,0x400000,120+len(code),120+len(code),4096)
 with tempfile.TemporaryDirectory(prefix='hd2-fex-probe-') as d:
  test=pathlib.Path(d)/'probe';test.write_bytes(header+segment+code);test.chmod(0o700)
  env=dict(os.environ,FEX_DISKCACHE='0',FEX_SILENTLOG='1')
  try:
   with open(os.devnull,'wb') as sink:
    process=subprocess.Popen([str(exe),str(test)],stdout=sink,stderr=sink,env=env,start_new_session=True)
    try:status=process.wait(timeout=12)
    except subprocess.TimeoutExpired:
     os.killpg(process.pid,signal.SIGKILL);process.wait();return {'reason':'FEX_TIMEOUT'}
  except OSError:return {'reason':'FEX_DEPENDENCY_FAILED'}
 if fingerprint(inventory(root))!=tree:return {'reason':'FEX_CHANGED'}
 if pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=EXPECTED_BOOT:return {'reason':'TARGET_CHANGED'}
 if status!=42:return {'reason':'FEX_RUNTIME_FAILED'}
 if RUNTIME_PATH:
  rt=pathlib.Path(RUNTIME_PATH)
  safe(rt)
  if not runtime_evidence(rt)[1]:return {'reason':'STEAM_RUNTIME_INCOMPATIBLE'}
  env=dict(os.environ,PRESSURE_VESSEL_EMULATOR=str(root/'emulator.json'),
           STEAM_COMPAT_EMULATOR=str(steam_root/'emulator.json'),
           STEAM_COMPAT_GRAPHICS_PROVIDER=str(provider/'graphics_provider.json'),
           STEAM_COMPAT_MACHINE_ARCHITECTURE='aarch64-linux-gnu',
           PRESSURE_VESSEL_PREFIX=str(rt/'pressure-vessel-arm64'))
  env.pop('FEX_ROOTFS',None)
  command=[str(rt/'_v2-entry-point'),'--verb=run','--','/bin/sh','-c',
           'case "${FEX_ROOTFS-unset}" in "") r=empty;; /) r=slash;; /usr/share/guestos/fex-mesa|/usr/share/guestos/fex-mesa/) r=provider;; unset) r=unset;; *) r=other;; esac; printf "HD2_ROOTFS_OK:%s\n" "$r"; sleep 1']
  with tempfile.TemporaryDirectory(prefix='hd2-fex-container-') as data:
   # Simulate Steam's per-app data contract without touching the game prefix.
   env.update(STEAM_COMPAT_DATA_PATH=data,FEX_APP_DATA_LOCATION=data+'/fex-emu',FEX_DISABLETELEMETRY='1')
   try:
    container=subprocess.Popen(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    deadline=time.monotonic()+90;loaded=False
    while True:
     loaded=loaded or observed_managed_executable(container.pid,exe)
     try:output,errors=container.communicate(timeout=0.15);break
     except subprocess.TimeoutExpired:
      if time.monotonic()>=deadline:
       os.killpg(container.pid,signal.SIGKILL);container.communicate();return {'reason':'FEX_TIMEOUT'}
   except OSError:return {'reason':'FEX_DEPENDENCY_FAILED'}
   evidence=[line for line in output.splitlines() if line.startswith(b'HD2_ROOTFS_OK:')]
   if container.returncode!=0 or len(evidence)!=1 or not loaded:return {'reason':'FEX_RUNTIME_FAILED'}
  if fingerprint(inventory(root))!=tree:return {'reason':'FEX_CHANGED'}
  result['probe_rootfs']=evidence[0].split(b':',1)[1].decode()
  result['loaded_executable']=str(exe)
 result['runtime']=True
 return result
try:print(json.dumps(check()))
except Exception:print(json.dumps({'reason':'FEX_INTEGRITY_FAILED'}))
"""#
    static func installedDigest(_ record: [String: JSONValue], snapshot: DeploymentSnapshot) -> String? {
        guard record["built"]?.boolean == true, record["audit"]?.object["ready"]?.boolean == true,
              record["audit"]?.object["source"]?.text == "87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8",
              record["audit"]?.object["patch"]?.text == "85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926",
              let executable = record["audit"]?.object["executable_sha256"]?.text, ApprovedArtifact.hash(executable),
              record["installation"]?.object["verified"]?.boolean == true,
              let digest = record["installation"]?.object["installed_manifest"]?.text, ApprovedArtifact.hash(digest) else { return nil }
        for key in ["fx_path", "machine_id", "fx_executable_sha256", "ssh_connection"] {
            guard let value = snapshot.facts[key], !value.isEmpty, record[key]?.text == value else { return nil }
        }
        return digest
    }
    static func verifyInstalled(tree: String, snapshot: DeploymentSnapshot) -> Bool {
        let store = CoreFS.nativeData().appendingPathComponent("fex-reviews", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: store, includingPropertiesForKeys: nil),
              files.count <= 1024 else { return false }
        for file in files where file.pathExtension == "json" && !FileManager.default.isSymbolicLink(atPath: file.path) {
            guard let bytes = try? Data(contentsOf: file), bytes.count < 1_048_576,
                  let record = try? JSONDecoder().decode([String: JSONValue].self, from: bytes),
                  let digest = installedDigest(record, snapshot: snapshot) else { continue }
            // The runtime probe rechecks this exact tree before executing any FEX code.
            if digest == tree { return true }
        }
        return false
    }

    private struct RFBundleFile: Decodable {
        let path: String, name: String, sha256: String
        let bytes: Int, mode: Int
    }
    private struct RFBundleManifest: Decodable {
        let schema: Int, packageID: String, version: String, expectedFiles: Int
        let payloadFingerprint: String
        let guestRoot: String, files: [RFBundleFile]
    }
    private struct RFBundlePackage {
        let id: String, fingerprint: String, files: [JSONValue]
    }

    private static let packagedManifestHash = "8354dbaf034e5c96d3b5cee84354e5a9650aea2c04245c979ff42be4d44636d8"
    private static let packagedGuestTree = "518185cf0713a01224d38c04897897547d8ec5e80f04426a45662b5bdd64e09f"

    private static func bundledPackage(context: CoreContext) throws -> (RFBundlePackage, String) {
        guard let resources = Bundle.main.resourceURL?.resolvingSymlinksInPath() else {
            throw CoreError("ARTIFACT_UNAVAILABLE")
        }
        let deployment = resources.appendingPathComponent("Deployment", isDirectory: true)
        do {
            return (try verifiedPackage(deployment: deployment, manifestDirectory: resources), "app-bundle")
        } catch {
            try context.check()
        }
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }

        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, let build = Int(buildString),
              let keyString = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: keyString),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              (try? NativeVersion(version)) != nil else { throw CoreError("ARTIFACT_UNAVAILABLE") }
        let release = "https://github.com/" + NativeUpdateHTTP.repository + "/releases/download/v" + version + "/"
        func download(_ url: URL, bytes: Int64, name: String) throws -> URL {
            guard NativeUpdateHTTP.trusted(url) else { throw CoreError("ARTIFACT_UNAVAILABLE") }
            let output = workspace.appendingPathComponent(name)
            let result = try CoreProcess.run("/usr/bin/curl", ["--disable", "--fail", "--silent", "--location",
                "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15", "--max-time", "120",
                "--max-filesize", String(bytes), "--output", output.path, url.absoluteString],
                timeout: 125, context: context)
            guard result.status == 0 else { throw CoreError("ARTIFACT_UNAVAILABLE") }
            return output
        }
        guard let manifestAsset = URL(string: release + "update-manifest-v3.json"),
              let signatureAsset = URL(string: release + "update-manifest-v3.sig") else { throw CoreError("ARTIFACT_UNAVAILABLE") }
        let manifestURL = try download(manifestAsset, bytes: 65_536, name: "manifest")
        let signatureURL = try download(signatureAsset, bytes: 1024, name: "signature")
        let manifest = try Data(contentsOf: manifestURL)
        guard let signature = Data(base64Encoded: try String(contentsOf: signatureURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              publicKey.isValidSignature(signature, for: manifest) else { throw CoreError("ARTIFACT_HASH") }
        let releaseManifest = try JSONDecoder().decode(NativeUpdateManifest.self, from: manifest)
        guard releaseManifest.schema == 3, releaseManifest.bundleID == NativeReleaseService.bundleID,
              releaseManifest.version == version, releaseManifest.build == build,
              releaseManifest.architecture == "arm64", releaseManifest.channel == "stable",
              let components = releaseManifest.components else { throw CoreError("ARTIFACT_UNAVAILABLE") }
        try components.validate(version: version, build: build)
        guard let module = components.modules.first(where: { $0.id == "rf-fex" }),
              module.artifact.length <= 48 * 1_048_576, module.artifact.expandedBytes <= 48 * 1_048_576 else {
            throw CoreError("ARTIFACT_UNAVAILABLE")
        }
        let archive = try download(module.artifact.url, bytes: module.artifact.length, name: "rf.zip")
        guard try ComponentUpdate.fileDigest(archive, length: module.artifact.length) == module.artifact.sha256 else {
            throw CoreError("ARTIFACT_HASH")
        }
        try ComponentUpdate.extract(archive, at: workspace, expectedBytes: module.artifact.expandedBytes)
        let root = workspace.appendingPathComponent(ComponentUpdate.rootName).appendingPathComponent(module.path)
        guard try ComponentUpdate.tree(root, limit: module.artifact.expandedBytes).hash == module.treeSHA256 else {
            throw CoreError("ARTIFACT_HASH")
        }
        let package = try verifiedPackage(deployment: root.deletingLastPathComponent(), manifestDirectory: resources)
        return (package, "verified-download")
    }

    /// Pinned manifest bytes and the complete file inventory are checked for both sources.
    private static func verifiedPackage(deployment: URL, manifestDirectory: URL) throws -> RFBundlePackage {
        let root = deployment.appendingPathComponent("RF-FEX", isDirectory: true)
        let manifestURL = manifestDirectory.appendingPathComponent("rf-fex-package-v1.json")
        let manifestValues = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard manifestValues?.isRegularFile == true, manifestValues?.isSymbolicLink != true,
              let manifestSize = manifestValues?.fileSize, manifestSize < 1_048_576,
              rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true,
              manifestURL.path == manifestURL.resolvingSymlinksInPath().path,
              root.path == root.resolvingSymlinksInPath().path else {
            throw CoreError("ARTIFACT_UNAVAILABLE")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard replayHash(manifestData) == packagedManifestHash else { throw CoreError("ARTIFACT_HASH") }
        let manifest = try JSONDecoder().decode(RFBundleManifest.self, from: manifestData)
        guard manifest.schema == 1, manifest.expectedFiles == 41, manifest.files.count == 41,
              manifest.guestRoot == "~/.local/share/HD2FXLauncher/compatibility/FEX-RF",
              ApprovedArtifact.hash(manifest.payloadFingerprint) else { throw CoreError("ARTIFACT_FORMAT") }
        var expected = Set<String>(), actual = Set<String>()
        var payload: [JSONValue] = [], total = 0
        var fingerprint = Data()
        for entry in manifest.files.sorted(by: { $0.path < $1.path }) {
            guard ApprovedArtifact.safe(entry.path), expected.insert(entry.path).inserted,
                  entry.name == URL(fileURLWithPath: entry.path).lastPathComponent,
                  entry.bytes >= 0, entry.bytes <= 8 * 1_048_576, [0o644, 0o755].contains(entry.mode),
                  ApprovedArtifact.hash(entry.sha256) else {
                throw CoreError("ARTIFACT_FORMAT")
            }
            let file = root.appendingPathComponent(entry.path)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == entry.bytes,
                  file.path == file.resolvingSymlinksInPath().path,
                  file.path.hasPrefix(root.path + "/") else { throw CoreError("UNSAFE_PATH") }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard (attributes[.posixPermissions] as? NSNumber)?.intValue == entry.mode else {
                throw CoreError("ARTIFACT_MODE")
            }
            let contents = try Data(contentsOf: file)
            guard contents.count == entry.bytes, replayHash(contents) == entry.sha256 else {
                throw CoreError("ARTIFACT_HASH")
            }
            total += contents.count
            guard total <= 48 * 1_048_576 else { throw CoreError("OUTPUT_LIMIT") }
            fingerprint.append(Data(entry.path.utf8)); fingerprint.append(0)
            fingerprint.append(Data(entry.sha256.utf8)); fingerprint.append(0)
            fingerprint.append(Data(String(entry.mode).utf8)); fingerprint.append(10)
            payload.append(.object(["path": .string(entry.path), "sha256": .string(entry.sha256),
                                    "mode": .number(Double(entry.mode)), "data": .string(contents.base64EncodedString())]))
        }
        guard replayHash(fingerprint) == manifest.payloadFingerprint,
              let iterator = FileManager.default.enumerator(atPath: root.path) else {
            throw CoreError("ARTIFACT_HASH")
        }
        var scanned = 0
        for case let relative as String in iterator {
            scanned += 1
            let file = root.appendingPathComponent(relative)
            guard scanned <= 128 else { throw CoreError("OUTPUT_LIMIT") }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CoreError("UNSAFE_PATH") }
            if values.isRegularFile == true {
                guard ApprovedArtifact.safe(relative) else { throw CoreError("UNSAFE_PATH") }
                actual.insert(relative)
            }
        }
        guard actual == expected else { throw CoreError("ARTIFACT_HASH") }
        return RFBundlePackage(id: manifest.packageID, fingerprint: manifest.payloadFingerprint, files: payload)
    }

    private static func replayHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func deployReplay(backend: SSHEnvironmentBackend, snapshot: DeploymentSnapshot,
                                     request original: [String: JSONValue], files: [JSONValue]) throws -> [String: JSONValue] {
        let dependency = try SteamRuntime4.observe(backend, snapshot: snapshot)
        guard let runtimePath = dependency.path else {
            throw CoreError(dependency.phase == "incompatible" ? SteamRuntime4.unverified : SteamRuntime4.missing)
        }
        var original = original
        original["runtime_path"] = .string(runtimePath)
        _ = try runLocalReplay(backend: backend, request: original, phase: "preflight")
        var install = original
        install["mode"] = .string("local_replay")
        install["ticket"] = .string(UUID().uuidString.lowercased())
        let payload = Data(CoreJSON.encode(.array(files)).utf8)
        guard payload.count <= 48 * 1_048_576 else { throw CoreError("OUTPUT_LIMIT") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let payloadFile = directory.appendingPathComponent("files.json")
        try payload.write(to: payloadFile, options: .atomic)
        install["files_sha256"] = .string(replayHash(payload))
        let staging = try runLocalReplay(backend: backend, request: install, phase: "upload")
        defer { _ = try? runLocalReplay(backend: backend, request: install, phase: "cleanup", context: CoreContext(timeout: 35)) }
        guard let remotePayload = staging["files"]?.text else {
            throw CoreError("PROTOCOL_ERROR")
        }
        try backend.transport.upload(payloadFile, to: remotePayload, context: backend.context)
        let result = try runLocalReplay(backend: backend, request: install, phase: "install")
        guard result["verified"]?.boolean == true, let tree = result["installed_manifest"]?.text,
              ApprovedArtifact.hash(tree) else { throw CoreError("VERIFY_FAILED") }
        guard tree == packagedGuestTree else { throw CoreError("VERIFY_FAILED") }
        return ["installed_manifest": .string(tree), "verified": .bool(true)]
    }

    private static func runLocalReplay(backend: SSHEnvironmentBackend, request: [String: JSONValue],
                                       phase: String, context: CoreContext? = nil) throws -> [String: JSONValue] {
        let payload = Data(CoreJSON.encode(.object(request)).utf8).base64EncodedString()
        let code: String
        if phase == "install" {
            let probe = runtimeProbe.components(separatedBy: "try:print(json.dumps(check()))")[0]
            code = SteamRuntime4.evidence + "\n" + probe + "\n" + pipeline
        } else {
            code = SteamRuntime4.evidence + "\n" + pipeline.components(separatedBy: "work=pathlib.Path.home()")[0]
                + "\nlocal_replay_prepare(" + CoreJSON.encode(.string(phase)) + ")"
        }
        let script = "python3 - <<'HD2_FEX_LOCAL'\nimport base64,json\nREQUEST=json.loads(base64.b64decode('" + payload + "'))\n" + code + "\nHD2_FEX_LOCAL\n"
        _ = try backend.hostIdentity()
        let outcome = try backend.transport.run(script, timeout: phase == "install" ? 350 : 30, context: context ?? backend.context)
        guard outcome.status == 0 else {
            let reasons = ["STEAM_RUNTIME_INCOMPATIBLE", "FEX_LOCAL_RUNTIME_MISSING", "FEX_ROOTFS_UNAVAILABLE", "TARGET_CHANGED", "STEAM_RUNNING",
                           "EXTERNAL_DRIFT", "ARTIFACT_HASH", "ARTIFACT_FORMAT", "UNSAFE_PATH", "VERIFY_FAILED",
                           "INSUFFICIENT_SPACE", "COMPONENT_CONFLICT", "TIMEOUT", "FEX_CHANGED", "FEX_TIMEOUT",
                           "FEX_DEPENDENCY_FAILED", "FEX_RUNTIME_FAILED"]
            let code = reasons.first { outcome.stderr.contains($0) } ?? "COMPONENT_INSTALL_FAILED"
            let reason = CoreRedaction.scrub(String(outcome.stderr.split(whereSeparator: \.isNewline).last?.suffix(300) ?? ""))
            throw CoreError(code, ["reason": .string(reason)])
        }
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(outcome.stdout.utf8))
    }

    private static func bundleReplay(backend: SSHEnvironmentBackend, package: RFBundlePackage) throws -> [String: JSONValue] {
        let snapshot = try backend.snapshot()
        guard snapshot.architecture == "aarch64", !snapshot.gameRunning,
              let machineID = snapshot.facts["machine_id"], !machineID.isEmpty else { throw CoreError("TARGET_CHANGED") }
        var request: [String: JSONValue] = ["boot": .string(snapshot.boot),
            "machine": .string(CoreHash.sha256(Data(machineID.utf8))),
            "expected_tree": .string(packagedGuestTree)]
        if let managed = snapshot.facts["fex_managed_emulator"] {
            guard managed.hasSuffix("/HD2FXLauncher/compatibility/FEX-RF/emulator.json"),
                  let tree = snapshot.facts["fex_tree"] ?? snapshot.facts["fex_repair_tree"],
                  ApprovedArtifact.hash(tree) else { throw CoreError("EXTERNAL_DRIFT") }
            request["legacy_tree"] = .string(tree)
        } else if snapshot.facts["fex_source_type"] == "app-managed" {
            guard let tree = snapshot.facts["fex_repair_tree"], ApprovedArtifact.hash(tree) else {
                throw CoreError("EXTERNAL_DRIFT")
            }
            request["legacy_tree"] = .string(tree)
        }
        var result = try deployReplay(backend: backend, snapshot: snapshot, request: request, files: package.files)
        result["package_id"] = .string(package.id)
        result["package_fingerprint"] = .string(package.fingerprint)
        return result
    }

    static func run(_ method: String, backend: SSHEnvironmentBackend, params: [String: JSONValue]) throws -> [String: JSONValue] {
        let mode = String(method.dropFirst("first_run_fex_".count))
        guard ["audit", "build", "install", "recover"].contains(mode) else { throw CoreError("INVALID_ARGUMENT") }
        let snapshot = try backend.snapshot()
        let store = CoreFS.nativeData().appendingPathComponent("fex-reviews", isDirectory: true)
        try CoreFS.ensurePrivateDirectory(store)
        var request: [String: JSONValue] = ["mode": .string(mode), "boot": .string(snapshot.boot)]
        if mode == "build", LaunchService.checkProxyPort(), SSHTransport.localHost(backend.transport.settings.host) {
            request["source_proxy"] = .string("http://192.168.127.254:7890")
        }
        let id: UUID
        if ["install", "recover"].contains(mode) {
            guard let selected = params["receipt_id"]?.text.flatMap(UUID.init(uuidString:)) else { throw CoreError("CONFIRMATION_REQUIRED") }
            id = selected
            let file = store.appendingPathComponent(id.uuidString + ".json")
            guard !FileManager.default.isSymbolicLink(atPath: file.path) else { throw CoreError("UNSAFE_PATH") }
            let data = try Data(contentsOf: file)
            guard data.count < 1_048_576 else { throw CoreError("OUTPUT_LIMIT") }
            let saved = try JSONDecoder().decode([String: JSONValue].self, from: data)
            guard saved["target"]?.text == snapshot.target, saved["boot"]?.text == snapshot.boot,
                  (mode == "recover" || saved["revision"]?.text == snapshot.revision) else { throw CoreError("TARGET_CHANGED") }
            if mode == "install" {
                guard saved["audit"]?.object["ready"]?.boolean == true else { throw CoreError("ARTIFACT_UNAPPROVED") }
                request["audit"] = saved["audit"]
            }
            request["ticket"] = .string(id.uuidString)
        } else { id = UUID() }
        guard let patchURL = Bundle.main.url(forResource: "fex-rf-reviewed", withExtension: "patch") else { throw CoreError("ARTIFACT_UNAPPROVED") }
        let patch = try Data(contentsOf: patchURL)
        guard CoreHash.sha256(patch) == "85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926" else { throw CoreError("SOURCE_MISMATCH") }
        request["patch"] = .string(patch.base64EncodedString())
        let payload = try JSONEncoder().encode(request).base64EncodedString()
        let source = FEXWorkflow.pipeline
        let script = "python3 - <<'HD2_FEX_PIPELINE'\nimport base64,json\nREQUEST=json.loads(base64.b64decode('" + payload + "'))\n" + source + "\nHD2_FEX_PIPELINE\n"
        _ = try backend.hostIdentity()
        if mode == "install" {
            let file = store.appendingPathComponent(id.uuidString + ".json")
            var saved = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: file))
            saved["attempted"] = .bool(true)
            try CoreFS.atomicWrite(try JSONEncoder().encode(saved), to: file)
        }
        let result = try backend.transport.run(script, timeout: mode == "build" ? 6000 : 300, context: backend.context)
        guard result.status == 0 else {
            let known = ["STEAM_RUNNING", "TARGET_CHANGED", "UNSAFE_PATH", "INSUFFICIENT_SPACE", "SOURCE_MISMATCH", "ARTIFACT_UNAPPROVED", "EXTERNAL_DRIFT", "VERIFY_FAILED", "BUILD_DEPENDENCY_MISSING", "BUILD_CANDIDATE_EXISTS", "COMPONENT_CONFLICT"]
            throw CoreError(known.first { result.stderr.contains($0) } ?? "COMPONENT_INSTALL_FAILED", ["summary": .string(CoreRedaction.scrub(String(result.stderr.suffix(4096)), secrets: ["password", "sudo_password", "passphrase"].compactMap { params[$0]?.text }))])
        }
        guard let data = result.stdout.data(using: .utf8), data.count < 1_048_576,
              var value = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw CoreError("PROTOCOL_ERROR") }
        if let log = value["build_log"]?.text { value["build_log"] = .string(CoreRedaction.scrub(log, secrets: ["password", "sudo_password", "passphrase"].compactMap { params[$0]?.text })) }
        _ = try backend.hostIdentity()
        let records = try FileManager.default.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)
        guard records.count <= 1024 else { throw CoreError("OUTPUT_LIMIT") }
        var restore: String?
        var trusted = mode == "build"
        for file in records where file.pathExtension == "json" && !FileManager.default.isSymbolicLink(atPath: file.path) {
            guard let bytes = try? Data(contentsOf: file), bytes.count < 1_048_576,
                  let old = try? JSONDecoder().decode([String: JSONValue].self, from: bytes),
                  old["target"]?.text == snapshot.target, old["boot"]?.text == snapshot.boot else { continue }
            if old["built"]?.boolean == true, old["audit"]?.object["candidate"] == value["candidate"],
               old["audit"]?.object["executable_sha256"] == value["executable_sha256"] { trusted = true }
            if old["attempted"]?.boolean == true, (value["recoverable"]?.array ?? []).contains(.string(file.deletingPathExtension().lastPathComponent)) { restore = file.deletingPathExtension().lastPathComponent }
        }
        if !trusted { value["ready"] = .bool(false) }
        if ["audit", "build"].contains(mode) {
            let record: [String: JSONValue] = ["target": .string(snapshot.target), "boot": .string(snapshot.boot), "revision": .string(snapshot.revision), "audit": .object(value), "built": .bool(trusted), "fx_path": .string(snapshot.facts["fx_path"] ?? ""), "machine_id": .string(snapshot.facts["machine_id"] ?? ""), "fx_executable_sha256": .string(snapshot.facts["fx_executable_sha256"] ?? ""), "ssh_connection": .string(snapshot.facts["ssh_connection"] ?? "")]
            try CoreFS.atomicWrite(try JSONEncoder().encode(record), to: store.appendingPathComponent(id.uuidString + ".json"))
        }
        if ["install", "recover"].contains(mode) {
            let file = store.appendingPathComponent(id.uuidString + ".json")
            var saved = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: file))
            saved["installation"] = mode == "install" ? .object(value) : .null
            try CoreFS.atomicWrite(try JSONEncoder().encode(saved), to: file)
            restore = mode == "install" ? id.uuidString : nil
        }
        return ["fex_audit": .object(value), "fex_ticket": .string(id.uuidString), "fex_restore_ticket": restore.map(JSONValue.string) ?? .null, "ssh_password_verified": .bool(backend.transport.passwordWasSent), "guest_boot": .string(snapshot.boot)]
    }
}

extension FEXWorkflow {
    /// First run uses the same identity-bound transaction for the bundle and its signed fallback.
    static func repair(backend: SSHEnvironmentBackend,
                       emit: (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        let before = try backend.snapshot()
        let reason = before.facts["fex_reason"] ?? "FEX_RUNTIME_FAILED"
        let repairable = ["FEX_MISSING", "FEX_NOT_EXECUTABLE", "FEX_ARCHITECTURE",
                          "FEX_INTEGRATION_MISSING", "FEX_CHANGED", "FEX_INTEGRITY_FAILED",
                          "FEX_RUNTIME_FAILED", "FEX_DEPENDENCY_FAILED", "FEX_LOCAL_RUNTIME_MISSING",
                          "FEX_KNOWN_LAUNCH_INCOMPATIBILITY", "FEX_PROTON_INTEGRATED_UNVERIFIED",
                    "STEAM_RUNTIME_INCOMPATIBLE"]
        guard repairable.contains(reason) else {
            throw CoreError(reason, ["diagnostic_reason": .string(before.facts["fex_diagnostic_reason"] ?? reason)])
        }

        emit("INFO", "FX runtime repair preflight", ["deployment_state": .string("Checking"),
             "component": .string("fex"), "status": .string("running"),
             "source": .string("app-bundle")])
        func runtimeProgress(_ phase: String) {
            emit("INFO", "Steam Runtime setup", ["kind": .string("steam_runtime_stage"), "runtime_phase": .string(phase)])
        }
        try SteamRuntime4.ensure(backend, snapshot: before, progress: runtimeProgress)
        if reason == SteamRuntime4.missing || reason == SteamRuntime4.unverified {
            let after = try backend.snapshot()
            try requireCompatible(after)
            runtimeProgress("ready")
            return ["repair_attempted": .bool(true), "repair_source": .string("steam"),
                    "verification": .object(["runtime_build": .string(after.facts["steam_runtime_build"] ?? "unknown"),
                                             "runtime_version": .string(after.facts["steam_runtime_version"] ?? "unknown")])]
        }
        let (package, source): (RFBundlePackage, String)
        do {
            (package, source) = try bundledPackage(context: backend.context)
        } catch is NativeUpdateFailure {
            throw CoreError("ARTIFACT_HASH", ["component": .string("fex")])
        }
        emit("INFO", "FX runtime package verified", ["deployment_state": .string("Deploying"),
             "component": .string("fex"), "status": .string("running"), "source": .string(source)])
        var result = try bundleReplay(backend: backend, package: package)
        let after = try backend.snapshot()
        try requireCompatible(after)
        runtimeProgress("ready")
        emit("INFO", "FX runtime repair verified", ["deployment_state": .string("Verifying"),
             "component": .string("fex"), "status": .string("done"), "source": .string(source)])
        result["repair_attempted"] = .bool(true)
        result["repair_source"] = .string(source)
        result["resource_source"] = .string(source)
        result["repair_reason"] = .string(reason)
        result["verification"] = .object([
            "status": .string(after.facts["fex_status"] ?? "unknown"),
            "runtime": .string(after.facts["fex_runtime"] ?? "unknown"),
            "executable_sha256": .string(after.facts["fex_executable_sha256"] ?? ""),
            "tree_sha256": .string(after.facts["fex_tree"] ?? "")
        ])
        return result
    }

    static let pipeline = #"""
# Executed only by the bundled Native Core over an identity-verified Guest SSH session.
import os,sys,json,hashlib,pathlib,subprocess,shutil,uuid,stat,time,fcntl,signal,shlex,urllib.parse
os.umask(0o077)
BASE='87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8'
PATCH='85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926'
EXPECTED='ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf'
def fail(code): raise RuntimeError(code)
def digest(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def elf_arm64(p):
 with p.open("rb") as f:h=f.read(64)
 return len(h)==64 and h[:6]==b"\x7fELF\x02\x01" and int.from_bytes(h[18:20],"little")==183
def safe(p):
 for x in [p,*p.parents]:
  if x.is_symlink():fail('UNSAFE_PATH')
def identity():
 if pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=REQUEST['boot']:fail('TARGET_CHANGED')
def save_record(path,value):
 safe(path)
 temp=path.with_name(path.name+'.tmp-'+str(uuid.uuid4()))
 with temp.open('x') as f:
  json.dump(value,f,sort_keys=True);f.flush();os.fsync(f.fileno())
 temp.rename(path)
 fd=os.open(path.parent,os.O_DIRECTORY);os.fsync(fd);os.close(fd)
def guest_proxy():
 values=[]
 if REQUEST.get('source_proxy'):values.append(REQUEST['source_proxy'])
 p=pathlib.Path('/run/user')/str(os.getuid())/'systemd/user/steam.service.d/90-hd2-proxy.conf'
 safe(p)
 if p.is_file() and p.stat().st_size<=16384:
  for line in p.read_text().splitlines():
   if not line.strip().startswith('Environment='):continue
   for item in shlex.split(line.strip()[len('Environment='):]):
    name,sep,value=item.partition('=')
    if name.lower() in ['http_proxy','https_proxy'] and sep:values.append(value)
 for value in values:
  u=urllib.parse.urlsplit(value)
  if u.scheme in ['http','https'] and u.hostname=='192.168.127.254' and not u.username and not u.password and u.port and not u.path.strip('/') and not u.query and not u.fragment:return value
 return None
def idle():
 identity()
 for n in ['steam','reaper','helldivers2.exe']:
  if subprocess.run(['pgrep','-x',n],stdout=subprocess.DEVNULL).returncode!=1:fail('STEAM_RUNNING')
def inventory(root, omit_var=False):
 safe(root)
 if not root.is_dir():return None
 result={};total=0
 for d,dirs,files in os.walk(root,followlinks=False):
  if omit_var and pathlib.Path(d)==root:
   if 'var' in dirs:dirs.remove('var')
   if 'var' in files:fail('UNSAFE_PATH')
  for n in dirs+files:
   p=pathlib.Path(d)/n;r=str(p.relative_to(root));s=p.lstat()
   if len(result)>=20000 or s.st_mode&0o7000:fail('ARTIFACT_FORMAT')
   if stat.S_ISLNK(s.st_mode):
    link=os.readlink(p)
    if pathlib.Path(link).is_absolute() or not p.resolve().is_relative_to(root.resolve()):fail('UNSAFE_PATH')
    result[r]=['link',link]
   elif stat.S_ISREG(s.st_mode):
    total+=s.st_size
    if total>2*1024**3:fail('ARTIFACT_FORMAT')
    # Runtime creates content-identical hardlinks in var/ for container copies.
    # Only its read-only inventory permits these; FEX transactions remain strict.
    if s.st_size>256*1024*1024 or (s.st_nlink!=1 and not omit_var):fail('ARTIFACT_FORMAT')
    result[r]=['file',digest(p),s.st_mode&0o777]
   elif stat.S_ISDIR(s.st_mode):result[r]=['dir']
   else:fail('ARTIFACT_FORMAT')
 return result
def observed_managed_executable(supervisor, executable):
 expected=executable.stat()
 processes={}
 matches=[]
 for entry in pathlib.Path('/proc').iterdir():
  if not entry.name.isdigit():continue
  try:
   stat_fields=(entry/'stat').read_text().rsplit(')',1)[1].split()
   pid=int(entry.name)
   processes[pid]=(int(stat_fields[1]),int(stat_fields[2]))
   actual=(entry/'exe').stat()
   if (actual.st_dev,actual.st_ino)==(expected.st_dev,expected.st_ino):matches.append(pid)
  except (OSError,ValueError,IndexError):continue
 for pid in matches:
  visited=set()
  while pid in processes and pid not in visited:
   if pid==supervisor or processes[pid][1]==supervisor:return True
   visited.add(pid);pid=processes[pid][0]
 return False
def fingerprint(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def replay_root():
 return pathlib.Path.home()/'.local/share/HD2FXLauncher/compatibility/FEX-RF'
def replay_work():
 return pathlib.Path.home()/'.local/share/HD2FXLauncher/fex-rf-v1'
def local_replay_preflight(installed):
 identity()
 machine=pathlib.Path('/etc/machine-id').read_text().strip()
 if hashlib.sha256(machine.encode()).hexdigest()!=REQUEST['machine']:fail('TARGET_CHANGED')
 safe(installed)
 if os.path.lexists(installed):
  legacy=REQUEST.get('legacy_tree')
  if not legacy or fingerprint(inventory(installed))!=legacy:fail('EXTERNAL_DRIFT')
 provider=pathlib.Path('/usr/share/guestos/fex-mesa')
 if not (provider/'graphics_provider.json').is_file() or not (provider/'usr/lib/ld-linux-x86-64.so.2').is_file():fail('FEX_ROOTFS_UNAVAILABLE')
 runtime=pathlib.Path(REQUEST['runtime_path'])
 safe(runtime)
 if not runtime.is_absolute() or runtime.name!='SteamLinuxRuntime_4' or runtime.parent.name!='common' or runtime.parent.parent.name!='steamapps':fail('UNSAFE_PATH')
 if not runtime_evidence(runtime)[1]:fail('STEAM_RUNTIME_INCOMPATIBLE')
 runtime_smoke(runtime)
 return runtime
def local_replay_prepare(phase):
 installed=replay_root()
 if phase=='preflight':
  local_replay_preflight(installed);print('{}');return
 identity()
 machine=pathlib.Path('/etc/machine-id').read_text().strip()
 if hashlib.sha256(machine.encode()).hexdigest()!=REQUEST['machine']:fail('TARGET_CHANGED')
 store=replay_work();safe(store)
 incoming=store/('incoming-'+str(uuid.UUID(REQUEST['ticket'])));safe(incoming)
 if phase=='upload':
  store.mkdir(parents=True,exist_ok=True,mode=0o700)
  if store.stat().st_uid!=os.getuid() or store.stat().st_mode&0o022:fail('UNSAFE_PATH')
  incoming.mkdir(mode=0o700)
  print(json.dumps({'files':str(incoming/'files.json')}))
 elif phase=='cleanup':
  if incoming.exists():
   (incoming/'files.json').unlink(missing_ok=True)
   incoming.rmdir()
  print('{}')
 else:fail('INVALID_ARGUMENT')
def runtime_smoke(runtime):
 tool=runtime/'pressure-vessel-arm64/bin/pressure-vessel-wrap';safe(tool)
 env=dict(os.environ)
 for key in ['LD_LIBRARY_PATH','LD_PRELOAD']:env.pop(key,None)
 result=subprocess.run([str(tool),'--version'],env=env,capture_output=True,timeout=15)
 if result.returncode!=0:fail('STEAM_RUNTIME_INCOMPATIBLE')
def stop_replay_steam():
 identity()
 for name in ['reaper','helldivers2.exe']:
  if subprocess.run(['pgrep','-x',name],stdout=subprocess.DEVNULL).returncode!=1:fail('STEAM_RUNNING')
 observed=subprocess.run(['pgrep','-x','steam'],capture_output=True,text=True)
 if observed.returncode==1:return False
 unit=subprocess.run(['systemctl','--user','show','-p','MainPID','--value','steam.service'],capture_output=True,text=True,timeout=8)
 if observed.returncode!=0 or unit.returncode!=0 or observed.stdout.split()!=[unit.stdout.strip()]:fail('STEAM_RUNNING')
 subprocess.run(['systemctl','--user','stop','steam.service'],check=True,timeout=30,stdout=subprocess.DEVNULL)
 return True
work=pathlib.Path.home()/'.local/share/HD2FXLauncher/fex-rf-v1';safe(work)
work.mkdir(parents=True,exist_ok=True,mode=0o700)
if work.stat().st_uid!=os.getuid() or work.stat().st_mode&0o022:fail('UNSAFE_PATH')
lock=work/'lock';safe(lock)
lockfd=os.open(lock,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
fcntl.flock(lockfd,fcntl.LOCK_EX|fcntl.LOCK_NB)
restart_steam=False
try:
 identity();src=work/'source';stage=work/'runtime';installed=replay_root()
 mode=REQUEST['mode']
 if mode=='local_replay':
  def interrupted(signum,frame):fail('TIMEOUT')
  for signum in [signal.SIGTERM,signal.SIGHUP,signal.SIGINT]:signal.signal(signum,interrupted)
 if mode=='build':
  for c in ['git','cmake','ninja','clang','clang++','ld.lld','patch']:
   if not shutil.which(c):fail('BUILD_DEPENDENCY_MISSING')
  if shutil.disk_usage(work).free<12*1024**3:fail('INSUFFICIENT_SPACE')
  statefile=work/'source-state.json';safe(statefile)
  state=json.loads(statefile.read_text()) if statefile.exists() else None
  if src.exists() and (not state or state.get('source')!=BASE or state.get('patch')!=PATCH):fail('BUILD_CANDIDATE_EXISTS')
  if not state:save_record(statefile,{'source':BASE,'patch':PATCH,'phase':'fetching'})
  log=work/'build.log'
  env=dict(os.environ,GIT_TERMINAL_PROMPT='0')
  active=None
  def stop(signum,frame):
   if active is not None:
    try:os.killpg(active.pid,signal.SIGTERM)
    except ProcessLookupError:pass
   fail('CANCELLED')
  for sig in [signal.SIGTERM,signal.SIGHUP,signal.SIGINT]:signal.signal(sig,stop)
  def run(args,seconds=180,cwd=None):
   global active
   identity()
   if args[0]=='git':
    proxy=guest_proxy()
    if proxy:args=args[:1]+['-c','http.proxy='+proxy]+args[1:]
   if args[0]=='git':args=args[:1]+['-c','core.hooksPath=/dev/null','-c','http.version=HTTP/1.1','-c','http.lowSpeedLimit=1024','-c','http.lowSpeedTime=30']+args[1:]
   with log.open('ab') as f:
    active=subprocess.Popen(args,cwd=cwd,env=env,stdin=subprocess.DEVNULL,stdout=f,stderr=f,start_new_session=True)
    try:
     code=active.wait(timeout=seconds)
     if code:raise subprocess.CalledProcessError(code,args)
    except BaseException:
     if active.poll() is None:
      os.killpg(active.pid,signal.SIGTERM)
      try:active.wait(timeout=5)
      except subprocess.TimeoutExpired:os.killpg(active.pid,signal.SIGKILL);active.wait()
     raise
    finally:active=None
  if not src.exists():
   run(['git','init',str(src)])
   run(['git','-C',str(src),'remote','add','origin','https://github.com/StonkGuy/FEX.git'])
  safe(src)
  if subprocess.check_output(['git','-C',str(src),'remote','get-url','origin'],text=True).strip()!='https://github.com/StonkGuy/FEX.git':fail('SOURCE_MISMATCH')
  if not state or state.get('phase')=='fetching':run(['git','-C',str(src),'-c','protocol.file.allow=never','fetch','--depth','1','origin',BASE],600)
  if not state or state.get('phase')=='fetching':run(['git','-C',str(src),'checkout','--detach','FETCH_HEAD'])
  actual=subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()
  if actual!=BASE:fail('SOURCE_MISMATCH')
  # All submodule object IDs are anchored in the pinned source tree. No local/ext protocol.
  modules=subprocess.check_output(['git','-C',str(src),'config','--file','.gitmodules','--get-regexp',r'submodule\..*\.url'],text=True)
  for line in modules.splitlines():
   url=line.split(None,1)[1]
   if not url.startswith('https://github.com/') or '..' in url or any(c in url for c in ['\n','?','#']):fail('SOURCE_MISMATCH')
  run(['git','-C',str(src),'-c','protocol.file.allow=never','-c','protocol.ext.allow=never','submodule','update','--init','--depth','1'],1200)
  patch=work/'reviewed.patch';import base64
  patch.write_bytes(base64.b64decode(REQUEST['patch']))
  if digest(patch)!=PATCH:fail('SOURCE_MISMATCH')
  if not state or state.get('phase')=='fetching':
   run(['git','-C',str(src),'apply','--check',str(patch)])
   run(['git','-C',str(src),'apply',str(patch)])
  diff=subprocess.check_output(['git','-C',str(src),'diff','--no-ext-diff','--binary'])
  diffhash=hashlib.sha256(diff).hexdigest()
  if state and state.get('phase')=='patched' and state.get('diff')!=diffhash:fail('SOURCE_MISMATCH')
  save_record(statefile,{'source':BASE,'patch':PATCH,'phase':'patched','diff':diffhash})
  if stage.exists():
   safe(stage);stage.rename(work/('retained-runtime-'+str(uuid.uuid4())))
  run(['cmake','-S',str(src),'-B',str(work/'build'),'-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_C_COMPILER=clang','-DCMAKE_CXX_COMPILER=clang++','-DBUILD_STEAM_SUPPORT=ON','-DBUILD_TESTING=OFF','-DBUILD_THUNKS=OFF','-DBUILD_FEXCONFIG=OFF','-DENABLE_LTO=OFF','-DENABLE_ASSERTIONS=OFF','-DCMAKE_CXX_SCAN_FOR_MODULES=OFF','-DCMAKE_INSTALL_PREFIX=/usr'],300)
  run(['cmake','--build',str(work/'build'),'-j',str(min(4,os.cpu_count() or 1))],3600)
  env['DESTDIR']=str(stage)
  run(['cmake','--install',str(work/'build'),'--component','Runtime'],180)
  if hashlib.sha256(subprocess.check_output(['git','-C',str(src),'diff','--no-ext-diff','--binary'])).hexdigest()!=diffhash:fail('SOURCE_MISMATCH')
  notices=stage/'usr/share/licenses/hd2-fex';notices.mkdir(parents=True,exist_ok=True)
  license=src/'LICENSE';safe(license)
  if not license.is_file():fail('SOURCE_MISMATCH')
  shutil.copy2(license,notices/'LICENSE')
  (notices/'SOURCE.txt').write_text('https://github.com/StonkGuy/FEX/tree/'+BASE+'\nPatch SHA-256: '+PATCH+'\n')
  tools={}
  for command in ['clang','clang++','cmake','ninja']:
   tools[command]=subprocess.check_output([command,'--version'],text=True,timeout=5).splitlines()[0][:512]
  metadata={'tools':tools,'source_diff_sha256':diffhash,'jobs':min(4,os.cpu_count() or 1)}
  (work/'provenance.json').write_text(json.dumps({'source':BASE,'patch':PATCH,'runtime':inventory(stage),'build':metadata},sort_keys=True))
 def audit():
  tree=inventory(stage);before=inventory(installed)
  provenance=work/'provenance.json'
  verified=False;build={}
  if provenance.is_file() and not provenance.is_symlink():
   p=json.loads(provenance.read_text());verified=p.get('source')==BASE and p.get('patch')==PATCH and p.get('runtime')==tree
   if verified:build=p.get('build',{})
  exe=stage/'usr/bin/FEX'
  actual=digest(exe) if exe.is_file() and not exe.is_symlink() else ''
  # Review the pinned build provenance, complete inventory and ELF architecture.
  ready=verified and bool(actual) and bool(tree) and bool(exe.stat().st_mode&0o111) and elf_arm64(exe)
  tail=''
  log=work/'build.log';safe(log)
  if log.is_file():
   with log.open('rb') as f:f.seek(max(0,log.stat().st_size-4096));tail=f.read(4096).decode(errors='replace')
  recoverable=[]
  for file in list(work.glob('*.json'))[:1024]:
   try:uuid.UUID(file.stem)
   except ValueError:continue
   safe(file)
   if file.stat().st_size>16384:fail('ARTIFACT_FORMAT')
   record=json.loads(file.read_text())
   if record.get('ticket')==file.stem and record.get('boot')==REQUEST['boot'] and record.get('state') in ['prepared','completed']:recoverable.append(file.stem)
  return {'build_metadata':build,'inventory':tree,'recoverable':sorted(recoverable),'build_log':tail,'source':BASE,'patch':PATCH,'executable_sha256':actual,'expected_sha256':EXPECTED,'ready':ready,'candidate':fingerprint(tree),'original':fingerprint(before),'files':len(tree or {}),'installed':before is not None}
 if mode in ['audit','build']:print(json.dumps(audit()))
 elif mode in ['install','local_replay']:
  if mode=='local_replay':
   rt=local_replay_preflight(installed)
   installed.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
   safe(installed.parent)
   stage=work/('local-runtime-'+str(uuid.UUID(REQUEST['ticket'])))
   stage.mkdir(mode=0o700)
   import base64
   if 'files_sha256' in REQUEST:
    packet=work/('incoming-'+str(uuid.UUID(REQUEST['ticket'])))/'files.json';safe(packet)
    metadata=packet.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink!=1 or metadata.st_size>48*1024**2:fail('ARTIFACT_FORMAT')
    payload=packet.read_bytes()
    if hashlib.sha256(payload).hexdigest()!=REQUEST['files_sha256']:fail('ARTIFACT_HASH')
    REQUEST['files']=json.loads(payload)
   for item in REQUEST['files']:
    relative=pathlib.Path(item['path'])
    if relative.is_absolute() or '..' in relative.parts:fail('UNSAFE_PATH')
    dst=stage/relative
    dst.parent.mkdir(parents=True,exist_ok=True)
    data=base64.b64decode(item['data'],validate=True)
    if hashlib.sha256(data).hexdigest()!=item['sha256']:fail('ARTIFACT_HASH')
    with dst.open('xb') as f:f.write(data)
    dst.chmod(item['mode'])
   registration=stage/'emulator.json'
   config=json.loads(registration.read_text())
   container_environment=config['emulator_v0']['container_environment']
   if container_environment.get('FEX_ROOTFS')!='':fail('ARTIFACT_UNAPPROVED')
   prior=inventory(stage)
   if fingerprint(prior)!=REQUEST['expected_tree']:fail('ARTIFACT_HASH')
   if REQUEST.get('legacy_tree'):
    legacy_config=json.loads(registration.read_text())
    legacy_config['emulator_v0']['container_environment']['FEX_ROOTFS']='/'
    legacy=dict(prior)
    legacy['emulator.json']=['file',hashlib.sha256((json.dumps(legacy_config,indent=2)+'\n').encode()).hexdigest(),prior['emulator.json'][2]]
    if fingerprint(legacy)!=REQUEST['legacy_tree']:
     observed=inventory(installed)
     if (fingerprint(observed)!=REQUEST['legacy_tree']
         or any(key not in prior or prior[key][0]!=value[0] for key,value in observed.items())):fail('EXTERNAL_DRIFT')
     approved=fingerprint(prior)
     receipts=list(work.glob('*.json'))
     if len(receipts)>1024:fail('EXTERNAL_DRIFT')
     def owned_receipt(path):
      try:
       uuid.UUID(path.stem)
       meta=path.lstat()
       if not stat.S_ISREG(meta.st_mode) or meta.st_nlink!=1 or meta.st_uid!=os.getuid() or meta.st_size>65536:return False
       record=json.loads(path.read_text())
       return record.get('ticket')==path.stem and record.get('state')=='completed' and record.get('installed')==approved
      except (ValueError,OSError,AttributeError):return False
     if not any(owned_receipt(path) for path in receipts):fail('EXTERNAL_DRIFT')
   restart_steam=stop_replay_steam()
   rt=local_replay_preflight(installed)
  idle();current=audit()
  if mode=='install' and (not current['ready'] or any(current[k]!=REQUEST['audit'].get(k) for k in ['source','patch','executable_sha256','expected_sha256','candidate','original','files','installed'])):fail('ARTIFACT_UNAPPROVED')
  if mode=='local_replay':
   if current['executable_sha256']!=EXPECTED:fail('ARTIFACT_UNAPPROVED')
   if current['original']!=REQUEST.get('legacy_tree',fingerprint(None)):fail('EXTERNAL_DRIFT')
  token=REQUEST['ticket'];uuid.UUID(token)
  backup=installed.with_name(installed.name+'.hd2-backup-'+token)
  prepared=installed.with_name(installed.name+'.hd2-stage-'+token)
  if os.path.lexists(backup) or os.path.lexists(prepared):fail('EXTERNAL_DRIFT')
  safe(installed.parent);installed.parent.mkdir(parents=True,exist_ok=True)
  # A bundled/local replay is the complete reviewed standalone tree. Keep the
  # prior App-owned tree as the rollback backup, but do not carry unknown or
  # damaged files into the prepared replacement. Source-build installs retain
  # their historical overlay behavior and Steam metadata.
  if mode=='local_replay':prepared.mkdir(mode=0o700)
  elif installed.exists():shutil.copytree(installed,prepared,symlinks=True)
  else:prepared.mkdir(mode=0o700)
  for d,dirs,files in os.walk(stage,followlinks=False):
   for n in dirs+files:
    p=pathlib.Path(d)/n;dest=prepared/p.relative_to(stage)
    safe(dest.parent)
    if dest.is_symlink():fail('UNSAFE_PATH')
    if p.is_symlink():
     if os.path.lexists(dest):fail('COMPONENT_CONFLICT')
     dest.symlink_to(os.readlink(p))
    elif p.is_dir():dest.mkdir(parents=True,exist_ok=True)
    else:shutil.copy2(p,dest)
  expected=inventory(prepared);idle()
  if audit()!=current:fail('EXTERNAL_DRIFT')
  receipt={'ticket':token,'original':current['original'],'installed':fingerprint(expected),'had_original':current['installed'],'boot':REQUEST['boot'],'state':'prepared'}
  record=work/(token+'.json');save_record(record,receipt)
  moved_original=False;activated=False
  try:
   if installed.exists():
    installed.rename(backup);moved_original=True
   prepared.rename(installed);activated=True
   if inventory(installed)!=expected:fail('VERIFY_FAILED')
   if mode=='local_replay':
    EXPECTED_BOOT=REQUEST['boot'];EXPECTED_TREE=fingerprint(expected);RUNTIME_PATH=str(rt)
    root=installed;exe=root/'usr/bin/FEX';managed=True
    runtime=check()
    if not runtime.get('runtime'):fail(runtime.get('reason','FEX_RUNTIME_FAILED'))
   receipt['state']='completed';save_record(record,receipt)
  except Exception:
   idle()
   if moved_original and fingerprint(inventory(backup))!=receipt['original']:fail('EXTERNAL_DRIFT')
   if activated:
    if inventory(installed)!=expected or os.path.lexists(prepared):fail('EXTERNAL_DRIFT')
    installed.rename(prepared)
   if moved_original:
    if os.path.lexists(installed):fail('EXTERNAL_DRIFT')
    backup.rename(installed)
   if fingerprint(inventory(installed))!=receipt['original']:fail('VERIFY_FAILED')
   receipt['state']='recovered';save_record(record,receipt)
   raise
  print(json.dumps({'ticket':token,'verified':True,'backup':backup.name,'installed_manifest':fingerprint(expected)}))
 elif mode=='recover':
  idle();token=REQUEST['ticket'];uuid.UUID(token);record=work/(token+'.json');safe(record)
  r=json.loads(record.read_text());backup=installed.with_name(installed.name+'.hd2-backup-'+token)
  if r['boot']!=REQUEST['boot'] or r['ticket']!=token:fail('TARGET_CHANGED')
  if 'runtime_tree' in r:fail('EXTERNAL_DRIFT')
  current=fingerprint(inventory(installed))
  if current==r['original']:
   r['state']='recovered';save_record(record,r);print(json.dumps({'ticket':token,'recovered':True}));sys.exit(0)
  if current!=r['installed'] and installed.exists():fail('EXTERNAL_DRIFT')
  if r['had_original'] and fingerprint(inventory(backup))!=r['original']:fail('EXTERNAL_DRIFT')
  retained=installed.with_name(installed.name+'.hd2-recovered-'+token)
  if os.path.lexists(retained):
   if installed.exists() or fingerprint(inventory(retained))!=r['installed']:fail('EXTERNAL_DRIFT')
  elif installed.exists():installed.rename(retained)
  if r['had_original']:backup.rename(installed)
  if fingerprint(inventory(installed))!=r['original']:fail('VERIFY_FAILED')
  r['state']='recovered';save_record(record,r);print(json.dumps({'ticket':token,'recovered':True}))
 else:fail('INVALID_ARGUMENT')
finally:
 try:
  if restart_steam:
   identity()
   subprocess.run(['systemctl','--user','start','steam.service'],check=True,timeout=30,stdout=subprocess.DEVNULL)
 finally:os.close(lockfd)

"""#
}
