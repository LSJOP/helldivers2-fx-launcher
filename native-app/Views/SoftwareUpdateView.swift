import SwiftUI

struct SoftwareUpdateView: View {
    @ObservedObject var manager: AppUpdateManager
    let language: String
    private func text(_ key: UpdateString) -> String { key.text(language) }
    private var installTitle: String {
        switch manager.status {
        case .downloading:
            guard let progress = manager.downloadProgress else { return text(.downloading) }
            return text(.downloading) + " " + progress.formatted(.percent.precision(.fractionLength(0)))
        case .verifying: return text(.verifying)
        case .installing: return text(.installing)
        case .restarting: return text(.restarting)
        case .available, .downloaded: return text(.downloadInstall)
        default: return text(.retryUpdate)
        }
    }
    var body: some View {
        TacticalPanel(number: "U", title: text(.section), symbol: "arrow.down.circle") {
            TacticalInfoRow(title: text(.currentVersion), value: manager.version)
            TacticalInfoRow(title: text(.build), value: manager.build)
            Picker(text(.channel), selection: Binding(get: { manager.channel }, set: { manager.selectChannel($0) })) {
                if manager.channel == NativeReleaseService.testChannel {
                    Text(text(.preview)).tag(NativeReleaseService.testChannel)
                } else {
                    Text(text(.stable)).tag("stable")
                    if manager.isConfigured && manager.configuration.previewEnabled { Text(text(.preview)).tag("preview") }
                }
            }.disabled(!manager.canCheck)
            if !manager.configuration.previewEnabled { Text(text(.previewBlocked)).font(TacticalTypography.caption).foregroundStyle(.secondary) }
            TacticalInfoRow(title: text(.lastCheck), value: manager.lastCheck?.formatted(date: .abbreviated, time: .shortened) ?? text(.never))
            Toggle(text(.automaticChecks), isOn: Binding(get: { manager.automaticChecks }, set: { manager.setAutomaticChecks($0) }))
                .disabled(!manager.isConfigured).accessibilityIdentifier("updates.automatic")
            Text(text(manager.automaticChecks ? .automaticOn : .automaticOff)).font(TacticalTypography.caption).foregroundStyle(.secondary)
            HStack {
                TacticalButton(title: text(.checkNow), symbol: "arrow.clockwise", disabledReason: manager.canCheck ? nil : text(.checking)) { manager.checkForUpdates() }
                    .accessibilityIdentifier("updates.check")
                if manager.canCancelOperation { Button(text(.cancel)) { manager.cancel() } }
            }
            Text(text(manager.status)).accessibilityIdentifier("updates.status")
            if let candidate = manager.candidate {
                Text(candidate.manifest.version + " (" + String(candidate.manifest.build) + ")").font(.headline)
                DisclosureGroup(text(.releaseNotes)) { Text(String((candidate.release.body ?? "").prefix(16000))).textSelection(.enabled) }
                Link(text(.releaseNotes), destination: candidate.release.html_url)
                TacticalButton(title: installTitle, symbol: "arrow.down.app", primary: true,
                               disabledReason: manager.canStartInstall ? nil : text(manager.canCheck ? .trustBlocked : manager.status)) {
                    manager.downloadAndInstall()
                }.accessibilityIdentifier("updates.install")
            }
            if manager.status == .downloading {
                ProgressView(value: manager.downloadProgress)
            }
            if manager.cachedArchive != nil { Text(text(.downloaded)) }
            if !manager.isConfigured { TacticalWarningBanner(text: text(.trustBlocked)) }
            if let code = manager.errorCode { DisclosureGroup(text(.failed)) { Text(code).font(TacticalTypography.log) } }
            Text(text(.scope)).font(TacticalTypography.caption).foregroundStyle(.secondary)
        }
    }
}
