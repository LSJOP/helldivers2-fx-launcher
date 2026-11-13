# Environment preparation candidate · 2026-11-13

## Implemented

Home and standalone setup share a preparation state machine and existing Core services. Standalone setup ends after verification. Home proceeds to guarded launch only after fresh successful detection. Unique installation discovery resumes the requested workflow. Multiple installations require selection.

Restart approval, identity checks, exact-change receipts, cancellation and encrypted target-scoped passwords remain active. Progress explicitly counts completed workflow steps. Long steps use an indeterminate indicator. Advanced maintenance remains folded and available.

## CONFIG_CHANGED

The previous SSH snapshot revision included raw Steam VDF documents. Steam can update unrelated metadata while managed launch options and the compatibility tool remain unchanged. A later snapshot then failed revision equality. The revision now covers managed values and the launcher configuration revision. Identity/boot checks remain separate. Offline writes retain full destination-file digest checks immediately before replacement.

RecoveryRequired receipts can be reconciled without writes only when the same persistent environment is identified and every affected value exactly matches its original value. Other unresolved receipts block deployment.

The setup profile now includes all four launch tokens required by the guarded launch path.

## Automated results

Functional suite passed independently of the README screenshot provenance gate. The latest Release Home and setup windows were captured on November 14 in the Codex GUI tool output.

- SSH 35, privileged executor 30, network 66
- Core 100, integration 27, FX identity 19
- Launch/workflow 23, session credentials 29, encrypted persistence 31
- Deployment 150, including conflict/recovery and externally restored receipt regression
- Proton installer 19, including the verified archive cache and runtime-cache validation
- Ten-language localization and 15 documentation checks passed

Fixture checks do not establish live deployment or gameplay success.

## Live observations and remaining acceptance

The first GUI Home attempt started FX, reused the saved SSH password and detected SteamOS. The initial Proton download was too slow. A matching SHA-256 archive from the local research cache enabled a retry, followed by verified installation and launch-option writeback. The VM rebooted, but its first SSH reconnect attempt stopped during gvproxy startup. A later authenticated detection verified the new boot on the same machine and resumed configuration without another reboot. The Core sudo verification succeeded.

A post-reboot file comparison found only generated Python cache entries and no changes to distributed Proton files. After the runtime-cache check was corrected, the configured Proton passed the full distributed-file inventory check. Steam readback confirmed the selected compatibility tool is proton-je-11.0-20261014-3. The November 14 standalone GUI run applied and verified all four managed launch options. The subsequent Home run reused saved credentials and skipped writes to already configured components.

Both GUI paths stopped at ARTIFACT_UNAPPROVED for FEX. The installed executable is aarch64 and has SHA-256 f9cbb7a70e804b9930fed02fd9d1349d49d7808faace703063a9b4944bc3568e. It differs from the reviewed baseline. No matching reviewed replacement was available, and FEX runtime readiness was not established. The Home flow did not reach game process creation. Main menu, EAC and multiplayer remain unverified. These results do not qualify for promotion to main.

## Internal build

The arm64 Release-configuration candidate is built from a clean committed checkout at native-app/build/Workflow-Release/CommittedProducts/HD2FXNative.app. It has an ad hoc signature and passed bundle validation. The marketing version remains 0.1.0.
