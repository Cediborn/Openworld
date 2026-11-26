#!/usr/bin/env bash
# Exports Openworld's Material Maker materials (*.ptex in this folder) to
# game/assets/environment/materials/<name>/ as PNG maps plus a Godot .tres.
# Material Maker is a desktop authoring tool (https://materialmaker.org, MIT),
# not a game dependency: run this on a development PC with a GPU.
#
#   MATERIAL_MAKER=/path/to/material_maker ./tools/materials/export_materials.sh [1024]
#
# Size defaults to 1024 (phones read 1024 or smaller well); the generated
# folders are imported by Godot with mipmaps and VRAM compression.
set -euo pipefail
cd "$(dirname "$0")/../.."
MM="${MATERIAL_MAKER:-material_maker}"
OUT=game/assets/environment/materials
mkdir -p "$OUT"
for f in tools/materials/*.ptex; do
  name=$(basename "$f" .ptex)
  mkdir -p "$OUT/$name"
  "$MM" --export-material --target Godot -o "$OUT/$name" "$f"
  echo "exported $name"
done
