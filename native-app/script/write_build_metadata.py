#!/usr/bin/env python3
"""Build-phase metadata. The installed App never needs Git or source access."""
import datetime, json, os, pathlib, subprocess
root = pathlib.Path(__file__).resolve().parents[2]
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
commit = git('rev-parse', 'HEAD')
# Include tracked source edits; ignore local build/evidence caches.
dirty = bool(git('status', '--porcelain'))
internal = os.environ.get('HD2FX_INTERNAL_BUILD') == 'YES'
if os.environ['CONFIGURATION'] == 'Release' and dirty and not internal:
    raise SystemExit('Release metadata requires a clean committed source snapshot')
now = datetime.datetime.now(datetime.timezone.utc)
metadata = {
    'version': os.environ['MARKETING_VERSION'],
    'build': os.environ['CURRENT_PROJECT_VERSION'],
    'commit': commit, 'source_dirty': dirty, 'internal_test_build': internal,
    'built_at': now.isoformat(timespec='seconds'),
    'core_version': (root/'native-app/Core/VERSION').read_text().strip(),
    'configuration': os.environ['CONFIGURATION'],
}
out = pathlib.Path(os.environ['TARGET_BUILD_DIR'])/os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']/'BuildMetadata.json'
out.write_text(json.dumps(metadata, indent=2)+'\n')
