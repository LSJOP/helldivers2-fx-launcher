"""Per-user process lock; stale files are harmless and no process is terminated."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path


@contextmanager
def claim(settings_file):
    path=Path(settings_file).with_name('launcher.lock')
    path.parent.mkdir(parents=True,exist_ok=True)
    flags=os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0)
    fd=os.open(path,flags,0o600)
    try:
        try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        os.fchmod(fd,0o600)
        os.ftruncate(fd,0)
        os.write(fd,json.dumps({'pid':os.getpid()}).encode())
        yield True
    finally:
        os.close(fd)  # OS releases the lock even after a crash; never unlink it.
