import Foundation

@main struct UpdateArchivePathChecks {
    static func main() throws {
        typealias Entry = UpdateArchiveEntry
        let root = "HD2FXNative.app"
        func e(_ p: String, _ kind: Entry.Kind) -> Entry { Entry(path: root + "/" + p, kind: kind) }
        func rejects(_ entries: [Entry]) -> Bool { do { try UpdateArchivePathPolicy.validate(entries, expectedRoot: root); return false } catch { return true } }
        let valid: [Entry] = [e("Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle", .file),
            e("Contents/Frameworks/Sparkle.framework/Versions/Current", .symbolicLink("A")),
            e("Contents/Frameworks/Sparkle.framework/Sparkle", .symbolicLink("Versions/Current/Sparkle"))]
        try UpdateArchivePathPolicy.validate(valid, expectedRoot: root)
        precondition(rejects(valid + [Entry(path: "../escape", kind: .file)]))
        precondition(rejects(valid + [e("../escape", .file)]))
        precondition(rejects(valid + [e("escape", .symbolicLink("../../outside"))]))
        precondition(rejects(valid + [e("Contents/Frameworks/Sparkle.framework/Versions/Current/injected", .file)]))
        precondition(rejects(valid + [e("cycle1", .symbolicLink("cycle2")), e("cycle2", .symbolicLink("cycle1"))]))
        precondition(rejects(valid + [e("missing", .symbolicLink("no-such-file"))]))
        precondition(rejects(valid + [e("Contents/frameworks/sparkle.framework/versions/a/SPARKLE", .file)]))
        precondition(rejects(valid + [Entry(path: "/tmp/evil", kind: .file)]))
        precondition(rejects(valid + [e("bad\\name", .file)]))
        precondition(rejects(valid + [e("Contents/A/x", .file), e("Contents/a/y", .file)]))
        precondition(rejects(valid + [e("Contents/é/x", .file), e("Contents/e\u{301}/y", .file)]))
        precondition(rejects(valid + [Entry(path: root, kind: .file)]))
        precondition(rejects(valid + [Entry(path: root, kind: .symbolicLink("Contents"))]))
        precondition(rejects(valid + [e("Contents/Foo", .file), e("Contents/link", .symbolicLink("foo"))]))
        try UpdateArchivePathPolicy.validate(valid + [Entry(path: root, kind: .directory)], expectedRoot: root)
        print("PASS archive path preflight: framework links and 14 malicious cases")
    }
}
