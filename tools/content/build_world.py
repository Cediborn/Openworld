"""Writes game/data/world_features.json (places, treasures, shrines, rare
bosses, fragment trials, world events, flattened pads for the bake) and
game/data/bosses.json.

Positions are [x, z] world metres. After changing pads, re-run
tools/bake_world.gd so the terrain is levelled under the new places.
Run: python3 tools/content/build_world.py
"""
import json
import os

HERE = os.path.dirname(__file__)
DATA = os.path.join(HERE, "..", "..", "game", "data")

VIOLET = [0.72, 0.35, 1.0]

# Built places. kind picks the builder in scripts/world_features.gd.
STRUCTURES = [
    {"id": "sanctuary", "kind": "sanctuary", "pos": [-40, -40]},
    {"id": "mill", "kind": "mill", "pos": [60, 62]},
    {"id": "twin_stones", "kind": "stones", "pos": [-110, 92], "count": 2},
    {"id": "lone_oak", "kind": "oak", "pos": [115, -62]},
    {"id": "hale_wagon", "kind": "wagon", "pos": [26, -10], "rot": 1.2},
    {"id": "sigrun_camp", "kind": "camp", "pos": [25, -196], "rest": True},
    {"id": "expedition_camp", "kind": "ruined_camp", "pos": [-60, -262]},
    {"id": "hunter_lodge", "kind": "lodge", "pos": [95, -244], "rot": 0.0},
    {"id": "frost_ruins", "kind": "ruin", "pos": [-166, -305], "size": 12, "tint": [0.78, 0.82, 0.9]},
    {"id": "glacier_vault", "kind": "cave", "pos": [-209, -326], "rot": 0.0, "tint": [0.75, 0.85, 1.0]},
    {"id": "frost_cave", "kind": "cave", "pos": [-120, -238], "rot": 1.2, "tint": [0.75, 0.8, 0.88]},
    {"id": "scholar_camp", "kind": "camp", "pos": [202, 15], "rest": True, "tent": [0.65, 0.55, 0.35]},
    {"id": "ember_temple", "kind": "temple", "pos": [324, -25]},
    {"id": "golem_forge", "kind": "forge", "pos": [262, -150]},
    {"id": "salamander_nest", "kind": "nest", "pos": [290, 100]},
    {"id": "wren_hut", "kind": "hut", "pos": [25, 205], "rot": 3.14159, "rest": True},
    {"id": "heart_hollow", "kind": "corruption", "pos": [-25, 385]},
    {"id": "singing_crystal", "kind": "crystal", "pos": [125, 330], "color": [0.4, 0.9, 1.0], "size": 3.0},
    {"id": "queen_sinkhole", "kind": "sinkhole", "pos": [-171, 378]},
    {"id": "caldor", "kind": "caldor", "pos": [-235, 190]},
    {"id": "burrow_a", "kind": "burrow", "pos": [-90, 250]},
    {"id": "grotto", "kind": "cave", "pos": [95, 372], "rot": 2.6, "tint": [0.55, 0.85, 0.9]},
    {"id": "cinder_crater", "kind": "crater", "pos": [368, -105]},
    {"id": "overlook", "kind": "overlook", "pos": [0, -362]},
]

# Flattened ground under the larger places (read by tools/bake_world.gd).
PADS = [
    {"x": -40, "z": -40, "r": 20, "blend": 10},
    {"x": 60, "z": 62, "r": 7}, {"x": 25, "z": -196, "r": 9}, {"x": -60, "z": -262, "r": 8},
    {"x": 95, "z": -244, "r": 8}, {"x": -166, "z": -305, "r": 11}, {"x": -209, "z": -324, "r": 9},
    {"x": -120, "z": -238, "r": 7}, {"x": 202, "z": 15, "r": 8}, {"x": 324, "z": -25, "r": 13, "blend": 10},
    {"x": 262, "z": -150, "r": 11}, {"x": 25, "z": 205, "r": 8}, {"x": -25, "z": 385, "r": 14},
    {"x": -171, "z": 378, "r": 16, "dig": 4.0, "blend": 12}, {"x": -235, "z": 192, "r": 22, "blend": 10},
    {"x": 368, "z": -105, "r": 13, "dig": 2.5, "blend": 10}, {"x": 86, "z": -330, "r": 12}, {"x": -58, "z": -385, "r": 13},
    {"x": 160, "z": 255, "r": 14}, {"x": -135, "z": -75, "r": 12}, {"x": 45, "z": -300, "r": 9},
    {"x": 369, "z": 57, "r": 9}, {"x": -65, "z": 220, "r": 9}, {"x": -395, "z": 56, "r": 9}, {"x": 70, "z": -95, "r": 9},
    {"x": -120, "z": -45, "r": 9}, {"x": -10, "z": -345, "r": 10}, {"x": 262, "z": -70, "r": 9}, {"x": 95, "z": 372, "r": 7},
    {"x": 0, "z": -362, "r": 6},
]

