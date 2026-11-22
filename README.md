# Openworld

A realistic open-world exploration game for PC and phone (landscape), made with Godot 4.5.

## Play the latest build

1. Open the **Actions** tab on GitHub and tap the newest green **Build game** run.
2. Scroll to **Artifacts**:
   - **Openworld-Android-APK**: download, unzip, and open `Openworld.apk` on your phone. Allow "install unknown apps" if asked.
   - **Openworld-Windows**: download, unzip, and run `Openworld.exe`.

## Controls

| | PC | Phone |
|---|---|---|
| Move | W A S D | Left joystick |
| Look | Mouse (click to lock, Esc to free) | Drag on the right side |
| Sprint | Shift | Orange button |
| Jump | Space | Big white button |

## What's in this first build

The green valley test zone: hills, a winding dirt trail, grass that moves in the wind, oak and pine trees, rocks, snowy mountains, golden-hour sun and haze.
The explorer is a stand-in made of simple shapes; the realistic model comes next.

## Layout

- `game/`: the Godot project (open `game/project.godot` in Godot 4.5)
- `tools/fetch_assets.py`: downloads free CC0 photo textures from Poly Haven during the build
- `.github/workflows/build.yml`: builds Windows and Android on every push
- `.claude/`, `CLAUDE.md`, `project.yaml`: the [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) template (MIT, see `LICENSE-claude-code-game-studios`)
