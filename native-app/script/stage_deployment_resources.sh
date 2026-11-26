#!/usr/bin/env bash
# Build-time resource assembly. Runtime reads only the generated integrity catalogue.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resources="${1:?usage: stage_deployment_resources.sh BUILT_RESOURCES}"
resources="$(cd "$resources" && pwd -P)"
source="$root/PrivateResources"
catalogue="$root/Resources/deployment-components-v1.json"
approval="$root/Resources/distribution-approvals-v1.json"
deployment="$resources/Deployment"
[[ ! -L "$deployment" && ! -e "$deployment/SteamLinuxRuntime_4" && ! -L "$deployment/SteamLinuxRuntime_4" ]]

if [[ -d "$source/Deployment/RF-FEX" ]]; then
  /bin/mkdir -p "$deployment"
  scratch="$(mktemp -d "$deployment/.stage.XXXXXXXX")"
  trap '/bin/rm -rf "$scratch"' EXIT
  /usr/bin/python3 -I -B "$root/script/rf_fex_bundle.py" assemble-release \
    --manifest "$root/Resources/rf-fex-debug-manifest-v1.json" --approval "$approval" \
    --resources "$root/Resources" --payload "$source/Deployment/RF-FEX" \
    --destination "$scratch/RF-FEX" --output-manifest "$scratch/RF-FEX.manifest.json"
  /bin/rm -rf "$deployment/RF-FEX"
  /bin/mv "$scratch/RF-FEX" "$deployment/RF-FEX"
  /bin/chmod 755 "$deployment/RF-FEX"
  /usr/bin/python3 -I -B "$root/script/rf_fex_bundle.py" verify-package \
    --manifest "$resources/rf-fex-package-v1.json" --payload "$deployment/RF-FEX"
  /bin/rm -f "$deployment/RF-FEX.manifest.json"
else
  [[ ! -e "$deployment/RF-FEX" && ! -L "$deployment/RF-FEX" && ! -e "$deployment/RF-FEX.manifest.json" && ! -L "$deployment/RF-FEX.manifest.json" ]]
fi
if [[ -d "$source/Deployment/Proton-JE" ]]; then
  /usr/bin/python3 -I -B "$root/script/deployment_archives.py" copy \
    --catalogue "$catalogue" --source "$source" --destination "$resources"
  /bin/chmod 644 "$deployment"/Proton-JE/*.tar.xz
else
  /usr/bin/python3 -I -B "$root/script/deployment_archives.py" reject \
    --catalogue "$catalogue" --destination "$resources"
fi
/bin/cp "$root/../THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
