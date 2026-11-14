"""Exercise the real installer with isolated signed macOS AppKit bundles."""
import base64, hashlib, json, os, plistlib, shutil, signal, subprocess, tempfile, time
from pathlib import Path
repo = Path(__file__).resolve().parents[2]
root = Path(tempfile.mkdtemp(prefix='hd2-helper-acceptance-', dir='/private/tmp'))
print(root, flush=True)
def run(*args, **kw): return subprocess.check_output([str(a) for a in args], **kw)
cache = root / 'modules'
def swift(src, output, *more):
    run('xcrun','swiftc','-module-cache-path',cache,src,*more,'-o',output)
signer = root/'signer'
swift(repo/'native-app/script/update_signing.swift', signer)
key=root/'isolated.key'
public=run(signer,'generate',key).decode().strip()
helper=root/'HD2UpdateInstaller'
swift(repo/'native-app/UpdateHelper/UpdateInstaller.swift', helper,
      repo/'native-app/Services/UpdateReleaseService.swift',
      repo/'native-app/UpdateHelper/ArchivePathPolicy.swift',
      repo/'native-app/UpdateHelper/UpdateZIPPreflight.swift')
src = root/'fixture.swift'
src.write_text('''
import AppKit
final class Delegate: NSObject, NSApplicationDelegate {
    var helper: Process?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--confirm-update-startup" {
            let failure = Bundle.main.object(forInfoDictionaryKey: "FixtureFailure") as? String
            if failure == "timeout" { return }
            if failure == "crash" { exit(42) }
            FileHandle.standardOutput.write(Data("HD2_UPDATE_READY \\(args[2])\\n".utf8))
            if failure == "receipt-crash" { exit(43) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { NSApp.terminate(nil) }
        } else if args.count == 2 && args[1] == "--recover-fixture" {
            let bundle = Bundle.main.bundleURL
            let token = UUID().uuidString
            let process = Process()
            process.executableURL = bundle.appendingPathComponent("Contents/MacOS/HD2UpdateInstaller")
            process.arguments = ["--recover", String(getpid()), token]
            process.standardError = FileHandle.standardError
            do { try process.run() } catch { exit(20) }
            helper = process
            let ready = bundle.deletingLastPathComponent().appendingPathComponent(".HD2FXNative-update/recover-" + token)
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if FileManager.default.fileExists(atPath: ready.path) || !process.isRunning {
                    timer.invalidate()
                    NSApp.terminate(nil)
                }
            }
        } else if args.count == 2 {
            let process = Process()
            process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/HD2UpdateInstaller")
            process.arguments = [args[1], String(ProcessInfo.processInfo.processIdentifier)]
            process.standardError = FileHandle.standardError
            process.terminationHandler = { child in
                if child.terminationStatus != 0 { exit(19) }
            }
            do {
                try process.run()
                helper = process
                try String(process.processIdentifier).write(toFile: args[1] + "/helper-pid", atomically: true, encoding: .utf8)
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    if FileManager.default.fileExists(atPath: args[1] + "/prepared") {
                        timer.invalidate()
                        NSApp.terminate(nil)
                    }
                }
            } catch { exit(18) }
        }
    }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
''')
binary=root/'fixture'
swift(src,binary)
def app(path, version, build, failure):
    files=path/'Contents/MacOS'
    files.mkdir(parents=True)
    shutil.copy2(binary, files/'HD2FXNative')
    shutil.copy2(helper, files/'HD2UpdateInstaller')
    (path/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='com.lsjop.helldivers2fx.native.phase1',
        CFBundleExecutable='HD2FXNative', CFBundlePackageType='APPL',
        CFBundleVersion=str(build), CFBundleShortVersionString=version,
        SUPublicEDKey=public, FixtureFailure=failure)))
    run('codesign','--force','--deep','--sign','-',path,stderr=subprocess.STDOUT)
