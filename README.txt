RIFTBORN  -  a native Apple Silicon action-roguelike
=====================================================

Prince of Persia movement, Diablo dungeons, StarCraft-flavoured factions,
NPCs with memory, and a fully synthesized techno/dubstep soundtrack.
Pure Swift + SpriteKit + AVAudioEngine. No assets, no dependencies.

Build:   ./build.sh
Play:    open build/Riftborn.app
         (or build/Riftborn.app/Contents/MacOS/Riftborn --fullscreen --fps)
Test:    build/Riftborn.app/Contents/MacOS/Riftborn --selftest   (headless 4-min autopilot)
         bash smoketest.sh                                       (boots the real window)
Reset:   build/Riftborn.app/Contents/MacOS/Riftborn --reset      (erases your chronicle)

Controls (keyboard / gamepad)
  A D / stick        move
  W or Space / A     jump  (hold toward a wall mid-air = wall-run; jump off wall = wall-jump)
  S + jump           drop through a ledge
  J / X              attack (3-hit combo, third hit heavy)
  K / RB             dash (brief invulnerability)
  L / LB             block; tap just before a hit = PARRY (stuns attacker); blocking reflects bolts
  E / Y              speak / decide a broken enemy's fate / use shrine
  Q / B              cast power      R / RT  cycle power
  1 2 3              dialogue and portal choices (LB / RB / LT on gamepad)
  Esc / Menu         pause + read your Chronicle

What makes it yours
  Souls: every enemy and wanderer is a named Soul with a faction (Hive, Iron Wardens,
    Echoes), a motive (vengeance, duty, hunger, faith, fear, redemption, curiosity) and a
    backstory. They speak before fighting and fight differently by motive.
  Consequences persist: spare someone and they owe you (may return as an ally); be cruel
    and they hold a grudge; kill someone and their kin may hunt you later; die and your
    killer levels up and comes back (nemesis).
  Faction reputation changes how beings greet you and what the depths spawn.
  Portals: at the end of each depth you choose a mutator that reshapes the next one.
  Progression: levels, shards, shrine powers (Psi Storm, Blink, Chrono Slow,
    Swarm Spawn, Overcharge). Depths are infinite and seed-deterministic.
  Music: 128 BPM house when exploring, crossfading into 140 BPM half-time wobble bass
    when enemies engage. Key and chord progression change per depth.

Save file: ~/Library/Application Support/Riftborn/chronicle.json
