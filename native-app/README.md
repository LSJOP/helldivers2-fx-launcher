# Native App

See the [repository README](../README.md) for requirements, build/install instructions, branch layout and safety limits. Open `HD2FXNative.xcodeproj` for Xcode development. `App/DesignSystem` owns the tactical theme; `Views` owns presentation; `Stores` and `Services` own state and Bridge supervision.

`CoreSnapshot` is a pinned Git submodule of the legacy archive. `script/package_resources.py` packages only `native-app-core-snapshot`'s allowlisted seven modules and VERSION. Runtime protocol and Core source bytes are unchanged; only development/build source location has moved.

Run the existing isolated checks after Bridge/service/packaging changes using `./script/run_checks.sh`. For low-risk UI work, batch edits and use static checks or one focused verification. Do not repeatedly launch the full screenshot sweep. Build output and evidence are ignored.
