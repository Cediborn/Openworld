"""Writes game/data/quests.json: the Shattered Island storyline, side quests,
special quests and the monster-contract templates.

Positions are [x, z] world metres (height comes from the terrain).
Run: python3 tools/content/build_quests.py
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "data", "quests.json")

TOWNSFOLK = ["pell", "marta", "joss", "henna", "dorn", "gerta", "ivo", "sela", "gus", "hester", "tobias", "nell",
             "wim", "rosa", "jory", "bert", "lotte", "mads", "sanne", "baker", "lina", "kid", "kael", "bryn",
             "guard_osric", "guard_wynn", "guard_dela", "guard_gate1", "guard_gate2", "harlan", "quill", "mira", "tilly", "smith", "nadia"]


def npc(name, model, jacket, pants, hair, acc, **kw):
    o = {"model": model, "jacket": jacket, "pants": pants, "boots": [0.22, 0.15, 0.1], "hair": hair, "accessories": acc}
    o.update(kw.pop("extra", {}))
    d = {"name": name, "outfit": o, "mode": kw.pop("mode", "wander"), "wander": 0.0, "lines": {"default": kw.pop("lines", ["..."])}}
    d.update(kw)
    return d


Q = {}

# ------------------------------------------------------------------ MAIN STORY

Q["island_heart"] = {
    "title": "The Island's Heart", "type": "main", "chapter": 0, "region": "Brickton", "virtual": True,
    "description": "Elder Tobin's first request: recover the three heart-stones - the Frost Crystal, the Ember Heart and the Glow Spore - and bring them to Bram the blacksmith.",
    "steps": [], "rewards": {"text": "Heartforged Sword"}}

Q["strange_silence"] = {
    "title": "A Strange Silence", "type": "main", "chapter": 1, "region": "Brickton", "giver": "elder", "requires": ["island_heart"],
    "description": "No traveller has reached Brickton in nine days, and at night the villagers hear stone grinding beneath the fields. Elder Tobin wants to know why.",
    "offer": ["The heart-stones are quiet, thanks to you. But the island is not.",
              "Nine days now and not a single traveller at our gates. And at night... a sound like millstones, deep under the fields.",
              "The townsfolk have seen things. Ask them, then look around the western outskirts. Will you?"],
    "accept": ["Thank you. Start with the people in the market square, they hear everything."],
    "progress_lines": ["Ask the townsfolk what they've seen, then search the outskirts to the west."],
    "steps": [
        {"text": "Speak to three villagers", "type": "talk_any", "count": 3, "exclude": ["elder"],
         "lines": ["Travellers? Not one in a week. The last ones were heading in from the west road.",
                   "Something knocked down the fences on the west side. From the outside.",
                   "My dog won't go past the last houses on the west side. Just whines and digs.",
                   "I heard grinding last night, under the floor. Like the whole island turning over in its sleep."],
         "by_npc": {"harlan": "My guards found tracks on the west road, boots and something with three toes. They lead north-west.",
                    "hester": "My grandmother said the Wardens sealed something under the island. When the stones sing, she said, it's waking.",
                    "kael": "I camped with two travellers on the west road a fortnight back. Never saw them arrive.",
                    "ivo": "Those fences on the west side were pushed down from the outside. Something big."}},
        {"type": "reach", "text": "Investigate the western outskirts", "pos": [-386, -16], "radius": 12,
         "lines": ["The fields beyond the last houses are trampled flat. Something heavy passed here, more than once."]},
        {"type": "inspect", "text": "Examine the footprints", "pos": [-392, -42], "model": "tracks", "dir": [-0.2, -1], "label": "Examine the footprints",
         "lines": ["Boot prints... and beside them, deep three-toed marks. Something was following the travellers.", "The trail leads north."]},
        {"type": "inspect", "text": "Follow the mysterious footprints", "pos": [-399, -80], "model": "tracks", "dir": [0.1, -1], "label": "Follow the footprints",
         "lines": ["The boot prints break into a run here. The other tracks don't."]},
        {"type": "inspect", "text": "Discover the abandoned campsite", "pos": [-396, -112], "model": "campsite", "label": "Search the abandoned camp", "range": 4.0,
         "lines": ["Tents slashed, the fire long cold. Packs left behind, food untouched.",
                   "A notebook in a satchel: 'Night four. The old stones by the meadow glowed when the ground shook. Mara says the marks match the Warden map her grandmother kept...'",
                   "The last page is torn out. Elder Tobin should see this."]},
        {"type": "talk", "text": "Return to the Village Elder with your findings", "npc": "elder",
         "lines": ["A camp torn apart, the travellers gone... and these marks. They're the same as on the Warden stones in our oldest records.",
                   "The Wardens sealed something beneath this island, long before Brickton was built. If it is waking...",
                   "Take this. My family has kept it for generations: a fragment of an ancient map. Its marks point to all five corners of the island.",
                   "A mountaineer named Sigrun sent word from the Frost Peaks. Her expedition hasn't come back. Start there."]},
    ],
    "rewards": {"coins": 120, "xp": 150, "items": {"map_fragment": 1}}}

Q["frozen_expedition"] = {
    "title": "The Frozen Expedition", "type": "main", "chapter": 2, "region": "Frost Peaks", "giver": "sigrun", "requires": ["strange_silence"],
    "description": "Sigrun's expedition went to study strange ice in the Frost Peaks and never returned. Find them.",
    "offer": ["You're the one from Brickton? Good. I need help, not sympathy.",
              "Six of my climbers went up to study the ice. It's been growing in colours ice shouldn't have. They're three days overdue.",
              "Their high camp is west along the ridge path. Find them. Please."],
    "accept": ["Follow the path west from here. Watch for the spirits, they hunt in the open."],
    "progress_lines": ["The high camp is west along the ridge path. Bring them home."],
    "npcs": {"corin": npc("Corin the Climber", "male", [0.6, 0.25, 0.2], [0.3, 0.3, 0.35], [0.7, 0.5, 0.25], ["hood"],
                          extra={"hood_color": [0.6, 0.6, 0.65]}, lines=["Stay close. Please."], present=[3, 5])},
    "steps": [
        {"type": "reach", "text": "Find the missing expedition camp", "pos": [-60, -262], "radius": 12},
        {"type": "inspect", "text": "Investigate the abandoned equipment", "pos": [-60, -262], "model": "equipment", "label": "Investigate the equipment", "range": 4.0,
         "lines": ["Ropes cut, a tent shredded. Frost has grown over everything in violet crystals.",
                   "A trail of footprints leads further west, towards the old ruins."]},
        {"type": "inspect", "text": "Follow the tracks through the snow", "pos": [-92, -271], "model": "tracks", "dir": [-1, -0.3], "label": "Follow the tracks",
         "lines": ["Someone ran this way, dragging a leg. Fresh."]},
        {"type": "talk", "text": "Locate the surviving expedition member", "npc": "corin", "pos": [-122, -283],
         "lines": ["You... you're real? I thought you were another one of them.",
                   "The spirits came out of the violet ice. They took the others down into it. I hid in the rocks.",
                   "Look out! They followed me!"]},
        {"type": "kill", "text": "Defeat the creatures threatening Corin", "spawn": {"species": "frost_spirit", "count": 3, "pos": [-112, -276], "radius": 6}},
        {"type": "escort", "text": "Escort Corin back to Sigrun's camp", "npc": "corin", "from": [-122, -283], "to": [25, -196], "radius": 10},
        {"type": "talk", "text": "Report to Sigrun", "npc": "sigrun",
         "lines": ["Corin! Thank the peaks... and the others?",
                   "Taken into the ice. Violet ice. Spirits coming out of it.",
                   "Whatever is waking under this island, it's reaching up through the mountains. You'll need these furs where you're going.",
                   "Corin's notes mention a scholar in the Ember Wastes asking about the same crystals. Aurelia. Find her."]},
    ],
    "rewards": {"coins": 150, "xp": 220, "items": {"frost_coat": 1}}}

Q["beneath_ashes"] = {
    "title": "Beneath the Ashes", "type": "main", "chapter": 3, "region": "Ember Wastes", "giver": "aurelia", "requires": ["frozen_expedition"],
    "description": "Aurelia the scholar believes the strange volcanic activity in the Ember Wastes is linked to an ancient temple half-buried in ash.",
    "offer": ["Ah! You've seen the violet crystals too? Then you know something is wrong.",
              "The ground here shakes every night and the lava has carved new channels. And there's a temple out there, half swallowed by ash.",
              "Violet crystals are growing at its door. I can read the old script, but I can't fight what guards it. Will you come?"],
    "accept": ["Splendid! Start at the steaming vent east of here, then follow the ash to the temple."],
    "progress_lines": ["The temple lies east, past the steaming vent. Mind the lava."],
    "steps": [
        {"type": "inspect", "text": "Investigate the unusual volcanic activity", "pos": [289, -15], "model": "crystal", "color": [0.75, 0.35, 1.0], "size": 1.6,
         "label": "Investigate the steaming vent", "range": 4.0,
         "lines": ["A vent hisses violet steam. The rock around it has crystallised in the same violet as the peaks.",
                   "Fresh tracks, heavy and many, lead east to a structure buried in ash."]},
        {"type": "reach", "text": "Locate the ancient structure", "pos": [318, -25], "radius": 16},
        {"text": "Defeat the creatures guarding the entrance", "goals": [
            {"type": "kill", "text": "Defeat the temple's golem", "spawn": {"species": "lava_golem", "count": 1, "pos": [306, -25], "radius": 2}},
            {"type": "kill", "text": "Defeat the salamanders", "spawn": {"species": "fire_salamander", "count": 3, "pos": [304, -20], "radius": 5}}]},
        {"type": "reach", "text": "Explore the structure", "pos": [324, -25], "radius": 4,
         "lines": ["Inside, the air is hot and utterly still. Carvings cover every wall."]},
        {"text": "Discover the ancient inscriptions", "goals": [
            {"type": "inspect", "text": "Read the north inscription", "pos": [324, -30], "model": "inscription", "color": [1.0, 0.5, 0.2], "label": "Read the inscription",
             "lines": ["'We, the Wardens, set the Heart to sleep beneath the five lands, and bound its hunger with five seals.'"]},
            {"type": "inspect", "text": "Read the south inscription", "pos": [324, -20], "model": "inscription", "color": [1.0, 0.5, 0.2], "label": "Read the inscription",
             "lines": ["'A Guardian of crystal watches the sleeper. Should the seals fail, the Guardian will wake with it.'"]},
            {"type": "inspect", "text": "Read the east inscription", "pos": [329, -25], "model": "inscription", "color": [1.0, 0.5, 0.2], "label": "Read the inscription",
             "lines": ["'Growth, Stillness, Fire, Light and Memory. Each land keeps one fragment. Together they open the way.'"]}]},
        {"type": "inspect", "text": "Recover the ancient relic", "pos": [327, -25], "model": "altar", "color": [1.0, 0.45, 0.15], "label": "Take the relic",
         "give": {"ancient_relic": 1},
         "lines": ["On the altar lies a carved disc of black stone. Five hollows ring its edge, one already filled with a red shard.", "This must be what Aurelia is looking for."]},
        {"type": "talk", "text": "Bring the relic to Aurelia", "npc": "aurelia",
         "lines": ["By the old stones... a Warden relic! Five hollows - five seals, five fragments.",
                   "The inscriptions say the Heart sleeps under the five lands. If the seals are failing, the fragments are the key.",
                   "Take this mantle. It kept me alive out here; it'll keep you alive near the lava.",
                   "And go to Glow Hollow. Wren the herbalist wrote me that her plants are dying. I fear it's all the same sickness."]},
    ],
    "rewards": {"coins": 200, "xp": 300, "items": {"ember_mantle": 1}, "text": "the Ember Relic"}}

Q["glowing_heart"] = {
    "title": "The Glowing Heart", "type": "main", "chapter": 4, "region": "Glow Hollow", "giver": "wren", "requires": ["beneath_ashes"],
    "description": "The glowing plants of Glow Hollow are dying and violet crystals are spreading. Wren needs to know why.",
    "offer": ["Aurelia sent you? Then you've seen the violet crystals. They're here too.",
              "My moonbells have gone dark. The glowcaps are turning grey. And these crystals push up through the moss like bruises.",
              "Find the corrupted crystals, bring me samples, and find where it's coming from."],
    "accept": ["Start with the withered patch just south of my hut. Be gentle with the plants."],
    "progress_lines": ["Bring me samples of the corrupted crystals, and find where the sickness starts."],
    "steps": [
        {"type": "inspect", "text": "Investigate the disappearance of the glowing plants", "pos": [45, 250], "model": "plant", "color": [0.4, 0.4, 0.42],
         "label": "Examine the withered plants",
         "lines": ["The moonbells here are grey and brittle, drained of light. Thin violet veins run through the soil, all pointing south."]},
        {"text": "Find the corrupted crystals and collect samples", "goals": [
            {"type": "inspect", "text": "Sample the western crystal", "pos": [-60, 280], "model": "crystal", "color": [0.7, 0.3, 1.0], "label": "Take a sample", "give": {"crystal_sample": 1},
             "lines": ["The crystal is warm. Something flickers inside it, like an eye."]},
            {"type": "inspect", "text": "Sample the eastern crystal", "pos": [60, 300], "model": "crystal", "color": [0.7, 0.3, 1.0], "label": "Take a sample", "give": {"crystal_sample": 1},
             "lines": ["It cracks off with a sound like a bell."]},
            {"type": "inspect", "text": "Sample the southern crystal", "pos": [10, 340], "model": "crystal", "color": [0.7, 0.3, 1.0], "label": "Take a sample", "give": {"crystal_sample": 1},
             "lines": ["The violet veins under this one are thick as roots. They run south, toward the heart of the Hollow."]}]},
        {"type": "reach", "text": "Locate the source of the corruption", "pos": [-25, 385], "radius": 18,
         "lines": ["The heart of the Hollow. The great crystal here pulses violet... and something huge is wrapped around it."]},
        {"type": "boss", "text": "Defeat the mutated guardian", "boss": "mutated_guardian", "pos": [-25, 380]},
        {"type": "deliver", "text": "Report the findings to the Herbalist", "npc": "wren", "item": "crystal_sample", "count": 3,
         "lines": ["You're back! And the Hollow... I can hear it humming again.",
                   "These samples - they're not from here. They're the island's own heart-light, twisted. Something below is feeding on it.",
                   "Take this crystal, cleansed in my spring. And my best remedy; you'll need it.",
                   "Go to Elder Tobin. Whatever the Wardens sealed, it's time someone opened the way to it."]},
    ],
    "rewards": {"coins": 180, "xp": 320, "items": {"magic_crystal": 1, "elixir": 3}}}

Q["five_fragments"] = {
    "title": "The Five Fragments", "type": "main", "chapter": 5, "region": "All regions", "giver": "elder", "requires": ["glowing_heart"],
    "description": "The Wardens' seal was made of five fragments, one hidden in each land. Find the clues on the Warden stones, recover the fragments and open the Ancient Sanctuary.",
    "offer": ["The relic... five hollows. And the inscriptions name the fragments: Growth, Stillness, Fire, Light and Memory.",
              "The Wardens hid one in each land. My map fragment marks a Warden stone in every region; each stone holds a clue.",
              "Bring me all five. Then we open the sanctuary in the meadow, the sealed one we've walked past all our lives."],
    "accept": ["The clue stones are marked on your map. Go carefully."],
    "progress_lines": ["Five fragments. The Warden stones in each land will point the way."],
    "steps": [
        {"text": "Collect the five ancient fragments", "goals": [
            {"type": "have", "item": "fragment_meadow", "text": "Fragment of Growth (Hub Meadow)", "pos": [-50, 122]},
            {"type": "have", "item": "fragment_frost", "text": "Fragment of Stillness (Frost Peaks)", "pos": [-10, -325]},
            {"type": "have", "item": "fragment_ember", "text": "Fragment of Fire (Ember Wastes)", "pos": [260, -49]},
            {"type": "have", "item": "fragment_glow", "text": "Fragment of Light (Glow Hollow)", "pos": [60, 282]},
            {"type": "have", "item": "fragment_town", "text": "Fragment of Memory (Brickton)", "pos": [-308, -68]}]},
        {"type": "talk", "text": "Return to Brickton and present the fragments to the Elder", "npc": "elder",
         "lines": ["All five... I never thought I'd see them together. Feel how they hum against each other.",
                   "The sanctuary door in the meadow has five hollows. Set them in their places and the way will open.",
                   "Whatever waits below - you won't face it alone. Brickton is with you."]},
        {"text": "Unlock the Ancient Sanctuary", "goals": [
            {"type": "place", "item": "fragment_meadow", "pos": [-46, -24], "model": "altar", "color": [0.4, 1.0, 0.4], "label": "Set the Fragment of Growth", "text": "Set the Fragment of Growth"},
            {"type": "place", "item": "fragment_frost", "pos": [-43, -23], "model": "altar", "color": [0.85, 0.95, 1.0], "label": "Set the Fragment of Stillness", "text": "Set the Fragment of Stillness"},
            {"type": "place", "item": "fragment_ember", "pos": [-40, -22.6], "model": "altar", "color": [1.0, 0.4, 0.15], "label": "Set the Fragment of Fire", "text": "Set the Fragment of Fire"},
            {"type": "place", "item": "fragment_glow", "pos": [-37, -23], "model": "altar", "color": [0.3, 1.0, 0.9], "label": "Set the Fragment of Light", "text": "Set the Fragment of Light"},
            {"type": "place", "item": "fragment_town", "pos": [-34, -24], "model": "altar", "color": [1.0, 0.85, 0.35], "label": "Set the Fragment of Memory", "text": "Set the Fragment of Memory"}]},
    ],
    "on_complete_flags": ["sanctuary_open"],
    "epilogue": ["The five fragments flare. With a sound like a held breath let go, the great stone door sinks into the earth.", "The Ancient Sanctuary is open."],
    "rewards": {"xp": 400, "coins": 150, "text": "access to the Ancient Sanctuary"}}

Q["awakening"] = {
    "title": "The Awakening", "type": "main", "chapter": 6, "region": "Ancient Sanctuary", "auto": True, "requires": ["five_fragments"],
    "description": "The sanctuary is open. Whatever the Wardens sealed is waking beneath it, and the Ancient Guardian waits within.",
    "npcs": {"warden": npc("Oren, the Last Warden", "male", [0.35, 0.4, 0.55], [0.25, 0.25, 0.3], [0.85, 0.85, 0.9], ["hood", "staff", "beard"],
                           extra={"hood_color": [0.3, 0.35, 0.5]}, lines=["..."], mode="work", face=180)},
    "steps": [
        {"type": "reach", "text": "Enter the newly unlocked sanctuary", "pos": [-40, -34], "radius": 5,
         "lines": ["Cold air rises from below. The walls are covered in paintings, and the floor hums under your boots."]},
        {"text": "Investigate the ancient chamber", "goals": [
            {"type": "inspect", "text": "Study the mural of the Wardens", "pos": [-50, -42], "model": "inscription", "color": [0.7, 0.4, 1.0], "label": "Study the mural",
             "lines": ["Figures in hooded robes kneel around a vast light beneath the island. Roots and veins of light run from it into five lands."]},
            {"type": "inspect", "text": "Study the mural of the Guardian", "pos": [-30, -42], "model": "inscription", "color": [0.7, 0.4, 1.0], "label": "Study the mural",
             "lines": ["A giant of crystal stands over the sleeping light. Its eyes are closed. Beneath it, the words: 'Watch, and never wake.'"]},
            {"type": "inspect", "text": "Study the broken mural", "pos": [-40, -52], "model": "inscription", "color": [0.7, 0.4, 1.0], "label": "Study the mural",
             "lines": ["The last panel is cracked. The light below has grown violet and hungry, and the Guardian's eyes are open."]}]},
        {"type": "defend", "text": "Survive the waves of corrupted creatures", "pos": [-40, -40], "radius": 22, "from": [0, -1], "spawn_dist": 10,
         "waves": [[["frost_spirit", 2, {"tint": [0.7, 0.3, 1.0], "health": 1.3}]],
                   [["fire_salamander", 3, {"tint": [0.7, 0.3, 1.0]}], ["mushroom_beetle", 1, {"tint": [0.7, 0.3, 1.0]}]],
                   [["ice_troll", 1, {"tint": [0.7, 0.3, 1.0], "health": 1.3}], ["frost_spirit", 2, {"tint": [0.7, 0.3, 1.0]}]]]},
        {"type": "inspect", "text": "Discover the truth about the island", "pos": [-40, -40], "model": "altar", "color": [0.75, 0.4, 1.0], "label": "Touch the central altar", "range": 3.0,
         "lines": ["As your hand touches the altar, a voice fills the chamber.",
                   "'The island is alive. Its Heart sleeps below, and its dreams are the light in the crystals, the warmth in the lava, the green of the meadow.'",
                   "'But the Heart hungers. We Wardens bound its hunger with five seals and set a Guardian to watch. Now the seals have failed, and the Guardian wakes as the Heart's own fist.'",
                   "'Free the Guardian from the Heart's grip - break its crown - and the Heart will sleep again.'",
                   "The floor shakes. Something enormous rises from the dark."]},
        {"type": "boss", "text": "Face and defeat the Ancient Guardian", "boss": "ancient_guardian", "pos": [-40, -46]},
        {"type": "talk", "text": "Complete the final interaction", "npc": "warden", "pos": [-40, -36],
         "lines": ["It is over. The Guardian is free, and the Heart sleeps. I can feel it in my bones, what's left of them.",
                   "You know me, I think. The stranger at midnight. My name is Oren, the last of the Wardens. I have waited a very long time for someone like you.",
                   "Because of you, the beasts will calm, the crystals will fade, and the travellers will come back to Brickton.",
                   "But the seals are still broken. The Heart will dream again, and someone must keep watch.",
                   "Take the Wardens' blade from the Guardian's crown: Dawnbreaker. It is yours now. The island has a new Warden."]},
    ],
    "on_complete_flags": ["chapter1_complete"],
    "epilogue": ["Across the island, the violet crystals dim. In Brickton, a bell rings: the first caravan in weeks is at the gate.", "CHAPTER ONE COMPLETE: THE SHATTERED ISLAND"],
    "rewards": {"coins": 600, "xp": 800, "items": {"dawnbreaker": 1}, "rep": 50, "text": "completion of Chapter One"}}

# ------------------------------------------------------------------ SIDE QUESTS

Q["lost_merchant"] = {
    "title": "The Lost Merchant", "type": "side", "region": "Hub Meadow", "giver": "hale",
    "description": "Hale the merchant lost his supply bag when wolves spooked his cart on the north road.",
    "offer": ["Ah, a customer! Well, I'd sell you something if I had anything left.",
              "Wolves spooked my cart on the north road this morning. Tipped the lot. My supply bag rolled off somewhere and I wasn't going back for it.",
              "Find it and I'll give you a discount for life. Well, twenty percent. For life."],
    "accept": ["The cart's still up the north road, past the meadow loop. Mind the wolves!"],
    "progress_lines": ["My cart's up the north road. The bag can't have gone far. Wolves don't eat paperwork. I hope."],
    "steps": [
        {"type": "inspect", "text": "Investigate the merchant's last known location", "pos": [8, -92], "model": "wagon", "label": "Search Hale's cart", "range": 4.0,
         "lines": ["The cart lies on its side, one wheel gone. Wolf tracks everywhere, and a trail of spilled pepper heading north-east."]},
        {"type": "kill", "text": "Drive off the wolves guarding the trail", "spawn": {"species": "wolf", "count": 3, "pos": [38, -128], "radius": 7}},
        {"type": "collect", "text": "Find the missing supply bag", "item": "supply_bag", "spots": [[41, -133]], "model": "bag", "label": "Pick up the supply bag"},
        {"type": "deliver", "text": "Return the bag to Hale", "npc": "hale", "item": "supply_bag", "count": 1,
         "lines": ["My bag! Paperwork, needles, the good pepper... all here!", "A deal's a deal. Twenty percent off at any merchant who knows my name, which is all of them."]},
    ],
    "rewards": {"coins": 100, "xp": 120, "flags": ["merchant_discount"], "text": "20% discount at merchants"}}

Q["blacksmith_request"] = {
    "title": "The Blacksmith's Request", "type": "side", "region": "Brickton", "giver": "smith", "requires": ["island_heart"],
    "description": "Bram can strengthen your blade further, but he needs iron from the Frost Peaks, obsidian from the Ember Wastes and a troll's hide for the grip.",
    "offer": ["That blade of yours could be better. Much better.",
              "Bring me three lumps of iron ore from the Frost Peaks, two pieces of obsidian from the Ember Wastes, and an ice troll's hide for the grip.",
              "Then we'll see what this anvil can really do."],
    "accept": ["Iron veins show rust-red in the snow along the north path. Obsidian's black and glassy, east of the scholar's camp."],
    "progress_lines": ["Three iron, two obsidian, one troll hide. My anvil's waiting."],
    "steps": [
        {"text": "Collect the materials", "goals": [
            {"type": "collect", "text": "Iron ore from the Frost Peaks", "item": "iron_ore", "spots": [[-15, -240], [8, -262], [-15, -306]], "model": "shard", "color": [0.55, 0.35, 0.3], "label": "Mine the iron ore"},
            {"type": "collect", "text": "Obsidian from the Ember Wastes", "item": "obsidian", "spots": [[250, -26], [267, 23]], "model": "shard", "color": [0.08, 0.06, 0.1], "label": "Break off the obsidian"},
            {"type": "kill", "text": "An ice troll's hide", "give": {"troll_hide": 1}, "spawn": {"species": "ice_troll", "count": 1, "pos": [12, -297], "radius": 2}}]},
        {"type": "deliver", "text": "Return the materials to Bram", "npc": "smith", "items": {"iron_ore": 3, "obsidian": 2, "troll_hide": 1}, "item": "iron_ore", "count": 3,
         "lines": ["Now that's proper iron. And obsidian for the edge... troll hide for the grip. Give me a moment.",
                   "*clang* *clang* *hiss*", "There. Feel the balance. That'll bite deeper than anything on this island."]},
    ],
    "rewards": {"smith": 1, "coins": 50, "xp": 200, "text": "sword upgrade (+12% damage)"}}

Q["hunters_challenge"] = {
    "title": "A Hunter's Challenge", "type": "side", "region": "Frost Peaks", "giver": "brann",
    "description": "Brann the hunter challenges you to track and defeat Greymane, the giant wolf of the peaks.",
    "offer": ["You've got the look of someone who thinks they're good with a blade.",
              "There's a wolf up here, Greymane. Twice the size of any wolf you've seen. Killed three of my dogs.",
              "Track her down and put her in the snow, and I'll give you my spare blade and my best leathers."],
    "accept": ["Her tracks start south-east of the lodge. Big as dinner plates. You can't miss them."],
    "progress_lines": ["Greymane's tracks lead south-east. Follow them up the slope."],
    "steps": [
        {"type": "inspect", "text": "Find Greymane's tracks", "pos": [58, -292], "model": "tracks", "dir": [1, -1], "label": "Examine the huge paw prints",
         "lines": ["Paw prints wider than your hand. Fresh. She went up the slope."]},
        {"type": "inspect", "text": "Track the target", "pos": [72, -314], "model": "tracks", "dir": [0.6, -1], "label": "Follow the trail",
         "lines": ["Tufts of silver fur caught on the rocks. And a smell of blood. She's close."]},
        {"type": "boss", "text": "Defeat Greymane", "boss": "greymane", "pos": [86, -330]},
        {"type": "talk", "text": "Return to Brann for the reward", "npc": "brann",
         "lines": ["You did it? You actually did it! Ha!", "Here, my spare falchion and the leathers. You've earned them, and the right to tell everyone in Brickton."]},
    ],
    "rewards": {"coins": 160, "xp": 250, "items": {"hunter_blade": 1, "hunter_leathers": 1}}}

Q["missing_caravan"] = {
    "title": "The Missing Caravan", "type": "side", "region": "Ember Wastes", "giver": "nadia",
    "description": "Nadia Ostrander's husband led a caravan through the Ember Wastes. It never arrived.",
    "offer": ["You're heading east? Please, listen. My husband's caravan was crossing the Ember Wastes four days ago.",
              "It never arrived. The guards haven't come back either.",
              "Find out what happened. And if the strongbox survived... it's everything we own."],
    "accept": ["They take the east road, past the scholar's camp. Bring me news, whatever it is."],
    "progress_lines": ["The caravan takes the east road. Please hurry."],
    "steps": [
        {"type": "inspect", "text": "Locate the caravan's last known position", "pos": [269, 56], "model": "wagon", "label": "Search the burned wagon", "range": 4.0,
         "lines": ["A wagon on its side, its canvas burned. No bodies, thank the stones. Boot prints lead south, running."]},
        {"type": "inspect", "text": "Investigate the abandoned route", "pos": [281, 80], "model": "tracks", "dir": [0.3, 1], "label": "Examine the scorch marks",
         "lines": ["Scorch marks and salamander tracks, dozens of them. Something heavy was dragged south, toward the vents."]},
        {"type": "inspect", "text": "Discover what happened", "pos": [286, 94], "model": "inscription", "color": [0.9, 0.6, 0.3], "label": "Read the note on the post",
         "lines": ["A note nailed to a post: 'Salamanders by the hundred. We ran north for the road. Couldn't save the box. Sorry, Nadia. - Piet'",
                   "They escaped! But the strongbox is somewhere in the nest."]},
        {"type": "kill", "text": "Defeat the creatures responsible", "spawn": {"species": "fire_salamander", "count": 5, "pos": [290, 100], "radius": 7}},
        {"type": "collect", "text": "Recover the caravan's valuable cargo", "item": "caravan_cargo", "spots": [[292, 104]], "model": "chest", "label": "Recover the strongbox"},
        {"type": "deliver", "text": "Return the strongbox to Nadia", "npc": "nadia", "item": "caravan_cargo", "count": 1,
         "lines": ["Piet's alive? He wrote that? Oh, the fool, the wonderful fool.", "And the box! Here, take a share. Materials from the east are worth a fortune in Brickton."]},
    ],
    "rewards": {"coins": 220, "xp": 260, "items": {"obsidian": 3, "golem_core": 1, "starsteel": 1}, "text": "rare materials"}}

Q["herbalist_collection"] = {
    "title": "The Herbalist's Collection", "type": "side", "region": "Glow Hollow", "giver": "wren",
    "description": "Wren needs moonbell flowers and glowcap mushrooms for an experiment.",
    "offer": ["Do you know your flowers? No? You'll learn.", "I need five moonbells and three glowcaps for a new remedy. They glow at the edges of the Hollow."],
    "accept": ["Blue for moonbells, teal for glowcaps. Pick gently."],
    "progress_lines": ["Five moonbells, three glowcaps."],
    "steps": [
        {"text": "Find the required plants", "goals": [
            {"type": "collect", "text": "Moonbell flowers", "item": "moonbell", "spots": [[30, 240], [-20, 265], [75, 285], [-45, 320], [30, 360]], "model": "plant", "color": [0.45, 0.6, 1.0], "label": "Pick the moonbell"},
            {"type": "collect", "text": "Glowcap mushrooms", "item": "glowcap", "spots": [[5, 230], [95, 260], [-70, 300]], "model": "plant", "color": [0.2, 1.0, 0.8], "label": "Pick the glowcap"}]},
        {"type": "deliver", "text": "Return the ingredients to Wren", "npc": "wren", "items": {"moonbell": 5, "glowcap": 3}, "item": "moonbell", "count": 5,
         "lines": ["Perfect specimens! Now, a pinch of this, a drop of that...", "Here, fresh remedies, and something for your trouble."]},
    ],
    "rewards": {"coins": 90, "xp": 150, "items": {"elixir": 2, "potion": 3}}}

Q["forgotten_explorer"] = {
    "title": "The Forgotten Explorer", "type": "side", "region": "Frost Peaks", "giver": "mira",
    "description": "Mira's brother Edric disappeared while studying the ruins in the Frost Peaks.",
    "offer": ["My brother Edric went to study the old ruins in the Frost Peaks a month ago. He writes to me every week.", "He hasn't written in three. Please, find out what happened to him."],
    "accept": ["The ruins are west along the ridge path, beyond the expedition camp. Thank you."],
    "progress_lines": ["The ruins are far west along the ridge path. Please find him."],
    "steps": [
        {"type": "reach", "text": "Discover the explorer's last known location", "pos": [-166, -305], "radius": 14,
         "lines": ["The Frostbound Ruins. Snow drifts against broken walls, and there's a cold campfire in the lee of a pillar."]},
        {"type": "inspect", "text": "Find his journal", "pos": [-161, -300], "model": "journal", "label": "Pick up the journal", "give": {"explorer_journal": 1},
         "lines": ["Edric's journal, half buried in snow. Pages are torn out. The last entry: 'The pages blew away in the storm. If I don't make it back, the ice tomb holds my answer.'"]},
        {"type": "collect", "text": "Collect the missing journal pages", "item": "journal_page", "spots": [[-150, -290], [-174, -296], [-145, -312]], "model": "page", "label": "Pick up the page"},
        {"type": "inspect", "text": "Discover the explorer's fate", "pos": [-152, -293], "model": "crystal", "color": [0.6, 0.85, 1.0], "size": 2.2, "label": "Look into the ice",
         "lines": ["Inside a pillar of clear ice: Edric, peaceful, his hand pressed flat against the ice as if holding something in.",
                   "His pages explain: the violet frost was spreading toward the ruins. He used the last of his lamp oil to seal the vault with ice, and stayed too long.",
                   "Mira deserves to know he was brave."]},
        {"type": "deliver", "text": "Return the journal to Mira", "npc": "mira", "item": "explorer_journal", "count": 1,
         "lines": ["...He always said the mountains would keep him.", "Thank you for bringing his words home. Take his compass. It will show you the places he never got to see."]},
    ],
    "rewards": {"coins": 140, "xp": 200, "items": {"explorer_compass": 1}, "text": "Edric's Compass (reveals undiscovered places on the map)"}}

Q["trouble_gates"] = {
    "title": "Trouble at the Gates", "type": "side", "region": "Brickton", "giver": "harlan",
    "description": "Monsters are gathering east of Brickton. Captain Harlan needs a fighter at the gate.",
    "offer": ["You there. My scouts say a pack is gathering east of town, wolves and worse.", "They'll hit the gate within the hour. I could use your sword."],
    "accept": ["Get the gate ready: ask Ivo to brace it and Gerta for supplies. Then hold the line with us."],
    "progress_lines": ["Talk to Ivo and Gerta, then meet us at the gate."],
    "steps": [
        {"text": "Prepare for the attack", "goals": [
            {"type": "talk", "text": "Ask Ivo to brace the gate", "npc": "ivo", "lines": ["Brace the gate? Say no more. I'll have planks across it in a minute."]},
            {"type": "talk", "text": "Ask Gerta for supplies", "npc": "gerta", "give": {"potion": 2}, "lines": ["Supplies? Take these draughts. And come back in one piece, I'll have stew waiting."]}]},
        {"type": "defend", "text": "Defeat the incoming enemies and protect the gate", "pos": [-192, 2], "radius": 30, "raid": True, "from": [1, 0], "spawn_dist": 26,
         "waves": [[["wolf", 3]], [["boar", 2], ["wolf", 1]], [["mushroom_beetle", 1], ["wolf", 2]]]},
        {"type": "talk", "text": "Report back to the guard captain", "npc": "harlan",
         "lines": ["That's the last of them. Not a single beast got through!", "Brickton owes you. I'll make sure everyone knows it."]},
    ],
    "rewards": {"coins": 150, "xp": 220, "rep": 25, "text": "Brickton reputation"}}

Q["hidden_treasure"] = {
    "title": "The Hidden Treasure", "type": "side", "region": "Hub Meadow",
    "trigger": {"pos": [60, 62], "label": "Pick up the old map", "lines": ["An old map is tucked behind a loose stone in the mill wall.", "Three marks, and a rhyme: 'Where two stones stand and never speak, where one tree stands alone on the peak, dig where the meadow meets the creek.'"]},
    "description": "An old treasure map found in the mill ruins. Three marks and a rhyme lead to buried treasure.",
    "offer": ["Follow the map's clues?"],
    "steps": [
        {"type": "inspect", "text": "'Where two stones stand and never speak'", "pos": [-110, 92], "model": "marker", "label": "Search between the stones",
         "lines": ["Scratched into the base of one stone: an arrow pointing east, and the words 'the lonely tree'."]},
        {"type": "inspect", "text": "'Where one tree stands alone on the peak'", "pos": [115, -62], "model": "marker", "label": "Search the roots", "give": {"chest_key": 1},
         "lines": ["Wedged in the roots: a small brass key, green with age."]},
        {"type": "inspect", "text": "'Dig where the meadow meets the creek'", "pos": [135, 112], "model": "marker", "label": "Dig here",
         "lines": ["You dig. Two feet down, your hands strike wood: an iron-bound chest."]},
        {"type": "inspect", "text": "Unlock the treasure chest", "pos": [135, 112], "model": "chest", "label": "Unlock the chest", "needs": "chest_key",
         "missing": "It's locked with a brass lock.",
         "lines": ["The key turns with a crunch. Coins, a bar of strange metal, and three coins stamped with a crowned tree."]},
    ],
    "rewards": {"coins": 300, "xp": 200, "items": {"starsteel": 1, "ancient_coin": 3, "elixir": 1}, "text": "rare loot"}}

Q["strange_crystal"] = {
    "title": "A Strange Crystal", "type": "side", "region": "Glow Hollow",
    "trigger": {"reach": True, "pos": [125, 330], "radius": 14, "lines": ["This crystal hums at a different pitch from the others. Around it, three carved stones lean inward as if listening."]},
    "description": "A crystal formation in Glow Hollow that behaves differently from the others: it sings.",
    "offer": ["Investigate the singing crystal?"],
    "steps": [
        {"type": "inspect", "text": "Investigate the crystal", "pos": [125, 330], "model": "crystal", "color": [0.4, 0.9, 1.0], "size": 2.6, "label": "Touch the crystal",
         "lines": ["The crystal's note changes under your hand. One of the carved stones answers with a faint glow."]},
        {"text": "Interact with the resonance stones", "goals": [
            {"type": "inspect", "text": "West resonance stone", "pos": [113, 322], "model": "stone", "label": "Strike the stone", "lines": ["A deep note. The crystal brightens."]},
            {"type": "inspect", "text": "East resonance stone", "pos": [137, 322], "model": "stone", "label": "Strike the stone", "lines": ["A middle note. The crystal answers."]},
            {"type": "inspect", "text": "South resonance stone", "pos": [125, 345], "model": "stone", "label": "Strike the stone", "lines": ["A high note. All three ring together."]}]},
        {"type": "inspect", "text": "Discover the source of its behaviour", "pos": [125, 330], "model": "crystal", "color": [0.9, 0.9, 1.0], "size": 2.6, "label": "Listen to the crystal",
         "lines": ["The chord rings out... and from far below, something answers. A slow beat, like a heart.", "The crystal isn't corrupted. It's a Warden's listening stone, still tuned to the Heart. And something has heard you listening."]},
        {"type": "kill", "text": "Defeat the creatures protecting it", "spawn": {"species": "frost_spirit", "count": 3, "pos": [125, 336], "radius": 6, "elite": {"tint": [0.7, 0.3, 1.0]}}},
        {"type": "talk", "text": "Report the discovery to Wren", "npc": "wren",
         "lines": ["A listening stone? The Wardens' work... I've read of those.", "Keep this sliver of it, it's still singing. And this old sigil I found by the spring; I think it belongs with you."]},
    ],
    "rewards": {"coins": 120, "xp": 220, "items": {"rare_crystal": 1, "warden_sigil": 1}, "text": "Warden's Sigil (+8% sword damage)"}}

Q["golems_secret"] = {
    "title": "The Golem's Secret", "type": "side", "region": "Ember Wastes", "giver": "aurelia",
    "description": "A golem in the Ember Wastes that doesn't attack anyone. Aurelia wants to know why.",
    "offer": ["There's a golem north of here that doesn't attack. It just... walks. Tends the rocks.", "Golems don't do that. Watch it for me, would you? From a safe distance."],
    "accept": ["North-east of here, toward the old forge. Don't provoke it!"],
    "progress_lines": ["Watch the peaceful golem. Don't attack it."],
    "steps": [
        {"type": "reach", "text": "Locate the unusual golem", "pos": [233, -107], "radius": 25},
        {"type": "observe", "text": "Observe its behaviour (stay close, don't attack)", "target": "ashwarden", "pos": [233, -107], "radius": 14, "seconds": 10,
         "lines": ["It isn't hunting. It presses molten rock into the cracks of the ground, sealing them. Every few steps it turns toward the old forge to the south-east."]},
        {"type": "inspect", "text": "Discover its origin", "pos": [258, -146], "model": "inscription", "color": [1.0, 0.55, 0.2], "label": "Read the forge inscription",
         "lines": ["'Here the Wardens shaped the stone-keepers, to mend the land where the Heart's fire breaks through.'",
                   "The golems were caretakers. The others have been twisted by the violet fire. This one never was."]},
        {"text": "Investigate the nearby ancient structures", "goals": [
            {"type": "inspect", "text": "Search the cold furnace", "pos": [266, -152], "model": "marker", "label": "Search the furnace", "lines": ["A cracked golem core lies in the ashes, still faintly warm."]},
            {"type": "inspect", "text": "Search the stone moulds", "pos": [256, -156], "model": "marker", "label": "Search the moulds", "lines": ["Moulds shaped like giant hands. Violet crystal has grown over all of them but one."]}]},
        {"type": "kill", "text": "Defeat the hostile creatures protecting the secret", "spawn": {"species": "lava_golem", "count": 2, "pos": [262, -138], "radius": 6, "elite": {"tint": [0.7, 0.3, 1.0], "health": 1.2}}},
        {"type": "talk", "text": "Tell Aurelia what you learned", "npc": "aurelia",
         "lines": ["Caretakers! The golems were the Wardens' gardeners, mending the island. And the violet fire turned them.", "That changes everything. Here, take these, materials from the forge are priceless to a smith."]},
    ],
    "rewards": {"coins": 200, "xp": 260, "items": {"golem_core": 2, "starsteel": 1}, "text": "rare crafting materials"}}

# ------------------------------------------------------------------ SPECIAL QUESTS

Q["night_beasts"] = {
    "title": "The Night of the Beasts", "type": "special", "region": "Brickton", "giver": "harlan", "requires": ["trouble_gates"],
    "description": "The beasts are massing for a night attack on Brickton. Warn the villagers, defend the town and protect its people.",
    "offer": ["The pack you broke at the gate was a scouting party. My scouts count three times as many in the hills.",
              "They'll come after dark. When they do, I need the townsfolk indoors and you on the wall."],
    "accept": ["Rest at the inn until nightfall if you need to. When it's dark, warn everyone you can."],
    "progress_lines": ["When night falls, get the townsfolk inside, then hold the gate."],
    "unhide": True,
    "steps": [
        {"type": "night", "text": "Wait for nightfall (rest at the inn)"},
        {"type": "talk_any", "text": "Warn the villagers", "count": 4, "hide": True,
         "only": ["pell", "marta", "joss", "henna", "dorn", "gus", "hester", "tobias", "nell", "wim", "rosa", "jory", "bert", "lotte", "mads", "sanne", "baker", "lina", "kid", "kael", "bryn", "tilly", "mira", "sela", "ivo", "nadia"],
         "lines": ["Beasts? Tonight? I'm going, I'm going!", "Kit! Inside, now!", "I'll bar the door. Good luck out there.", "Get the shutters closed!"]},
        {"type": "defend", "text": "Defend the settlement and protect its civilians", "pos": [-200, 2], "radius": 35, "raid": True, "from": [1, 0.2], "spawn_dist": 28,
         "waves": [[["wolf", 4]], [["boar", 2], ["wolf", 2]], [["mushroom_beetle", 2], ["frost_spirit", 1]], [["ice_troll", 1], ["wolf", 2]]]},
        {"type": "boss", "text": "Defeat the final attacking creature", "boss": "night_terror", "pos": [-180, 4]},
        {"type": "talk", "text": "Report to Captain Harlan", "npc": "harlan",
         "lines": ["Listen. Quiet. The real kind, this time.", "Not one villager hurt. Brickton won't forget this night, and neither will I."]},
    ],
    "rewards": {"coins": 300, "xp": 400, "rep": 50, "items": {"elixir": 2}}}

Q["last_journal"] = {
    "title": "The Last Journal", "type": "special", "region": "Frost Peaks", "giver": "mira", "requires": ["forgotten_explorer"],
    "description": "Edric's journal mentions final pages scattered by a storm, and a hidden place he sealed with ice.",
    "offer": ["I read Edric's journal again. The last entries mention pages he lost in a storm, west of the ruins.", "And a place he 'sealed with ice'. What was he protecting? Please, find out."],
    "accept": ["West of the Frostbound Ruins, he said, where the path climbs to the glacier."],
    "progress_lines": ["The last pages blew west of the ruins, toward the glacier."],
    "steps": [
        {"type": "collect", "text": "Collect the scattered journal pages", "item": "last_page", "spots": [[-190, -318], [-174, -296], [-198, -332], [-218, -325]], "model": "page", "label": "Pick up the page"},
        {"type": "reach", "text": "Uncover the hidden location", "pos": [-209, -323], "radius": 9,
         "lines": ["The pages lead here: a cave in the glacier, its mouth sealed with clear ice. Three frozen lanterns stand outside."]},
        {"text": "Light the three frozen lanterns", "goals": [
            {"type": "inspect", "text": "Left lantern", "pos": [-214, -318], "model": "altar", "color": [0.6, 0.9, 1.0], "label": "Light the lantern", "lines": ["The lantern flickers to life."]},
            {"type": "inspect", "text": "Right lantern", "pos": [-204, -318], "model": "altar", "color": [0.6, 0.9, 1.0], "label": "Light the lantern", "lines": ["A second light."]},
            {"type": "inspect", "text": "Centre lantern", "pos": [-209, -316], "model": "altar", "color": [0.6, 0.9, 1.0], "label": "Light the lantern", "lines": ["The third light. The ice over the cave mouth groans and cracks."]}]},
        {"type": "inspect", "text": "Discover the explorer's final secret", "pos": [-209, -327], "model": "chest", "label": "Open Edric's cache",
         "lines": ["Inside: a letter addressed to Mira, a bundle of starsteel ingots, and a map of the island with a stranger's mark at every Warden stone.",
                   "The letter: 'Mira. I met a man in a grey hood who knows the island better than anyone alive. He says the Wardens are gone, but their work isn't. I'm helping him. Don't worry.'",
                   "Edric was working with the stranger who walks at midnight."]},
        {"type": "deliver", "text": "Bring the last pages to Mira", "npc": "mira", "item": "last_page", "count": 4,
         "lines": ["A letter... for me.", "...He wasn't lost. He was helping someone. That's so like him. Take the starsteel, he'd want it used, not hoarded."]},
    ],
    "rewards": {"coins": 250, "xp": 350, "items": {"starsteel": 2, "ancient_coin": 2}}}

Q["queen_beneath"] = {
    "title": "The Queen Beneath", "type": "special", "region": "Glow Hollow",
    "trigger": {"pos": [-90, 250], "label": "Examine the strange hole", "lines": ["A hole, wide as a cart, freshly dug. The edges are scored by enormous mandibles.", "More holes run south-west in a line."]},
    "description": "Huge burrows are appearing around Glow Hollow. Something very large is digging underneath.",
    "offer": ["Follow the burrows?"],
    "steps": [
        {"text": "Investigate the other holes", "goals": [
            {"type": "inspect", "text": "Second burrow", "pos": [-125, 295], "model": "burrow", "label": "Examine the burrow", "lines": ["Shed chitin, each plate as big as a shield."]},
            {"type": "inspect", "text": "Third burrow", "pos": [-150, 335], "model": "burrow", "label": "Examine the burrow", "lines": ["The ground trembles. Something below is moving toward the south-west."]}]},
        {"type": "reach", "text": "Follow the underground trail", "pos": [-171, 378], "radius": 22,
         "lines": ["The trail ends at a great sinkhole. At the bottom, the ground heaves... and the Beetle Queen rises from the soil."]},
        {"type": "boss", "text": "Defeat the Beetle Queen", "boss": "beetle_queen", "pos": [-171, 378]},
    ],
    "rewards": {"coins": 350, "xp": 500, "items": {"beetle_chitin": 6, "rare_crystal": 1, "starsteel": 1}}}

Q["forgotten_kingdom"] = {
    "title": "The Forgotten Kingdom", "type": "special", "region": "Brickton outskirts", "giver": "quill",
    "description": "Brickton's records mention Caldor, a kingdom older than the town. Find its ruins, its keys and its royal chamber.",
    "offer": ["You have the look of someone who finds things. Have you heard of Caldor?",
              "A kingdom, older than Brickton. Our oldest ledgers say its last king sealed his chamber with three keys: sun, moon and star.",
              "Nobody knows where its ruins are. Find them, and tell me everything."],
    "accept": ["Start by asking travellers. They see more of the island than we clerks."],
    "progress_lines": ["Sun, moon and star. Three keys, one chamber."],
    "steps": [
        {"type": "talk", "text": "Find clues about Caldor", "npc": "kael",
         "lines": ["Crowned trees carved on stones? I've seen them. South of town, past the last fields, where the grass starts to glow blue.", "There's a ring of broken walls there. I didn't go in. It felt... watched."]},
        {"type": "reach", "text": "Discover the ruins of Caldor", "pos": [-235, 192], "radius": 26,
         "lines": ["Broken walls, toppled columns, crowned trees carved on every stone. This was Caldor."]},
        {"type": "inspect", "text": "Find the hidden entrance", "pos": [-235, 181], "model": "tablet", "color": [1.0, 0.8, 0.4], "label": "Pull aside the vines",
         "lines": ["Behind the vines, a sealed stone door. Three locks: a sun, a moon, a star.",
                   "Carved beside it: 'The sun rises in order. The moon hides in the rubble. The star is kept by its guard.'"]},
        {"text": "Collect the three keys", "goals": [
            {"type": "have", "item": "sun_key", "text": "Sun Key (west hall: touch the stones in order)", "pos": [-258, 192]},
            {"type": "have", "item": "moon_key", "text": "Moon Key (east hall: find the hidden levers)", "pos": [-212, 192]},
            {"type": "have", "item": "star_key", "text": "Star Key (south court: defeat its guard)", "pos": [-235, 212]}]},
        {"type": "place", "text": "Unlock the abandoned royal chamber", "pos": [-235, 181], "items": {"sun_key": 1, "moon_key": 1, "star_key": 1}, "item": "sun_key",
         "model": "marker", "label": "Turn the three keys", "missing": "Three locks. You need the sun, moon and star keys.",
         "lines": ["Sun, moon, star. The locks turn together and the door grinds open."]},
        {"type": "inspect", "text": "Discover the chamber's treasure and history", "pos": [-235, 194], "model": "chest", "label": "Open the royal chest", "range": 3.0,
         "give": {"kingsblade": 1, "royal_plate": 1},
         "lines": ["A throne of black stone. On the wall, the story of Caldor: a kingdom that served the Wardens, until the Heart's first waking drove its people west, to found a village of brick.",
                   "Brickton was Caldor, once. The king's sword and plate lie in the chest, waiting."]},
        {"type": "talk", "text": "Tell Archivist Quill what you found", "npc": "quill",
         "lines": ["Brickton... was Caldor? Our grandfathers' grandfathers were its people?", "This rewrites every ledger I own. Thank you. Truly."]},
    ],
    "rewards": {"coins": 400, "xp": 450, "items": {"ancient_coin": 5}}}

STRANGER = {"name": "The Stranger", "outfit": {"model": "male", "jacket": [0.3, 0.32, 0.36], "pants": [0.2, 0.2, 0.24], "boots": [0.2, 0.15, 0.12],
                                               "hair": [0.85, 0.85, 0.9], "accessories": ["hood", "staff", "beard"], "hood_color": [0.32, 0.33, 0.38]},
            "mode": "work", "face": 0, "lines": {"default": ["..."]}}
Q["stranger_midnight"] = {
    "title": "The Stranger at Midnight", "type": "special", "region": "Everywhere (at night)", "auto": True, "requires": ["strange_silence"],
    "description": "A hooded traveller appears at night in different corners of the island. Each meeting reveals more about the island, and about him.",
    "npcs": {"stranger1": STRANGER, "stranger2": STRANGER, "stranger3": STRANGER, "stranger4": STRANGER, "stranger5": STRANGER},
    "steps": [
        {"type": "encounter", "text": "Meet the stranger at the standing stones (at night)", "npc": "stranger1", "pos": [-107, 96], "night": True},
        {"type": "talk", "npc": "stranger1", "text": "Speak with the stranger",
         "lines": ["You see me? Few do. Fewer still at this hour.", "These stones are older than the meadow. They listen to the island. Lately they've been hearing it toss in its sleep.",
                   "If you want to know more, look for me in the peaks, near the mountaineer's fire. At night."]},
        {"type": "encounter", "text": "Find the stranger in the Frost Peaks (at night)", "npc": "stranger2", "pos": [38, -188], "night": True},
        {"type": "talk", "npc": "stranger2", "text": "Speak with the stranger",
         "lines": ["You came. Good.", "The violet ice is the island's own light, gone sour. Something beneath is feeding on it.",
                   "A young man named Edric helped me once. Brave lad. Too brave.", "The wastes, next. By the scholar's camp."]},
        {"type": "encounter", "text": "Find the stranger in the Ember Wastes (at night)", "npc": "stranger3", "pos": [214, 30], "night": True},
        {"type": "talk", "npc": "stranger3", "text": "Speak with the stranger",
         "lines": ["Hot, isn't it? It used to be hotter. The golems kept it in check, once.", "There were five of us who kept watch. Then four. Then... well.", "Glow Hollow. Wren's hut. You know the time."]},
        {"type": "encounter", "text": "Find the stranger in Glow Hollow (at night)", "npc": "stranger4", "pos": [40, 214], "night": True},
        {"type": "talk", "npc": "stranger4", "text": "Speak with the stranger",
         "lines": ["The Hollow sings to me. It always has.", "You've asked yourself who I am. I'll tell you where it began: at the sanctuary in the meadow. Meet me on its steps."]},
        {"type": "encounter", "text": "Meet the stranger at the sanctuary steps (at night)", "npc": "stranger5", "pos": [-40, -14], "night": True},
        {"type": "talk", "npc": "stranger5", "text": "Learn the stranger's true identity",
         "lines": ["Here we are. Where I took my vows, a very long time ago.", "My name is Oren. I am the last of the Wardens who sealed the Heart. The others gave themselves to the seals; I was left to keep watch.",
                   "I am more memory than man now. I cannot hold a sword. But you can.", "Take my mantle and my sigil. When the sanctuary opens, I'll be waiting inside."]},
    ],
    "rewards": {"coins": 200, "xp": 400, "items": {"warden_mantle": 1, "warden_sigil": 1}, "text": "the Warden's Mantle"}}

# ------------------------------------------------------------------ CONTRACTS

CONTRACTS = {
    "_comment": "Repeatable monster contracts. Each template picks one of its sites; difficulty tier grows with the explorer's level (1-3): more health and damage, bigger rewards. Pay = base_coins * tier, paid once on completion.",
    "givers": ["harlan", "brann", "board"],
    "templates": [
        {"id": "golem", "title": "Golem Breaker", "desc": "A golem has been smashing the caravan road. Break it.", "species": "lava_golem", "count": 1, "elite": True,
         "sites": [[245, 40], [292, -60], [230, -40]], "base_coins": 90, "xp": 120},
        {"id": "beetles", "title": "Beetle Cull", "desc": "Beetles are digging under Glow Hollow's paths. Thin them out.", "species": "mushroom_beetle", "count": 3,
         "sites": [[-30, 250], [80, 270], [-110, 310], [40, 330]], "base_coins": 70, "xp": 100},
        {"id": "rare", "title": "Rare Prey: Ironhide Boar", "desc": "A boar with hide like iron has been tearing up the meadow farms.", "species": "boar", "count": 1, "elite": True, "elite_name": "Ironhide Boar",
         "sites": [[60, 20], [-70, -20], [100, 80], [-90, 60]], "base_coins": 80, "xp": 110},
        {"id": "den", "title": "Clear the Wolf Den", "desc": "Wolves have made a den in the frost cave north-west of the hunter's lodge.", "species": "wolf", "count": 4,
         "sites": [[-118, -232]], "base_coins": 85, "xp": 130},
        {"id": "alpha", "title": "Track the Alpha Troll", "desc": "An unusually powerful ice troll is attacking climbers.", "species": "ice_troll", "count": 1, "elite": True, "elite_name": "Frostjaw",
         "sites": [[-30, -262], [40, -236], [-14, -318]], "base_coins": 110, "xp": 160},
        {"id": "protect", "title": "Protect Hale's Wagon", "desc": "Something keeps raiding Hale's wagon at the crossroads. Stand guard.", "defend": True,
         "pos": [22, -8], "waves": [[["wolf", 2]], [["boar", 1], ["wolf", 1]]], "base_coins": 75, "xp": 110},
        {"id": "salamanders", "title": "Vent Patrol", "desc": "Salamanders are swarming near the scholar's camp.", "species": "fire_salamander", "count": 5,
         "sites": [[230, 30], [250, -20]], "base_coins": 70, "xp": 100},
    ]}

data = {
    "_comment": "Generated by tools/content/build_quests.py. Quests: type main/side/special; giver (npc id) or trigger (start by examining/reaching something) or auto (starts when its prerequisites are done); requires = quest ids; steps = goals (see scripts/quests.gd); rewards given exactly once.",
    "quests": Q, "contracts": CONTRACTS}

with open(OUT, "w") as f:
    json.dump(data, f, indent=1)
print("wrote", OUT, len(Q), "quests")
