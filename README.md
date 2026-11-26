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
| Brickton | west | a market town (every house can be entered; your own white-stone house by the south gardens; the Church of the Mended Isle further south): main street, market square with stalls and a well, inn, town hall bell tower, north and south residential streets, craft quarter, guarded east gate; 40+ townsfolk who visit the church in the morning, gather at the tavern in the evening and go home at night |

A full day lasts 16 real minutes (`game/data/game_config.json`). The clock is top-left.

## Controls

| | PC | Phone |
|---|---|---|
| Move | W A S D (Ctrl to walk) | Left joystick (push a little to walk) |
| Look | Mouse (click to lock, Esc to free) | Drag on the right side |
| Sprint | Shift | Orange button |
| Jump | Space | White button |
| Attack (3-swing combo) | Left click or F | Red sword button |
| Dodge roll | Q | Blue arrow button |
| Block | Hold right mouse | Hold grey shield button |
| Drink potion | H | Flask button (top right) |
| Talk / use | E | Tap the prompt |
| Get on / off a horse | E next to the horse | Tap the prompt |
| Gallop (on a horse) | Shift | Orange button |
| Dialogue choices | 1, 2, 3 or click | Tap |
| Journal (quests, people, discoveries, lore, notes, inventory, map) | J | Book button (top right) |
| Draw / holster the flintlock | G | Pistol button (right side) |
| Aim / fire the flintlock | Hold right mouse / left click | Pistol drawn: red button fires (auto-aim at the crosshair) |
| Reload | R (or fire when empty) | Reload button (while drawn) |
| Whistle for your horse | T | Horseshoe button (right side) |
| Open / close a door | E at the door | Tap the prompt |
| Sleep until morning (your house) | E at your bed | Tap the prompt |
| Store / take materials (your house) | E at the living-room chests | Tap the prompt |

## What there is to do

- **Main story, The Shattered Island** (after the Elder's first quest): six chapters across all five regions, ending in the Ancient Sanctuary against the Ancient Guardian.
- **10 side quests and 5 special quests** from townsfolk and travellers, or found in the world (an old map, a hole in the ground, a singing crystal).
- **Monster contracts** from Captain Harlan, Brann the hunter and the board in the market square. New ones keep coming; pay grows with your level.
- **Horses**: a white, a black and a brown horse wait at the hitching rail beside the path, just ahead of where you start. Ride at a walk, trot or gallop (about three times running speed). They stay where you leave them, and the save remembers where.
- **Yellow "!"** floats over anyone (or anything, like the contract board or a found map) with a mission for you, and stays visible through buildings and from far away. A blue "?" means someone to report back to.
- **Exploring**: 22 named places (some hidden), 12 treasures (chests, buried caches that need their map, a locked cellar, guarded hoards), 6 shrines with different puzzles, 4 rare bosses with unique weapons, random world events (raids, a travelling merchant, rare creatures, eruptions, travellers in need).
- **Progress**: coins, experience and levels, Brickton reputation, weapons and armour (frost and fire resistance), blacksmith upgrades. Everything saves.
- **Save slots**: every New Game is its own adventure in its own slot; Continue picks up the one you played last, Load Game lists them all (name, level, region, time played, when saved) and lets you rename or delete them. The game saves itself every 30 seconds, at quest steps, when you pause, sleep or quit, and writes each save crash-safely (a damaged save falls back to the previous one). Saves from before slots existed appear as "Adventure 1"; the old file is left as it was.
- **Menus**: a medieval look throughout (Cinzel and Alegreya fonts, gold-framed panels, a parchment journal with People, Discoveries, Lore and Notes pages, a sepia map you can drag and zoom). Settings has Display, Graphics, Audio, Gameplay, Controls and Accessibility pages (text size, reduced motion) with Apply, Cancel and Reset.

Design notes: `design/gdd/chapter-one.md`. Content is generated from `tools/content/*.py` into `game/data/`.

## How it's built

- `game/`: the Godot project. `data/` holds the baked island (`tools/bake_world.gd` regenerates it) and tunable values.
- Ground is drawn by the GPU from the baked height map, with less detail far away.
- Grass travels with the player, so phones only draw what is close.
- Phones render at a lower resolution that rises or falls to keep the frame rate steady.
- `tools/fetch_vendor.py` + `tools/asset_manifest.json`: the **Fetch assets** workflow downloads the CC0 assets and stores them on the `assets` branch; builds copy them in.
- Combat animations for the explorer are authored on his skeleton by `tools/bake_anims.gd` (swings, guard, block, hit, death, talking); monsters animate procedurally with per-species attack moves (`data/creatures.json`).
- `.github/workflows/build.yml`: runs the world, combat and full-playthrough tests and builds Windows and Android on every push.
- `.claude/`, `CLAUDE.md`, `project.yaml`: the [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) template (MIT, see `LICENSE-claude-code-game-studios`).
- `.claude/skills/` also holds the Godot skills from [GodotPrompter](https://github.com/jame581/godotprompter) (MIT, see `LICENSE-godotprompter`).

## Credits (all CC0)

- Explorer body and animations: Quaternius (Universal Base Characters, Universal Animation Library), via the Quaternius_IK_Rigged pack by jamesonBradfield.
- Textures, rocks and plants: Poly Haven (see `tools/asset_manifest.json`).
