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
        let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
            MainActor.assumeIsolated {
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
        WindowGroup("HELLDIVERS 2 FX Launcher", id: "main") {
            ContentView(state: state, tasks: state.tasks)
                .frame(minWidth: 850, minHeight: 560)
                .preferredColorScheme(state.appearance.scheme)
                .task {
                    NativeLifecycle.cancel = { state.tasks.cancel() }
                    if !state.hasLoaded { state.refresh() }
                    #if DEBUG
                    await SmokeRunner.runIfRequested(state: state)
                    #endif
                }
        }
        .defaultSize(width: 1060, height: 720)
        .commands { NavigationCommands(state: state) }
        Settings {
            SettingsView(state: state)
                .padding(24).frame(width: 500)
                .preferredColorScheme(state.appearance.scheme)
        }
    }
}

struct NavigationCommands: Commands {
    @ObservedObject var state: AppState
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu(state.t("导航", "Navigate")) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element.id) { index, page in
                Button(page.title(state.chinese)) { state.selection = page }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            .id(state.chinese)
            Divider()
            Button(state.t("刷新", "Refresh")) { state.refresh() }.keyboardShortcut("r", modifiers: .command)
                .id(state.chinese)
        }
    }
}
