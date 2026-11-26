# Environment pipeline: terrain, water, materials, physics

How Openworld's landscape is made and how to change it. Tools run on a
development computer; only their results ship in the game.

| Piece | What it is | Ships in the game? |
|---|---|---|
| Terrain3D 1.1.0 | terrain plugin (GDExtension), `game/addons/terrain_3d` | yes (Windows x86_64, Android arm64; Linux for CI) |
| FastNoise2 1.1.1 | noise library, used by `tools/world_generation/heightgen` | no: offline only |
| Material Maker 1.8 | material authoring app, `tools/materials/*.ptex` | no: exported PNGs would |
| Jolt Physics | Godot 4.5's built-in Jolt | yes (project setting) |

## Physics: Jolt

`physics/3d/physics_engine = "Jolt Physics"` (project.godot). Chosen after a
side-by-side run of `tests/performance/physics_bench.gd` on the island's real
collision (150 tumbling rocks, 40 walkers, 400 raycasts a step), and every
gameplay suite under both engines:

| | Godot Physics | Jolt |
|---|---|---|
| physics time per step | 16.5-18.6 ms | 8.5-8.6 ms |
| 400 raycasts | 1.8-2.0 ms | 2.5 ms |
| walker sinking into ground | 0.002 m | 0.002 m |
| ray hit vs heightmap (95%) | 0.000 m | 0.012 m |
| ground, horse, combat, sword, expansion, playthrough tests | pass | pass |
| green-valley test (Terrain3D collision) | pass | pass |

Jolt halves the physics cost; raycasts are a little slower but the game casts
few. The player-sinking checks pass on both. To compare again, drop a
`game/override.cfg` containing `[physics]` /
`3d/physics_engine="GodotPhysics3D"` and rerun the bench (delete it after).

## Terrain3D

Installed from the official `Terrain3D_v1.1.0-stable.zip` (Godot 4.5-4.8).
Only the binaries Openworld exports are kept (`terrain.gdextension` lists
them); the plugin is enabled in Project Settings > Plugins. Its sculpting
brushes and extras are left out of exports by the export filter.

To upgrade: replace `game/addons/terrain_3d` with the new release's folder,
delete the binaries for platforms we don't ship, comment their lines in
`terrain.gdextension` (a `;` line, never a trailing comment: Godot rejects
the whole file), then run `godot --headless --import --path game` and the
green-valley test.

### The green-valley test zone

`game/world/test_zone/green_valley.tscn`: 512 x 512 m of FastNoise2 hills
around a valley, a spring-fed brook, a 10 m waterfall into a plunge pool, a
pond, forest, meadow, rocks, the player and a horse. Open it in the editor
(F6), or start the game with `-- --test-zone` (works in exported builds).
`tests/integration/green_valley_test.gd` checks the import, the carved
brook, the waterfall drop, water sitting on the terrain, standing and
walking without sinking, wading, riding and foliage placement (in CI).

The main island still uses its own terrain renderer (`scripts/terrain.gd`):
see "Moving the island to Terrain3D" below.

## Heightmaps (FastNoise2, offline)

```
cmake -S tools/world_generation -B build/worldgen -DCMAKE_BUILD_TYPE=Release
cmake --build build/worldgen
build/worldgen/heightgen tools/world_generation/regions.cfg green_valley game/world/terrain/source
```

`regions.cfg` has one recipe per region (rolling hills, mountains, volcanic,
hollow, farmland), each with its own seed, size, spacing and height range.
Strict floating point is on, so a seed always gives the same file (checked:
identical md5 on rebuild). Output: `<region>.r16` (16-bit heights) and
`<region>.json` (the range), in `game/world/terrain/source/` (not exported).

## Building a Terrain3D zone

```
godot --headless --path game -s res://tools/build_terrain.gd -- res://world/test_zone/green_valley.json
```

Reads the zone JSON and its heightmap, applies the hand-made sculpt (river
valleys and channels along each river's bed line, waterfalls where the bed
steps down, bowls for ponds and plunge pools), imports into Terrain3D,
paints the control map (grass, dry grass on the heights, forest floor in
patches, rock on steep ground, wet rock at falls, mud along water) and
saves the region files to the zone's `data_dir`.

Regenerating never destroys hand-made places: they live in the zone JSON,
not in the generated heightmap, and are applied on every build. To add one,
add it to the JSON (a river's points are `[x, z, bed height]`, downhill;
two points close together with a big drop make a waterfall; `sculpt.pools`
digs a bowl) and rebuild.

## Water

`scripts/water.gd` builds rivers, streams, waterfalls, ponds and lakes from
a description plus a ground-height function, so it works on Terrain3D and on
the island's own terrain alike. Every vertex measures its depth over the
ground: the shader (`shaders/spatial_env_water.gdshader`) shades shallows,
deep water, shore foam and rapids from that, with no screen reads (cheap on
phones). Options: `murk`, `speed`, `rapids`, `frozen` (ice), and waterfalls
get mist particles (fewer on phones) and a 3D roar. Streams murmur along
their length (synthesized sounds, `tools/audio/synth_water.py`). The player
wades (slower, water footsteps) and splashes on entering.

To add water to a place: add a river, fall or lake to its JSON. Rivers:
points `[x, z, bed]` downhill, `width`, `depth`. Falls: `top` and `bottom`
`[x, y, z]`, `width`. Lakes: `center`, `radius`, `level`.

## Materials (Material Maker)

Sources in `tools/materials/` (see its README); export with
`tools/materials/export_materials.sh` on a PC with a GPU. Material Maker
could not run in the cloud environment these were prepared in (no GPU), so
they are not exported yet; the game uses the CC0 Poly Haven sets fetched by
`tools/fetch_vendor.py` meanwhile, graded per region.

## Android

The Android export is arm64 only, and Terrain3D's arm64 libraries ship with
it. Terrain3D has only been exercised in tests and on PC-class software
rendering here, not on a phone; reviews report problems on some Android
devices. The main island therefore keeps its proven terrain on phones.
Before turning Terrain3D on for phones, run `-- --test-zone` on the target
phone and watch frame rate and memory (the test zone already uses fewer
LODs, smaller mesh size, half the grass and fewer mist particles on phones).

## Moving the island to Terrain3D

Not done yet, on purpose: the island's terrain shader carries its regions'
look (snow on ledges, triplanar cliffs, lava glow, Glow Hollow's tint, the
paths) and its LOD, collision and tests are proven on phones. The way
across, keeping every place where it is:

1. Import `game/data/height.bin` (513 x 513, 2 m spacing) into Terrain3D
   with `vertex_spacing = 2` — the same heights, so roads, buildings and
   quest spots stay put; `WorldData.height()` remains the gameplay height.
2. Paint the control map from `biome.bin` and `mask.bin` (zone ground,
   snow, rock on slopes, paths) in `tools/build_terrain.gd`.
3. Port the region effects into a Terrain3D shader override.
4. Run every suite plus a phone test of the test zone, then switch PC first.