# Named places. Hidden ones never show on the map until found (or with Edric's Compass).
DISCOVERIES = [
    {"id": "d_sanctuary", "name": "The Sealed Sanctuary", "pos": [-40, -40], "radius": 26, "xp": 40, "lines": ["A ring of ancient stone, its great door sealed. Five hollows are cut into the door."]},
    {"id": "d_mill", "name": "The Old Mill", "pos": [60, 62], "radius": 14, "xp": 30, "coins": 10},
    {"id": "d_stones", "name": "The Standing Stones", "pos": [-110, 92], "radius": 14, "xp": 30},
    {"id": "d_oak", "name": "Lone Oak Hill", "pos": [115, -62], "radius": 14, "xp": 30},
    {"id": "d_market", "name": "Brickton Market Square", "pos": [-311, -50], "radius": 16, "xp": 20},
    {"id": "d_campm1", "name": "The Abandoned Camp", "pos": [-396, -112], "radius": 12, "xp": 30, "hidden": True},
    {"id": "d_sigrun", "name": "Sigrun's Camp", "pos": [25, -196], "radius": 14, "xp": 30},
    {"id": "d_lodge", "name": "The Hunter's Lodge", "pos": [95, -244], "radius": 14, "xp": 30},
    {"id": "d_expedition", "name": "The High Camp", "pos": [-60, -262], "radius": 14, "xp": 30},
    {"id": "d_frostruins", "name": "The Frostbound Ruins", "pos": [-166, -305], "radius": 18, "xp": 40},
    {"id": "d_glacier", "name": "The Glacier Vault", "pos": [-209, -326], "radius": 10, "xp": 60, "hidden": True},
    {"id": "d_overlook", "name": "Summit Overlook", "pos": [0, -362], "radius": 10, "xp": 50, "coins": 20, "lines": ["The whole island lies below: the meadow, the lava's glow, the blue hollow, and Brickton's chimneys."]},
    {"id": "d_scholar", "name": "Scholar's Camp", "pos": [202, 15], "radius": 14, "xp": 30},
    {"id": "d_temple", "name": "Temple of Embers", "pos": [324, -25], "radius": 18, "xp": 50},
    {"id": "d_forge", "name": "The Golem Forge", "pos": [262, -150], "radius": 16, "xp": 50, "hidden": True},
    {"id": "d_crater", "name": "Cinder Crater", "pos": [368, -105], "radius": 16, "xp": 60, "hidden": True},
    {"id": "d_wren", "name": "Wren's Hut", "pos": [25, 205], "radius": 14, "xp": 30},
    {"id": "d_heart", "name": "The Heart of the Hollow", "pos": [-25, 385], "radius": 18, "xp": 50},
    {"id": "d_singing", "name": "The Singing Crystal", "pos": [125, 330], "radius": 16, "xp": 40},
    {"id": "d_sinkhole", "name": "The Queen's Sinkhole", "pos": [-171, 378], "radius": 22, "xp": 60, "hidden": True},
    {"id": "d_grotto", "name": "The Moonlit Grotto", "pos": [95, 372], "radius": 10, "xp": 60, "hidden": True},
    {"id": "d_caldor", "name": "Ruins of Caldor", "pos": [-235, 192], "radius": 26, "xp": 80, "hidden": True,
     "lines": ["Crowned trees carved on every broken stone. Someone ruled here, long ago."]},
]

