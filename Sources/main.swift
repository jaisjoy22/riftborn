import AppKit
import SpriteKit

final class GameView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { Input.shared.keys.insert(e.keyCode) }
    override func keyUp(with e: NSEvent) { Input.shared.keys.remove(e.keyCode) }
    override func flagsChanged(with e: NSEvent) {
        // Shift keys arrive only as modifier changes; mirror them into the key set as keycodes 56/60.
        guard e.keyCode == 56 || e.keyCode == 60 else { return }
        if !e.modifierFlags.contains(.shift) { Input.shared.keys.remove(56); Input.shared.keys.remove(60) }
        else if Input.shared.keys.contains(e.keyCode) { Input.shared.keys.remove(e.keyCode) }
        else { Input.shared.keys.insert(e.keyCode) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let synth = Synth()

    func applicationDidFinishLaunching(_ n: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Riftborn"
        window.center()
        let view = GameView(frame: frame)
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        view.showsFPS = CommandLine.arguments.contains("--fps")
        view.showsNodeCount = CommandLine.arguments.contains("--fps")
        if CommandLine.arguments.contains("--fpslog") {
            // Log real rendered frame rate once per second (verifies GPU performance with lighting on)
            var frames = 0, last = CFAbsoluteTimeGetCurrent(), seconds = 0
            let link = Timer.scheduledTimer(withTimeInterval: 1.0 / 240, repeats: true) { _ in }
            _ = link
            NotificationCenter.default.addObserver(forName: NSNotification.Name("RiftbornFrame"), object: nil, queue: nil) { _ in
                frames += 1
                let now = CFAbsoluteTimeGetCurrent()
                if now - last >= 1 { seconds += 1; print("fps \(frames)"); fflush(stdout); frames = 0; last = now }
            }
        }
        let scene = GameScene(size: frame.size)
        scene.synth = synth
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        // v3 fixture mode: build an isolated, deterministic scene and simulate it headlessly before presenting.
        let fixtureArgs = parseFixtureArgs(CommandLine.arguments)
        let wantsSnapshot = CommandLine.arguments.contains("--snapshot")
        if case .fixture(let fx, let frames) = fixtureArgs {
            prepareV3Fixture(scene, fx)
            Input.shared.suppressHardware = true
            resetTestInput(Input.shared)
            advanceTest(scene, frames: frames, acts: [])
            resetTestInput(Input.shared)
            Input.shared.suppressHardware = false
            if wantsSnapshot { scene.simFrozen = true; scene.isPaused = true }
            print("fixture \(fx.rawValue): \(frames) steps, player \(scene.player.pos)"); fflush(stdout)
        }
        view.presentScene(scene)
        if !CommandLine.arguments.contains("--mute") { synth.start() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            // Render the live scene to PNG from inside the app (no screen-recording permission needed)
            let path = CommandLine.arguments[i + 1]
            // Fixture captures are frozen after their simulated steps; only wait for a render pass.
            let delay: Double = scene.simFrozen ? 0.5 : 4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Crop to exactly what the camera shows (scene coords), so HUD + framing match the player's view.
                let cs = scene.camera?.xScale ?? 1, cp = scene.camera?.position ?? .zero
                let vw = scene.size.width * cs, vh = scene.size.height * cs
                let crop = CGRect(x: cp.x - vw / 2, y: cp.y - vh / 2, width: vw, height: vh)
                if let tex = view.texture(from: scene, crop: crop) {
                    let img = tex.cgImage()
                    let rep = NSBitmapImageRep(cgImage: img)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    print("snapshot \(img.width)x\(img.height) -> \(path)")
                } else { print("snapshot failed") }
                fflush(stdout); NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--fullscreen") { window.toggleFullScreen(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { synth.engine.stop() }
}

// MARK: - Headless self-test: runs the real simulation with an autopilot, no window.

func selfTest() -> Int32 {
    let save = NSTemporaryDirectory() + "riftborn-selftest-\(getpid()).json"
    setenv("RIFTBORN_SAVE", save, 1)
    try? FileManager.default.removeItem(atPath: save)
    let scene = GameScene(size: CGSize(width: 1440, height: 900))
    scene.setup()
    var failures: [String] = []
    let inp = Input.shared
    var r = RNG(42)
    let t0 = Date()
    var depthsSeen = Set<Int>()
    var frame = 0
    while frame < 60 * 240 {            // 4 simulated minutes
        frame += 1
        inp.synthetic = []
        let p = scene.player!
        switch scene.mode {
        case .dialogue: inp.synthetic.insert(r.chance(0.5) ? .opt1 : .opt2)
        case .portal: inp.synthetic.insert([.opt1, .opt2, .opt3][r.int(3)])
        case .dead: inp.synthetic.insert(.jump)
        case .paused: inp.synthetic.insert(.pause)
        case .play:
            // Head toward the portal; jump often; fight what's near; talk sometimes.
            let dx = scene.portalNode.position.x - p.pos.x, dy = scene.portalNode.position.y - p.pos.y
            if abs(dx) > 20 { inp.synthetic.insert(dx > 0 ? .right : .left) }
            if frame % 20 < 3 || (dy > 40 && frame % 9 == 0) || p.wallDir != 0 { inp.synthetic.insert(.jump) }
            if dy < -60 && frame % 30 == 0 { inp.synthetic.insert(.down); inp.synthetic.insert(.jump) }
            if frame % 11 == 0 { inp.synthetic.insert(.attack) }
            if frame % 97 == 0 { inp.synthetic.insert(.dash) }
            if frame % 53 == 0 { inp.synthetic.insert(.talk) }
            if frame % 131 == 0 { inp.synthetic.insert(.power) }
            // Unstick: periodically teleport near the portal so the test exercises transitions.
            if frame % (60 * 25) == 0 { p.pos = CGPoint(x: scene.portalNode.position.x - 10, y: scene.portalNode.position.y - 50); p.vel = .zero }
        }
        scene.tick(1.0 / 60)
        depthsSeen.insert(scene.chron.depth)
        if !p.pos.x.isFinite || !p.pos.y.isFinite { failures.append("non-finite player position"); break }
    }
    let secs = Date().timeIntervalSince(t0)
    let c = scene.chron
    if depthsSeen.count < 2 { failures.append("never reached a second depth") }
    if c.souls.isEmpty { failures.append("no souls generated") }
    if c.souls.count > 320 { failures.append("soul table unbounded (\(c.souls.count))") }
    if !FileManager.default.fileExists(atPath: save) { failures.append("chronicle not saved") }
    let reload = Chronicle.load()
    if reload.souls.count != c.souls.count && reload.depth != c.depth { failures.append("save/load mismatch") }

    // Determinism: same seed+depth produce identical worlds.
    let a = World(seed: 99, depth: 3), b = World(seed: 99, depth: 3)
    if a.g != b.g { failures.append("world generation not deterministic") }
    // Reachability sanity: start and portal both open tiles.
    for d in 1...12 {
        let w = World(seed: 7, depth: d)
        if w.at(w.start.x, w.start.y) != .empty || w.at(w.portal.x, w.portal.y) != .empty { failures.append("depth \(d): start/portal blocked") }
    }

    // Combat-feel contract (PoP-derived): windup < recovery for every attack; heavy is slower & harder.
    for s in [AttackSpec.light1, .light2, .heavy] where !(s.windup < s.recovery && s.active > 0) { failures.append("attack timing violates anticipation<recovery") }
    if !(AttackSpec.heavy.damage > AttackSpec.light1.damage * 2 && AttackSpec.heavy.hitStop > AttackSpec.light1.hitStop) { failures.append("heavy not heavier") }
    // Phase machine: pressing attack produces windup -> active (hurtbox) -> recovery -> none.
    do {
        let w = World(seed: 5, depth: 1)
        let pl = Player(pos: CGPoint(x: (CGFloat(w.start.x) + 0.5) * T, y: CGFloat(w.start.y) * T))
        let i2 = Input(); var seen: [Phase] = []; var sawHurtbox = false
        for f in 0..<60 {
            i2.synthetic = f == 2 ? [.attack] : []
            i2.poll(); pl.update(1.0 / 60, w, i2)
            if seen.last != pl.phase { seen.append(pl.phase) }
            if pl.swing != nil { sawHurtbox = true }
        }
        if seen != [.none, .windup, .active, .recovery, .none] { failures.append("attack phases wrong: \(seen)") }
        if !sawHurtbox { failures.append("no hurtbox during active frames") }
    }
    // Stats gathered during the autopilot run
    if scene.combat.hits == 0 { failures.append("player never landed a hit") }

    // Duel harness: a Warden attacks a player holding block; first hit inside the window must PARRY,
    // later hits must be BLOCKED (chip damage), and a parried foe must be stunned.
    do {
        let ds = GameScene(size: CGSize(width: 1440, height: 900)); ds.setup()
        ds.beings.forEach { $0.node.removeFromParent() }; ds.beings.removeAll()
        let p = ds.player!
        var soul = Soul(id: 9999, name: "Test Warden", faction: .wardens, motive: .duty, backstory: "")
        soul.level = 6
        let foe = Being(soul: soul, pos: CGPoint(x: p.pos.x + 46, y: p.pos.y), role: .hostile)
        ds.beings.append(foe); ds.worldNode.addChild(foe.node)
        p.facing = 1
        inp.synthetic = []
        var parried = 0, blocked = 0, stunnedAfterParry = false
        var reacting = false
        for f in 0..<900 {
            // Human-like: hold block normally, but release+re-press when the foe's windup telegraph is about to land.
            if foe.phase == .windup && foe.phaseT < 0.14 && !reacting { reacting = true; inp.synthetic = [] }
            else if reacting { inp.synthetic = [.block]; if foe.phase != .windup { reacting = false } }
            else { inp.synthetic = f % 2 == 0 ? [.block] : [.block] }
            if f % 120 == 0 { foe.pos.x = p.pos.x + 46; foe.vel = .zero; foe.cooldown = 0; foe.stun = 0 }
            let pp = ds.combat.parries, pb = ds.combat.playerBlocks
            ds.tick(1.0 / 60)
            if ds.combat.parries > pp { parried += 1; if foe.stun > 0.5 { stunnedAfterParry = true } }
            if ds.combat.playerBlocks > pb { blocked += 1 }
            p.hp = p.maxHP
        }
        print("  duel harness     : parries \(parried), blocks \(blocked), foe stunned after parry: \(stunnedAfterParry)")
        if parried + blocked == 0 { failures.append("duel: warden never attacked into block") }
        if parried > 0 && !stunnedAfterParry { failures.append("duel: parry did not stun attacker") }
    }

    // v3 deterministic fixtures (isolated scenes; run after the unchanged progression harness).
    runV3Tests(&failures)

    print("""
    RIFTBORN SELFTEST
      simulated frames : \(frame) (\(String(format: "%.0f", Double(frame) / 60))s game time) in \(String(format: "%.2f", secs))s wall -> \(String(format: "%.0f", Double(frame) / secs)) sim fps
      depths visited   : \(depthsSeen.sorted())
      souls created    : \(c.souls.count)  (dead \(c.souls.filter { !$0.alive }.count), with grudge \(c.souls.filter { $0.grudge > 0 }.count), in debt \(c.souls.filter { $0.debt > 0 }.count), kin-avengers \(c.souls.filter { $0.kinOf != nil }.count))
      kills/spared/talks: \(scene.stats.kills)/\(scene.stats.spared)/\(scene.stats.talks)  deaths \(c.deaths)
      combat           : hits \(scene.combat.hits), blocked by foes \(scene.combat.blockedByFoe), player blocks \(scene.combat.playerBlocks), parries \(scene.combat.parries), hitstop frames \(scene.combat.hitStopFrames)
      player           : Lv \(c.level), power \(c.power), shards \(c.shards), powers \(c.powers), \(c.alignment)
      reputation       : \(c.rep)
      mutators chosen  : \(c.choicesAtPortal)
      sample chronicle :
    \(c.log.suffix(6).map { "        " + $0 }.joined(separator: "\n"))
      result           : \(failures.isEmpty ? "PASS" : "FAIL " + failures.joined(separator: "; "))
    """)
    try? FileManager.default.removeItem(atPath: save)
    Prof.dump()
    return failures.isEmpty ? 0 : 1
}

// MARK: - v3 deterministic fixture harness (independent of the progression autopilot above)

enum V3Fixture: String, CaseIterable { case overview, ledge, combat, crowd, props }

let v3FixtureSeed: UInt64 = 0x524946544233

/// Fixture arena bounds in tiles (inclusive interior). Kept well inside the world boundary.
let v3Arena = (x0: 4, y0: 4, x1: 47, y1: 19)

enum FixtureArgs: Equatable { case none, fixture(V3Fixture, Int), error(String) }

/// Parses `--fixture <name>` and `--snapshot-frame <n>`; rejects unknown names and negative frames.
func parseFixtureArgs(_ args: [String]) -> FixtureArgs {
    var fx: V3Fixture?, frames = 120
    if let i = args.firstIndex(of: "--fixture") {
        guard i + 1 < args.count else { return .error("--fixture requires a name (\(V3Fixture.allCases.map { $0.rawValue }.joined(separator: ", ")))") }
        guard let f = V3Fixture(rawValue: args[i + 1]) else { return .error("unknown fixture '\(args[i + 1])' (expected \(V3Fixture.allCases.map { $0.rawValue }.joined(separator: ", ")))") }
        fx = f
    }
    if let i = args.firstIndex(of: "--snapshot-frame") {
        guard i + 1 < args.count, let n = Int(args[i + 1]) else { return .error("--snapshot-frame requires an integer") }
        guard n >= 0 else { return .error("--snapshot-frame must be non-negative (got \(n))") }
        guard fx != nil else { return .error("--snapshot-frame requires --fixture") }
        frames = n
    }
    if let f = fx { return .fixture(f, frames) }
    return .none
}

/// Clears keys/synthetic state and polls twice so neither `now` nor `prev` carries stale edges.
func resetTestInput(_ input: Input) {
    input.keys.removeAll()
    input.synthetic = []
    input.poll(); input.poll()
}

/// Fixed-step advance: one `tick` (and therefore exactly one input poll) per 1/60 s step.
func advanceTest(_ scene: GameScene, frames: Int, acts: Set<Act>) {
    guard frames > 0 else { return }
    for _ in 0..<frames {
        scene.input.synthetic = acts
        scene.tick(1.0 / 60.0)
    }
    scene.input.synthetic = []
}

/// Builds a fresh, isolated fixture scene: in-memory Chronicle, seeded RNGs, carved arena, scripted spawns.
/// Must be called on a scene that has not been set up yet.
func prepareV3Fixture(_ scene: GameScene, _ fixture: V3Fixture) {
    scene.beginTestSession(seed: v3FixtureSeed, depth: 1)
    let a = v3Arena
    scene.fixtureLayout = { w in
        // Fill everything solid, then carve the arena with World.set (which never touches the border).
        for y in 0..<w.h { for x in 0..<w.w { w.set(x, y, .solid) } }
        for y in a.y0...a.y1 { for x in a.x0...a.x1 { w.set(x, y, .empty) } }
        w.spawns = []
        w.start = (x: a.x0 + 4, y: a.y0)
        w.portal = (x: a.x1 - 1, y: a.y0)       // far from every fixture actor: never auto-entered
        switch fixture {
        case .overview:
            for x in 14...19 { w.set(x, a.y0 + 3, .ledge) }
            for x in 24...28 { for y in a.y0...(a.y0 + 2) { w.set(x, y, .solid) } }
            for x in 32...37 { w.set(x, a.y0 + 6, .ledge) }
            w.set(30, a.y0, .spike); w.set(31, a.y0, .spike)
        case .ledge:
            // A 4-tile wall step and a free-standing one-way ledge, both reachable from the start.
            for x in 14...20 { for y in a.y0...(a.y0 + 3) { w.set(x, y, .solid) } }
            for x in 25...30 { w.set(x, a.y0 + 4, .ledge) }
        case .combat:
            w.spawns = [Spawn(kind: .enemy, x: a.x0 + 7, y: a.y0)]
        case .crowd:
            w.spawns = [Spawn(kind: .enemy, x: a.x0 + 7, y: a.y0), Spawn(kind: .enemy, x: a.x0 + 9, y: a.y0),
                        Spawn(kind: .enemy, x: a.x0 + 11, y: a.y0), Spawn(kind: .wanderer, x: a.x0 + 1, y: a.y0),
                        Spawn(kind: .wanderer, x: a.x0 + 14, y: a.y0)]
        case .props:
            w.spawns = [Spawn(kind: .shrine, x: a.x0 + 10, y: a.y0), Spawn(kind: .chest, x: a.x0 + 14, y: a.y0)]
        }
    }
    scene.setup()
}

/// Comparable digest of everything a fixture snapshot depends on.
func fixtureDigest(_ s: GameScene) -> String {
    let p = s.player!
    var out = "p \(p.pos.x),\(p.pos.y) v \(p.vel.dx),\(p.vel.dy) ph \(p.phase) f \(p.facing) hp \(p.hp)"
    for b in s.beings { out += " | \(b.soul.name) \(b.pos.x),\(b.pos.y) \(b.phase) \(b.hp)" }
    out += " | cam \(s.cam.position.x),\(s.cam.position.y) props \(s.props.count) mode \(s.mode)"
    return out
}

func runV3Tests(_ failures: inout [String]) {
    // Production save must never be touched: point the save URL at a sentinel that must stay absent.
    let prevSave = ProcessInfo.processInfo.environment["RIFTBORN_SAVE"]
    let sentinel = NSTemporaryDirectory() + "riftborn-v3-sentinel-\(getpid()).json"
    try? FileManager.default.removeItem(atPath: sentinel)
    setenv("RIFTBORN_SAVE", sentinel, 1)
    defer { if let p = prevSave { setenv("RIFTBORN_SAVE", p, 1) } else { unsetenv("RIFTBORN_SAVE") } }

    let inp = Input.shared
    let wasSuppressed = inp.suppressHardware
    inp.suppressHardware = true
    defer { inp.suppressHardware = wasSuppressed; resetTestInput(inp) }

    // CLI parsing contract
    if parseFixtureArgs(["x"]) != .none { failures.append("v3 cli: no flags must leave behavior unchanged") }
    if parseFixtureArgs(["x", "--fixture", "combat"]) != .fixture(.combat, 120) { failures.append("v3 cli: snapshot-frame default is not 120") }
    if parseFixtureArgs(["x", "--fixture", "ledge", "--snapshot-frame", "7"]) != .fixture(.ledge, 7) { failures.append("v3 cli: snapshot-frame not parsed") }
    if case .error = parseFixtureArgs(["x", "--fixture", "nope"]) {} else { failures.append("v3 cli: unknown fixture accepted") }
    if case .error = parseFixtureArgs(["x", "--fixture", "crowd", "--snapshot-frame", "-1"]) {} else { failures.append("v3 cli: negative frame accepted") }
    if case .error = parseFixtureArgs(["x", "--fixture"]) {} else { failures.append("v3 cli: missing fixture name accepted") }

    // Input edges: reset clears state; a held key is one hit; a release step is required before the next hit.
    do {
        let i2 = Input(); i2.suppressHardware = true
        i2.keys = [38]; i2.synthetic = [.attack]; i2.poll()
        resetTestInput(i2)
        if i2.held(.attack) || i2.hit(.attack) || !i2.keys.isEmpty { failures.append("v3 input: reset left stale state") }
        i2.synthetic = [.attack]; i2.poll()
        let first = i2.hit(.attack)
        i2.poll()
        let held = i2.hit(.attack)
        i2.synthetic = []; i2.poll(); i2.synthetic = [.attack]; i2.poll()
        let again = i2.hit(.attack)
        if !(first && !held && again) { failures.append("v3 input: edge detection wrong (first \(first) held \(held) again \(again))") }
        i2.keys = [38]; i2.synthetic = []; i2.poll()
        if i2.held(.attack) { failures.append("v3 input: suppressed hardware still read keyboard") }
    }

    // Schema guard: Chronicle's Codable layout is unchanged.
    do {
        let expected: Set<String> = ["seed", "depth", "souls", "nextId", "rep", "log", "mercy", "cruelty", "xp", "level", "shards",
                                     "maxHP", "power", "powers", "choicesAtPortal", "mutator", "deaths"]
        if let d = try? JSONEncoder().encode(Chronicle()), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if Set(o.keys) != expected { failures.append("v3 save schema changed: \(Set(o.keys).symmetricDifference(expected).sorted())") }
        } else { failures.append("v3 save schema: encode failed") }
    }

    // Each fixture: fresh scene, isolated chronicle, in-bounds geometry, deterministic after N steps.
    var digests: [String] = []
    for fx in V3Fixture.allCases {
        func run() -> (GameScene, String) {
            let s = GameScene(size: CGSize(width: 1440, height: 900))
            prepareV3Fixture(s, fx)
            resetTestInput(inp)
            advanceTest(s, frames: 120, acts: [])
            return (s, fixtureDigest(s))
        }
        let (s, d1) = run()
        let (s2, d2) = run()
        let tag = "v3 \(fx.rawValue)"
        if !s.isTestSession || s.loadedFromDisk || s.persistCount != 0 { failures.append("\(tag): test session used production load/save") }
        if s.chron.seed != v3FixtureSeed || s.chron.depth != 1 { failures.append("\(tag): fixture seed/depth not honored") }
        if s.world.g != s2.world.g { failures.append("\(tag): geometry not deterministic") }
        if d1 != d2 { failures.append("\(tag): fixture state not deterministic\n      \(d1)\n      \(d2)") }
        let a = v3Arena
        if !(a.x0 > 0 && a.y0 > 0 && a.x1 < s.world.w - 1 && a.y1 < s.world.h - 1) { failures.append("\(tag): arena touches world boundary") }
        if s.world.at(s.world.start.x, s.world.start.y) != .empty { failures.append("\(tag): start tile blocked") }
        let p = s.player!
        if !p.pos.x.isFinite || !p.pos.y.isFinite { failures.append("\(tag): non-finite player") }
        if !p.onGround { failures.append("\(tag): player not settled on ground after 120 steps") }
        let ax0 = CGFloat(a.x0) * T, ax1 = CGFloat(a.x1 + 1) * T
        if p.pos.x < ax0 || p.pos.x > ax1 || p.pos.y < CGFloat(a.y0) * T - 0.5 { failures.append("\(tag): player left arena (\(p.pos))") }
        if s.mode != .play { failures.append("\(tag): idle fixture left play mode (\(s.mode))") }
        let wantBeings: [V3Fixture: Int] = [.combat: 1, .crowd: 5]
        if s.beings.count != (wantBeings[fx] ?? 0) { failures.append("\(tag): expected \(wantBeings[fx] ?? 0) actors, got \(s.beings.count)") }
        if fx == .props && s.props.count != 2 { failures.append("\(tag): expected 2 props, got \(s.props.count)") }
        if fx != .props && !s.props.isEmpty { failures.append("\(tag): stray props") }
        digests.append(d1)
    }
    // Scripted input through the harness is deterministic too (attack press, release, press).
    do {
        func scripted() -> String {
            let s = GameScene(size: CGSize(width: 1440, height: 900))
            prepareV3Fixture(s, .combat); resetTestInput(inp)
            for _ in 0..<3 { advanceTest(s, frames: 1, acts: [.right, .attack]); advanceTest(s, frames: 20, acts: [.right]) }
            advanceTest(s, frames: 60, acts: [])
            return fixtureDigest(s)
        }
        if scripted() != scripted() { failures.append("v3 combat: scripted run not deterministic") }
    }
    if FileManager.default.fileExists(atPath: sentinel) { failures.append("v3: test session wrote a save file"); try? FileManager.default.removeItem(atPath: sentinel) }
    print("  v3 fixtures      : \(V3Fixture.allCases.map { $0.rawValue }.joined(separator: ", ")) (seed 0x\(String(v3FixtureSeed, radix: 16)), deterministic \(digests.count)x2)")
}

func audioTest() -> Int32 {
    let s = Synth()
    s.start()
    print("audio engine running:", s.engine.isRunning, "sampleRate:", s.engine.outputNode.outputFormat(forBus: 0).sampleRate)
    s.targetIntensity = 1
    Thread.sleep(forTimeInterval: 0.5)
    s.engine.stop()
    return s.engine.isRunning ? 1 : 0
}

if CommandLine.arguments.contains("--selftest") { exit(selfTest()) }
if CommandLine.arguments.contains("--audiotest") { exit(audioTest()) }
if case .error(let msg) = parseFixtureArgs(CommandLine.arguments) { fputs("riftborn: \(msg)\n", stderr); exit(2) }
if CommandLine.arguments.contains("--reset") { try? FileManager.default.removeItem(at: Chronicle.url); print("Chronicle erased.") }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
