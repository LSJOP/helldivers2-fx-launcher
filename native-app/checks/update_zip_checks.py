"""Exercise ZIP metadata validation on real archives before extraction."""
import pathlib
import subprocess
import tempfile
import unittest
import zipfile

APP = pathlib.Path(__file__).resolve().parents[1]


class ZIPChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.directory = pathlib.Path(cls.scratch.name)
        source = cls.directory / "Main.swift"
        source.write_text("""
import Foundation
enum NativeUpdateFailure: Error { case integrity }
@main struct Check {
    static func main() {
        do {
            try UpdateZIPPreflight.validate(URL(fileURLWithPath: CommandLine.arguments[1]))
        } catch { exit(1) }
    }
}
""")
        cls.executable = cls.directory / "check"
        subprocess.run(["xcrun", "swiftc", str(APP / "UpdateHelper/ArchivePathPolicy.swift"),
                        str(APP / "UpdateHelper/UpdateZIPPreflight.swift"), str(source),
                        "-o", str(cls.executable)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def archive(self, entries):
        archive = self.directory / "fixture.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
            for name, data in entries:
                output.writestr(name, data)
        return archive

    def accepted(self, archive):
        return subprocess.run([str(self.executable), str(archive)], timeout=15).returncode == 0

    def test_valid_compressed_app(self):
        self.assertTrue(self.accepted(self.archive([("HD2FXNative.app/Contents/Info.plist", "plist")])))

    def test_traversal(self):
        self.assertFalse(self.accepted(self.archive([("HD2FXNative.app/../../escape", "bad")])))

    def test_case_collision(self):
        self.assertFalse(self.accepted(self.archive([("HD2FXNative.app/A", "a"), ("HD2FXNative.app/a", "b")])))

    def test_local_directory_name_disagreement(self):
        archive = self.archive([("HD2FXNative.app/A", "data")])
        data = bytearray(archive.read_bytes())
        data[30] = ord("X")
        archive.write_bytes(data)
        self.assertFalse(self.accepted(archive))

    def test_framework_symlinks(self):
        link = zipfile.ZipInfo("HD2FXNative.app/Contents/Frameworks/F.framework/Versions/Current")
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        self.assertTrue(self.accepted(self.archive([
            ("HD2FXNative.app/Contents/Frameworks/F.framework/Versions/A/F", "binary"),
            (link, "A"),
        ])))

    def test_escaping_symlink(self):
        link = zipfile.ZipInfo("HD2FXNative.app/link")
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        self.assertFalse(self.accepted(self.archive([(link, "../../escape")])))

    def test_truncated_directory(self):
        archive = self.archive([("HD2FXNative.app/file", "data")])
        archive.write_bytes(archive.read_bytes()[:-6])
        self.assertFalse(self.accepted(archive))


if __name__ == "__main__":
    unittest.main()
