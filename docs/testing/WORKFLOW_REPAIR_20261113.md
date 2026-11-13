# Environment preparation candidate · 2026-11-13

## Implemented

Home and standalone setup share a preparation state machine and existing Core services. Standalone setup ends after verification. Home proceeds to guarded launch only after fresh successful detection. Unique installation discovery resumes the requested workflow. Multiple installations require selection.

Restart approval, identity checks, exact-change receipts, cancellation and encrypted target-scoped passwords remain active. Progress explicitly counts completed workflow steps. Long steps use an indeterminate indicator. Advanced maintenance remains folded and available.

## CONFIG_CHANGED

The previous SSH snapshot revision included raw Steam VDF documents. Steam can update unrelated metadata while managed launch options and the compatibility tool remain unchanged. A later snapshot then failed revision equality. The revision now covers managed values and the launcher configuration revision. Identity/boot checks remain separate. Offline writes retain full destination-file digest checks immediately before replacement.

RecoveryRequired receipts can be reconciled without writes only when the same persistent environment is identified and every affected value exactly matches its original value. Other unresolved receipts block deployment.

The setup profile now includes all four launch tokens required by the guarded launch path.

## Automated results

Functional suite passed, with screenshot provenance checked separately because the desktop is locked.

- SSH 35, privileged executor 30, network 66
- Core 100, integration 27, FX identity 16
- Launch/workflow 23, session credentials 29, encrypted persistence 31
- Deployment 144, including conflict/recovery and externally restored receipt regression
- Ten-language localization and 15 documentation checks passed

Fixture checks do not establish live deployment or gameplay success.

## Live observations and remaining acceptance

The GUI Home action started FX, reused the saved SSH password, connected to SteamOS, detected the environment and reached restart approval. After approval it reached deployment. The Mac locked before the final result could be observed. Configuration success remains unverified.

A separate read-only Core probe confirmed the game installation and both live Steam configuration APIs. Proton-JE was missing. Installed FEX is an aarch64 ELF with SHA-256 f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e. It differs from the reviewed executable baseline. Runtime readiness and candidate installation remain unverified.

A separate-process sudo probe encountered SSH_LOCAL_PORT_BUSY while the GUI App owned the normal tunnel. This does not establish sudo success or failure.

Final Home/setup screenshots, successful configuration, reboot/reconnect continuation, game process, main menu, EAC and multiplayer acceptance remain pending. Incomplete results prevent main promotion.

## Internal build

native-app/build/Workflow-Release/Products/HD2FXNative.app is an arm64 Release-configuration internal candidate with an ad hoc signature. Metadata explicitly records dirty source and internal-test status. The formal clean-source release gate remains unsatisfied. No version number was changed.
