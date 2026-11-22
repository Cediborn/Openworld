#!/usr/bin/env python3
"""Download third-party CC0 assets listed in tools/asset_manifest.json into vendor/.

Runs in GitHub Actions (fetch-assets workflow), which commits vendor/ to the
`assets` branch. The game build then copies it into game/assets/vendor/.
Also saves the Poly Haven catalogues so we can pick assets by name.
"""
import io
import json
import pathlib
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "vendor"
UA = {"User-Agent": "openworld-build/1.0"}
API = "https://api.polyhaven.com"


def fetch(url, timeout=300):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_json(url):
    return json.loads(fetch(url, 60))


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def polyhaven_asset(asset_id, kind, res, out_dir, log):
    """kind: textures | models | hdris. Saves the gltf (+bin, textures) or maps."""
    files = get_json(f"{API}/files/{asset_id}")
    dest = out_dir / asset_id
    if kind == "models":
        g = files["gltf"][res]["gltf"]
        gltf_bytes = fetch(g["url"])
        for rel, info in g.get("include", {}).items():
            save(dest / rel, fetch(info["url"]))
        # JPEG colour maps lose the leaf cut-outs; fetch PNG versions with alpha.
        swapped = []
        for key, val in files.items():
            if key in ("gltf", "fbx", "blend", "usd") or not isinstance(val, dict):
                continue
            if "diff" not in key.lower():
                continue
            png = val.get(res, {}).get("png")
            if not png:
                continue
            name = png["url"].rsplit("/", 1)[-1]
            save(dest / "textures" / name, fetch(png["url"]))
            swapped.append(name)
        text = gltf_bytes.decode("utf-8")
        for name in swapped:
            text = text.replace("textures/" + name[:-4] + ".jpg", "textures/" + name)
        save(dest / f"{asset_id}.gltf", text.encode("utf-8"))
        save(OUT / "catalogues" / "files" / f"{asset_id}.json", json.dumps(files, indent=1).encode())
    elif kind == "hdris":
        save(dest / f"{asset_id}.hdr", fetch(files["hdri"][res]["hdr"]["url"]))
    else:
        for key, name in (("Diffuse", "albedo"), ("nor_gl", "normal"), ("Rough", "rough"), ("AO", "ao"), ("arm", "arm")):
            if key in files and res in files[key]:
                save(dest / f"{name}.jpg", fetch(files[key][res]["jpg"]["url"]))
    log.append(f"polyhaven {kind} {asset_id} {res}")


def main():
    manifest = json.loads((ROOT / "tools" / "asset_manifest.json").read_text())
    log = []
    cat_dir = OUT / "catalogues"
    for t in ("textures", "models", "hdris"):
        try:
            data = get_json(f"{API}/assets?t={t}")
            slim = {k: {"name": v.get("name"), "categories": v.get("categories"), "tags": v.get("tags"),
                        "polycount": v.get("polycount"), "dimensions": v.get("dimensions")} for k, v in data.items()}
            save(cat_dir / f"polyhaven_{t}.json", json.dumps(slim, indent=1).encode())
        except Exception as e:
            log.append(f"FAILED catalogue {t}: {e}")

    for item in manifest.get("polyhaven", []):
        try:
            polyhaven_asset(item["id"], item["type"], item.get("res", "1k"), OUT / "polyhaven" / item["type"], log)
        except Exception as e:
            log.append(f"FAILED polyhaven {item}: {e}")

    for item in manifest.get("zips", []):
        try:
            data = fetch(item["url"], 600)
            z = zipfile.ZipFile(io.BytesIO(data))
            prefix = item.get("keep_prefix", "")
            dest = OUT / item["name"]
            n = 0
            for info in z.infolist():
                if info.is_dir() or not info.filename.startswith(prefix):
                    continue
                if any(info.filename.lower().endswith(x) for x in item.get("skip_ext", [])):
                    continue
                save(dest / info.filename[len(prefix):], z.read(info))
                n += 1
            log.append(f"zip {item['name']}: {n} files")
        except Exception as e:
            log.append(f"FAILED zip {item.get('name')}: {e}")

    save(OUT / "FETCH_LOG.txt", ("\n".join(log) + "\n").encode())
    print("\n".join(log))


if __name__ == "__main__":
    main()
