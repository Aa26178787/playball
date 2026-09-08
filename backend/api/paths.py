"""Filesystem and public URL settings shared by API modules."""
import os
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parent.parent
STATIC_DIR = Path(os.environ.get("STATIC_DIR", BACKEND_DIR / "static")).resolve()
PUBLIC_BASE_URL = os.environ.get(
    "PUBLIC_BASE_URL", "https://playball.duckdns.org"
).rstrip("/")


def static_subdir(name: str) -> Path:
    path = STATIC_DIR / name
    path.mkdir(parents=True, exist_ok=True)
    return path
