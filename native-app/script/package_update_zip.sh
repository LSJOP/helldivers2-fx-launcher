#!/bin/bash
# Package an already signed App using the v1.0.1 update archive rules.
set -euo pipefail
app="${1:?usage: package_update_zip.sh HD2FXNative.app OUTPUT.zip}"
archive="${2:?usage: package_update_zip.sh HD2FXNative.app OUTPUT.zip}"
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(basename "$app")" = HD2FXNative.app && -d "$app" && "$archive" = /* && ! -e "$archive" ]]
"$root/script/check_release_bundle.sh" "$app"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/hd2-zip-preflight.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
cat > "$temporary/check.swift" <<'SWIFT'
import Foundation
@main struct Check {
    static func main() throws {
        try UpdateZIPPreflight.validate(URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
SWIFT
xcrun swiftc "$root/UpdateHelper/ArchivePathPolicy.swift" "$root/UpdateHelper/UpdateZIPPreflight.swift" \
    "$root/Services/UpdateReleaseService.swift" "$temporary/check.swift" -o "$temporary/check"
ditto -c -k --norsrc --keepParent "$app" "$archive"
if ! "$temporary/check" "$archive"; then
    rm -f "$archive"
    echo 'Update ZIP rejected by archive safety policy.' >&2
    exit 1
fi
