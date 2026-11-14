#!/usr/bin/env python3
"""Compile and exercise the same evidence resolver used by the actual Dashboard."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='hd2-dashboard-matrix-') as directory:
    binary = Path(directory) / 'DashboardStatusChecks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macos14.0',
                    '-sdk', sdk, '-module-cache-path', str(root / 'build/ModuleCache'),
                    str(root / 'Models/BridgeModels.swift'), str(root / 'Models/LaunchSession.swift'),
                    str(root / 'checks/DashboardStatusChecks.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
