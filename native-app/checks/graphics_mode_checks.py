"""Offline checks for the format-sensitive graphics transaction boundaries."""
from pathlib import Path
import json
import runpy
import tempfile
import unittest

MODULE = runpy.run_path(str(Path(__file__).parents[1] / "Resources/graphics-mode-guest.txt"))
SCOPE = MODULE["audio_card"].__globals__


class GraphicsChecks(unittest.TestCase):
    def test_launch_options_preserve_the_command(self):
        original = 'FEX_DISKCACHE=0 PROTON_LOG_DIR="/path with space" %command%'
        self.assertEqual(MODULE["dx11_options"](original), original + " --use-d3d11")
        for invalid in ("--use-d3d11 %command%", "%command% | tee log", "prefix%command%"):
            with self.assertRaises(MODULE["Refused"]):
                MODULE["dx11_options"](invalid)

    def test_taa_edit_is_scoped(self):
        original = ("resolution = [1920 1080]\r\nrender_settings = {\r\n\tupscaling_method = 2\r\n"
                    "\trender_resolution_factor_index = 3\r\n}\r\nv_sync = false\r\n")
        updated = MODULE["edit_taa"](original, "0")
        self.assertEqual(updated, original.replace("method = 2", "method = 0"))
        self.assertEqual(MODULE["edit_taa"](updated, "2"), original)
        for invalid in ("", original + "upscaling_method = 1\n"):
            with self.assertRaises(MODULE["Refused"]):
                MODULE["edit_taa"](invalid, "0")

    def test_restore_preserves_new_steam_options(self):
        original = "FEX_DISKCACHE=0 %command% --custom"
        dx11 = MODULE["dx11_options"](original)
        record = {"launch": original, "launch_dxmt": dx11}
        self.assertEqual(MODULE["restore_options"](dx11, record), original)
        self.assertEqual(MODULE["restore_options"](dx11 + ' --new "two words"', record),
                         original + ' --new "two words"')
        with self.assertRaises(MODULE["Refused"]):
            MODULE["restore_options"]("--use-d3d11 %command% --custom", record)

    def test_config_transfer_retries_after_rename_and_retains_both_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, target, receipt = [root / name for name in ("current", "parked", "receipt")]
            source.write_text("latest settings")
            target.write_text("previous settings")
            before = [MODULE["sha"](path) for path in (source, target)]
            staging = root / "staging"
            # Simulate the state after the atomic exchange and before receipt completion.
            source.rename(staging)
            target.rename(source)
            staging.rename(target)
            record = {"settings_dx12": before}
            MODULE["carry_settings"](source, target, receipt, record, "dx12")
            self.assertEqual(record["settings_dx12"], "complete")
            self.assertEqual((target.read_text(), source.read_text()), ("latest settings", "previous settings"))
            target.write_text("changed after completion")
            MODULE["carry_settings"](source, target, receipt, record, "dx12")
            self.assertEqual(target.read_text(), "changed after completion")

    def test_config_handoff_to_empty_prefix_and_conflict(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, target, receipt = [root / name for name in ("current", "parked", "receipt")]
            source.write_text("latest")
            MODULE["carry_settings"](source, target, receipt, {}, "dx11")
            self.assertFalse(source.exists())
            self.assertEqual(target.read_text(), "latest")
            source.write_text("edited")
            with self.assertRaises(MODULE["Refused"]):
                MODULE["carry_settings"](source, target, receipt, {"settings_dx12": ["unknown", None]}, "dx12")
            self.assertEqual((source.read_text(), target.read_text()), ("edited", "latest"))

    def test_only_default_virtio_output_is_selected(self):
        selected = {"name": "pci-virtio-card", "active_profile": "duplex", "profiles": {
            "output:real-time": {"sinks": 1, "sources": 0, "available": True},
            "output:unavailable": {"sinks": 1, "sources": 0, "available": False},
            "duplex": {"sinks": 1, "sources": 1, "available": True},
        }}
        cards = [selected, {**selected, "name": "unrelated"}]
        sinks = [{"name": "headphones", "monitor_source": "monitor", "properties": {
            "device.name": selected["name"]
        }}]
        sources = [{"name": "monitor", "mute": False}]
        original = SCOPE["run"]
        try:
            def response(*args, **_kwargs):
                return "headphones" if args[-1] == "get-default-sink" else json.dumps({
                    "sinks": sinks, "cards": cards, "sources": sources
                }[args[-1]])
            SCOPE["run"] = response
            self.assertEqual(MODULE["audio_card"](), ("pci-virtio-card", "duplex", "output:real-time", "monitor", False))
            sinks[0]["properties"]["device.name"] = "unrelated"
            with self.assertRaises(MODULE["Refused"]):
                MODULE["audio_card"]()
        finally:
            SCOPE["run"] = original

    def test_atomic_file_writer_refuses_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            real = Path(tmp) / "real"
            real.write_text("original")
            alias = real.with_name("alias")
            alias.symlink_to(real)
            with self.assertRaises(MODULE["Refused"]):
                MODULE["write"](alias, "changed")
            self.assertEqual(real.read_text(), "original")
            MODULE["write"](real, "safe")
            self.assertEqual(real.read_text(), "safe")

    def test_reapplies_only_the_verified_monitor_mute_after_reboot(self):
        record = {"card": "virtio", "audio": "duplex", "output": "output:stereo", "monitor": "analog.monitor"}
        mute = False
        commands = []
        original = SCOPE["run"], SCOPE["audio_card"]
        try:
            def set_mute(*args):
                nonlocal mute
                if args[-1] == "sources":
                    return json.dumps([{"name": "analog.monitor", "index": 1}])
                if args[-1] == "source-outputs":
                    return json.dumps([{"source": 1}])
                commands.append(args)
                mute = True

            SCOPE["run"] = set_mute
            SCOPE["audio_card"] = lambda: ("virtio", "output:stereo", "output:stereo", "analog.monitor", mute)
            MODULE["apply_output_audio"](record)
            MODULE["apply_output_audio"](record)
            self.assertEqual(commands, [("pactl", "set-source-mute", "analog.monitor", "1")])
            with self.assertRaises(MODULE["Refused"]):
                MODULE["apply_output_audio"]({**record, "monitor": "unrelated.monitor"})
            self.assertEqual(len(commands), 1)
        finally:
            SCOPE["run"], SCOPE["audio_card"] = original

    def test_dxmt_native_dll_preserves_every_byte_except_builtin_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp) / "payload.dll"
            live = Path(tmp) / "live.dll"
            data = bytes(range(96))
            payload.write_bytes(data)
            live.write_bytes(data)
            self.assertFalse(MODULE["native_d3d11_matches"](payload, live))
            live.write_bytes(data[:64] + bytes(16) + data[80:])
            self.assertTrue(MODULE["native_d3d11_matches"](payload, live))


if __name__ == "__main__":
    unittest.main()
