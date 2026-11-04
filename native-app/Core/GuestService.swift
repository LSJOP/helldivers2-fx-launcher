import Foundation

/// Guest probes and narrowly scoped transactions delivered over the verified SSH master.
/// Scripts are fixed, POSIX-only and never interpolate user input.
enum GuestScripts {
    static let state = #"""
set -u
S="$HOME/.local/share/Steam"
PROTON="$S/compatibilitytools.d/proton-je-11.0-20261014-3"
hashf(){ if [ -f "$1" ]; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1; else printf ''; fi; }
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown')
marker=false; grep -q 'steamac.gfx=vulkan' /proc/cmdline 2>/dev/null && marker=true
ipv6_all=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || printf '?')
ipv6_default=$(cat /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || printf '?')
ipv6_eth0=$(cat /proc/sys/net/ipv6/conf/eth0/disable_ipv6 2>/dev/null || printf '?')
ipv6_lo=$(cat /proc/sys/net/ipv6/conf/lo/disable_ipv6 2>/dev/null || printf '?')
gp=$(pgrep -x helldivers2.exe 2>/dev/null | wc -l | tr -d ' ')
sp=$(pgrep -x steam 2>/dev/null | wc -l | tr -d ' ')
login=unknown
log="$S/logs/connection_log.txt"
if [ -f "$log" ]; then
  last=$(tail -c 65536 "$log" 2>/dev/null | grep -o '\[\(Logged On\|Logged Off\|Connecting\|Connected\|Logging On\|Disconnected\),' | tail -1)
  case "$last" in *"Logged On"*) login=true ;; "") login=unknown ;; *) login=false ;; esac
fi
apps=$(pgrep -a -x reaper 2>/dev/null | grep -o 'SteamLaunch AppId=[0-9]*' | grep -o '[0-9]*$' | sort -u | tr '\n' ' ')
vulkan=false; grep -q 'steamac.gfx=vulkan' /proc/cmdline 2>/dev/null && vulkan=true
fex=$(hashf "$S/steamapps/common/FEX-Emu/usr/bin/FEX")
ntdll=$(hashf "$PROTON/files/lib/wine/x86_64-windows/ntdll.dll")
u32=$(hashf "$PROTON/files/lib/wine/x86_64-windows/user32.dll")
w32u=$(hashf "$PROTON/files/lib/wine/x86_64-windows/win32u.dll")
kb=$(hashf "$PROTON/files/lib/wine/x86_64-windows/kernelbase.dll")
u32s=$(hashf "$PROTON/files/lib/wine/x86_64-unix/win32u.so")
tool=""
if [ -f "$S/config/config.vdf" ]; then
  tool=$(sed -n '/"CompatToolMapping"/,$p' "$S/config/config.vdf" 2>/dev/null | awk '/"553850"/{seen=1} seen && /"name"/{print; exit}' | sed 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/')
fi
launch=""
for cfg in "$S"/userdata/*/config/localconfig.vdf; do
  [ -f "$cfg" ] || continue
  candidate=$(awk '/"553850"/{seen=1} seen && /"LaunchOptions"/{print; exit}' "$cfg" 2>/dev/null | sed 's/.*"LaunchOptions"[[:space:]]*"\([^"]*\)".*/\1/')
  if [ -n "$candidate" ]; then launch="$candidate"; break; fi
done
uid=$(id -u)
proxy=none
p="/run/user/$uid/systemd/user/steam.service.d/90-hd2-proxy.conf"
if [ -f "$p" ]; then
  if grep -q '192.168.127.254:7890' "$p" 2>/dev/null; then proxy=current; elif grep -q '127.0.0.1:17890' "$p" 2>/dev/null; then proxy=legacy; else proxy=unknown; fi
fi
svc=$(systemctl --user show steam.service --property=LoadState,ActiveState,SubState 2>/dev/null | tr '\n' ' ')
service=unknown
case "$svc" in *"LoadState=loaded"*"ActiveState=active"*"SubState=running"*) service=running ;; *"ActiveState=inactive"*|*"ActiveState=failed"*) service=stopped ;; esac
printf '{"boot":"%s","marker":%s,"ipv6":{"all":"%s","default":"%s","eth0":"%s","lo":"%s"},"proxy":"%s","service":"%s","service_raw":"%s","game_count":%s,"steam_count":%s,"steam_logged_on":%s,"apps":"%s","vulkan":%s,"fex":"%s","ntdll":"%s","tool":"%s","launch":"%s","wine_core":{"x86_64-windows/user32.dll":"%s","x86_64-windows/win32u.dll":"%s","x86_64-windows/kernelbase.dll":"%s","x86_64-unix/win32u.so":"%s"},"uid":%s}\n' \
 "$boot" "$marker" "$ipv6_all" "$ipv6_default" "$ipv6_eth0" "$ipv6_lo" "$proxy" "$service" "$svc" "$gp" "$sp" "$login" "$apps" "$vulkan" "$fex" "$ntdll" "$(json_escape "$tool")" "$(json_escape "$launch")" "$u32" "$w32u" "$kb" "$u32s" "$uid"
