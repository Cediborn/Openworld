# Openworld material library (Material Maker sources)

Each `.ptex` here is a Material Maker graph. They started from Material
Maker's own MIT-licensed examples and are the starting points of the
region libraries below; tune them in Material Maker, then export with
`export_materials.sh` (needs Material Maker 1.5+ and a GPU).

| File | Use | Region |
|---|---|---|
| meadow_grass.ptex | flowering meadow ground | Hub Meadow |
| ash_ground.ptex | cracked, ash-dry earth | Ember Wastes |
| volcanic_rock.ptex | dark rock faces | Ember Wastes, Frost Peaks cliffs |
| lava_crust.ptex | cooling lava crust | Ember Wastes |
| medieval_brick.ptex | brick walls | Brickton |
| church_stonework.ptex | dressed stone, the church | Brickton |
| weathered_stone.ptex | old walls, ruins | everywhere |
| cobblestone.ptex | streets and squares | Brickton |

Export size: 1024 px (512 for small props). Godot imports them with
mipmaps and ETC2/ASTC compression for phones.

Status: Material Maker could not run in the cloud build environment (it
needs a Vulkan or a full OpenGL GPU; three attempts crashed at start-up
under software rendering), so these have not been exported yet. Until
they are, the game uses the CC0 Poly Haven textures fetched by
`tools/fetch_vendor.py`, which already give each region its own ground,
rock and snow.
