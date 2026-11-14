#!/usr/bin/env python3
"""Exercise the exact Swift LED priority function with all input combinations."""
from pathlib import Path
import re, subprocess, tempfile
source = (Path(__file__).resolve().parents[1] / 'Views/DashboardView.swift').read_text()
match = re.search(r'    static func resolve\(processing: Bool, failed: Bool, confirmed: Bool\) -> Tone \{.*?\n    \}', source, re.S)
assert match
assert 'let detectedEAC = false' in source
assert 'statusCard(state.t("ui.191"), "person.2", "multiplayer", nil)' in source
assert 'let tone = DashboardLED.resolve(processing: processing, failed: failed, confirmed: connected || detectedEAC)' in source
swift = '''enum Tone { case success, working, failed, unknown }
struct DashboardLED {
''' + match.group(0) + '''
}
for processing in [false, true] {
 for failed in [false, true] {
  for confirmed in [false, true] {
   let expected: Tone = processing ? .working : failed ? .failed : confirmed ? .success : .unknown
   precondition(DashboardLED.resolve(processing: processing, failed: failed, confirmed: confirmed) == expected)
  }
 }
}
print("PASS: 8 LED priority combinations; EAC and multiplayer cannot imply success")
'''
with tempfile.TemporaryDirectory() as directory:
    path=Path(directory)/'matrix.swift'; path.write_text(swift)
    subprocess.run(['swift',str(path)],check=True)
