"""Exercise the real installer with isolated signed macOS AppKit bundles."""
import base64, hashlib, json, plistlib, shutil, subprocess, tempfile, time
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
