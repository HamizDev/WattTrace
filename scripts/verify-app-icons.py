#!/usr/bin/env python3
"""Validate both new icon appearances and prevent the old composer asset overriding them."""
import json
import struct
from pathlib import Path

root = Path(__file__).resolve().parent.parent

def validate_png(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", path
    assert struct.unpack(">II", data[16:24]) == (1024, 1024), path
    assert data[24:26] == bytes([8, 2]), f"Expected opaque RGB PNG: {path}"
    return data

ios = root / "MiniWatts/Assets.xcassets/AppIcon.appiconset"
watch = root / "WatchApp/Assets.xcassets/AppIcon.appiconset"
for target in ("MiniWatts", "WatchApp"):
    assert not (root / target / "AppIcon.icon").exists(), f"Old icon override: {target}"
images = json.loads((ios / "Contents.json").read_text())["images"]
assert len(images) == 2
assert images[0]["filename"] == "AppIcon-Light.png" and not images[0].get("appearances")
assert images[1]["filename"] == "AppIcon-Dark.png"
assert images[1]["appearances"] == [{"appearance": "luminosity", "value": "dark"}]
assert all(i["platform"] == "ios" and i["size"] == "1024x1024" for i in images)
light = validate_png(ios / "AppIcon-Light.png")
dark = validate_png(ios / "AppIcon-Dark.png")
assert light != dark
watch_images = json.loads((watch / "Contents.json").read_text())["images"]
assert len(watch_images) == 1 and watch_images[0]["platform"] == "watchos"
assert watch_images[0]["filename"] == "AppIcon-Dark.png"
assert validate_png(watch / "AppIcon-Dark.png") == dark
assert validate_png(root / "docs/icon.png") == light
print("iOS light/dark and watchOS opaque 1024x1024 icon assets verified")