"""#

    static let inspect = #"""
set -u
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown')
marker=false; grep -q 'steamac.gfx=vulkan' /proc/cmdline 2>/dev/null && marker=true
ok=true
a=""; d=""; e=""; l=""
for k in all default eth0 lo; do
  v=$(cat "/proc/sys/net/ipv6/conf/$k/disable_ipv6" 2>/dev/null || printf '?')
  case "$k" in all) a="$v";; default) d="$v";; eth0) e="$v";; lo) l="$v";; esac
  case "$v" in 0|1) ;; *) ok=false ;; esac
done
uid=$(id -u)
p="/run/user/$uid/systemd/user/steam.service.d/90-hd2-proxy.conf"
proxy=none
if [ -f "$p" ]; then
  if grep -q '192.168.127.254:7890' "$p" 2>/dev/null; then proxy=current; elif grep -q '127.0.0.1:17890' "$p" 2>/dev/null; then proxy=legacy; else proxy=unknown; fi
fi
svc=$(systemctl --user show steam.service --property=LoadState,ActiveState,SubState 2>/dev/null | tr '\n' ' ')
service=unknown
case "$svc" in *"LoadState=loaded"*"ActiveState=active"*"SubState=running"*) service=running ;; *"ActiveState=inactive"*|*"ActiveState=failed"*) service=stopped ;; esac
printf '{"boot":"%s","marker":%s,"ipv6_ok":%s,"ipv6":{"all":"%s","default":"%s","eth0":"%s","lo":"%s"},"proxy":"%s","service":"%s"}\n' "$boot" "$marker" "$ok" "$a" "$d" "$e" "$l" "$proxy" "$service"
"""#

    /// Steam is started at most once; the probe never stops it and never retries a transaction.
    static func steam(boot: String) -> String {
        #"""
set -u
boot_now=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown')
[ "$boot_now" = "\#(boot)" ] || { printf '{"ok":false,"reason":"guest_identity_changed"}\n'; exit 0; }
grep -q 'steamac.gfx=vulkan' /proc/cmdline 2>/dev/null || { printf '{"ok":false,"reason":"guest_marker_unverified"}\n'; exit 0; }
for n in reaper helldivers2.exe; do
  if pgrep -x "$n" >/dev/null 2>&1; then printf '{"ok":false,"reason":"game_or_launch_active"}\n'; exit 0; fi
done
svc=$(systemctl --user show steam.service --property=LoadState,ActiveState,SubState 2>/dev/null | tr '\n' ' ')
case "$svc" in
  *"LoadState=loaded"*) ;;
  *) printf '{"ok":false,"reason":"steam_service_unloaded"}\n'; exit 0 ;;
esac
case "$svc" in
  *"ActiveState=active"*"SubState=running"*) printf '{"ok":true,"started":false,"service":"running"}\n'; exit 0 ;;
  *"ActiveState=inactive"*|*"ActiveState=failed"*) ;;
  *) printf '{"ok":false,"reason":"steam_service_transitioning"}\n'; exit 0 ;;
esac
if ! systemctl --user start steam.service >/dev/null 2>&1; then
  printf '{"ok":false,"reason":"steam_start_failed"}\n'; exit 0
fi
printf '{"ok":true,"started":true,"service":"started"}\n'
"""#
    }

    static func launchGame(boot: String) -> String {
        #"""
