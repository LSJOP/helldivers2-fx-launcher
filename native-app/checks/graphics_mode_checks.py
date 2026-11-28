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
        original = "resolution = [1920 1080]\nrender_settings = {\n\tupscaling_method = 2\n}\nv_sync = false\n"
        updated = MODULE["settings_text"](original)
        self.assertEqual(updated, original.replace("method = 2", "method = 0"))
        self.assertEqual(MODULE["settings_text"](updated), updated)
        for invalid in ("", original + "upscaling_method = 1\n"):
            with self.assertRaises(MODULE["Refused"]):
                MODULE["settings_text"](invalid)

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


if __name__ == "__main__":
    unittest.main()