# Treasure: kind chest (hidden), dig (needs its map to be visible), locked (needs a key),
# guarded (opens once its guardian is beaten: needs_flag).
TREASURES = [
    {"id": "t_hollow_oak", "name": "Hollow Tree Cache", "kind": "chest", "pos": [-140, 20], "loot": {"coins": 60, "potion": 2},
     "lines": ["Something glints inside a hollow trunk: a small chest, pushed deep into the rotten wood."]},
    {"id": "t_frost_cave", "name": "Frost Cave Chest", "kind": "chest", "pos": [-121, -241], "loot": {"coins": 80, "iron_ore": 2, "treasure_map_frost": 1},
     "lines": ["At the back of the cave, a trapper's chest. Inside, among the coins, a map drawn on hide."]},
    {"id": "t_frost_dig", "name": "Frozen Map Treasure", "kind": "dig", "pos": [-1, -353], "needs": "treasure_map_frost",
     "loot": {"coins": 200, "frost_shard": 3, "starsteel": 1}, "lines": ["The X on the hide map. You chip through the frozen earth... a buried strongbox."]},
    {"id": "t_temple_vault", "name": "Temple Treasure Chamber", "kind": "guarded", "pos": [327, -16], "guardian": {"species": "lava_golem", "elite": {"tint": [1.0, 0.6, 0.2], "health": 1.6, "scale": 1.2}},
     "loot": {"coins": 150, "ember_shard": 3, "golem_core": 1}, "lines": ["The guardian crumbles. Behind it, a niche full of offerings left for the Wardens."]},
    {"id": "t_glow_dig", "name": "Spore Map Treasure", "kind": "dig", "pos": [150, 300], "needs": "treasure_map_glow",
     "loot": {"coins": 180, "rare_crystal": 1, "glow_spore": 3}, "lines": ["Under the moss where the map's X sits: a clay jar sealed with wax."]},
    {"id": "t_sinkhole", "name": "Queen's Hoard", "kind": "chest", "pos": [-163, 371], "needs_flag": "boss:beetle_queen",
     "loot": {"coins": 250, "starsteel": 1, "beetle_chitin": 4}, "lines": ["The queen's nest holds the remains of everything she dragged down: including a traveller's purse."]},
    {"id": "t_cellar", "name": "Old Cellar", "kind": "locked", "pos": [-376, -14], "needs": "rusty_key",
     "loot": {"coins": 200, "ancient_coin": 2, "elixir": 1}, "lines": ["The rusty key turns. The cellar is dry and very old: a crowned tree is painted on the wall."]},
    {"id": "t_nest", "name": "Nest Chest", "kind": "chest", "pos": [293, 108], "loot": {"coins": 40, "rusty_key": 1, "treasure_map_glow": 1},
     "lines": ["Among the scorched bones of the nest, a battered chest. A rusty key stamped with a crown, and a map stained with spores."]},
    {"id": "t_overlook", "name": "Climber's Cache", "kind": "chest", "pos": [2, -364], "loot": {"coins": 120, "frost_shard": 2},
     "lines": ["Climbers leave a cache at the summit for those who make it. Tradition says you take one thing and leave one thing. You take two."]},
    {"id": "t_crater", "name": "Cinder Hoard", "kind": "chest", "pos": [374, -100], "needs_flag": "boss:cinderhulk",
     "loot": {"coins": 300, "obsidian": 4}, "lines": ["Cinderhulk's lair glitters with obsidian and the gold of fools who came before."]},
    {"id": "t_lava_ridge", "name": "Ridge Cache", "kind": "chest", "pos": [300, 80], "loot": {"coins": 100, "ember_shard": 2},
     "lines": ["Wedged between basalt columns on the ridge: a sealed tin box."]},
    {"id": "t_scarecrow", "name": "Under the Scarecrow", "kind": "dig", "pos": [-380, 90], "loot": {"coins": 80, "potion": 2},
     "lines": ["Old Gus always said his grandfather buried 'something for a rainy day' under the scarecrow."]},
]

