# Character assets and their licences

Every file here is CC0 1.0 (public domain). Sources and what the game does with them:

| Files | What | Source | Licence |
|---|---|---|---|
| `Superhero_Male_FullBody.*`, `Superhero_Female_FullBody.*`, `T_Superhero_*`, `T_Eye_*`, `T_Hair_*` | Base bodies. The game keeps only the head and neck (face, ears, eyes, skin) and reshapes the face six ways (`ExplorerBody.FACE_SHAPES`) | Universal Base Characters [Standard] by Quaternius, https://quaternius.com/packs/universalbasecharacters.html | CC0 1.0 (`LICENSE-CC0.txt`) |
| `kit/hair/*` | Six hairstyles, a beard and two pairs of eyebrows, rigged to the same skeleton; tinted per person | Universal Base Characters [Standard] by Quaternius | CC0 1.0 (`kit/hair/LICENSE-Quaternius-Universal-Base-Characters.txt`) |
| `kit/outfits/*` | Peasant and Ranger outfits, male and female: modelled clothes with colour, normal and ORM maps. The game dyes them per person (`shaders/spatial_char_kit.gdshader`) and mixes parts (a peasant can wear the ranger's hood) | Modular Character Outfits - Fantasy [Standard] by Quaternius, https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | CC0 1.0 (`kit/outfits/LICENSE-Quaternius-Modular-Character-Outfits-Fantasy.txt`) |
| `anims/*.res` | Animations retargeted onto the skeleton | Universal Animation Library [Standard] by Quaternius | CC0 1.0 |

Made in code from those parts (no extra files): the white long coat outfit
(the shirt mesh pushed out and opened at the front, full-length sleeves, a
flared skirt with folds, silver trim and a sash, `ExplorerBody._add_coat`)
and work aprons (`ExplorerBody._add_apron`). Both are skinned to the same
skeleton, so they move with every animation.

The kit files were copied unchanged from the Standard (free) releases, as
mirrored in https://github.com/kirbycope/godot-3d-player-controller-v2
(`assets/modular_character_outfits`, `assets/universal_base_characters`).
