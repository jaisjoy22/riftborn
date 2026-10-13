# Riftborn v3 implementation plan

## 0. Contract, scope, and evidence

- Deliver an original procedural cinematic platformer, not a literal asset remake.
- Prioritize readable people, ledge traversal, committed swordplay, and clean staging.
- Retain SpriteKit, AppKit, AVFoundation, GameController, and native arm64.
- Build with `./build.sh`; retain Swift 5 language mode and optimized WMO.
- No packages, downloaded assets, copied sequences, or offline Metal tooling.
- Implementation ceiling: 4,000 changed source lines, including new tests.
- This document is a plan; performance and gameplay acceptance remain unexecuted.
- Existing timings in the brief are baseline reports, not new measurements.
- Read the brief, RE notes, and digest in that order.
- Digest omissions required narrow source clarification, not additional RE research.
- `GameScene.play(_:)` was referenced but its combat/HUD integration was omitted.
- `Being` was truncated before its update and reaction signatures.
- `World.solidAt(_:)` did not establish `at(_:_:)` boundary behavior.
- `Input.poll()` did not establish the existing up/jump alias and controller mapping.
- Those ambiguities were resolved in the corresponding Swift files only.
- No SDLPoP source was opened; no implementation code is reproduced here.
- Sequence labels establish separate jump, catch, hang, climb, and release states.
- They do not establish exact durations; all proposed timings below are original.
- Preserve existing combat probability tables; do not import additional tables.
- Treat the RE notes' PoP2 lineage claim as context, not independently verified fact.
- Names marked NEW are proposed additions, not claims about the current digest.
- Existing names retain their current spelling and external argument labels.

### Ordered delivery and cut line

1. Establish deterministic fixtures and protect current tests.
2. Replace mannequin silhouettes and improve baked platform readability.
3. Add grab/hang/climb, careful movement, crouch, and distinct jumps.
4. Tighten directional attacks, guard break, reactions, and death presentation.
5. Fix spawn staging, HUD targeting, and nameplate collisions.
6. Add a small procedural dressing/interaction set without generation rewrites.
7. Tune audio, then run the complete acceptance matrix and performance gates.

- Phases 1–5 are mandatory before adding extra environment mechanics.
- Phase 6 ships pillars, an exit frame, red/green potions, and one plate/gate pair.
- Defer loose-floor simulation and chompers/blades to a later version.
- Defer full ragdolls, cloth physics, IK systems, new factions, and story rewrites.
- Defer climb-down initiation and shimmying; falling catch and hang-drop ship now.
- Do not describe deferred hazards or photorealistic PS4 fidelity as delivered.
- If the source ceiling is threatened, cut plate/gate first, then reverb expansion.
- Keep silhouette, traversal, directional combat, HUD, and their tests intact.

## 1. Baseline and deterministic harness

### Sources/main.swift

- MODIFY `selfTest() -> Int32`; keep the existing ten-depth autopilot intact.
- Keep its combat-phase contract and duel harness; add independent fixtures.
- NEW `enum V3Fixture: String` with cases overview, ledge, combat, crowd, props.
- NEW `func prepareV3Fixture(_ scene: GameScene, _ fixture: V3Fixture)`.
- NEW `func runV3Tests(_ failures: inout [String])`.
- NEW `func resetTestInput(_ input: Input)`; clear keys/synthetic and poll twice.
- NEW `func advanceTest(_ scene: GameScene, frames: Int, acts: Set<Act>)`.
- Use fixed `1.0 / 60.0` steps, seeded `RNG`, and a fresh scene per fixture.
- Poll inputs once per simulation step; do not simulate a hit with a held key.
- Test input transitions with a release step before the next press.
- Fixture seed: `0x524946544233`; use it without changing production save seeds.
- Clear fixture actors/props and carve a small arena using `World.set(_:_:_:)`.
- Use a fresh generated `World`; do not add a second level-file format.
- Keep fixture geometry inside the world boundary; out-of-bounds tiles are solid.
- Snapshot fixtures must use fixed actor clocks and deterministic visual randomness.
- NEW `--fixture <name>` and `--snapshot-frame <n>` options.
- Retain `--snapshot <png>`, `--selftest`, `--audiotest`, `--fpslog`, and `--mute`.
- MODIFY `AppDelegate.applicationDidFinishLaunching(_:)` to select fixture setup.
- Snapshot-frame default: 120; reject unknown fixtures and negative frame indices.
- Snapshot capture runs after the requested simulation steps and a render pass.
- Freeze subsequent simulation while capturing; do not capture a live racing frame.
- Existing command-line behavior without new flags must remain unchanged.

### Sources/GameScene.swift and Sources/Mind.swift