# Shrines: each has its own puzzle. Solving one opens its reward chest.
SHRINES = [
    {"id": "hub_shrine", "name": "Shrine of the Rising Sun", "pos": [-120, -45], "puzzle": "order", "glyphs": ["SUN", "MOON", "STAR", "EARTH"], "order": [2, 0, 3, 1],
     "hint": "Carved on the lintel: 'First the star, then the sun; the earth before the moon.'", "loot": {"coins": 120, "elixir": 1, "ancient_coin": 1}},
    {"id": "frost_shrine", "name": "Shrine of Stillness", "pos": [45, -300], "puzzle": "align", "rings": 3, "target": [2, 1, 3],
     "hint": "The plaque shows three stones: the first bears SNOW, the second PEAK, the third MOON.", "symbols": ["STAR", "PEAK", "SNOW", "MOON"],
     "loot": {"coins": 150, "frost_shard": 2, "starsteel": 1}},
    {"id": "ember_shrine", "name": "Shrine of the Forge", "pos": [369, 57], "puzzle": "guardian", "guardian": {"species": "lava_golem", "elite": {"tint": [1.0, 0.85, 0.3], "health": 1.8, "scale": 1.25, "name": "Shrine Guardian"}},
     "hint": "'Only the worthy may touch the forge-fire.'", "loot": {"coins": 160, "golem_core": 1, "ember_shard": 2}},
    {"id": "glow_shrine", "name": "Shrine of Light", "pos": [-65, 220], "puzzle": "components", "parts": [[-88, 205], [-44, 196], [-82, 246]],
     "hint": "Three shards of the shrine's lens are missing. Their glow can be seen among the mushrooms.", "loot": {"coins": 130, "elixir": 1, "glow_spore": 3}},
    {"id": "west_shrine", "name": "Shrine of Memory", "pos": [-395, 56], "puzzle": "switches", "switches": [[-406, 49], [-387, 68], [-401, 70]],
     "hint": "'Three hands hold the door. Find where they hide in the grass and stone.'", "loot": {"coins": 120, "ancient_coin": 2, "potion": 2}},
    {"id": "hidden_shrine", "name": "Hidden Shrine of the Path", "pos": [70, -95], "puzzle": "route", "plate": [58, -86],
     "hint": "A shrine with no door at all. The ground nearby sounds hollow in one spot.", "loot": {"coins": 140, "rare_crystal": 1}},
]

# Rare bosses out in the world (separate from quest bosses).
RARE_BOSSES = [
    {"id": "cinderhulk", "pos": [368, -105], "loot": {"coins": 400, "cinder_edge": 1, "trophy_cinderhulk": 1, "golem_core": 2}, "xp": 500},
    {"id": "gloomhorn", "pos": [160, 255], "loot": {"coins": 350, "gloomfang": 1, "trophy_gloomhorn": 1, "beetle_chitin": 4}, "xp": 450},
    {"id": "rimeclaw", "pos": [-58, -385], "loot": {"coins": 380, "frostbite": 1, "trophy_rimeclaw": 1, "troll_hide": 2}, "xp": 480},
    {"id": "hollow_sentinel", "pos": [-135, -75], "loot": {"coins": 300, "rare_crystal": 1, "trophy_sentinel": 1}, "xp": 400, "night_only": False},
]

# The Five Fragments trials (active while that quest is running).
FRAGMENTS = [
    {"id": "fragment_meadow", "kind": "order", "clue": [-50, 122], "clue_text": ["A Warden stone. Its carving: three runestones in a curve, and the words 'Growth wakes in the east, sinks to the south, and sleeps in the west.'"],
     "stones": [[20, 150], [-30, 165], [-80, 148]], "glyphs": ["EAST", "SOUTH", "WEST"], "order": [0, 1, 2], "reward_pos": [-30, 145]},
    {"id": "fragment_frost", "kind": "guardian", "clue": [-10, -325], "clue_text": ["A Warden stone half buried in snow: 'Stillness is kept by a sentinel who never sleeps. Wake it, and take what it guards.'"],
     "boss": "frost_sentinel", "boss_pos": [-10, -345]},
    {"id": "fragment_ember", "kind": "order", "clue": [260, -49], "clue_text": ["A Warden stone, warm to the touch: 'Light the braziers as fire is born: spark, flame, then ash.' "],
     "stones": [[256, -72], [262, -66], [268, -72]], "glyphs": ["ASH", "SPARK", "FLAME"], "order": [1, 2, 0], "reward_pos": [262, -72]},
    {"id": "fragment_glow", "kind": "hidden", "clue": [60, 282], "clue_text": ["A Warden stone furred with moss: 'Light hides where the moths gather. Follow them south.' A glowing moth flutters away from the stone."],
     "path": [[70, 310], [82, 340], [92, 362]], "reward_pos": [95, 374]},
    {"id": "fragment_town", "kind": "order", "clue": [-308, -68], "clue_text": ["Quill shows you a ledger: 'Caldor's memory rests in Brickton. Visit the water, the watch and the welcome, in that order, then ring the bell.'",
                                                                                  "The water must be the well in the square, the watch the gate tower, the welcome... the inn's sign?"],
     "stones": [[-311, -47], [-196, -2], [-335, -50]], "order": [0, 1, 2], "glyphs": ["Well", "Gate", "Inn"], "reward_pos": [-311, -70], "landmarks": True},
]

