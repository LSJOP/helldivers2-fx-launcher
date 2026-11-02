import SwiftUI

struct SoftwareUpdateView: View {
    @ObservedObject var manager: AppUpdateManager
    let language: String
    var body: some View {
        TacticalPanel(number: "U", title: UpdateString.section.text(language), symbol: "arrow.down.circle") {
            TacticalInfoRow(title: UpdateString.currentVersion.text(language), value: manager.version)
            Toggle(UpdateString.automaticChecks.text(language), isOn: Binding(
                get: { manager.automaticChecks }, set: { manager.setAutomaticChecks($0) }
            )).disabled(!manager.isConfigured).accessibilityIdentifier("updates.automatic")
            Text((manager.automaticChecks ? UpdateString.automaticOn : .automaticOff).text(language))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            TacticalButton(title: UpdateString.checkNow.text(language), symbol: "arrow.clockwise") {
                manager.checkForUpdates()
            }.disabled(!manager.canCheck).accessibilityIdentifier("updates.check")
            Text(manager.status.text(language)).accessibilityIdentifier("updates.status")
            if let code = manager.errorCode { Text(code).font(TacticalTypography.log).textSelection(.enabled) }
            Text(UpdateString.scope.text(language)).font(TacticalTypography.caption).foregroundStyle(.secondary)
        }
    }
}
