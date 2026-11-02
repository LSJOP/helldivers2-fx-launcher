#if DEBUG
import SwiftUI
import AppKit
import ApplicationServices

// Explicit debug-only acceptance. External capture records only this app's window.
@MainActor enum SmokeRunner {
    private static var started = false
    static func runIfRequested(state: AppState) async {
        let args = ProcessInfo.processInfo.arguments
        if !started, let i = args.firstIndex(of: "--migration-smoke"), args.count > i + 1 {
            started = true
            await migrationReview(state, directory: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            return
        }
        if !started, let i = args.firstIndex(of: "--ui-refinement-smoke"), args.count > i + 1 {
            started = true
            await refinementReview(state, directory: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            return
        }
        if !started, let index = args.firstIndex(of: "--ui-v2-menu-review"), args.count > index + 1 {
            started = true
            await menuReview(state, directory: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            return
        }
        if !started, let index = args.firstIndex(of: "--phase1-exit-smoke"), args.count > index + 1 {
            started = true
            await ExitSmokeRunner.run(state: state, directory: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            return
        }
        guard !started, let index = args.firstIndex(of: "--phase1-smoke"), args.count > index + 1 else { return }
        started = true
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        let externalCapture = args.contains("--external-capture")
        var evidence: [String: Any] = ["kind": "native_menu_dispatch_and_swiftui_render", "interactive_clicks": "NOT_TESTED",
                                       "accessibility_trusted": AXIsProcessTrusted(),
                                       "initial_appearance": state.appearance.rawValue,
                                       "default_dark": state.appearance == .dark ? "PASS" : "FAIL"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await waitForTask(state)
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = window.contentView else {
                throw ErrorState("WINDOW_UNAVAILABLE")
            }
            evidence["bridge_loaded"] = state.hasLoaded
            evidence["bridge_error"] = state.error?.code ?? "none"
            evidence["native_window"] = window.isVisible
            evidence["window_number"] = window.windowNumber
            evidence["resizable"] = window.styleMask.contains(.resizable)
            evidence["bundle_id"] = Bundle.main.bundleIdentifier ?? "missing"
            evidence["launcher_version"] = state.value("get_launcher_version", "version")
            evidence["fx_candidates"] = state.rows("list_fx_versions", "candidates").map { $0["version"]?.text ?? "unknown" }
            let snapshotTime = state.observedAt
            let sessionLogCount = state.sessionLogs.count
            window.setContentSize(NSSize(width: 1180, height: 900))
            var captures: [[String: Any]] = []
            var menuActions = 0
            for zh in [false, true] {
                state.chinese = zh
                for appearance in [Appearance.light, .dark] {
                    state.appearance = appearance
                    for page in Page.allCases {
                        // Dispatch the real native Navigate menu action, not a test-only navigation function.
                        state.selection = page == .dashboard ? .logs : .dashboard
                        try await Task.sleep(nanoseconds: 100_000_000)
                        NSApp.mainMenu?.update()
                        for submenu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] { submenu.update() }
                        evidence["menu_items"] = NSApp.mainMenu?.items.map { item in
                            ["title": item.title, "children": item.submenu?.items.map(\.title) ?? []] as [String: Any]
                        }
                        guard let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: { $0.items.contains(where: { $0.title == page.title(state.chinese) }) }),
                              let menuIndex = menu.items.firstIndex(where: { $0.title == page.title(state.chinese) }) else { throw ErrorState("MENU_UNAVAILABLE") }
                        menu.performActionForItem(at: menuIndex)
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        guard state.selection == page else { throw ErrorState("NAVIGATION_FAILED") }
                        menuActions += 1
                        view.layoutSubtreeIfNeeded()
                        let name = "\(zh ? "zh" : "en")-\(appearance.rawValue)-\(page.rawValue).png"
                        let captured = try await capture(window, name: name, directory: directory, external: externalCapture)
                        captures.append(["page": page.rawValue, "title": page.title(zh), "language": zh ? "zh" : "en",
                                         "appearance": appearance.rawValue, "captured": captured, "file": name])
                    }
                }
            }
            evidence["language_theme_preserve_snapshot"] = state.observedAt == snapshotTime && state.sessionLogs.count == sessionLogCount ? "PASS" : "FAIL"
            let original = window.frame
            state.selection = .dashboard
            for zh in [true, false] {
                state.chinese = zh
                for appearance in [Appearance.dark, .light] {
                    state.appearance = appearance
                    window.setContentSize(NSSize(width: 850, height: 560))
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let name = "\(zh ? "zh" : "en")-\(appearance.rawValue)-minimum-dashboard.png"
                    let captured = try await capture(window, name: name, directory: directory, external: externalCapture)
                    captures.append(["page": "dashboard", "title": Page.dashboard.title(zh), "language": zh ? "zh" : "en",
                                     "appearance": appearance.rawValue, "captured": captured, "file": name])
                }
            }
            evidence["minimum_content_width"] = view.bounds.width
            evidence["minimum_content_height"] = view.bounds.height
            evidence["minimum_layout_width"] = window.contentLayoutRect.width
            evidence["minimum_layout_height"] = window.contentLayoutRect.height
            evidence["minimum_window_width"] = window.frame.width
            evidence["minimum_window_height"] = window.frame.height
            state.chinese = true; state.appearance = .dark
            state.selection = .settings
            window.setContentSize(NSSize(width: 880, height: 600))
            try await Task.sleep(nanoseconds: 200_000_000)
            evidence["resize_width"] = view.bounds.width
            _ = try await capture(window, name: "resized-settings.png", directory: directory, external: externalCapture)
            window.setFrame(original, display: true)
            // Exercise a genuine client failure and successful recovery; no Core mutation.
            state.selection = .dashboard
            let python = state.pythonURL
            state.pythonURL = directory.appendingPathComponent("missing-python")
            state.refresh(); try await waitForTask(state)
            evidence["error_propagation"] = state.error?.code == "PYTHON_UNAVAILABLE" && state.stale ? "PASS" : "FAIL"
            _ = try await capture(window, name: "error-python.png", directory: directory, external: externalCapture)
            state.pythonURL = python; state.refresh(); try await waitForTask(state)
            evidence["error_recovery"] = state.error == nil && !state.stale ? "PASS" : "FAIL"
            evidence["native_menu_actions"] = menuActions
            evidence["captures"] = captures
            evidence["capture_method"] = externalCapture ? "screencapture_app_window_only" : "NOT_TESTED"
            evidence["programmatic_result"] = state.hasLoaded && menuActions == 20 ? "PASS" : "FAIL"
            evidence["visual_capture"] = externalCapture && captures.allSatisfy { $0["captured"] as? Bool == true } ? "PASS" : "NOT_TESTED"
            state.selection = .dashboard; state.appearance = .dark
            state.chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        } catch {
            evidence["programmatic_result"] = "FAIL"
            evidence["error"] = (error as? ErrorState)?.code ?? "CAPTURE_FAILED"
        }
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("gui-smoke.json"))
        }
    }
    // One focused check after the user's menu-label feedback; no five-page sweep.
    private static func migrationReview(_ state: AppState, directory: URL) async {
        var result: [String: Any] = [:]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await waitForTask(state)
            guard state.hasLoaded, state.error == nil else { throw ErrorState("BRIDGE_UNAVAILABLE") }
            guard state.rows("get_legacy_catalog", "languages").count == 10,
                  state.rows("get_legacy_catalog", "operations").count == 20 else { throw ErrorState("CATALOG_MISSING") }
            guard let base = Bundle.main.resourceURL else { throw ErrorState("CORE_UNAVAILABLE") }
            for (code, _) in NativeLocalization.languages {
                guard FileManager.default.fileExists(atPath: base.appendingPathComponent("locales/" + code + ".json").path) else { throw ErrorState("LOCALE_MISSING") }
                state.languageCode = code
                guard !state.pageTitle(.dashboard).isEmpty else { throw ErrorState("LOCALE_MISSING") }
            }
            state.languageCode = "zh-CN"
            state.runOperation("read_configuration"); try await waitForTask(state)
            guard state.operationError == nil, state.operationResult["revision"]?.text != nil else { throw ErrorState("CONFIG_READ_FAILED") }
            state.runOperation("launch_game"); try await waitForTask(state)
            guard state.operationError?.code == "CONFIRMATION_REQUIRED" else { throw ErrorState("CONSENT_FAILED") }
            state.runOperation("launch_game", params: ["confirmed": .bool(true)]); try await waitForTask(state)
            guard state.operationError?.code == "RUNTIME_ROOT_REQUIRED" else { throw ErrorState("ROOT_GUARD_FAILED") }
            state.operationSelection = NativeOperation(method: "launch_game")
            try await Task.sleep(nanoseconds: 300_000_000)
            guard NSApp.windows.contains(where: { $0.isVisible }) else { throw ErrorState("WINDOW_UNAVAILABLE") }
            state.operationSelection = nil
            result = ["result":"PASS", "catalog_operations":20, "bundled_original_locales":10,
                      "configuration":"read_only", "launch_guards":"consent_and_root_rejected",
                      "live_game_network_writes":"not_performed", "native_translation":"partial"]
        } catch { result = ["result":"FAIL", "code":(error as? ErrorState)?.code ?? "SMOKE_FAILED"] }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("migration.json"), options: .atomic)
        }
        NSApp.terminate(nil)
    }
    private static func menuReview(_ state: AppState, directory: URL) async {
        var result: [String: Any] = ["kind": "ui_v2_menu_labels", "initial_appearance": state.appearance.rawValue]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await waitForTask(state)
            guard state.hasLoaded, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                throw ErrorState("WINDOW_UNAVAILABLE")
            }
            result["default_dark"] = state.appearance == .dark ? "PASS" : "FAIL"
            for zh in [false, true] {
                state.chinese = zh
                try await Task.sleep(nanoseconds: 500_000_000)
                NSApp.mainMenu?.update()
                let name = state.t("导航", "Navigate")
                guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == name })?.submenu else {
                    throw ErrorState("MENU_UNAVAILABLE")
                }
                // Match AppKit's normal lazy-menu preparation before inspection.
                menu.delegate?.menuNeedsUpdate?(menu)
                menu.delegate?.menuWillOpen?(menu)
                menu.update()
                let titles = menu.items.filter { !$0.isSeparatorItem && !$0.title.isEmpty }.map(\.title)
                let expected = Page.allCases.map { $0.title(zh) } + [state.t("刷新", "Refresh")]
                result[zh ? "chinese_menu" : "english_menu"] = titles
                result[zh ? "chinese_expected" : "english_expected"] = expected
                guard titles == expected else { throw ErrorState("MENU_LABELS_MISMATCH") }
                result[zh ? "chinese_shortcuts" : "english_shortcuts"] = menu.items.filter { !$0.isSeparatorItem && !$0.title.isEmpty }.map(\.keyEquivalent)
            }
            state.selection = .dashboard
            window.setContentSize(NSSize(width: 1180, height: 900))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(nanoseconds: 700_000_000)
            let captured = try await capture(window, name: "zh-dark-dashboard.png", directory: directory, external: true)
            result["captured"] = captured
            result["result"] = captured && state.appearance == .dark ? "PASS" : "FAIL"
        } catch { result["result"] = "FAIL"; result["error"] = (error as? ErrorState)?.code ?? "REVIEW_FAILED" }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("menu-review.json"))
        }
    }
    private static func refinementReview(_ state: AppState, directory: URL) async {
        var result: [String: Any] = ["kind": "five_page_ui_refinement", "physical_keyboard_voiceover": "NOT_TESTED"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await waitForTask(state)
            guard state.hasLoaded, state.error == nil, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { throw ErrorState("BRIDGE_OR_WINDOW_UNAVAILABLE") }
            let snapshot = state.observedAt
            let heroOnly = ProcessInfo.processInfo.arguments.contains("--hero-only")
            guard NSImage(named: "HelldiverHero") != nil else { throw ErrorState("HERO_ASSET_MISSING") }
            state.chinese = true; state.appearance = .dark
            window.setContentSize(NSSize(width: 1180, height: 850))
            try await Task.sleep(nanoseconds: 300_000_000)
            var files: [String] = []
            for page in (heroOnly ? [.dashboard] : Page.allCases) {
                NSApp.mainMenu?.update()
                guard let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == "导航" }) else { throw ErrorState("MENU_UNAVAILABLE") }
                menu.delegate?.menuNeedsUpdate?(menu); menu.delegate?.menuWillOpen?(menu); menu.update()
                guard let index = menu.items.firstIndex(where: { $0.title == page.title(true) }) else { throw ErrorState("MENU_UNAVAILABLE") }
                menu.performActionForItem(at: index)
                try await Task.sleep(nanoseconds: 500_000_000)
                guard state.selection == page else { throw ErrorState("NAVIGATION_FAILED") }
                let file = "zh-dark-" + page.rawValue + ".png"
                guard try await capture(window, name: file, directory: directory, external: true) else { throw ErrorState("CAPTURE_FAILED") }
                files.append(file)
            }
            state.selection = .dashboard
            for variant in (heroOnly ? ["zh-dark-minimum-dashboard"] : ["en-dark-dashboard", "zh-light-dashboard", "zh-dark-minimum-dashboard"]) {
                state.chinese = !variant.hasPrefix("en")
                state.appearance = variant.contains("light") ? .light : .dark
                if variant.contains("minimum") { window.setContentSize(NSSize(width: 850, height: 560)) }
                try await Task.sleep(nanoseconds: 500_000_000)
                let file = variant + ".png"
                guard try await capture(window, name: file, directory: directory, external: true) else { throw ErrorState("CAPTURE_FAILED") }
                files.append(file)
            }
            result["files"] = files
            result["native_menu_pages"] = heroOnly ? 1 : 5
            result["snapshot_preserved"] = state.observedAt == snapshot
            result["runtime_evidence"] = state.results["get_environment_status"]?["status"]?.text ?? "unknown"
            result["soldier_asset"] = "HelldiverHero asset catalog image loaded"
            result["result"] = state.observedAt == snapshot ? "PASS" : "FAIL"
            window.setContentSize(NSSize(width: 1180, height: 850))
            state.chinese = true; state.appearance = .dark
        } catch { result["result"] = "FAIL"; result["error"] = (error as? ErrorState)?.code ?? "UI_CHECK_FAILED" }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("refinement-review.json"))
        }
    }
    private static func waitForTask(_ state: AppState) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while state.tasks.busy {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ErrorState("TIMEOUT") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    private static func capture(_ window: NSWindow, name: String, directory: URL, external: Bool) async throws -> Bool {
        guard external else { return false }
        let token = UUID().uuidString
        let request: [String: Any] = ["token": token, "window": window.windowNumber, "file": name]
        try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("capture-request.json"), options: .atomic)
        let ack = directory.appendingPathComponent(token + ".ack")
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !FileManager.default.fileExists(atPath: ack.path) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ErrorState("CAPTURE_TIMEOUT") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return (try? String(contentsOf: ack, encoding: .utf8)) == "OK"
    }
}