set -u
boot_now=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown')
[ "$boot_now" = "\#(boot)" ] || { printf '{"ok":false,"reason":"guest_identity_changed"}\n'; exit 0; }
if pgrep -x helldivers2.exe >/dev/null 2>&1; then printf '{"ok":true,"started":false,"reason":"already_running"}\n'; exit 0; fi
uid=$(id -u)
DISPLAY=:0 XDG_RUNTIME_DIR="/run/user/$uid" steam -applaunch 553850 >/dev/null 2>&1 || { printf '{"ok":false,"reason":"steam_rejected_launch"}\n'; exit 0; }
printf '{"ok":true,"started":true}\n'
"""#
    }


}

struct GuestSession {
    var boot: String
    var identitySignature: String
    var plan: [String: JSONValue]
}

enum GuestService {
    static func steamReady(_ state: [String: JSONValue]) -> Bool {
        state["steam_logged_on"]?.boolean == true && (state["steam_count"]?.integer ?? 0) > 0 && state["service"]?.text == "running"
    }
    static func parse(_ text: String, expected: String) throws -> [String: JSONValue] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoreError(expected)
        }
        return CoreJSON.value(object).object
    }

    static func state(_ transport: SSHTransport, context: CoreContext?) throws -> [String: JSONValue] {
        let result = try transport.run(GuestScripts.state, timeout: 40, context: context)
        guard result.status == 0 else { throw CoreError("GUEST_INSPECTION_FAILED", ["summary": .string(CoreRedaction.scrub(result.stderr))]) }
        return try parse(result.stdout, expected: "GUEST_INSPECTION_FAILED")
    }

    static func inspect(_ transport: SSHTransport, context: CoreContext?) throws -> [String: JSONValue] {
        let result = try transport.run(GuestScripts.inspect, timeout: 25, context: context)
        guard result.status == 0 else { throw CoreError("GUEST_INSPECTION_FAILED") }
        let plan = try parse(result.stdout, expected: "GUEST_INSPECTION_FAILED")
        guard plan["boot"]?.text != nil, plan["marker"]?.boolean == true, plan["ipv6_ok"]?.boolean == true else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("guest_identity_or_marker_unverified")])
        }
        return plan
    }

    static func connect(_ transport: SSHTransport, password: String?, passphrase: String?,
                        context: CoreContext?, hostIdentity: () throws -> String) throws -> GuestSession {
        transport.setSecret(password: password, passphrase: passphrase)
        try transport.connectOnce(context: context)
        let first = try hostIdentity()
        let plan = try inspect(transport, context: context)
        let second = try hostIdentity()
        guard first == second, let boot = plan["boot"]?.text else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("target_changed_during_binding")])
        }
        return GuestSession(boot: boot, identitySignature: second, plan: plan)
    }

    static func verify(_ transport: SSHTransport, session: GuestSession, context: CoreContext?,
                       hostIdentity: () throws -> String) throws -> [String: JSONValue] {
        guard try hostIdentity() == session.identitySignature else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("fx_instance_changed")])
        }
        let plan = try inspect(transport, context: context)
        guard plan["boot"]?.text == session.boot else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("guest_identity_changed")])
        }
        return plan
    }

    static func steam(_ transport: SSHTransport, session: GuestSession, context: CoreContext?) throws -> [String: JSONValue] {
        let result = try transport.run(GuestScripts.steam(boot: session.boot), timeout: 45, context: context)
        guard result.status == 0 else { throw CoreError("STEAM_START_FAILED") }
        let value = try parse(result.stdout, expected: "STEAM_START_FAILED")
        guard value["ok"]?.boolean == true else {
            throw CoreError("STEAM_START_FAILED", ["reason": .string(value["reason"]?.text ?? "unknown")])
        }
        return value
    }

    static func launchGame(_ transport: SSHTransport, session: GuestSession, context: CoreContext?) throws -> [String: JSONValue] {
        let result = try transport.run(GuestScripts.launchGame(boot: session.boot), timeout: 40, context: context)
        guard result.status == 0 else { throw CoreError("GAME_START_FAILED") }
        let value = try parse(result.stdout, expected: "GAME_START_FAILED")
        guard value["ok"]?.boolean == true else {
            throw CoreError("GAME_START_FAILED", ["reason": .string(value["reason"]?.text ?? "unknown")])
        }
        return value
    }

    static func waitForGame(_ transport: SSHTransport, attempts: Int = 90, context: CoreContext?) throws -> Int {
        for _ in 0..<attempts {
            try context?.check()
            Thread.sleep(forTimeInterval: 2)
            let current = try state(transport, context: context)
            if let count = current["game_count"]?.integer, count > 0 { return count }
        }
        throw CoreError("GAME_START_FAILED", ["reason": .string("game_process_not_observed")])
    }
}
