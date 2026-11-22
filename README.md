# Openworld

A realistic open-world exploration game for PC and phone (landscape), made with Godot 4.5.

## Play the latest build

1. Open the **Actions** tab on GitHub and tap the newest green **Build game** run.
2. Scroll to **Artifacts**:
   - **Openworld-Android-APK**: download, unzip, and open `Openworld.apk` on your phone. Allow "install unknown apps" if asked.
   - **Openworld-Windows**: download, unzip, and run `Openworld.exe`.

A new build is not pushed to your phone automatically: install each new APK the same way.
It replaces the old version in place.

## The island

| Zone | Where | What's there |
|---|---|---|
| Hub Meadow | centre (spawn) | grass, wildflowers, oaks, a loop trail; fireflies at night |
| Frost Peaks | north | snowy pines, a mountain pass, falling snow, aurora at night |
| Ember Wastes | east | black basalt, lava rivers, rising embers, smoky haze |
| Glow Hollow | south | giant glowing mushrooms, crystals, blue grass that shines at night |
| Brickton | west | timber-framed houses on a cobbled street, lit windows at night |

A full day lasts 16 real minutes (`game/data/game_config.json`). The clock is top-left.

## Controls

| | PC | Phone |
|---|---|---|
| Move | W A S D (Ctrl to walk) | Left joystick (push a little to walk) |
| Look | Mouse (click to lock, Esc to free) | Drag on the right side |
| Sprint | Shift | Orange button |
| Jump | Space | White button |

## How it's built

- `game/`: the Godot project. `data/` holds the baked island (`tools/bake_world.gd` regenerates it) and tunable values.
- Ground is drawn by the GPU from the baked height map, with less detail far away.
- Grass travels with the player, so phones only draw what is close.
- Phones render at a lower resolution that rises or falls to keep the frame rate steady.
- `tools/fetch_vendor.py` + `tools/asset_manifest.json`: the **Fetch assets** workflow downloads the CC0 assets and stores them on the `assets` branch; builds copy them in.
- `.github/workflows/build.yml`: runs the world tests and builds Windows and Android on every push.
- `.claude/`, `CLAUDE.md`, `project.yaml`: the [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) template (MIT, see `LICENSE-claude-code-game-studios`).

## Credits (all CC0)

- Explorer body and animations: Quaternius (Universal Base Characters, Universal Animation Library), via the Quaternius_IK_Rigged pack by jamesonBradfield.
- Textures, rocks and plants: Poly Haven (see `tools/asset_manifest.json`).