- NEW `GameScene.isTestSession: Bool = false`; set before `setup()` in test modes.
- Test sessions initialize an in-memory `Chronicle`; never load the user's save.
- NEW `GameScene.saveChronicle()`; call `chron.save()` only outside test sessions.
- Route scene persistence call sites through `saveChronicle()`.
- MODIFY `buildDepth()` to honor the in-memory seed/depth in fixture sessions.
- Keep `Chronicle`'s Codable layout, `load()`, `save()`, and `url` unchanged.
- A fixture or selftest must not require `--reset` or mutate normal progression.

### Initial acceptance

- Baseline build, original selftest, and original audiotest must pass first.
- Record build duration and steady-state FPS before adding features.
- Capture baseline overview/combat/crowd using the same fixture coordinates.
- Do not accept a manually teleported autopilot as proof of traversal correctness.
- Keep direct state fixtures separate from the unchanged progression harness.

## 2. Procedural silhouette and environment readability

### Sources/Art.swift

- KEEP `paint(_:_:_:_:)` as the cache-backed texture creation entry point.
- NEW `static func clothPanel(_ base: SKColor, variant: Int) -> SKTexture`.
- NEW `static func boot(_ base: SKColor) -> SKTexture`.
- NEW `static func healthPip() -> SKTexture`.
- NEW `static func potion(growth: Bool) -> SKTexture`.
- Cloth panels use tapered polygon silhouettes, not stretched capsules.
- Author textures at 64×96; boots at 32×48; pips at 24×32.
- Use broad folds: one dark crease, one midtone, one narrow lit edge.
- Cache keys include the full quantized RGBA and variant, not variant alone.
- Create shared textures before worker jobs; never mutate `Art.cache` in workers.
- KEEP `normalMap(from:strength:)` unused; do not restore dynamic terrain normals.
- KEEP `stone(_:variant:)` and `backWall(_:)`; repair sampling phase in World.

### Sources/Rig.swift

- MODIFY `RigStyle`; NEW defaulted `scarf: Bool = false` property.
- Retain `skin`, `cloth`, `accent`, `metal`, `scale`, `bulk`, `weapon`, and `cape`.
- MODIFY `Rig.init(_:)` to replace thigh/torso capsule silhouettes with cloth panels.
- Keep the bone hierarchy, weapon textures, and `Rig.height` contract unchanged.
- Keep the collision-sized actor envelope; garments may extend beyond it visually.
- Taper waist to 0.76 of chest width; enlarge clothed thigh width to 1.30 of baseline.
- Reduce exposed forearm width to 0.86 of baseline; boots flare to 1.18.
- Add a visible waist sash, cuff edges, and an asymmetric shoulder panel.
- Player: split trousers, short scarf, exposed forearms, narrow waist, curved blade.
- Warden: broad chest panel, squared shoulder, heavy boots, short cape.
- Echo: long split robe, narrow shoulders, tall head silhouette, staff.
- Hive: retain low crouch/claws; use segmented plates instead of human trousers.
- NEW `Rig.updateSecondary(_ dt: CGFloat, velocity: CGVector, grounded: Bool)`.
- Use two scarf sprites and two cape panels; avoid per-frame path reconstruction.
- Target cloth angle from horizontal velocity, clamped to ±0.55 radians.
- Smooth with time-based exponential response, rate 12; add subtle 4 Hz flutter.
- Flutter amplitude: 0.04 radians grounded, 0.09 airborne.
- Clamp the animation dt to 0.033 seconds; no free-running spring integration.
- Stop flutter during hit-stop and pause by passing zero simulation dt.
- MODIFY `buildKeylines()` once at construction to include garment silhouettes.
- Keep `flash(_:)` compatible with every added tintable sprite.
- MODIFY `baseColor(_:)` so damage flash restores original garment colors.
- Keep added rendering nodes bounded to eight per character.
- Do not add lights, emitters, or shaders per garment.

### Pose library

- MODIFY `Pose.run(_:)`; replace the sine-only gait with authored keyframe sampling.
- NEW static poses `runContact`, `runDown`, `runPassing`, and `runUp`.
- Mirror front/back limbs for the second half-cycle; interpolate with `Pose.lerp`.
- Sample normalized cycle positions 0.00, 0.12, 0.25, 0.38, then mirrored poses.
- Preserve the radians-like phase input expected by existing run callers.
- Drive phase from distance traveled, not elapsed time when blocked by a wall.
- Target full stride distance: 156 world units at normal running speed.
- Contact bodyY 0; down -3; passing +1; up +3 world units.
- NEW static poses `turn`, `land`, `crouch`, `hang`, and `climbPull`.
- NEW static poses `climbTuck`, `climbStand`, `jumpRun`, and `hurtHigh`.
- NEW `static func climb(_ progress: CGFloat) -> Pose`.
- Blend climbPull → climbTuck → climbStand at progress 0.0, 0.55, 1.0.
- Turn anticipation lasts 0.07 seconds visually; never delay directional input.
- Landing squash lasts 0.12 seconds; blend out without locking movement.
- Ensure hips and knees bend opposite the straight capsule-column silhouette.

### Sources/World.swift

