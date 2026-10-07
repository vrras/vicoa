#!/usr/bin/env python3
"""Self-check for the STORAGE_DIR local backend in shared.storage.

Run from backend/ inside the image or venv:
    python scripts/check-local-storage.py
Exits 0 when local put/get/delete round-trips and bad keys are rejected.
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

# Force the local backend before shared.settings reads the environment.
os.environ["STORAGE_DIR"] = tempfile.mkdtemp(prefix="vicoa-storage-check-")
os.environ.pop("AWS_ACCESS_KEY_ID", None)
os.environ.pop("AWS_SECRET_ACCESS_KEY", None)

from shared import storage  # noqa: E402

assert storage._use_local(), "local backend not selected — check STORAGE_DIR/AWS_*"

KEY = "attachments/00000000-0000-0000-0000-000000000000/check.png"

storage.upload_attachment(KEY, b"png-bytes", "image/png")
data, ctype = storage.download_object(KEY)
assert (data, ctype) == (b"png-bytes", "image/png"), (data, ctype)
assert storage.download_attachment(KEY) == b"png-bytes"
storage.delete_object(KEY)
try:
    storage.download_attachment(KEY)
    raise SystemExit("FAIL: deleted key still readable")
except FileNotFoundError:
    pass

for bad in ("../escape", "/absolute"):
    try:
        storage._local_path(bad)
        raise SystemExit(f"FAIL: bad key accepted: {bad}")
    except ValueError:
        pass

print("local storage check OK:", os.environ["STORAGE_DIR"])