EVENTS = {
    "_comment": "Random world events. One at a time, never while a quest battle or boss fight is on. every = seconds between checks; chance per check.",
    "every": [240, 420],
    "types": [
        {"id": "raid", "name": "Monsters attack!", "region": "Brickton", "sites": [[-205, 40], [-380, -40], [-250, 80]], "groups": [["wolf", 3], ["boar", 2]], "reward": {"coins": 60, "xp": 80}},
        {"id": "hub_raid", "name": "Wolves at the crossroads!", "region": "Hub Meadow", "sites": [[30, -20], [-40, 30]], "groups": [["wolf", 3]], "reward": {"coins": 40, "xp": 60}},
        {"id": "merchant", "name": "A travelling merchant has set up shop", "sites": [[-20, 60], [10, -230], [215, -5], [15, 230], [-205, -5]], "duration": 300},
        {"id": "rare", "name": "A rare creature has been sighted", "options": [
            {"species": "boar", "where": [80, 40], "elite": {"name": "Goldbristle Boar", "tint": [1.0, 0.8, 0.2], "scale": 1.35, "health": 2.0}, "loot": {"coins": 90, "starsteel": 1}},
            {"species": "wolf", "where": [-60, -220], "night": True, "elite": {"name": "Moonlit Wolf", "tint": [0.6, 0.8, 1.0], "scale": 1.3, "health": 2.0}, "loot": {"coins": 90, "frost_shard": 2}},
            {"species": "mushroom_beetle", "where": [-40, 300], "elite": {"name": "Shimmerback Beetle", "tint": [0.2, 1.0, 0.6], "scale": 1.4, "health": 2.0}, "loot": {"coins": 90, "rare_crystal": 1}}]},
        {"id": "crystal_surge", "name": "Crystals are erupting in Glow Hollow", "region": "Glow Hollow", "centre": [20, 290], "item": "glow_spore", "count": 5, "duration": 180},
        {"id": "volcanic", "name": "The Ember Wastes are erupting", "region": "Ember Wastes", "centre": [280, 0], "item": "obsidian", "count": 4, "duration": 150, "hazard": True},
        {"id": "traveller", "name": "Someone is calling for help", "sites": [[-120, 10], [60, -150], [160, 60], [-60, 180], [-230, -60]], "reward": {"coins": 70, "xp": 90}},
    ]}