- MODIFY `buildNode(theme:lights:)`; keep parallel 16×16-tile chunk baking.
- Existing slabH is 16: improve face shading first, not a fictitious missing slab.
- Set ledge face depth to 20 world units; retain the existing collision top.
- Add a 3-unit top lip and a 4-unit lower shadow band within the same slab.
- Draw continuous front-face joints at world-aligned intervals of two tiles.
- Background contrast target: about 0.60 of gameplay-face local luminance.
- Gameplay top edges receive a warm 2-unit highlight; no white neon outlines.
- NEW private `masonryPhase(x: Int, y: Int) -> CGPoint` for world-space phase.
- Use world coordinates for brick offsets, noise hashes, and torch attenuation.
- Never restart a masonry pattern or random seed at a chunk boundary.
- Compute lighting for every pool intersecting a chunk, including off-chunk centers.
- Retain torch pool radius 300; preserve six pooled scene lights, not per-tile lights.
- Add a 1-pixel sampling gutter around each baked chunk image.
- Map only the chunk interior to its world rect; never enlarge collision geometry.
- Use matching neighbor texels at the gutter, not transparent padding.
- Retain opaque terrain/back-wall composition where possible to reduce overdraw.

### Phase acceptance

- At 1440×900, identify the player and all factions from silhouette alone.
- At gameplay zoom, separate boots, trousers, sash, forearms, head, and blade.
- Run contacts read as planted feet; hands do not continuously orbit the torso.
- No cloth detaches or snaps across the body on a facing flip.
- Slabs read as weight-bearing surfaces; decorative background edges read as inert.
- A torch centered on a chunk seam has no brightness step or masonry reset.

## 3. Traversal with explicit authority over physics

### Sources/Core.swift

- MODIFY `Act`; NEW `.careful` action only; use existing up/down for modifiers.
- MODIFY `Input.poll()`; map left/right Shift keycodes 56/60 to `.careful`.
- Controller careful movement: left trigger in play; retain `.opt3` for menus.
- Keep all existing movement, attack, dash, block, and interaction bindings.
- Keyboard W/up currently also emits jump; preserve that legacy outside modifiers.
- Attack+up consumes the jump alias; hanging uses up as climb, not jump impulse.
- NEW `Input.suppressesHardware: Bool = false`; fixture inputs set it true.
- With hardware suppressed, `poll()` builds state from `synthetic` only.

### Sources/World.swift: collision queries

- NEW `struct LedgeAnchor` with `tileX: Int`, `tileY: Int`, `facing: CGFloat`.
- NEW `LedgeAnchor.corner: CGPoint`; derive from tile coordinates and facing.
- Facing +1 catches the platform's left edge; facing -1 catches its right edge.
- NEW `func bodyFits(_ rect: CGRect) -> Bool`.
- Test every overlapped tile using floor-based indices and inset epsilon 0.01.
- Solid tiles block fit; one-way ledges do not block lateral/upward occupancy.
- NEW `func supportAt(_ foot: CGPoint) -> Bool` for solid/ledge top support.
- NEW `func grabCandidate(previous: CGRect, current: CGRect, facing: CGFloat) -> LedgeAnchor?`.
- Query only the swept hand envelope's local tiles, never the entire world.
- Candidate tile must be solid or ledge, with empty space above its top.
- A solid candidate needs an exposed side; a ledge needs an endpoint, not a seam.
- Reject map borders, spikes, blocked hanging space, and blocked standing space.
- Use interpolated hand height at edge crossing, not just end-of-frame height.
- Hand height target: body top - 4; reach tolerance above/below corner: 12 units.
- Horizontal reach tolerance: 10 units beyond the leading body edge.
- Rank valid candidates by swept crossing time, then tileY/tileX deterministically.
- NEW `func climbDestination(_ anchor: LedgeAnchor, size: CGSize) -> CGPoint?`.
- Destination feet sit at platform top + 0.5, inward by half body width + 3.
- Require the complete standing rectangle to fit and have safe top support.

### Sources/Entities.swift: Body and Player

