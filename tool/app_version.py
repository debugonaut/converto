"""Read the shared Flutter package version without an extra build dependency."""
from pathlib import Path
import re


def version_info(root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
                      (root / 'pubspec.yaml').read_text(), re.MULTILINE)
    if match is None:
        raise ValueError('pubspec.yaml must declare a semantic version and build number')
    return match.group(1), int(match.group(2))
