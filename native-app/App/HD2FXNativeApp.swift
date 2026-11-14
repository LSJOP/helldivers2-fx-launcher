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
            ContentView(state: state, tasks: state.tasks)
                .frame(minWidth: 850, minHeight: 560)
                .preferredColorScheme(state.appearance.scheme)
                .task {
                    NativeLifecycle.cancel = { state.endSession() }
                    if !state.hasLoaded { state.refresh() }
                    await NativeLifecycle.confirmUpdateStartup()
                    #if DEBUG
                    await SmokeRunner.runIfRequested(state: state)
                    #endif
                }
        }
        .defaultSize(width: 1060, height: 720)
        .commands {
            NavigationCommands(state: state)
            AppUpdateCommands(state: state, manager: state.updates)
        }
        Settings {
            ScrollView { SettingsView(state: state).padding(24) }
                .frame(width: 650, height: 700)
                .preferredColorScheme(state.appearance.scheme)
        }
    }
}

struct AppUpdateCommands: Commands {
    @ObservedObject var state: AppState
    @ObservedObject var manager: AppUpdateManager
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(UpdateString.checkNow.text(state.languageCode)) { manager.checkForUpdates() }
                .disabled(!manager.canCheck)
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
            }
            .id(state.languageCode)
            Divider()
            Button(state.t("ui.262")) { state.refresh() }.keyboardShortcut("r", modifiers: .command)
                .id(state.languageCode)
        }
    }
}