- MODIFY `Body.step(_:_:gravity:)` only to honor the effective `rect` dimensions.
- Preserve `Body.size` as the immutable standing size; do not resize every actor.
- NEW `Player.MoveMode` cases free, hanging, climbing.
- NEW `Player.moveMode`, `ledge: LedgeAnchor?`, `climbT: Double = 0`.
- NEW `Player.grabCooldown: Double = 0`, `isCrouching: Bool = false`.
- NEW `Player.climbStart: CGPoint`, `climbTarget: CGPoint`.
- NEW `Player.runningJump: Bool = false`, `turnT: Double = 0`.
- Override `Player.rect`; crouched height is 0.62 of standing height.
- Keep feet anchored while crouching; exit only when the standing rect fits.
- NEW `func beginHang(_ anchor: LedgeAnchor, in world: World)`.
- NEW `func releaseLedge()` and `func beginClimb(in world: World) -> Bool`.
- NEW `func updateTraversal(_ dt: CGFloat, _ world: World, _ input: Input) -> Bool`.
- Return true when traversal consumed movement; skip normal `step` that frame.
- NEW `func cancelTraversal()` for damage, death, teleports, and depth replacement.
- MODIFY `Player.update(_:_:_:)`; evaluate traversal before wall-run/jump logic.
- Eligible catch: airborne, falling/non-rising, facing into the edge, phase none.
- Require held toward-edge or held up; never auto-catch while retreating.
- Disallow catch during dash, hurtPose, dropThrough, or grabCooldown.
- Test the swept rectangle from immediately before/after physics; snap only if valid.
- Catch precedes wall-slide presentation; ground contact wins over a redundant catch.
- On catch, zero velocity, clear wallDir/coyote/jumpBuffer, phase, block, and dash.
- Hang bottom-center x is corner.x - facing × (half body width + 2).
- Hang y is corner.y - standing body height + 4; sword trail is disabled.
- Hanging has no gravity, attack, block, dash, power, or jump buffering.
- Remain hanging without input; do not require a held grab button.
- Up or jump hit begins climb; down hit releases immediately.
- Holding away for 0.12 seconds also releases; a facing flip alone does not.
- Release sets vel.dy = -80 and grabCooldown = 0.25 seconds.
- Climb duration: 0.42 seconds of gameplay time, not wall time.
- First 65% lifts outside the edge; final 35% moves inward over its top.
- Use two smoothstep segments; no diagonal interpolation through the slab corner.
- Validate swept body clearance at intervals no larger than 4 world units.
- If blocked or support disappears, return to a valid hang or release; never teleport.
- At finish, set exact destination, onGround true, mode free, and velocity zero.
- Clear the anchor and require a fresh jump press after climb completion.
- Revalidate hang support each frame to support future dynamic floors safely.
- Damage may knock a hanging/climbing player off; no hidden traversal invulnerability.
- Pause, dialogue, and hit-stop freeze climb/cloth progression together.

### Careful movement, crouch, and jumps

- Free running remains 300 units/second; ground acceleration remains 3000.
- Air steering acceleration remains 1600; do not change GRAVITY = -2200.
- Careful speed: 90; grounded crouch speed: 55; existing block speed: 90.
- Careful mode probes support 6 units ahead of the leading foot before movement.
- Clamp movement at unsupported edges; jumping deliberately bypasses the edge brake.
- Down alone crouches; down+jump on ledge retains dropThrough = 0.25.
- Do not shrink the body while airborne; force a safe standing shape at takeoff.
- If overhead clearance blocks standing, consume jump without starting an impulse.
- Standing jump impulse remains 760; running jump impulse is 740.
- Running jump requires speed at least 220 and held direction aligned with velocity.
- Preserve up to 330 horizontal speed at launch; do not grant an extra dash.
- Keep coyote 0.10, jumpBuffer 0.12, and current variable-height jump release.
- Attack recovery and climb cannot be cancelled by an incidental up/jump alias.
- Existing wall-run remains the fallback when no valid catch is available.
- NEW `Player.onTraversal: ((TraversalCue) -> Void)?`.
- NEW `enum TraversalCue` cases step, land, grab, climb, draw.
- Emit events only on transitions or planted run contacts, not every animation frame.

### Animation integration

- MODIFY `Player.animate(_:wallRunning:)`; traversal poses override combat poses.
- Hang pose visually places both hands at the ledge; tuck the sword behind the arm.
- Do not add IK: adjust hand reach with bounded shoulder/elbow pose parameters.
- Visual hand-to-corner error target: at most 4 world units in both facings.
- Use `Pose.climb(_:)` with the same progress as physical movement.
- Choose `Pose.jumpRun` only for runningJump; retain `.jump` for standing takeoff.
- Apply crouch/turn/landing before `Rig.apply(_:facing:)`, then secondary motion.
- Feet at climb finish must match the collision top without a one-frame pop.

## 4. Directional, committed combat

### Sources/Entities.swift