// Exercises the real applicationShouldTerminate path. The external runner observes
// actual child PIDs and requests quit while a real read-only refresh is underway.
@MainActor private enum ExitSmokeRunner {
    static func run(state: AppState, directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NativeLifecycle.event = { event in
                let path = directory.appendingPathComponent("lifecycle-events.txt")
                let previous = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
                try? (previous + event + "\n").write(to: path, atomically: true, encoding: .utf8)
            }
            let initialDeadline = ProcessInfo.processInfo.systemUptime + 20
            while state.tasks.busy {
                guard ProcessInfo.processInfo.systemUptime < initialDeadline else { throw ErrorState("TIMEOUT") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard state.hasLoaded else { throw ErrorState("BRIDGE_UNAVAILABLE") }
            try write(["pid": ProcessInfo.processInfo.processIdentifier, "bridge_loaded": state.hasLoaded], name: "exit-ready.json", directory: directory)
            try await waitFor("refresh.request", directory: directory)
            state.refresh()
            try await waitFor("quit.request", directory: directory)
            try write(["pid": ProcessInfo.processInfo.processIdentifier, "task_busy_at_quit": state.tasks.busy,
                       "quit_route": "NSApplication.terminate -> applicationShouldTerminate"], name: "exit-request.json", directory: directory)
            NSApp.terminate(nil)
            NativeLifecycle.event?("terminateReturned")
        } catch {
            try? write(["result": "FAIL", "code": (error as? ErrorState)?.code ?? "EXIT_CHECK_FAILED"], name: "exit-error.json", directory: directory)
        }
    }
    private static func waitFor(_ name: String, directory: URL) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ErrorState("TIMEOUT") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    private static func write(_ value: [String: Any], name: String, directory: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
#endif
