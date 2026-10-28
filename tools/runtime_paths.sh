# Shared by Start.command and the Python/Node installer; Bash 3.2 and zsh.
# Changes apply only to this process, never to shell profiles.
hd2_setup_paths() {
    export PATH="/opt/homebrew/opt/node@24/bin:/opt/homebrew/opt/python@3.14/libexec/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
}

hd2_python_candidates() {
    command -v python3 2>/dev/null || true
    printf '%s\n' /opt/homebrew/opt/python@3.14/libexec/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3
}

hd2_find_python() {
    local candidate
    while IFS= read -r candidate; do
        # Avoid triggering macOS's Command Line Tools installer from its stub.
        if [ "$candidate" = /usr/bin/python3 ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
            continue
        fi
        if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(hd2_python_candidates)
    return 1
}

hd2_find_node() {
    local candidate
    for candidate in "$(command -v node 2>/dev/null)" /opt/homebrew/bin/node /usr/local/bin/node "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"; do
        # Match the existing backend's first-existing-file selection.
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}