- KEEP `Phase` and the windup → active → recovery → none contract.
- NEW `enum AttackKind` cases slash, thrust, overhead.
- NEW `Player.attackKind`, `bufferedKind`, and `recoilLock: Double = 0`.
- KEEP `Player.startAttack()` signature; read the captured bufferedKind internally.
- MODIFY `AttackSpec`; NEW `static let thrust` and `breaksGuard: Bool = false`.
- Preserve `.light1`, `.light2`, and `.heavy` names for existing callers/tests.
- Up+attack selects overhead; down+attack selects thrust; otherwise slash combo.
- Priority when both modifiers held: up wins; attack suppresses crouch/jump that step.
- Capture the modifier on the press, not when the buffered attack finally starts.
- Keep input buffer 0.25 seconds; add the same capture during scene hit-stop.
- Immediate feedback means windup starts on the next simulation step, not instant damage.
- Slash retains light1/light2 timing and their damage/reach values from the digest.
- Thrust: windup 0.09, active 0.07, recovery 0.22 seconds.
- Thrust: lunge 260, reach 78, damage 0.90, knock 180, hitStop 0.045, shake 4.
- Overhead uses heavy timing 0.17/0.10/0.32 and damage 2.4/reach 76.
- Set heavy lunge to 360, knock to 460, hitStop to 0.085, shake to 9.
- Heavy has breaksGuard true; light/thrust false; do not infer it from damage.
- Overhead costs 20 energy at attack start; insufficient energy falls back to light1.
- Slash combo finisher is overhead and uses the same explicit energy rule.
- Direct thrust/overhead reset combo; plain attack retains the three-hit chain.
- Keep the original no-argument `startAttack()` useful in the existing phase test.
- Chain a light only after 0.09 seconds of recovery; heavy recovery is uncancellable.
- Recoil retains 0.38 seconds; set recoilLock so chaining/dash/jump cannot bypass it.
- Reset buffered attacks on damage, traversal entry, death, and modal UI changes.
- Replace per-frame velocity decay with equivalent time-scaled decay at 60 Hz.
- MODIFY `Player.swing`; thrust height 22 at feet+22, slash retains existing box.
- Overhead box height 66; keep its reach consistent with the visible blade arc.
- Preserve one hit per target per `swingId`, including guard-break contact.
- NEW `Pose.thrustWindup`, `Pose.thrustStrike`; use heavy poses for overhead.
- NEW `Being.hitReact(knock:dir:high:)` overload; retain old signature as wrapper.
- High reaction selects `.hurtHigh`; ordinary reaction retains `.hurt`.
- NEW `Being.breakGuard(dir: CGFloat)` clears blockT/phase and sets stun 0.45.
- Do not invoke `parried()` for a guard break; distinguish their counter semantics.
- Keep existing `Being.update(_:_:target:playerPos:threat:r:)` AI and 12 Hz cadence.

### Sources/GameScene.swift

- MODIFY `tickInner(_:)` to capture attack presses even when hitStop suppresses play.
- NEW `Player.captureAttack(_ input: Input)`; call exactly once per input poll.
- Buffer expiry uses gameplay time; modal changes explicitly discard it.
- MODIFY `updateBeings(_:)` guard branch to use `player.spec.breaksGuard`.
- Guard break deals 0.65 of otherwise applicable damage and staggers once.
- Unblocked overhead deals normal damage; ordinary blocked attacks still recoil.
- NEW combat counter `guardBreaks`; do not count a guard break as a parry.
- MODIFY `hurtPlayer(_:from:)` to call `cancelTraversal()` on actual damage.
- MODIFY `castPower()` to reject activation while moveMode is not free.
- A successful block/parry must not detach the player from unrelated ground state.
- Preserve `impact(at:dir:stop:shake:color:blood:heavy:)` as the shared FX entry.
- Clamp zoom punch magnitude to 0.035 and shake to 10 world units.
- Kill hit-stop target 0.10; parry hit-stop 0.085; kill slow-mo 0.25 seconds.
- Apply slow-mo only to gameplay dt; HUD, pause input, and audio playback remain live.
- MODIFY `kill(_:)` to ignore an already-dead Being and award consequences once.
- NEW `Being.deathT: Double = 0` and `updateDeath(_ dt: CGFloat, _ world: World)`.
- Current live-only scene loop skips dead animation; add a separate corpse update pass.
- Corpse motion: collision-aware fall, 0.30-second collapse, then settle into `.dead`.
- Retain removal near 1.9 seconds; cap visible corpses at eight, remove oldest first.
- Never run dead AI, return melee, reapply soul rewards, or bounce corpses indefinitely.

## 5. Spawn staging and bounded HUD

### Sources/GameScene.swift

