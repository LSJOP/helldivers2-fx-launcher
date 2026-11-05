# Automatic deployment test report

Status: **ISOLATED TESTING PASS; REAL GUEST NOT TESTED**.

| Area | Status | Evidence |
|---|---|---|
| Evidence baseline decoding and invariants | PASS | `DeploymentChecks` |
| Future FX detection remains read-only | PASS | `DeploymentChecks` |
| Passed IPv4/gvproxy stay non-orange | PASS | `DeploymentChecks` |
| Unknown IPv6 is advisory/nonblocking | PASS | `DeploymentChecks` |
| Memory-only SSH/sudo lifecycle and redaction | PASS | `CredentialChecks`, `check_memory_only.py` |
| Configuration receipt/rollback/failure injection | PASS | `DeploymentChecks` |
| Proton production script with official 348245820-byte archive | PASS (isolated HOME) | 5609 regular files, 1896 symlinks, pinned ntdll hash; installed tree retained on rollback |
| Real Guest Proton download/install | NOT TESTED | requires explicit write authorization |
| Real FEX download/install | BLOCKED | no approved artifact |
| Real game/EAC/multiplayer | NOT TESTED | requires separate explicit authorization |

The isolated production-path test used the same generated install and rollback
scripts shipped by the application. It did not connect to the FX VM. The
complete repository check suite is rerun from the clean candidate commit before
the candidate is handed off; its machine-readable output is copied into the
candidate `Evidence` directory.
