"""Observe real CLI lock acquisition without replacing the locking primitive."""

import fcntl
import os
from pathlib import Path

flock = fcntl.flock
probe = Path(os.environ["MEMORY_LOCK_PROBE"])


def observed_flock(file, operation):
    if operation == fcntl.LOCK_EX:
        probe.with_suffix(".attempt").touch()
    result = flock(file, operation)
    if operation == fcntl.LOCK_EX:
        probe.with_suffix(".acquired").touch()
    return result


fcntl.flock = observed_flock