- MODIFY `spawnBeing(_:at:role:)`; validate support and full body clearance.
- NEW `func safeSpawn(near p: CGPoint, size: CGSize) -> CGPoint?`.
- Search deterministic offsets 0, +64, -64, +128, -128, +192, -192 on safe support.
- Reject spikes, portal clearance, gate rects, and occupied actor rectangles.
- Required separation: body edges plus 16 units; target center spacing at least 64.
- Keep hostile spawns at least 128 units from player start and 96 from the exit.
- If no safe spot exists, skip that spawn; never stack actors as a fallback.
- Register only successfully spawned souls for active encounter bookkeeping.
- Apply the same placement helper to summoned allies; do not assign duplicate soul IDs.
- NEW `func separateBeings(_ dt: CGFloat)` for gentle same-floor crowd separation.
- Affect living actors only; max correction speed 45, collision-check both moves.
- Exclude active attack, hurt, and airborne actors; never push through walls/edges.
- Use nearby actors only; do not introduce an all-world per-frame search.
- MODIFY `setup()`, `layoutHUD()`, and `updateHUD()` for health pip strips.
- NEW `playerPips: [SKSpriteNode]`, `enemyPips: [SKSpriteNode]`.
- NEW `func updatePips(_ nodes: [SKSpriteNode], hp: CGFloat, maxHP: CGFloat)`.
- Use ten fixed pips with partial fill, so unbounded maxHP does not grow the HUD.
- Add numeric current/max HP below the player strip; keep `enBar` and power text.
- Hide `hpBar`/`hpBack` after migration; do not display a duplicate player health bar.
- Pips: 18×24 logical screen units, 4-unit spacing, 24-unit viewport margins.
- Player top-left; focused hostile top-right with name/faction and fractional pips.
- NEW `focusedBeing: Being?`, `focusUntil: Double`.
- NEW `func updateCombatFocus(_ dt: CGFloat)`.
- Prefer last struck/striking living hostile; hold focus 2.0 seconds.
- Otherwise select nearest visible hostile within 320 world units, same floor band.
- Drop focus immediately on death, despawn, dialogue target change, or depth rebuild.
- NEW `func layoutNameplates()`; execute after `updateCamera(_:)`.
- Measure labels in camera/HUD coordinates, including current zoom and shake.
- Clamp every visible nameplate into a 16-unit viewport inset below the HUD.
- Show at most six labels: dialogue target, focus, allies/wanderers, then nearest foes.
- Try three vertical rows spaced 18 screen units; suppress labels that still collide.
- Maintain at least 6 screen units between label bounds; truncate names to 22 glyphs.
- MODIFY `barkAt(_:_:)` to use a bounded camera-space speech area, max two lines.
- Do not let barks compete with nameplate rows or cover health strips.
- Keep `Being.nameTag` and `Being.hpBar`; scene visibility rules override actor defaults.
- Include interaction hints for Shift/careful, down/crouch, grab/climb, and modifiers.
- Controller hints must show the equivalent actions, not keyboard-only instructions.

## 6. Small environmental gameplay set

### Sources/World.swift and Sources/Art.swift

- NEW `struct WorldProp` with `Kind`, `position`, and optional `link: Int`.
- `Kind` cases: pillar, skeleton, healPotion, growthPotion, plate, gate, exitFrame.
- NEW `World.decor: [WorldProp]`; keep `Spawn.Kind` unchanged for existing switches.
- NEW `World.placeDecor(seed: UInt64)` after collision generation and spawn filtering.
- Use a separate deterministic RNG stream so decorations do not perturb room layout.
- Place at most two pillars and one skeleton per visited room.
- Bake pillars/capitals/skeletons into background chunks; no per-frame decoration work.
- Pillars sit behind gameplay with lower contrast and no collision claims.
- NEW `Art.pillar(_ base: SKColor) -> SKTexture` and `Art.exitFrame(_ base: SKColor) -> SKTexture`.
- Reuse `Art.potion(growth:)`; red heals, green has a distinct taller silhouette.
- Place heal potions in optional safe alcoves; cap at three per depth.
- Growth potion: at most one per depth, placement probability 0.20.
- Never consume enemy/shrine positions or block essential jumping routes.
- Exit frame wraps the existing `portalNode`; retain portal choices and progression.

### Sources/GameScene.swift

- NEW `struct PropState` containing descriptor, node, used, and timer.
- NEW `worldProps: [PropState]`; do not overload existing shrine/chest `props` tuples.
- NEW `func buildWorldProps()` and `func updateWorldProps(_ dt: CGFloat)`.
- Red pickup within 24 units heals 25, clamped to maxHP; consume only if HP is missing.
- Green pickup adds 5 to `chron.maxHP` and `player.maxHP`, and heals 5.
- Mark used before effects/save; rebuilding must not retrigger the same live pickup.
- Saving persists the maxHP benefit through existing Chronicle fields.
- Cross-death potion respawning follows existing depth regeneration; no new save schema.
- For plate/gate, use one optional alcove with no essential route behind the gate.
- Plate is a 28×6 trigger; player body overlap opens its linked gate permanently this depth.
- Gate opens over 0.35 seconds with a visible 0.08-second initial response.
- NEW `World.closedGateRects: [Int: CGRect]`; plate link addresses its gate ID.
- Integrate gate rects into `Body.step`, `bodyFits`, and climb sweep checks.
- Keep collision until visually raised clear of actor height; never close on an actor.
- Gate geometry is dynamic sprites, not a baked-tile mutation requiring full rebakes.
- Cap linked pairs at one per depth; if placement is unsafe, omit the pair.
- No mandatory pressure puzzle and no changes to the ten-depth portal route.

## 7. Audio refinement without a synthesis rewrite

### Sources/Synth.swift

