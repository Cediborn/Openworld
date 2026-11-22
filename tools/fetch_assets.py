#!/usr/bin/env python3
"""Download free CC0 photo textures from Poly Haven into game/assets/polyhaven/.

Runs in GitHub Actions (Claude's workspace can't reach Poly Haven).
If anything fails, the game falls back to its procedural colours, so the
build never breaks because of this script.
"""
import json
import pathlib
import sys
import urllib.request

OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "polyhaven"
API = "https://api.polyhaven.com"
RES = "2k"

# For each ground layer: preferred Poly Haven texture ids, then a keyword to search for.
WANTED = {
    "grass": (["aerial_grass_rock", "forest_ground_04", "grass_path_2"], "grass"),
    "path": (["brown_mud_leaves_01", "forest_ground_01", "dirt"], "dirt"),
    "rock": (["rocky_terrain_02", "rock_face", "aerial_rocks_02"], "rock"),
}
MAPS = {"albedo": "Diffuse", "normal": "nor_gl"}


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "openworld-build/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": "openworld-build/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        dest.write_bytes(r.read())


def files_for(asset_id):
    try:
        return get_json(f"{API}/files/{asset_id}")
    except Exception:
        return None


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        catalogue = get_json(f"{API}/assets?t=textures")
    except Exception as e:
        print(f"Poly Haven unreachable ({e}); using procedural ground.")
        return 0
    credits = []
    for kind, (ids, keyword) in WANTED.items():
        candidates = [i for i in ids if i in catalogue]
        candidates += sorted(i for i in catalogue if keyword in i and i not in candidates)
        for asset_id in candidates:
            files = files_for(asset_id)
            if not files:
                continue
            try:
                for name, key in MAPS.items():
                    url = files[key][RES]["jpg"]["url"]
                    download(url, OUT / f"{kind}_{name}.jpg")
                credits.append(f"{kind}: {asset_id} (https://polyhaven.com/a/{asset_id})")
                print(f"{kind}: {asset_id}")
                break
            except Exception as e:
                print(f"{kind}: {asset_id} failed ({e}), trying next")
    (OUT / "CREDITS.txt").write_text("Poly Haven, CC0\n" + "\n".join(credits) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
