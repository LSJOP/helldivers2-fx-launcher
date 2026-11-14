import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        NativeLifecycle.event?("applicationShouldTerminate")
        #endif
        NativeLifecycle.cancel?()
        // AppKit runs a nested termination loop. A queued main-dispatch reply can
        // be blocked by the caller's MainActor task; use that loop's timer instead.
        let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard !CoreWorkerStatus.isActive else { return }
                timer.invalidate()
                #if DEBUG
                NativeLifecycle.event?("replyToApplicationShouldTerminate")
                #endif
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        return .terminateLater
    }
}

@MainActor enum NativeLifecycle {
    private static var didConfirmUpdate = false
    static func confirmUpdateStartup() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didConfirmUpdate, let index = arguments.firstIndex(of: "--confirm-update-startup"),
              arguments.indices.contains(index + 1),
              let token = UUID(uuidString: arguments[index + 1]) else { return }
        // The main scene has mounted. Give immediate startup crashes time to surface.
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        guard !didConfirmUpdate, NSApp.windows.contains(where: { $0.isVisible }) else { return }
        didConfirmUpdate = true
        FileHandle.standardOutput.write(Data("HD2_UPDATE_READY \(token.uuidString)\n".utf8))
    }
    private static var checkedInterruptedUpdate = false
    static func recoverInterruptedUpdate() async {
        guard !checkedInterruptedUpdate else { return }
        checkedInterruptedUpdate = true
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let directory = bundle.deletingLastPathComponent().appendingPathComponent(".HD2FXNative-update")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("state.json").path) else { return }
        let deadline = ContinuousClock.now + .seconds(40)
        while ContinuousClock.now < deadline && !Task.isCancelled {
            let token = UUID().uuidString
            let helper = Process()
            helper.executableURL = bundle.appendingPathComponent("Contents/MacOS/HD2UpdateInstaller")
            helper.arguments = ["--recover", String(getpid()), token]
            do { try helper.run() } catch { return }
            let ready = directory.appendingPathComponent("recover-" + token)
            while helper.isRunning {
                if FileManager.default.fileExists(atPath: ready.path) {
                    NSApp.terminate(nil)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard helper.terminationStatus == 75 else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
    }

    static var cancel: (() -> Void)?
    #if DEBUG
    static var event: ((String) -> Void)?
    #endif
}

@main
struct HD2FXNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup(state.t("ui.brand.name"), id: "main") {
            Group {
                #if DEBUG
                if NativeLocalization.artworkPreviewRequested {
                    if NativeLocalization.artworkPreviewAllowed {
                        ArtworkFixturePreview(state: state)
                    } else {
                        Text(verbatim: "UI PREVIEW REFUSED: use an isolated review bundle with updates disabled.")
                    }
                } else {
                    regularContent
                }
                #else
                regularContent
                #endif
            }
            .frame(minWidth: 850, minHeight: 560)
            .preferredColorScheme(state.appearance.scheme)
        }
        .defaultSize(width: 1060, height: 720)
        .commands {
            NavigationCommands(state: state)
            AppUpdateCommands(state: state, manager: state.updates)
        }
        Settings {
            ScrollView { SettingsView(state: state).padding(24) }
                .disabled(NativeLocalization.artworkPreviewRequested)
                .frame(width: 650, height: 700)
                .preferredColorScheme(state.appearance.scheme)
        }
    }
    private var regularContent: some View {
        ContentView(state: state, tasks: state.tasks)
            .task {
                NativeLifecycle.cancel = { state.endSession() }
                Task { await NativeLifecycle.recoverInterruptedUpdate() }
                if !state.hasLoaded { state.refresh() }
                await NativeLifecycle.confirmUpdateStartup()
                #if DEBUG
                await SmokeRunner.runIfRequested(state: state)
                #endif
            }
    }
}

struct AppUpdateCommands: Commands {
    @ObservedObject var state: AppState
    @ObservedObject var manager: AppUpdateManager
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(UpdateString.checkNow.text(state.languageCode)) { manager.checkForUpdates() }
                .disabled(!manager.canCheck || NativeLocalization.artworkPreviewRequested)
                .id(state.languageCode)
        }
    }
}

struct NavigationCommands: Commands {
    @ObservedObject var state: AppState
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu(state.t("ui.193")) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element.id) { index, page in
                Button(state.pageTitle(page)) { state.selection = page }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(NativeLocalization.artworkPreviewRequested)
            }
            .id(state.languageCode)
            Divider()
            Button(state.t("ui.262")) { state.refresh() }.keyboardShortcut("r", modifiers: .command)
                .disabled(NativeLocalization.artworkPreviewRequested)
                .id(state.languageCode)
        }
    }
}

#if DEBUG
/// An isolated, non-interactive view of synthetic state. It never starts ContentView,
/// its refresh task, or any Core, FX or SSH operation.
@MainActor private struct ArtworkFixturePreview: View {
    @ObservedObject var state: AppState
    @State private var configured = false
    private let args = ProcessInfo.processInfo.arguments
    private func option(_ name: String, fallback: String) -> String {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return fallback }
        return args[index + 1]
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "UI PREVIEW / FIXTURE DATA — NOT REAL  ·  界面预览 / 模拟数据，非真实结果")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.yellow)
            HStack(spacing: 0) {
                SidebarView(state: state).frame(width: 210)
                ScrollView {
                    Group {
                        if option("--artwork-fixture-preview", fallback: "") == "completion" {
                            FirstRunSetupView(state: state, tasks: state.tasks, credentials: state.credentials)
                        } else {
                            DashboardView(state: state, tasks: state.tasks)
                        }
                    }
                    .padding(TacticalSpacing.page)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(TacticalColors(scheme: state.appearance.scheme ?? .dark).background)
            }
            .disabled(true)
        }
        .task {
            guard !configured else { return }
            state.configureArtworkFixture(
                scenario: option("--artwork-fixture-preview", fallback: ""),
                language: option("--preview-language", fallback: "en"),
                appearance: option("--preview-appearance", fallback: "dark") == "light" ? .light : .dark)
            configured = true
            let request = option("--preview-capture-request", fallback: "")
            guard !request.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            let width = Double(option("--preview-width", fallback: "1280")) ?? 1280
            let height = Double(option("--preview-height", fallback: "900")) ?? 900
            window.setContentSize(NSSize(width: max(850, width), height: max(560, height)))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try? String(window.windowNumber).write(toFile: request, atomically: true, encoding: .utf8)
            // Only this isolated fixture process exits; no other app is touched.
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: request + ".ack") { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