BOSSES = {
    "_comment": "Bosses: base species (model and walk/run tuning) with overrides. Moves as in creatures.json plus volley / quake (centre self) / burrow / summon / charge; pose picks which animation a special move uses. phases: at health fraction -> speed multiplier, new moves, summons.",
    "bosses": {
        "ancient_guardian": {"name": "The Ancient Guardian", "base": "lava_golem", "scale": [2.3, 2.3], "health": 2200, "damage": 30, "radius": 1.5, "arena": 40,
                             "glow_color": [0.75, 0.35, 1.0], "glow_energy": 3.5, "crystals": VIOLET, "run_speed": 3.4, "attack_rate": 1.8, "min_height": -100,
                             "attacks": [
                                 {"name": "overhead_smash", "windup": 0.95, "strike": 0.25, "recover": 0.7, "reach": 3.0, "arc": 80, "damage": 1.2, "telegraph": True},
                                 {"name": "hook", "windup": 0.65, "strike": 0.3, "recover": 0.55, "reach": 3.0, "arc": 150, "damage": 0.9},
                                 {"name": "quake", "pose": "ground_pound", "centre": "self", "windup": 1.1, "strike": 0.3, "recover": 0.8, "reach": 3.0, "aoe": 3.6, "damage": 1.0, "telegraph": True, "min_range": 0, "max_range": 4.0},
                                 {"name": "volley", "pose": "overhead_smash", "windup": 0.8, "strike": 0.2, "recover": 0.8, "reach": 3.0, "count": 5, "aoe": 1.8, "damage": 0.6, "min_range": 4.0, "max_range": 18.0}],
                             "phases": [{"at": 0.66, "speed": 1.15, "summon": ["frost_spirit", 2]},
                                        {"at": 0.33, "speed": 1.3, "summon": ["fire_salamander", 3],
                                         "add": [{"name": "charge", "pose": "punch", "windup": 0.9, "strike": 0.5, "recover": 0.7, "reach": 2.4, "arc": 70, "damage": 1.3, "lunge": 4.0, "min_range": 5.0, "max_range": 16.0}]}],
                             "summon": ["frost_spirit", 2], "reward": {"items": {"trophy_guardian": 1}}},
        "beetle_queen": {"name": "The Beetle Queen", "base": "mushroom_beetle", "scale": [3.0, 3.0], "health": 1700, "damage": 24, "radius": 1.8, "arena": 40,
                         "glow_color": [0.85, 0.3, 1.0], "glow_energy": 3.0, "crystals": [0.85, 0.3, 1.0], "run_speed": 3.6, "min_height": -100,
                         "attacks": [
                             {"name": "horn_lunge", "windup": 0.75, "strike": 0.4, "recover": 0.7, "reach": 1.9, "arc": 70, "damage": 1.1, "lunge": 2.2, "min_range": 2.0, "max_range": 9.0},
                             {"name": "bite", "windup": 0.4, "strike": 0.2, "recover": 0.5, "reach": 2.1, "arc": 80, "damage": 0.9, "max_range": 3.0},
                             {"name": "quake", "pose": "horn_lunge", "centre": "self", "windup": 0.9, "strike": 0.3, "recover": 0.7, "reach": 2.0, "aoe": 3.2, "damage": 0.9, "telegraph": True, "max_range": 3.5}],
                         "phases": [{"at": 0.7, "speed": 1.1, "summon": ["mushroom_beetle", 3],
                                     "add": [{"name": "burrow", "windup": 1.4, "strike": 0.4, "recover": 0.8, "reach": 2.0, "aoe": 2.8, "damage": 1.3, "telegraph": True, "min_range": 3.0, "max_range": 25.0, "weight": 1.5}]},
                                    {"at": 0.35, "speed": 1.3, "summon": ["mushroom_beetle", 2],
                                     "add": [{"name": "volley", "pose": "spit", "windup": 0.7, "strike": 0.2, "recover": 0.7, "reach": 2.0, "count": 6, "aoe": 1.7, "damage": 0.6, "min_range": 4.0, "max_range": 20.0}]}],
                         "reward": {"items": {"trophy_queen": 1}}},
        "mutated_guardian": {"name": "The Mutated Guardian", "base": "ice_troll", "scale": [1.7, 1.7], "health": 950, "damage": 22, "radius": 1.1, "arena": 30,
                             "glow_color": [0.7, 0.35, 1.0], "glow_energy": 2.4, "crystals": VIOLET, "min_height": -100, "element": "",
                             "attacks": [
                                 {"name": "overhead_smash", "windup": 0.85, "strike": 0.24, "recover": 0.7, "reach": 2.9, "arc": 80, "damage": 1.2, "telegraph": True},
                                 {"name": "hook", "windup": 0.55, "strike": 0.28, "recover": 0.5, "reach": 2.8, "arc": 140, "damage": 0.9},
                                 {"name": "volley", "pose": "overhead_smash", "windup": 0.8, "strike": 0.2, "recover": 0.8, "reach": 2.8, "count": 3, "aoe": 1.6, "damage": 0.6, "min_range": 4.0, "max_range": 16.0}],
                             "phases": [{"at": 0.5, "speed": 1.2, "summon": ["frost_spirit", 2]}], "reward": {"items": {"rare_crystal": 1}}},
        "greymane": {"name": "Greymane", "base": "wolf", "scale": [1.9, 1.9], "health": 650, "damage": 18, "radius": 0.8, "arena": 35, "temper": "threaten",
                     "glow_color": [0.8, 0.85, 1.0], "glow_energy": 0.6, "crystals": [0.85, 0.9, 1.0], "run_speed": 8.5, "min_height": -100,
                     "attacks": [
                         {"name": "pounce", "windup": 0.5, "strike": 0.36, "recover": 0.5, "reach": 1.6, "arc": 80, "damage": 1.2, "lunge": 2.4, "min_range": 2.0, "max_range": 6.0},
                         {"name": "bite", "windup": 0.3, "strike": 0.16, "recover": 0.4, "reach": 1.9, "arc": 80, "damage": 0.9, "max_range": 2.4},
                         {"name": "charge", "pose": "pounce", "windup": 0.8, "strike": 0.5, "recover": 0.6, "reach": 1.6, "arc": 70, "damage": 1.3, "lunge": 4.5, "min_range": 5.0, "max_range": 14.0}],
                     "phases": [{"at": 0.5, "speed": 1.2, "summon": ["wolf", 2]}], "reward": {"items": {"trophy_greymane": 1}}},
        "cinderhulk": {"name": "Cinderhulk, the Ancient Golem", "base": "lava_golem", "scale": [2.5, 2.5], "health": 1600, "damage": 32, "radius": 1.6, "arena": 35, "element": "fire",
                       "glow_color": [1.0, 0.35, 0.05], "glow_energy": 4.5, "crystals": [1.0, 0.5, 0.1], "min_height": -100,
                       "attacks": [
                           {"name": "overhead_smash", "windup": 1.0, "strike": 0.26, "recover": 0.8, "reach": 3.0, "arc": 80, "damage": 1.2, "telegraph": True},
                           {"name": "ground_pound", "windup": 1.1, "strike": 0.3, "recover": 0.9, "reach": 3.0, "aoe": 3.0, "damage": 1.1, "telegraph": True},
                           {"name": "quake", "pose": "ground_pound", "centre": "self", "windup": 1.2, "strike": 0.3, "recover": 0.9, "reach": 3.0, "aoe": 4.0, "damage": 1.0, "telegraph": True, "max_range": 4.5},
                           {"name": "volley", "pose": "overhead_smash", "windup": 0.9, "strike": 0.2, "recover": 0.8, "reach": 3.0, "count": 5, "aoe": 2.0, "damage": 0.6, "min_range": 5.0, "max_range": 20.0}],
                       "phases": [{"at": 0.5, "speed": 1.25, "summon": ["fire_salamander", 3]}], "reward": {}},
        "gloomhorn": {"name": "Gloomhorn", "base": "mushroom_beetle", "scale": [2.6, 2.6], "health": 1200, "damage": 26, "radius": 1.6, "arena": 35,
                      "glow_color": [0.2, 1.0, 0.7], "glow_energy": 3.0, "crystals": [0.2, 1.0, 0.7], "run_speed": 3.8, "min_height": -100,
                      "attacks": [
                          {"name": "charge", "pose": "horn_lunge", "windup": 1.0, "strike": 0.55, "recover": 0.8, "reach": 1.8, "arc": 70, "damage": 1.3, "lunge": 5.0, "min_range": 4.0, "max_range": 18.0, "weight": 1.4},
                          {"name": "horn_lunge", "windup": 0.7, "strike": 0.38, "recover": 0.6, "reach": 1.8, "arc": 70, "damage": 1.1, "lunge": 2.0, "max_range": 6.0},
                          {"name": "quake", "pose": "horn_lunge", "centre": "self", "windup": 0.9, "strike": 0.3, "recover": 0.7, "reach": 2.0, "aoe": 3.2, "damage": 0.9, "telegraph": True, "max_range": 3.5}],
                      "phases": [{"at": 0.5, "speed": 1.3, "add": [{"name": "volley", "pose": "spit", "windup": 0.7, "strike": 0.2, "recover": 0.7, "reach": 2.0, "count": 5, "aoe": 1.7, "damage": 0.6, "min_range": 4.0, "max_range": 18.0}]}],
                      "reward": {}},
        "rimeclaw": {"name": "Rimeclaw, the Frost Titan", "base": "ice_troll", "scale": [2.2, 2.2], "health": 1450, "damage": 30, "radius": 1.5, "arena": 35, "element": "frost",
                     "glow_color": [0.5, 0.85, 1.0], "glow_energy": 3.0, "crystals": [0.6, 0.9, 1.0], "min_height": -100,
                     "attacks": [
                         {"name": "overhead_smash", "windup": 0.9, "strike": 0.25, "recover": 0.75, "reach": 3.0, "arc": 80, "damage": 1.2, "telegraph": True},
                         {"name": "hook", "windup": 0.6, "strike": 0.3, "recover": 0.55, "reach": 3.0, "arc": 150, "damage": 0.9},
                         {"name": "volley", "pose": "overhead_smash", "windup": 0.8, "strike": 0.2, "recover": 0.8, "reach": 3.0, "count": 5, "aoe": 1.8, "damage": 0.6, "min_range": 4.0, "max_range": 18.0},
                         {"name": "quake", "pose": "ground_pound", "centre": "self", "windup": 1.0, "strike": 0.3, "recover": 0.8, "reach": 3.0, "aoe": 3.6, "damage": 1.0, "telegraph": True, "max_range": 4.0}],
                     "phases": [{"at": 0.5, "speed": 1.2, "summon": ["frost_spirit", 2]}], "reward": {}},
        "hollow_sentinel": {"name": "The Hollow Sentinel", "base": "frost_spirit", "scale": [2.0, 2.0], "health": 1000, "damage": 24, "radius": 1.0, "arena": 30,
                            "glow_color": [0.75, 0.35, 1.0], "glow_energy": 2.5, "crystals": VIOLET, "hover": 0.6,
                            "attacks": [
                                {"name": "claw_swipe", "windup": 0.55, "strike": 0.25, "recover": 0.5, "reach": 2.6, "arc": 130, "damage": 1.0},
                                {"name": "wail_lunge", "windup": 0.7, "strike": 0.35, "recover": 0.55, "reach": 1.8, "arc": 70, "damage": 1.2, "lunge": 3.0, "min_range": 3.0, "max_range": 9.0},
                                {"name": "volley", "pose": "claw_swipe", "windup": 0.7, "strike": 0.2, "recover": 0.7, "reach": 2.0, "count": 4, "aoe": 1.7, "damage": 0.6, "min_range": 4.0, "max_range": 18.0}],
                            "phases": [{"at": 0.5, "speed": 1.2, "summon": ["frost_spirit", 2]}], "reward": {}},
        "night_terror": {"name": "The Night Terror", "base": "ice_troll", "scale": [1.8, 1.8], "health": 900, "damage": 24, "radius": 1.2, "arena": 40,
                         "glow_color": [1.0, 0.25, 0.2], "glow_energy": 2.5, "crystals": [1.0, 0.3, 0.25], "min_height": -100, "element": "",
                         "attacks": [
                             {"name": "overhead_smash", "windup": 0.85, "strike": 0.24, "recover": 0.7, "reach": 2.9, "arc": 80, "damage": 1.2, "telegraph": True},
                             {"name": "hook", "windup": 0.55, "strike": 0.28, "recover": 0.5, "reach": 2.8, "arc": 140, "damage": 0.9},
                             {"name": "charge", "pose": "punch", "windup": 0.8, "strike": 0.45, "recover": 0.6, "reach": 2.3, "arc": 70, "damage": 1.2, "lunge": 3.5, "min_range": 4.0, "max_range": 12.0}],
                         "phases": [{"at": 0.5, "speed": 1.2, "summon": ["wolf", 2]}], "reward": {}},
        "frost_sentinel": {"name": "The Frozen Sentinel", "base": "ice_troll", "scale": [1.5, 1.5], "health": 700, "damage": 22, "radius": 1.0, "arena": 25, "element": "frost",
                           "glow_color": [0.75, 0.95, 1.0], "glow_energy": 2.5, "crystals": [0.85, 0.95, 1.0], "min_height": -100,
                           "attacks": [
                               {"name": "overhead_smash", "windup": 0.8, "strike": 0.24, "recover": 0.7, "reach": 2.8, "arc": 80, "damage": 1.2, "telegraph": True},
                               {"name": "punch", "windup": 0.4, "strike": 0.18, "recover": 0.45, "reach": 2.6, "arc": 50, "damage": 0.8}],
                           "phases": [{"at": 0.5, "speed": 1.2}], "reward": {"items": {"fragment_frost": 1}}},
    }}

data = {
    "_comment": "Generated by tools/content/build_world.py. Places, treasures, shrines, rare bosses, fragment trials, world events and the pads levelled by tools/bake_world.gd.",
    "structures": STRUCTURES, "pads": PADS, "discoveries": DISCOVERIES, "treasures": TREASURES, "shrines": SHRINES,
    "rare_bosses": RARE_BOSSES, "fragments": FRAGMENTS, "events": EVENTS}
with open(os.path.join(DATA, "world_features.json"), "w") as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
with open(os.path.join(DATA, "bosses.json"), "w") as f:
    json.dump(BOSSES, f, indent=1)
print("structures", len(STRUCTURES), "discoveries", len(DISCOVERIES), "treasures", len(TREASURES), "shrines", len(SHRINES),
      "rare bosses", len(RARE_BOSSES), "fragment trials", len(FRAGMENTS), "event types", len(EVENTS["types"]), "bosses", len(BOSSES["bosses"]))