- MODIFY `render()` mixing, retaining current procedural voices and tempo mapping.
- Keep `master = 0.55`; reduce sustained bass contribution to 0.85 of baseline.
- Give impact/clang priority; reduce ordinary whoosh level to 0.75 of baseline.
- Kick: retain the existing frequency sweep; add a short 0.012-second noise click.
- Clap/snare: add a 0.09-second filtered noise body, keeping halftime placement.
- NEW `func cue(_ cue: TraversalCue, strength: Float = 1)`.
- Step: 0.045-second noise/tap, gain 0.10; minimum interval 0.12 seconds.
- Land: 0.10-second low thump, gain 0.22; strength follows clamped impact speed.
- Grab/climb: 0.12-second filtered breath/grunt, gain 0.16; no sampled voice.
- Draw: 0.13-second high metallic scrape, gain 0.18; first strike after 1.5 seconds idle.
- NEW `func setSituation(combat: Bool, lowHP: Bool)`; call on state changes only.
- Combat entry adds a 0.18-second tonal/percussive stinger; cooldown 4 seconds.
- Low HP enters below 0.25 and exits above 0.32; avoid threshold chatter.
- Low-HP music low-pass target 1800 Hz with 0.25-second smoothing; SFX remain clear.
- Keep existing sidechain; impact duck target 0.35 with 0.18-second release.
- Reverb uses the existing preallocated buffer; wet target 0.10, feedback capped 0.28.
- Do not increase buffer capacity, add sample assets, or allocate inside `render()`.
- Hoist constant interval/ratio arrays out of the per-sample render path.
- NEW bounded cue mailbox capacity 16; coalesce duplicate footsteps, never grow it.
- Use a short producer lock and audio-side nonblocking try-lock once per buffer.
- If unavailable, render with previous controls; never wait on the audio callback.
- Route existing scene SFX writes through the same control handoff while editing.
- Audio-owned envelopes, intensity smoothing, phases, and buffers stay audio-owned.
- Snapshot control values once per buffer; no SpriteKit access, logging, or RNG sharing.
- NEW `func renderTestFrames(_ count: Int) -> [(Float, Float)]` for offline tests only.
- Offline rendering requires the engine stopped; never advance a live renderer twice.

### Sources/Entities.swift, GameScene.swift, and main.swift

- Wire `Player.onTraversal` once when creating the player in `buildDepth()`.
- Generate footsteps from contact crossings and actual grounded displacement.
- Do not emit footsteps while hanging, paused, dead, blocked against a wall, or airborne.
- Call `setSituation` from encounter/HP state, not every oscillator sample.
- MODIFY `audioTest()` to exercise each cue, stacked impacts, and low-HP transitions.
- Assert finite stereo samples, bounded output, no DC drift, and decaying cue tails.
- Listen with music on: every sword contact must remain distinct from the snare.

## 8. New selftest assertions

- Add named failures rather than replacing old checks with a single aggregate pass.
- Every fixture uses suppressed hardware, clean input edges, and its own scene/RNG.
- Traversal position tolerance: 0.5 world units; timing tolerance: one simulation step.
- Run traversal cases at 60 Hz and 120 Hz; include an uneven-dt catch case.
- Assert hanging catches from both left and right on solid edges and ledge endpoints.
- Assert no catch on an interior ledge seam, spike, ceiling, or out-of-bounds wall.
- Assert no catch while rising, dashing, hurt, dropping through, or moving away.
- Assert swept catch succeeds when a hand crosses the valid height within one step.
- Assert hang holds position for 120 steps with zero velocity and no gravity drift.
- Assert fresh up/jump enters climb, completes at 0.42 seconds, and has safe support.
- Assert all climb sweep samples avoid solids/gates, including the slab corner.
- Assert blocked headroom refuses climb without moving through the ceiling.
- Assert down release and away release set cooldown and cannot instantly regrab.
- Assert removed support or damage releases traversal and restores ordinary physics.
- Assert hit-stop/pause freeze climb progress and discard modal attack buffering.
- Assert careful walking stops before an edge and deliberate jumping still leaves it.
- Assert crouch reduces rect height, preserves foot position, and cannot stand in a roof.
- Assert down+jump retains one-way drop behavior and does not initiate a grab.
- Assert running and standing jumps select different impulses/poses, with bounded speed.
- Assert up+attack does not also jump; down+attack does not shrink the attacking body.
- Assert all attack kinds expose a swing only during `.active`.
- Assert thrust uses its narrow box and both facings produce mirrored reach.
- Assert modifiers are captured at press time, including presses during hit-stop.
- Assert each target receives at most one outcome per swingId.
- Assert low-energy heavy falls back safely and energy never becomes negative.
- Assert ordinary guard causes recoil; recoilLock prevents dash/jump/chain cancellation.
- Assert guard break clears block, increments guardBreaks once, and applies reduced damage.
- Assert parry still staggers the attacker and the unchanged duel harness succeeds.
- Assert corpse animation advances despite exclusion from living AI; reward fires once.
- Assert safeSpawn rejects overlaps/spikes/ceilings and fails safely in a full room.
- Assert health pips handle HP 0, fractional HP, overheal input, and very large maxHP.
- Assert focused HUD target clears on death, despawn, rebuild, and target loss.
- Assert projected visible label rectangles stay inside viewport and do not overlap.
- Assert red/green pickup effects fire once and maxHP matches Chronicle immediately.
- Assert plate opens only its linked gate and the main route works with gate closed.
- Assert a build clears old gates, props, corpses, labels, focus, and traversal anchors.
- Assert identical seeds give identical geometry/decor and deterministic fixture poses.
- Assert test sessions never call production load/save; retain the save schema unchanged.
- Audio: every cue produces nonzero output and every sample is finite within [-1, 1].
- Audio: absolute mean per channel below 0.02 in a fixed 2-second mixed-cue render.
- Audio: isolated cue tail RMS decreases after its attack; no runaway feedback.
- Do not make stochastic combat success depend on an unseeded visual animation clock.