for mode in ('success', 'crash', 'receipt-crash', 'timeout'):
    location=root/mode
    installed=location/'Installed Launcher.app'
    app(installed,'1.0.1',1,'success')
    package=location/'package/HD2FXNative.app'
    app(package,'1.0.2',2,mode)
    request=location/'request';request.mkdir(mode=0o700)
    archive=request/'archive.zip'
    subprocess.run(['/usr/bin/zip','-qry',str(archive),package.name],cwd=package.parent,check=True)
    manifest=request/'manifest.json'
    manifest.write_text(json.dumps(dict(schema=2,bundleID='com.lsjop.helldivers2fx.native.phase1',
        version='1.0.2',build=2,channel='stable',platform='macOS',architecture='arm64',
        minimumSystemVersion='14.0',archive='HD2FXNative-v1.0.2-arm64.zip',
        length=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
        archiveEdSignature=run(signer,'sign',key,archive).decode().strip())))
    (request/'manifest.sig').write_bytes(base64.b64decode(run(signer,'sign',key,manifest).strip()))
    stderr=location/'stderr'
    with stderr.open('wb') as error:
        old=subprocess.Popen([installed/'Contents/MacOS/HD2FXNative',str(request)],stderr=error)
        try:
            for i in range(400):
                logs=list(location.glob('.HD2FXNative-update-*/journal.log'))
                if logs: break
                if old.poll() not in (None,0): raise RuntimeError(stderr.read_text())
                time.sleep(.1)
            else: raise RuntimeError('No finalized journal: '+stderr.read_text())
        finally:
            if old.poll() is None: old.terminate()
            old.wait(timeout=5)
    print(mode, logs[0].read_text(),flush=True)
    assert plistlib.loads((installed/'Contents/Info.plist').read_bytes())['CFBundleVersion']==('2' if mode=='success' else '1')
    expected='old version restored and confirmed' if mode!='success' else ': confirmed'
    assert expected in logs[0].read_text()

# Deny writes to the real installation parent while leaving the old bundle runnable.
location = root / 'unwritable-install'
installed = location / 'Installed Launcher.app'
app(installed, '1.0.1', 1, 'success')
shutil.copytree(root / 'success/request', location / 'request', ignore=shutil.ignore_patterns('prepared', 'helper-pid'))
executable = installed / 'Contents/MacOS/HD2FXNative'
original = (installed.stat().st_ino, executable.read_bytes())
location.chmod(0o500)
try:
    denied = subprocess.run([executable, location / 'request'], capture_output=True, timeout=10)
    assert denied.returncode == 19 and (b'13' in denied.stderr or b'Permission denied' in denied.stderr), denied.stderr
    assert not list(location.glob('.HD2FXNative-update*'))
    assert (installed.stat().st_ino, executable.read_bytes()) == original
    run('codesign', '--verify', '--deep', '--strict', installed)
    print('PASS unwritable installation preserves signed original', flush=True)
finally:
    location.chmod(0o700)

# Force the installing helper to exit after the atomic exchange, while the
# new process is still unconfirmed. Relaunching that bundle takes over.
location = root / 'interrupted-after-exchange'
installed = location / 'Installed Launcher.app'
app(installed, '1.0.1', 1, 'success')
shutil.copytree(root / 'timeout/request', location / 'request', ignore=shutil.ignore_patterns('prepared', 'helper-pid'))
request = location / 'request'
transaction = location / '.HD2FXNative-update'
old = subprocess.Popen([installed/'Contents/MacOS/HD2FXNative', str(request)])
try:
    for _ in range(700):
        old.poll()  # Reap the exited parent so the helper can observe ESRCH.
        state = transaction / 'state.json'
        if state.exists() and json.loads(state.read_text())['phase'] == 'awaitingStartup' and list(transaction.glob('startup-*')):
            os.kill(int((request/'helper-pid').read_text()), signal.SIGKILL)
            break
        time.sleep(.05)
    else:
        raise RuntimeError('No exchange before interrupt')
    old.wait(timeout=5)
    # The unconfirmed process is a fixture on this exact installation.
    # Capture its PID from ps by exact executable and fixture startup flag.
    executable = str(installed/'Contents/MacOS/HD2FXNative')
    for line in run('ps','-axo','pid=,command=').decode().splitlines():
        pid, _, command = line.strip().partition(' ')
        if command.startswith(tuple(path + ' --confirm-update-startup ' for path in (executable, executable.replace('/private/tmp/', '/tmp/', 1)))):
            os.kill(int(pid), signal.SIGTERM)
    recovery = subprocess.Popen([executable, '--recover-fixture'])
    recovery.wait(timeout=10)
    for _ in range(200):
        logs = list(location.glob('.HD2FXNative-update-*/journal.log'))
        if logs:
            assert 'interrupted exchange rolled back and original confirmed' in logs[0].read_text()
            break
        time.sleep(.05)
    else:
        raise RuntimeError('Recovery did not finalize')
    assert plistlib.loads((installed/'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '1'
    print('PASS interrupted exchange recovery', flush=True)
finally:
    if old.poll() is None: old.terminate()
