#!/usr/bin/env python3
"""
scripts/update_altstore.py
Automatically updates AltStore / LiveContainer source (apps.json)
with the latest release info from getsentrix/LSpoof.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

REPO_NAME = "getsentrix/LSpoof"
REPO_URL = f"https://github.com/{REPO_NAME}"
PAGES_URL = "https://getsentrix.github.io/LSpoof/"
RAW_CONTENT_URL = "https://raw.githubusercontent.com/getsentrix/LSpoof/main"

def get_latest_release_info():
    """Fetch latest release info via gh CLI or fallback to local defaults."""
    try:
        cmd = ["gh", "release", "view", "--repo", REPO_NAME, "--json", "tagName,publishedAt,body,assets"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        
        tag = data.get("tagName", "v1.1.1")
        version = tag.lstrip("v")
        published_at = data.get("publishedAt", datetime.now(timezone.utc).isoformat())
        body = data.get("body", "Latest stability and UI release.")
        
        dylib_size = 449768
        dylib_url = f"{REPO_URL}/releases/download/{tag}/LocationSpoofer.dylib"
        
        for asset in data.get("assets", []):
            if asset.get("name") == "LocationSpoofer.dylib":
                dylib_size = asset.get("size", dylib_size)
                dylib_url = asset.get("url", dylib_url)
                break
                
        return {
            "version": version,
            "tag": tag,
            "date": published_at,
            "body": body,
            "size": dylib_size,
            "downloadURL": dylib_url
        }
    except Exception as e:
        print(f"Notice: gh CLI query failed ({e}); checking fallback...", file=sys.stderr)
        return {
            "version": "1.1.1",
            "tag": "v1.1.1",
            "date": "2026-10-01T03:08:40Z",
            "body": "v1.1.1: Retained static cell architecture, Apple SF Symbol badges, native Inset Grouped UI, and glitch-free coordinate typing.",
            "size": 449768,
            "downloadURL": f"{REPO_URL}/releases/download/v1.1.1/LocationSpoofer.dylib"
        }

def generate_altstore_source(info):
    icon_url = f"{RAW_CONTENT_URL}/docs/assets/icon.png"
    
    first_paragraph = info["body"].strip().split("\n\n")[0] if info["body"] else ""
    summary = first_paragraph.replace("#", "").strip()
    if len(summary) > 280:
        summary = summary[:277] + "..."
    if not summary:
        summary = f"v{info['version']}: Modern Inset Grouped UI polish, Apple SF Symbols, and glitch-free coordinate typing."

    source_data = {
        "name": "LSpoof Repo",
        "identifier": "com.sentrix.lspoof.repo",
        "subtitle": "Universal iOS Location Spoofer",
        "description": "Official community repository for LSpoof — no-jailbreak iOS location spoofer dylib with modern Inset Grouped UI for LiveContainer, Sideloadly, and TrollStore.",
        "iconURL": icon_url,
        "website": PAGES_URL,
        "apps": [
            {
                "name": "Location Spoofer",
                "bundleIdentifier": "com.sentrix.lspoof",
                "developerName": "getsentrix",
                "subtitle": "Universal GPS Spoofer for iOS",
                "version": info["version"],
                "versionDate": info["date"],
                "versionDescription": summary,
                "downloadURL": info["downloadURL"],
                "localizedDescription": "Universal GPS, altitude, and heading spoofer for sideloaded iOS apps. Features draggable pins, real-time route simulation along Apple Maps road networks, randomized GPS drift fluctuation, and a native iOS 16+ Inset Grouped interface.",
                "iconURL": icon_url,
                "tintColor": "007AFF",
                "size": info["size"],
                "screenshotURLs": [
                    f"{RAW_CONTENT_URL}/docs/assets/preview-static.png"
                ]
            }
        ],
        "news": [
            {
                "title": f"LSpoof v{info['version']} Released",
                "identifier": f"lspoof-release-{info['version']}",
                "caption": "Modern Inset Grouped UI, Apple SF Symbols & Stability Polish",
                "date": info["date"],
                "tintColor": "007AFF",
                "imageURL": icon_url,
                "url": f"{REPO_URL}/releases/tag/{info['tag']}"
            }
        ]
    }
    return source_data

def main():
    parser = argparse.ArgumentParser(description="Update AltStore / LiveContainer source JSON")
    parser.add_argument("--version", help="Explicit version override (e.g. 1.1.1)")
    parser.add_argument("--tag", help="Explicit tag override (e.g. v1.1.1)")
    parser.add_argument("--size", type=int, help="Explicit file size in bytes")
    parser.add_argument("--url", help="Explicit download URL override")
    args = parser.parse_args()

    info = get_latest_release_info()
    if args.version:
        info["version"] = args.version
    if args.tag:
        info["tag"] = args.tag
    if args.size:
        info["size"] = args.size
    if args.url:
        info["downloadURL"] = args.url

    source = generate_altstore_source(info)

    # Save to docs/apps.json and apps.json
    paths = [
        os.path.join("docs", "apps.json"),
        "apps.json"
    ]
    for p in paths:
        os.makedirs(os.path.dirname(p) if os.path.dirname(p) else ".", exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(source, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Updated {p} for version v{info['version']} ({info['size']} bytes)")

if __name__ == "__main__":
    main()