## 9. Snapshot and runtime acceptance

### Reproducible captures

- Capture each fixture with `--mute --fixture <name> --snapshot-frame <n> --snapshot <png>`.
- Use the executable produced by the existing build; do not invent a new binary path.
- Output names: `/tmp/riftborn_v3_overview.png`, `_ledge.png`, `_combat.png`, `_crowd.png`, `_props.png`.
- Capture at 1440×900 window and existing 480-world-unit camera height.
- Also capture crowd at 1024×640 to exercise margins and text suppression.
- Compare matching seed, coordinates, camera, and animation phase, not arbitrary screenshots.
- Overview: clear foreground/background hierarchy, thick slabs, no chunk seams.
- Overview: player scarf/trousers and faction silhouettes readable without zooming in.
- Ledge: visible hand contact, no slab penetration, feet below edge during hang.
- Ledge: additional pull/tuck/stand captures show continuous movement and supported finish.
- Combat: windup, active, recovery silhouettes are visibly different in both directions.
- Combat: blade trail follows the weapon, and thrust/overhead match their collision boxes.
- Combat: heavy impact does not obscure the next enemy tell or push HUD out of frame.
- Crowd: no spawn intersection; no overlapping nameplates, clipping, or duplicate health bars.
- Crowd: enemy health is opposite player health and belongs to the focused living target.
- Props: capitals, potion silhouettes, exit frame, and gate/plate affordances are recognizable.
- Props: decorative pillars cannot be confused with walkable or blocking platforms.
- Reject any visually attractive frame that hides incorrect collision or label layout.

### Runtime and performance gates

- Run `./build.sh`, full `--selftest`, and `--audiotest`; require zero failures.
- Run `--fpslog` at 1440×900 for 60 seconds in normal exploration and dense combat.
- Warm textures first; report loading frames separately rather than hiding them in averages.
- Require sustained display-rate 60 fps and steady-state p95 frame time at most 16.7 ms.
- Require no repeatable animation/HUD-induced frame spikes above 33 ms.
- Use `RIFTBORN_PROFILE=1`; retain `Prof.time(_:_:)` and `Prof.dump()`.
- Add timing labels for traversal, label layout, dynamic props, and chunk baking.
- Across the ten-depth run, target buildDepth p95 at most 150 ms and every build below 180 ms.
- Hard rejection: any depth build reaches 200 ms on the target M1 after warm-up.
- Compare cold launch/build separately; report it honestly rather than silently excluding it.
- Bound caches by palette/variant; no texture key may contain frame/time/actor identity.
- Require no added terrain lights, no per-frame CG drawing, and no per-frame texture generation.
- Exercise repeated depth changes; node/texture growth must plateau rather than accumulate.
- Manual keyboard/controller pass: jump, catch, climb, drop, crouch, modifiers, parry, and menus.
- Listen at low HP and during a crowded fight; reject clipping, clicks, or buried impacts.
- Verify normal save/load and nemesis/mercy consequences after leaving test mode.

## 10. Risks, rollback boundaries, and completion

- Scope: enforce the cut line before adding loose tiles, blade traps, or procedural quests.
- API drift: newly declared types are additions; do not rename established digest symbols.
- Geometry: bottom-center bodies and one-way tops require explicit coordinate tests.
- Tunneling: a point hand probe is insufficient; retain swept catch/climb checks.
- Input: W/up alias, down-drop, and trigger/menu sharing need precedence tests.
- Feel: catch snapping must remain inside reach tolerance, not become magnetic teleporting.
- Combat: lowering hit-stop must not weaken contact; judge against phase captures and audio.
- Rendering: bake changes may expose gutters/alpha fringes; compare seam-centered torches.
- Performance: HUD text churn and shape rebuilding can erase gains from chunk baking.
- Audio: shared controls are concurrency-sensitive; handoff changes need live stress testing.
- Progression: do not encode new transient traversal/prop state into Chronicle.
- Gates: collision overlay must participate in all relevant body/clearance queries.
- Testing: snapshots establish appearance, not traversal correctness or 60 fps.
- Provenance: use only original procedural geometry, sounds, poses, and test layouts.
- If optional features are cut, list them explicitly; do not mark their acceptance as passed.
- Completion report should list changed files, actual command results, captures, and remaining cuts.
- This planning task changes only `docs/PLAN_v3.md`; Sources remain unmodified.
