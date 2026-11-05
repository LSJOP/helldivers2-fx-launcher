# Automatic deployment audit

## Result

**CONDITIONALLY READY FOR CANDIDATE TESTING, NOT RELEASE READY**. The Swift path now has a verified pipeline for the one approved Proton archive and a transaction/receipt engine for configuration. The complete successful environment still cannot be provisioned from a fresh VM because the exact FEX build has no approved release artifact.

## Confirmed strengths

- detection and modification are separate;
- passed observations remain green even when another component is unavailable;
- IPv6 is advisory and excluded from executable operations;
- exact consent, Steam/game idle guards, target identity, revision compare-and-swap, durable prewrite receipts, readback verification, cancellation, and recovery are tested;
- launch-option merging preserves unrelated user values and stops on conflicts;
- credentials are now process-memory-only and SSH/sudo authorization states are independent.

## Release blockers

- FEX PR20 has no trusted release artifact; automatic download is forbidden;
- real Guest Proton download/install/rollback remains NOT TESTED pending explicit write authorization;
- a future FX/SteamOS version needs its own evidence baseline before automatic mutation;
- archive download currently reports deployment phases rather than byte-level UI progress.

For the exact Proton release, `first_run_deploy` now uses a fixed HTTPS URL, HTTPS-only redirects, TLS 1.2 minimum, connection/resource/stall limits, an exact byte ceiling and size, full archive SHA-256, private staging, exact inventory counts, escaping-link and special-file rejection, critical-file hashes, stopped Steam/game and boot checks, an atomic final move, readback verification, receipt integration and retained-tree rollback. The same production script completed against the historical official archive in an isolated local HOME; no real Guest was changed.

The candidate must not claim fresh-VM completeness until the FEX artifact blocker and real Guest acceptance are closed.
